extends Node
## Autoload "Progress": everything that should persist for an ACCOUNT –
## nickname, highscores, achievements. Guests get none of it by design:
## every method is a no-op (or returns empty data) when not logged in.

signal achievement_unlocked(def: AchievementDefinition)
signal profile_changed()

const ACHIEVEMENT_DIR := "res://data/achievements/"

var nickname: String = ""
var unlocked: Dictionary = {}  # achievement id -> true
var achievements: Array[AchievementDefinition] = []


func _ready() -> void:
	_load_achievement_defs()
	Auth.session_changed.connect(_on_session_changed)
	if Auth.is_logged_in():
		_on_session_changed(true)


func is_tracking() -> bool:
	return Auth.is_logged_in()


func user_id() -> String:
	return Auth.user_id if is_tracking() else ""


## Name shown in matches. Guests may still pick a local nickname (not saved online).
func display_name() -> String:
	if nickname != "":
		return nickname
	var local: String = GameSettings.get_value("game", "nickname", "")
	if local != "":
		return local
	if is_tracking() and Auth.provider_name != "":
		return Auth.provider_name
	return tr("GUEST_NAME")


func set_nickname(value: String) -> void:
	value = value.strip_edges().left(16)
	GameSettings.set_value("game", "nickname", value)
	if is_tracking():
		nickname = value
		await Auth.rest("POST", "/rest/v1/profiles", {"id": Auth.user_id, "nickname": value}, true,
				PackedStringArray(["Prefer: resolution=merge-duplicates"]))
	profile_changed.emit()


## Called by the results screen. Returns a short note for the player.
func submit_match(sim: MatchSimulation, setup: MatchSetup, ranking: Array) -> String:
	var human_index := -1
	for i in setup.slots.size():
		if setup.slots[i].kind == PlayerSlot.Kind.LOCAL_HUMAN:
			human_index = i
			break
	if human_index < 0:
		return ""
	if not is_tracking():
		return tr("RESULTS_GUEST_NOTE")
	var p := sim.get_player(human_index)
	var stats := stats_for(sim, p, ranking)
	_check_achievements(stats, setup.mode.mode_id)
	if setup.mode.leaderboard_enabled:
		_post_score(setup, sim, p)
	return tr("RESULTS_SAVED")


func stats_for(sim: MatchSimulation, p: PlayerState, ranking: Array) -> Dictionary:
	var won := 0
	if sim.players.size() > 1 and not ranking.is_empty() and ranking[0].player_id == p.id:
		won = 1
	return {
		AchievementDefinition.Stat.SCORE: p.score,
		AchievementDefinition.Stat.LINES_FINISHED: p.lines_finished,
		AchievementDefinition.Stat.CELLS_CLEARED: p.cells_cleared,
		AchievementDefinition.Stat.MAX_COMBO: p.max_combo,
		AchievementDefinition.Stat.BEST_CLEAR: p.best_clear,
		AchievementDefinition.Stat.SPECIALS: p.specials_triggered,
		AchievementDefinition.Stat.WON_MULTIPLAYER: won,
		AchievementDefinition.Stat.PIECES_PLACED: p.pieces_placed,
	}


## Returns Array of {nickname, score, lines, created_at}. Empty when offline.
func fetch_leaderboard(mode_id: StringName, limit := 20) -> Array:
	if not Auth.is_available():
		return []
	var path := "/rest/v1/leaderboard?mode_id=eq.%s&order=score.desc&limit=%d" % [mode_id, limit]
	var res: Dictionary = await Auth.rest("GET", path, null, false)
	return res.data if res.ok and res.data is Array else []


func _post_score(setup: MatchSetup, sim: MatchSimulation, p: PlayerState) -> void:
	Auth.rest("POST", "/rest/v1/scores", {
		"mode_id": String(setup.mode.mode_id),
		"score": p.score,
		"lines": p.lines_finished,
		"players": setup.slots.size(),
		"duration_s": sim.tick_count / MatchSimulation.TICKS_PER_SECOND,
		"seed": setup.seed,
	})


func _check_achievements(stats: Dictionary, mode_id: StringName) -> void:
	for def in achievements:
		if unlocked.has(def.id):
			continue
		if def.is_met(stats, mode_id):
			unlocked[def.id] = true
			achievement_unlocked.emit(def)
			Auth.rest("POST", "/rest/v1/player_achievements", {"achievement_id": String(def.id)})


func _on_session_changed(logged_in: bool) -> void:
	unlocked.clear()
	nickname = ""
	if not logged_in:
		profile_changed.emit()
		return
	var prof: Dictionary = await Auth.rest("GET", "/rest/v1/profiles?id=eq.%s&select=nickname" % Auth.user_id, null)
	if prof.ok and prof.data is Array and not prof.data.is_empty():
		nickname = str(prof.data[0].get("nickname", ""))
	var ach: Dictionary = await Auth.rest("GET", "/rest/v1/player_achievements?select=achievement_id", null)
	if ach.ok and ach.data is Array:
		for row: Dictionary in ach.data:
			unlocked[StringName(row.achievement_id)] = true
	profile_changed.emit()


func _load_achievement_defs() -> void:
	var dir := DirAccess.open(ACHIEVEMENT_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if f.ends_with(".tres"):
			var res := load(ACHIEVEMENT_DIR + f)
			if res is AchievementDefinition:
				achievements.append(res)
