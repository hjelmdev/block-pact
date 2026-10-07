extends SceneTree
## Regenerates the default data resources (pieces, specials, game modes).
## Run: godot --headless --path . -s res://tools/build_default_data.gd
## Edit the produced .tres files in the inspector afterwards if you like –
## this script is only a convenient starting point.


func _init() -> void:
	var pieces := _build_pieces()
	ResourceSaver.save(pieces, "res://data/pieces/standard_pieces.tres")

	var x2 := _special(1, &"x2", 2, 1.0)
	var x3 := _special(2, &"x3", 3, 1.0)
	var x5 := _special(3, &"x5", 5, 1.0)
	ResourceSaver.save(x2, "res://data/specials/x2.tres")
	ResourceSaver.save(x3, "res://data/specials/x3.tres")
	ResourceSaver.save(x5, "res://data/specials/x5.tres")
	pieces = load("res://data/pieces/standard_pieces.tres")
	x5 = load("res://data/specials/x5.tres")

	var score := ScoreRules.new()
	ResourceSaver.save(score, "res://data/modes/default_score_rules.tres")
	score = load("res://data/modes/default_score_rules.tres")

	# --- Classic solo
	var solo := _mode(&"classic_solo", "Classic", "Solo play on a classic 10×20 board.", pieces, score)
	solo.min_players = 1
	solo.max_players = 1
	solo.board_sizes = [_size(1, 10, 20)]
	solo.special_types = [x5]
	solo.special_chance = 0.08
	solo.win_condition = WinCondition.new()
	ResourceSaver.save(solo, "res://data/modes/classic_solo.tres")

	# --- Shared board competition (main mode)
	var shared := _mode(&"shared_competition", "Shared Board",
			"Everyone builds on one board. Your color = your blocks. More of your color in a cleared row = more points.",
			pieces, score)
	shared.min_players = 1
	shared.max_players = 8
	shared.board_sizes = [_size(1, 10, 20), _size(2, 16, 24), _size(3, 20, 24), _size(4, 24, 26), _size(6, 32, 26), _size(8, 40, 28)]
	shared.special_types = [x5]
	shared.win_condition = WinCondition.new()
	ResourceSaver.save(shared, "res://data/modes/shared_competition.tres")

	# --- Pure co-op
	var coop := _mode(&"pure_coop", "Pure Co-op", "Survive together. The team total is what counts.", pieces, score)
	coop.min_players = 1
	coop.max_players = 8
	coop.board_sizes = shared.board_sizes
	coop.special_types = [x5]
	coop.team_mode = GameModeConfig.TeamMode.COOP
	var coop_win := WinCondition.new()
	coop_win.rank_by = WinCondition.RankBy.SHARED_SCORE
	coop.win_condition = coop_win
	ResourceSaver.save(coop, "res://data/modes/pure_coop.tres")

	# --- Teams
	var teams := _mode(&"team_battle", "Team Battle", "Shared board, teams of two. Team scores are summed.", pieces, score)
	teams.min_players = 2
	teams.max_players = 8
	teams.board_sizes = shared.board_sizes
	teams.special_types = [x5]
	teams.team_mode = GameModeConfig.TeamMode.TEAMS
	teams.team_size = 2
	var team_win := WinCondition.new()
	team_win.rank_by = WinCondition.RankBy.TEAM_SCORE
	teams.win_condition = team_win
	ResourceSaver.save(teams, "res://data/modes/team_battle.tres")

	print("Default data written.")
	quit()


func _mode(id: StringName, title: String, desc: String, pieces: PieceSet, score: ScoreRules) -> GameModeConfig:
	var m := GameModeConfig.new()
	m.mode_id = id
	m.display_name = title
	m.description = desc
	m.piece_set = pieces
	m.score_rules = score
	return m


func _size(max_players: int, w: int, h: int) -> BoardSizeRule:
	var r := BoardSizeRule.new()
	r.max_players = max_players
	r.width = w
	r.height = h
	return r


func _special(id: int, key: StringName, mult: int, weight: float) -> SpecialBlockType:
	var s := SpecialBlockType.new()
	s.id = id
	s.key = key
	s.multiplier = mult
	s.spawn_weight = weight
	return s


func _build_pieces() -> PieceSet:
	var set := PieceSet.new()
	set.pieces = [
		_piece(&"I", 4, &"i", [Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)]),
		_piece(&"O", 2, &"none", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)], false),
		_piece(&"T", 3, &"jlstz", [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]),
		_piece(&"S", 3, &"jlstz", [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)]),
		_piece(&"Z", 3, &"jlstz", [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)]),
		_piece(&"J", 3, &"jlstz", [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]),
		_piece(&"L", 3, &"jlstz", [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]),
	]
	return set


func _piece(id: StringName, box: int, kicks: StringName, cells: Array[Vector2i], rotates := true) -> PieceShape:
	var p := PieceShape.new()
	p.id = id
	p.display_name = String(id)
	p.box_size = box
	p.kick_table = kicks
	p.cells = cells
	p.can_rotate = rotates
	return p
