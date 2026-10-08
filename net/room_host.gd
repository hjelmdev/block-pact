class_name RoomHost
extends Node
## One hosted online room – the authority for its lobby and match traffic.
##
## Used by both kinds of host, so there is exactly one implementation:
##   * a player hosting from the game (Net autoload, `has_local_seat`), and
##   * the dedicated headless server (server/server_main.gd), which runs
##     many RoomHosts and has no seat of its own.
##
## The host is WebRTC peer 1 (star topology). Signaling (hello / sdp / ice)
## and chat go over the room's Supabase Realtime channel; the owner routes
## that channel's events here with [method on_broadcast] / [method on_presence].
##
## The room "leader" may change mode, options, bots and start the match:
## the host player in P2P rooms, the first human on a server.
##
## Implements the lockstep endpoint used by MatchController:
## send_inputs(), send_hash(), is_authority() and the signals
## inputs_received / peer_dropped / desync_detected / host_lost.

signal lobby_changed()
signal state_changed(state: int)
signal status(text: String, is_error: bool)
## Setup as seen by the host (its own seat local, bots local, rest REMOTE).
signal match_start(setup: MatchSetup, input_delay: int)
signal return_to_lobby()
signal inputs_received(slot: int, first_tick: int, bits: PackedByteArray)
signal peer_dropped(peer_id: int)
signal desync_detected(tick: int)
signal host_lost()  # never emitted – the host is the authority
## Something shown in the public room list changed (re-advertise).
signal advert_changed()

enum State { CLOSED, LOBBY, IN_MATCH }

const HUMAN := -1
const PING_INTERVAL := 1.0
const DEFAULT_OPTIONS := {"collision": false, "powerups": true, "specials": "all"}

var rt: RealtimeClient
var presence_key: String
var host_name: String = "Host"
var code: String = ""
var public: bool = true
var has_local_seat: bool = true
var local_avatar: String = ""
var local_user_id: String = ""
var ice_servers: Array = []

var state: int = State.CLOSED
## { mode_id, options, slots: [{name, kind, peer_id, bot_profile_id, bot_personality_id, avatar}], code, leader }
var lobby: Dictionary = {}
## peer_id -> {name, key, connected, ping_ms}
var peers: Dictionary = {}
var topic: String = ""
## When the last human left (msec), for server room clean-up.
var empty_since_ms: int = 0

var _mp: WebRTCMultiplayerPeer
var _conns: Dictionary = {}
var _key_to_peer: Dictionary = {}
var _next_peer_id := 2
var _ping_timer := 0.0
var _hashes: Dictionary = {}


func _init(p_rt: RealtimeClient, p_presence_key: String, p_host_name: String, p_has_local_seat: bool,
		p_ice_servers: Array = []) -> void:
	rt = p_rt
	presence_key = p_presence_key
	host_name = p_host_name
	has_local_seat = p_has_local_seat
	ice_servers = p_ice_servers


## Opens the room on Realtime. `options` = lobby rule options (see MatchOptions).
func open(p_code: String, p_public: bool, options: Dictionary = {}) -> void:
	code = p_code
	public = p_public
	_mp = WebRTCMultiplayerPeer.new()
	_mp.create_server()
	_mp.peer_connected.connect(_on_peer_connected)
	_mp.peer_disconnected.connect(_on_peer_disconnected)
	peers = {}
	var slots: Array = []
	if has_local_seat:
		peers[1] = {"name": host_name, "key": presence_key, "connected": true, "ping_ms": 0}
		slots.append(human_slot_dict(1, host_name, local_avatar))
	lobby = {
		"mode_id": "shared_competition",
		"options": options if not options.is_empty() else DEFAULT_OPTIONS.duplicate(),
		"slots": slots,
		"code": code,
		"leader": 1 if has_local_seat else 0,
	}
	empty_since_ms = Time.get_ticks_msec()
	topic = rt.join(NetProtocol.ROOM_PREFIX + code, presence_key)
	rt.track(topic, {"name": host_name, "host": true, "build": NetProtocol.build_id()})
	_set_state(State.LOBBY)
	lobby_changed.emit()


func close() -> void:
	if state == State.CLOSED:
		return
	if _mp:
		_send(0, [NetProtocol.MSG_KICK, "Room closed"])
		_mp.close()
	_mp = null
	_conns.clear()
	_key_to_peer.clear()
	peers.clear()
	if topic != "":
		rt.leave(topic)
		topic = ""
	_set_state(State.CLOSED)


# --------------------------------------------------------------------------
# Queries

func human_count() -> int:
	var n := 0
	for s: Dictionary in lobby.get("slots", []):
		if s.kind == HUMAN:
			n += 1
	return n


func connected_remote_humans() -> int:
	var n := 0
	for pid: int in peers:
		if pid != 1 and peers[pid].get("connected", false):
			n += 1
	return n


func mode() -> GameModeConfig:
	return MatchFactory.load_mode(StringName(lobby.get("mode_id", "shared_competition")))


func is_joinable() -> bool:
	return state == State.LOBBY and lobby.get("slots", []).size() < mode().max_players


## Entry for the public room list (Presence on the lobby channel).
func advert() -> Dictionary:
	var m := mode()
	return {
		"code": code, "host": host_name, "mode": m.display_name,
		"players": lobby.get("slots", []).size(), "max": m.max_players,
		"open": state == State.LOBBY, "build": NetProtocol.build_id(),
	}


static func can_start(p_lobby: Dictionary, p_peers: Dictionary) -> bool:
	var m := MatchFactory.load_mode(StringName(p_lobby.get("mode_id", "shared_competition")))
	var slots: Array = p_lobby.get("slots", [])
	if slots.size() < maxi(m.min_players, 1):
		return false
	var humans := 0
	for s: Dictionary in slots:
		if s.kind == HUMAN:
			humans += 1
			if not p_peers.get(s.peer_id, {}).get("connected", false):
				return false
	return humans > 0


static func human_slot_dict(peer_id: int, pname: String, avatar := "") -> Dictionary:
	return {"name": pname, "kind": HUMAN, "peer_id": peer_id, "bot_profile_id": "", "bot_personality_id": "",
			"avatar": avatar}


# --------------------------------------------------------------------------
# Lobby control (local host directly, or a leader's command)

func set_mode(mode_id: String) -> void:
	if state != State.LOBBY or not MatchFactory.MODES.has(StringName(mode_id)):
		return
	lobby.mode_id = mode_id
	var m := mode()
	while lobby.slots.size() > m.max_players:
		var removed := false
		for i in range(lobby.slots.size() - 1, -1, -1):
			if lobby.slots[i].kind != HUMAN:
				lobby.slots.remove_at(i)
				removed = true
				break
		if not removed:
			break
	_lobby_updated()


func set_options(options: Dictionary) -> void:
	if state != State.LOBBY:
		return
	lobby.options = {
		"collision": bool(options.get("collision", false)),
		"powerups": bool(options.get("powerups", true)),
		"specials": str(options.get("specials", "all")) if str(options.get("specials", "all")) in ["", "all", "off"] else "all",
	}
	_lobby_updated()


func add_bot(profile_id := "normal") -> void:
	if state != State.LOBBY or lobby.slots.size() >= mode().max_players:
		return
	if not profile_id in ["easy", "normal", "hard", "adaptive"]:
		profile_id = "normal"
	var idx: int = lobby.slots.size()
	var b := MatchFactory.bot_slot(idx, StringName(profile_id))
	lobby.slots.append({"name": b.display_name, "kind": PlayerSlot.Kind.BOT, "peer_id": 1,
			"bot_profile_id": String(b.bot_profile_id), "bot_personality_id": String(b.bot_personality_id),
			"avatar": b.avatar})
	_lobby_updated()


func remove_slot(index: int) -> void:
	if index < 0 or index >= lobby.get("slots", []).size():
		return
	var s: Dictionary = lobby.slots[index]
	if s.kind == HUMAN:
		if s.peer_id == 1 or s.peer_id == lobby.get("leader", 0):
			return  # the host / leader can't kick themselves
		_send(s.peer_id, [NetProtocol.MSG_KICK, "Removed by the room leader"])
		_drop_peer(s.peer_id)
		return
	lobby.slots.remove_at(index)
	_lobby_updated()


func start() -> bool:
	if state != State.LOBBY or not can_start(lobby, peers):
		return false
	var setup := lobby_to_setup()
	setup.seed = randi()
	var max_rtt := 0
	for pid: int in peers:
		max_rtt = maxi(max_rtt, int(peers[pid].get("ping_ms", 0)))
	# Half the round trip + margin, in 60 Hz ticks.
	var delay := clampi(ceili(float(max_rtt) * 0.5 / 16.7) + 3, 3, 12)
	var d := setup.to_dict()
	_hashes.clear()
	_send(0, [NetProtocol.MSG_START, d, delay])
	_set_state(State.IN_MATCH)
	match_start.emit(localize_for_host(d), delay)
	return true


func back_to_lobby() -> void:
	if state != State.IN_MATCH:
		return
	_send(0, [NetProtocol.MSG_TO_LOBBY])
	_set_state(State.LOBBY)
	# Seats of players who left during the match are freed now.
	for i in range(lobby.slots.size() - 1, -1, -1):
		var s: Dictionary = lobby.slots[i]
		if s.kind == HUMAN and not peers.has(s.peer_id):
			lobby.slots.remove_at(i)
	_ensure_leader()
	return_to_lobby.emit()
	_lobby_updated()


## Commands from the room leader (server rooms) – same effect as the
## host pressing the buttons.
func apply_command(from_peer: int, cmd: String, arg: Variant) -> void:
	if from_peer != lobby.get("leader", 0):
		return
	match cmd:
		"mode":
			set_mode(str(arg))
		"options":
			if arg is Dictionary:
				set_options(arg)
		"add_bot":
			add_bot(str(arg))
		"remove":
			remove_slot(int(arg))
		"start":
			start()
		"to_lobby":
			back_to_lobby()


# --------------------------------------------------------------------------
# Lockstep endpoint

func is_authority() -> bool:
	return true


func send_inputs(slot: int, first_tick: int, bits: PackedByteArray) -> void:
	_send(0, [NetProtocol.MSG_INPUTS, slot, first_tick, bits])


func send_hash(tick: int, h: int) -> void:
	_hashes[tick] = h


# --------------------------------------------------------------------------
# Realtime events for this room's channel (routed by the owner)

func on_broadcast(event: String, p: Dictionary) -> void:
	match event:
		"hello":
			_on_hello(p)
		"sdp":
			if int(p.get("to_peer", -1)) == 1:
				var c: WebRTCPeerConnection = _conns.get(int(p.get("from_peer", -1)))
				if c:
					c.set_remote_description(str(p.type), str(p.sdp))
		"ice":
			if int(p.get("to_peer", -1)) == 1:
				var c: WebRTCPeerConnection = _conns.get(int(p.get("from_peer", -1)))
				if c:
					c.add_ice_candidate(str(p.media), int(p.index), str(p.name))


func on_presence(presence_state: Dictionary) -> void:
	# A client vanished from Realtime before WebRTC connected.
	for key: String in _key_to_peer.keys():
		var pid: int = _key_to_peer[key]
		if not presence_state.has(key) and not peers.get(pid, {}).get("connected", false):
			_drop_peer(pid)


func _on_hello(p: Dictionary) -> void:
	var key: String = p.get("from", "")
	if key == "" or _key_to_peer.has(key):
		return
	var reason := ""
	if p.get("build", "") != NetProtocol.build_id():
		reason = tr("ONLINE_VERSION_MISMATCH")
	elif state != State.LOBBY:
		reason = tr("ONLINE_ALREADY_STARTED")
	elif lobby.slots.size() >= mode().max_players:
		reason = tr("ONLINE_ROOM_FULL")
	if reason != "":
		rt.broadcast(topic, "reject", {"to": key, "reason": reason})
		return
	var pid := _next_peer_id
	_next_peer_id += 1
	_key_to_peer[key] = pid
	var pname := ChatFilter.clean(str(p.get("name", "Player"))).left(16)
	if pname == "":
		pname = "Player"
	peers[pid] = {"name": pname, "key": key, "connected": false, "ping_ms": 0}
	var av := str(p.get("avatar", ""))
	lobby.slots.append(human_slot_dict(pid, pname, av if Assets.avatar_ids().has(av) else ""))
	rt.broadcast(topic, "welcome", {"to": key, "peer_id": pid})
	var conn := _new_connection(pid)
	if conn:
		conn.create_offer()
	_lobby_updated()


func _new_connection(remote_peer: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	if conn.initialize({"iceServers": ice_servers}) != OK:
		status.emit(tr("ONLINE_NO_WEBRTC"), true)
		return null
	conn.session_description_created.connect(func(type: String, sdp: String):
		conn.set_local_description(type, sdp)
		rt.broadcast(topic, "sdp", {"to_peer": remote_peer, "from_peer": 1, "type": type, "sdp": sdp}))
	conn.ice_candidate_created.connect(func(media: String, index: int, cname: String):
		rt.broadcast(topic, "ice", {"to_peer": remote_peer, "from_peer": 1, "media": media, "index": index, "name": cname}))
	_conns[remote_peer] = conn
	_mp.add_peer(conn, remote_peer)
	return conn


# --------------------------------------------------------------------------
# WebRTC

func _process(delta: float) -> void:
	if _mp == null:
		return
	_mp.poll()
	while _mp and _mp.get_available_packet_count() > 0:
		var from := _mp.get_packet_peer()
		var msg: Variant = bytes_to_var(_mp.get_packet())
		if msg is Array and not msg.is_empty():
			_on_packet(from, msg)
	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_send(0, [NetProtocol.MSG_PING, Time.get_ticks_msec()])


func _on_peer_connected(pid: int) -> void:
	if peers.has(pid):
		peers[pid].connected = true
	_ensure_leader()
	_lobby_updated()


func _on_peer_disconnected(pid: int) -> void:
	_drop_peer(pid)


func _drop_peer(pid: int) -> void:
	if not peers.has(pid):
		return
	var was_connected: bool = peers[pid].get("connected", false)
	peers.erase(pid)
	for key: String in _key_to_peer.keys():
		if _key_to_peer[key] == pid:
			_key_to_peer.erase(key)
	_conns.erase(pid)
	if _mp and _mp.has_peer(pid):
		_mp.remove_peer(pid)
	if state == State.IN_MATCH:
		# Keep the seat: the host feeds empty inputs for it from now on.
		peer_dropped.emit(pid)
		for i in _slots_for_peer(pid):
			_send(0, [NetProtocol.MSG_SLOT_LEFT, i])
		_ensure_leader()
		_lobby_updated(false)
	else:
		for i in range(lobby.get("slots", []).size() - 1, -1, -1):
			var s: Dictionary = lobby.slots[i]
			if s.kind == HUMAN and s.peer_id == pid:
				lobby.slots.remove_at(i)
		if was_connected:
			status.emit(tr("ONLINE_PLAYER_LEFT"), false)
		_ensure_leader()
		_lobby_updated()
	if human_count() == 0 or connected_remote_humans() == 0:
		empty_since_ms = Time.get_ticks_msec()


## Server rooms: the earliest connected human leads. P2P: always the host.
func _ensure_leader() -> void:
	if has_local_seat:
		lobby.leader = 1
		return
	var leader: int = lobby.get("leader", 0)
	if peers.get(leader, {}).get("connected", false):
		return
	lobby.leader = 0
	for s: Dictionary in lobby.get("slots", []):
		if s.kind == HUMAN and peers.get(s.peer_id, {}).get("connected", false):
			lobby.leader = s.peer_id
			return


func _slots_for_peer(pid: int) -> Array[int]:
	var out: Array[int] = []
	for i in lobby.get("slots", []).size():
		var s: Dictionary = lobby.slots[i]
		if s.kind == HUMAN and s.peer_id == pid:
			out.append(i)
	return out


func _on_packet(from: int, msg: Array) -> void:
	match int(msg[0]):
		NetProtocol.MSG_HELLO:
			if peers.has(from):
				var n := ChatFilter.clean(str(msg[1])).left(16)
				if n != "":
					peers[from].name = n
					for s: Dictionary in lobby.slots:
						if s.kind == HUMAN and s.peer_id == from:
							s.name = n
				_lobby_updated()
		NetProtocol.MSG_INPUTS:
			if msg.size() < 4 or not (msg[3] is PackedByteArray):
				return
			# Only accept inputs for seats owned by the sender.
			if not _slots_for_peer(from).has(int(msg[1])):
				return
			for pid: int in peers:
				if pid != 1 and pid != from and peers[pid].connected:
					_send(pid, msg)
			inputs_received.emit(int(msg[1]), int(msg[2]), msg[3])
		NetProtocol.MSG_HASH:
			var t := int(msg[1])
			if _hashes.has(t) and _hashes[t] != int(msg[2]):
				desync_detected.emit(t)
				_send(0, [NetProtocol.MSG_DESYNC, t])
		NetProtocol.MSG_PING:
			_send(from, [NetProtocol.MSG_PONG, msg[1]])
		NetProtocol.MSG_PONG:
			if peers.has(from):
				peers[from].ping_ms = Time.get_ticks_msec() - int(msg[1])
				if state == State.LOBBY:
					_lobby_updated(false)
		NetProtocol.MSG_CMD:
			if msg.size() >= 2:
				apply_command(from, str(msg[1]), msg[2] if msg.size() > 2 else null)


func _send(target: int, msg: Array) -> void:
	if _mp == null:
		return
	var bytes := var_to_bytes(msg)
	_mp.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	if target == 0:
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
	return peer_channels_open(_mp.get_peer(pid))


## True when the peer is connected and its data channels are still open
## (sending on a closing channel logs engine errors).
static func peer_channels_open(info: Dictionary) -> bool:
	if not info.get("connected", false):
		return false
	for ch in info.get("channels", []):
		if ch != null and (ch as WebRTCDataChannel).get_ready_state() != WebRTCDataChannel.STATE_OPEN:
			return false
	var conn: WebRTCPeerConnection = info.get("connection")
	return conn == null or conn.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED


func _lobby_updated(notify_list := true) -> void:
	_send(0, [NetProtocol.MSG_LOBBY, lobby, peers])
	lobby_changed.emit()
	if notify_list:
		advert_changed.emit()


func _set_state(s: int) -> void:
	if s != state:
		state = s
		state_changed.emit(s)
		advert_changed.emit()


# --------------------------------------------------------------------------
# Setups

func lobby_to_setup() -> MatchSetup:
	var setup := MatchSetup.new()
	setup.mode = mode()
	setup.rule_overrides = MatchOptions.to_rule_overrides(lobby.get("options", {}))
	var slots: Array[PlayerSlot] = []
	for i in lobby.slots.size():
		var s: Dictionary = lobby.slots[i]
		var ps := PlayerSlot.new()
		ps.display_name = s.name
		ps.color_index = i
		ps.peer_id = s.peer_id
		ps.avatar = str(s.get("avatar", ""))
		if s.kind == HUMAN:
			ps.kind = PlayerSlot.Kind.REMOTE
		else:
			ps.kind = PlayerSlot.Kind.BOT
			ps.bot_profile_id = StringName(s.bot_profile_id)
			ps.bot_personality_id = StringName(s.bot_personality_id)
		slots.append(ps)
	setup.slots = slots
	return setup


## The host's own view: its seat (peer 1) is local, bots run here.
func localize_for_host(d: Dictionary) -> MatchSetup:
	var setup := MatchSetup.from_dict(d)
	for s in setup.slots:
		if s.kind == PlayerSlot.Kind.REMOTE and s.peer_id == 1 and has_local_seat:
			s.kind = PlayerSlot.Kind.LOCAL_HUMAN
			s.input_device = ControlSchemes.default_device()
			s.user_id = local_user_id
	return setup
