extends MenuPage
## Online: create a room (public/private), join by code, or pick a public
## room from the live list (Supabase Realtime Presence).

var _name_field: TextField
var _code_field: TextField
var _rooms_box: VBoxContainer
var _status: Label


func _build() -> void:
	if not Net.is_available():
		add_label(tr("ONLINE_NOT_CONFIGURED"), 15)
		return
	if not Net.webrtc_available():
		add_label(tr("ONLINE_NO_WEBRTC"), 14, Color(1, 0.6, 0.5))

	_name_field = TextField.new()
	_name_field.placeholder_text = "ACCOUNT_NICKNAME"
	_name_field.max_length = 16
	_name_field.text = Progress.display_name()
	add_row(tr("ACCOUNT_NICKNAME"), _name_field)

	var create_row := HBoxContainer.new()
	create_row.add_theme_constant_override(&"separation", 8)
	content.add_child(create_row)
	for public in [true, false]:
		var b := Button.new()
		b.text = tr("ONLINE_CREATE_PUBLIC") if public else tr("ONLINE_CREATE_PRIVATE")
		b.custom_minimum_size.y = 46
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			AudioManager.play(Sfx.UI_CLICK)
			Net.host_room(public, _player_name()))
		create_row.add_child(b)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override(&"separation", 8)
	content.add_child(join_row)
	_code_field = TextField.new()
	_code_field.placeholder_text = "ONLINE_CODE"
	_code_field.max_length = 6
	_code_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_code_field.text_submitted.connect(func(_t): _join(_code_field.text))
	join_row.add_child(_code_field)
	var join := Button.new()
	join.text = tr("ONLINE_JOIN")
	join.custom_minimum_size = Vector2(110, 46)
	join.pressed.connect(func(): _join(_code_field.text))
	join_row.add_child(join)

	_status = add_label("", 13, Color(0.7, 0.8, 1.0))
	add_label(tr("ONLINE_PUBLIC_ROOMS"), 16)
	_rooms_box = VBoxContainer.new()
	_rooms_box.add_theme_constant_override(&"separation", 6)
	content.add_child(_rooms_box)
	add_label(tr("ONLINE_HELP"), 12, Color(0.6, 0.65, 0.8))

	Net.rooms_changed.connect(_show_rooms)
	Net.status.connect(_on_status)
	Net.state_changed.connect(_on_state)
	Net.start_browsing()
	_show_rooms(Net.rooms)


func _player_name() -> String:
	var n := _name_field.text.strip_edges()
	if n == "":
		n = Progress.display_name()
	if n != GameSettings.get_value("game", "nickname", ""):
		GameSettings.set_value("game", "nickname", n)
	return n


func _join(code: String) -> void:
	code = NetProtocol.normalize_code(code)
	if code.length() < 4:
		_on_status(tr("ONLINE_ENTER_CODE"), true)
		return
	AudioManager.play(Sfx.UI_CLICK)
	Net.join_room(code, _player_name())


func _show_rooms(rooms: Array) -> void:
	if _rooms_box == null:
		return
	for c in _rooms_box.get_children():
		c.queue_free()
	if rooms.is_empty():
		var l := Label.new()
		l.text = tr("ONLINE_NO_ROOMS")
		l.add_theme_color_override(&"font_color", Color(0.6, 0.62, 0.75))
		_rooms_box.add_child(l)
		return
	for r: Dictionary in rooms:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "%s · %s · %d/%d" % [r.get("host", "?"), r.get("mode", ""), int(r.get("players", 0)), int(r.get("max", 0))]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var b := Button.new()
		b.text = tr("ONLINE_JOIN")
		b.custom_minimum_size = Vector2(90, 40)
		b.disabled = int(r.get("players", 0)) >= int(r.get("max", 8))
		var code: String = r.get("code", "")
		b.pressed.connect(func(): _join(code))
		row.add_child(l)
		row.add_child(b)
		_rooms_box.add_child(row)


func _on_status(text: String, is_error: bool) -> void:
	if _status:
		_status.text = text
		_status.add_theme_color_override(&"font_color", Color(1, 0.55, 0.5) if is_error else Color(0.7, 0.8, 1.0))


func _on_state(s: int) -> void:
	if s == Net.State.HOSTING or s == Net.State.IN_ROOM:
		Router.goto(&"online_lobby")


func _on_back() -> void:
	Net.stop_browsing()
	Net.leave_room()
	super()
