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
var _chat_log: RichTextLabel
var _chat_input: TextField
var _known_slots: Dictionary = {}


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
	_build_chat()

	Net.chat_received.connect(func(_e): _render_chat())
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
		var sw := AvatarView.make(str(s.get("avatar", "")), palette.get_color(i), 34)
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
		if s.kind == Net.HUMAN and s.peer_id != Net.my_peer_id:
			var key := Net.key_for_peer(s.peer_id)
			if key != "":
				var mute := Button.new()
				mute.toggle_mode = true
				mute.button_pressed = Net.muted.has(key)
				mute.text = tr("CHAT_UNMUTE") if mute.button_pressed else tr("CHAT_MUTE")
				mute.custom_minimum_size = Vector2(0, 36)
				mute.toggled.connect(func(on):
					Net.set_muted(key, on)
					mute.text = tr("CHAT_UNMUTE") if on else tr("CHAT_MUTE"))
				row.add_child(mute)
		if host and i > 0:
			var x := Button.new()
			x.text = "X"
			x.custom_minimum_size = Vector2(40, 36)
			x.pressed.connect(func(): Net.host_remove_slot(i))
			row.add_child(x)
		_players.add_child(row)
	_note_joins(slots)
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


# --------------------------------------------------------------------------
# Chat

func _build_chat() -> void:
	add_label(tr("CHAT_TITLE"), 14, Color(0.7, 0.75, 0.9))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.fit_content = false
	_chat_log.custom_minimum_size = Vector2(0, 130)
	_chat_log.add_theme_font_size_override(&"normal_font_size", 13)
	_chat_log.add_theme_font_size_override(&"bold_font_size", 13)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.25)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(6)
	_chat_log.add_theme_stylebox_override(&"normal", sb)
	content.add_child(_chat_log)
	var row := HBoxContainer.new()
	_chat_input = TextField.new()
	_chat_input.placeholder_text = "CHAT_PLACEHOLDER"
	_chat_input.max_length = ChatFilter.MAX_LENGTH
	_chat_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chat_input.text_submitted.connect(func(_t): _send_chat())
	if Platform.is_web() and Platform.is_mobile():
		_chat_input.value_committed.connect(func(_t): _send_chat())
	var send := Button.new()
	send.text = tr("CHAT_SEND")
	send.custom_minimum_size = Vector2(72, 44)
	send.pressed.connect(_send_chat)
	row.add_child(_chat_input)
	row.add_child(send)
	content.add_child(row)
	_render_chat()


func _send_chat() -> void:
	var t := _chat_input.text
	if t.strip_edges() == "":
		return
	if Net.send_chat(t):
		_chat_input.text = ""
		AudioManager.play(Sfx.UI_CLICK)


func _render_chat() -> void:
	if _chat_log == null:
		return
	var palette := Assets.palette()
	var color_of := {}
	var slots: Array = Net.lobby.get("slots", [])
	for i in slots.size():
		if slots[i].kind == Net.HUMAN:
			color_of[Net.key_for_peer(slots[i].peer_id) if slots[i].peer_id != Net.my_peer_id else Net.my_key] = palette.get_color(i)
	_chat_log.clear()
	for e: Dictionary in Net.chat_log:
		if e.system:
			_chat_log.append_text("[color=#8890aa][i]%s[/i][/color]\n" % e.text)
			continue
		var col: Color = color_of.get(e.key, Color(0.8, 0.85, 1.0))
		_chat_log.append_text("[color=#%s][b]%s:[/b][/color] %s\n" % [col.lightened(0.25).to_html(false), ChatFilter.clean(e.name), e.text])


## Announce players joining / leaving in the chat.
func _note_joins(slots: Array) -> void:
	var now := {}
	for s: Dictionary in slots:
		if s.kind == Net.HUMAN:
			now[s.peer_id] = s.name
	if not _known_slots.is_empty():
		for pid in now:
			if not _known_slots.has(pid):
				Net.system_chat(tr("CHAT_JOINED") % now[pid])
		for pid in _known_slots:
			if not now.has(pid):
				Net.system_chat(tr("CHAT_LEFT") % _known_slots[pid])
	_known_slots = now
