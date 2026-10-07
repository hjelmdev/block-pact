class_name WinCondition
extends Resource
## Decides when a match ends and how players are ranked.
##
## Default behaviour (Shared Board): when the board tops out everybody loses
## together and the ranking is by score. Optional goals end the match early.
## Subclass for knockout / lives / respawn variants.

enum RankBy { PLAYER_SCORE, TEAM_SCORE, SHARED_SCORE }

@export var end_on_top_out: bool = true
## End when this many lines have been cleared in total (0 = no goal).
@export var target_lines: int = 0
## End after this many seconds (0 = no limit).
@export var time_limit_seconds: float = 0.0
@export var rank_by: RankBy = RankBy.PLAYER_SCORE


## Called when a player's piece can no longer spawn / locks out.
## Return true if the whole match should end.
func on_top_out(sim: MatchSimulation, player: PlayerState) -> bool:
	if end_on_top_out:
		return true
	player.alive = false
	return sim.alive_player_count() == 0


func check_goal(sim: MatchSimulation) -> bool:
	if target_lines > 0 and sim.total_lines >= target_lines:
		return true
	if time_limit_seconds > 0.0 and sim.tick_count >= int(time_limit_seconds * MatchSimulation.TICKS_PER_SECOND):
		return true
	return false


## Returns Array of Dictionary sorted best-first:
## { player_id, score, team, team_score, rank }
func rank(sim: MatchSimulation) -> Array:
	var team_scores := sim.get_team_scores()
	var rows: Array = []
	for p in sim.players:
		rows.append({
			"player_id": p.id,
			"score": p.score,
			"team": p.team,
			"team_score": team_scores.get(p.team, p.score),
		})
	var key := "team_score" if rank_by == RankBy.TEAM_SCORE else "score"
	rows.sort_custom(func(a, b):
		if a[key] == b[key]:
			return a.score > b.score
		return a[key] > b[key])
	var rank_no := 0
	var last_value = null
	for i in rows.size():
		if rows[i][key] != last_value:
			rank_no = i + 1
			last_value = rows[i][key]
		rows[i]["rank"] = rank_no
	return rows
