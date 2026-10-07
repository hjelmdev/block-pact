extends Node
## Autoload "Assets": loads the active GameAssets configuration and hands
## out skins, palettes, sounds and icons. Scenes ask Assets instead of
## preloading art, which keeps every asset swappable from one resource.

signal assets_changed()

const CONFIG_PATH := "res://config/game_assets.tres"

var config: GameAssets


func _ready() -> void:
	if ResourceLoader.exists(CONFIG_PATH):
		config = load(CONFIG_PATH)
	if config == null:
		config = GameAssets.new()
	_apply_theme()


func set_config(new_config: GameAssets) -> void:
	config = new_config
	_apply_theme()
	if config.sound_library:
		AudioManager.set_library(config.sound_library)
	assets_changed.emit()


func skin() -> BlockSkin:
	return config.block_skin if config.block_skin else BlockSkin.new()


func palette() -> PlayerPalette:
	return config.player_palette if config.player_palette else PlayerPalette.new()


func sounds() -> SoundLibrary:
	return config.sound_library


func icon(icon_name: StringName) -> Texture2D:
	return config.icon(icon_name)


func _apply_theme() -> void:
	if config.ui_theme:
		get_tree().root.theme = config.ui_theme
	RenderingServer.set_default_clear_color(config.menu_background_color)
