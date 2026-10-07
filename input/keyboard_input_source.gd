class_name KeyboardInputSource
extends HeldInputSource
## Reads a keyboard control scheme registered by the ControlSchemes autoload
## (actions named "<scheme>_left", "<scheme>_rotate_cw" …).

var scheme: StringName
var _actions: Dictionary = {}


func _init(p_scheme: StringName = &"kb_solo") -> void:
	super()
	scheme = p_scheme
	for cmd: int in ControlSchemes.COMMAND_ACTIONS:
		_actions[cmd] = StringName("%s_%s" % [scheme, ControlSchemes.COMMAND_ACTIONS[cmd]])


func _read_held() -> int:
	var bits := 0
	for cmd: int in _actions:
		var action: StringName = _actions[cmd]
		if not InputMap.has_action(action):
			continue
		if Input.is_action_pressed(action) or Input.is_action_just_pressed(action):
			bits |= cmd
	return bits
