class_name InputCommand
extends RefCounted
## Bit flags for one player's input during one simulation tick.
##
## Input sources (keyboard, touch, bots, network) produce an int per tick.
## The simulation only ever sees these ints, which keeps it deterministic and
## trivially serializable for networking / replays.

const NONE := 0
const LEFT := 1
const RIGHT := 2
const SOFT_DROP := 4
const HARD_DROP := 8
const ROTATE_CW := 16
const ROTATE_CCW := 32
const HOLD := 64

## Returned by an input source that has no data yet for a tick (lockstep stall).
const NOT_READY := -1


static func has(bits: int, flag: int) -> bool:
	return bits & flag != 0
