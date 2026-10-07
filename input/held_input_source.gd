class_name HeldInputSource
extends InputSource
## Base for human inputs that report "which buttons are held right now".
## Converts held state into per-tick commands with DAS/ARR auto-repeat, so
## keyboard, touch and gamepad all feel identical.

## Delayed Auto Shift: ticks a direction is held before it starts repeating.
var das_ticks: int = 10
## Auto Repeat Rate: ticks between repeats once DAS has kicked in.
var arr_ticks: int = 2

var _prev: int = 0
var _dir: int = 0
var _dir_timer: int = 0

const _ONE_SHOT := [InputCommand.HARD_DROP, InputCommand.ROTATE_CW, InputCommand.ROTATE_CCW, InputCommand.HOLD]


func _init() -> void:
	das_ticks = GameSettings.get_value("controls", "das_ticks", das_ticks)
	arr_ticks = maxi(1, GameSettings.get_value("controls", "arr_ticks", arr_ticks))


## Override: return the InputCommand bits that are currently held down.
func _read_held() -> int:
	return 0


func is_local_human() -> bool:
	return true


func gather(_tick: int) -> int:
	var held := _read_held()
	var pressed := held & ~_prev
	var out := 0
	for f: int in _ONE_SHOT:
		if pressed & f:
			out |= f
	if held & InputCommand.SOFT_DROP:
		out |= InputCommand.SOFT_DROP

	var left := held & InputCommand.LEFT != 0
	var right := held & InputCommand.RIGHT != 0
	if pressed & InputCommand.LEFT:
		_dir = -1
		_dir_timer = 0
		out |= InputCommand.LEFT
	elif pressed & InputCommand.RIGHT:
		_dir = 1
		_dir_timer = 0
		out |= InputCommand.RIGHT
	else:
		if (_dir == -1 and not left) or (_dir == 1 and not right):
			_dir = -1 if left else (1 if right else 0)
			_dir_timer = 0
		if _dir != 0:
			_dir_timer += 1
			if _dir_timer >= das_ticks and (_dir_timer - das_ticks) % arr_ticks == 0:
				out |= InputCommand.LEFT if _dir < 0 else InputCommand.RIGHT
	_prev = held
	return out
