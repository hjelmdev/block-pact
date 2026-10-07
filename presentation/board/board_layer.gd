class_name BoardLayer
extends Control
## One drawing layer of a BoardView. Exists so each layer can have its own
## material (tint shader / additive glow) while BoardView owns the logic.

enum Kind { CELLS, OVERLAY, GLOW }

@export var kind: Kind = Kind.CELLS


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _draw() -> void:
	var view := get_parent() as BoardView
	if view == null:
		return
	match kind:
		Kind.CELLS:
			view.draw_cells_layer(self)
		Kind.OVERLAY:
			view.draw_overlay_layer(self)
		Kind.GLOW:
			view.draw_glow_layer(self)
