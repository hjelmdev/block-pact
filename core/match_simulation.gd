class_name MatchSimulation
extends RefCounted
## The authoritative, deterministic game simulation.
##
## - No nodes, no rendering, no wall-clock time, no global RNG.
## - Advance with [method step] once per tick, passing one InputCommand bitmask
##   per player. Same setup + seed + inputs always gives the same result,
##   which is what local play, bots, replays and future lockstep/rollback
##   networking all build upon.
## - Presentation (board view, HUD, audio, effects) only listens to signals.

const TICKS_PER_SECOND := 60
const SPAWN_RETRY_TICKS := 6
const SPAWN_MAX_ATTEMPTS := 40
## Spawn elsewhere if the own spawn spot has less fall room than this.
const SAFE_SPAWN_ROOM := 4
const SPECIAL_SETS_DIR := "res://data/specials/sets/"
const POWERUP_CELL_PATH := "res://data/specials/powerup_cell.tres"
const POWERUPS_DIR := "res://data/powerups/"
## Bomb powerup: radius around each cell of the locked piece.
const BOMB_PIECE_RADIUS := 1

signal match_started()
signal piece_spawned(player_id: int)
signal piece_moved(player_id: int)
signal piece_rotated(player_id: int, kicked: bool)
signal piece_soft_dropped(player_id: int)
signal piece_hard_dropped(player_id: int, rows: int)
signal piece_held(player_id: int)
signal piece_locked(player_id: int, cells: Array[Vector2i])
signal lines_cleared(result: LineClearResult)
signal score_changed(player_id: int, score: int, delta: int)
signal combo_changed(player_id: int, combo: int)
signal level_changed(level: int)
signal board_changed()
signal player_topped_out(player_id: int)
signal match_finished(ranking: Array)
## Something changed the board outside a normal clear (bomb, laser, paint,
## quake, gold, powerup). Dictionary:
##   key: StringName (bomb, megabomb, laser, paint, gold, powerup, bomb_piece, quake)
##   owner: int        – player whose block/powerup caused it
##   player: int       – who benefits (finisher / activator), -1 if nobody
##   origin: Vector2i  – board cell where it happened (before rows collapse)
##   cells: Array[Vector2i] – affected cells
##   amount: int       – points (gold) or powerup id (powerup)
signal board_effect(effect: Dictionary)
signal powerup_changed(player_id: int, powerup_id: int)
signal powerup_used(player_id: int, powerup_id: int)

var config: GameModeConfig
var setup: MatchSetup
var board: BoardState
var players: Array[PlayerState] = []
var rng := RandomNumberGenerator.new()
var tick_count: int = 0
var total_lines: int = 0
var level: int = 1
var started: bool = false
var finished: bool = false
var ranking: Array = []
## Incremented every time locked cells change (bots use it to re-plan).
var board_version: int = 0

var _rules: Array[MatchRule] = []
var _win: WinCondition
var _score_rules: ScoreRules
var _special_by_id: Dictionary = {}
var _special_total_weight: float = 0.0
var _special_types: Array[SpecialBlockType] = []
var _special_chance: float = 0.0
var _powerup_cell: SpecialBlockType
var _powerups: Array[PowerupType] = []
var _powerup_by_id: Dictionary = {}
var _powerup_total_weight: float = 0.0
var _next_uid: int = 1


func _init(p_setup: MatchSetup) -> void:
	setup = p_setup
	config = p_setup.mode
	if not p_setup.rule_overrides.is_empty():
		config = p_setup.mode.duplicate()
		for key: String in p_setup.rule_overrides:
			config.set(key, p_setup.rule_overrides[key])
	_score_rules = config.score_rules if config.score_rules else ScoreRules.new()
	_win = config.win_condition if config.win_condition else WinCondition.new()
	for r in config.rules:
		_rules.append(r.duplicate(true))
	_setup_specials()
	_setup_powerups()
	rng.seed = hash([p_setup.seed, "specials"])
	level = config.start_level

	var size := p_setup.board_size_override
	if size == Vector2i.ZERO:
		size = config.board_size_for(p_setup.player_count())
	board = BoardState.new(size.x, size.y + config.hidden_rows, config.hidden_rows)

	var n := p_setup.player_count()
	for i in n:
		var slot := p_setup.slots[i]
		var p := PlayerState.new()
		p.id = i
		p.lives = _win.starting_lives()
		p.display_name = slot.display_name
		p.team = slot.team if slot.team >= 0 else config.team_for_slot(i, n)
		var bag_seed := hash([p_setup.seed, "bag"]) if config.shared_sequence else hash([p_setup.seed, "bag", i])
		p.bag = PieceBag.new(config.piece_set, bag_seed)
		# Spawn lanes are spread over the middle part of the board so players
		# stay close enough to see (and fight over) each other's rows.
		var spread := clampf(config.spawn_spread, 0.1, 1.0)
		var margin := float(board.width) * (1.0 - spread) * 0.5
		p.spawn_column = int(margin + (float(i) + 0.5) * float(board.width) * spread / float(n))
		players.append(p)


func _setup_specials() -> void:
	_special_types = config.special_types.duplicate()
	_special_chance = config.special_chance
	match config.special_preset:
		"":
			pass
		"off":
			_special_types.clear()
			_special_chance = 0.0
		_:
			var path := SPECIAL_SETS_DIR + config.special_preset + ".tres"
			if ResourceLoader.exists(path):
				var set: SpecialSet = load(path)
				_special_types = set.types.duplicate()
				_special_chance = set.chance
	for t in _special_types:
		_special_by_id[t.id] = t
		_special_total_weight += t.spawn_weight


func _setup_powerups() -> void:
	if not config.powerups_enabled:
		return
	_powerups = config.powerup_types.duplicate()
	if _powerups.is_empty():
		_powerups = load_all_powerups()
	for t in _powerups:
		_powerup_by_id[t.id] = t
		_powerup_total_weight += t.spawn_weight
	if ResourceLoader.exists(POWERUP_CELL_PATH):
		_powerup_cell = load(POWERUP_CELL_PATH)
		_special_by_id[_powerup_cell.id] = _powerup_cell


## Every PowerupType in res://data/powerups/, sorted by id (deterministic).
static func load_all_powerups() -> Array[PowerupType]:
	var out: Array[PowerupType] = []
	for f in ResourceLoader.list_directory(POWERUPS_DIR):
		if f.ends_with(".tres"):
			var r := load(POWERUPS_DIR + f)
			if r is PowerupType:
				out.append(r)
	out.sort_custom(func(a: PowerupType, b: PowerupType): return a.id < b.id)
	return out


func start() -> void:
	if started:
		return
	started = true
	for r in _rules:
		r.setup(self)
	for p in players:
		_fill_queue(p)
		p.spawn_wait = p.id * 4  # small stagger so not everyone spawns on the same tick
	match_started.emit()


## Advance the simulation one tick. `inputs[i]` belongs to players[i].
func step(inputs: PackedInt32Array) -> void:
	if finished or not started:
		return
	tick_count += 1
	var n := players.size()
	# Rotate processing order each tick so no player has permanent priority
	# when two pieces compete for the same cells.
	for k in n:
		var i := (tick_count + k) % n
		var p := players[i]
		if not p.alive:
			continue
		var bits := inputs[i] if i < inputs.size() else 0
		_process_player(p, maxi(bits, 0))
		if finished:
			return
	for p in players:
		if p.slow_ticks > 0:
			p.slow_ticks -= 1
		if p.double_ticks > 0:
			p.double_ticks -= 1
		if p.rush_ticks > 0:
			p.rush_ticks -= 1
	for r in _rules:
		r.on_tick(self)
	if not finished and _win.check_goal(self):
		_finish()


# --------------------------------------------------------------------------
# Queries (used by presentation and bots)

func get_player(player_id: int) -> PlayerState:
	return players[player_id] if player_id >= 0 and player_id < players.size() else null


func alive_player_count() -> int:
	var c := 0
	for p in players:
		if p.alive:
			c += 1
	return c


func get_team_scores() -> Dictionary:
	var out := {}
	for p in players:
		out[p.team] = out.get(p.team, 0) + p.score
	return out


func get_shared_score() -> int:
	var t := 0
	for p in players:
		t += p.score
	return t


func get_special_type(special_id: int) -> SpecialBlockType:
	return _special_by_id.get(special_id)


func get_powerup_type(powerup_id: int) -> PowerupType:
	return _powerup_by_id.get(powerup_id)


func powerups_enabled() -> bool:
	return not _powerups.is_empty()


## Leaderboard family: "party" (special blocks / powerups) or "classic".
func ruleset() -> String:
	if powerups_enabled() or config.special_preset == "all":
		return "party"
	return "classic"


## Gravity for one player, including Slow / Rush effects.
func gravity_ticks_for(p: PlayerState) -> int:
	var g := current_gravity_ticks()
	if p.rush_ticks > 0:
		g = maxi(1, g / 3)
	if p.slow_ticks > 0:
		g *= 3
	return g


func get_ghost_cells(player_id: int) -> Array[Vector2i]:
	var p := get_player(player_id)
	if p == null or p.active == null:
		return []
	var pos := p.active.position
	while board.cells_fit(p.active.get_cells_at(pos + Vector2i.DOWN, p.active.rotation)):
		pos += Vector2i.DOWN
	return p.active.get_cells_at(pos, p.active.rotation)


func current_gravity_ticks() -> int:
	return config.gravity_for_level(level)


## True if the cells are free of locked blocks and (optionally) other active pieces.
func cells_free(cells: Array[Vector2i], ignore_player: int) -> bool:
	if not board.cells_fit(cells):
		return false
	if config.active_piece_collision:
		for other in players:
			if other.id == ignore_player or other.active == null:
				continue
			for oc in other.active.get_cells():
				if cells.has(oc):
					return false
	return true


# --------------------------------------------------------------------------
# Per-player processing

func _process_player(p: PlayerState, bits: int) -> void:
	if InputCommand.has(bits, InputCommand.USE_POWER) and p.powerup > 0:
		_use_powerup(p)
		if finished or not p.alive:
			return
	if p.active == null:
		if p.spawn_wait > 0:
			p.spawn_wait -= 1
			return
		_try_spawn(p)
		return

	if InputCommand.has(bits, InputCommand.HOLD) and config.hold_enabled and not p.hold_used:
		_do_hold(p)
		if p.active == null:
			return
	if InputCommand.has(bits, InputCommand.ROTATE_CW):
		_try_rotate(p, 1)
	if InputCommand.has(bits, InputCommand.ROTATE_CCW):
		_try_rotate(p, -1)
	if InputCommand.has(bits, InputCommand.LEFT):
		_try_shift(p, Vector2i.LEFT)
	if InputCommand.has(bits, InputCommand.RIGHT):
		_try_shift(p, Vector2i.RIGHT)

	if InputCommand.has(bits, InputCommand.HARD_DROP):
		_hard_drop(p)
		return

	if p.hard_drop_pending:
		# Hard-dropped onto another falling piece: keep falling fast, lock on landing.
		if not _try_fall(p):
			if _grounded_on_board(p):
				_lock(p)
		return

	var soft := InputCommand.has(bits, InputCommand.SOFT_DROP)
	if soft:
		if p.soft_drop_counter % maxi(config.soft_drop_ticks, 1) == 0 and _try_fall(p):
			p.gravity_counter = 0
			_add_score(p, _score_rules.soft_drop_points_per_row * (level if _score_rules.scale_with_level else 1))
			piece_soft_dropped.emit(p.id)
		p.soft_drop_counter += 1
	else:
		p.soft_drop_counter = 0
		p.gravity_counter += 1
		if p.gravity_counter >= gravity_ticks_for(p):
			p.gravity_counter = 0
			_try_fall(p)

	if p.active == null:
		return
	if _grounded_on_board(p):
		p.lock_counter += 1
		if p.lock_counter >= config.lock_delay_ticks:
			_lock(p)
	else:
		p.lock_counter = 0


func _try_spawn(p: PlayerState) -> void:
	var shape: PieceShape = p.queue.pop_front()
	_fill_queue(p)
	_spawn_shape(p, shape)


func _spawn_shape(p: PlayerState, shape: PieceShape) -> void:
	var piece := ActivePiece.new(shape, p.id, _next_uid)
	_next_uid += 1
	_roll_specials(piece)
	var x := clampi(p.spawn_column - shape.box_size / 2, 0, board.width - shape.box_size)
	piece.position = Vector2i(x, 0)

	if not board.cells_fit(piece.get_cells()) or _drop_room(piece, piece.position) < SAFE_SPAWN_ROOM:
		# Own spawn spot is (nearly) buried: on a shared board, spawn at the
		# nearest roomier spot instead (dynamic spawn lanes). Only when the
		# whole top is full is it game over.
		var alt := _find_spawn_x(piece, x)
		if alt >= 0:
			piece.position.x = alt
		elif not board.cells_fit(piece.get_cells()):
			_top_out(p)
			return
	if not cells_free(piece.get_cells(), p.id):
		# Another falling piece is in the spawn zone: wait and retry.
		p.spawn_attempts += 1
		if p.spawn_attempts > SPAWN_MAX_ATTEMPTS:
			_top_out(p)
			return
		p.queue.push_front(shape)
		p.spawn_wait = SPAWN_RETRY_TICKS
		return
	p.spawn_attempts = 0
	p.active = piece
	if p.bomb_armed:
		piece.bomb = true
		p.bomb_armed = false
	p.gravity_counter = 0
	p.lock_counter = 0
	p.lock_resets = 0
	p.hard_drop_pending = false
	# Drop one row immediately if possible (modern guideline behaviour).
	var down := piece.get_cells_at(piece.position + Vector2i.DOWN, piece.rotation)
	if cells_free(down, p.id):
		piece.position += Vector2i.DOWN
	piece_spawned.emit(p.id)
	for r in _rules:
		r.on_piece_spawned(self, p)


func _find_spawn_x(piece: ActivePiece, preferred: int) -> int:
	var fallback := -1
	for d in range(1, board.width):
		for x: int in [preferred - d, preferred + d]:
			if x < -piece.shape.box_size or x > board.width:
				continue
			var pos := Vector2i(x, 0)
			if not board.cells_fit(piece.get_cells_at(pos, 0)):
				continue
			if _drop_room(piece, pos) >= SAFE_SPAWN_ROOM:
				return x
			if fallback < 0:
				fallback = x
	return fallback


## How many rows a piece could fall from `pos` (locked cells only).
func _drop_room(piece: ActivePiece, pos: Vector2i) -> int:
	var rows := 0
	while rows < SAFE_SPAWN_ROOM and board.cells_fit(piece.get_cells_at(pos + Vector2i(0, rows + 1), piece.rotation)):
		rows += 1
	return rows


func _roll_specials(piece: ActivePiece) -> void:
	var n := piece.shape.get_cell_count()
	if not _special_types.is_empty() and _special_chance > 0.0 and rng.randf() < _special_chance:
		var cell_index := rng.randi_range(0, n - 1)
		var roll := rng.randf() * _special_total_weight
		var picked: SpecialBlockType = _special_types.back()
		for t in _special_types:
			roll -= t.spawn_weight
			if roll <= 0.0:
				picked = t
				break
		piece.specials[cell_index] = picked.id
	if _powerup_cell and rng.randf() < config.powerup_cell_chance:
		var first := rng.randi_range(0, n - 1)
		for k in n:
			var i := (first + k) % n
			if not piece.specials.has(i):
				piece.specials[i] = _powerup_cell.id
				break


func _fill_queue(p: PlayerState) -> void:
	while p.queue.size() < maxi(config.next_preview_count, 1) + 1:
		p.queue.append(p.bag.next())


func _do_hold(p: PlayerState) -> void:
	var current := p.active.shape
	if p.active.bomb:
		p.bomb_armed = true
	p.active = null
	p.hold_used = true
	if p.hold_piece == null:
		p.hold_piece = current
		_try_spawn(p)
	else:
		var swap := p.hold_piece
		p.hold_piece = current
		_spawn_shape(p, swap)
	piece_held.emit(p.id)


func _try_shift(p: PlayerState, dir: Vector2i) -> bool:
	var a := p.active
	var cells := a.get_cells_at(a.position + dir, a.rotation)
	if not cells_free(cells, p.id):
		return false
	a.position += dir
	_on_moved_while_grounded(p)
	piece_moved.emit(p.id)
	return true


func _try_rotate(p: PlayerState, dir: int) -> bool:
	var a := p.active
	if not a.shape.can_rotate:
		return false
	var to_rot := posmod(a.rotation + dir, 4)
	var kicks := SrsKicks.get_kicks(a.shape.kick_table, a.rotation, to_rot)
	for i in kicks.size():
		var offset: Vector2i = kicks[i]
		var cells := a.get_cells_at(a.position + offset, to_rot)
		if cells_free(cells, p.id):
			a.position += offset
			a.rotation = to_rot
			_on_moved_while_grounded(p)
			piece_rotated.emit(p.id, i > 0)
			return true
	return false


func _try_fall(p: PlayerState) -> bool:
	var a := p.active
	if a == null:
		return false
	var cells := a.get_cells_at(a.position + Vector2i.DOWN, a.rotation)
	if not cells_free(cells, p.id):
		return false
	a.position += Vector2i.DOWN
	piece_moved.emit(p.id)
	return true


func _hard_drop(p: PlayerState) -> void:
	var rows := 0
	while _try_fall_silent(p):
		rows += 1
	if rows > 0:
		_add_score(p, rows * _score_rules.hard_drop_points_per_row * (level if _score_rules.scale_with_level else 1))
	piece_hard_dropped.emit(p.id, rows)
	if _grounded_on_board(p):
		_lock(p)
	else:
		p.hard_drop_pending = true
		piece_moved.emit(p.id)


func _try_fall_silent(p: PlayerState) -> bool:
	var a := p.active
	var cells := a.get_cells_at(a.position + Vector2i.DOWN, a.rotation)
	if not cells_free(cells, p.id):
		return false
	a.position += Vector2i.DOWN
	return true


func _grounded_on_board(p: PlayerState) -> bool:
	var a := p.active
	return not board.cells_fit(a.get_cells_at(a.position + Vector2i.DOWN, a.rotation))


func _on_moved_while_grounded(p: PlayerState) -> void:
	if p.lock_counter > 0 and p.lock_resets < config.max_lock_resets:
		p.lock_counter = 0
		p.lock_resets += 1


func _lock(p: PlayerState) -> void:
	var a := p.active
	var cells := a.get_cells()
	var lock_out := true
	for i in cells.size():
		var c := cells[i]
		board.set_cell(c.x, c.y, p.id, a.special_at_index(i), a.uid)
		if c.y >= board.hidden_rows:
			lock_out = false
	p.active = null
	p.hold_used = false
	p.hard_drop_pending = false
	p.pieces_placed += 1
	board_version += 1
	piece_locked.emit(p.id, cells)
	for r in _rules:
		r.on_piece_locked(self, p, cells)
	if a.bomb:
		var destroyed := _destroy_area(cells, BOMB_PIECE_RADIUS, {})
		p.blocks_destroyed += destroyed.size()
		board_effect.emit({"key": &"bomb_piece", "owner": p.id, "player": p.id,
				"origin": cells[0], "cells": destroyed, "amount": 0})
		_settle_above(destroyed, PackedInt32Array(), p)

	var full := board.find_full_rows()
	if full.is_empty():
		if p.combo != 0:
			p.combo = 0
			combo_changed.emit(p.id, 0)
	else:
		_clear_rows(p, full)
	# Without active-piece collision a falling piece may sit where this one
	# just locked – lift it out.
	_resolve_active_overlaps()
	board_changed.emit()

	if lock_out and not finished:
		_top_out(p)


func _clear_rows(finisher: PlayerState, rows: PackedInt32Array) -> void:
	finisher.combo += 1
	finisher.max_combo = maxi(finisher.max_combo, finisher.combo)
	combo_changed.emit(finisher.id, finisher.combo)

	var row_cells: Array = []
	for y in rows:
		var cells: Array = []
		for x in board.width:
			cells.append({"x": x, "owner": board.get_owner(x, y), "special": board.get_special(x, y)})
		row_cells.append(cells)

	var result := _score_rules.evaluate_clear(row_cells, rows, finisher.id, finisher.combo, level,
			board.width, _special_by_id)
	var destroyed := _apply_special_effects(finisher, rows, row_cells, result)
	for pid: int in result.awards.keys():
		var dp := get_player(pid)
		if dp and dp.double_ticks > 0:
			result.awards[pid] *= 2
			result.doubled.append(pid)
	board.remove_rows(rows)
	_settle_above(destroyed, rows, finisher)
	_resolve_active_overlaps()

	finisher.lines_finished += rows.size()
	finisher.best_clear = maxi(finisher.best_clear, rows.size())
	for row in result.rows:
		for owner: int in row.counts:
			var op := get_player(owner)
			if op:
				op.cells_cleared += row.counts[owner]
		for cell: Dictionary in row.cells:
			if cell.special > 0:
				var sp := get_player(cell.owner)
				if sp:
					sp.specials_triggered += 1
	for pid: int in result.awards:
		var pl := get_player(pid)
		if pl:
			_add_score(pl, result.awards[pid])

	total_lines += rows.size()
	var new_level := config.start_level + total_lines / maxi(config.lines_per_level, 1)
	lines_cleared.emit(result)
	for e: Dictionary in result.effects:
		board_effect.emit(e)
	for r in _rules:
		r.on_lines_cleared(self, result)
	if new_level != level:
		level = new_level
		level_changed.emit(level)
	# Chain reaction: blocks that fell after a blast may have filled rows.
	if not finished:
		var chain := board.find_full_rows()
		if not chain.is_empty():
			_clear_rows(finisher, chain)


## Special cells in the rows being cleared. Runs before the rows collapse, so
## coordinates are the pre-clear ones. Never touches the full rows themselves.
func _apply_special_effects(finisher: PlayerState, rows: PackedInt32Array, row_cells: Array,
		result: LineClearResult) -> Array[Vector2i]:
	var destroyed: Array[Vector2i] = []
	var skip := {}
	for y in rows:
		skip[y] = true
	var level_mult := level if _score_rules.scale_with_level else 1
	for i in rows.size():
		var y := rows[i]
		for cell: Dictionary in row_cells[i]:
			if cell.special <= 0:
				continue
			var t: SpecialBlockType = _special_by_id.get(cell.special)
			if t == null or t.is_multiplier():
				continue
			var origin := Vector2i(cell.x, y)
			var owner: int = cell.owner
			var affected: Array[Vector2i] = []
			var e := {"key": t.key, "owner": owner, "player": owner, "origin": origin,
					"cells": affected, "amount": 0}
			match t.effect:
				SpecialBlockType.Effect.BOMB:
					affected.append_array(_destroy_area([origin] as Array[Vector2i], t.radius, skip))
					_count_destroyed(owner, affected.size())
					destroyed.append_array(affected)
				SpecialBlockType.Effect.LASER:
					for yy in board.height:
						if not skip.has(yy) and board.is_occupied(origin.x, yy):
							board.clear_cell(origin.x, yy)
							affected.append(Vector2i(origin.x, yy))
					_count_destroyed(owner, affected.size())
					destroyed.append_array(affected)
				SpecialBlockType.Effect.PAINT:
					for dy in range(-t.radius, t.radius + 1):
						for dx in range(-t.radius, t.radius + 1):
							var c := origin + Vector2i(dx, dy)
							if skip.has(c.y) or not board.is_occupied(c.x, c.y):
								continue
							if board.get_owner(c.x, c.y) != owner:
								board.set_owner(c.x, c.y, owner)
								affected.append(c)
					var pp := get_player(owner)
					if pp:
						pp.blocks_painted += affected.size()
				SpecialBlockType.Effect.GOLD:
					e.player = finisher.id
					e.amount = t.bonus_points * level_mult
					result.awards[finisher.id] = result.awards.get(finisher.id, 0) + e.amount
				SpecialBlockType.Effect.POWERUP:
					e.player = finisher.id
					e.amount = _grant_powerup(finisher)
			result.effects.append(e)
	if not result.effects.is_empty():
		board_version += 1
	return destroyed


## After a blast: in every column where blocks were destroyed, the blocks
## above the lowest destroyed cell fall down into the gaps. `cells` are in
## coordinates from before `removed_rows` collapsed. Rows that become full
## are cleared by the caller (chain reaction).
func _settle_above(cells: Array[Vector2i], removed_rows: PackedInt32Array, by: PlayerState) -> void:
	if cells.is_empty():
		return
	var bottom := {}  # column -> lowest destroyed row (after the collapse)
	for c in cells:
		var y := c.y
		for r in removed_rows:
			if r > c.y:
				y += 1
		if y < board.height:
			bottom[c.x] = maxi(bottom.get(c.x, -1), y)
	var moved: Array[Vector2i] = []
	var columns := bottom.keys()
	columns.sort()
	for x: int in columns:
		var write: int = bottom[x]
		for y in range(bottom[x], -1, -1):
			if board.is_occupied(x, y):
				if y != write:
					board.move_cell(Vector2i(x, y), Vector2i(x, write))
					moved.append(Vector2i(x, write))
				write -= 1
	if moved.is_empty():
		return
	board_version += 1
	board_effect.emit({"key": &"settle", "owner": by.id, "player": by.id,
			"origin": moved[0], "cells": moved, "amount": 0})


## Clears locked cells within `radius` (Chebyshev) of the given cells, except
## rows in `skip`. Returns the destroyed cells.
func _destroy_area(centers: Array[Vector2i], radius: int, skip: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	for c in centers:
		for dy in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				var q := c + Vector2i(dx, dy)
				if seen.has(q) or skip.has(q.y):
					continue
				seen[q] = true
				if board.is_occupied(q.x, q.y):
					board.clear_cell(q.x, q.y)
					out.append(q)
	board_version += 1
	return out


func _count_destroyed(player_id: int, n: int) -> void:
	var p := get_player(player_id)
	if p:
		p.blocks_destroyed += n


func _grant_powerup(p: PlayerState) -> int:
	if _powerups.is_empty() or not p.alive:
		return 0
	var roll := rng.randf() * _powerup_total_weight
	var picked: PowerupType = _powerups.back()
	for t in _powerups:
		roll -= t.spawn_weight
		if roll <= 0.0:
			picked = t
			break
	p.powerup = picked.id
	powerup_changed.emit(p.id, picked.id)
	return picked.id


func _use_powerup(p: PlayerState) -> void:
	var t: PowerupType = _powerup_by_id.get(p.powerup)
	p.powerup = 0
	if t == null:
		return
	p.powerups_used += 1
	powerup_changed.emit(p.id, 0)
	powerup_used.emit(p.id, t.id)
	match t.effect:
		PowerupType.Effect.BOMB_PIECE:
			if p.active:
				p.active.bomb = true
			else:
				p.bomb_armed = true
		PowerupType.Effect.SLOW:
			p.slow_ticks = t.duration_ticks
			p.rush_ticks = 0
		PowerupType.Effect.DOUBLE:
			p.double_ticks = t.duration_ticks
		PowerupType.Effect.RUSH:
			for o in players:
				if o != p and o.alive:
					o.rush_ticks = t.duration_ticks
					o.slow_ticks = 0
		PowerupType.Effect.QUAKE:
			_quake(p)


## Every column settles: blocks fall straight down to fill holes. Full rows
## that result are cleared with `p` as the finisher.
func _quake(p: PlayerState) -> void:
	var moved: Array[Vector2i] = []
	for x in board.width:
		var write := board.height - 1
		for y in range(board.height - 1, -1, -1):
			if board.is_occupied(x, y):
				if y != write:
					board.move_cell(Vector2i(x, y), Vector2i(x, write))
					moved.append(Vector2i(x, write))
				write -= 1
	board_version += 1
	board_effect.emit({"key": &"quake", "owner": p.id, "player": p.id,
			"origin": Vector2i(board.width / 2, board.height - 1), "cells": moved, "amount": 0})
	var full := board.find_full_rows()
	if not full.is_empty():
		_clear_rows(p, full)
	_resolve_active_overlaps()
	board_changed.emit()


## Knockout: removes every locked block owned by `p` and drops the player's
## held powerup. Called by KnockoutWinCondition.
func knock_out(p: PlayerState) -> void:
	var removed: Array[Vector2i] = []
	for y in board.height:
		for x in board.width:
			if board.get_owner(x, y) == p.id:
				board.clear_cell(x, y)
				removed.append(Vector2i(x, y))
	board_version += 1
	if p.powerup > 0:
		p.powerup = 0
		powerup_changed.emit(p.id, 0)
	board_effect.emit({"key": &"knockout", "owner": p.id, "player": p.id,
			"origin": Vector2i(p.spawn_column, board.hidden_rows), "cells": removed, "amount": p.lives})
	_resolve_active_overlaps()
	board_changed.emit()


## After rows collapse, locked blocks may move into a falling piece – push it up.
func _resolve_active_overlaps() -> void:
	for p in players:
		if p.active == null:
			continue
		var guard := 0
		while not board.cells_fit(p.active.get_cells()) and guard < board.height:
			p.active.position += Vector2i.UP
			guard += 1


func _add_score(p: PlayerState, delta: int) -> void:
	if delta == 0:
		return
	p.score += delta
	score_changed.emit(p.id, p.score, delta)


func _top_out(p: PlayerState) -> void:
	p.active = null
	p.bomb_armed = false
	player_topped_out.emit(p.id)
	if _win.on_top_out(self, p):
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	for p in players:
		p.active = null
	ranking = _win.rank(self)
	match_finished.emit(ranking)
