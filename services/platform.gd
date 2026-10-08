extends Node
## Autoload "Platform": answers "where are we running?" and bridges to the
## browser (JavaScript helpers for mobile-friendly text input, URL hash for
## OAuth redirects, etc.).

signal layout_changed(is_portrait: bool)
## Web: the browser tab was hidden (false) or shown again (true). Browsers
## stop running the game in hidden tabs, so online play has to know.
signal page_visibility_changed(visible: bool)

const WEB_HELPER_JS := "res://platform/web/block_pact_web.js"

var _portrait := false
var page_visible := true
var _visibility_cb: JavaScriptObject


func _ready() -> void:
	if is_web():
		_install_web_helpers()
	get_tree().root.size_changed.connect(_on_size_changed)
	_on_size_changed()


func is_web() -> bool:
	return OS.has_feature("web")


func is_mobile() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios"):
		return true
	if is_web():
		return _js_bool("window.blockPact ? window.blockPact.isMobile() : /Android|iPhone|iPad|iPod/i.test(navigator.userAgent)")
	return false


func is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or is_mobile()


func has_keyboard() -> bool:
	return not is_mobile()


func is_portrait() -> bool:
	return _portrait


## Whether on-screen touch controls should be shown (setting: auto/on/off).
func want_touch_controls() -> bool:
	match String(GameSettings.get_value("controls", "touch_controls", "auto")):
		"on":
			return true
		"off":
			return false
	return is_touch()


func open_url(url: String, same_tab := false) -> void:
	if is_web() and same_tab:
		JavaScriptBridge.eval("window.location.href = %s;" % JSON.stringify(url))
	else:
		OS.shell_open(url)


## Current page URL (web only, "" elsewhere).
func page_url() -> String:
	if not is_web():
		return ""
	var v: Variant = JavaScriptBridge.eval("window.location.origin + window.location.pathname")
	return str(v) if v != null else ""


## Reads and clears the URL fragment (used for OAuth implicit-flow tokens).
func consume_url_hash() -> String:
	if not is_web():
		return ""
	var v: Variant = JavaScriptBridge.eval("""
		(function(){
			var h = window.location.hash || '';
			if (h.length > 1) { history.replaceState(null, '', window.location.pathname + window.location.search); }
			return h.length > 1 ? h.substring(1) : '';
		})()""")
	return str(v) if v != null else ""


func _js_bool(expr: String) -> bool:
	var v: Variant = JavaScriptBridge.eval("!!(%s)" % expr)
	return v == true


func _install_web_helpers() -> void:
	var f := FileAccess.open(WEB_HELPER_JS, FileAccess.READ)
	if f:
		JavaScriptBridge.eval(f.get_as_text(), true)
	# Runs synchronously from the browser event, so a message can still go
	# out before the browser stops the game loop.
	_visibility_cb = JavaScriptBridge.create_callback(func(_args): set_page_visible(not _js_bool("document.hidden")))
	JavaScriptBridge.get_interface("document").addEventListener("visibilitychange", _visibility_cb)


## Also used by tests to simulate a hidden tab.
func set_page_visible(v: bool) -> void:
	if v == page_visible:
		return
	page_visible = v
	page_visibility_changed.emit(v)


func _on_size_changed() -> void:
	var win := get_window()
	var s := Vector2(win.size)
	var portrait := s.y > s.x * 1.05
	# The base canvas is 720x720 ("expand"). On a narrow portrait screen that
	# makes everything tiny, so zoom the UI in until ~480 logical px are visible.
	win.content_scale_factor = clampf(720.0 / 480.0, 1.0, 2.0) if portrait else 1.0
	if portrait != _portrait:
		_portrait = portrait
		layout_changed.emit(_portrait)
