extends Node
## Autoload "Progress": everything that should persist for an ACCOUNT –
## nickname, highscores, achievements. Guests get none of it by design:
## every method is a no-op (or returns empty data) when not logged in.

signal achievement_unlocked(def: AchievementDefinition)
signal profile_changed()
## After a score was posted: a short note for the results screen.
signal score_saved(note: String)

const ACHIEVEMENT_DIR := "res://data/achievements/"

var nickname: String = ""
var profile_avatar: String = ""
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


## Chosen avatar id: the account's (when signed in) or this device's.
func avatar() -> String:
	if is_tracking() and profile_avatar != "":
		return profile_avatar
	var local: String = GameSettings.get_value("game", "avatar", "")
	return local if local != "" else Assets.default_avatar(display_name())


func set_avatar(id: String) -> void:
	if not Assets.avatar_ids().has(id):
		return
	GameSettings.set_value("game", "avatar", id)
	if is_tracking():
		profile_avatar = id
		await Auth.rest("PATCH", "/rest/v1/profiles?id=eq.%s" % Auth.user_id, {"avatar": id})
	profile_changed.emit()


func set_nickname(value: String) -> void:
	value = value.strip_edges().left(16)
	GameSettings.set_value("game", "nickname", value)
	if is_tracking():
		nickname = value
		await Auth.rest("POST", "/rest/v1/profiles", {"id": Auth.user_id, "nickname": value}, true,
				PackedStringArray(["Prefer: resolution=merge-duplicates"]))
	profile_changed.emit()


## How often / how long the results screen waits for the server's verdict.
const VERIFY_POLL_SECONDS := 3.0
const VERIFY_POLL_TRIES := 20


## Called by the results screen. Returns a short note for the player.
## `replay` is the full match (setup + inputs); the score only reaches the
## leaderboard once the server has replayed it and got the same result.
func submit_match(sim: MatchSimulation, setup: MatchSetup, ranking: Array, replay: MatchReplay = null) -> String:
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
	if setup.mode.leaderboard_enabled and replay != null:
		_submit_replay(setup, sim, p, replay)
		return tr("RESULTS_SAVING")
	return tr("RESULTS_SAVED")


## "classic" or "party" (special blocks / powerups) – separate leaderboards.
static func ruleset_for(sim: MatchSimulation) -> String:
	return sim.ruleset()


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
		AchievementDefinition.Stat.BLOCKS_DESTROYED: p.blocks_destroyed,
		AchievementDefinition.Stat.BLOCKS_PAINTED: p.blocks_painted,
		AchievementDefinition.Stat.POWERUPS_USED: p.powerups_used,
	}


## Returns Array of {user_id, nickname, avatar, score, lines, created_at}.
## Readable by guests too; empty when offline.
func fetch_leaderboard(mode_id: StringName, ruleset := "classic", limit := 20) -> Array:
	if not Auth.is_available():
		return []
	var path := "/rest/v1/leaderboard?mode_id=eq.%s&ruleset=eq.%s&order=score.desc&limit=%d" % [
			String(mode_id).uri_encode(), ruleset.uri_encode(), limit]
	var res: Dictionary = await Auth.rest("GET", path, null, false)
	return res.data if res.ok and res.data is Array else []


## Best score of the signed-in player for a mode/ruleset (0 = none).
func fetch_personal_best(mode_id: StringName, ruleset: String) -> int:
	if not is_tracking():
		return 0
	var path := "/rest/v1/scores?select=score&user_id=eq.%s&mode_id=eq.%s&ruleset=eq.%s&order=score.desc&limit=1" % [
			Auth.user_id, String(mode_id).uri_encode(), ruleset.uri_encode()]
	var res: Dictionary = await Auth.rest("GET", path, null)
	if res.ok and res.data is Array and not res.data.is_empty():
		return int(res.data[0].get("score", 0))
	return 0


func _submit_replay(setup: MatchSetup, sim: MatchSimulation, p: PlayerState, replay: MatchReplay) -> void:
	var ruleset := ruleset_for(sim)
	var previous_best := await fetch_personal_best(setup.mode.mode_id, ruleset)
	var res: Dictionary = await Auth.rest("POST", "/rest/v1/score_submissions", {
		"mode_id": String(setup.mode.mode_id),
		"ruleset": ruleset,
		"slot": p.id,
		"claimed_score": p.score,
		"sim_version": MatchReplay.SIM_VERSION,
		"replay": replay.to_dict(),
	}, true, PackedStringArray(["Prefer: return=representation"]))
	if not res.ok or not res.data is Array or res.data.is_empty():
		score_saved.emit(tr("RESULTS_SAVE_FAILED"))
		return
	var id := int(res.data[0].get("id", 0))
	score_saved.emit(tr("RESULTS_VERIFYING"))
	for i in VERIFY_POLL_TRIES:
		await get_tree().create_timer(VERIFY_POLL_SECONDS).timeout
		var st: Dictionary = await Auth.rest("GET", "/rest/v1/score_submissions?select=status&id=eq.%d" % id, null)
		var status := ""
		if st.ok and st.data is Array and not st.data.is_empty():
			status = str(st.data[0].get("status", ""))
		match status:
			"verified":
				if p.score > previous_best:
					score_saved.emit(tr("RESULTS_NEW_BEST") % p.score)
				else:
					score_saved.emit(tr("RESULTS_SAVED_BEST") % previous_best)
				return
			"rejected":
				score_saved.emit(tr("RESULTS_REJECTED"))
				return
			"unsupported":
				score_saved.emit(tr("RESULTS_OUTDATED"))
				return
	# No verifier answered in time – it will be handled later.
	score_saved.emit(tr("RESULTS_VERIFY_LATER"))


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
	profile_avatar = ""
	if not logged_in:
		profile_changed.emit()
		return
	var prof: Dictionary = await Auth.rest("GET", "/rest/v1/profiles?id=eq.%s&select=nickname,avatar" % Auth.user_id, null)
	if prof.ok and prof.data is Array and not prof.data.is_empty():
		nickname = str(prof.data[0].get("nickname", ""))
		var av = prof.data[0].get("avatar")
		profile_avatar = str(av) if av != null else ""
		if profile_avatar == "" and GameSettings.get_value("game", "avatar", "") != "":
			set_avatar(GameSettings.get_value("game", "avatar", ""))  # carry the guest pick over
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
