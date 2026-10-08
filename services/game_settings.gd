extends Node
## Autoload "GameSettings": per-device user preferences (audio, visuals,
## controls, language). Stored in user://settings.cfg (IndexedDB on web).
## These are NOT account progress – guests have settings too.

signal setting_changed(section: String, key: String, value: Variant)

const PATH := "user://settings.cfg"
const DEFAULTS := {
	"audio": {"master": 0.8, "music": 0.6, "sfx": 0.8},
	"video": {"screen_shake": true, "show_ghost": true, "color_patterns": false, "particles": true, "piece_tags": true},
	"controls": {"das_ticks": 10, "arr_ticks": 2, "touch_controls": "auto", "touch_scheme": "gestures", "swipe_sensitivity": 0.9},
	"game": {"language": "", "nickname": ""},
}

var _cfg := ConfigFile.new()


func _ready() -> void:
	_cfg.load(PATH)
	var lang: String = get_value("game", "language", "")
	if lang != "":
		TranslationServer.set_locale(lang)


func get_value(section: String, key: String, fallback: Variant = null) -> Variant:
	var def: Variant = DEFAULTS.get(section, {}).get(key, fallback)
	return _cfg.get_value(section, key, def)


func set_value(section: String, key: String, value: Variant, save_now := true) -> void:
	_cfg.set_value(section, key, value)
	if section == "game" and key == "language" and value != "":
		TranslationServer.set_locale(value)
	setting_changed.emit(section, key, value)
	if save_now:
		save()


func save() -> void:
	_cfg.save(PATH)
