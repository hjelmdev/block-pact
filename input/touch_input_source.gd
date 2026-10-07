class_name TouchInputSource
extends HeldInputSource
## Fed by the on-screen TouchControls (and swipe gestures). The controls
## call [method set_held] / [method tap]; this class turns that into
## per-tick commands with the same DAS/ARR as the keyboard.

var _held: int = 0
var _taps: int = 0


func set_held(command: int, is_down: bool) -> void:
	if is_down:
		_held |= command
		_taps |= command  # make sure very short presses are not lost
	else:
		_held &= ~command


func tap(command: int) -> void:
	_taps |= command


func _read_held() -> int:
	var bits := _held | _taps
	_taps = 0
	return bits
