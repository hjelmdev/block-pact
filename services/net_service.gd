extends Node
## Autoload "Net": online rooms for this game client.
##
##   Supabase Realtime  – public room list (Presence), WebRTC signaling and
##                        chat (Broadcast). No database tables needed.
##   WebRTC             – the actual game traffic, star topology: every
##                        client talks to the host, the host relays inputs.
##
## Two ways to play online, same code for both:
##   * host from the game: Net owns a RoomHost (this player is peer 1), or
##   * join a room – hosted by another player or by the dedicated headless
##     server (server/server_main.gd), which runs many RoomHosts.
## The match itself is deterministic lockstep (MatchController + NetLockstep):
## peers only exchange per-tick input bits, never game state.

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
## Host side: a player's tab went to the background / came back.
signal peer_away(peer_id: int)
signal peer_back(peer_id: int)
## Client side: our seat is ours again from `tick` (after being away).
signal seat_returned(slot: int, tick: int)
## UI: seat `slot` is away or back (-1 = the host).
signal away_info(slot: int, away: bool)
## Chat line added to [member chat_log] ({key, name, text, system}).
signal chat_received(entry: Dictionary)
## In-match quick emote from a player (realtime key + emote id).
signal emote_received(key: String, emote: String)

enum State { OFFLINE, BROWSING, HOSTING, JOINING, IN_ROOM, IN_MATCH }

const JOIN_TIMEOUT := 12.0
const HUMAN := RoomHost.HUMAN  # lobby slot kind marker for a human seat
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
## Lobby chat history for the current room (survives lobby <-> match).
var chat_log: Array = []
## Realtime keys of muted players (chat + emotes hidden).
var muted: Dictionary = {}

## Shared lobby description (the host / RoomHost is the authority):
## { mode_id, options, leader, slots: [ {name, kind(HUMAN|BOT), peer_id, bot_profile_id, bot_personality_id, avatar} ] }
var lobby: Dictionary:
	get:
		return _room.lobby if _room else _client_lobby
	set(v):
		_client_lobby = v
## peer_id -> {name, key, connected, ping_ms}
var peers: Dictionary:
	get:
		return _room.peers if _room else _client_peers
	set(v):
		_client_peers = v

var _room: RoomHost
var _client_lobby: Dictionary = {}
var _client_peers: Dictionary = {}
var _mp: WebRTCMultiplayerPeer  # client side only
var _conns: Dictionary = {}
var _room_topic := ""
var _lobby_topic := ""
var _hello_sent := false
var _join_timer := 0.0
var _browse_wanted := false
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


## May change mode / options / bots and start (host, or a server room's leader).
func is_leader() -> bool:
	return is_host or (my_peer_id != 0 and int(lobby.get("leader", 0)) == my_peer_id)


## Lockstep endpoint: the host is the authority for its room.
func is_authority() -> bool:
	return is_host


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


## Turns lobby-channel presence into a room list. A player-hosted room is
## one presence entry; a server lists all its open rooms in one entry.
static func parse_rooms(presence_state: Dictionary) -> Array:
	var out: Array = []
	for key: String in presence_state:
		var m: Dictionary = presence_state[key]
		if m.get("build", "") != NetProtocol.build_id():
			continue
		if m.has("rooms"):
			for r: Dictionary in m.rooms:
				if r.get("open", false) and r.get("code", "") != "":
					var e := r.duplicate()
					e["server"] = true
					out.append(e)
		elif m.get("open", false) and m.get("code", "") != "":
			out.append(m)
	return out


# --------------------------------------------------------------------------
# Hosting (this player is the room's host)

func host_room(public: bool, player_name: String) -> void:
	leave_room()
	my_name = player_name
	is_host = true
	room_public = public
	my_peer_id = 1
	room_code = NetProtocol.make_code()
	_ensure_connected()
	_room = RoomHost.new(rt, my_key, my_name, true, config.ice_servers)
	_room.name = "Room"
	_room.local_avatar = Progress.avatar()
	_room.local_user_id = Progress.user_id()
	add_child(_room)
	_room.lobby_changed.connect(func(): lobby_changed.emit())
	_room.status.connect(func(t, e): status.emit(t, e))
	_room.inputs_received.connect(func(s, f, b): inputs_received.emit(s, f, b))
	_room.peer_dropped.connect(func(p): peer_dropped.emit(p))
	_room.desync_detected.connect(func(t): desync_detected.emit(t))
	_room.peer_away.connect(func(p): peer_away.emit(p))
	_room.peer_back.connect(func(p): peer_back.emit(p))
	_room.away_info.connect(func(sl, a): away_info.emit(sl, a))
	_room.advert_changed.connect(_advertise)
	_room.match_start.connect(func(setup, delay):
		_set_state(State.IN_MATCH)
		match_start.emit(setup, delay))
	_room.return_to_lobby.connect(func():
		_set_state(State.HOSTING)
		return_to_lobby.emit())
	_room.open(room_code, public, MatchOptions.saved_options())
	_room_topic = _room.topic
	_set_state(State.HOSTING)
	if public:
		if _lobby_topic == "":
			_lobby_topic = rt.join(NetProtocol.LOBBY_CHANNEL, my_key)
		_advertise()
	lobby_changed.emit()


# Lobby controls. The host applies them directly; a server room's leader
# sends them as commands to the server.

func host_set_mode(mode_id: String) -> void:
	_control("mode", mode_id)


func host_set_options(options: Dictionary) -> void:
	_control("options", options)


func host_add_bot(profile_id := "normal") -> void:
	_control("add_bot", profile_id)


func host_remove_slot(index: int) -> void:
	_control("remove", index)


func host_start() -> void:
	_control("start", null)


func host_back_to_lobby() -> void:
	_control("to_lobby", null)


func host_can_start() -> bool:
	if not is_leader() or not state in [State.HOSTING, State.IN_ROOM]:
		return false
	return RoomHost.can_start(lobby, peers)


func _control(cmd: String, arg: Variant) -> void:
	if _room:
		_room.apply_command(1, cmd, arg)
	elif is_leader():
		_send(1, [NetProtocol.MSG_CMD, cmd, arg])


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


func leave_room() -> void:
	chat_log.clear()
	if _room:
		_room.close()
		_room.queue_free()
		_room = null
	elif _room_topic != "":
		rt.leave(_room_topic)
	_room_topic = ""
	if _mp:
		_mp.close()
	_mp = null
	_conns.clear()
	_client_peers = {}
	_client_lobby = {}
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
# Chat and emotes (Realtime broadcast in the room channel)

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


# --------------------------------------------------------------------------
# In-match traffic (lockstep endpoint)

func send_inputs(slot: int, first_tick: int, bits: PackedByteArray) -> void:
	if _room:
		_room.send_inputs(slot, first_tick, bits)
	else:
		_send(1, [NetProtocol.MSG_INPUTS, slot, first_tick, bits])


func send_hash(tick: int, h: int) -> void:
	if _room:
		_room.send_hash(tick, h)
	else:
		_send(1, [NetProtocol.MSG_HASH, tick, h])


## Our tab went to the background (true) or is visible again (false).
## A client only reports "away"; it says "back" with send_back() once it
## has caught up. A hosting player just informs the others.
func set_away(away: bool) -> void:
	if _room:
		_room.set_away(away)
	elif away:
		_send(1, [NetProtocol.MSG_AWAY])


func send_back() -> void:
	if not _room:
		_send(1, [NetProtocol.MSG_BACK])


func return_seat(slot: int, tick: int) -> void:
	if _room:
		_room.return_seat(slot, tick)


# --------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _mp:
		_mp.poll()
		while _mp and _mp.get_available_packet_count() > 0:
			var from := _mp.get_packet_peer()
			var msg: Variant = bytes_to_var(_mp.get_packet())
			if msg is Array and not msg.is_empty():
				_on_packet(from, msg)
	if state == State.JOINING:
		_join_timer += delta
		if _join_timer > JOIN_TIMEOUT:
			status.emit(tr("ONLINE_ROOM_NOT_FOUND") % room_code, true)
			leave_room()


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


func _advertise() -> void:
	if not _room or not room_public or _lobby_topic == "":
		return
	rt.track(_lobby_topic, _room.advert())


# --- Realtime ---------------------------------------------------------------

func _on_presence(topic: String, presence_state: Dictionary) -> void:
	if topic == _lobby_topic:
		rooms = parse_rooms(presence_state)
		rooms_changed.emit(rooms)
	elif topic == _room_topic:
		if _room:
			_room.on_presence(presence_state)
		elif state == State.JOINING and not _hello_sent:
			for key: String in presence_state:
				var m: Dictionary = presence_state[key]
				if m.get("host", false):
					if m.get("build", "") != NetProtocol.build_id():
						status.emit(tr("ONLINE_VERSION_MISMATCH"), true)
						leave_room()
						return
					_hello_sent = true
					rt.broadcast(_room_topic, "hello", {"from": my_key, "name": my_name, "avatar": Progress.avatar(), "build": NetProtocol.build_id()})
		elif state in [State.IN_ROOM, State.IN_MATCH]:
			var host_present := false
			for key: String in presence_state:
				if presence_state[key].get("host", false):
					host_present = true
			if not host_present and not peers.get(1, {}).get("connected", false):
				_host_gone()


func _on_broadcast(topic: String, event: String, p: Dictionary) -> void:
	if topic != _room_topic:
		return
	match event:
		"chat":
			var key := str(p.get("from", ""))
			if key != "" and key != my_key and not muted.has(key):
				var text := ChatFilter.clean(str(p.get("text", "")))
				if text != "":
					_add_chat({"key": key, "name": ChatFilter.clean(str(p.get("name", "?"))).left(16), "text": text, "system": false})
			return
		"emote":
			var ekey := str(p.get("from", ""))
			var emote := str(p.get("emote", ""))
			if ekey != my_key and not muted.has(ekey) and EMOTES.has(emote):
				emote_received.emit(ekey, emote)
			return
	if _room:
		_room.on_broadcast(event, p)
		return
	match event:
		"welcome":
			if p.get("to", "") == my_key and state == State.JOINING:
				_client_on_welcome(int(p.peer_id))
		"reject":
			if p.get("to", "") == my_key:
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


# --- Client side WebRTC ------------------------------------------------------

func _client_on_welcome(peer_id: int) -> void:
	my_peer_id = peer_id
	_mp = WebRTCMultiplayerPeer.new()
	_mp.create_client(peer_id)
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(_on_peer_disconnected)
	var conn := WebRTCPeerConnection.new()
	if conn.initialize({"iceServers": config.ice_servers}) != OK:
		status.emit(tr("ONLINE_NO_WEBRTC"), true)
		return
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		rt.broadcast(_room_topic, "sdp", {"to_peer": 1, "from_peer": my_peer_id, "type": type, "sdp": sdp}))
	conn.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		rt.broadcast(_room_topic, "ice", {"to_peer": 1, "from_peer": my_peer_id, "media": media, "index": index, "name": cname}))
	_conns[1] = conn
	_mp.add_peer(conn, 1)
	status.emit(tr("ONLINE_CONNECTING"), false)


func _on_peer_connected(pid: int) -> void:
	if pid == 1:
		var p := peers.duplicate()
		p[1] = {"name": "Host", "key": "", "connected": true, "ping_ms": 0}
		peers = p
		_send(1, [NetProtocol.MSG_HELLO, my_name, Progress.user_id(), NetProtocol.build_id()])
		_set_state(State.IN_ROOM)
		status.emit(tr("ONLINE_CONNECTED"), false)


func _on_peer_disconnected(pid: int) -> void:
	if pid == 1:
		_host_gone()


func _host_gone() -> void:
	var in_match := state == State.IN_MATCH
	status.emit(tr("ONLINE_HOST_LEFT"), true)
	leave_room()
	if in_match:
		host_lost.emit()


func _on_packet(_from: int, msg: Array) -> void:
	match int(msg[0]):
		NetProtocol.MSG_LOBBY:
			lobby = msg[1]
			if msg.size() > 2:
				peers = msg[2]
			lobby_changed.emit()
		NetProtocol.MSG_START:
			_set_state(State.IN_MATCH)
			match_start.emit(_localize(msg[1]), int(msg[2]))
		NetProtocol.MSG_INPUTS:
			inputs_received.emit(int(msg[1]), int(msg[2]), msg[3])
		NetProtocol.MSG_DESYNC:
			desync_detected.emit(int(msg[1]))
		NetProtocol.MSG_PING:
			_send(1, [NetProtocol.MSG_PONG, msg[1]])
		NetProtocol.MSG_KICK:
			status.emit(str(msg[1]), true)
			leave_room()
		NetProtocol.MSG_TO_LOBBY:
			_set_state(State.IN_ROOM)
			return_to_lobby.emit()
		NetProtocol.MSG_SLOT_LEFT:
			pass
		NetProtocol.MSG_SEAT_BACK:
			if msg.size() >= 3:
				seat_returned.emit(int(msg[1]), int(msg[2]))
		NetProtocol.MSG_AWAY_INFO:
			if msg.size() >= 3:
				away_info.emit(int(msg[1]), bool(msg[2]))


func _send(target: int, msg: Array) -> void:
	if _mp == null or not _mp.has_peer(target) or not RoomHost.peer_channels_open(_mp.get_peer(target)):
		return
	_mp.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	_mp.set_target_peer(target)
	_mp.put_packet(var_to_bytes(msg))


## Turns the shared setup into this client's view: my seat = local human,
## everything else (other players, bots run by the host) is REMOTE.
func _localize(d: Dictionary) -> MatchSetup:
	var setup := MatchSetup.from_dict(d)
	for s in setup.slots:
		if s.kind == PlayerSlot.Kind.REMOTE and s.peer_id == my_peer_id:
			s.kind = PlayerSlot.Kind.LOCAL_HUMAN
			s.input_device = ControlSchemes.default_device()
			s.user_id = Progress.user_id()
		elif s.kind == PlayerSlot.Kind.BOT:
			s.kind = PlayerSlot.Kind.REMOTE
	return setup
