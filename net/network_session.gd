class_name NetworkSession
extends Node
## Abstract transport for online play – NOT implemented in the MVP.
##
## Planned design (deterministic lockstep, fits the existing core):
##   1. Host creates a lobby, players join (WebSocket relay or WebRTC with
##      Supabase Realtime as signaling – both work in browsers).
##   2. Host broadcasts MatchSetup.to_dict() including the seed.
##   3. Every peer runs the same MatchSimulation. Each tick, each peer sends
##      its local players' InputCommand bits for tick + input_delay.
##   4. Remote seats use a NetworkInputSource (see ScriptedInputSource) that
##      returns InputCommand.NOT_READY until the frame arrives; the
##      MatchController then simply waits (stall) – no desync possible.
##   5. Bots run on the host and their inputs are broadcast like a human's.
## Rollback can later be layered on top because the simulation is cheap to
## copy and fully deterministic.

signal peer_joined(peer_id: int, info: Dictionary)
signal peer_left(peer_id: int)
signal setup_received(setup_dict: Dictionary)
signal input_received(tick: int, slot: int, bits: int)
signal connection_failed(reason: String)

## Ticks of input delay used to hide latency.
var input_delay: int = 3


func is_online() -> bool:
	return false


func is_host() -> bool:
	return true


func host_lobby(_options: Dictionary) -> void:
	connection_failed.emit("Online play is not available yet")


func join_lobby(_code: String) -> void:
	connection_failed.emit("Online play is not available yet")


func send_setup(_setup: MatchSetup) -> void:
	pass


func send_input(_tick: int, _slot: int, _bits: int) -> void:
	pass


func leave() -> void:
	pass
