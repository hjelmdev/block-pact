extends SceneTree
## Trains bot weights with a genetic algorithm and writes the shipped
## profiles (easy / normal / hard / adaptive) to res://ai/profiles/.
##
## Run: godot --headless --path . -s res://tools/train_bots.gd -- --generations 8
## Options: --generations N  --population N  --seconds S  --seeds N  --out res://ai/profiles/

func _init() -> void:
	var args := _parse_args()
	var generations: int = int(args.get("generations", "6"))
	var mode: GameModeConfig = load("res://data/modes/shared_competition.tres")
	var start := BotProfile.load_profile(&"hard")
	var trainer := BotTrainer.new(mode, start, start.get_weights(), int(args.get("seed", "7")))
	trainer.population_size = int(args.get("population", "14"))
	trainer.max_ticks = int(args.get("seconds", "120")) * MatchSimulation.TICKS_PER_SECOND
	trainer.seeds_per_eval = int(args.get("seeds", "3"))
	trainer.generation_finished.connect(func(g, f, w):
		print("generation %d  best %.0f  %s" % [g, f, w]))
	for i in generations:
		trainer.run_generation()
	var best := trainer.best_weights
	print("best fitness %.0f" % trainer.best_fitness)
	BotTrainer.write_profiles(best, String(args.get("out", "res://ai/profiles/")))
	quit()


func _parse_args() -> Dictionary:
	var out := {}
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		if a[i].begins_with("--") and i + 1 < a.size():
			out[a[i].trim_prefix("--")] = a[i + 1]
			i += 2
		else:
			i += 1
	return out
