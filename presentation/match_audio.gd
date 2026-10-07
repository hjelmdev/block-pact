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


func _on_lines_cleared(result: LineClearResult) -> void:
	AudioManager.play(Sfx.line_clear(result.line_count()))
	if not result.specials_triggered.is_empty():
		AudioManager.play(Sfx.SPECIAL)


func on_score_arrived(_pid: int, _points: int, _mult: int) -> void:
	AudioManager.play(Sfx.SCORE_ARRIVE, 1.0 + randf() * 0.2)
