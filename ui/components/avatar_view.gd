class_name AvatarView
extends Control
## A player's avatar: pixel art tinted with the player's color on a dark tile.

@export var tile_color: Color = Color(0.05, 0.06, 0.1, 0.9)

var _texture: Texture2D
var _color: Color = Color.WHITE


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func make(avatar_id: String, color: Color, px := 28.0) -> AvatarView:
	var v := AvatarView.new()
	v.custom_minimum_size = Vector2(px, px)
	v.set_avatar(avatar_id, color)
	return v


func set_avatar(avatar_id: String, color: Color) -> void:
	_texture = Assets.avatar(avatar_id)
	_color = color.lightened(0.15)
	queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	var r := Rect2((size - Vector2(s, s)) * 0.5, Vector2(s, s))
	draw_rect(r, tile_color, true)
	if _texture:
		draw_texture_rect(_texture, r, false, _color)
