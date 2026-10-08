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
	else:
		_run()


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
