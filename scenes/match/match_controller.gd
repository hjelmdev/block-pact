class_name MatchController
extends Node
## Owns one MatchSimulation and its input sources, and ticks it at a fixed
## rate. Identical for solo, bots, local multiplayer and (later) online:
## only the InputSource objects differ.
##
## Presentation nodes join the "match_presenter" group and implement
## bind_match(sim, setup, controller); they are bound automatically.

signal match_ready(sim: MatchSimulation, setup: MatchSetup)
signal match_ended(ranking: Array)
signal countdown_tick(value: int)

@export var countdown_seconds: int = 3

var setup: MatchSetup
var sim: MatchSimulation
var sources: Array[InputSource] = []
var running: bool = false
## Lockstep hook: when a source returns NOT_READY the tick is skipped.
var stalled_ticks: int = 0
## Inputs of every tick, for replays / server-side validation later.
var input_log: Array[PackedInt32Array] = []
var record_inputs: bool = true

var _touch_source: TouchInputSource
var _countdown_left: float = 0.0
var _last_count: int = -1


func start_match(p_setup: MatchSetup) -> void:
	setup = p_setup
	if setup.seed == 0:
		setup.seed = randi()
	sim = MatchSimulation.new(setup)
	_create_sources()
	sim.match_finished.connect(_on_match_finished)
	get_tree().call_group(&"match_presenter", &"bind_match", sim, setup, self)
	match_ready.emit(sim, setup)
	_countdown_left = float(countdown_seconds)
	_last_count = -1
	if countdown_seconds <= 0:
		_begin()


func get_touch_source() -> TouchInputSource:
	return _touch_source


## Ids of players controlled by people on this device.
func local_human_ids() -> Array[int]:
	var out: Array[int] = []
	for i in sources.size():
		if sources[i].is_local_human():
			out.append(i)
	return out


func _create_sources() -> void:
	sources.clear()
	for i in setup.slots.size():
		var slot := setup.slots[i]
		var src: InputSource
		match slot.kind:
			PlayerSlot.Kind.BOT:
				var profile: BotProfile
				if slot.bot_profile_id == BotLearning.PROFILE_ID:
					profile = BotLearning.trial_profile()
				else:
					profile = BotProfile.load_profile(slot.bot_profile_id)
				var personality := BotPersonality.load_personality(slot.bot_personality_id)
				if personality:
					profile = personality.apply_to(profile)
				src = BotInputSource.new(profile)
			PlayerSlot.Kind.REMOTE:
				# Placeholder until online play exists: a remote seat idles.
				var remote := ScriptedInputSource.new()
				src = remote
			_:
				src = ControlSchemes.create_source(slot.input_device)
				if src is TouchInputSource and _touch_source == null:
					_touch_source = src
		src.bind(sim, i)
		sources.append(src)
	# If touch controls are wanted but nobody picked "touch", let the first
	# local human use them too (e.g. phone + "Keyboard" default).
	if _touch_source == null and Platform.want_touch_controls():
		for i in sources.size():
			if sources[i].is_local_human():
				var combo := CombinedInputSource.new([sources[i], TouchInputSource.new()])
				combo.bind(sim, i)
				_touch_source = combo.sources[1] as TouchInputSource
				sources[i] = combo
				break


func _begin() -> void:
	running = true
	sim.start()


func _physics_process(delta: float) -> void:
	if sim == null:
		return
	if not running:
		if sim.started:
			return
		_countdown_left -= delta
		var c := ceili(_countdown_left)
		if c != _last_count:
			_last_count = c
			countdown_tick.emit(c)
		if _countdown_left <= 0.0:
			_begin()
		return
	if sim.finished:
		return
	var inputs := PackedInt32Array()
	inputs.resize(sources.size())
	for i in sources.size():
		var bits := sources[i].gather(sim.tick_count)
		if bits == InputCommand.NOT_READY:
			stalled_ticks += 1
			return
		inputs[i] = bits
	if record_inputs:
		input_log.append(inputs)
	sim.step(inputs)


func _on_match_finished(ranking: Array) -> void:
	running = false
	_report_bot_learning()
	match_ended.emit(ranking)


func _report_bot_learning() -> void:
	var scores := []
	for p in sim.players:
		scores.append(p.score)
	for i in setup.slots.size():
		var s := setup.slots[i]
		if s.kind == PlayerSlot.Kind.BOT and s.bot_profile_id == BotLearning.PROFILE_ID:
			BotLearning.report(sim.players[i].score, scores)


func _exit_tree() -> void:
	for s in sources:
		s.dispose()
