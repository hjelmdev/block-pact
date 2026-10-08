class_name NetProtocol
extends RefCounted
## Message ids and helpers for the peer-to-peer game protocol.
## Packets are var_to_bytes([MSG_*, ...]) sent over WebRTC data channels.

## Bump when the simulation or protocol changes – peers must match exactly
## because lockstep requires bit-identical simulations.
const VERSION := 2

const MSG_HELLO := 1        # C->H [name, user_id, version]
const MSG_LOBBY := 2        # H->C [lobby_dict]
const MSG_START := 3        # H->C [setup_dict, input_delay]
const MSG_INPUTS := 4       # both [slot, first_tick, PackedByteArray]
const MSG_HASH := 5         # C->H [tick, hash]
const MSG_PING := 6         # [time_ms]
const MSG_PONG := 7         # [time_ms]
const MSG_KICK := 8         # H->C [reason]
const MSG_TO_LOBBY := 9     # H->C []
const MSG_DESYNC := 10      # H->C [tick]
const MSG_SLOT_LEFT := 11   # H->C [slot] (info only; host keeps feeding inputs)

const ROOM_PREFIX := "bp-room-"
const LOBBY_CHANNEL := "bp-lobbies"
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


static func make_code(length := 5) -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var s := ""
	for i in length:
		s += CODE_CHARS[rng.randi_range(0, CODE_CHARS.length() - 1)]
	return s


static func normalize_code(code: String) -> String:
	return code.strip_edges().to_upper().replace(" ", "")


static func build_id() -> String:
	return "%d-%s" % [VERSION, Engine.get_version_info().string]


## Hash of everything that must be identical on all peers.
static func state_hash(sim: MatchSimulation) -> int:
	var parts: Array = [sim.tick_count, sim.total_lines, sim.board.owners, sim.board.specials]
	for p in sim.players:
		parts.append(p.score)
		parts.append(p.active.position if p.active else Vector2i(-1, -1))
		parts.append([p.powerup, p.slow_ticks, p.double_ticks, p.rush_ticks, p.bomb_armed, p.lives, p.alive])
	return hash(parts)
