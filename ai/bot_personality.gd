class_name BotPersonality
extends Resource
## A play style layered on top of a BotProfile's learned weights.
## Difficulty (BotProfile) = how well/fast it plays; personality = WHAT it
## wants. Add new personalities as .tres files in res://data/bots/.

const DIR := "res://data/bots/"

@export var id: StringName = &"builder"
## Translation key for the name, e.g. "PERSONALITY_THIEF".
@export var name_key: String = "PERSONALITY_BUILDER"
## Translation key for the one-line description shown in the lobby.
@export var description_key: String = ""
## Absolute weight values that replace the profile's (see BotProfile.WEIGHT_NAMES).
@export var weight_overrides: Dictionary = {}
## Optional skill tweaks, e.g. {"move_interval_ticks": 5}.
@export var skill_overrides: Dictionary = {}


func apply_to(profile: BotProfile) -> BotProfile:
	var p := profile.duplicate() as BotProfile
	for k: String in weight_overrides:
		p.set(k, weight_overrides[k])
	for k: String in skill_overrides:
		p.set(k, skill_overrides[k])
	return p


static func load_personality(personality_id: StringName) -> BotPersonality:
	var path := "%s%s.tres" % [DIR, personality_id]
	if personality_id != &"" and ResourceLoader.exists(path):
		return load(path)
	return null


static func list_ids() -> Array[StringName]:
	return [&"thief", &"greedy", &"saboteur", &"builder"]
