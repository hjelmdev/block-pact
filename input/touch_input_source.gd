class_name TouchInputSource
extends HeldInputSource
## Fed by the on-screen TouchControls (buttons) or GestureControls (swipes).
## Buttons call [method set_held] / [method tap]; gestures additionally queue
## exact column moves with [method queue_move]. Queued moves are released at
## the same auto-repeat rate (ARR) as a held key, so swiping never moves a
## piece faster than the keyboard can.

var _held: int = 0
var _taps: int = 0
var _moves: int = 0
var _move_cooldown: int = 0
var _piece_uid: int = -1


func set_held(command: int, is_down: bool) -> void:
	if is_down:
		_held |= command
		_taps |= command  # make sure very short presses are not lost
	else:
		_held &= ~command


func tap(command: int) -> void:
	_taps |= command


## Queue `dir` columns of movement (negative = left).
func queue_move(dir: int) -> void:
	_moves = clampi(_moves + dir, -40, 40)


func clear_moves() -> void:
	_moves = 0


func pending_moves() -> int:
	return _moves


func gather(tick: int) -> int:
	var out := super.gather(tick)
	if sim:
		var p := sim.get_player(player_id)
		var uid := p.active.uid if p and p.active else -1
		if uid != _piece_uid:
			# A new piece: moves meant for the previous one are dropped.
			_piece_uid = uid
			_moves = 0
	if _move_cooldown > 0:
		_move_cooldown -= 1
	elif _moves != 0:
		out |= InputCommand.LEFT if _moves < 0 else InputCommand.RIGHT
		_moves -= signi(_moves)
		_move_cooldown = maxi(arr_ticks - 1, 0)
	return out


func _read_held() -> int:
	var bits := _held | _taps
	_taps = 0
	return bits
