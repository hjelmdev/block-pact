class_name SlotRow
extends HBoxContainer
## One seat in the lobby: human (with input device) or bot (with difficulty).

signal remove_requested(row: SlotRow)
signal changed()

@onready var _swatch: ColorRect = %Swatch
@onready var _kind: OptionButton = %KindOption
@onready var _detail: OptionButton = %DetailOption
@onready var _name: TextField = %NameField
@onready var _remove: Button = %RemoveButton
@onready var _personality: OptionButton = %PersonalityOption

var slot: PlayerSlot
var _devices: Array = []
var _bot_ids: Array[StringName] = []
var _personality_ids: Array[StringName] = []


func _ready() -> void:
	_kind.clear()
	_kind.add_item(tr("LOBBY_HUMAN"), PlayerSlot.Kind.LOCAL_HUMAN)
	_kind.add_item(tr("LOBBY_BOT"), PlayerSlot.Kind.BOT)
	_kind.item_selected.connect(func(_i): _on_kind_changed())
	_detail.item_selected.connect(func(_i): _on_detail_changed())
	_personality_ids = BotPersonality.list_ids()
	for i in _personality_ids.size():
		var p := BotPersonality.load_personality(_personality_ids[i])
		_personality.add_item(tr(p.name_key) if p else String(_personality_ids[i]), i)
		if p and p.description_key != "":
			_personality.set_item_tooltip(i, tr(p.description_key))
	_personality.item_selected.connect(func(i):
		slot.bot_personality_id = _personality_ids[i]
		slot.display_name = MatchFactory.bot_name(slot.color_index, slot.bot_personality_id)
		changed.emit())
	_name.value_committed.connect(func(v):
		if slot:
			slot.display_name = v if v.strip_edges() != "" else slot.display_name
		changed.emit())
	_remove.pressed.connect(func(): remove_requested.emit(self))


func set_slot(p_slot: PlayerSlot, color: Color) -> void:
	slot = p_slot
	_swatch.color = color
	_kind.select(_kind.get_item_index(slot.kind))
	_name.text = slot.display_name
	_fill_detail()
	_update_kind_ui()


func set_removable(v: bool) -> void:
	_remove.disabled = not v


func _on_kind_changed() -> void:
	slot.kind = _kind.get_selected_id() as PlayerSlot.Kind
	if slot.kind == PlayerSlot.Kind.BOT:
		if slot.bot_personality_id == &"":
			slot.bot_personality_id = _personality_ids[maxi(slot.color_index - 1, 0) % _personality_ids.size()]
		slot.display_name = MatchFactory.bot_name(slot.color_index, slot.bot_personality_id)
	else:
		slot.display_name = "Player %d" % (slot.color_index + 1)
	_name.text = slot.display_name
	_fill_detail()
	_update_kind_ui()
	changed.emit()


## Bots pick a personality instead of typing a name.
func _update_kind_ui() -> void:
	var bot := slot.kind == PlayerSlot.Kind.BOT
	_name.visible = not bot
	_personality.visible = bot
	if bot:
		_personality.select(maxi(_personality_ids.find(slot.bot_personality_id), 0))


func _fill_detail() -> void:
	_detail.clear()
	if slot.kind == PlayerSlot.Kind.BOT:
		_bot_ids = BotProfile.list_shipped_ids()
		for i in _bot_ids.size():
			_detail.add_item(BotProfile.load_profile(_bot_ids[i]).display_name, i)
			if _bot_ids[i] == slot.bot_profile_id:
				_detail.select(i)
	else:
		_devices = ControlSchemes.available_devices()
		for i in _devices.size():
			_detail.add_item(_devices[i].name, i)
			if _devices[i].id == slot.input_device:
				_detail.select(i)
		if _detail.selected < 0 and not _devices.is_empty():
			_detail.select(0)
			slot.input_device = _devices[0].id


func _on_detail_changed() -> void:
	var i := _detail.selected
	if slot.kind == PlayerSlot.Kind.BOT:
		slot.bot_profile_id = _bot_ids[i]
	else:
		slot.input_device = _devices[i].id
	changed.emit()
