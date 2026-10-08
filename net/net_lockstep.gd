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
## Ticks per frame while replaying a backlog (after being away).
const FAST_CATCH_UP := 120
## Backlog (beyond the input delay) that switches to fast catch-up.
const FAST_THRESHOLD := 20

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
	# Far behind (we were away and the host kept our seat going): replay the
	# buffered ticks quickly, sampling local seats as the simulation moves.
	var budget := FAST_CATCH_UP if ticks_buffered() > delay + FAST_THRESHOLD else MAX_CATCH_UP
	var fast := budget > MAX_CATCH_UP
	var first := next_local
	var sampled := {}
	var sampled_count := 0
	var steps := 0
	while true:
		# 1) Sample local seats up to `delay` ticks ahead of the simulation.
		while next_local < sim.tick_count + delay + 1 and sampled_count < budget:
			for slot in local_slots:
				var b := sources[slot].gather(sim.tick_count)
				b = clampi(b, 0, 255)
				frames[slot][next_local] = b
				if not sampled.has(slot):
					sampled[slot] = PackedByteArray()
				sampled[slot].append(b)
			next_local += 1
			sampled_count += 1
		# 2) Advance while every seat's input for the next tick is known.
		if steps >= budget or sim.finished or not _step_if_ready():
			break
		steps += 1
		# Normal pace: only catch up when behind the local sampling horizon.
		if not fast and sim.tick_count + delay >= next_local:
			break
	for slot: int in sampled:
		send_inputs.emit(slot, first, sampled[slot])
	if steps == 0:
		stalled_frames += 1
	return steps


func _step_if_ready() -> bool:
	var t := sim.tick_count
	var inputs := PackedInt32Array()
	inputs.resize(frames.size())
	for slot in frames.size():
		if not frames[slot].has(t):
			return false
		inputs[slot] = frames[slot][t]
	for slot in frames.size():
		frames[slot].erase(t)
	input_log.append(inputs)
	sim.step(inputs)
	return true


## How many ticks ahead of the simulation every remote seat's input is known.
func ticks_buffered() -> int:
	var lead := -1
	for slot in frames.size():
		if is_local(slot):
			continue
		var n := 0
		while frames[slot].has(sim.tick_count + n):
			n += 1
		lead = n if lead < 0 else mini(lead, n)
	return maxi(lead, 0)


## True when we are roughly live again (not replaying a backlog).
func caught_up() -> bool:
	return ticks_buffered() <= delay + FAST_THRESHOLD / 2


# --------------------------------------------------------------------------
# Away / back (a player's browser tab went to the background)

## Client: stop sending for our seats; the host feeds them from the next
## tick we have not sent yet. Returns the seats given away.
func go_away() -> Array[int]:
	var gone := local_slots.duplicate()
	for slot in gone:
		recv_next[slot] = next_local
	local_slots.clear()
	return gone


## Client: the host hands `slot` back; we sample it again from `tick`.
## Ticks before that come from the host (already relayed, ordered channel).
func resume(slot: int, tick: int) -> void:
	if is_local(slot):
		return
	if local_slots.is_empty():
		next_local = maxi(tick, sim.tick_count)
	else:
		# Other local seats already sampled ahead: give this one empty
		# inputs up to there so every seat stays in step.
		var fill := PackedByteArray()
		for t in range(tick, next_local):
			frames[slot][t] = 0
			fill.append(0)
		if not fill.is_empty():
			send_inputs.emit(slot, tick, fill)
	local_slots.append(slot)


## Host: stop feeding a taken-over seat. The owner sends from the returned
## tick on (everything before it has already been sent by us).
func release(slot: int) -> int:
	if not is_local(slot):
		return recv_next[slot]
	local_slots.erase(slot)
	recv_next[slot] = next_local
	return next_local


func missing_slots() -> Array[int]:
	var out: Array[int] = []
	for slot in frames.size():
		if not frames[slot].has(sim.tick_count):
			out.append(slot)
	return out
