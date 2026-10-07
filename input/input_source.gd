class_name InputSource
extends RefCounted
## Produces one InputCommand bitmask per simulation tick for one player.
##
## Everything that can control a player implements this: keyboard, touch,
## gamepad, bots and (later) network peers. The match controller does not
## care which kind it is talking to, which is what keeps singleplayer,
## bots and multiplayer on the same code path.

var sim: MatchSimulation
var player_id: int = -1


func bind(p_sim: MatchSimulation, p_player_id: int) -> void:
	sim = p_sim
	player_id = p_player_id


## Return InputCommand bits for this tick, or InputCommand.NOT_READY if this
## source has no data yet (e.g. waiting for a remote peer in lockstep).
func gather(_tick: int) -> int:
	return InputCommand.NONE


## True for sources driven by a person on this device (used for ghosts, HUD focus …).
func is_local_human() -> bool:
	return false


func dispose() -> void:
	pass
