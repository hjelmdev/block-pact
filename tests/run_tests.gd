extends SceneTree
## Headless test runner for the pure simulation layer.
## Run: godot --headless --path . -s res://tests/run_tests.gd

var _failures := 0
var _passes := 0


func _init() -> void:
	_test_rotation_cache()
	_test_row_removal()
	_test_scoring_ownership()
	_test_x5_owner_share()
	_test_determinism()
	_test_active_collision()
	_test_bot_plays()
	print("\n%d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, label: String) -> void:
	if cond:
		_passes += 1
		print("  ok   ", label)
	else:
		_failures += 1
		printerr("  FAIL ", label)


func _make_setup(players: int, seed_value: int, mode_path := "res://data/modes/shared_competition.tres") -> MatchSetup:
	var s := MatchSetup.new()
	s.mode = load(mode_path)
	s.seed = seed_value
	for i in players:
		var slot := PlayerSlot.new()
		slot.display_name = "P%d" % (i + 1)
		slot.kind = PlayerSlot.Kind.BOT
		slot.color_index = i
		s.slots.append(slot)
	return s


func _test_rotation_cache() -> void:
	var set: PieceSet = load("res://data/pieces/standard_pieces.tres")
	var t := set.get_by_id(&"T")
	var r1 := t.get_cells(1)
	_check(r1.has(Vector2i(2, 1)) and r1.has(Vector2i(1, 0)) and r1.has(Vector2i(1, 2)), "T rotates clockwise")
	_check(t.get_cells(4) == t.get_cells(0), "rotation wraps")


func _test_row_removal() -> void:
	var b := BoardState.new(4, 6, 2)
	for x in 4:
		b.set_cell(x, 5, 0)
	b.set_cell(1, 4, 1)
	b.remove_rows(b.find_full_rows())
	_check(b.get_owner(1, 5) == 1 and b.get_owner(0, 5) == BoardState.EMPTY, "rows collapse")


func _test_scoring_ownership() -> void:
	var rules := ScoreRules.new()
	rules.scale_with_level = false
	var row: Array = []
	for x in 10:
		row.append({"x": x, "owner": 0 if x < 4 else (1 if x < 7 else 2), "special": 0})
	var res := rules.evaluate_clear([row], PackedInt32Array([5]), 2, 1, 1, 10, {})
	_check(res.rows[0].points[0] == 40 and res.rows[0].points[1] == 30 and res.rows[0].points[2] == 30, "40/30/30 split")
	_check(res.awards[2] == 30 + rules.completion_bonus, "finisher bonus")


func _test_x5_owner_share() -> void:
	var rules := ScoreRules.new()
	rules.scale_with_level = false
	var x5 := SpecialBlockType.new()
	x5.id = 3
	x5.multiplier = 5
	var row: Array = []
	for x in 10:
		row.append({"x": x, "owner": 0 if x < 6 else 1, "special": 3 if x == 0 else 0})
	var res := rules.evaluate_clear([row], PackedInt32Array([5]), 1, 1, 1, 10, {3: x5})
	_check(res.rows[0].points[0] == 300, "x5 multiplies owner's share (60*5)")
	_check(res.rows[0].points[1] == 40, "others unaffected by x5")


func _run_random(seed_value: int, ticks: int) -> String:
	var sim := MatchSimulation.new(_make_setup(4, seed_value))
	sim.start()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for t in ticks:
		var inputs := PackedInt32Array()
		for i in 4:
			inputs.append(rng.randi() & 127 if rng.randf() < 0.3 else 0)
		sim.step(inputs)
		if sim.finished:
			break
	var parts := [sim.tick_count, sim.total_lines, sim.board.owners, sim.board.specials]
	for p in sim.players:
		parts.append(p.score)
	return str(hash(parts))


func _test_determinism() -> void:
	var a := _run_random(1234, 6000)
	var b := _run_random(1234, 6000)
	var c := _run_random(999, 6000)
	_check(a == b, "same seed + inputs => identical state")
	_check(a != c, "different seed => different state")


func _test_active_collision() -> void:
	var setup := _make_setup(2, 7)
	setup.rule_overrides = {"active_piece_collision": true}
	var sim := MatchSimulation.new(setup)
	sim.start()
	# Let both spawn.
	for i in 20:
		sim.step(PackedInt32Array([0, 0]))
	var p0 := sim.players[0]
	var p1 := sim.players[1]
	_check(p0.active != null and p1.active != null, "both players have active pieces")
	# Push player 0 right into player 1 many times; pieces must never overlap.
	var overlap := false
	for i in 60:
		sim.step(PackedInt32Array([InputCommand.RIGHT, InputCommand.LEFT]))
		if p0.active and p1.active:
			for c in p0.active.get_cells():
				if p1.active.get_cells().has(c):
					overlap = true
	_check(not overlap, "active pieces never overlap")


func _test_bot_plays() -> void:
	var setup := _make_setup(2, 42)
	for s in setup.slots:
		s.bot_profile_id = &"hard"
	var sim := MatchSimulation.new(setup)
	var bots: Array[BotInputSource] = []
	for i in 2:
		var b := BotInputSource.new(BotProfile.load_profile(&"hard"))
		b.bind(sim, i)
		bots.append(b)
	sim.start()
	var t0 := Time.get_ticks_msec()
	for t in 60 * 120:
		var inputs := PackedInt32Array()
		for b in bots:
			inputs.append(b.gather(sim.tick_count))
		sim.step(inputs)
		if sim.finished:
			break
	var ms := Time.get_ticks_msec() - t0
	print("    bots: %d lines, scores %d / %d, %d ticks in %d ms" % [sim.total_lines, sim.players[0].score, sim.players[1].score, sim.tick_count, ms])
	_check(sim.total_lines >= 10, "bots clear lines on a shared board")
