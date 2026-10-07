extends Control
## First scene: lets autoloads settle (e.g. Auth reading an OAuth redirect)
## and then opens the main menu.


func _ready() -> void:
	await get_tree().create_timer(0.35).timeout
	Router.goto(&"main_menu")
