extends Node
## Autoload "AudioManager": plays SoundEvents by id from the active
## SoundLibrary. Gameplay code never references audio files directly.

const POOL_SIZE := 16

var library: SoundLibrary
var _pool: Array[AudioStreamPlayer] = []
var _playing_count: Dictionary = {}
var _music: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_pool.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = &"Music"
	add_child(_music)
	set_library(Assets.sounds())
	_apply_volumes()
	GameSettings.setting_changed.connect(func(section, _k, _v):
		if section == "audio":
			_apply_volumes())


func set_library(lib: SoundLibrary) -> void:
	library = lib


## Play a sound event. `pitch` lets callers raise pitch (e.g. for combos).
func play(id: StringName, pitch: float = 1.0, volume_offset_db: float = 0.0) -> void:
	if library == null:
		return
	var ev := library.get_event(id)
	if ev == null or ev.streams.is_empty():
		return
	if _playing_count.get(id, 0) >= ev.max_polyphony:
		return
	var player := _free_player()
	if player == null:
		return
	player.stream = ev.streams[randi() % ev.streams.size()]
	player.volume_db = ev.volume_db + volume_offset_db
	player.pitch_scale = pitch * (1.0 + randf_range(-ev.pitch_random, ev.pitch_random))
	player.bus = ev.bus
	player.set_meta(&"sfx_id", id)
	_playing_count[id] = _playing_count.get(id, 0) + 1
	player.play()


func play_music() -> void:
	if library == null or library.music == null:
		return
	if _music.playing and _music.stream == library.music:
		return
	var stream := library.music
	# Safety net – the music .import file already enables looping.
	if stream is AudioStreamWAV and stream.loop_mode == AudioStreamWAV.LOOP_DISABLED \
			and stream.format == AudioStreamWAV.FORMAT_16_BITS and not stream.stereo:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2  # 16-bit mono samples
	_music.stream = stream
	_music.volume_db = library.music_volume_db
	_music.play()


func stop_music() -> void:
	_music.stop()


func _free_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return null


func _on_finished(p: AudioStreamPlayer) -> void:
	var id: StringName = p.get_meta(&"sfx_id", &"")
	_playing_count[id] = maxi(0, _playing_count.get(id, 0) - 1)


func _apply_volumes() -> void:
	_set_bus_volume(&"Master", GameSettings.get_value("audio", "master", 0.8))
	_set_bus_volume(&"Music", GameSettings.get_value("audio", "music", 0.6))
	_set_bus_volume(&"SFX", GameSettings.get_value("audio", "sfx", 0.8))


func _set_bus_volume(bus: StringName, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
		AudioServer.set_bus_mute(idx, linear <= 0.001)


func _ensure_buses() -> void:
	for bus_name in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, &"Master")
