extends Node
## Autoload "Net": online rooms with one player as host (peer-to-peer).
##
##   Supabase Realtime  – public room list (Presence) + WebRTC signaling
##                        (Broadcast). No database tables needed.
##   WebRTC             – the actual game traffic, star topology: every
##                        client talks to the host, the host relays inputs.
##
## The match itself is deterministic lockstep (see MatchController): peers
## only exchange per-tick input bits, never game state. A future dedicated
## headless Godot server can implement the same messages (NetProtocol).

signal state_changed(state: int)
signal rooms_changed(rooms: Array)
signal lobby_changed()
signal status(text: String, is_error: bool)
signal match_start(setup: MatchSetup, input_delay: int)
signal inputs_received(slot: int, first_tick: int, bits: PackedByteArray)
signal peer_dropped(peer_id: int)
signal host_lost()
signal return_to_lobby()
signal desync_detected(tick: int)
## Chat line added to [member chat_log] ({key, name, text, system}).
signal chat_received(entry: Dictionary)
## In-match quick emote from a player (realtime key + emote id).
signal emote_received(key: String, emote: String)

enum State { OFFLINE, BROWSING, HOSTING, JOINING, IN_ROOM, IN_MATCH }

const JOIN_TIMEOUT := 12.0
const PING_INTERVAL := 1.0
const HUMAN := -1  # lobby slot kind marker for a human seat
const EMOTES := ["gg", "nice", "oops", "wow", "hi", "gl"]
const CHAT_LOG_SIZE := 60
## Rate limit: at most this many chat lines per 10 seconds.
const CHAT_BURST := 5

var config: BackendConfig
var rt: RealtimeClient
var state: int = State.OFFLINE
var my_key: String = ""
var my_name: String = "Player"
var room_code: String = ""
var room_public: bool = true
var is_host: bool = false
var my_peer_id: int = 0
var rooms: Array = []
## Shared lobby description (host is the authority):
## { mode_id, collision, slots: [ {name, kind(HUMAN|BOT), peer_id, bot_profile_id, bot_personality_id} ] }
var lobby: Dictionary = {}
## peer_id -> {name, key, connected, ping_ms}
var peers: Dictionary = {}

var _mp: WebRTCMultiplayerPeer
var _conns: Dictionary = {}       # peer_id -> WebRTCPeerConnection
var _key_to_peer: Dictionary = {} # host: realtime key -> peer_id
var _next_peer_id := 2
var _room_topic := ""
var _lobby_topic := ""
var _hello_sent := false
var _join_timer := 0.0
var _ping_timer := 0.0
var _browse_wanted := false
## Lobby chat history for the current room (survives lobby <-> match).
var chat_log: Array = []
## Realtime keys of muted players (chat + emotes hidden).
var muted: Dictionary = {}
var _chat_times: Array = []
var _last_emote_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	config = BackendConfig.load_active()
	my_key = "%x%x" % [randi(), Time.get_ticks_usec()]
	rt = RealtimeClient.new()
	rt.name = "Realtime"
	add_child(rt)
	rt.broadcast_received.connect(_on_broadcast)
	rt.presence_changed.connect(_on_presence)
	rt.channel_error.connect(func(topic, msg): status.emit("Realtime: %s %s" % [topic, msg], true))
	rt.disconnected.connect(_on_rt_disconnected)


func is_available() -> bool:
	return config.online_available()


func webrtc_available() -> bool:
	if OS.has_feature("web"):
		return true
	var test := WebRTCPeerConnection.new()
	return test.initialize({}) == OK


# --------------------------------------------------------------------------
# Browsing public rooms

func start_browsing() -> void:
	_browse_wanted = true
	_ensure_connected()
	if _lobby_topic == "":
		_lobby_topic = rt.join(NetProtocol.LOBBY_CHANNEL, my_key)
	if state == State.OFFLINE:
		_set_state(State.BROWSING)


func stop_browsing() -> void:
	_browse_wanted = false
	if _lobby_topic != "" and not (is_host and room_public):
		rt.leave(_lobby_topic)
		_lobby_topic = ""


# --------------------------------------------------------------------------
# Hosting

func host_room(public: bool, player_name: String) -> void:
	leave_room()
	my_name = player_name
	is_host = true
	room_public = public
	my_peer_id = 1
	room_code = NetProtocol.make_code()
	_mp = WebRTCMultiplayerPeer.new()
	_mp.create_server()
	_wire_mp()
	peers = {1: {"name": my_name, "key": my_key, "connected": true, "ping_ms": 0}}
	lobby = {
		"mode_id": "shared_competition",
		"options": MatchOptions.saved_options(),
		"slots": [_human_slot_dict(1, my_name)],
		"code": room_code,
	}
	_ensure_connected()
	_room_topic = rt.join(NetProtocol.ROOM_PREFIX + room_code, my_key)
	rt.track(_room_topic, {"name": my_name, "host": true, "build": NetProtocol.build_id()})
	_set_state(State.HOSTING)
	if public:
		if _lobby_topic == "":
			_lobby_topic = rt.join(NetProtocol.LOBBY_CHANNEL, my_key)
		_advertise()
	lobby_changed.emit()


func host_set_mode(mode_id: String) -> void:
	if not is_host:
		return
	lobby.mode_id = mode_id
	var mode := MatchFactory.load_mode(StringName(mode_id))
	while lobby.slots.size() > mode.max_players:
		# drop bots first
		var removed := false
		for i in range(lobby.slots.size() - 1, -1, -1):
			if lobby.slots[i].kind != HUMAN:
				lobby.slots.remove_at(i)
				removed = true
				break
		if not removed:
			break
	_lobby_updated()


func host_set_options(options: Dictionary) -> void:
	if is_host:
		lobby.options = options.duplicate()
		_lobby_updated()


func host_add_bot(profile_id := "normal") -> void:
	if not is_host:
		return
	var mode := MatchFactory.load_mode(StringName(lobby.mode_id))
	if lobby.slots.size() >= mode.max_players:
		return
	var idx: int = lobby.slots.size()
	var b := MatchFactory.bot_slot(idx, StringName(profile_id))
	lobby.slots.append({"name": b.display_name, "kind": PlayerSlot.Kind.BOT, "peer_id": 1,
			"bot_profile_id": String(b.bot_profile_id), "bot_personality_id": String(b.bot_personality_id)})
	_lobby_updated()


func host_remove_slot(index: int) -> void:
	if not is_host or index <= 0 or index >= lobby.slots.size():
		return
	var s: Dictionary = lobby.slots[index]
	if s.kind == HUMAN and s.peer_id != 1:
		_send(s.peer_id, [NetProtocol.MSG_KICK, "Removed by host"])
		_drop_peer(s.peer_id)
		return
	lobby.slots.remove_at(index)
	_lobby_updated()


func host_can_start() -> bool:
	if not is_host or state != State.HOSTING:
		return false
	var mode := MatchFactory.load_mode(StringName(lobby.mode_id))
	if lobby.slots.size() < maxi(mode.min_players, 1):
		return false
	for s: Dictionary in lobby.slots:
		if s.kind == HUMAN and not peers.get(s.peer_id, {}).get("connected", false):
			return false
	return true


func host_start() -> void:
	if not host_can_start():
		return
	var setup := _lobby_to_setup()
	setup.seed = randi()
	var max_rtt := 0
	for pid: int in peers:
		max_rtt = maxi(max_rtt, int(peers[pid].get("ping_ms", 0)))
	# Half the round trip + margin, in 60 Hz ticks.
	var delay := clampi(ceili(float(max_rtt) * 0.5 / 16.7) + 3, 3, 12)
	var d := setup.to_dict()
	_send(0, [NetProtocol.MSG_START, d, delay])
	_set_state(State.IN_MATCH)
	_advertise()
	match_start.emit(_localize(d), delay)


func host_back_to_lobby() -> void:
	if not is_host:
		return
	_send(0, [NetProtocol.MSG_TO_LOBBY])
	_set_state(State.HOSTING)
	_advertise()
	return_to_lobby.emit()


# --------------------------------------------------------------------------
# Joining

func join_room(code: String, player_name: String) -> void:
	leave_room()
	my_name = player_name
	is_host = false
	room_code = NetProtocol.normalize_code(code)
	_hello_sent = false
	_join_timer = 0.0
	_ensure_connected()
	_room_topic = rt.join(NetProtocol.ROOM_PREFIX + room_code, my_key)
	rt.track(_room_topic, {"name": my_name, "host": false, "build": NetProtocol.build_id()})
	_set_state(State.JOINING)
	status.emit(tr("ONLINE_JOINING") % room_code, false)


## Sends a chat line to everyone in the room. Returns false if it was
## empty or rate-limited.
func send_chat(text: String) -> bool:
	text = ChatFilter.clean(text)
	if text == "" or _room_topic == "":
		return false
	var now := Time.get_ticks_msec()
	_chat_times = _chat_times.filter(func(t): return now - t < 10000)
	if _chat_times.size() >= CHAT_BURST:
		_add_chat({"key": "", "name": "", "text": tr("CHAT_SLOW_DOWN"), "system": true})
		return false
	_chat_times.append(now)
	rt.broadcast(_room_topic, "chat", {"from": my_key, "name": my_name, "text": text})
	_add_chat({"key": my_key, "name": my_name, "text": text, "system": false})
	return true


func send_emote(emote: String) -> void:
	var now := Time.get_ticks_msec()
	if _room_topic == "" or not EMOTES.has(emote) or now - _last_emote_ms < 1500:
		return
	_last_emote_ms = now
	rt.broadcast(_room_topic, "emote", {"from": my_key, "emote": emote})
	emote_received.emit(my_key, emote)


func set_muted(key: String, on: bool) -> void:
	if on:
		muted[key] = true
	else:
		muted.erase(key)


func key_for_peer(peer_id: int) -> String:
	return str(peers.get(peer_id, {}).get("key", ""))


func system_chat(text: String) -> void:
	_add_chat({"key": "", "name": "", "text": text, "system": true})


func _add_chat(entry: Dictionary) -> void:
	chat_log.append(entry)
	while chat_log.size() > CHAT_LOG_SIZE:
		chat_log.pop_front()
	chat_received.emit(entry)


func leave_room() -> void:
	chat_log.clear()
	if _mp:
		_mp.close()
	_mp = null
	_conns.clear()
	_key_to_peer.clear()
	peers.clear()
	lobby = {}
	_next_peer_id = 2
	if _room_topic != "":
		rt.leave(_room_topic)
		_room_topic = ""
	if is_host and _lobby_topic != "" and not _browse_wanted:
		rt.leave(_lobby_topic)
		_lobby_topic = ""
	elif is_host and _lobby_topic != "":
		rt.track(_lobby_topic, {"open": false})
	is_host = false
	my_peer_id = 0
	room_code = ""
	_set_state(State.BROWSING if _browse_wanted else State.OFFLINE)


# --------------------------------------------------------------------------
# In-match traffic

func send_inputs(slot: int, first_tick: int, bits: PackedByteArray) -> void:
	var msg := [NetProtocol.MSG_INPUTS, slot, first_tick, bits]
	if is_host:
		_send(0, msg)
	else:
		_send(1, msg)


func send_hash(tick: int, h: int) -> void:
	if not is_host:
		_send(1, [NetProtocol.MSG_HASH, tick, h])
	else:
		_host_hashes[tick] = h


func slot_index_for_peer(peer_id: int) -> Array[int]:
	var out: Array[int] = []
	for i in lobby.get("slots", []).size():
		var s: Dictionary = lobby.slots[i]
		if s.kind == HUMAN and s.peer_id == peer_id:
			out.append(i)
	return out


var _host_hashes: Dictionary = {}


# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _mp:
		_mp.poll()
		while _mp and _mp.get_available_packet_count() > 0:
			var from := _mp.get_packet_peer()
			var pkt := _mp.get_packet()
			var msg: Variant = bytes_to_var(pkt)
			if msg is Array and not msg.is_empty():
				_on_packet(from, msg)
	if state == State.JOINING:
		_join_timer += delta
		if _join_timer > JOIN_TIMEOUT:
			status.emit(tr("ONLINE_ROOM_NOT_FOUND") % room_code, true)
			leave_room()
	if is_host and _mp:
		_ping_timer += delta
		if _ping_timer >= PING_INTERVAL:
			_ping_timer = 0.0
			_send(0, [NetProtocol.MSG_PING, Time.get_ticks_msec()])


func _ensure_connected() -> void:
	if rt.is_open() or rt._ws.get_ready_state() == WebSocketPeer.STATE_CONNECTING:
		return
	if not is_available():
		status.emit(tr("ONLINE_NOT_CONFIGURED"), true)
		return
	rt.access_token = Auth.access_token if Auth.is_logged_in() else ""
	rt.connect_to_server(config.realtime_url())


func _on_rt_disconnected(reason: String) -> void:
	if state == State.OFFLINE:
		return
	status.emit(tr("ONLINE_DISCONNECTED") % reason, true)
	if state in [State.BROWSING, State.JOINING]:
		_lobby_topic = ""
		_room_topic = ""
		_set_state(State.OFFLINE)


func _set_state(s: int) -> void:
	if s != state:
		state = s
		state_changed.emit(s)


func _wire_mp() -> void:
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(_on_peer_disconnected)


# --- Realtime ---------------------------------------------------------------

func _on_presence(topic: String, presence_state: Dictionary) -> void:
	if topic == _lobby_topic:
		rooms.clear()
		for key: String in presence_state:
			var m: Dictionary = presence_state[key]
			if m.get("open", false) and m.get("build", "") == NetProtocol.build_id() and m.get("code", "") != "":
				rooms.append(m)
		rooms_changed.emit(rooms)
	elif topic == _room_topic:
		if state == State.JOINING and not _hello_sent:
			for key: String in presence_state:
				var m: Dictionary = presence_state[key]
				if m.get("host", false):
					if m.get("build", "") != NetProtocol.build_id():
						status.emit(tr("ONLINE_VERSION_MISMATCH"), true)
						leave_room()
						return
					_hello_sent = true
					rt.broadcast(_room_topic, "hello", {"from": my_key, "name": my_name, "build": NetProtocol.build_id()})
		elif not is_host and state in [State.IN_ROOM, State.IN_MATCH]:
			var host_present := false
			for key: String in presence_state:
				if presence_state[key].get("host", false):
					host_present = true
			if not host_present and not peers.get(1, {}).get("connected", false):
				_host_gone()
		elif is_host:
			# A client vanished from Realtime before WebRTC connected.
			for key: String in _key_to_peer.keys():
				var pid: int = _key_to_peer[key]
				if not presence_state.has(key) and not peers.get(pid, {}).get("connected", false):
					_drop_peer(pid)


func _on_broadcast(topic: String, event: String, p: Dictionary) -> void:
	if topic != _room_topic:
		return
	match event:
		"chat":
			var key := str(p.get("from", ""))
			if key != "" and key != my_key and not muted.has(key):
				var text := ChatFilter.clean(str(p.get("text", "")))
				if text != "":
					_add_chat({"key": key, "name": str(p.get("name", "?")).left(16), "text": text, "system": false})
		"emote":
			var ekey := str(p.get("from", ""))
			var emote := str(p.get("emote", ""))
			if ekey != my_key and not muted.has(ekey) and EMOTES.has(emote):
				emote_received.emit(ekey, emote)
		"hello":
			if is_host:
				_host_on_hello(p)
		"welcome":
			if not is_host and p.get("to", "") == my_key and state == State.JOINING:
				_client_on_welcome(int(p.peer_id))
		"reject":
			if not is_host and p.get("to", "") == my_key:
				status.emit(str(p.get("reason", "Rejected")), true)
				leave_room()
		"sdp":
			if int(p.get("to_peer", -1)) == my_peer_id:
				var c: WebRTCPeerConnection = _conns.get(int(p.from_peer))
				if c:
					c.set_remote_description(str(p.type), str(p.sdp))
		"ice":
			if int(p.get("to_peer", -1)) == my_peer_id:
				var c: WebRTCPeerConnection = _conns.get(int(p.from_peer))
				if c:
					c.add_ice_candidate(str(p.media), int(p.index), str(p.name))


func _host_on_hello(p: Dictionary) -> void:
	var key: String = p.get("from", "")
	if key == "" or _key_to_peer.has(key):
		return
	var mode := MatchFactory.load_mode(StringName(lobby.mode_id))
	var reason := ""
	if p.get("build", "") != NetProtocol.build_id():
		reason = tr("ONLINE_VERSION_MISMATCH")
	elif state != State.HOSTING:
		reason = tr("ONLINE_ALREADY_STARTED")
	elif lobby.slots.size() >= mode.max_players:
		reason = tr("ONLINE_ROOM_FULL")
	if reason != "":
		rt.broadcast(_room_topic, "reject", {"to": key, "reason": reason})
		return
	var pid := _next_peer_id
	_next_peer_id += 1
	_key_to_peer[key] = pid
	var pname := str(p.get("name", "Player")).left(16)
	peers[pid] = {"name": pname, "key": key, "connected": false, "ping_ms": 0}
	lobby.slots.append(_human_slot_dict(pid, pname))
	rt.broadcast(_room_topic, "welcome", {"to": key, "peer_id": pid})
	var conn := _new_connection(pid)
	if conn:
		conn.create_offer()
	_lobby_updated()


func _client_on_welcome(peer_id: int) -> void:
	my_peer_id = peer_id
	_mp = WebRTCMultiplayerPeer.new()
	_mp.create_client(peer_id)
	_wire_mp()
	_new_connection(1)
	status.emit(tr("ONLINE_CONNECTING"), false)


func _new_connection(remote_peer: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	var err := conn.initialize({"iceServers": config.ice_servers})
	if err != OK:
		status.emit(tr("ONLINE_NO_WEBRTC"), true)
		return null
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		rt.broadcast(_room_topic, "sdp", {"to_peer": remote_peer, "from_peer": my_peer_id, "type": type, "sdp": sdp}))
	conn.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		rt.broadcast(_room_topic, "ice", {"to_peer": remote_peer, "from_peer": my_peer_id, "media": media, "index": index, "name": cname}))
	_conns[remote_peer] = conn
	_mp.add_peer(conn, remote_peer)
	return conn


# --- WebRTC -----------------------------------------------------------------

func _on_peer_connected(pid: int) -> void:
	if is_host:
		if peers.has(pid):
			peers[pid].connected = true
		_lobby_updated()
	elif pid == 1:
		peers[1] = {"name": "Host", "key": "", "connected": true, "ping_ms": 0}
		_send(1, [NetProtocol.MSG_HELLO, my_name, Progress.user_id(), NetProtocol.build_id()])
		_set_state(State.IN_ROOM)
		status.emit(tr("ONLINE_CONNECTED"), false)


func _on_peer_disconnected(pid: int) -> void:
	if is_host:
		_drop_peer(pid)
	elif pid == 1:
		_host_gone()


func _drop_peer(pid: int) -> void:
	if not peers.has(pid):
		return
	var was_connected: bool = peers[pid].get("connected", false)
	peers.erase(pid)
	for key: String in _key_to_peer.keys():
		if _key_to_peer[key] == pid:
			_key_to_peer.erase(key)
	if _conns.has(pid):
		_conns.erase(pid)
	if _mp and _mp.has_peer(pid):
		_mp.remove_peer(pid)
	if state == State.IN_MATCH:
		# Keep the seat: the host feeds empty inputs for it from now on.
		peer_dropped.emit(pid)
		for i in slot_index_for_peer(pid):
			_send(0, [NetProtocol.MSG_SLOT_LEFT, i])
	else:
		for i in range(lobby.get("slots", []).size() - 1, -1, -1):
			var s: Dictionary = lobby.slots[i]
			if s.kind == HUMAN and s.peer_id == pid:
				lobby.slots.remove_at(i)
		if was_connected:
			status.emit(tr("ONLINE_PLAYER_LEFT"), false)
		_lobby_updated()


func _host_gone() -> void:
	var in_match := state == State.IN_MATCH
	status.emit(tr("ONLINE_HOST_LEFT"), true)
	leave_room()
	if in_match:
		host_lost.emit()


func _on_packet(from: int, msg: Array) -> void:
	var t: int = msg[0]
	match t:
		NetProtocol.MSG_HELLO:
			if is_host and peers.has(from):
				peers[from].name = str(msg[1]).left(16)
				for s: Dictionary in lobby.slots:
					if s.kind == HUMAN and s.peer_id == from:
						s.name = peers[from].name
				_lobby_updated()
		NetProtocol.MSG_LOBBY:
			if not is_host:
				lobby = msg[1]
				peers = msg[2] if msg.size() > 2 else peers
				lobby_changed.emit()
		NetProtocol.MSG_START:
			if not is_host:
				lobby_setup_dict = msg[1]
				_set_state(State.IN_MATCH)
				match_start.emit(_localize(msg[1]), int(msg[2]))
		NetProtocol.MSG_INPUTS:
			if is_host:
				# relay to everyone except the sender
				for pid: int in peers:
					if pid != 1 and pid != from and peers[pid].connected:
						_send(pid, msg)
			inputs_received.emit(int(msg[1]), int(msg[2]), msg[3])
		NetProtocol.MSG_HASH:
			if is_host and _host_hashes.has(int(msg[1])) and _host_hashes[int(msg[1])] != int(msg[2]):
				desync_detected.emit(int(msg[1]))
				_send(0, [NetProtocol.MSG_DESYNC, int(msg[1])])
		NetProtocol.MSG_DESYNC:
			desync_detected.emit(int(msg[1]))
		NetProtocol.MSG_PING:
			_send(from, [NetProtocol.MSG_PONG, msg[1]])
		NetProtocol.MSG_PONG:
			if is_host and peers.has(from):
				peers[from].ping_ms = Time.get_ticks_msec() - int(msg[1])
				if state == State.HOSTING:
					_lobby_updated(false)
		NetProtocol.MSG_KICK:
			status.emit(str(msg[1]), true)
			leave_room()
		NetProtocol.MSG_TO_LOBBY:
			_set_state(State.IN_ROOM)
			return_to_lobby.emit()
		NetProtocol.MSG_SLOT_LEFT:
			pass


var lobby_setup_dict: Dictionary = {}


func _send(target: int, msg: Array) -> void:
	if _mp == null:
		return
	var bytes := var_to_bytes(msg)
	_mp.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if target == 0:
		# Broadcast only to peers whose data channels are open.
		for pid: int in _conns:
			if _peer_open(pid):
				_mp.set_target_peer(pid)
				_mp.put_packet(bytes)
		return
	if _peer_open(target):
		_mp.set_target_peer(target)
		_mp.put_packet(bytes)


func _peer_open(pid: int) -> bool:
	if _mp == null or not _mp.has_peer(pid):
		return false
	return _mp.get_peer(pid).get("connected", false)


func _lobby_updated(advertise := true) -> void:
	if not is_host:
		return
	_send(0, [NetProtocol.MSG_LOBBY, lobby, peers])
	if advertise:
		_advertise()
	lobby_changed.emit()


func _advertise() -> void:
	if not is_host or not room_public or _lobby_topic == "":
		return
	var mode := MatchFactory.load_mode(StringName(lobby.get("mode_id", "shared_competition")))
	rt.track(_lobby_topic, {
		"code": room_code, "host": my_name, "mode": mode.display_name,
		"players": lobby.slots.size(), "max": mode.max_players,
		"open": state == State.HOSTING, "build": NetProtocol.build_id(),
	})


func _human_slot_dict(peer_id: int, pname: String) -> Dictionary:
	return {"name": pname, "kind": HUMAN, "peer_id": peer_id, "bot_profile_id": "", "bot_personality_id": ""}


func _lobby_to_setup() -> MatchSetup:
	var setup := MatchSetup.new()
	setup.mode = MatchFactory.load_mode(StringName(lobby.mode_id))
	setup.rule_overrides = MatchOptions.to_rule_overrides(lobby.get("options", {}))
	var slots: Array[PlayerSlot] = []
	for i in lobby.slots.size():
		var s: Dictionary = lobby.slots[i]
		var ps := PlayerSlot.new()
		ps.display_name = s.name
		ps.color_index = i
		ps.peer_id = s.peer_id
		if s.kind == HUMAN:
			ps.kind = PlayerSlot.Kind.REMOTE
		else:
			ps.kind = PlayerSlot.Kind.BOT
			ps.bot_profile_id = StringName(s.bot_profile_id)
			ps.bot_personality_id = StringName(s.bot_personality_id)
		slots.append(ps)
	setup.slots = slots
	return setup


## Turns the shared setup into this peer's view: my seat = local human,
## bots run only on the host, everything else is REMOTE (fed by Net).
func _localize(d: Dictionary) -> MatchSetup:
	var setup := MatchSetup.from_dict(d)
	for s in setup.slots:
		if s.kind == PlayerSlot.Kind.REMOTE and s.peer_id == my_peer_id:
			s.kind = PlayerSlot.Kind.LOCAL_HUMAN
			s.input_device = ControlSchemes.default_device()
			s.user_id = Progress.user_id()
		elif s.kind == PlayerSlot.Kind.BOT and not is_host:
			s.kind = PlayerSlot.Kind.REMOTE
	return setup
