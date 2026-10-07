extends Control
## In-editor/desktop bot training. Runs the genetic algorithm on a thread
## and saves the result to user://bots/, where the game picks it up for
## all bot difficulties (shipped profiles in res:// stay untouched).

@onready var _log: RichTextLabel = %Log
@onready var _start: Button = %StartButton
@onready var _gens: SpinBox = %GenerationsSpin
@onready var _back: Button = %BackButton

var _thread: Thread
var _stop := false


func _ready() -> void:
	_start.pressed.connect(_on_start)
	_back.pressed.connect(func():
		_stop = true
		Router.goto(&"main_menu"))
	_log.text = "Trains bot weights by self-play (headless matches vs the current 'hard' bot).\n" + \
		"CLI alternative: godot --headless -s res://tools/train_bots.gd -- --generations 8\n"


func _on_start() -> void:
	if _thread and _thread.is_alive():
		return
	_start.disabled = true
	_thread = Thread.new()
	_thread.start(_train.bind(int(_gens.value)))


func _train(generations: int) -> void:
	var mode: GameModeConfig = load("res://data/modes/shared_competition.tres")
	var start := BotProfile.load_profile(&"hard")
	var trainer := BotTrainer.new(mode, start, start.get_weights(), randi())
	trainer.population_size = 10
	for i in generations:
		if _stop:
			return
		trainer.run_generation()
		_append.call_deferred("Generation %d: best fitness %.0f" % [trainer.generation, trainer.best_fitness])
	BotTrainer.write_profiles(trainer.best_weights, BotProfile.USER_DIR)
	_append.call_deferred("Saved to %s – all bot levels now use the new weights." % BotProfile.USER_DIR)
	_done.call_deferred()


func _append(line: String) -> void:
	_log.text += line + "\n"


func _done() -> void:
	_start.disabled = false


func _exit_tree() -> void:
	_stop = true
	if _thread:
		_thread.wait_to_finish()
