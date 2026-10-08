class_name MatchReplay
extends RefCounted
## A finished match as data: the setup plus every tick's inputs.
##
## Because the simulation is deterministic, replaying the inputs on the same
## setup reproduces the match exactly. The client uploads a replay with its
## score; the server replays it headless and only stores scores it could
## reproduce (see server/score_verifier.gd).
##
## Inputs are stored tick-major, one byte per seat (InputCommand bits fit in
## 0..255), deflate-compressed and base64-encoded.

## Must change whenever the simulation changes – old replays can no longer
## be reproduced by a newer build. Shared with the online protocol, which
## has the same requirement.
const SIM_VERSION := NetProtocol.VERSION
## Longest match we accept (60 min at 60 ticks/s). Keeps verification cheap.
const MAX_TICKS := 60 * 60 * MatchSimulation.TICKS_PER_SECOND
const MAX_SLOTS := 8
const MODES_DIR := "res://data/modes/"
## Lobby options a replay may override (see MatchOptions.to_rule_overrides).
const ALLOWED_OVERRIDES := {
	"active_piece_collision": [true, false],
	"powerups_enabled": [true, false],
	"special_preset": ["", "all", "off"],
}

var setup: MatchSetup
var slot_count: int = 0
var ticks: int = 0
## ticks * slot_count bytes
var inputs := PackedByteArray()


static func from_log(p_setup: MatchSetup, log: Array[PackedInt32Array]) -> MatchReplay:
	var r := MatchReplay.new()
	r.setup = p_setup
	r.slot_count = p_setup.slots.size()
	r.ticks = log.size()
	r.inputs.resize(r.ticks * r.slot_count)
	var k := 0
	for frame in log:
		for s in r.slot_count:
			r.inputs[k] = clampi(frame[s] if s < frame.size() else 0, 0, 255)
			k += 1
	return r


func frame(t: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(slot_count)
	var base := t * slot_count
	for s in slot_count:
		out[s] = inputs[base + s]
	return out


func to_dict() -> Dictionary:
	var packed := inputs.compress(FileAccess.COMPRESSION_DEFLATE)
	return {
		"v": SIM_VERSION,
		"setup": _setup_to_dict(setup),
		"slots": slot_count,
		"ticks": ticks,
		"inputs": Marshalls.raw_to_base64(packed),
	}


## Only what the simulation needs – no account ids or peer ids.
static func _setup_to_dict(s: MatchSetup) -> Dictionary:
	var d := s.to_dict()
	var slots := []
	for sd: Dictionary in d.slots:
		slots.append({"display_name": sd.display_name, "team": sd.team, "kind": sd.kind})
	d.slots = slots
	return d


## Parses and validates an uploaded replay. Returns {replay} or {error}.
## Never trust anything in `d`: it comes straight from a client.
static func from_dict(d: Variant) -> Dictionary:
	if not d is Dictionary:
		return {"error": "not an object"}
	if int(d.get("v", -1)) != SIM_VERSION:
		return {"error": "version", "unsupported": true}
	var sd: Variant = d.get("setup")
	if not sd is Dictionary:
		return {"error": "no setup"}
	var mode_path := str(sd.get("mode_path", ""))
	if not (mode_path.begins_with(MODES_DIR) and mode_path.ends_with(".tres")) or mode_path.contains("..") \
			or not ResourceLoader.exists(mode_path):
		return {"error": "mode"}
	var mode: Variant = load(mode_path)
	if not mode is GameModeConfig:
		return {"error": "mode"}
	var slots_in: Variant = sd.get("slots")
	if not slots_in is Array or slots_in.is_empty() or slots_in.size() > MAX_SLOTS:
		return {"error": "slots"}
	var overrides_in: Variant = sd.get("rule_overrides", {})
	if not overrides_in is Dictionary:
		return {"error": "overrides"}
	var overrides := {}
	for key in overrides_in:
		if not ALLOWED_OVERRIDES.has(key) or not ALLOWED_OVERRIDES[key].has(overrides_in[key]):
			return {"error": "override %s" % key}
		overrides[key] = overrides_in[key]
	var bs: Variant = sd.get("board_size_override", [0, 0])
	if not (bs is Array and bs.size() == 2 and int(bs[0]) == 0 and int(bs[1]) == 0):
		return {"error": "board size"}

	var s := MatchSetup.new()
	s.mode = mode
	s.seed = int(sd.get("seed", 0))
	s.rule_overrides = overrides
	for item: Variant in slots_in:
		if not item is Dictionary:
			return {"error": "slot"}
		var slot := PlayerSlot.new()
		slot.display_name = str(item.get("display_name", "Player")).left(24)
		slot.team = clampi(int(item.get("team", -1)), -1, MAX_SLOTS)
		slot.kind = clampi(int(item.get("kind", 0)), 0, PlayerSlot.Kind.size() - 1) as PlayerSlot.Kind
		s.slots.append(slot)
	if s.slots.size() < mode.min_players or s.slots.size() > mode.max_players:
		return {"error": "player count"}

	var r := MatchReplay.new()
	r.setup = s
	r.slot_count = s.slots.size()
	r.ticks = int(d.get("ticks", 0))
	if int(d.get("slots", 0)) != r.slot_count or r.ticks <= 0 or r.ticks > MAX_TICKS:
		return {"error": "ticks"}
	var raw := Marshalls.base64_to_raw(str(d.get("inputs", "")))
	var expected := r.ticks * r.slot_count
	r.inputs = raw.decompress(expected, FileAccess.COMPRESSION_DEFLATE) if not raw.is_empty() else PackedByteArray()
	if r.inputs.size() != expected:
		return {"error": "inputs"}
	return {"replay": r}


## Replays a match step by step (so a server can spread the work over
## several frames). Call `advance()` until it returns true, then read `sim`.
class Runner:
	extends RefCounted
	var replay: MatchReplay
	var sim: MatchSimulation
	var _t := 0

	func _init(p_replay: MatchReplay) -> void:
		replay = p_replay
		sim = MatchSimulation.new(replay.setup)
		sim.start()

	## Runs up to `budget` ticks. Returns true when the replay is done.
	func advance(budget: int) -> bool:
		var end := mini(_t + budget, replay.ticks)
		while _t < end and not sim.finished:
			sim.step(replay.frame(_t))
			_t += 1
		return _t >= replay.ticks or sim.finished

	## True when the replay ends exactly where the match ended.
	func consistent() -> bool:
		return sim.finished and _t == replay.ticks and sim.tick_count == replay.ticks
