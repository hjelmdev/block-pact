class_name MenuBackground
extends Control
## Attract mode: bots playing a shared board behind the menus. It is the
## exact same simulation + BoardView used in real matches.

@export var bot_count: int = 4
@export var dim: float = 0.55

@onready var _view: BoardView = $BoardView
@onready var _dim: ColorRect = $Dim

var _sim: MatchSimulation
var _bots: Array[BotInputSource] = []
var _restart_timer := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(Assets.config.menu_background_color, dim)
	_start()


func _start() -> void:
	var setup := MatchFactory.attract_mode(bot_count)
	_sim = MatchSimulation.new(setup)
	_bots.clear()
	for i in bot_count:
		var p := BotProfile.load_profile(&"normal").duplicate() as BotProfile
		p.think_ticks = 8
		p.move_interval_ticks = 5
		var b := BotInputSource.new(p)
		b.bind(_sim, i)
		_bots.append(b)
	_view.bind_match(_sim, setup, null)
	_sim.start()


func _physics_process(delta: float) -> void:
	if _sim == null:
		return
	if _sim.finished:
		_restart_timer += delta
		if _restart_timer > 2.0:
			_restart_timer = 0.0
			_start()
		return
	var inputs := PackedInt32Array()
	for b in _bots:
		inputs.append(b.gather(_sim.tick_count))
	_sim.step(inputs)
