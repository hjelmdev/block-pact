class_name TouchButton
extends Control
## One on-screen control. Visuals come from Assets icons; the parent
## TouchControls does the multi-touch tracking.

@export var command: int = InputCommand.LEFT
@export var icon_name: StringName = &"left"
@export var bg_color: Color = Color(1, 1, 1, 0.08)
@export var pressed_color: Color = Color(1, 1, 1, 0.28)
@export var icon_color: Color = Color(1, 1, 1, 0.85)

var pressed: bool = false:
	set(v):
		pressed = v
		queue_redraw()

var _icon: Texture2D


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon = Assets.icon(icon_name)
	resized.connect(queue_redraw)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-3)
	var sb := StyleBoxFlat.new()
	sb.bg_color = pressed_color if pressed else bg_color
	sb.set_corner_radius_all(int(minf(r.size.x, r.size.y) * 0.25))
	sb.border_color = Color(1, 1, 1, 0.18)
	sb.set_border_width_all(2)
	draw_style_box(sb, r)
	if _icon:
		var s := minf(r.size.x, r.size.y) * 0.55
		var ir := Rect2(r.get_center() - Vector2(s, s) * 0.5, Vector2(s, s))
		draw_texture_rect(_icon, ir, false, icon_color)
