class_name LineClearEffect
extends Control
## The "colors fly to their owner's score bank" effect.
##
## On every line clear each cleared cell becomes a shard in its owner's
## color that flies along a curve to that player's score panel. When the
## first shard of a player arrives, [signal score_arrived] fires so the HUD
## can show "+40" / "+150 x5". Purely visual – the simulation already moved on.

signal score_arrived(player_id: int, points: int, multiplier: int)

@export var flight_time: float = 0.65
@export var shard_scale: float = 0.55
@export var row_flash_time: float = 0.22

var board_view: BoardView
## Callable(player_id) -> Vector2 global position of the score bank.
var anchor_provider: Callable

var _shards: Array = []
var _flashes: Array = []  # {rect, t}
var _pending: Dictionary = {}  # clear_id -> {pid -> [points, mult, announced]}
var _clear_id: int = 0
var _particles_enabled := true


func _ready() -> void:
	add_to_group(&"match_presenter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_particles_enabled = GameSettings.get_value("video", "particles", true)


func bind_match(sim: MatchSimulation, _setup: MatchSetup, _controller: Node) -> void:
	sim.lines_cleared.connect(_on_lines_cleared)


func _on_lines_cleared(result: LineClearResult) -> void:
	if board_view == null:
		return
	_clear_id += 1
	var per_player := {}
	for pid: int in result.awards:
		per_player[pid] = [result.awards[pid], result.max_multiplier_for(pid), false]
	_pending[_clear_id] = per_player
	var inv := get_global_transform().affine_inverse()
	for row in result.rows:
		var r0 := board_view.cell_rect(0, row.y)
		var r1 := board_view.cell_rect(board_view.sim.board.width - 1, row.y)
		var g0 := inv * (board_view.get_global_transform() * r0.position)
		var g1 := inv * (board_view.get_global_transform() * r1.end)
		_flashes.append({"rect": Rect2(g0, g1 - g0), "t": row_flash_time})
		for cell: Dictionary in row.cells:
			var owner: int = cell.owner
			if owner < 0:
				continue
			var start: Vector2 = inv * board_view.cell_center_global(cell.x, row.y)
			var target_g: Vector2 = anchor_provider.call(owner) if anchor_provider.is_valid() else start
			var target: Vector2 = inv * target_g
			var special: bool = cell.special > 0
			var ctrl := start.lerp(target, 0.35) + Vector2(randf_range(-60, 60), randf_range(-120, -40))
			if not _particles_enabled:
				continue
			_shards.append({
				"from": start, "to": target, "ctrl": ctrl,
				"t": -float(cell.x) * 0.008 - randf() * 0.05,
				"dur": flight_time * randf_range(0.85, 1.15),
				"color": board_view.player_color(owner),
				"size": board_view.cell_size * shard_scale * (1.6 if special else 1.0),
				"owner": owner, "clear": _clear_id, "special": special,
			})
	if not _particles_enabled:
		# Announce immediately when particles are disabled.
		for pid: int in per_player:
			score_arrived.emit(pid, per_player[pid][0], per_player[pid][1])
		_pending.erase(_clear_id)


func _process(delta: float) -> void:
	if _shards.is_empty() and _flashes.is_empty():
		return
	for f in _flashes:
		f.t -= delta
	_flashes = _flashes.filter(func(f): return f.t > 0.0)
	var alive: Array = []
	for s in _shards:
		s.t += delta
		if s.t >= s.dur:
			_announce(s.clear, s.owner)
		else:
			alive.append(s)
	_shards = alive
	queue_redraw()


func _announce(clear_id: int, owner: int) -> void:
	var entry: Dictionary = _pending.get(clear_id, {})
	if not entry.has(owner) or entry[owner][2]:
		return
	entry[owner][2] = true
	score_arrived.emit(owner, entry[owner][0], entry[owner][1])


func _draw() -> void:
	for f in _flashes:
		var a: float = f.t / row_flash_time
		draw_rect(f.rect, Color(1, 1, 1, 0.75 * a), true)
	var tex: Texture2D = board_view.skin.particle_texture if board_view else null
	for s in _shards:
		if s.t < 0.0:
			continue
		var k: float = clampf(s.t / s.dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - k, 2.2)  # ease out
		var p: Vector2 = _bezier(s.from, s.ctrl, s.to, e)
		var sz: float = s.size * (1.0 - 0.6 * k)
		var col: Color = s.color.lightened(0.25 if s.special else 0.1)
		col.a = 1.0 - 0.3 * k
		# short trail
		var p2: Vector2 = _bezier(s.from, s.ctrl, s.to, maxf(0.0, e - 0.06))
		draw_line(p2, p, Color(col.r, col.g, col.b, col.a * 0.4), maxf(1.0, sz * 0.5))
		var r := Rect2(p - Vector2(sz, sz) * 0.5, Vector2(sz, sz))
		if tex:
			draw_texture_rect(tex, r, false, col)
		else:
			draw_rect(r, col, true)


static func _bezier(a: Vector2, c: Vector2, b: Vector2, t: float) -> Vector2:
	return a.lerp(c, t).lerp(c.lerp(b, t), t)
