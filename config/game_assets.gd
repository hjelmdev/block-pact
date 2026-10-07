class_name GameAssets
extends Resource
## The single place that says which art / audio / UI theme the game uses.
## To restyle the whole game, point these at new resources (or make a new
## GameAssets .tres and change Assets.CONFIG_PATH). No scene scripts change.

@export var block_skin: BlockSkin
@export var player_palette: PlayerPalette
@export var sound_library: SoundLibrary
@export var ui_theme: Theme
## Icons used by touch controls and HUD buttons, keyed by name
## (left, right, down, hard_drop, rotate_cw, rotate_ccw, hold, pause).
@export var icons: Dictionary = {}
@export var menu_background_color: Color = Color(0.035, 0.04, 0.065)
@export var accent_color: Color = Color(0.35, 0.85, 1.0)


func icon(icon_name: StringName) -> Texture2D:
	return icons.get(icon_name)
