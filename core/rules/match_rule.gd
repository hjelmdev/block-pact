class_name MatchRule
extends Resource
## Extension point for game-mode specific behaviour (powerups, garbage,
## events, timed modifiers …). The simulation duplicates every rule at match
## start, so a rule may keep per-match state in its own variables.
##
## All hooks are optional. Rules must stay deterministic: use sim.rng only.

func setup(_sim: MatchSimulation) -> void:
	pass


func on_tick(_sim: MatchSimulation) -> void:
	pass


func on_piece_spawned(_sim: MatchSimulation, _player: PlayerState) -> void:
	pass


func on_piece_locked(_sim: MatchSimulation, _player: PlayerState, _cells: Array[Vector2i]) -> void:
	pass


func on_lines_cleared(_sim: MatchSimulation, _result: LineClearResult) -> void:
	pass
