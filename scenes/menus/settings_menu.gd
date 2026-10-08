extends MenuPage


func _build() -> void:
	_slider("SETTINGS_MASTER", "audio", "master")
	_slider("SETTINGS_MUSIC", "audio", "music")
	_slider("SETTINGS_SFX", "audio", "sfx")
	_check("SETTINGS_GHOST", "video", "show_ghost")
	_check("SETTINGS_PIECE_TAGS", "video", "piece_tags")
	_check("SETTINGS_SHAKE", "video", "screen_shake")
	_check("SETTINGS_PARTICLES", "video", "particles")
	_check("SETTINGS_PATTERNS", "video", "color_patterns")

	var touch := OptionButton.new()
	for opt in ["auto", "on", "off"]:
		touch.add_item(tr("SETTINGS_TOUCH_" + opt.to_upper()))
	touch.select(["auto", "on", "off"].find(GameSettings.get_value("controls", "touch_controls", "auto")))
	touch.item_selected.connect(func(i): GameSettings.set_value("controls", "touch_controls", ["auto", "on", "off"][i]))
	add_row(tr("SETTINGS_TOUCH"), touch)

	_spin("SETTINGS_DAS", "controls", "das_ticks", 1, 30)
	_spin("SETTINGS_ARR", "controls", "arr_ticks", 1, 10)

	var lang := OptionButton.new()
	var locales := ["en", "sv"]
	for l in locales:
		lang.add_item(TranslationServer.get_locale_name(l))
	var cur := TranslationServer.get_locale().substr(0, 2)
	lang.select(maxi(0, locales.find(cur)))
	lang.item_selected.connect(func(i):
		GameSettings.set_value("game", "language", locales[i])
		Router.goto(&"settings"))
	add_row(tr("SETTINGS_LANGUAGE"), lang)

	if OS.is_debug_build() and not Platform.is_web():
		add_button(tr("SETTINGS_BOT_TRAINER"), func(): Router.goto(&"bot_trainer"))


func _slider(key: String, section: String, setting: String) -> void:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = GameSettings.get_value(section, setting, 0.8)
	s.value_changed.connect(func(v): GameSettings.set_value(section, setting, v))
	s.drag_ended.connect(func(_c): AudioManager.play(Sfx.UI_CLICK))
	add_row(tr(key), s)


func _check(key: String, section: String, setting: String) -> void:
	var c := CheckButton.new()
	c.button_pressed = GameSettings.get_value(section, setting, true)
	c.toggled.connect(func(v): GameSettings.set_value(section, setting, v))
	add_row(tr(key), c)


func _spin(key: String, section: String, setting: String, lo: int, hi: int) -> void:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = GameSettings.get_value(section, setting, lo)
	s.value_changed.connect(func(v): GameSettings.set_value(section, setting, int(v)))
	add_row(tr(key), s)
