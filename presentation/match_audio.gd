class_name MatchAudio
extends Node
## Translates simulation events into sound events. The only place that
## decides "which sound for which game event" – the files themselves are
## chosen by the SoundLibrary resource.

## Movement sounds only for local humans (8 bots ticking is noise).
var _audible_players: Array[int] = []
var _last_x: Dictionary = {}


func _ready() -> void:
	add_to_group(&"match_presenter")


func bind_match(sim: MatchSimulation, setup: MatchSetup, _controller: Node) -> void:
	for i in setup.slots.size():
		if setup.slots[i].kind == PlayerSlot.Kind.LOCAL_HUMAN:
			_audible_players.append(i)
	var all_bots := _audible_players.is_empty()
	sim.piece_moved.connect(func(pid):
		if pid in _audible_players:
			var p := sim.get_player(pid)
			if p.active and _last_x.get(pid, p.active.position.x) != p.active.position.x and not p.hard_drop_pending:
				AudioManager.play(Sfx.MOVE)
			if p.active:
				_last_x[pid] = p.active.position.x)
	sim.piece_spawned.connect(func(pid):
		var p := sim.get_player(pid)
		if p.active:
			_last_x[pid] = p.active.position.x)
	sim.piece_rotated.connect(func(pid, _k):
		if pid in _audible_players:
			AudioManager.play(Sfx.ROTATE))
	sim.piece_hard_dropped.connect(func(pid, _rows):
		if pid in _audible_players or all_bots:
			AudioManager.play(Sfx.HARD_DROP, 1.0, 0.0 if pid in _audible_players else -8.0))
	sim.piece_locked.connect(func(pid, _cells):
		AudioManager.play(Sfx.LOCK, 1.0, 0.0 if pid in _audible_players else -9.0))
	sim.piece_held.connect(func(pid):
		if pid in _audible_players:
			AudioManager.play(Sfx.HOLD))
	sim.lines_cleared.connect(_on_lines_cleared)
	sim.combo_changed.connect(func(_pid, combo):
		if combo > 1:
			AudioManager.play(Sfx.COMBO, 1.0 + minf(combo - 1, 10) * 0.08))
	sim.level_changed.connect(func(_l): AudioManager.play(Sfx.LEVEL_UP))
	sim.player_topped_out.connect(func(_pid): AudioManager.play(Sfx.TOP_OUT))
	sim.match_finished.connect(func(_r): AudioManager.play(Sfx.GAME_OVER))
	sim.board_effect.connect(_on_board_effect)
	sim.powerup_changed.connect(func(pid, id):
		if id > 0:
			AudioManager.play(Sfx.POWERUP_GET, 1.0, 0.0 if pid in _audible_players or all_bots else -6.0))
	sim.powerup_used.connect(func(_pid, id): _on_powerup_used(sim.get_powerup_type(id)))


func _on_lines_cleared(result: LineClearResult) -> void:
	AudioManager.play(Sfx.line_clear(result.line_count()))
	for key in result.specials_triggered:
		if key in [&"x2", &"x3", &"x5"]:
			AudioManager.play(Sfx.SPECIAL)
			break


func _on_powerup_used(t: PowerupType) -> void:
	AudioManager.play(Sfx.POWERUP_USE)
	if t == null:
		return
	if t.effect == PowerupType.Effect.SLOW:
		AudioManager.play(Sfx.SLOW)
	elif t.effect == PowerupType.Effect.RUSH:
		AudioManager.play(Sfx.RUSH)


func _on_board_effect(e: Dictionary) -> void:
	match String(e.key):
		"bomb", "bomb_piece":
			AudioManager.play(Sfx.EXPLOSION)
		"megabomb":
			AudioManager.play(Sfx.MEGABOMB)
		"laser":
			AudioManager.play(Sfx.LASER)
		"paint":
			AudioManager.play(Sfx.PAINT)
		"gold":
			AudioManager.play(Sfx.GOLD)
		"quake":
			AudioManager.play(Sfx.QUAKE)


func on_score_arrived(_pid: int, _points: int, _mult: int) -> void:
	AudioManager.play(Sfx.SCORE_ARRIVE, 1.0 + randf() * 0.2)
