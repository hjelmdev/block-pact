class_name NetLockstep
extends RefCounted
## Deterministic lockstep driver for online matches.
##
## Every peer runs the same MatchSimulation. Local seats (my human, and on
## the host also bots / abandoned seats) are sampled `delay` ticks ahead and
## their bits are sent out; the simulation only advances tick T once the
## bits of every seat for T are known. Ticks 0..delay-1 are empty for all.
##
## Transport-agnostic: hook `send_inputs` to the network and call
## `receive()` for incoming bits (see Net service / tests).

signal send_inputs(slot: int, first_tick: int, bits: PackedByteArray)

const MAX_CATCH_UP := 4

var sim: MatchSimulation
var sources: Array[InputSource]
var delay: int
var local_slots: Array[int] = []
## per slot: tick -> bits
var frames: Array[Dictionary] = []
## per slot: next tick we expect to receive (remote) – used for take-over
var recv_next: PackedInt32Array
var next_local: int
## Frames the sim had to wait (for "waiting for player" UI / stats)
var stalled_frames: int = 0
var input_log: Array[PackedInt32Array] = []


func _init(p_sim: MatchSimulation, p_sources: Array[InputSource], p_local_slots: Array[int], p_delay: int) -> void:
	sim = p_sim
	sources = p_sources
	delay = maxi(1, p_delay)
	local_slots = p_local_slots.duplicate()
	var n := sources.size()
	recv_next = PackedInt32Array()
	recv_next.resize(n)
	recv_next.fill(delay)
	for i in n:
		var d := {}
		for t in delay:
			d[t] = 0
		frames.append(d)
	next_local = delay


func is_local(slot: int) -> bool:
	return local_slots.has(slot)


func receive(slot: int, first_tick: int, bits: PackedByteArray) -> void:
	if slot < 0 or slot >= frames.size() or is_local(slot):
		return
	for k in bits.size():
		var t := first_tick + k
		if t >= sim.tick_count:
			frames[slot][t] = bits[k]
	recv_next[slot] = maxi(recv_next[slot], first_tick + bits.size())


## Host only: a player left – keep their seat alive with empty inputs,
## starting right after the last tick we received (and relayed) from them.
func take_over(slot: int) -> void:
	if is_local(slot):
		return
	var from := recv_next[slot]
	var fill := PackedByteArray()
	for t in range(from, next_local):
		frames[slot][t] = 0
		fill.append(0)
	if not fill.is_empty():
		send_inputs.emit(slot, from, fill)
	sources[slot] = InputSource.new()
	sources[slot].bind(sim, slot)
	local_slots.append(slot)


## Call once per physics frame. Returns how many ticks were simulated.
func update() -> int:
	# 1) Sample local seats up to `delay` ticks ahead of the simulation.
	var first := next_local
	var sampled := {}
	var guard := 0
	while next_local < sim.tick_count + delay + 1 and guard < MAX_CATCH_UP:
		for slot in local_slots:
			var b := sources[slot].gather(sim.tick_count)
			b = clampi(b, 0, 255)
			frames[slot][next_local] = b
			if not sampled.has(slot):
				sampled[slot] = PackedByteArray()
			sampled[slot].append(b)
		next_local += 1
		guard += 1
	for slot: int in sampled:
		send_inputs.emit(slot, first, sampled[slot])

	# 2) Advance while every seat's input for the next tick is known.
	var steps := 0
	while steps < MAX_CATCH_UP and not sim.finished:
		var t := sim.tick_count
		var inputs := PackedInt32Array()
		inputs.resize(frames.size())
		var ready := true
		for slot in frames.size():
			if not frames[slot].has(t):
				ready = false
				break
			inputs[slot] = frames[slot][t]
		if not ready:
			break
		for slot in frames.size():
			frames[slot].erase(t)
		input_log.append(inputs)
		sim.step(inputs)
		steps += 1
		# Only catch up when we are behind the local sampling horizon.
		if sim.tick_count + delay >= next_local:
			break
	if steps == 0:
		stalled_frames += 1
	return steps


func missing_slots() -> Array[int]:
	var out: Array[int] = []
	for slot in frames.size():
		if not frames[slot].has(sim.tick_count):
			out.append(slot)
	return out
