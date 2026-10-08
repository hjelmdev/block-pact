extends Control
## First scene: lets autoloads settle (e.g. Auth reading an OAuth redirect)
## and then opens the main menu.


func _ready() -> void:
	# Sanity line in the log / browser console: data folders found in this build.
	print("[boot] Block Pact %s – avatars %d, powerups %d" % [NetProtocol.build_id(),
			Assets.avatar_ids().size(), MatchSimulation.load_all_powerups().size()])
	await get_tree().create_timer(0.35).timeout
	Router.goto(&"main_menu")
