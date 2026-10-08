class_name ScoreVerifier
extends Node
## Checks uploaded highscores by replaying them (server side).
##
## Clients upload a MatchReplay to `score_submissions`. This node claims open
## submissions through the service-role API, replays each one headless with
## the same deterministic MatchSimulation the game uses, and records the
## verdict. A verified score is written from the values computed here, never
## from what the client claimed (see supabase/migrations/0003_*).
##
## Needs the Supabase service-role key in the environment variable
## BLOCK_PACT_SERVICE_KEY. Never put that key in the game or the repository.

signal idle()
signal verdict(submission_id: int, status: String, reason: String)

const KEY_ENV := "BLOCK_PACT_SERVICE_KEY"
## Ticks replayed per frame – keeps rooms on the same server responsive.
const TICKS_PER_FRAME := 3000
const BATCH := 5

var poll_seconds := 5.0
var base_url := ""
var _key := ""
var _queue: Array = []
var _runner: MatchReplay.Runner
var _current: Dictionary = {}
var _busy := false
var _poll_in := 0.0


static func service_key() -> String:
	return OS.get_environment(KEY_ENV).strip_edges()


func _init(p_base_url: String, p_key: String) -> void:
	base_url = p_base_url.trim_suffix("/")
	_key = p_key


func _process(_delta: float) -> void:
	if _runner:
		if _runner.advance(TICKS_PER_FRAME):
			var job := _current
			var r := _runner
			_runner = null
			_current = {}
			_finish_replay(job, r)
		return
	if _busy:
		return
	if not _queue.is_empty():
		_start(_queue.pop_front())
		return
	_poll_in -= _delta
	if _poll_in <= 0.0:
		_poll_in = poll_seconds
		_claim()


func _claim() -> void:
	_busy = true
	var res := await _rpc("claim_score_submissions", {"p_limit": BATCH})
	_busy = false
	if res.ok and res.data is Array:
		_queue.append_array(res.data)
	if _queue.is_empty():
		idle.emit()


func _start(sub: Dictionary) -> void:
	var check := check_submission(sub)
	if check.has("status"):
		_report(sub, check.status, check.get("reason", ""))
		return
	_current = sub
	_runner = MatchReplay.Runner.new(check.replay)


## Static checks before replaying. Returns {replay} or a final {status, reason}.
static func check_submission(sub: Dictionary) -> Dictionary:
	if int(sub.get("sim_version", -1)) != MatchReplay.SIM_VERSION:
		return {"status": "unsupported", "reason": "sim version %d" % int(sub.get("sim_version", -1))}
	var parsed := MatchReplay.from_dict(sub.get("replay"))
	if parsed.get("unsupported", false):
		return {"status": "unsupported", "reason": "replay version"}
	if parsed.has("error"):
		return {"status": "rejected", "reason": "bad replay: %s" % parsed.error}
	var replay: MatchReplay = parsed.replay
	var mode := replay.setup.mode
	if not mode.leaderboard_enabled:
		return {"status": "rejected", "reason": "mode has no leaderboard"}
	if String(mode.mode_id) != str(sub.get("mode_id", "")):
		return {"status": "rejected", "reason": "mode mismatch"}
	var slot := int(sub.get("slot", -1))
	if slot < 0 or slot >= replay.slot_count:
		return {"status": "rejected", "reason": "bad slot"}
	if replay.setup.slots[slot].kind == PlayerSlot.Kind.BOT:
		return {"status": "rejected", "reason": "slot is a bot"}
	return {"replay": replay}


## Final verdict once the replay has run. Pure – also used by tests.
static func judge(sub: Dictionary, runner: MatchReplay.Runner) -> Dictionary:
	if not runner.consistent():
		return {"status": "rejected", "reason": "replay does not end the match"}
	var slot := int(sub.get("slot", -1))
	var p := runner.sim.get_player(slot)
	if p.score != int(sub.get("claimed_score", -1)):
		return {"status": "rejected", "reason": "score %d != claimed %d" % [p.score, int(sub.get("claimed_score", -1))]}
	if runner.sim.ruleset() != str(sub.get("ruleset", "")):
		return {"status": "rejected", "reason": "ruleset mismatch"}
	return {
		"status": "verified", "score": p.score, "lines": p.lines_finished,
		"players": runner.replay.slot_count,
		"duration_s": runner.sim.tick_count / MatchSimulation.TICKS_PER_SECOND,
	}


func _finish_replay(sub: Dictionary, runner: MatchReplay.Runner) -> void:
	var v := judge(sub, runner)
	_report(sub, v.status, v.get("reason", ""), v)


func _report(sub: Dictionary, status: String, reason: String, values: Dictionary = {}) -> void:
	_busy = true
	var id := int(sub.get("id", 0))
	var res := await _rpc("finish_score_submission", {
		"p_id": id, "p_status": status,
		"p_score": int(values.get("score", 0)), "p_lines": int(values.get("lines", 0)),
		"p_players": int(values.get("players", 1)), "p_duration_s": int(values.get("duration_s", 0)),
		"p_reason": reason if reason != "" else null,
	})
	_busy = false
	if not res.ok:
		push_warning("verifier: could not store verdict for %d (HTTP %d)" % [id, res.code])
	print("[verifier] submission %d: %s%s" % [id, status, (" – " + reason) if reason != "" else ""])
	verdict.emit(id, status, reason)


func _rpc(fn: String, body: Dictionary) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + _key,
		"Authorization: Bearer " + _key,
		"Content-Type: application/json",
	])
	var err := http.request("%s/rest/v1/rpc/%s" % [base_url, fn], headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if code < 200 or code >= 300:
		push_warning("verifier: %s failed (HTTP %d): %s" % [fn, code, str(data).left(200)])
	return {"ok": code >= 200 and code < 300, "code": code, "data": data}
