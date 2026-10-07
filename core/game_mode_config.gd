class_name GameModeConfig
extends Resource
## Everything that makes one game mode different from another.
## New modes are new .tres files in res://data/modes/ – no code needed
## unless a mode wants custom ScoreRules / WinCondition / MatchRule scripts.

enum TeamMode {
	## Everyone for themselves (still on a shared board).
	FREE_FOR_ALL,
	## Players grouped in teams of [member team_size]; team scores summed.
	TEAMS,
	## Everyone in one team; the shared total is what matters.
	COOP,
}

@export_group("Identity")
@export var mode_id: StringName = &"shared"
@export var display_name: String = "Shared Board"
@export_multiline var description: String = ""
@export var min_players: int = 1
@export var max_players: int = 8
## Whether results may be submitted to online leaderboards.
@export var leaderboard_enabled: bool = true

@export_group("Board")
## Picked by player count: first rule with max_players >= count.
@export var board_sizes: Array[BoardSizeRule] = []
@export var hidden_rows: int = 2

@export_group("Pieces")
@export var piece_set: PieceSet
@export var next_preview_count: int = 3
@export var hold_enabled: bool = true
## Same piece sequence for every player (else each player has its own seed).
@export var shared_sequence: bool = false
## Whether falling pieces of different players block each other.
@export var active_piece_collision: bool = true
@export_range(0.0, 1.0) var special_chance: float = 0.12
@export var special_types: Array[SpecialBlockType] = []

@export_group("Speed")
@export var start_level: int = 1
@export var lines_per_level: int = 10
## Ticks per row of gravity, indexed by level-1 (last value repeats).
@export var gravity_ticks: PackedInt32Array = PackedInt32Array([48, 43, 38, 33, 28, 23, 18, 13, 9, 7, 6, 5, 4, 4, 3, 3, 2, 2, 1])
@export var lock_delay_ticks: int = 30
@export var max_lock_resets: int = 15
@export var soft_drop_ticks: int = 2

@export_group("Rules")
@export var team_mode: TeamMode = TeamMode.FREE_FOR_ALL
@export var team_size: int = 2
@export var score_rules: ScoreRules
@export var win_condition: WinCondition
@export var rules: Array[MatchRule] = []


func board_size_for(player_count: int) -> Vector2i:
	for rule in board_sizes:
		if player_count <= rule.max_players:
			return Vector2i(rule.width, rule.height)
	if board_sizes.is_empty():
		return Vector2i(10, 20)
	var last: BoardSizeRule = board_sizes.back()
	return Vector2i(last.width, last.height)


func gravity_for_level(level: int) -> int:
	if gravity_ticks.is_empty():
		return 30
	return gravity_ticks[clampi(level - 1, 0, gravity_ticks.size() - 1)]


func team_for_slot(slot_index: int, player_count: int) -> int:
	match team_mode:
		TeamMode.COOP:
			return 0
		TeamMode.TEAMS:
			var teams := maxi(1, ceili(float(player_count) / float(maxi(team_size, 1))))
			return slot_index % teams
		_:
			return slot_index
