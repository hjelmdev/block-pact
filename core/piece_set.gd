class_name PieceSet
extends Resource
## A collection of piece shapes a game mode draws from (e.g. the standard 7).

@export var set_id: StringName = &"standard"
@export var pieces: Array[PieceShape] = []


func get_by_id(piece_id: StringName) -> PieceShape:
	for p in pieces:
		if p.id == piece_id:
			return p
	return null


func index_of(shape: PieceShape) -> int:
	return pieces.find(shape)
