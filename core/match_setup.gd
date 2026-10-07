class_name MatchSetup
extends Resource
## Complete description needed to start (or replay / sync) a match.
## Same seed + same setup + same per-tick inputs => identical match.

@export var mode: GameModeConfig
@export var slots: Array[PlayerSlot] = []
@export var seed: int = 0
## Overrides the mode's board size when non-zero.
@export var board_size_override: Vector2i = Vector2i.ZERO


func player_count() -> int:
	return slots.size()


func has_human() -> bool:
	for s in slots:
		if s.kind == PlayerSlot.Kind.LOCAL_HUMAN:
			return true
	return false


func human_count() -> int:
	var n := 0
	for s in slots:
		if s.kind == PlayerSlot.Kind.LOCAL_HUMAN:
			n += 1
	return n


func to_dict() -> Dictionary:
	var arr := []
	for s in slots:
		arr.append(s.to_dict())
	return {
		"mode_path": mode.resource_path if mode else "",
		"slots": arr,
		"seed": seed,
		"board_size_override": [board_size_override.x, board_size_override.y],
	}


static func from_dict(d: Dictionary) -> MatchSetup:
	var m := MatchSetup.new()
	var path: String = d.get("mode_path", "")
	if path != "":
		m.mode = load(path)
	for sd: Dictionary in d.get("slots", []):
		m.slots.append(PlayerSlot.from_dict(sd))
	m.seed = d.get("seed", 0)
	var bs: Array = d.get("board_size_override", [0, 0])
	m.board_size_override = Vector2i(bs[0], bs[1])
	return m
