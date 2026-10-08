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
## Online: slots we are waiting for (empty when the game flows again).
signal net_waiting(slots: Array)
signal net_desync(tick: int)
signal net_host_lost()

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

## Online play (deterministic lockstep over the Net service).
var net_mode: bool = false
var net_delay: int = 4
var lockstep: NetLockstep
## Lockstep endpoint: the Net autoload (players) or a RoomHost (server).
## Needs send_inputs(), send_hash(), is_authority() and the signals
## inputs_received, peer_dropped, desync_detected, host_lost.
var endpoint: Object
var _waiting := false
const HASH_INTERVAL := 120

var _touch_source: TouchInputSource
var _countdown_left: float = 0.0
var _last_count: int = -1


func start_match(p_setup: MatchSetup, p_net_delay: int = -1) -> void:
	setup = p_setup
	net_mode = p_net_delay > 0
	net_delay = p_net_delay
	if setup.seed == 0:
		setup.seed = randi()
	sim = MatchSimulation.new(setup)
	_create_sources()
	if net_mode:
		_setup_lockstep()
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
				# Fed by the network (NetLockstep); never gathered directly.
				src = InputSource.new()
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


func _setup_lockstep() -> void:
	var local: Array[int] = []
	for i in setup.slots.size():
		if setup.slots[i].kind != PlayerSlot.Kind.REMOTE:
			local.append(i)
	if endpoint == null:
		endpoint = Net
	lockstep = NetLockstep.new(sim, sources, local, net_delay)
	lockstep.send_inputs.connect(endpoint.send_inputs)
	endpoint.inputs_received.connect(lockstep.receive)
	endpoint.peer_dropped.connect(_on_net_peer_dropped)
	endpoint.desync_detected.connect(_on_net_desync)
	endpoint.host_lost.connect(_on_net_host_lost)


func _on_net_desync(tick: int) -> void:
	net_desync.emit(tick)


func _on_net_host_lost() -> void:
	net_host_lost.emit()


func _on_net_peer_dropped(peer_id: int) -> void:
	if not endpoint.is_authority():
		return
	for i in setup.slots.size():
		if setup.slots[i].kind == PlayerSlot.Kind.REMOTE and setup.slots[i].peer_id == peer_id:
			lockstep.take_over(i)


func _net_step() -> void:
	var steps := lockstep.update()
	if steps > 0:
		if _waiting:
			_waiting = false
			net_waiting.emit([])
		if sim.tick_count % HASH_INTERVAL == 0:
			endpoint.send_hash(sim.tick_count, NetProtocol.state_hash(sim))
	elif lockstep.stalled_frames % 30 == 29 and not sim.finished:
		_waiting = true
		net_waiting.emit(lockstep.missing_slots())


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
	if net_mode:
		_net_step()
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
	if lockstep and is_instance_valid(endpoint):
		var pairs := [[endpoint.inputs_received, lockstep.receive], [endpoint.peer_dropped, _on_net_peer_dropped],
				[endpoint.desync_detected, _on_net_desync], [endpoint.host_lost, _on_net_host_lost]]
		for pair in pairs:
			if (pair[0] as Signal).is_connected(pair[1]):
				(pair[0] as Signal).disconnect(pair[1])
