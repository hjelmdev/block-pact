extends Node
## Visual smoke test: drives the real game through menus and matches and
## saves screenshots. Run (needs a display, e.g. xvfb-run):
##   godot --path . res://tests/visual_test.tscn -- --out /tmp/shots
## The driver re-parents itself to the root so it survives scene changes.

var out_dir := "user://shots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--out")
	if i >= 0 and i + 1 < args.size():
		out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_detach.call_deferred()


func _detach() -> void:
	# Survive scene changes: move to the root and hand "current scene" to a dummy.
	reparent(get_tree().root)
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	if OS.get_cmdline_user_args().has("--fx"):
		_run_fx()
	elif OS.get_cmdline_user_args().has("--knockout"):
		_run_knockout()
	elif OS.get_cmdline_user_args().has("--gestures"):
		_run_gestures()
	else:
		_run()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, from: Vector2, to: Vector2, steps: int, seconds: float) -> void:
	var prev := from
	for i in steps:
		var p := from.lerp(to, float(i + 1) / steps)
		var e := InputEventScreenDrag.new()
		e.index = index
		e.position = p
		e.relative = p - prev
		e.velocity = (p - prev) / (seconds / steps)
		Input.parse_input_event(e)
		prev = p
		await get_tree().create_timer(seconds / steps, true, false, true).timeout


func _run_gestures() -> void:
	GameSettings.set_value("controls", "touch_controls", "on")
	GameSettings.set_value("controls", "touch_scheme", "gestures")
	GameSettings.set_value("controls", "gesture_hint_shown", 0)
	var win := get_window()
	win.size = Vector2i(390, 844)
	var setup := MatchFactory.quick_solo()
	setup.rule_overrides = {"powerups_enabled": true}
	Router.goto(&"match", {"setup": setup})
	await _wait(4.5)
	var screen = get_tree().current_scene
	var sim: MatchSimulation = screen.controller.sim
	var p := sim.get_player(0)
	await _shot("g_0_start")
	var cell: float = screen.gestures._cell_px()
	var c := Vector2(195, 500)
	# Swipe right 3 columns.
	var x0 := p.active.position.x
	_touch(0, c, true)
	await _drag(0, c, c + Vector2(cell * 3.2, 0), 8, 0.2)
	_touch(0, c + Vector2(cell * 3.2, 0), false)
	await _wait(0.3)
	print("GESTURE swipe right: dx=", p.active.position.x - x0)
	# Tap = rotate CW
	var r0 := p.active.rotation
	_touch(0, c, true)
	await _wait(0.05)
	_touch(0, c, false)
	await _wait(0.15)
	print("GESTURE tap rotate: ", r0, " -> ", p.active.rotation)
	# Two-finger tap = rotate CCW
	r0 = p.active.rotation
	_touch(0, c, true)
	_touch(1, c + Vector2(60, 0), true)
	await _wait(0.05)
	_touch(1, c + Vector2(60, 0), false)
	_touch(0, c, false)
	await _wait(0.15)
	print("GESTURE two-finger: ", r0, " -> ", p.active.rotation)
	# Long press = hold
	var held_before := p.hold_piece
	_touch(0, c, true)
	await _wait(0.6)
	_touch(0, c, false)
	await _wait(0.15)
	print("GESTURE long press hold: ", held_before == null and p.hold_piece != null)
	# Soft drop: drag down and keep finger
	var y0 := p.active.position.y
	_touch(0, c, true)
	await _drag(0, c, c + Vector2(0, cell * 2.0), 4, 0.1)
	await _wait(0.4)
	print("GESTURE soft drop rows: ", p.active.position.y - y0)
	_touch(0, c + Vector2(0, cell * 2.0), false)
	# Flick up = hard drop
	var placed := p.pieces_placed
	_touch(0, c, true)
	await _drag(0, c, c - Vector2(0, cell * 3.0), 3, 0.06)
	_touch(0, c - Vector2(0, cell * 3.0), false)
	await _wait(0.2)
	print("GESTURE flick hard drop: ", p.pieces_placed - placed)
	await _shot("g_1_after")
	print("visual test done")
	get_tree().quit()


func _run_knockout() -> void:
	get_window().size = Vector2i(1280, 720)
	var setup := MatchFactory.vs_bots(3, &"normal")
	setup.mode = MatchFactory.load_mode(&"knockout")
	Router.goto(&"match", {"setup": setup})
	await _wait(8.0)
	var sim: MatchSimulation = get_tree().current_scene.controller.sim
	sim._top_out(sim.players[1])
	await _wait(0.3)
	await _shot("ko_1_life_lost")
	sim._top_out(sim.players[2])
	sim._top_out(sim.players[2])
	sim._top_out(sim.players[2])
	await _wait(0.5)
	await _shot("ko_2_eliminated")
	print("visual test done")
	get_tree().quit()


## Special blocks + powerups: 4 hard bots with boosted chances.
func _run_fx() -> void:
	var win := get_window()
	win.size = Vector2i(1280, 720)
	var setup := MatchFactory.vs_bots(3, &"hard")
	setup.slots[0] = MatchFactory.bot_slot(0, &"hard")
	setup.slots[0].display_name = "Adam"
	setup.rule_overrides = {"special_preset": "all", "powerups_enabled": true,
			"powerup_cell_chance": 0.35, "special_chance": 0.5}
	Router.goto(&"match", {"setup": setup})
	await _wait(5.0)
	var sim: MatchSimulation = get_tree().current_scene.controller.sim
	var keys := {}
	var n := 0
	while n < 4:
		var e: Dictionary = await sim.board_effect
		if keys.has(e.key) or e.key == &"gold":
			continue
		keys[e.key] = true
		await _wait(0.12)
		await _shot("fx_%d_%s" % [n, e.key])
		n += 1
	await _wait(1.0)
	await _shot("fx_panels")
	win.size = Vector2i(390, 844)
	await _wait(2.0)
	await _shot("fx_portrait")
	print("visual test done")
	get_tree().quit()


func _run() -> void:
	print("run start")
	var win := get_window()
	win.size = Vector2i(1280, 720)
	Router.goto(&"main_menu")
	await _wait(3.0)
	await _shot("01_main_menu")

	Router.goto(&"lobby", {"preset": "vs_bots"})
	await _wait(1.0)
	var lobby := get_tree().current_scene
	lobby._add_seat(PlayerSlot.Kind.BOT)
	lobby._add_seat(PlayerSlot.Kind.LOCAL_HUMAN)
	await _wait(0.5)
	await _shot("02_lobby")

	var teams := MatchSetup.new()
	teams.mode = MatchFactory.load_mode(&"team_battle")
	var tslots: Array[PlayerSlot] = [MatchFactory.human_slot(0)]
	for k in 3:
		tslots.append(MatchFactory.bot_slot(k + 1, &"normal"))
	teams.slots = tslots
	Router.goto(&"match", {"setup": teams})
	await _wait(9.0)
	await _shot("02b_team_battle_human")
	get_tree().current_scene._pause()
	await _wait(0.5)
	await _shot("02c_paused")
	get_tree().paused = false

	var setup := MatchFactory.vs_bots(3, &"hard")
	setup.slots[0] = MatchFactory.bot_slot(0, &"hard")
	setup.slots[0].display_name = "Adam"
	Router.goto(&"match", {"setup": setup})
	await _wait(6.0)
	var sim: MatchSimulation = get_tree().current_scene.controller.sim
	await sim.lines_cleared
	await _wait(0.3)
	await _shot("03a_line_clear_effect")
	await _wait(12.0)
	await _shot("03_match_4p_landscape")

	win.size = Vector2i(390, 844)
	await _wait(2.0)
	await _shot("04_match_4p_portrait")

	GameSettings.set_value("controls", "touch_controls", "on", false)
	var solo := MatchFactory.quick_solo()
	Router.goto(&"match", {"setup": solo})
	await _wait(5.0)
	await _shot("05_solo_portrait_touch")

	win.size = Vector2i(1280, 720)
	GameSettings.set_value("controls", "touch_controls", "auto", false)
	var eight := MatchFactory.attract_mode(8)
	Router.goto(&"match", {"setup": eight})
	await _wait(30.0)
	await _shot("06_match_8p")

	get_tree().paused = false
	Router.goto(&"settings")
	await _wait(1.0)
	await _shot("07_settings")
	Router.goto(&"account")
	await _wait(1.0)
	await _shot("08_account")
	Router.goto(&"leaderboard")
	await _wait(1.0)
	await _shot("09_leaderboard")
	win.size = Vector2i(390, 844)
	Router.goto(&"main_menu")
	await _wait(2.0)
	await _shot("10_main_menu_portrait")
	Router.goto(&"lobby", {"preset": "vs_bots"})
	await _wait(1.0)
	await _shot("11_lobby_portrait")
	win.size = Vector2i(1280, 720)
	Router.goto(&"online")
	await _wait(2.0)
	await _shot("12_online_menu")
	Net.host_room(true, "Adam")
	Router.goto(&"online_lobby")
	await _wait(1.0)
	Net.host_add_bot("normal")
	Net.host_add_bot("hard")
	await _wait(1.0)
	await _shot("13_online_lobby")
	Net.leave_room()
	print("visual test done")
	get_tree().quit()


func _wait(sec: float) -> void:
	print("wait ", sec, " fps ", Engine.get_frames_per_second())
	await get_tree().create_timer(sec, true, false, true).timeout


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, shot_name])
	print("shot ", shot_name)
