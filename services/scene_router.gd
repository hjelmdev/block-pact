extends Node
## Autoload "Router": scene navigation with parameters.
## Scenes read their input from [member params] in _ready().

signal scene_changed(key: StringName)

const SCENES := {
	&"boot": "res://scenes/boot/boot.tscn",
	&"main_menu": "res://scenes/menus/main_menu.tscn",
	&"lobby": "res://scenes/menus/lobby.tscn",
	&"match": "res://scenes/match/match.tscn",
	&"settings": "res://scenes/menus/settings_menu.tscn",
	&"account": "res://scenes/menus/account_menu.tscn",
	&"leaderboard": "res://scenes/menus/leaderboard_menu.tscn",
	&"online": "res://scenes/menus/online_menu.tscn",
	&"online_lobby": "res://scenes/menus/online_lobby.tscn",
	&"bot_trainer": "res://tools/bot_trainer.tscn",
}

var params: Dictionary = {}
var current: StringName = &""


func goto(key: StringName, p_params: Dictionary = {}) -> void:
	params = p_params
	current = key
	get_tree().paused = false
	var path: String = SCENES.get(key, "")
	if path == "":
		push_error("Unknown scene key %s" % key)
		return
	get_tree().change_scene_to_file.call_deferred(path)
	scene_changed.emit(key)


func back_to_menu() -> void:
	goto(&"main_menu")
