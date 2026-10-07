class_name MenuPage
extends Control
## Small base class for the simple menu pages (settings, account …):
## shared helpers to add labeled rows to %Content and a Back button.

@onready var content: VBoxContainer = %Content
@onready var back_button: Button = %BackButton


func _ready() -> void:
	back_button.pressed.connect(_on_back)
	_build()
	back_button.grab_focus()


func _build() -> void:
	pass


func _on_back() -> void:
	AudioManager.play(Sfx.UI_BACK)
	Router.goto(&"main_menu")


func add_label(text: String, size := 14, color := Color(0.85, 0.87, 0.95)) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override(&"font_size", size)
	l.add_theme_color_override(&"font_color", color)
	content.add_child(l)
	return l


func add_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size.x = 150
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.size_flags_horizontal = Control.SIZE_SHRINK_END if control is CheckButton else Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 40)
	row.add_child(l)
	row.add_child(control)
	content.add_child(row)
	return row


func add_button(text: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 46
	b.pressed.connect(func(): AudioManager.play(Sfx.UI_CLICK); callback.call())
	content.add_child(b)
	return b
