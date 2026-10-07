class_name BotBrain
extends RefCounted
## Evaluates every reachable placement of a piece and scores it with a
## weighted sum of board features. Pure function of the simulation state.

class Placement:
	extends RefCounted
	var rotation: int
	var x: int
	var y: int
	var value: float
	var use_hold: bool = false

var profile: BotProfile
var _w: PackedFloat32Array
var _occ := PackedByteArray()
var _own := PackedByteArray()
## Cells occupied by other players' falling pieces (obstacles for the path).
var _blk := PackedByteArray()
## Per column: lowest row reached by another player's falling piece (-1 = none).
var _busy_cols := PackedInt32Array()
## A falling piece this many rows above our landing spot counts as contested.
const CONTEST_ROWS := 5
var _lane_half := 3.0
var _base_heights := PackedInt32Array()
var _base_holes := PackedInt32Array()
var _base_holes_total := 0
## Per row (before placement): leader id, leader count, fill count,
## and the highest cell count of any player other than me.
var _row_leader := PackedInt32Array()
var _row_fill := PackedInt32Array()
var _row_other_max := PackedInt32Array()


func _init(p_profile: BotProfile) -> void:
	profile = p_profile
	_w = profile.get_weights()


## Returns placements sorted best-first for the player's active piece.
func evaluate(sim: MatchSimulation, player: PlayerState, shape: PieceShape = null) -> Array[Placement]:
	var out: Array[Placement] = []
	var piece := player.active
	if piece == null:
		return out
	if shape == null:
		shape = piece.shape
	var board := sim.board
	_snapshot(board, player.id)
	_snapshot_actives(sim, player.id)
	_snapshot_columns(board)
	_lane_half = float(board.width) / float(maxi(sim.players.size(), 1)) * 0.5
	var rotations := 4 if shape.can_rotate else 1
	var start := piece.position
	var x_min := maxi(-shape.box_size, start.x - profile.search_radius)
	var x_max := mini(board.width, start.x + profile.search_radius)
	var seen := {}
	var special_idx := -1
	for k: int in piece.specials:
		special_idx = k
	for rot in rotations:
		var rel := shape.get_cells(rot)
		# must be able to rotate in place (ignores kicks – good enough)
		if not _fits_moving(board, rel, start):
			continue
		for x in range(x_min, x_max + 1):
			var pos := Vector2i(x, start.y)
			if not _fits_moving(board, rel, pos):
				continue
			if not _path_clear(board, rel, start, pos):
				continue
			while _fits(board, rel, pos + Vector2i.DOWN):
				pos += Vector2i.DOWN
			var key := _cells_key(rel, pos)
			if seen.has(key):
				continue
			seen[key] = true
			var p := Placement.new()
			p.rotation = rot
			p.x = x
			p.y = pos.y
			p.value = _score_placement(board, rel, pos, player, special_idx)
			out.append(p)
	out.sort_custom(func(a: Placement, b: Placement): return a.value > b.value)
	return out


func _snapshot(board: BoardState, me: int) -> void:
	var n := board.width * board.height
	_occ.resize(n)
	_own.resize(n)
	for i in n:
		var o := board.owners[i]
		_occ[i] = 1 if o != BoardState.EMPTY else 0
		_own[i] = 1 if o == me else 0
	_row_leader.resize(board.height)
	_row_fill.resize(board.height)
	_row_other_max.resize(board.height)
	for y in board.height:
		var counts := {}
		var filled := 0
		for x in board.width:
			var o := board.owners[y * board.width + x]
			if o != BoardState.EMPTY:
				filled += 1
				counts[o] = counts.get(o, 0) + 1
		var leader := -1
		var best := 0
		var other_max := 0
		for o: int in counts:
			if counts[o] > best:
				best = counts[o]
				leader = o
			if o != me:
				other_max = maxi(other_max, counts[o])
		_row_leader[y] = leader
		_row_fill[y] = filled
		_row_other_max[y] = other_max


## Returns Vector2i(height, holes) for column x, skipping rows in `skip`.
func _column_stats(x: int, w: int, h: int, skip: Dictionary) -> Vector2i:
	var col_h := 0
	var holes := 0
	var seen := false
	var skipped_below := 0
	for y in h:
		if not skip.is_empty() and skip.has(y):
			if seen:
				skipped_below += 1
			continue
		var filled := _occ[y * w + x] != 0
		if filled and not seen:
			seen = true
			col_h = h - y
		elif not filled and seen:
			holes += 1
	return Vector2i(maxi(0, col_h - skipped_below), holes)


func _snapshot_columns(board: BoardState) -> void:
	_base_heights.resize(board.width)
	_base_holes.resize(board.width)
	_base_holes_total = 0
	for x in board.width:
		var st := _column_stats(x, board.width, board.height, {})
		_base_heights[x] = st.x
		_base_holes[x] = st.y
		_base_holes_total += st.y


func _snapshot_actives(sim: MatchSimulation, me: int) -> void:
	var b := sim.board
	_blk.resize(b.width * b.height)
	_blk.fill(0)
	_busy_cols.resize(b.width)
	_busy_cols.fill(-1)
	var collide := sim.config.active_piece_collision
	for other in sim.players:
		if other.id == me or other.active == null:
			continue
		for c in other.active.get_cells():
			if collide and b.in_bounds(c.x, c.y):
				_blk[b.idx(c.x, c.y)] = 1
			if c.x >= 0 and c.x < b.width:
				_busy_cols[c.x] = maxi(_busy_cols[c.x], c.y)


func _fits_moving(board: BoardState, rel: Array[Vector2i], pos: Vector2i) -> bool:
	if not _fits(board, rel, pos):
		return false
	for c in rel:
		var x := c.x + pos.x
		var y := c.y + pos.y
		if y >= 0 and _blk[y * board.width + x] != 0:
			return false
	return true


func _fits(board: BoardState, rel: Array[Vector2i], pos: Vector2i) -> bool:
	for c in rel:
		var x := c.x + pos.x
		var y := c.y + pos.y
		if x < 0 or x >= board.width or y >= board.height:
			return false
		if y >= 0 and _occ[y * board.width + x] != 0:
			return false
	return true


func _path_clear(board: BoardState, rel: Array[Vector2i], from: Vector2i, to: Vector2i) -> bool:
	var step := 1 if to.x > from.x else -1
	var x := from.x
	while x != to.x:
		x += step
		if not _fits_moving(board, rel, Vector2i(x, from.y)):
			return false
	return true


func _cells_key(rel: Array[Vector2i], pos: Vector2i) -> int:
	var cells: Array = []
	for c in rel:
		cells.append((c.y + pos.y) * 1000 + c.x + pos.x)
	cells.sort()
	return hash(cells)


func _score_placement(board: BoardState, rel: Array[Vector2i], pos: Vector2i, player: PlayerState, special_idx: int) -> float:
	var w := board.width
	var h := board.height
	var placed: Array[int] = []
	for c in rel:
		var i := (c.y + pos.y) * w + c.x + pos.x
		if i >= 0:
			placed.append(i)
			_occ[i] = 1
			_own[i] = 1

	# Completed rows and ownership inside them
	var lines := 0
	var own_cleared := 0
	var other_cleared := 0
	var special_cleared := 0.0
	var own_row_fill := 0.0
	var row_fill := 0.0
	var steals := 0
	var sabotage := 0
	var rows_touched := {}
	for c in rel:
		rows_touched[c.y + pos.y] = true
	var cleared_rows := {}
	for y: int in rows_touched:
		if y < 0:
			continue
		var filled := 0
		var mine := 0
		for x in w:
			var i := y * w + x
			filled += _occ[i]
			mine += _own[i]
		if filled == w:
			lines += 1
			cleared_rows[y] = true
			own_cleared += mine
			other_cleared += w - mine
			if _row_other_max[y] > mine:
				steals += 1
		else:
			own_row_fill += float(mine) * float(filled) / float(w)
			var r := float(filled) / float(w)
			row_fill += r * r
	if special_idx >= 0 and lines > 0:
		var sc: Vector2i = rel[special_idx] + pos
		if cleared_rows.has(sc.y):
			special_cleared = float(own_cleared) / float(maxi(lines, 1))

	# Sabotage: gaps we cover in rows another player leads.
	if _w[15] != 0.0:
		for c in rel:
			var cx := c.x + pos.x
			var yy := c.y + pos.y + 1
			while yy < h and _occ[yy * w + cx] == 0:
				var leader := _row_leader[yy]
				if leader >= 0 and leader != player.id and _row_fill[yy] * 2 >= w:
					sabotage += 1
				yy += 1

	# Column features. Fast path: only re-scan the columns the piece touched.
	var heights: PackedInt32Array
	var holes := 0
	if lines == 0:
		heights = _base_heights.duplicate()
		holes = _base_holes_total
		var cols := {}
		for c in rel:
			cols[c.x + pos.x] = true
		for x: int in cols:
			var st := _column_stats(x, w, h, {})
			holes += st.y - _base_holes[x]
			heights[x] = st.x
	else:
		heights = PackedInt32Array()
		heights.resize(w)
		for x in w:
			var st := _column_stats(x, w, h, cleared_rows)
			heights[x] = st.x
			holes += st.y
	var agg := 0
	var bump := 0
	var max_h := 0
	var wells := 0
	for x in w:
		agg += heights[x]
		max_h = maxi(max_h, heights[x])
		if x > 0:
			bump += absi(heights[x] - heights[x - 1])
		var left := heights[x - 1] if x > 0 else h
		var right := heights[x + 1] if x < w - 1 else h
		var depth := mini(left, right) - heights[x]
		if depth > 2:
			wells += depth
	var landing := float(h - pos.y)
	var center := 0.0
	for c in rel:
		center += float(c.x + pos.x)
	center /= float(maxi(rel.size(), 1))
	var lane := maxf(0.0, absf(center - float(player.spawn_column)) - _lane_half)
	var contested := 0
	for c in rel:
		var cx := c.x + pos.x
		if cx >= 0 and cx < w and _busy_cols[cx] >= 0 and (c.y + pos.y) - _busy_cols[cx] <= CONTEST_ROWS:
			contested += 1

	for i in placed:
		_occ[i] = 0
		_own[i] = 0

	var v := 0.0
	v += _w[0] * lines * lines
	v += _w[1] * own_cleared
	v += _w[2] * other_cleared
	v += _w[3] * holes
	v += _w[4] * agg
	v += _w[5] * bump
	v += _w[6] * max_h
	v += _w[7] * landing
	v += _w[8] * own_row_fill
	v += _w[9] * special_cleared
	v += _w[10] * lane
	v += _w[11] * wells
	v += _w[12] * contested
	v += _w[13] * row_fill
	v += _w[14] * steals
	v += _w[15] * sabotage
	return v
