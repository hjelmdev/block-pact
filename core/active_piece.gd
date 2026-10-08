class_name ActivePiece
extends RefCounted
## A falling piece controlled by one player.

var shape: PieceShape
var rotation: int = 0
var position: Vector2i = Vector2i.ZERO
var owner_id: int = -1
var uid: int = 0
## cell index (stable across rotations) -> SpecialBlockType id
var specials: Dictionary = {}
## Explodes (3x3 around every cell) when it locks – the Bomb powerup.
var bomb: bool = false


func _init(p_shape: PieceShape = null, p_owner: int = -1, p_uid: int = 0) -> void:
	shape = p_shape
	owner_id = p_owner
	uid = p_uid


func get_cells() -> Array[Vector2i]:
	return get_cells_at(position, rotation)


func get_cells_at(pos: Vector2i, rot: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in shape.get_cells(rot):
		out.append(c + pos)
	return out


func special_at_index(i: int) -> int:
	return specials.get(i, 0)
