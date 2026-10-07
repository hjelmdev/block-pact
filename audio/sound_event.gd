class_name SoundEvent
extends Resource
## One named game sound. Several streams = random variation.

@export var id: StringName = &""
@export var streams: Array[AudioStream] = []
@export_range(-40.0, 12.0) var volume_db: float = 0.0
@export_range(0.0, 0.5) var pitch_random: float = 0.0
## Max simultaneous instances of this sound (avoids stacking 8 lock sounds).
@export var max_polyphony: int = 3
@export var bus: StringName = &"SFX"
