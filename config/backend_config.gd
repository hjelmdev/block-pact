class_name BackendConfig
extends Resource
## Online backend settings (Supabase). Empty = offline/guest-only, and the
## game runs fine without it.
##
## Put real values in res://config/backend_config.local.tres (git-ignored)
## or directly in backend_config.tres. The anon key is a public key – Row
## Level Security in the database is what protects data.

const LOCAL_PATH := "res://config/backend_config.local.tres"
const DEFAULT_PATH := "res://config/backend_config.tres"

@export var supabase_url: String = ""
@export var supabase_anon_key: String = ""
## OAuth providers enabled in Supabase Auth.
@export var oauth_providers: PackedStringArray = PackedStringArray(["google", "discord"])
## Where Supabase sends the browser after login. Empty = the current page.
## Must also be listed under Auth > URL Configuration > Redirect URLs.
@export var web_redirect_url: String = ""
## Port for the desktop/editor login callback (http://localhost:PORT/).
@export var desktop_callback_port: int = 43117

@export_group("Online multiplayer")
## Supabase Realtime is used for lobbies and WebRTC signaling.
@export var realtime_enabled: bool = true
## Override the Realtime websocket URL (e.g. a local test server). Empty =
## derived from supabase_url.
@export var realtime_url_override: String = ""
## Fetch short-lived TURN servers from the Supabase Edge Function
## "turn-credentials" (see supabase/functions/turn-credentials). Harmless
## when the function is not set up.
@export var turn_enabled: bool = true
## STUN/TURN servers for WebRTC. Add a TURN server here for players behind
## strict NATs, e.g. {"urls": ["turn:turn.example.com:3478"], "username": "u", "credential": "p"}.
@export var ice_servers: Array[Dictionary] = [
	{"urls": ["stun:stun.l.google.com:19302", "stun:stun1.l.google.com:19302"]},
]


func is_configured() -> bool:
	return supabase_url.strip_edges() != "" and supabase_anon_key.strip_edges() != ""


func base_url() -> String:
	return supabase_url.strip_edges().trim_suffix("/")


func realtime_url() -> String:
	if realtime_url_override != "":
		return realtime_url_override
	var u := base_url().replace("https://", "wss://").replace("http://", "ws://")
	return "%s/realtime/v1/websocket?apikey=%s&vsn=1.0.0" % [u, supabase_anon_key]


func online_available() -> bool:
	return realtime_enabled and (is_configured() or realtime_url_override != "")


static func load_active() -> BackendConfig:
	var cfg := BackendConfig.new()
	for path in [LOCAL_PATH, DEFAULT_PATH]:
		if ResourceLoader.exists(path):
			var res := load(path)
			if res is BackendConfig:
				cfg = res.duplicate()
				break
	# Command line overrides (tests / local servers):
	#   -- --realtime-url ws://127.0.0.1:4000/socket/websocket
	var args := OS.get_cmdline_user_args()
	var i := args.find("--realtime-url")
	if i >= 0 and i + 1 < args.size():
		cfg.realtime_url_override = args[i + 1]
	i = args.find("--supabase-url")
	if i >= 0 and i + 1 < args.size():
		cfg.supabase_url = args[i + 1]
	if args.has("--no-stun"):
		cfg.ice_servers = []
	# Web: ?realtime=ws://… (testing against a local Realtime server)
	if OS.has_feature("web"):
		var q: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('realtime') || ''")
		if q is String and q != "":
			cfg.realtime_url_override = q
	return cfg
