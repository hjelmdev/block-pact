class_name SpecialBlockType
extends Resource
## A special cell type such as x2 / x3 / x5. Gameplay-only data; the look
## lives in the BlockSkin (looked up by [member key]).

## Stable numeric id stored in board cells. Must be > 0 and unique per mode.
@export var id: int = 1
## Key used by skins / sounds, e.g. &"x5".
@export var key: StringName = &"x5"
@export var multiplier: int = 5
## Relative weight when a piece rolls a special cell.
@export var spawn_weight: float = 1.0
