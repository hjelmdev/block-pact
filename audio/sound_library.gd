class_name SoundLibrary
extends Resource
## Maps game event ids (see Sfx) to sounds. Swap the whole library or edit
## single SoundEvents in the inspector – no code changes needed.

@export var events: Array[SoundEvent] = []
@export var music: AudioStream
@export_range(-40.0, 6.0) var music_volume_db: float = -8.0

var _index: Dictionary = {}


func get_event(id: StringName) -> SoundEvent:
	if _index.is_empty():
		for e in events:
			_index[e.id] = e
	return _index.get(id)
