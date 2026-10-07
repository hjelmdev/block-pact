class_name BotProfile
extends Resource
## How a bot thinks (evaluation weights) and how "human" it plays
## (reaction time, speed, mistakes). Weights can be hand-tuned in the
## inspector or produced by the genetic trainer (tools/bot_trainer.gd) or
## by in-game learning (BotLearning).

const USER_DIR := "user://bots/"
const RES_DIR := "res://ai/profiles/"
const WEIGHT_NAMES: Array[StringName] = [
	&"w_lines", &"w_own_cleared", &"w_other_cleared", &"w_holes", &"w_aggregate_height",
	&"w_bumpiness", &"w_max_height", &"w_landing_height", &"w_own_row_fill",
	&"w_special_cleared", &"w_lane_distance", &"w_wells", &"w_contested", &"w_row_fill", &"w_steal", &"w_sabotage",
]

@export var id: StringName = &"normal"
@export var display_name: String = "Normal"

@export_group("Skill")
## Ticks before the bot reacts to a new piece.
@export var think_ticks: int = 12
## Ticks between each move/rotate action.
@export var move_interval_ticks: int = 4
## Chance to pick a sub-optimal placement.
@export_range(0.0, 1.0) var mistake_chance: float = 0.1
## How much worse (in evaluation points) a "mistake" placement may be.
@export var mistake_margin: float = 2.5
## How many columns left/right of the piece the bot considers.
@export var search_radius: int = 8
@export var use_hard_drop: bool = true
@export var use_hold: bool = false

@export_group("Weights")
@export var w_lines: float = 0.8
@export var w_own_cleared: float = 0.15
@export var w_other_cleared: float = -0.05
@export var w_holes: float = -3.5
@export var w_aggregate_height: float = -0.5
@export var w_bumpiness: float = -0.18
@export var w_max_height: float = -0.2
@export var w_landing_height: float = -0.05
@export var w_own_row_fill: float = 0.05
@export var w_special_cleared: float = 1.0
## Columns outside your own spawn lane (0 inside it).
@export var w_lane_distance: float = -0.3
@export var w_wells: float = -0.1
## Landing in columns where another player's piece is currently falling.
@export var w_contested: float = -0.6
## Reward for adding cells to rows that are already nearly full (any owner).
@export var w_row_fill: float = 1.0
## Completing a row where another player owns more cells than you.
@export var w_steal: float = 0.0
## Covering gaps in rows that another player leads (blocking their clear).
@export var w_sabotage: float = 0.0


func get_weights() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for n in WEIGHT_NAMES:
		arr.append(get(n))
	return arr


func set_weights(arr: PackedFloat32Array) -> void:
	for i in mini(arr.size(), WEIGHT_NAMES.size()):
		set(WEIGHT_NAMES[i], arr[i])


## Loads a learned profile from user:// if present, otherwise the shipped one.
static func load_profile(profile_id: StringName) -> BotProfile:
	for dir in [USER_DIR, RES_DIR]:
		var path := "%s%s.tres" % [dir, profile_id]
		if ResourceLoader.exists(path):
			var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if res is BotProfile:
				return res
	var fallback := BotProfile.new()
	fallback.id = profile_id
	return fallback


static func list_shipped_ids() -> Array[StringName]:
	return [&"easy", &"normal", &"hard", &"adaptive"]
