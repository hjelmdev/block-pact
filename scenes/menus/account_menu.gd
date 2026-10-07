extends MenuPage
## Guest / account status, nickname, Google & Discord login.

var _status: Label
var _name_field: TextField
var _buttons: VBoxContainer
var _error: Label


func _build() -> void:
	_status = add_label("", 16)
	var nick := TextField.new()
	nick.placeholder_text = "ACCOUNT_NICKNAME"
	nick.max_length = 16
	nick.text = Progress.display_name() if Progress.is_tracking() or GameSettings.get_value("game", "nickname", "") != "" else ""
	nick.value_committed.connect(func(v):
		if v.strip_edges() != "" and v != Progress.display_name():
			Progress.set_nickname(v))
	_name_field = nick
	add_row(tr("ACCOUNT_NICKNAME"), nick)
	_buttons = VBoxContainer.new()
	_buttons.add_theme_constant_override(&"separation", 8)
	content.add_child(_buttons)
	_error = add_label("", 13, Color(1, 0.55, 0.5))
	add_label(tr("ACCOUNT_GUEST_INFO"), 12, Color(0.6, 0.65, 0.8))
	Auth.session_changed.connect(func(_l): _refresh())
	Auth.login_failed.connect(func(msg): _error.text = msg)
	Progress.profile_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	for c in _buttons.get_children():
		c.queue_free()
	if Auth.is_logged_in():
		_status.text = tr("ACCOUNT_SIGNED_IN") % [Progress.display_name(), Auth.provider.capitalize()]
		_name_field.text = Progress.display_name()
		var out := Button.new()
		out.text = tr("ACCOUNT_LOGOUT")
		out.custom_minimum_size.y = 46
		out.pressed.connect(Auth.logout)
		_buttons.add_child(out)
		return
	_status.text = tr("ACCOUNT_GUEST")
	if not Auth.is_available():
		var l := Label.new()
		l.text = tr("ACCOUNT_NOT_CONFIGURED")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.8))
		_buttons.add_child(l)
	for p in ["google", "discord"]:
		var b := Button.new()
		b.text = tr("ACCOUNT_LOGIN_WITH") % p.capitalize()
		b.custom_minimum_size.y = 46
		b.disabled = not Auth.available_providers().has(p)
		b.pressed.connect(func(): AudioManager.play(Sfx.UI_CLICK); Auth.login_with(p))
		_buttons.add_child(b)
