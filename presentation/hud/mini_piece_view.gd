class_name MiniPieceView
extends Control
## Draws a single PieceShape (next / hold preview) using the active skin.

@export var cell_px: float = 10.0

var shape: PieceShape
var color: Color = Color.WHITE
var dimmed: bool = false
var skin: BlockSkin


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if skin == null:
		skin = Assets.skin()
	material = skin.cell_material if skin.tint_with_shader else null
	custom_minimum_size = Vector2(cell_px * 4, cell_px * 2.5)


func set_piece(p_shape: PieceShape, p_color: Color, p_dimmed := false) -> void:
	shape = p_shape
	color = p_color
	dimmed = p_dimmed
	queue_redraw()


func _draw() -> void:
	if shape == null or skin == null or skin.cell_texture == null:
		return
	var cells := shape.get_cells(0)
	var min_c := Vector2i(99, 99)
	var max_c := Vector2i(-99, -99)
	for c in cells:
		min_c = Vector2i(mini(min_c.x, c.x), mini(min_c.y, c.y))
		max_c = Vector2i(maxi(max_c.x, c.x), maxi(max_c.y, c.y))
	var dims := Vector2(max_c - min_c + Vector2i.ONE)
	var cs := minf(cell_px, minf(size.x / dims.x, size.y / dims.y))
	var origin := (size - dims * cs) * 0.5
	var col := color
	if dimmed:
		col = col.darkened(0.5)
	for c in cells:
		var r := Rect2(origin + Vector2(c - min_c) * cs, Vector2(cs, cs))
		draw_texture_rect(skin.cell_texture, r, false, col)
