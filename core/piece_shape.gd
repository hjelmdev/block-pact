class_name PieceShape
extends Resource
## Data definition of one piece type (tetromino or any other polyomino).
##
## Cells are given for rotation state 0 inside a square bounding box of
## [member box_size]. Rotations are derived automatically (clockwise, y down)
## so cell indices are stable across rotations – this lets special cells
## (e.g. x5) follow the piece when it rotates.

@export var id: StringName = &""
@export var display_name: String = ""
## Cells in rotation state 0, relative to the top-left of the bounding box.
@export var cells: Array[Vector2i] = []
@export var box_size: int = 3
## Which kick table in [SrsKicks] to use: &"jlstz", &"i" or &"none".
@export var kick_table: StringName = &"jlstz"
## If false the piece never rotates (e.g. O-piece).
@export var can_rotate: bool = true

var _rotation_cache: Array = []


func get_cells(rotation: int) -> Array[Vector2i]:
	if _rotation_cache.is_empty():
		_build_cache()
	return _rotation_cache[posmod(rotation, 4)]


func get_cell_count() -> int:
	return cells.size()


func _build_cache() -> void:
	_rotation_cache.clear()
	var current: Array[Vector2i] = cells.duplicate()
	for r in 4:
		_rotation_cache.append(current.duplicate())
		var next: Array[Vector2i] = []
		for c in current:
			# Clockwise rotation in a box with y pointing down.
			next.append(Vector2i(box_size - 1 - c.y, c.x))
		current = next
