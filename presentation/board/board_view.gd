class_name BoardView
extends Control
## Renders a MatchSimulation's board. Read-only: never changes the simulation.
##
## Layers (child nodes, see board_view.tscn) so each can have its own material:
##   Cells   – locked + active cells, tinted by BlockSkin.cell_material
##   Overlay – ghosts, colorblind patterns, special glyphs, flashes
##   Glow    – additive soft glow
## All visuals come from the BlockSkin / PlayerPalette resources.

signal geometry_changed()

@export var skin: BlockSkin
@export var palette: PlayerPalette
## Extra empty space around the board, in cells.
@export var padding_cells: float = 0.75
## 0 = top, 0.5 = centered, 1 = bottom (portrait layouts hug the controls).
@export_range(0.0, 1.0) var vertical_align: float = 0.5:
	set(v):
		vertical_align = v
		_recalc_geometry()

var sim: MatchSimulation
var setup: MatchSetup
## Player ids whose ghost piece is shown (local humans by default).
var ghost_players: Array[int] = []
var show_patterns: bool = false
var show_ghost: bool = true

var cell_size: float = 16.0
var board_origin: Vector2 = Vector2.ZERO
var shake_offset: Vector2 = Vector2.ZERO

var _flashes: Dictionary = {}  # Vector2i -> time left (sec)
## Board effects being animated: {kind, cells, color, t, dur, origin}
var _bursts: Array = []
var _shake_strength: float = 0.0
var _time: float = 0.0
## Hard-drop streaks: {cells, rows, color, t, dur}
var _trails: Array = []
## Landing dust: {pos (px, board-local), vel, t, dur, color}
var _dust: Array = []
## 0..1, how close the stack is to the top (smoothed).
var _danger: float = 0.0
var show_piece_tags: bool = true

@onready var _cells_layer: BoardLayer = $Cells
@onready var _overlay_layer: BoardLayer = $Overlay
@onready var _glow_layer: BoardLayer = $Glow
@onready var _meters_layer: BoardLayer = $Meters


func _ready() -> void:
	add_to_group(&"match_presenter")
	if skin == null:
		skin = Assets.skin()
	if palette == null:
		palette = Assets.palette()
	_apply_skin()
	resized.connect(_recalc_geometry)
	show_patterns = GameSettings.get_value("video", "color_patterns", false)
	show_ghost = GameSettings.get_value("video", "show_ghost", true)
	show_piece_tags = GameSettings.get_value("video", "piece_tags", true)
	GameSettings.setting_changed.connect(_on_setting_changed)


func bind_match(p_sim: MatchSimulation, p_setup: MatchSetup, _controller: Node) -> void:
	sim = p_sim
	setup = p_setup
	sim.board_changed.connect(_redraw_all)
	sim.piece_moved.connect(_on_piece_changed)
	sim.piece_rotated.connect(func(_p, _k): _on_piece_changed(_p))
	sim.piece_spawned.connect(_on_piece_changed)
	sim.piece_held.connect(_on_piece_changed)
	sim.piece_locked.connect(_on_piece_locked)
	sim.piece_hard_dropped.connect(_on_hard_drop)
	sim.lines_cleared.connect(_on_lines_cleared)
	sim.board_effect.connect(_on_board_effect)
	_recalc_geometry()
	_redraw_all()


func set_skin(new_skin: BlockSkin) -> void:
	skin = new_skin
	_apply_skin()
	_redraw_all()


# --------------------------------------------------------------------------
# Geometry helpers (also used by effects)

func board_pixel_size() -> Vector2:
	if sim == null:
		return Vector2.ZERO
	return Vector2(sim.board.width, sim.board.visible_height()) * cell_size


## Local rect of a cell given in board coordinates (row 0 = top hidden row).
func cell_rect(x: int, y: int) -> Rect2:
	var vy := y - sim.board.hidden_rows
	return Rect2(board_origin + shake_offset + Vector2(x, vy) * cell_size, Vector2(cell_size, cell_size))


func cell_center_global(x: int, y: int) -> Vector2:
	return get_global_transform() * cell_rect(x, y).get_center()


func player_color(player_id: int) -> Color:
	return appearance(player_id).color


func appearance(player_id: int) -> PlayerAppearance:
	var idx := player_id
	if setup and player_id >= 0 and player_id < setup.slots.size():
		idx = setup.slots[player_id].color_index
	return palette.get_appearance(idx)


func shake(strength: float) -> void:
	if GameSettings.get_value("video", "screen_shake", true):
		_shake_strength = maxf(_shake_strength, strength)


func flash_cells(cells: Array[Vector2i], duration := 0.18) -> void:
	for c in cells:
		_flashes[c] = duration


# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	var need_overlay := false
	if not _flashes.is_empty():
		for k in _flashes.keys():
			_flashes[k] -= delta
			if _flashes[k] <= 0.0:
				_flashes.erase(k)
		need_overlay = true
	if _shake_strength > 0.01:
		shake_offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake_strength
		_shake_strength = lerpf(_shake_strength, 0.0, minf(1.0, delta * 14.0))
		_redraw_all()
	elif shake_offset != Vector2.ZERO:
		shake_offset = Vector2.ZERO
		_redraw_all()
	if not _bursts.is_empty():
		for i in range(_bursts.size() - 1, -1, -1):
			_bursts[i].t += delta
			if _bursts[i].t >= _bursts[i].dur:
				_bursts.remove_at(i)
		need_overlay = true
	if not _trails.is_empty():
		for i in range(_trails.size() - 1, -1, -1):
			_trails[i].t += delta
			if _trails[i].t >= _trails[i].dur:
				_trails.remove_at(i)
		need_overlay = true
	if not _dust.is_empty():
		for i in range(_dust.size() - 1, -1, -1):
			var d: Dictionary = _dust[i]
			d.t += delta
			d.vel.y += cell_size * 14.0 * delta
			d.pos += d.vel * delta
			if d.t >= d.dur:
				_dust.remove_at(i)
		need_overlay = true
	if sim:
		_update_danger(delta)
	if show_piece_tags and sim and sim.players.size() > 1:
		need_overlay = true
	if need_overlay:
		_overlay_layer.queue_redraw()
	_glow_layer.queue_redraw()  # glow pulses
	if sim:
		for p in sim.players:
			if p.active and p.active.bomb:
				_overlay_layer.queue_redraw()
				break
	_meters_layer.queue_redraw()


func _recalc_geometry() -> void:
	if sim == null:
		return
	var w := float(sim.board.width) + padding_cells * 2.0
	var h := float(sim.board.visible_height()) + padding_cells * 2.0
	var fit := minf(size.x / w, size.y / h)
	cell_size = maxf(4.0, floorf(fit))
	var px := board_pixel_size()
	board_origin = Vector2((size.x - px.x) * 0.5, (size.y - px.y) * vertical_align).floor()
	geometry_changed.emit()
	_redraw_all()


func _redraw_all() -> void:
	queue_redraw()
	if is_node_ready():
		_cells_layer.queue_redraw()
		_overlay_layer.queue_redraw()
		_glow_layer.queue_redraw()
		_meters_layer.queue_redraw()


func _on_piece_changed(_player_id: int) -> void:
	_cells_layer.queue_redraw()
	_overlay_layer.queue_redraw()


func _on_piece_locked(_player_id: int, cells: Array[Vector2i]) -> void:
	flash_cells(cells, 0.12)


func _on_hard_drop(player_id: int, rows: int) -> void:
	if rows > 2:
		shake(minf(1.0 + rows * 0.15, 4.0))
	var p := sim.get_player(player_id)
	if p == null or p.active == null:
		return
	var cells := p.active.get_cells()
	var col := player_color(player_id)
	if rows > 0:
		_trails.append({"cells": cells, "rows": rows, "color": col, "t": 0.0, "dur": 0.22})
	# Dust puffs under the lowest cell of each column.
	var lowest := {}
	for c in cells:
		if not lowest.has(c.x) or c.y > lowest[c.x]:
			lowest[c.x] = c.y
	var n := clampi(rows / 3 + 2, 2, 6)
	for x: int in lowest:
		var y: int = lowest[x]
		if y < sim.board.hidden_rows:
			continue
		for k in n:
			var base := Vector2((x + randf()) * cell_size, (y - sim.board.hidden_rows + 1) * cell_size)
			var vel := Vector2(randf_range(-1.0, 1.0) * cell_size * 3.0, -randf_range(0.5, 2.0) * cell_size * 2.0)
			_dust.append({"pos": base, "vel": vel, "t": 0.0, "dur": randf_range(0.25, 0.45), "color": col.lightened(0.4)})


func _on_lines_cleared(result: LineClearResult) -> void:
	shake(2.0 + result.line_count() * 1.5)


func _update_danger(delta: float) -> void:
	var b := sim.board
	var max_h := 0
	for x in b.width:
		max_h = maxi(max_h, b.column_height(x))
	var fill := float(max_h) / float(maxi(b.visible_height(), 1))
	var target := clampf((fill - 0.65) / 0.3, 0.0, 1.0)
	var before := _danger
	_danger = lerpf(_danger, target, minf(1.0, delta * 4.0))
	if _danger > 0.01 or before > 0.01:
		queue_redraw()


func danger_level() -> float:
	return _danger


func _on_board_effect(e: Dictionary) -> void:
	var col := player_color(e.owner) if e.owner >= 0 else Color.WHITE
	var cells: Array = e.cells
	match String(e.key):
		"bomb", "bomb_piece":
			_add_burst(&"blast", cells, Color(1.0, 0.65, 0.2), 0.45, e.origin)
			shake(5.0)
		"megabomb":
			_add_burst(&"blast", cells, Color(1.0, 0.4, 0.15), 0.6, e.origin)
			shake(8.0)
		"laser":
			_add_burst(&"beam", cells, Color(0.55, 0.95, 1.0), 0.5, e.origin)
			shake(3.0)
		"paint":
			_add_burst(&"paint", cells, col, 0.6, e.origin)
		"quake":
			_add_burst(&"quake", cells, Color(1.0, 0.8, 0.5), 0.6, e.origin)
			shake(9.0)


func _add_burst(kind: StringName, cells: Array, color: Color, dur: float, origin: Vector2i) -> void:
	_bursts.append({"kind": kind, "cells": cells.duplicate(), "color": color, "t": 0.0, "dur": dur, "origin": origin})


func _draw_bursts(layer: CanvasItem) -> void:
	var b := sim.board
	for burst: Dictionary in _bursts:
		var k: float = 1.0 - burst.t / burst.dur
		var col: Color = burst.color
		match String(burst.kind):
			"blast":
				# Expanding ring + fading hot cells.
				var center := cell_rect(burst.origin.x, burst.origin.y).get_center()
				var r := cell_size * (0.8 + 3.5 * (1.0 - k))
				layer.draw_arc(center, r, 0.0, TAU, 32, Color(col.r, col.g, col.b, 0.8 * k), maxf(2.0, cell_size * 0.35 * k), true)
				for c: Vector2i in burst.cells:
					if c.y >= b.hidden_rows:
						layer.draw_rect(cell_rect(c.x, c.y).grow(-cell_size * 0.1 * (1.0 - k)), Color(1, 0.95, 0.7, 0.85 * k), true)
			"beam":
				var x: int = burst.origin.x
				var top := cell_rect(x, b.hidden_rows).position
				var w := cell_size * (0.3 + 0.9 * k)
				var rect := Rect2(top.x + (cell_size - w) * 0.5, top.y, w, cell_size * b.visible_height())
				layer.draw_rect(rect, Color(col.r, col.g, col.b, 0.75 * k), true)
				layer.draw_rect(rect.grow_individual(-w * 0.3, 0, -w * 0.3, 0), Color(1, 1, 1, 0.9 * k), true)
			"paint":
				for c: Vector2i in burst.cells:
					if c.y >= b.hidden_rows:
						var rr := cell_rect(c.x, c.y)
						layer.draw_rect(rr, Color(col.r, col.g, col.b, 0.75 * k), true)
						layer.draw_rect(rr, Color(1, 1, 1, 0.6 * k), false, 2.0)
			"quake":
				for c: Vector2i in burst.cells:
					if c.y >= b.hidden_rows:
						layer.draw_rect(cell_rect(c.x, c.y), Color(col.r, col.g, col.b, 0.45 * k), true)


func _draw_trails_and_dust(layer: CanvasItem) -> void:
	var b := sim.board
	for tr_: Dictionary in _trails:
		var k: float = 1.0 - tr_.t / tr_.dur
		var col: Color = tr_.color
		var xs := {}
		var top := {}
		for c: Vector2i in tr_.cells:
			if not top.has(c.x) or c.y < top[c.x]:
				top[c.x] = c.y
			xs[c.x] = true
		for x: int in xs:
			var y_end: int = top[x]
			var y_start: int = maxi(b.hidden_rows, y_end - tr_.rows)
			if y_end <= y_start:
				continue
			var r0 := cell_rect(x, y_start)
			var r1 := cell_rect(x, y_end)
			var h := r1.position.y - r0.position.y
			var inset := cell_size * (0.15 + 0.25 * (1.0 - k))
			var rect := Rect2(r0.position.x + inset, r0.position.y, cell_size - inset * 2.0, h)
			layer.draw_rect(rect, Color(col.r, col.g, col.b, 0.28 * k), true)
	var origin := board_origin + shake_offset
	for d: Dictionary in _dust:
		var a: float = 1.0 - d.t / d.dur
		var s := maxf(1.5, cell_size * 0.16)
		layer.draw_rect(Rect2(origin + d.pos - Vector2(s, s) * 0.5, Vector2(s, s)), Color(d.color.r, d.color.g, d.color.b, 0.8 * a), true)


## Name tag above every falling piece so you can tell who is where; your
## own piece gets a "YOU" marker.
func _draw_piece_tags(layer: CanvasItem) -> void:
	var font := get_theme_default_font()
	var fs := clampi(int(cell_size * 0.55), 9, 16)
	var b := sim.board
	var placed: Array[Rect2] = []
	for p in sim.players:
		if p.active == null:
			continue
		var cells := p.active.get_cells()
		var min_x := 9999
		var max_x := -9999
		var min_y := 9999
		for c in cells:
			min_x = mini(min_x, c.x)
			max_x = maxi(max_x, c.x)
			min_y = mini(min_y, c.y)
		var mine := ghost_players.has(p.id)
		var text := tr("HUD_YOU") if mine else p.display_name.get_slice(" (", 0).left(10)
		var col := player_color(p.id).lightened(0.35)
		var top := cell_rect(min_x, maxi(min_y, b.hidden_rows))
		var center_x := (cell_rect(min_x, 0).position.x + cell_rect(max_x, 0).end.x) * 0.5
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pos := Vector2(center_x - tw * 0.5, top.position.y - fs * 0.35)
		# Stack tags that would overlap (pieces spawning next to each other).
		var rect := Rect2(pos - Vector2(2, fs), Vector2(tw + 4, fs + 2))
		for _i in 4:
			var hit := false
			for other in placed:
				if other.intersects(rect):
					hit = true
					break
			if not hit:
				break
			rect.position.y -= fs + 1
		pos.y = rect.position.y + fs
		placed.append(rect)
		var alpha := 0.95 if mine else 0.7
		layer.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(3, fs / 3), Color(0.02, 0.03, 0.06, 0.85 * alpha))
		layer.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, alpha))


func _on_setting_changed(section: String, key: String, value: Variant) -> void:
	if section == "video" and key == "color_patterns":
		show_patterns = value
		_redraw_all()
	elif section == "video" and key == "show_ghost":
		show_ghost = value
		_redraw_all()
	elif section == "video" and key == "piece_tags":
		show_piece_tags = value
		_redraw_all()


func _apply_skin() -> void:
	if not is_node_ready():
		return
	_cells_layer.material = skin.cell_material if skin.tint_with_shader else null
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = add


# --------------------------------------------------------------------------
# Drawing (called by BoardLayer children)

func _draw() -> void:
	if sim == null:
		return
	var px := board_pixel_size()
	var r := Rect2(board_origin + shake_offset, px)
	draw_rect(r.grow(2.0), skin.board_border, true)
	if _danger > 0.01:
		# Pulsing red frame when the stack nears the top.
		var pulse := 0.5 + 0.5 * sin(_time * (6.0 + 6.0 * _danger))
		var w := 2.0 + 4.0 * _danger
		draw_rect(r.grow(w), Color(1.0, 0.18, 0.15, (0.35 + 0.5 * pulse) * _danger), false, w)
	draw_rect(r, skin.board_background, true)
	if skin.grid_texture:
		for y in sim.board.visible_height():
			for x in sim.board.width:
				draw_texture_rect(skin.grid_texture, Rect2(r.position + Vector2(x, y) * cell_size, Vector2(cell_size, cell_size)), false, skin.grid_tint)


func draw_cells_layer(layer: CanvasItem) -> void:
	if sim == null or skin.cell_texture == null:
		return
	var b := sim.board
	for y in range(b.hidden_rows, b.height):
		for x in b.width:
			var owner := b.owners[b.idx(x, y)]
			if owner == BoardState.EMPTY:
				continue
			var col := player_color(owner) if skin.modulate_cells else Color.WHITE
			layer.draw_texture_rect(skin.cell_texture, cell_rect(x, y), false, col)
	for p in sim.players:
		if p.active == null:
			continue
		var col := player_color(p.id) if skin.modulate_cells else Color.WHITE
		col = Color(col.r * skin.active_brightness, col.g * skin.active_brightness, col.b * skin.active_brightness, 1.0)
		for c in p.active.get_cells():
			if c.y >= b.hidden_rows:
				layer.draw_texture_rect(skin.cell_texture, cell_rect(c.x, c.y), false, col)


func draw_overlay_layer(layer: CanvasItem) -> void:
	if sim == null:
		return
	var b := sim.board
	# Ghosts first (under the specials/patterns of the active piece).
	if show_ghost and skin.ghost_texture:
		for pid in ghost_players:
			var p := sim.get_player(pid)
			if p == null or p.active == null:
				continue
			var col := player_color(pid)
			col.a = skin.ghost_alpha
			for c in sim.get_ghost_cells(pid):
				if c.y >= b.hidden_rows:
					layer.draw_texture_rect(skin.ghost_texture, cell_rect(c.x, c.y), false, col)
	# Locked: patterns + specials
	for y in range(b.hidden_rows, b.height):
		for x in b.width:
			var i := b.idx(x, y)
			var owner := b.owners[i]
			if owner == BoardState.EMPTY:
				continue
			_draw_cell_decor(layer, x, y, owner, b.specials[i])
	# Active pieces: patterns + specials
	for p in sim.players:
		if p.active == null:
			continue
		var cells := p.active.get_cells()
		for idx in cells.size():
			var c := cells[idx]
			if c.y >= b.hidden_rows:
				_draw_cell_decor(layer, c.x, c.y, p.id, p.active.special_at_index(idx))
	# Bomb pieces: pulsing glyph on every cell.
	var bomb_tex := skin.get_special_overlay(&"bomb_piece")
	for p in sim.players:
		if p.active == null or not p.active.bomb:
			continue
		var pulse := 0.55 + 0.45 * sin(_time * 12.0)
		for c in p.active.get_cells():
			if c.y >= b.hidden_rows:
				layer.draw_rect(cell_rect(c.x, c.y), Color(1, 0.3, 0.15, 0.35 * pulse), true)
				if bomb_tex:
					layer.draw_texture_rect(bomb_tex, cell_rect(c.x, c.y), false, Color(1, 1, 1, 0.6 + 0.4 * pulse))
	_draw_bursts(layer)
	_draw_trails_and_dust(layer)
	if show_piece_tags and sim.players.size() > 1:
		_draw_piece_tags(layer)
	# Lock flashes
	for c: Vector2i in _flashes:
		if c.y >= b.hidden_rows:
			var a: float = clampf(_flashes[c] / 0.18, 0.0, 1.0) * 0.6
			layer.draw_rect(cell_rect(c.x, c.y), Color(1, 1, 1, a), true)


func _draw_cell_decor(layer: CanvasItem, x: int, y: int, owner: int, special: int) -> void:
	if show_patterns:
		var app := appearance(owner)
		if app.pattern:
			layer.draw_texture_rect(app.pattern, cell_rect(x, y), false, Color(0, 0, 0, 0.9))
	if special > 0:
		var t := sim.get_special_type(special)
		if t:
			var tex := skin.get_special_overlay(t.key)
			if tex:
				layer.draw_texture_rect(tex, cell_rect(x, y), false)


## Who leads each row: thin strips left and right of the board in the
## leader's color; nearly full rows pulse. Makes the whole board readable
## at a glance even when you focus on your own corner.
func draw_meters_layer(layer: CanvasItem) -> void:
	if sim == null or skin.row_meter_width <= 0.0:
		return
	var b := sim.board
	var mw := maxf(2.0, cell_size * skin.row_meter_width)
	var gap := maxf(2.0, cell_size * 0.12)
	var left_x := board_origin.x + shake_offset.x - gap - mw
	var right_x := board_origin.x + shake_offset.x + float(b.width) * cell_size + gap
	var pulse := 0.5 + 0.5 * sin(_time * 9.0)
	for y in range(b.hidden_rows, b.height):
		var counts := {}
		var filled := 0
		for x in b.width:
			var o := b.owners[b.idx(x, y)]
			if o != BoardState.EMPTY:
				filled += 1
				counts[o] = counts.get(o, 0) + 1
		if filled == 0:
			continue
		var leader := -1
		var best := 0
		var tie := false
		for o: int in counts:
			if counts[o] > best:
				best = counts[o]
				leader = o
				tie = false
			elif counts[o] == best:
				tie = true
		var fill := float(filled) / float(b.width)
		var col := Color(0.6, 0.6, 0.65) if tie else player_color(leader)
		col.a = 0.25 + 0.6 * fill
		if fill >= skin.row_meter_hot:
			col = col.lightened(0.35 * pulse)
			col.a = 0.85 + 0.15 * pulse
		var ry := cell_rect(0, y).position.y + 1.0
		var rh := cell_size - 2.0
		layer.draw_rect(Rect2(left_x, ry, mw, rh), col, true)
		layer.draw_rect(Rect2(right_x, ry, mw * fill, rh), col, true)


func draw_glow_layer(layer: CanvasItem) -> void:
	if sim == null or skin.glow_texture == null:
		return
	var b := sim.board
	var gsize := Vector2(cell_size, cell_size) * skin.glow_scale
	var pulse := 0.75 + 0.25 * sin(_time * skin.glow_pulse_speed)
	if skin.glow_strength_locked > 0.0:
		for y in range(b.hidden_rows, b.height):
			for x in b.width:
				var i := b.idx(x, y)
				var owner := b.owners[i]
				if owner == BoardState.EMPTY:
					continue
				var strength := skin.glow_strength_special * pulse if b.specials[i] > 0 else skin.glow_strength_locked
				_glow_at(layer, x, y, owner, strength, gsize * (1.4 if b.specials[i] > 0 else 1.0))
	for p in sim.players:
		if p.active == null:
			continue
		var cells := p.active.get_cells()
		for idx in cells.size():
			var c := cells[idx]
			if c.y < b.hidden_rows:
				continue
			var special := p.active.special_at_index(idx) > 0
			_glow_at(layer, c.x, c.y, p.id, skin.glow_strength_special * pulse if special else skin.glow_strength_active, gsize * (1.4 if special else 1.0))


func _glow_at(layer: CanvasItem, x: int, y: int, owner: int, strength: float, gsize: Vector2) -> void:
	var col := player_color(owner)
	col.a = strength
	var center := cell_rect(x, y).get_center()
	layer.draw_texture_rect(skin.glow_texture, Rect2(center - gsize * 0.5, gsize), false, col)
