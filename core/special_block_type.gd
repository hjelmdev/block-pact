class_name SpecialBlockType
extends Resource
## A special cell type such as x5, a bomb or a laser. Gameplay-only data; the
## look lives in the BlockSkin (looked up by [member key]).
##
## Special cells trigger when the row they sit in is cleared.

enum Effect {
	## Multiplies the owner's share of the row (see ScoreRules.special_mode).
	MULTIPLIER,
	## Destroys locked blocks within [member radius] (1 = 3x3, 2 = 5x5).
	BOMB,
	## Destroys the whole column.
	LASER,
	## Repaints blocks within [member radius] in the cell owner's color.
	PAINT,
	## Flat bonus (× level) to the player who finished the row.
	GOLD,
	## The player who finished the row gets a random powerup.
	POWERUP,
}

## Stable numeric id stored in board cells. Must be > 0 and unique per mode.
@export var id: int = 1
## Key used by skins / sounds, e.g. &"x5".
@export var key: StringName = &"x5"
@export var effect: Effect = Effect.MULTIPLIER
@export var multiplier: int = 5
@export var radius: int = 1
@export var bonus_points: int = 0
## Relative weight when a piece rolls a special cell.
@export var spawn_weight: float = 1.0


func is_multiplier() -> bool:
	return effect == Effect.MULTIPLIER
