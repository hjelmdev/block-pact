class_name PieceBag
extends RefCounted
## Deterministic "7-bag" randomizer (works for any piece set size).

var _set: PieceSet
var _rng := RandomNumberGenerator.new()
var _bag: Array[PieceShape] = []


func _init(piece_set: PieceSet, seed_value: int) -> void:
	_set = piece_set
	_rng.seed = seed_value


func next() -> PieceShape:
	if _bag.is_empty():
		_refill()
	return _bag.pop_back()


func _refill() -> void:
	_bag = _set.pieces.duplicate()
	# Fisher–Yates with our own seeded RNG (Array.shuffle uses the global RNG).
	for i in range(_bag.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var tmp := _bag[i]
		_bag[i] = _bag[j]
		_bag[j] = tmp
