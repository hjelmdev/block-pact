class_name ResultsPanel
extends Control
## End-of-match screen: ranking, MVP stats, and (for logged-in players)
## highscore submission + achievements. Guests see results but nothing is saved.

signal rematch_requested()
signal menu_requested()

@onready var _title: Label = %TitleLabel
@onready var _rows: VBoxContainer = %Rows
@onready var _note: Label = %NoteLabel
@onready var _rematch: Button = %RematchButton
@onready var _menu: Button = %MenuButton


func _ready() -> void:
	_rematch.pressed.connect(func(): AudioManager.play(Sfx.UI_CLICK); rematch_requested.emit())
	_menu.pressed.connect(func(): menu_requested.emit())


## Online: the host returns everyone to the room; clients just wait.
func set_rematch_text(text: String, visible_button: bool) -> void:
	_rematch.visible = visible_button
	if text != "":
		_rematch.text = text
	if not visible_button:
		_note.text += ("\n" if _note.text != "" else "") + tr("ONLINE_WAITING_HOST")
		_note.visible = true
		_menu.grab_focus()


func show_results(sim: MatchSimulation, setup: MatchSetup, ranking: Array, view: BoardView, replay: MatchReplay = null) -> void:
	for c in _rows.get_children():
		c.queue_free()
	var coop := setup.mode.team_mode == GameModeConfig.TeamMode.COOP
	if coop:
		_title.text = tr("RESULTS_COOP") % sim.get_shared_score()
	elif ranking.size() > 1:
		var winner := sim.get_player(ranking[0].player_id)
		_title.text = tr("RESULTS_WINNER") % winner.display_name
	else:
		_title.text = tr("RESULTS_GAME_OVER")

	var mvp := _mvp_awards(sim)
	for r: Dictionary in ranking:
		var p := sim.get_player(r.player_id)
		var block := VBoxContainer.new()
		block.add_theme_constant_override(&"separation", 0)
		var row := HBoxContainer.new()
		var rank := Label.new()
		rank.text = "#%d" % r.rank
		rank.custom_minimum_size.x = 36
		var sw := AvatarView.make(setup.slots[p.id].avatar if p.id < setup.slots.size() else "", view.player_color(p.id), 26)
		var name_l := Label.new()
		name_l.text = p.display_name
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var score := Label.new()
		score.text = str(p.score)
		score.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for c in [rank, sw, name_l, score]:
			row.add_child(c)
		block.add_child(row)
		var stats := Label.new()
		var extra := ""
		if mvp.has(p.id):
			extra = "   • " + ", ".join(mvp[p.id])
		stats.text = "        " + tr("RESULTS_STATS") % [p.lines_finished, p.cells_cleared, p.max_combo] + extra
		stats.add_theme_font_size_override(&"font_size", 12)
		stats.modulate = Color(1, 0.85, 0.45) if extra != "" else Color(0.7, 0.72, 0.82)
		stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(stats)
		_rows.add_child(block)

	# Saving progress (accounts only)
	if not Progress.score_saved.is_connected(_on_score_saved):
		Progress.score_saved.connect(_on_score_saved)
	var result := Progress.submit_match(sim, setup, ranking, replay)
	_note.text = result
	_note.visible = result != ""
	show()
	_rematch.grab_focus()


func _on_score_saved(note: String) -> void:
	if is_visible_in_tree():
		_note.text = note
		_note.visible = true


func _mvp_awards(sim: MatchSimulation) -> Dictionary:
	var out := {}
	if sim.players.size() < 2:
		return out
	var cats := {
		"MVP_FINISHER": func(p: PlayerState): return p.lines_finished,
		"MVP_BUILDER": func(p: PlayerState): return p.cells_cleared,
		"MVP_COMBO": func(p: PlayerState): return p.max_combo,
		"MVP_SPECIAL": func(p: PlayerState): return p.specials_triggered,
		"MVP_DESTROYER": func(p: PlayerState): return p.blocks_destroyed,
		"MVP_PAINTER": func(p: PlayerState): return p.blocks_painted,
	}
	for key: String in cats:
		var best: PlayerState = null
		var best_v := 0
		for p in sim.players:
			var v: int = cats[key].call(p)
			if v > best_v:
				best_v = v
				best = p
		if best:
			if not out.has(best.id):
				out[best.id] = []
			out[best.id].append(tr(key))
	return out
