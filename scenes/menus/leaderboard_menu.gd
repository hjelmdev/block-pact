extends MenuPage

var _mode: OptionButton
var _list: VBoxContainer
var _modes: Array[GameModeConfig] = []


func _build() -> void:
	_modes = MatchFactory.all_modes().filter(func(m): return m.leaderboard_enabled)
	_mode = OptionButton.new()
	for m in _modes:
		_mode.add_item(m.display_name)
	_mode.item_selected.connect(func(_i): _load())
	add_row(tr("LEADERBOARD_MODE"), _mode)
	_list = VBoxContainer.new()
	content.add_child(_list)
	_load()


func _load() -> void:
	for c in _list.get_children():
		c.queue_free()
	if not Auth.is_available():
		_info(tr("LEADERBOARD_OFFLINE"))
		return
	_info(tr("COMMON_LOADING"))
	var rows: Array = await Progress.fetch_leaderboard(_modes[_mode.selected].mode_id)
	for c in _list.get_children():
		c.queue_free()
	if rows.is_empty():
		_info(tr("LEADERBOARD_EMPTY"))
		return
	for i in rows.size():
		var r: Dictionary = rows[i]
		var row := HBoxContainer.new()
		var a := Label.new()
		a.text = "%d. %s" % [i + 1, r.get("nickname", "?")]
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := Label.new()
		b.text = str(r.get("score", 0))
		row.add_child(a)
		row.add_child(b)
		_list.add_child(row)


func _info(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_list.add_child(l)
