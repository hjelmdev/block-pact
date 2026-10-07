class_name CombinedInputSource
extends InputSource
## ORs several sources together (e.g. keyboard + on-screen touch for the
## same player).

var sources: Array[InputSource] = []


func _init(p_sources: Array) -> void:
	for s in p_sources:
		sources.append(s)


func bind(p_sim: MatchSimulation, p_player_id: int) -> void:
	super(p_sim, p_player_id)
	for s in sources:
		s.bind(p_sim, p_player_id)


func is_local_human() -> bool:
	for s in sources:
		if s.is_local_human():
			return true
	return false


func gather(tick: int) -> int:
	var bits := 0
	for s in sources:
		var b := s.gather(tick)
		if b == InputCommand.NOT_READY:
			return b
		bits |= b
	return bits
