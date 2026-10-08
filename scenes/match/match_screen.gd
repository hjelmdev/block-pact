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
var gestures: GestureControls
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
var _online := false
var _notice: Label
var _emote_button: Button
var _emote_bar: PanelContainer


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
	gestures = GestureControls.new()
	gestures.board_view = board_view
	gestures.exclude_rects.append(func(): return pause_button.get_global_rect().grow(10))
	add_child(gestures)
	move_child(gestures, pause_menu.get_index())
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
	var net_delay: int = Router.params.get("net_delay", -1)
	_online = net_delay > 0
	if _online:
		controller.net_waiting.connect(_on_net_waiting)
		controller.net_host_lost.connect(_on_host_lost)
		controller.net_desync.connect(func(t): _show_notice(tr("ONLINE_DESYNC") % t, Color(1, 0.6, 0.4)))
		Net.return_to_lobby.connect(_on_net_return_to_lobby)
		Net.emote_received.connect(_on_emote)
		_build_emotes()
	controller.start_match(setup, net_delay)
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
		sim.board_effect.connect(func(e): if e.key == &"knockout": _update_ranks())
	_apply_layout(Platform.is_portrait())


func _update_ranks() -> void:
	var order := sim.players.duplicate()
	order.sort_custom(func(a, b): return a.score > b.score)
	for i in order.size():
		var p: PlayerState = order[i]
		var rank := 1
		for q: PlayerState in order:
			# Knocked-out players always rank below everyone still in.
			if (q.alive and not p.alive) or (q.alive == p.alive and q.score > p.score):
				rank += 1
		var panel: PlayerPanel = panels.get(p.id)
		if panel:
			panel.set_rank(rank, rank == 1 and p.alive and p.score > 0 and (order.size() < 2 or order[1].score < p.score or not order[1].alive))


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
	# Keep both side columns (even if one is empty) so the board stays
	# centered on screen in solo / odd player counts.
	right_col.visible = not portrait
	right_col.custom_minimum_size.x = 160.0 if not portrait else 0.0
	left_col.custom_minimum_size.x = 160.0 if not portrait else 0.0
	touch_controls.custom_minimum_size.y = 190.0 if portrait else 140.0
	var bottom := 4
	if GestureControls.scheme_active():
		# Swipe controls: the board gets the space the buttons would take,
		# minus a thumb strip at the bottom for the power button.
		touch_controls.custom_minimum_size.y = 0.0
		if portrait and sim and sim.powerups_enabled():
			bottom = 84
	$Layout.add_theme_constant_override(&"margin_bottom", bottom)


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
	# Center over the board, not the window.
	var board_center := board_view.board_origin + board_view.board_pixel_size() * 0.5
	var local := get_global_transform().affine_inverse() * (board_view.get_global_transform() * board_center)
	countdown_label.position = local - countdown_label.size * 0.5
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
	elif _online and event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).physical_keycode
		if k >= KEY_1 and k <= KEY_6:
			Net.send_emote(Net.EMOTES[k - KEY_1])
			get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------
# Emotes (online only): quick reactions, shown above the sender's panel.

func _build_emotes() -> void:
	_emote_button = Button.new()
	_emote_button.text = ":)"
	_emote_button.focus_mode = Control.FOCUS_NONE
	_emote_button.custom_minimum_size = Vector2(44, 36)
	pause_button.get_parent().add_child(_emote_button)
	pause_button.get_parent().move_child(_emote_button, pause_button.get_index())
	_emote_bar = PanelContainer.new()
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override(&"h_separation", 4)
	flow.add_theme_constant_override(&"v_separation", 4)
	for i in Net.EMOTES.size():
		var id: String = Net.EMOTES[i]
		var b := Button.new()
		b.text = tr("EMOTE_" + id.to_upper())
		b.tooltip_text = str(i + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 40)
		b.pressed.connect(func():
			Net.send_emote(id)
			_emote_bar.hide())
		flow.add_child(b)
	_emote_bar.add_child(flow)
	_emote_bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_emote_bar.offset_left = -330
	_emote_bar.offset_top = 48
	_emote_bar.offset_right = -8
	_emote_bar.hide()
	add_child(_emote_bar)
	_emote_button.pressed.connect(func(): _emote_bar.visible = not _emote_bar.visible)
	gestures.exclude_rects.append(func(): return _emote_button.get_global_rect().grow(10))
	gestures.exclude_rects.append(func(): return _emote_bar.get_global_rect().grow(6) if _emote_bar.visible else Rect2())


func _on_emote(key: String, emote: String) -> void:
	if setup == null:
		return
	for i in setup.slots.size():
		var pid: int = setup.slots[i].peer_id
		var slot_key := Net.my_key if pid == Net.my_peer_id else Net.key_for_peer(pid)
		if slot_key != key or setup.slots[i].kind == PlayerSlot.Kind.BOT:
			continue
		var panel: PlayerPanel = panels.get(i)
		if panel == null:
			return
		var l := Label.new()
		l.text = tr("EMOTE_" + emote.to_upper())
		l.add_theme_font_size_override(&"font_size", 20)
		l.add_theme_color_override(&"font_color", board_view.player_color(i).lightened(0.4))
		l.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		l.add_theme_constant_override(&"outline_size", 6)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		l.reset_size()
		var r := panel.get_global_rect()
		l.global_position = Vector2(r.get_center().x - l.size.x * 0.5, r.end.y - l.size.y * 0.2)
		var t := create_tween().set_parallel(true)
		t.tween_property(l, "global_position:y", l.global_position.y - 30.0, 1.6)
		t.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.1)
		t.chain().tween_callback(l.queue_free)
		return


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


# --- Online helpers ---------------------------------------------------------

func _show_notice(text: String, color := Color(1, 1, 1)) -> void:
	if _notice == null:
		_notice = Label.new()
		_notice.add_theme_font_size_override(&"font_size", 22)
		_notice.add_theme_color_override(&"font_outline_color", Color(0, 0, 0, 0.9))
		_notice.add_theme_constant_override(&"outline_size", 8)
		_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_notice)
		_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		_notice.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	_notice.text = text
	_notice.add_theme_color_override(&"font_color", color)
	_notice.visible = text != ""


func _on_net_waiting(slots: Array) -> void:
	if slots.is_empty():
		_show_notice("")
		return
	var names: PackedStringArray = []
	for i: int in slots:
		names.append(sim.get_player(i).display_name)
	_show_notice(tr("ONLINE_WAITING_FOR") % ", ".join(names), Color(1, 0.9, 0.5))


func _on_host_lost() -> void:
	_show_notice(tr("ONLINE_HOST_LEFT"), Color(1, 0.55, 0.5))
	await get_tree().create_timer(3.0).timeout
	Router.goto(&"online")


func _on_net_return_to_lobby() -> void:
	Router.goto(&"online_lobby")


func _restart() -> void:
	if _online:
		if Net.is_leader():
			Net.host_back_to_lobby()
			Router.goto(&"online_lobby")
		return
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
	if _online:
		Net.leave_room()
	AudioManager.play(Sfx.UI_BACK)
	Router.goto(&"main_menu")


func _on_match_ended(ranking: Array) -> void:
	await get_tree().create_timer(1.2).timeout
	results_panel.show_results(sim, setup, ranking, board_view)
	if _online:
		results_panel.set_rematch_text(tr("ONLINE_BACK_TO_ROOM") if Net.is_leader() else "", Net.is_leader())


func _exit_tree() -> void:
	if Net.return_to_lobby.is_connected(_on_net_return_to_lobby):
		Net.return_to_lobby.disconnect(_on_net_return_to_lobby)
