extends SceneTree
## Dev probe: how well do bots play? godot --headless -s res://tests/bot_probe.gd -- <players> <profile> <mode>

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var n := int(a[0]) if a.size() > 0 else 1
	var prof := StringName(a[1]) if a.size() > 1 else &"hard"
	var mode := a[2] if a.size() > 2 else "classic_solo"
	var setup := MatchSetup.new()
	setup.mode = load("res://data/modes/%s.tres" % mode)
	setup.seed = 5
	if a.size() > 4:
		setup.board_size_override = Vector2i(int(a[4]), int(a[5]))
	for i in n:
		var s := PlayerSlot.new()
		s.kind = PlayerSlot.Kind.BOT
		setup.slots.append(s)
	if a.size() > 3:
		setup.mode = setup.mode.duplicate()
		setup.mode.active_piece_collision = a[3] == "1"
	var sim := MatchSimulation.new(setup)
	var bots: Array[BotInputSource] = []
	for i in n:
		var b := BotInputSource.new(BotProfile.load_profile(prof))
		b.bind(sim, i)
		bots.append(b)
	sim.start()
	var t0 := Time.get_ticks_msec()
	while not sim.finished and sim.tick_count < 60 * 300:
		var inputs := PackedInt32Array()
		for b in bots:
			inputs.append(b.gather(sim.tick_count))
		sim.step(inputs)
		if sim.tick_count % 1800 == 0:
			print("t=%ds lines=%d pieces=%d" % [sim.tick_count / 60, sim.total_lines, sim.players[0].pieces_placed])
	print("END t=%ds lines=%d pieces=%s ms=%d" % [sim.tick_count / 60, sim.total_lines, sim.players.map(func(p): return p.pieces_placed), Time.get_ticks_msec() - t0])
	var b := sim.board
	for y in range(b.hidden_rows, b.height):
		var row := ""
		for x in b.width:
			var o := b.owners[b.idx(x, y)]
			row += "." if o < 0 else str(o)
		print(row)
	quit()
