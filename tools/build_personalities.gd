extends SceneTree
## Writes the default bot personalities to res://data/bots/.
## godot --headless --path . -s res://tools/build_personalities.gd


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://data/bots")
	_save(&"builder", "PERSONALITY_BUILDER", "PERSONALITY_BUILDER_DESC", {}, {})
	_save(&"thief", "PERSONALITY_THIEF", "PERSONALITY_THIEF_DESC", {
		"w_steal": 3.0,
		"w_other_cleared": 0.35,
		"w_own_cleared": 0.0,
		"w_lines": 1.2,
		"w_lane_distance": 0.0,
		"w_contested": 0.0,
	}, {"search_radius": 16})
	_save(&"greedy", "PERSONALITY_GREEDY", "PERSONALITY_GREEDY_DESC", {
		"w_own_cleared": 0.6,
		"w_own_row_fill": 0.5,
		"w_other_cleared": -0.45,
		"w_special_cleared": 3.0,
		"w_lines": 0.1,
	}, {})
	_save(&"saboteur", "PERSONALITY_SABOTEUR", "PERSONALITY_SABOTEUR_DESC", {
		"w_sabotage": 1.6,
		"w_other_cleared": -0.6,
		"w_holes": -2.8,
		"w_lane_distance": 0.0,
	}, {"search_radius": 14})
	print("personalities written")
	quit()


func _save(id: StringName, name_key: String, desc_key: String, weights: Dictionary, skill: Dictionary) -> void:
	var p := BotPersonality.new()
	p.id = id
	p.name_key = name_key
	p.description_key = desc_key
	p.weight_overrides = weights
	p.skill_overrides = skill
	ResourceSaver.save(p, "res://data/bots/%s.tres" % id)
