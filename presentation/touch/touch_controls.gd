class_name TouchControls
extends Control
## On-screen controls for phones/tablets with true multi-touch (hold left
## while tapping rotate). Feeds a TouchInputSource; knows nothing about the
## simulation.

signal pause_requested()

var source: TouchInputSource
var _touch_to_button: Dictionary = {}  # touch index -> TouchButton
var _buttons: Array[TouchButton] = []


func _ready() -> void:
	add_to_group(&"match_presenter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for b in find_children("*", "TouchButton", true, false):
		_buttons.append(b)


func bind_match(sim: MatchSimulation, _setup: MatchSetup, controller: Node) -> void:
	source = controller.get_touch_source()
	visible = source != null and Platform.want_touch_controls() and not GestureControls.scheme_active()
	var power := get_node_or_null(^"%Power") as Control
	if power:
		power.visible = sim.powerups_enabled()
		(power.get_parent() as GridContainer).columns = 3 if power.visible else 2


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or source == null:
		return
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			var b := _button_at(st.position)
			if b:
				_press(st.index, b)
				get_viewport().set_input_as_handled()
		else:
			if _touch_to_button.has(st.index):
				_release(st.index)
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _touch_to_button.has(sd.index):
			var b := _button_at(sd.position)
			# Sliding a finger between move buttons switches direction.
			if b and b != _touch_to_button[sd.index] and _is_slidable(b) and _is_slidable(_touch_to_button[sd.index]):
				_release(sd.index)
				_press(sd.index, b)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not Platform.is_touch():
		# Desktop testing with touch controls forced on.
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			var b := _button_at(mb.position)
			if b:
				_press(-1, b)
				get_viewport().set_input_as_handled()
		elif _touch_to_button.has(-1):
			_release(-1)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_VISIBILITY_CHANGED:
		for idx in _touch_to_button.keys():
			_release(idx)


func _press(index: int, b: TouchButton) -> void:
	_touch_to_button[index] = b
	b.pressed = true
	if b.command == 0:
		pause_requested.emit()
		return
	source.set_held(b.command, true)
	if b.command in [InputCommand.ROTATE_CW, InputCommand.ROTATE_CCW, InputCommand.HARD_DROP, InputCommand.USE_POWER]:
		Input.vibrate_handheld(15)


func _release(index: int) -> void:
	var b: TouchButton = _touch_to_button.get(index)
	_touch_to_button.erase(index)
	if b == null:
		return
	if not _touch_to_button.values().has(b):
		b.pressed = false
		if b.command != 0 and source:
			source.set_held(b.command, false)


func _button_at(pos: Vector2) -> TouchButton:
	for b in _buttons:
		if b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return b
	return null


func _is_slidable(b: TouchButton) -> bool:
	return b.command in [InputCommand.LEFT, InputCommand.RIGHT, InputCommand.SOFT_DROP]
