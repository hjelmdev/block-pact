class_name PlayerSlot
extends Resource
## Who sits in one seat of a match and how they are controlled.
## Lives in MatchSetup; the simulation only reads name/team.

enum Kind { LOCAL_HUMAN, BOT, REMOTE }

@export var display_name: String = "Player"
@export var kind: Kind = Kind.LOCAL_HUMAN
## For LOCAL_HUMAN: a ControlSchemes id, e.g. &"kb_solo", &"kb_left", &"touch", &"joy_0".
@export var input_device: StringName = &"kb_solo"
## For BOT: id of a BotProfile in res://ai/profiles/ (e.g. &"normal").
@export var bot_profile_id: StringName = &"normal"
## Index into the PlayerPalette (visual only).
@export var color_index: int = 0
## -1 = let the game mode decide.
@export var team: int = -1
## Account id when logged in ("" for guests / bots).
@export var user_id: String = ""
## Network peer id when REMOTE.
@export var peer_id: int = 0


func to_dict() -> Dictionary:
	return {
		"display_name": display_name, "kind": kind, "input_device": String(input_device),
		"bot_profile_id": String(bot_profile_id), "color_index": color_index, "team": team,
		"user_id": user_id, "peer_id": peer_id,
	}


static func from_dict(d: Dictionary) -> PlayerSlot:
	var s := PlayerSlot.new()
	s.display_name = d.get("display_name", "Player")
	s.kind = d.get("kind", Kind.LOCAL_HUMAN)
	s.input_device = StringName(d.get("input_device", "kb_solo"))
	s.bot_profile_id = StringName(d.get("bot_profile_id", "normal"))
	s.color_index = d.get("color_index", 0)
	s.team = d.get("team", -1)
	s.user_id = d.get("user_id", "")
	s.peer_id = d.get("peer_id", 0)
	return s
