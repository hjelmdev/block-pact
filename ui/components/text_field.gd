class_name TextField
extends LineEdit
## LineEdit that behaves well everywhere: normal editing on desktop, and on
## mobile browsers a styled HTML overlay input (real virtual keyboard, no
## zoom, no canvas focus issues). Use it for nicknames, lobby codes, etc.

signal value_committed(value: String)

## Title shown in the mobile overlay (defaults to the placeholder text).
@export var prompt_title: String = ""

var _js_callback: JavaScriptObject
var _overlay_open := false


func _ready() -> void:
	virtual_keyboard_enabled = true
	custom_minimum_size.y = maxf(custom_minimum_size.y, 44.0)
	text_submitted.connect(func(t): value_committed.emit(t))
	focus_exited.connect(func(): value_committed.emit(text))
	focus_entered.connect(_on_focus_entered)


func _use_overlay() -> bool:
	return Platform.is_web() and Platform.is_mobile()


func _on_focus_entered() -> void:
	if not _use_overlay() or _overlay_open:
		return
	release_focus()
	_overlay_open = true
	var window := JavaScriptBridge.get_interface("window")
	if window == null or window.blockPact == null:
		_overlay_open = false
		return
	_js_callback = JavaScriptBridge.create_callback(_on_overlay_result)
	var title := prompt_title if prompt_title != "" else tr(placeholder_text)
	window.blockPact.promptText(title, text, max_length, _js_callback)


func _on_overlay_result(args: Array) -> void:
	_overlay_open = false
	if args.is_empty() or args[0] == null:
		return
	text = str(args[0])
	if max_length > 0:
		text = text.left(max_length)
	text_changed.emit(text)
	value_committed.emit(text)
