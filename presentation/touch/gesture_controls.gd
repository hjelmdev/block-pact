class_name GestureControls
extends Control
## Swipe controls for phones and tablets (no on-screen d-pad):
##   drag sideways   – the piece follows your finger, one column per cell
##   drag down       – soft drop while the finger stays down
##   flick up        – hard drop
##   tap             – rotate clockwise
##   two-finger tap  – rotate counter-clockwise
##   long press      – hold
## plus a small round button for powerups. Feeds the same TouchInputSource
## as the button controls, so the simulation can't tell the difference.

## Fraction of a board cell the finger must travel per column.
@export var sensitivity: float = 0.9
@export var long_press_sec: float = 0.42
@export var tap_max_sec: float = 0.28

var board_view: BoardView
var source: TouchInputSource
## Screen rects where touches must not become gestures (buttons, HUD).
var exclude_rects: Array[Callable] = []

var _touches: Dictionary = {}  # index -> state Dictionary
var _max_fingers := 0
var _any_moved := false
var _gesture_used := false  # long press / flick already consumed this gesture
var _power_button: Button
var _hint: Label
var _active := false


func _ready() -> void:
	add_to_group(&"match_presenter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_power_button = Button.new()
	_power_button.icon = Assets.icon(&"power")
	_power_button.expand_icon = true
	_power_button.custom_minimum_size = Vector2(64, 64)
	_power_button.focus_mode = Control.FOCUS_NONE
	_power_button.anchor_left = 1.0
	_power_button.anchor_right = 1.0
	_power_button.anchor_top = 1.0
	_power_button.anchor_bottom = 1.0
	_power_button.offset_left = -80
	_power_button.offset_top = -84
	_power_button.offset_right = -16
	_power_button.offset_bottom = -20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.85, 0.3, 0.16)
	sb.border_color = Color(1, 0.85, 0.3, 0.45)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(32)
	for st in [&"normal", &"hover", &"focus"]:
		_power_button.add_theme_stylebox_override(st, sb)
	var sbp := sb.duplicate()
	sbp.bg_color = Color(1, 0.85, 0.3, 0.4)
	_power_button.add_theme_stylebox_override(&"pressed", sbp)
	_power_button.button_down.connect(func():
		if source:
			source.tap(InputCommand.USE_POWER)
			Input.vibrate_handheld(20))
	_power_button.hide()
	add_child(_power_button)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.add_theme_font_size_override(&"font_size", 15)
	_hint.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
	_hint.add_theme_constant_override(&"outline_size", 6)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -170
	_hint.offset_right = 170
	_hint.offset_top = -190
	_hint.offset_bottom = -100
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.hide()
	add_child(_hint)


static func scheme_active() -> bool:
	return Platform.want_touch_controls() and String(GameSettings.get_value("controls", "touch_scheme", "gestures")) == "gestures"


func bind_match(sim: MatchSimulation, _setup: MatchSetup, controller: Node) -> void:
	source = controller.get_touch_source()
	sensitivity = float(GameSettings.get_value("controls", "swipe_sensitivity", sensitivity))
	_active = source != null and scheme_active()
	visible = _active
	_power_button.visible = _active and sim.powerups_enabled()
	if _active:
		_show_hint()


func _show_hint() -> void:
	var shown: int = GameSettings.get_value("controls", "gesture_hint_shown", 0)
	if shown >= 3:
		return
	GameSettings.set_value("controls", "gesture_hint_shown", shown + 1)
	_hint.text = tr("GESTURE_HINT")
	_hint.show()
	_hint.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(5.0)
	t.tween_property(_hint, "modulate:a", 0.0, 0.8)
	t.tween_callback(_hint.hide)


func _cell_px() -> float:
	var c := board_view.cell_size if board_view else 24.0
	# Scale from board-local to screen pixels.
	if board_view:
		c *= board_view.get_global_transform_with_canvas().get_scale().x
	return maxf(c * sensitivity, 10.0)


func _excluded(pos: Vector2) -> bool:
	if _power_button.visible and _power_button.get_global_rect().grow(8).has_point(pos):
		return true
	for f in exclude_rects:
		var r: Rect2 = f.call()
		if r.has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _active or source == null or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_on_down(st.index, st.position)
		else:
			_on_up(st.index, st.position)
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_on_drag(sd.index, sd.position, sd.relative, sd.velocity)
	elif event.device == InputEvent.DEVICE_ID_EMULATION:
		return  # mouse events emulated from touch – already handled above
	elif event is InputEventMouseButton and not Platform.is_touch():
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_down(-1, mb.position)
			else:
				_on_up(-1, mb.position)
	elif event is InputEventMouseMotion and not Platform.is_touch() and _touches.has(-1):
		var mm := event as InputEventMouseMotion
		_on_drag(-1, mm.position, mm.relative, mm.velocity)


func _on_down(index: int, pos: Vector2) -> void:
	if _excluded(pos):
		return
	if _touches.is_empty():
		_max_fingers = 0
		_any_moved = false
		_gesture_used = false
	_touches[index] = {"start": pos, "time": 0.0, "acc_x": 0.0, "moved": false, "soft": false,
			"vel": Vector2.ZERO, "last_us": Time.get_ticks_usec()}
	_max_fingers = maxi(_max_fingers, _touches.size())


func _on_drag(index: int, pos: Vector2, rel: Vector2, vel: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	var cell := _cell_px()
	var total: Vector2 = pos - t.start
	# Our own velocity estimate: some platforms (web) report none.
	var now := Time.get_ticks_usec()
	var dt := maxf(float(now - t.last_us) / 1000000.0, 1.0 / 240.0)
	t.last_us = now
	t.vel = (t.vel as Vector2).lerp(rel / dt, 0.6)
	if vel == Vector2.ZERO or absf(t.vel.y) > absf(vel.y):
		vel = t.vel
	if not t.moved and total.length() > cell * 0.45:
		t.moved = true
		_any_moved = true
	if _touches.size() > 1:
		return  # multi-finger gestures don't move pieces
	# Flick up = hard drop (once per gesture).
	if not _gesture_used and vel.y < -cell * 28.0 and total.y < -cell * 1.2 and absf(total.y) > absf(total.x):
		_gesture_used = true
		source.clear_moves()
		source.tap(InputCommand.HARD_DROP)
		Input.vibrate_handheld(15)
		_release_soft(t)
		return
	# Horizontal: one column per cell of finger travel.
	if not t.soft:
		t.acc_x += rel.x
		while absf(t.acc_x) >= cell:
			var dir := signi(int(signf(t.acc_x)))
			source.queue_move(dir)
			t.acc_x -= dir * cell
	# Downward drag = soft drop while the finger stays below the start.
	var down := total.y > cell * 1.0 and total.y > absf(total.x) * 0.8
	if down and not t.soft:
		t.soft = true
		source.set_held(InputCommand.SOFT_DROP, true)
	elif t.soft and total.y < cell * 0.5:
		_release_soft(t)


func _on_up(index: int, _pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var t: Dictionary = _touches[index]
	_release_soft(t)
	_touches.erase(index)
	if not _touches.is_empty():
		return
	# Gesture finished: a quick, still tap rotates.
	if not _any_moved and not _gesture_used and t.time <= tap_max_sec:
		source.tap(InputCommand.ROTATE_CCW if _max_fingers >= 2 else InputCommand.ROTATE_CW)
		Input.vibrate_handheld(10)


func _release_soft(t: Dictionary) -> void:
	if t.soft:
		t.soft = false
		source.set_held(InputCommand.SOFT_DROP, false)


func _process(delta: float) -> void:
	if _touches.is_empty():
		return
	for k in _touches:
		_touches[k].time += delta
	if _touches.size() == 1 and not _any_moved and not _gesture_used:
		var t: Dictionary = _touches.values()[0]
		if t.time >= long_press_sec:
			_gesture_used = true
			source.tap(InputCommand.HOLD)
			Input.vibrate_handheld(25)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and source:
		for t: Dictionary in _touches.values():
			_release_soft(t)
		_touches.clear()
