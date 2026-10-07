extends Node
## Autoload "Auth": optional account login via Supabase (Google / Discord
## OAuth). Without a configured backend – or without logging in – the player
## is a guest and everything still works; only progress is not saved.
##
## Web: redirects to Supabase's /authorize endpoint and reads the tokens from
## the URL fragment when the browser comes back (implicit flow).
## Desktop/editor: opens the system browser and catches the redirect on a
## tiny localhost server (see LocalOAuthCatcher).

signal session_changed(logged_in: bool)
signal login_failed(message: String)

const SESSION_PATH := "user://session.cfg"

var config: BackendConfig
var access_token: String = ""
var refresh_token: String = ""
var expires_at: int = 0
var user_id: String = ""
var email: String = ""
var provider: String = ""
var provider_name: String = ""
var avatar_url: String = ""

var _catcher: LocalOAuthCatcher


func _ready() -> void:
	config = BackendConfig.load_active()
	if not config.is_configured():
		return
	_load_session()
	var frag := Platform.consume_url_hash()
	if frag.contains("access_token="):
		await _accept_tokens(frag)
	elif frag.contains("error"):
		login_failed.emit(_parse_query(frag).get("error_description", "Login failed").uri_decode())
	elif refresh_token != "" and Time.get_unix_time_from_system() > expires_at - 60:
		await refresh_session()


func is_available() -> bool:
	return config != null and config.is_configured()


func is_logged_in() -> bool:
	return access_token != "" and user_id != ""


func available_providers() -> PackedStringArray:
	return config.oauth_providers if is_available() else PackedStringArray()


func login_with(oauth_provider: String) -> void:
	if not is_available():
		login_failed.emit(tr("ACCOUNT_NOT_CONFIGURED"))
		return
	var redirect := ""
	if Platform.is_web():
		redirect = config.web_redirect_url if config.web_redirect_url != "" else Platform.page_url()
	else:
		redirect = "http://localhost:%d/" % config.desktop_callback_port
		_start_catcher()
	var url := "%s/auth/v1/authorize?provider=%s&redirect_to=%s" % [config.base_url(), oauth_provider, redirect.uri_encode()]
	Platform.open_url(url, true)


func logout() -> void:
	if is_logged_in():
		rest("POST", "/auth/v1/logout", null)  # fire and forget
	_clear_session()
	session_changed.emit(false)


func refresh_session() -> bool:
	if refresh_token == "":
		return false
	var res := await rest("POST", "/auth/v1/token?grant_type=refresh_token", {"refresh_token": refresh_token}, false)
	if not res.ok:
		_clear_session()
		session_changed.emit(false)
		return false
	_apply_token_response(res.data)
	_save_session()
	session_changed.emit(true)
	return true


## Calls the Supabase REST/Auth API. Returns {ok, code, data}.
func rest(method: String, path: String, body: Variant = null, with_user := true, extra_headers: PackedStringArray = []) -> Dictionary:
	if not is_available():
		return {"ok": false, "code": 0, "data": null}
	if with_user and is_logged_in() and Time.get_unix_time_from_system() > expires_at - 30:
		await refresh_session()
	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + config.supabase_anon_key,
		"Content-Type: application/json",
	])
	headers.append("Authorization: Bearer " + (access_token if with_user and is_logged_in() else config.supabase_anon_key))
	headers.append_array(extra_headers)
	var m := HTTPClient.METHOD_GET
	match method:
		"POST":
			m = HTTPClient.METHOD_POST
		"PATCH":
			m = HTTPClient.METHOD_PATCH
		"DELETE":
			m = HTTPClient.METHOD_DELETE
	var payload := "" if body == null else JSON.stringify(body)
	var err := http.request(config.base_url() + path, headers, m, payload)
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	var data: Variant = JSON.parse_string(text) if text != "" else null
	return {"ok": code >= 200 and code < 300, "code": code, "data": data}


# --------------------------------------------------------------------------

func _accept_tokens(fragment: String) -> void:
	var q := _parse_query(fragment)
	access_token = q.get("access_token", "")
	refresh_token = q.get("refresh_token", "")
	expires_at = int(Time.get_unix_time_from_system()) + int(q.get("expires_in", "3600"))
	var res := await rest("GET", "/auth/v1/user", null)
	if not res.ok or typeof(res.data) != TYPE_DICTIONARY:
		_clear_session()
		login_failed.emit("Could not fetch user")
		return
	_apply_user(res.data)
	_save_session()
	session_changed.emit(true)


func _apply_token_response(d: Dictionary) -> void:
	access_token = d.get("access_token", "")
	refresh_token = d.get("refresh_token", refresh_token)
	expires_at = int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 3600))
	if d.has("user"):
		_apply_user(d.user)


func _apply_user(u: Dictionary) -> void:
	user_id = u.get("id", "")
	email = u.get("email", "")
	var app_meta: Dictionary = u.get("app_metadata", {})
	provider = app_meta.get("provider", "")
	var meta: Dictionary = u.get("user_metadata", {})
	provider_name = meta.get("full_name", meta.get("name", meta.get("user_name", "")))
	avatar_url = meta.get("avatar_url", "")


func _parse_query(s: String) -> Dictionary:
	var out := {}
	for part in s.split("&", false):
		var kv := part.split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


func _save_session() -> void:
	var cfg := ConfigFile.new()
	for k in ["access_token", "refresh_token", "expires_at", "user_id", "email", "provider", "provider_name", "avatar_url"]:
		cfg.set_value("session", k, get(k))
	cfg.save(SESSION_PATH)


func _load_session() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) != OK:
		return
	for k in ["access_token", "refresh_token", "expires_at", "user_id", "email", "provider", "provider_name", "avatar_url"]:
		set(k, cfg.get_value("session", k, get(k)))


func _clear_session() -> void:
	access_token = ""
	refresh_token = ""
	expires_at = 0
	user_id = ""
	email = ""
	provider = ""
	provider_name = ""
	avatar_url = ""
	DirAccess.remove_absolute(SESSION_PATH)


func _start_catcher() -> void:
	if _catcher:
		_catcher.queue_free()
	_catcher = LocalOAuthCatcher.new()
	_catcher.port = config.desktop_callback_port
	_catcher.tokens_received.connect(func(fragment: String):
		_catcher.queue_free()
		_catcher = null
		_accept_tokens(fragment))
	add_child(_catcher)
