class_name BotInputSource
extends InputSource
## A computer player. Plans a placement with BotBrain when a new piece
## appears, then "presses buttons" at a human-like pace defined by its
## BotProfile. Produces the same InputCommand bits a person would, so bots
## are indistinguishable from humans for the simulation and the network.

var profile: BotProfile
var brain: BotBrain
var rng := RandomNumberGenerator.new()

var _piece_uid: int = -1
var _wait: int = 0
var _target: BotBrain.Placement
var _cooldown: int = 0
var _stuck: int = 0
var _last_pos := Vector2i(-999, -999)
var _last_rot := -1
var _planned_version := -1
var _planned_tick := -999
var _last_action := 0
## Re-plan at most this often when the shared board changes (CPU budget).
const REPLAN_MIN_TICKS := 8


func _init(p_profile: BotProfile) -> void:
	profile = p_profile
	brain = BotBrain.new(profile)


func bind(p_sim: MatchSimulation, p_player_id: int) -> void:
	super(p_sim, p_player_id)
	rng.seed = hash([p_sim.setup.seed, "bot", p_player_id])


func gather(_tick: int) -> int:
	var p := sim.get_player(player_id)
	if p == null or p.active == null:
		_piece_uid = -1
		return 0
	if p.active.uid != _piece_uid:
		_piece_uid = p.active.uid
		_target = null
		_wait = profile.think_ticks
		# Panic mode: no time to think when the piece is about to land.
		if sim.get_ghost_cells(player_id)[0].y - p.active.get_cells()[0].y < 4:
			_wait = mini(_wait, 2)
		_stuck = 0
		_cooldown = 0
	if _wait > 0:
		_wait -= 1
		return 0
	if _target != null and _planned_version != sim.board_version and sim.tick_count - _planned_tick >= REPLAN_MIN_TICKS:
		# The shared board changed under us (someone locked a piece): re-plan.
		_target = _choose(p)
		if _target == null:
			return InputCommand.SOFT_DROP
		_target.use_hold = false
	if _target == null:
		_target = _choose(p)
		if _target == null:
			return InputCommand.SOFT_DROP
		if _target.use_hold:
			_target = null
			return InputCommand.HOLD
	if _cooldown > 0:
		_cooldown -= 1
		return 0
	_cooldown = maxi(profile.move_interval_ticks - 1, 0)
	return _next_action(p)


func _choose(p: PlayerState) -> BotBrain.Placement:
	_planned_version = sim.board_version
	_planned_tick = sim.tick_count
	var options := brain.evaluate(sim, p)
	if options.is_empty():
		return null
	var pick := options[0]
	if options.size() > 1 and rng.randf() < profile.mistake_chance:
		# Human-like slip: a plausible but not optimal spot (no wild blunders).
		var close: Array[BotBrain.Placement] = []
		for o in options:
			if o.value >= pick.value - profile.mistake_margin:
				close.append(o)
		pick = close[rng.randi_range(0, close.size() - 1)]
	if profile.use_hold and sim.config.hold_enabled and not p.hold_used:
		var alt_shape := p.hold_piece if p.hold_piece else (p.queue[0] if not p.queue.is_empty() else null)
		if alt_shape and alt_shape != p.active.shape:
			var alt := brain.evaluate(sim, p, alt_shape)
			if not alt.is_empty() and alt[0].value > pick.value + 1.0:
				pick.use_hold = true
	return pick


func _next_action(p: PlayerState) -> int:
	var a := p.active
	# Only horizontal/rotation progress counts – gravity moves us down anyway.
	if a.position.x == _last_pos.x and a.rotation == _last_rot and _last_action != InputCommand.HARD_DROP and _last_action != InputCommand.SOFT_DROP:
		_stuck += 1
	else:
		_stuck = 0
	_last_pos = a.position
	_last_rot = a.rotation
	if _stuck > 2:
		# Blocked (probably by another player's piece) – re-plan.
		_stuck = 0
		_target = _choose(p)
		if _target == null:
			return InputCommand.SOFT_DROP
	_last_action = _decide(a)
	return _last_action


func _decide(a: ActivePiece) -> int:
	if a.rotation != _target.rotation:
		var diff := posmod(_target.rotation - a.rotation, 4)
		return InputCommand.ROTATE_CCW if diff == 3 else InputCommand.ROTATE_CW
	if a.position.x < _target.x:
		return InputCommand.RIGHT
	if a.position.x > _target.x:
		return InputCommand.LEFT
	return InputCommand.HARD_DROP if profile.use_hard_drop else InputCommand.SOFT_DROP
