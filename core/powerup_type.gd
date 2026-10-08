class_name PowerupType
extends Resource
## A powerup a player can hold (one at a time) and activate with the
## USE_POWER input. Earned by finishing a row that contains a powerup cell.
## Gameplay data only; icon/name for UI live here too so new powerups can be
## added as .tres files (new effects need code in MatchSimulation).

enum Effect {
	## Your current (or next) piece explodes when it locks (3x3 around it).
	BOMB_PIECE,
	## Your pieces fall three times slower.
	SLOW,
	## Your line points are doubled.
	DOUBLE,
	## Every column settles: floating blocks fall down, full rows clear (credited to you).
	QUAKE,
	## Everyone else's pieces fall three times faster.
	RUSH,
}

## Stable id (> 0) stored in PlayerState.powerup.
@export var id: int = 1
## Key for skins, sounds and translations (POWERUP_<KEY>).
@export var key: StringName = &"bomb"
@export var effect: Effect = Effect.BOMB_PIECE
## Duration for timed effects, in simulation ticks (60 per second).
@export var duration_ticks: int = 600
@export var spawn_weight: float = 1.0
@export var icon: Texture2D


func is_timed() -> bool:
	return effect == Effect.SLOW or effect == Effect.DOUBLE or effect == Effect.RUSH
