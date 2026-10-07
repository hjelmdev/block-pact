class_name PlayerState
extends RefCounted
## Simulation-side state of one player. Pure data.

var id: int = 0
var team: int = 0
var display_name: String = ""
var alive: bool = true

var score: int = 0
var combo: int = 0

# Statistics (results screen / achievements)
var lines_finished: int = 0
var cells_cleared: int = 0
var max_combo: int = 0
var pieces_placed: int = 0
var specials_triggered: int = 0
var best_clear: int = 0

var bag: PieceBag
var queue: Array[PieceShape] = []
var hold_piece: PieceShape
var hold_used: bool = false
var active: ActivePiece

var spawn_column: int = 0
var gravity_counter: int = 0
var lock_counter: int = 0
var lock_resets: int = 0
var spawn_wait: int = 0
var spawn_attempts: int = 0
var hard_drop_pending: bool = false
var soft_drop_counter: int = 0


func next_pieces(count: int) -> Array[PieceShape]:
	var out: Array[PieceShape] = []
	for i in mini(count, queue.size()):
		out.append(queue[i])
	return out
