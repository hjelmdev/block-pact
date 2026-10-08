class_name BoardState
extends RefCounted
## Pure data model of the shared grid. No rendering, no nodes.
##
## Each cell stores ownership separately from any visual color:
##   owner   – player id that placed it (EMPTY when free)
##   special – SpecialBlockType id (0 = none)
##   piece   – unique id of the piece the cell came from
## Row 0 is the top. The first [member hidden_rows] rows are the spawn buffer
## and are not shown.

const EMPTY := -1

var width: int
var height: int
var hidden_rows: int
var owners: PackedInt32Array
var specials: PackedInt32Array
var piece_ids: PackedInt32Array


func _init(p_width: int = 10, p_height: int = 22, p_hidden_rows: int = 2) -> void:
	width = p_width
	height = p_height
	hidden_rows = p_hidden_rows
	owners = PackedInt32Array()
	owners.resize(width * height)
	owners.fill(EMPTY)
	specials = PackedInt32Array()
	specials.resize(width * height)
	specials.fill(0)
	piece_ids = PackedInt32Array()
	piece_ids.resize(width * height)
	piece_ids.fill(0)


func visible_height() -> int:
	return height - hidden_rows


func idx(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < width and y >= 0 and y < height


## Walls and floor count as occupied; space above the top is free.
func is_blocked(x: int, y: int) -> bool:
	if x < 0 or x >= width or y >= height:
		return true
	if y < 0:
		return false
	return owners[idx(x, y)] != EMPTY


func is_occupied(x: int, y: int) -> bool:
	if not in_bounds(x, y):
		return false
	return owners[idx(x, y)] != EMPTY


func get_owner(x: int, y: int) -> int:
	return owners[idx(x, y)] if in_bounds(x, y) else EMPTY


func get_special(x: int, y: int) -> int:
	return specials[idx(x, y)] if in_bounds(x, y) else 0


func set_cell(x: int, y: int, owner: int, special: int = 0, piece_uid: int = 0) -> void:
	if not in_bounds(x, y):
		return
	var i := idx(x, y)
	owners[i] = owner
	specials[i] = special
	piece_ids[i] = piece_uid


func clear_cell(x: int, y: int) -> void:
	set_cell(x, y, EMPTY, 0, 0)


func set_owner(x: int, y: int, owner: int) -> void:
	if in_bounds(x, y):
		owners[idx(x, y)] = owner


## Moves a cell (owner, special, piece id) and leaves the source empty.
func move_cell(from: Vector2i, to: Vector2i) -> void:
	var a := idx(from.x, from.y)
	var b := idx(to.x, to.y)
	owners[b] = owners[a]
	specials[b] = specials[a]
	piece_ids[b] = piece_ids[a]
	clear_cell(from.x, from.y)


func cells_fit(cells: Array[Vector2i]) -> bool:
	for c in cells:
		if is_blocked(c.x, c.y):
			return false
	return true


func is_row_full(y: int) -> bool:
	var base := y * width
	for x in width:
		if owners[base + x] == EMPTY:
			return false
	return true


func find_full_rows() -> PackedInt32Array:
	var rows := PackedInt32Array()
	for y in height:
		if is_row_full(y):
			rows.append(y)
	return rows


## Removes the given rows and collapses everything above them downward.
func remove_rows(rows: PackedInt32Array) -> void:
	if rows.is_empty():
		return
	var remove := {}
	for r in rows:
		remove[r] = true
	var write_y := height - 1
	for read_y in range(height - 1, -1, -1):
		if remove.has(read_y):
			continue
		if write_y != read_y:
			_copy_row(read_y, write_y)
		write_y -= 1
	while write_y >= 0:
		_clear_row(write_y)
		write_y -= 1


func column_height(x: int) -> int:
	for y in height:
		if owners[idx(x, y)] != EMPTY:
			return height - y
	return 0


func copy() -> BoardState:
	var b := BoardState.new(width, height, hidden_rows)
	b.owners = owners.duplicate()
	b.specials = specials.duplicate()
	b.piece_ids = piece_ids.duplicate()
	return b


func _copy_row(from_y: int, to_y: int) -> void:
	for x in width:
		var a := idx(x, from_y)
		var b := idx(x, to_y)
		owners[b] = owners[a]
		specials[b] = specials[a]
		piece_ids[b] = piece_ids[a]


func _clear_row(y: int) -> void:
	for x in width:
		clear_cell(x, y)
