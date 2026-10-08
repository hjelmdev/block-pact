class_name JoypadInputSource
extends HeldInputSource
## Reads one specific gamepad by device index, so several pads can control
## several local players.

var device: int = 0
var deadzone: float = 0.5


func _init(p_device: int = 0) -> void:
	super()
	device = p_device


func _read_held() -> int:
	var bits := 0
	var ax := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
	var ay := Input.get_joy_axis(device, JOY_AXIS_LEFT_Y)
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_LEFT) or ax < -deadzone:
		bits |= InputCommand.LEFT
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_RIGHT) or ax > deadzone:
		bits |= InputCommand.RIGHT
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_DOWN) or ay > deadzone:
		bits |= InputCommand.SOFT_DROP
	if Input.is_joy_button_pressed(device, JOY_BUTTON_DPAD_UP):
		bits |= InputCommand.HARD_DROP
	if Input.is_joy_button_pressed(device, JOY_BUTTON_A):
		bits |= InputCommand.ROTATE_CW
	if Input.is_joy_button_pressed(device, JOY_BUTTON_B) or Input.is_joy_button_pressed(device, JOY_BUTTON_X):
		bits |= InputCommand.ROTATE_CCW
	if Input.is_joy_button_pressed(device, JOY_BUTTON_LEFT_SHOULDER) or Input.is_joy_button_pressed(device, JOY_BUTTON_RIGHT_SHOULDER):
		bits |= InputCommand.HOLD
	if Input.is_joy_button_pressed(device, JOY_BUTTON_Y):
		bits |= InputCommand.USE_POWER
	return bits
