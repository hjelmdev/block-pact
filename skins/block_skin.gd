class_name BlockSkin
extends Resource
## Everything about how blocks LOOK. Swap this resource to restyle the game.
##
## Default pipeline: [member cell_texture] is a grayscale "shade map"
## (0 = dark edge, 0.5 = player color, 1 = highlight) that
## [member cell_material] tints with the owner's color. A full-color sprite
## sheet works too: set [member tint_with_shader] = false and the texture is
## drawn with plain modulate (or set modulate_cells = false to draw as-is).

@export var skin_name: String = "Default Pixel Glow"
## Native pixel size of one cell (used for pixel-perfect scaling).
@export var cell_pixels: int = 16

@export_group("Cells")
@export var cell_texture: Texture2D
@export var tint_with_shader: bool = true
@export var cell_material: ShaderMaterial
@export var modulate_cells: bool = true
## Active (falling) pieces are drawn slightly brighter.
@export var active_brightness: float = 1.15

@export_group("Board")
@export var board_background: Color = Color(0.055, 0.06, 0.09)
@export var board_border: Color = Color(0.25, 0.27, 0.38)
@export var grid_texture: Texture2D
@export var grid_tint: Color = Color(1, 1, 1, 1)
@export var spawn_zone_tint: Color = Color(1, 1, 1, 0.03)

@export_group("Ghost")
@export var ghost_texture: Texture2D
@export var ghost_alpha: float = 0.45

@export_group("Glow")
@export var glow_texture: Texture2D
## Glow sprite size relative to a cell.
@export var glow_scale: float = 2.2
@export var glow_strength_locked: float = 0.10
@export var glow_strength_active: float = 0.32
@export var glow_strength_special: float = 0.75
@export var glow_pulse_speed: float = 4.0

@export_group("Specials")
## SpecialBlockType.key -> Texture2D overlay (e.g. &"x5": special_x5.png)
@export var special_overlays: Dictionary = {}

@export_group("Effects")
@export var particle_texture: Texture2D
@export var line_flash_color: Color = Color(1, 1, 1, 0.85)


func get_special_overlay(key: StringName) -> Texture2D:
	return special_overlays.get(key)
