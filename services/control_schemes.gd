extends Node
## Autoload "ControlSchemes": registers keyboard input actions for each local
## control scheme at startup (data-driven so rebinding can be added later
## without touching project.godot), and lists the devices a local player can
## pick in the lobby.

const COMMAND_ACTIONS := {
	InputCommand.LEFT: "left",
	InputCommand.RIGHT: "right",
	InputCommand.SOFT_DROP: "soft_drop",
	InputCommand.HARD_DROP: "hard_drop",
	InputCommand.ROTATE_CW: "rotate_cw",
	InputCommand.ROTATE_CCW: "rotate_ccw",
	InputCommand.HOLD: "hold",
	InputCommand.USE_POWER: "use_power",
}

## Physical key positions, so layouts (e.g. Swedish vs US) don't matter.
const KEYBOARD_SCHEMES := {
	&"kb_solo": {
		"name": "Keyboard",
		"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "soft_drop": [KEY_DOWN, KEY_S],
		"hard_drop": [KEY_SPACE], "rotate_cw": [KEY_UP, KEY_X, KEY_W], "rotate_ccw": [KEY_Z, KEY_CTRL, KEY_Q],
		"hold": [KEY_C, KEY_SHIFT, KEY_E], "use_power": [KEY_V, KEY_F, KEY_ENTER],
	},
	&"kb_left": {
		"name": "Keyboard (left: WASD)",
		"left": [KEY_A], "right": [KEY_D], "soft_drop": [KEY_S], "hard_drop": [KEY_W],
		"rotate_cw": [KEY_E], "rotate_ccw": [KEY_Q], "hold": [KEY_SHIFT], "use_power": [KEY_R],
	},
	&"kb_right": {
		"name": "Keyboard (right: arrows)",
		"left": [KEY_LEFT], "right": [KEY_RIGHT], "soft_drop": [KEY_DOWN], "hard_drop": [KEY_UP],
		"rotate_cw": [KEY_PERIOD, KEY_KP_2], "rotate_ccw": [KEY_COMMA, KEY_KP_1], "hold": [KEY_SLASH, KEY_KP_3],
		"use_power": [KEY_ENTER, KEY_KP_0],
	},
}

const PAUSE_ACTION := &"pause"


func _ready() -> void:
	for scheme: StringName in KEYBOARD_SCHEMES:
		var def: Dictionary = KEYBOARD_SCHEMES[scheme]
		for cmd: int in COMMAND_ACTIONS:
			var suffix: String = COMMAND_ACTIONS[cmd]
			var action := StringName("%s_%s" % [scheme, suffix])
			if not InputMap.has_action(action):
				InputMap.add_action(action, 0.2)
			for key: int in def.get(suffix, []):
				var ev := InputEventKey.new()
				ev.physical_keycode = key
				InputMap.action_add_event(action, ev)
	if not InputMap.has_action(PAUSE_ACTION):
		InputMap.add_action(PAUSE_ACTION)
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event(PAUSE_ACTION, esc)
		var p := InputEventKey.new()
		p.physical_keycode = KEY_P
		InputMap.action_add_event(PAUSE_ACTION, p)
		var start := InputEventJoypadButton.new()
		start.button_index = JOY_BUTTON_START
		InputMap.action_add_event(PAUSE_ACTION, start)


## Devices selectable for a local human in the lobby: Array of {id, name}.
func available_devices() -> Array:
	var out := []
	if Platform.has_keyboard():
		for scheme: StringName in KEYBOARD_SCHEMES:
			out.append({"id": scheme, "name": KEYBOARD_SCHEMES[scheme].name})
	if Platform.is_touch():
		out.append({"id": &"touch", "name": "Touch"})
	for d in Input.get_connected_joypads():
		out.append({"id": StringName("joy_%d" % d), "name": "Gamepad %d" % (d + 1)})
	return out


func default_device() -> StringName:
	return &"touch" if Platform.is_touch() and not Platform.has_keyboard() else &"kb_solo"


func device_name(id: StringName) -> String:
	if KEYBOARD_SCHEMES.has(id):
		return KEYBOARD_SCHEMES[id].name
	if id == &"touch":
		return "Touch"
	if String(id).begins_with("joy_"):
		return "Gamepad %d" % (int(String(id).trim_prefix("joy_")) + 1)
	return String(id)


## Builds an InputSource for a local human device id.
func create_source(device: StringName) -> InputSource:
	if KEYBOARD_SCHEMES.has(device):
		return KeyboardInputSource.new(device)
	if String(device).begins_with("joy_"):
		return JoypadInputSource.new(int(String(device).trim_prefix("joy_")))
	if device == &"touch":
		return TouchInputSource.new()
	return KeyboardInputSource.new(&"kb_solo")
