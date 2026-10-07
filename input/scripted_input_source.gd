class_name ScriptedInputSource
extends InputSource
## Plays back a recorded list of per-tick inputs (replays, tests, and a
## template for the future NetworkInputSource which fills [member frames]
## from the network and returns NOT_READY while waiting).

## tick -> bits
var frames: Dictionary = {}
var stall_when_missing: bool = false


func push_frame(tick: int, bits: int) -> void:
	frames[tick] = bits


func gather(tick: int) -> int:
	if frames.has(tick):
		return frames[tick]
	return InputCommand.NOT_READY if stall_when_missing else InputCommand.NONE
