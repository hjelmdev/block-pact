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

var slot: PlayerSlot
var _devices: Array = []
var _bot_ids: Array[StringName] = []


func _ready() -> void:
	_kind.clear()
	_kind.add_item(tr("LOBBY_HUMAN"), PlayerSlot.Kind.LOCAL_HUMAN)
	_kind.add_item(tr("LOBBY_BOT"), PlayerSlot.Kind.BOT)
	_kind.item_selected.connect(func(_i): _on_kind_changed())
	_detail.item_selected.connect(func(_i): _on_detail_changed())
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


func set_removable(v: bool) -> void:
	_remove.disabled = not v


func _on_kind_changed() -> void:
	slot.kind = _kind.get_selected_id() as PlayerSlot.Kind
	if slot.kind == PlayerSlot.Kind.BOT:
		slot.display_name = "%s-bot" % MatchFactory.BOT_NAMES[slot.color_index % MatchFactory.BOT_NAMES.size()]
	else:
		slot.display_name = "Player %d" % (slot.color_index + 1)
	_name.text = slot.display_name
	_fill_detail()
	changed.emit()


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
