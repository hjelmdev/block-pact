class_name MatchOptions
extends VBoxContainer
## Lobby rule options shared by the local lobby and the online lobby:
## piece collision, special blocks and powerups. Produces a plain Dictionary
## (network-safe) that [method to_rule_overrides] turns into
## MatchSetup.rule_overrides.

signal options_changed(options: Dictionary)

const SPECIAL_PRESETS := ["", "all", "off"]
const SPECIAL_LABELS := ["LOBBY_SPECIALS_MODE", "LOBBY_SPECIALS_ALL", "LOBBY_SPECIALS_OFF"]

var _collision: CheckButton
var _powerups: CheckButton
var _specials: OptionButton
var _suppress := false


func _ready() -> void:
	add_theme_constant_override(&"separation", 4)
	_collision = _check("LOBBY_COLLISION")
	_powerups = _check("LOBBY_POWERUPS")
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = tr("LOBBY_SPECIALS")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_specials = OptionButton.new()
	_specials.custom_minimum_size = Vector2(0, 40)
	for i in SPECIAL_LABELS.size():
		_specials.add_item(tr(SPECIAL_LABELS[i]), i)
	_specials.item_selected.connect(func(_i): _emit())
	row.add_child(l)
	row.add_child(_specials)
	add_child(row)
	set_options(saved_options())


## Options last used on this device (stored in GameSettings).
static func saved_options() -> Dictionary:
	return {
		"collision": GameSettings.get_value("game", "piece_collision", false),
		"powerups": GameSettings.get_value("game", "powerups", true),
		"specials": GameSettings.get_value("game", "specials", "all"),
	}


static func save_options(o: Dictionary) -> void:
	GameSettings.set_value("game", "piece_collision", o.get("collision", false))
	GameSettings.set_value("game", "powerups", o.get("powerups", true))
	GameSettings.set_value("game", "specials", o.get("specials", "all"))


static func to_rule_overrides(o: Dictionary) -> Dictionary:
	return {
		"active_piece_collision": bool(o.get("collision", false)),
		"powerups_enabled": bool(o.get("powerups", false)),
		"special_preset": String(o.get("specials", "")),
	}


func get_options() -> Dictionary:
	return {
		"collision": _collision.button_pressed,
		"powerups": _powerups.button_pressed,
		"specials": SPECIAL_PRESETS[maxi(_specials.selected, 0)],
	}


func set_options(o: Dictionary) -> void:
	_suppress = true
	_collision.set_pressed_no_signal(o.get("collision", false))
	_powerups.set_pressed_no_signal(o.get("powerups", false))
	_specials.select(maxi(SPECIAL_PRESETS.find(String(o.get("specials", ""))), 0))
	_suppress = false


func set_editable(editable: bool) -> void:
	_collision.disabled = not editable
	_powerups.disabled = not editable
	_specials.disabled = not editable


func _check(text_key: String) -> CheckButton:
	var c := CheckButton.new()
	c.text = tr(text_key)
	c.custom_minimum_size = Vector2(0, 40)
	c.toggled.connect(func(_v): _emit())
	add_child(c)
	return c


func _emit() -> void:
	if _suppress:
		return
	var o := get_options()
	save_options(o)
	options_changed.emit(o)
