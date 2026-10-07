class_name BotTrainer
extends RefCounted
## Genetic algorithm that learns BotProfile weights by playing headless
## self-play matches on a shared board.
##
## Usable from the CLI (tools/train_bots.gd), from an in-game/editor scene
## (tools/bot_trainer.tscn) or anything else – call [method run_generation]
## repeatedly.

signal generation_finished(generation: int, best_fitness: float, best: PackedFloat32Array)

var population_size: int = 16
var elite_count: int = 4
var mutation_rate: float = 0.25
var mutation_scale: float = 0.3
var seeds_per_eval: int = 3
var max_ticks: int = 60 * 180
var players: int = 4
var mode: GameModeConfig
var reference: BotProfile

var generation: int = 0
var population: Array[PackedFloat32Array] = []
var best_weights: PackedFloat32Array
var best_fitness: float = -INF
var rng := RandomNumberGenerator.new()


func _init(p_mode: GameModeConfig, p_reference: BotProfile, start: PackedFloat32Array, seed_value := 1) -> void:
	mode = p_mode
	reference = p_reference
	rng.seed = seed_value
	best_weights = start
	population.append(start)
	while population.size() < population_size:
		population.append(_mutate(start, 1.0))


func run_generation() -> void:
	var scored: Array = []
	for w in population:
		scored.append({"w": w, "f": evaluate(w)})
	scored.sort_custom(func(a, b): return a.f > b.f)
	if scored[0].f > best_fitness:
		best_fitness = scored[0].f
		best_weights = scored[0].w
	var next: Array[PackedFloat32Array] = []
	for i in mini(elite_count, scored.size()):
		next.append(scored[i].w)
	while next.size() < population_size:
		var a: PackedFloat32Array = scored[_tournament(scored.size())].w
		var b: PackedFloat32Array = scored[_tournament(scored.size())].w
		next.append(_mutate(_crossover(a, b), 1.0))
	population = next
	generation += 1
	generation_finished.emit(generation, scored[0].f, scored[0].w)


func evaluate(weights: PackedFloat32Array) -> float:
	var total := 0.0
	for s in seeds_per_eval:
		total += _play(weights, 1000 + s * 7919)
	return total / float(seeds_per_eval)


func make_profile(weights: PackedFloat32Array, id: StringName, title: String) -> BotProfile:
	var p := fast_profile(weights)
	p.id = id
	p.display_name = title
	return p


static func fast_profile(weights: PackedFloat32Array) -> BotProfile:
	var p := BotProfile.new()
	p.set_weights(weights)
	p.think_ticks = 0
	p.move_interval_ticks = 1
	p.mistake_chance = 0.0
	p.search_radius = 12
	return p


func _play(weights: PackedFloat32Array, seed_value: int) -> float:
	# Self-play on a 4-player shared board at "normal" human-like speed.
	# Fitness rewards keeping the shared board alive and clearing lines –
	# the core skill of the game. (Greed weights stay hand-tuned.)
	var setup := MatchSetup.new()
	setup.mode = mode
	setup.seed = seed_value
	for i in players:
		var slot := PlayerSlot.new()
		slot.kind = PlayerSlot.Kind.BOT
		setup.slots.append(slot)
	var sim := MatchSimulation.new(setup)
	var bots: Array[BotInputSource] = []
	for i in players:
		var prof := BotProfile.new()
		prof.set_weights(weights)
		prof.think_ticks = 20
		prof.move_interval_ticks = 6
		prof.mistake_chance = 0.0
		prof.search_radius = 10
		var b := BotInputSource.new(prof)
		b.bind(sim, i)
		bots.append(b)
	sim.start()
	var inputs := PackedInt32Array()
	inputs.resize(players)
	while not sim.finished and sim.tick_count < max_ticks:
		for i in players:
			inputs[i] = bots[i].gather(sim.tick_count)
		sim.step(inputs)
	var seconds := float(sim.tick_count) / MatchSimulation.TICKS_PER_SECOND
	return seconds * 100.0 + sim.total_lines * 40.0


func _tournament(n: int) -> int:
	var a := rng.randi_range(0, n - 1)
	var b := rng.randi_range(0, n - 1)
	return mini(a, b)  # list is sorted best-first


func _crossover(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for i in a.size():
		out.append(a[i] if rng.randf() < 0.5 else b[i])
	return out


func _mutate(w: PackedFloat32Array, strength: float) -> PackedFloat32Array:
	var out := w.duplicate()
	for i in out.size():
		if rng.randf() < mutation_rate:
			out[i] += rng.randfn(0.0, mutation_scale * strength) * maxf(absf(out[i]), 0.2)
	return out


## Writes easy/normal/hard/adaptive profiles that share the learned weights
## but differ in reaction time, speed and mistakes.
static func write_profiles(best: PackedFloat32Array, out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var tiers := [
		# id, name, think, interval, mistakes, radius, hold
		[&"easy", "Easy", 45, 14, 0.3, 6, false],
		[&"normal", "Normal", 26, 8, 0.1, 9, false],
		[&"hard", "Hard", 12, 4, 0.03, 12, true],
		[&"adaptive", "Adaptive (learns)", 20, 6, 0.06, 10, true],
	]
	for t: Array in tiers:
		var p := BotProfile.new()
		p.set_weights(best)
		p.id = t[0]
		p.display_name = t[1]
		p.think_ticks = t[2]
		p.move_interval_ticks = t[3]
		p.mistake_chance = t[4]
		p.search_radius = t[5]
		p.use_hold = t[6]
		ResourceSaver.save(p, "%s%s.tres" % [out_dir, t[0]])
	print("profiles written to ", out_dir)
