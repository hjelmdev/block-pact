extends MenuPage
## Top scores per mode and ruleset (classic / party). Readable by everyone,
## including guests; only signed-in players appear on it.

const RULESETS := ["classic", "party"]
const RULESET_LABELS := ["LEADERBOARD_CLASSIC", "LEADERBOARD_PARTY"]

var _mode: OptionButton
var _ruleset: OptionButton
var _best: Label
var _list: VBoxContainer
var _modes: Array[GameModeConfig] = []
var _loading := 0


func _build() -> void:
	_modes = MatchFactory.all_modes().filter(func(m): return m.leaderboard_enabled)
	_mode = OptionButton.new()
	for m in _modes:
		_mode.add_item(m.display_name)
	_mode.item_selected.connect(func(_i): _load())
	add_row(tr("LEADERBOARD_MODE"), _mode)
	_ruleset = OptionButton.new()
	for k in RULESET_LABELS:
		_ruleset.add_item(tr(k))
	var saved: Dictionary = MatchOptions.saved_options()
	_ruleset.select(1 if saved.get("powerups", false) or saved.get("specials", "") == "all" else 0)
	_ruleset.item_selected.connect(func(_i): _load())
	add_row(tr("LEADERBOARD_RULESET"), _ruleset)
	_best = add_label("", 13, Color(1, 0.85, 0.4))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override(&"separation", 2)
	content.add_child(_list)
	_load()


func _load() -> void:
	_loading += 1
	var my_load := _loading
	_clear()
	_best.text = ""
	if not Auth.is_available():
		_info(tr("LEADERBOARD_OFFLINE"))
		return
	_info(tr("COMMON_LOADING"))
	var mode_id := _modes[_mode.selected].mode_id
	var ruleset: String = RULESETS[maxi(_ruleset.selected, 0)]
	var rows: Array = await Progress.fetch_leaderboard(mode_id, ruleset)
	if my_load != _loading:
		return  # a newer request replaced this one
	_clear()
	if Progress.is_tracking():
		var best: int = await Progress.fetch_personal_best(mode_id, ruleset)
		if my_load != _loading:
			return
		_best.text = tr("LEADERBOARD_YOUR_BEST") % best if best > 0 else ""
	else:
		_best.text = tr("LEADERBOARD_GUEST_HINT")
	if rows.is_empty():
		_info(tr("LEADERBOARD_EMPTY"))
		return
	for i in rows.size():
		_list.add_child(_row(i + 1, rows[i]))


func _row(rank: int, r: Dictionary) -> Control:
	var mine := Progress.is_tracking() and str(r.get("user_id", "")) == Auth.user_id
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 8)
	var rank_l := Label.new()
	rank_l.text = "%d." % rank
	rank_l.custom_minimum_size.x = 32
	var name_l := Label.new()
	name_l.text = str(r.get("nickname", "?")) + ("  (" + tr("LEADERBOARD_YOU") + ")" if mine else "")
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var lines_l := Label.new()
	lines_l.text = "%d L" % int(r.get("lines", 0))
	lines_l.add_theme_color_override(&"font_color", Color(0.6, 0.65, 0.8))
	lines_l.add_theme_font_size_override(&"font_size", 12)
	var score_l := Label.new()
	score_l.text = str(int(r.get("score", 0)))
	score_l.custom_minimum_size.x = 80
	score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var gold := Color(1, 0.84, 0.3)
	if rank <= 3:
		rank_l.add_theme_color_override(&"font_color", [gold, Color(0.8, 0.82, 0.9), Color(0.85, 0.6, 0.4)][rank - 1])
	if mine:
		name_l.add_theme_color_override(&"font_color", gold)
		score_l.add_theme_color_override(&"font_color", gold)
	for c in [rank_l, name_l, lines_l, score_l]:
		row.add_child(c)
	return row


func _clear() -> void:
	for c in _list.get_children():
		c.queue_free()


func _info(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(l)
