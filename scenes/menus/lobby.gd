extends Control
## Local match setup: choose mode, seats (humans / bots), then start.
## Builds a MatchSetup – the same object an online lobby will produce.

const SLOT_ROW := preload("res://scenes/menus/slot_row.tscn")

@onready var _mode: OptionButton = %ModeOption
@onready var _desc: Label = %ModeDescription
@onready var _slots: VBoxContainer = %Slots
@onready var _add_bot: Button = %AddBotButton
@onready var _add_human: Button = %AddHumanButton
@onready var _start: Button = %StartButton
@onready var _back: Button = %BackButton
@onready var _info: Label = %InfoLabel
@onready var _options: MatchOptions = %MatchOptions

var _modes: Array[GameModeConfig] = []
var _seats: Array[PlayerSlot] = []


func _ready() -> void:
	_modes = MatchFactory.all_modes().filter(func(m: GameModeConfig): return m.max_players > 1)
	for i in _modes.size():
		_mode.add_item(_modes[i].display_name, i)
	_mode.item_selected.connect(func(_i): _on_mode_changed())
	_add_bot.pressed.connect(func(): _add_seat(PlayerSlot.Kind.BOT))
	_add_human.pressed.connect(func(): _add_seat(PlayerSlot.Kind.LOCAL_HUMAN))
	_start.pressed.connect(_on_start)
	_back.pressed.connect(func(): AudioManager.play(Sfx.UI_BACK); Router.goto(&"main_menu"))

	var preset: String = Router.params.get("preset", "vs_bots")
	_seats.append(MatchFactory.human_slot(0))
	if preset == "local":
		_seats[0].input_device = &"kb_left"
		var p2 := MatchFactory.human_slot(1, &"kb_right")
		_seats.append(p2)
	else:
		_seats.append(MatchFactory.bot_slot(1, &"normal"))
	_mode.select(0)
	_on_mode_changed()
	_start.grab_focus()


func _current_mode() -> GameModeConfig:
	return _modes[maxi(_mode.selected, 0)]


func _on_mode_changed() -> void:
	var m := _current_mode()
	_desc.text = m.description
	while _seats.size() > m.max_players:
		_seats.pop_back()
	while _seats.size() < m.min_players:
		_seats.append(MatchFactory.bot_slot(_seats.size()))
	_rebuild()


func _add_seat(kind: PlayerSlot.Kind) -> void:
	AudioManager.play(Sfx.UI_CLICK)
	if _seats.size() >= _current_mode().max_players:
		return
	var i := _seats.size()
	if kind == PlayerSlot.Kind.BOT:
		_seats.append(MatchFactory.bot_slot(i))
	else:
		# A second keyboard player splits the keyboard into left/right halves.
		for s in _seats:
			if s.kind == PlayerSlot.Kind.LOCAL_HUMAN and s.input_device == &"kb_solo":
				s.input_device = &"kb_left"
		var used := []
		for s in _seats:
			if s.kind == PlayerSlot.Kind.LOCAL_HUMAN:
				used.append(s.input_device)
		var device := ControlSchemes.default_device()
		for d in ControlSchemes.available_devices():
			if d.id != &"kb_solo" and not used.has(d.id):
				device = d.id
				break
		_seats.append(MatchFactory.human_slot(i, device))
	_rebuild()


func _remove_seat(row: SlotRow) -> void:
	_seats.erase(row.slot)
	_rebuild()


func _rebuild() -> void:
	for c in _slots.get_children():
		c.queue_free()
	var m := _current_mode()
	var palette := Assets.palette()
	for i in _seats.size():
		_seats[i].color_index = i
		var row: SlotRow = SLOT_ROW.instantiate()
		_slots.add_child(row)
		row.set_slot(_seats[i], palette.get_color(i))
		row.set_removable(_seats.size() > m.min_players)
		row.remove_requested.connect(_remove_seat)
		row.changed.connect(_validate)
	_add_bot.disabled = _seats.size() >= m.max_players
	_add_human.disabled = _seats.size() >= m.max_players
	_validate()


func _validate() -> void:
	var devices := {}
	var conflict := false
	for s in _seats:
		if s.kind == PlayerSlot.Kind.LOCAL_HUMAN:
			if devices.has(s.input_device):
				conflict = true
			devices[s.input_device] = true
	# "Keyboard" (solo) uses both halves of the keyboard.
	if devices.has(&"kb_solo") and (devices.has(&"kb_left") or devices.has(&"kb_right")):
		conflict = true
	var size := _current_mode().board_size_for(_seats.size())
	_info.text = tr("LOBBY_BOARD_INFO") % [size.x, size.y]
	if conflict:
		_info.text += "\n" + tr("LOBBY_DEVICE_CONFLICT")
	_start.disabled = conflict


func _on_start() -> void:
	AudioManager.play(Sfx.UI_CLICK)
	var setup := MatchSetup.new()
	setup.mode = _current_mode()
	var slots: Array[PlayerSlot] = []
	for s in _seats:
		slots.append(s.duplicate())
	setup.slots = slots
	setup.rule_overrides = MatchOptions.to_rule_overrides(_options.get_options())
	Router.goto(&"match", {"setup": setup})
