class_name BoardCallouts
extends Control
## Floating text where things happen on the board ("STOLEN!", "QUAD!",
## "x5!", "COMBO x3") plus a banner when the lead changes. Purely visual:
## it only reads LineClearResult / score signals.

signal leader_changed(player_id: int, previous_id: int)

@export var callout_time: float = 1.1
@export var banner_time: float = 1.8

var board_view: BoardView
var sim: MatchSimulation
var setup: MatchSetup
## Players controlled on this device (for "you lost the lead" sounds).
var local_players: Array[int] = []

var _leader: int = -1
var _banner: Label


func _ready() -> void:
	add_to_group(&"match_presenter")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner = _make_label(26)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0


func bind_match(p_sim: MatchSimulation, p_setup: MatchSetup, controller: Node) -> void:
	sim = p_sim
	setup = p_setup
	local_players = controller.local_human_ids()
	sim.lines_cleared.connect(_on_lines_cleared)
	sim.score_changed.connect(_on_score_changed)


func _competitive() -> bool:
	return sim.players.size() > 1 and setup.mode.team_mode != GameModeConfig.TeamMode.COOP


func _on_lines_cleared(result: LineClearResult) -> void:
	if board_view == null:
		return
	var finisher := result.finisher_id
	var fcol := board_view.player_color(finisher)
	var b := sim.board
	var mid_x := b.width / 2
	# Biggest event first, one callout per row group to keep it readable.
	var top_y: int = result.rows[0].y
	var stolen_from := -1
	for row in result.rows:
		top_y = mini(top_y, row.y)
		if not _competitive():
			continue
		var mine: int = row.counts.get(finisher, 0)
		for owner: int in row.counts:
			if owner != finisher and row.counts[owner] > mine and sim.get_player(owner).team != sim.get_player(finisher).team:
				stolen_from = owner
	var anchor_x := _finisher_column(result, mid_x)
	if result.line_count() >= 4:
		_callout(anchor_x, top_y, tr("CALLOUT_QUAD"), fcol, 1.5)
	elif result.line_count() >= 2:
		_callout(anchor_x, top_y, tr("CALLOUT_MULTI") % result.line_count(), fcol, 1.2)
	if stolen_from >= 0:
		var victim := sim.get_player(stolen_from)
		_callout(anchor_x, top_y - 1, tr("CALLOUT_STOLEN") % victim.display_name, fcol, 1.25)
		AudioManager.play(Sfx.STEAL)
	if result.combo > 1:
		_callout(anchor_x, top_y + 1, tr("CALLOUT_COMBO") % result.combo, fcol.lightened(0.3), 1.0)
	# Specials: show the multiplier where the special cell was.
	for row in result.rows:
		for cell: Dictionary in row.cells:
			if cell.special > 0:
				var t := sim.get_special_type(cell.special)
				if t:
					var owner_col := board_view.player_color(cell.owner)
					var pts: int = row.points.get(cell.owner, 0)
					_callout(cell.x, row.y, "x%d  +%d" % [t.multiplier, pts], Color(1, 0.86, 0.3).lerp(owner_col, 0.25), 1.3)


func _finisher_column(result: LineClearResult, fallback: int) -> int:
	# Average x of the finisher's cells in the cleared rows.
	var sum := 0
	var n := 0
	for row in result.rows:
		for cell: Dictionary in row.cells:
			if cell.owner == result.finisher_id:
				sum += cell.x
				n += 1
	return sum / n if n > 0 else fallback


func _on_score_changed(_pid: int, _score: int, _delta: int) -> void:
	if not _competitive():
		return
	var best := -1
	var best_score := 0
	var tie := false
	for p in sim.players:
		if p.score > best_score:
			best_score = p.score
			best = p.id
			tie = false
		elif p.score == best_score and best_score > 0:
			tie = true
	if tie or best < 0 or best == _leader:
		return
	var previous := _leader
	_leader = best
	leader_changed.emit(best, previous)
	if previous < 0:
		return  # first points of the match – no banner
	var p := sim.get_player(best)
	_show_banner(tr("CALLOUT_LEAD") % p.display_name, board_view.player_color(best))
	if local_players.has(previous) and not local_players.has(best):
		AudioManager.play(Sfx.LEAD_LOST)
	else:
		AudioManager.play(Sfx.LEAD_CHANGE)


func _show_banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override(&"font_color", color.lightened(0.25))
	_banner.position.y = 44.0
	var t := create_tween()
	_banner.modulate.a = 0.0
	t.tween_property(_banner, "modulate:a", 1.0, 0.15)
	t.tween_interval(banner_time)
	t.tween_property(_banner, "modulate:a", 0.0, 0.4)


func _callout(x: int, y: int, text: String, color: Color, scale_mult: float) -> void:
	var size_px := clampi(int(board_view.cell_size * 0.9 * scale_mult), 14, 40)
	var l := _make_label(size_px)
	l.text = text
	l.add_theme_color_override(&"font_color", color)
	var y_clamped := clampi(y, sim.board.hidden_rows, sim.board.height - 1)
	var global_pos := board_view.cell_center_global(clampi(x, 0, sim.board.width - 1), y_clamped)
	var local := get_global_transform().affine_inverse() * global_pos
	l.reset_size()
	l.position = local - l.size * 0.5
	# keep inside the board horizontally
	var bl := get_global_transform().affine_inverse() * (board_view.get_global_transform() * board_view.board_origin)
	var bw := board_view.board_pixel_size().x
	l.position.x = clampf(l.position.x, bl.x, bl.x + bw - l.size.x)
	l.pivot_offset = l.size * 0.5
	l.scale = Vector2.ONE * 0.6
	var t := create_tween().set_parallel(true)
	t.tween_property(l, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "position:y", l.position.y - board_view.cell_size * 1.5, callout_time)
	t.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(callout_time - 0.35)
	t.chain().tween_callback(l.queue_free)


func _make_label(font_size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override(&"font_size", font_size)
	l.add_theme_color_override(&"font_outline_color", Color(0.02, 0.03, 0.06, 0.95))
	l.add_theme_constant_override(&"outline_size", maxi(4, font_size / 4))
	add_child(l)
	return l
