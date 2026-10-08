extends MenuPage
## Room lobby for online play. The host edits mode/seats and starts; clients
## see the same view read-only. Everything shown comes from Net.lobby.

var _title: Label
var _mode: OptionButton
var _options: MatchOptions
var _players: VBoxContainer
var _add_bot: Button
var _start: Button
var _status: Label
var _modes: Array[GameModeConfig] = []


func _build() -> void:
	_title = %Title
	_title.text = tr("ONLINE_ROOM") % Net.room_code
	add_label(tr("ONLINE_SHARE_CODE"), 12, Color(0.6, 0.65, 0.8))

	_modes = MatchFactory.all_modes().filter(func(m: GameModeConfig): return m.max_players > 1)
	_mode = OptionButton.new()
	for i in _modes.size():
		_mode.add_item(_modes[i].display_name, i)
	_mode.item_selected.connect(func(i): Net.host_set_mode(String(_modes[i].mode_id)))
	add_row(tr("LEADERBOARD_MODE"), _mode)

	_options = MatchOptions.new()
	content.add_child(_options)
	_options.options_changed.connect(func(o): Net.host_set_options(o))

	_players = VBoxContainer.new()
	_players.add_theme_constant_override(&"separation", 6)
	content.add_child(_players)

	_add_bot = add_button(tr("LOBBY_ADD_BOT"), func(): Net.host_add_bot("normal"))
	_status = add_label("", 13, Color(0.7, 0.8, 1.0))
	_start = add_button(tr("LOBBY_START"), func(): Net.host_start())

	Net.lobby_changed.connect(_refresh)
	Net.status.connect(_on_status)
	Net.match_start.connect(_on_match_start)
	Net.state_changed.connect(_on_state)
	_refresh()


func _refresh() -> void:
	var lobby := Net.lobby
	var host := Net.is_host
	_mode.disabled = not host
	_options.set_editable(host)
	_add_bot.visible = host
	_start.visible = host
	if lobby.is_empty():
		_status.text = tr("ONLINE_CONNECTING")
		return
	for i in _modes.size():
		if String(_modes[i].mode_id) == lobby.get("mode_id", ""):
			_mode.select(i)
	_options.set_options(lobby.get("options", {}))
	for c in _players.get_children():
		c.queue_free()
	var palette := Assets.palette()
	var slots: Array = lobby.get("slots", [])
	for i in slots.size():
		var s: Dictionary = slots[i]
		var row := HBoxContainer.new()
		row.add_theme_constant_override(&"separation", 8)
		var sw := ColorRect.new()
		sw.color = palette.get_color(i)
		sw.custom_minimum_size = Vector2(10, 36)
		var name_l := Label.new()
		name_l.text = s.name
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var tag := Label.new()
		tag.add_theme_font_size_override(&"font_size", 12)
		tag.add_theme_color_override(&"font_color", Color(0.65, 0.7, 0.85))
		if s.kind == Net.HUMAN:
			var p: Dictionary = Net.peers.get(s.peer_id, {})
			if s.peer_id == 1:
				tag.text = tr("ONLINE_TAG_HOST")
			elif not p.get("connected", false):
				tag.text = tr("ONLINE_CONNECTING")
			else:
				tag.text = "%d ms" % int(p.get("ping_ms", 0))
			if s.peer_id == Net.my_peer_id:
				name_l.text += " (" + tr("ONLINE_TAG_YOU") + ")"
		else:
			tag.text = tr("LOBBY_BOT")
		row.add_child(sw)
		row.add_child(name_l)
		row.add_child(tag)
		if host and i > 0:
			var x := Button.new()
			x.text = "X"
			x.custom_minimum_size = Vector2(40, 36)
			x.pressed.connect(func(): Net.host_remove_slot(i))
			row.add_child(x)
		_players.add_child(row)
	if host:
		_start.disabled = not Net.host_can_start()
		_status.text = tr("ONLINE_HOST_HINT") if slots.size() < 2 else ""
	else:
		_status.text = tr("ONLINE_WAITING_HOST")


func _on_status(t: String, err: bool) -> void:
	_status.text = t
	_status.add_theme_color_override(&"font_color", Color(1, 0.55, 0.5) if err else Color(0.7, 0.8, 1.0))


func _on_match_start(setup: MatchSetup, delay: int) -> void:
	Router.goto(&"match", {"setup": setup, "net_delay": delay})


func _on_state(s: int) -> void:
	if s == Net.State.OFFLINE or s == Net.State.BROWSING:
		Router.goto(&"online")


func _on_back() -> void:
	Net.leave_room()
	AudioManager.play(Sfx.UI_BACK)
	Router.goto(&"online")
