extends Node
## End-to-end online test: run one host and one client process against a
## Realtime server (real Supabase or tests/mock_realtime_server.gd).
##   godot --headless --path . res://tests/online_test.tscn -- --role host --dir /tmp/bp --realtime-url ws://127.0.0.1:4000/x --no-stun
##   godot --headless --path . res://tests/online_test.tscn -- --role client --dir /tmp/bp ...
## Both write state hashes to <dir>/<role>_hashes.txt for comparison.

var role := "host"
var dir := "user://online_test"
var seconds := 25.0
var leave_after := -1.0
var _hashes: PackedStringArray = []
var _sim: MatchSimulation


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	var la := a.find("--leave-after")
	if la >= 0:
		leave_after = float(a[la + 1])
	for k in ["--role", "--dir", "--seconds"]:
		var i := a.find(k)
		if i >= 0 and i + 1 < a.size():
			match k:
				"--role": role = a[i + 1]
				"--dir": dir = a[i + 1]
				"--seconds": seconds = float(a[i + 1])
	DirAccess.make_dir_recursive_absolute(dir)
	Net.status.connect(func(t, e): print("[%s] status: %s%s" % [role, t, " (error)" if e else ""]))
	Net.desync_detected.connect(func(t): print("[%s] DESYNC at %d" % [role, t]))
	_detach.call_deferred()


func _detach() -> void:
	reparent(get_tree().root)
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	_run()


func _run() -> void:
	var code_file := dir + "/room_code.txt"
	if role == "host":
		DirAccess.remove_absolute(code_file)
		Net.host_room(true, "HostAda")
		Router.goto(&"online_lobby")
		await _wait(1.0)
		var f := FileAccess.open(code_file, FileAccess.WRITE)
		f.store_string(Net.room_code)
		f.close()
		print("[host] room ", Net.room_code)
		Net.host_add_bot("hard")
		var t := 0.0
		while not Net.host_can_start() or Net.lobby.slots.size() < 3:
			await _wait(0.25)
			t += 0.25
			if t > 30.0:
				print("[host] FAIL: client never connected")
				get_tree().quit(1)
				return
		print("[host] peers ", Net.peers)
		await _wait(1.0)
		Net.host_start()
	else:
		var t := 0.0
		while not FileAccess.file_exists(code_file):
			await _wait(0.25)
			t += 0.25
			if t > 20.0:
				print("[client] FAIL: no room code")
				get_tree().quit(1)
				return
		var code := FileAccess.get_file_as_string(code_file).strip_edges()
		await _wait(0.5)
		Net.join_room(code, "ClientByte")
		Net.state_changed.connect(func(s):
			if s == Net.State.IN_ROOM and Router.current != &"online_lobby" and Router.current != &"match":
				Router.goto(&"online_lobby"))
	# wait for the match scene
	var waited := 0.0
	while Router.current != &"match":
		await _wait(0.25)
		waited += 0.25
		if waited > 40.0:
			print("[%s] FAIL: match never started" % role)
			get_tree().quit(1)
			return
	await _wait(0.5)
	var ctrl: MatchController = get_tree().current_scene.get_node("MatchController")
	_sim = ctrl.sim
	# Let a bot play for the local human so the game has real moves.
	for i in ctrl.setup.slots.size():
		if ctrl.setup.slots[i].kind == PlayerSlot.Kind.LOCAL_HUMAN:
			var b := BotInputSource.new(BotProfile.load_profile(&"normal"))
			b.bind(_sim, i)
			ctrl.lockstep.sources[i] = b
	print("[%s] match started, delay %d, slots %s" % [role, ctrl.net_delay, ctrl.setup.slots.map(func(s): return [s.display_name, s.kind])])
	var elapsed := 0.0
	var last_logged := -1
	while elapsed < seconds:
		await get_tree().physics_frame
		elapsed += 1.0 / 60.0
		if leave_after > 0.0 and elapsed >= leave_after:
			print("[%s] leaving mid-match at tick %d" % [role, _sim.tick_count])
			Net.leave_room()
			break
		if _sim.tick_count % 120 == 0 and _sim.tick_count != last_logged and _sim.tick_count > 0:
			last_logged = _sim.tick_count
			_hashes.append("%d %d" % [_sim.tick_count, NetProtocol.state_hash(_sim)])
	var out := FileAccess.open("%s/%s_hashes.txt" % [dir, role], FileAccess.WRITE)
	out.store_string("\n".join(_hashes))
	out.close()
	print("[%s] done: tick %d, lines %d, stalls %d, finished %s" % [role, _sim.tick_count, _sim.total_lines, ctrl.lockstep.stalled_frames, _sim.finished])
	await _wait(1.0 if role == "host" else 3.0)
	get_tree().quit(0)


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, true).timeout
