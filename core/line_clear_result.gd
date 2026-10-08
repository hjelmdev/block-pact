class_name LineClearResult
extends RefCounted
## Everything that happened in one line clear. Produced by ScoreRules,
## consumed by the simulation (to apply score) and by presentation (effects).

class ClearedRow:
	extends RefCounted
	var y: int = 0
	## Array of { "x": int, "owner": int, "special": int }
	var cells: Array = []
	## player id -> owned cell count
	var counts: Dictionary = {}
	## player id -> points earned from this row (incl. multipliers)
	var points: Dictionary = {}
	## player id -> multiplier that was applied to that player's share
	var multipliers: Dictionary = {}

var rows: Array[ClearedRow] = []
var finisher_id: int = -1
var finisher_bonus: int = 0
var combo: int = 0
var combo_bonus: int = 0
var level: int = 1
## player id -> total points awarded by this clear
var awards: Dictionary = {}
## Special keys that were part of the cleared rows (for effects/sounds).
var specials_triggered: Array[StringName] = []
## Board effects caused by special cells in the cleared rows (see
## MatchSimulation.board_effect for the dictionary layout).
var effects: Array = []
## Players whose awards were doubled by the Double powerup.
var doubled: Array[int] = []


func line_count() -> int:
	return rows.size()


func total_points() -> int:
	var t := 0
	for v: int in awards.values():
		t += v
	return t


func max_multiplier_for(player_id: int) -> int:
	var m := 1
	for r in rows:
		m = maxi(m, r.multipliers.get(player_id, 1))
	return m
