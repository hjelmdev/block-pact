class_name KnockoutWinCondition
extends WinCondition
## Knockout: every player has a few lives. When the board overflows on a
## player's spawn, that player loses a life and all of their blocks vanish
## from the board (making room for everyone). At zero lives the player is
## out. Last player standing wins; then by elimination order, then score.

@export var lives: int = 3
## Ticks before a knocked-out player's next piece appears.
@export var respawn_ticks: int = 45


func starting_lives() -> int:
	return lives


func on_top_out(sim: MatchSimulation, player: PlayerState) -> bool:
	player.lives -= 1
	if player.lives <= 0:
		player.alive = false
		player.eliminated_tick = sim.tick_count
		player.eliminated_order = sim.players.size() - sim.alive_player_count()
		sim.knock_out(player)
		return sim.alive_player_count() <= 1
	sim.knock_out(player)
	player.spawn_wait = respawn_ticks
	player.spawn_attempts = 0
	return false


func rank(sim: MatchSimulation) -> Array:
	var rows: Array = []
	for p in sim.players:
		rows.append({
			"player_id": p.id,
			"score": p.score,
			"team": p.team,
			"team_score": p.score,
			"alive": p.alive,
			"out_at": p.eliminated_order if not p.alive else 1 << 30,
		})
	rows.sort_custom(func(a, b):
		if a.out_at != b.out_at:
			return a.out_at > b.out_at
		return a.score > b.score)
	for i in rows.size():
		rows[i]["rank"] = i + 1
	return rows
