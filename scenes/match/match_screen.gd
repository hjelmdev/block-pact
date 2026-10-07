extends Control
## Root of the match scene: wires the controller to the presentation,
## lays out player panels for landscape (desktop) or portrait (phone), and
## handles countdown / pause / results.

const PANEL_SCENE := preload("res://presentation/hud/player_panel.tscn")

@onready var controller: MatchController = $MatchController
@onready var audio: MatchAudio = $MatchAudio
@onready var board_view: BoardView = %BoardView
@onready var effect: LineClearEffect = %LineClearEffect
@onready var callouts: BoardCallouts = %BoardCallouts
@onready var left_col: VBoxContainer = %LeftPanels
@onready var right_col: VBoxContainer = %RightPanels
@onready var compact_row: HFlowContainer = %CompactPanels
@onready var touch_controls: TouchControls = %TouchControls
@onready var mode_label: Label = %ModeLabel
@onready var level_label: Label = %LevelLabel
@onready var lines_label: Label = %LinesLabel
@onready var time_label: Label = %TimeLabel
@onready var shared_label: Label = %SharedLabel
@onready var pause_button: Button = %PauseButton
@onready var countdown_label: Label = %CountdownLabel
@onready var pause_menu: PauseMenu = %PauseMenu
@onready var results_panel: ResultsPanel = %ResultsPanel

var sim: MatchSimulation
var setup: MatchSetup
var panels: Dictionary = {}  # player id -> PlayerPanel


func _ready() -> void:
	setup = Router.params.get("setup")
	if setup == null:
		setup = MatchFactory.quick_solo()
	controller.match_ready.connect(_on_match_ready)
	controller.match_ended.connect(_on_match_ended)
	controller.countdown_tick.connect(_on_countdown)
	effect.board_view = board_view
	effect.anchor_provider = _score_anchor
	effect.score_arrived.connect(_on_score_arrived)
	callouts.board_view = board_view
	Platform.layout_changed.connect(_apply_layout)
	pause_button.pressed.connect(_pause)
	pause_button.icon = Assets.icon(&"pause")
	touch_controls.pause_requested.connect(_pause)
	pause_menu.resume_requested.connect(_resume)
	pause_menu.restart_requested.connect(_restart)
	pause_menu.quit_requested.connect(_quit)
	results_panel.rematch_requested.connect(_restart)
	results_panel.menu_requested.connect(_quit)
	pause_menu.hide()
	results_panel.hide()
	controller.start_match(setup)
	AudioManager.play_music()


func _on_match_ready(p_sim: MatchSimulation, p_setup: MatchSetup) -> void:
	sim = p_sim
	setup = p_setup
	mode_label.text = setup.mode.display_name
	board_view.ghost_players = controller.local_human_ids()
	var humans := controller.local_human_ids()
	var n := setup.slots.size()
	for i in n:
		var panel: PlayerPanel = PANEL_SCENE.instantiate()
		left_col.add_child(panel)  # temporary parent; _apply_layout moves it
		var team_text := ""
		if setup.mode.team_mode == GameModeConfig.TeamMode.TEAMS:
			team_text = "T%d" % (sim.players[i].team + 1)
		var show_previews := humans.has(i) or n <= 4
		panel.setup_panel(sim, i, board_view.player_color(i), show_previews, team_text)
		panels[i] = panel
	if n > 1 and setup.mode.team_mode != GameModeConfig.TeamMode.COOP:
		sim.score_changed.connect(func(_p, _s, _d): _update_ranks())
	_apply_layout(Platform.is_portrait())


func _update_ranks() -> void:
	var order := sim.players.duplicate()
	order.sort_custom(func(a, b): return a.score > b.score)
	for i in order.size():
		var p: PlayerState = order[i]
		var rank := 1
		for q: PlayerState in order:
			if q.score > p.score:
				rank += 1
		var panel: PlayerPanel = panels.get(p.id)
		if panel:
			panel.set_rank(rank, rank == 1 and p.score > 0 and (order.size() < 2 or order[1].score < p.score))


func _apply_layout(portrait: bool) -> void:
	if panels.is_empty():
		return
	var n := panels.size()
	for i in n:
		var panel: PlayerPanel = panels[i]
		var target: Container
		if portrait:
			target = compact_row
		else:
			target = left_col if i < ceili(n / 2.0) else right_col
		if panel.get_parent() != target:
			panel.reparent(target, false)
		panel.set_compact(n > 4 or (portrait and n > 2))
		panel.custom_minimum_size.x = 112.0 if portrait else 160.0
	board_view.vertical_align = 1.0 if portrait else 0.5
	compact_row.visible = portrait
	left_col.visible = not portrait
	right_col.visible = not portrait and n > 1
	touch_controls.custom_minimum_size.y = 190.0 if portrait else 140.0


func _score_anchor(player_id: int) -> Vector2:
	var panel: PlayerPanel = panels.get(player_id)
	return panel.get_score_anchor_global() if panel else get_global_rect().get_center()


func _on_score_arrived(player_id: int, points: int, mult: int) -> void:
	var panel: PlayerPanel = panels.get(player_id)
	if panel:
		panel.show_popup(points, mult)
	audio.on_score_arrived(player_id, points, mult)


func _process(_delta: float) -> void:
	if sim == null:
		return
	level_label.text = tr("HUD_LEVEL") % sim.level
	lines_label.text = tr("HUD_LINES") % sim.total_lines
	var secs := sim.tick_count / MatchSimulation.TICKS_PER_SECOND
	time_label.text = "%d:%02d" % [secs / 60, secs % 60]
	match setup.mode.team_mode:
		GameModeConfig.TeamMode.COOP:
			shared_label.text = tr("HUD_TEAM_TOTAL") % sim.get_shared_score()
		GameModeConfig.TeamMode.TEAMS:
			var parts: PackedStringArray = []
			var ts := sim.get_team_scores()
			var keys := ts.keys()
			keys.sort()
			for t in keys:
				parts.append("T%d %d" % [t + 1, ts[t]])
			shared_label.text = "  ".join(parts)
		_:
			shared_label.text = ""


func _on_countdown(value: int) -> void:
	if value > 0:
		countdown_label.text = str(value)
		AudioManager.play(Sfx.COUNTDOWN)
	else:
		countdown_label.text = tr("HUD_GO")
		AudioManager.play(Sfx.GO)
	countdown_label.show()
	countdown_label.modulate.a = 1.0
	countdown_label.pivot_offset = countdown_label.size * 0.5
	countdown_label.scale = Vector2.ONE * 1.4
	var t := create_tween()
	t.tween_property(countdown_label, "scale", Vector2.ONE, 0.25)
	if value <= 0:
		t.tween_property(countdown_label, "modulate:a", 0.0, 0.4)
		t.tween_callback(countdown_label.hide)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(ControlSchemes.PAUSE_ACTION) and not get_tree().paused and results_panel.visible == false:
		_pause()
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# Auto-pause when the browser tab / app loses focus (solo only).
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and sim and not sim.finished and _can_pause():
		_pause()


func _can_pause() -> bool:
	for s in setup.slots:
		if s.kind == PlayerSlot.Kind.REMOTE:
			return false
	return true


func _pause() -> void:
	if not _can_pause() or (sim and sim.finished):
		return
	get_tree().paused = true
	pause_menu.open()


func _resume() -> void:
	pause_menu.hide()
	get_tree().paused = false


func _restart() -> void:
	var again := MatchSetup.new()
	again.mode = setup.mode
	again.board_size_override = setup.board_size_override
	again.rule_overrides = setup.rule_overrides.duplicate()
	var slots: Array[PlayerSlot] = []
	for s in setup.slots:
		slots.append(s.duplicate())
	again.slots = slots
	Router.goto(&"match", {"setup": again})


func _quit() -> void:
	AudioManager.play(Sfx.UI_BACK)
	Router.goto(&"main_menu")


func _on_match_ended(ranking: Array) -> void:
	await get_tree().create_timer(1.2).timeout
	results_panel.show_results(sim, setup, ranking, board_view)
