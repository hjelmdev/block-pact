extends Node
## Dedicated headless server: hosts many online rooms in one process.
##
##   godot --headless --path . res://server/server_main.tscn -- --max-rooms 20 --min-open 2 --name "Block Pact EU"
##
## Every room is a RoomHost (the same class a player uses to host from the
## game) plus, while a match runs, a MatchController that simulates the
## match (bots run here, dropped players are taken over, client state hashes
## are checked). The server keeps `--min-open` public rooms waiting for
## players and opens new ones as they fill up, up to `--max-rooms`. Empty
## rooms are closed. All rooms are listed in the public room list through
## one Presence entry on the lobby channel.
##
## Options:
##   --name TEXT          shown as host name in the room list (default "Server")
##   --max-rooms N        hard limit of rooms (default 20)
##   --min-open N         public rooms kept open for joining (default 1)
##   --idle-close SEC     close empty rooms after this long (default 60)
##   --realtime-url URL   override the Realtime websocket (local tests)
##   --no-stun            no STUN servers (local tests)

const MAINTENANCE_INTERVAL := 1.0
const RESULTS_SECONDS := 8.0
const RECONNECT_SECONDS := 3.0

var server_name := "Server"
var max_rooms := 20
var min_open := 1
var idle_close_ms := 60000

var config: BackendConfig
var rt: RealtimeClient
var server_key := ""
var rooms: Dictionary = {}        # code -> RoomHost
var matches: Dictionary = {}      # code -> MatchController
var _by_topic: Dictionary = {}    # realtime topic -> RoomHost
var _lobby_topic := ""
var _advert_dirty := true
var _timer := 0.0
var _reconnect_in := -1.0


func _ready() -> void:
	_parse_args()
	config = BackendConfig.load_active()
	server_key = "srv%x%x" % [randi(), Time.get_ticks_usec()]
	rt = RealtimeClient.new()
	rt.name = "Realtime"
	add_child(rt)
	rt.broadcast_received.connect(_on_broadcast)
	rt.presence_changed.connect(_on_presence)
	rt.channel_error.connect(func(t, m): _log("realtime error %s: %s" % [t, m]))
	rt.disconnected.connect(_on_disconnected)
	_log("starting '%s' (build %s), max %d rooms, %d kept open" % [server_name, NetProtocol.build_id(), max_rooms, min_open])
	_connect()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var v: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--name":
				server_name = v.left(24)
			"--max-rooms":
				max_rooms = maxi(1, int(v))
			"--min-open":
				min_open = maxi(0, int(v))
			"--idle-close":
				idle_close_ms = maxi(5, int(v)) * 1000


func _connect() -> void:
	if not config.online_available():
		_log("no Realtime configured (backend_config or --realtime-url) – exiting")
		get_tree().quit(1)
		return
	rt.connect_to_server(config.realtime_url())
	_lobby_topic = rt.join(NetProtocol.LOBBY_CHANNEL, server_key)
	_advert_dirty = true


func _on_disconnected(reason: String) -> void:
	_log("realtime disconnected (%s) – closing rooms, reconnecting" % reason)
	for code in rooms.keys():
		_close_room(code)
	_lobby_topic = ""
	_reconnect_in = RECONNECT_SECONDS


func _process(delta: float) -> void:
	if _reconnect_in > 0.0:
		_reconnect_in -= delta
		if _reconnect_in <= 0.0:
			_reconnect_in = -1.0
			_connect()
		return
	_timer += delta
	if _timer >= MAINTENANCE_INTERVAL:
		_timer = 0.0
		_maintain()
	if _advert_dirty and rt.is_open():
		_advert_dirty = false
		_advertise()


# --------------------------------------------------------------------------
# Rooms

func _maintain() -> void:
	if not rt.is_open():
		return
	var now := Time.get_ticks_msec()
	var open_rooms := 0
	for code: String in rooms.keys():
		var room: RoomHost = rooms[code]
		if room.state == RoomHost.State.IN_MATCH and room.connected_remote_humans() == 0:
			_log("room %s: everyone left the match – back to lobby" % code)
			room.back_to_lobby()
		if room.state == RoomHost.State.LOBBY and room.is_joinable():
			open_rooms += 1
	# Close rooms that have been empty for a while (keep min_open waiting).
	for code: String in rooms.keys():
		var room: RoomHost = rooms[code]
		if room.state == RoomHost.State.LOBBY and room.human_count() == 0 \
				and now - room.empty_since_ms > idle_close_ms and open_rooms > min_open:
			_close_room(code)
			open_rooms -= 1
	while open_rooms < min_open and rooms.size() < max_rooms:
		_open_room()
		open_rooms += 1


func _open_room() -> RoomHost:
	var code := NetProtocol.make_code()
	while rooms.has(code):
		code = NetProtocol.make_code()
	var room := RoomHost.new(rt, server_key, server_name, false, config.ice_servers)
	room.name = "Room_" + code
	add_child(room)
	room.open(code, true)
	rooms[code] = room
	_by_topic[room.topic] = room
	room.advert_changed.connect(func(): _advert_dirty = true)
	room.match_start.connect(_on_match_start.bind(code))
	room.return_to_lobby.connect(_end_match.bind(code))
	room.status.connect(func(t, _e): _log("room %s: %s" % [code, t]))
	room.lobby_changed.connect(func(): pass)
	_log("room %s opened (%d rooms)" % [code, rooms.size()])
	_advert_dirty = true
	return room


func _close_room(code: String) -> void:
	var room: RoomHost = rooms.get(code)
	if room == null:
		return
	_end_match(code)
	_by_topic.erase(room.topic)
	room.close()
	room.queue_free()
	rooms.erase(code)
	_log("room %s closed (%d rooms)" % [code, rooms.size()])
	_advert_dirty = true


func _on_match_start(setup: MatchSetup, delay: int, code: String) -> void:
	_end_match(code)
	var ctrl := MatchController.new()
	ctrl.name = "Match_" + code
	ctrl.endpoint = rooms[code]
	add_child(ctrl)
	ctrl.match_ended.connect(func(_ranking):
		_log("room %s: match finished" % code)
		await get_tree().create_timer(RESULTS_SECONDS).timeout
		var room: RoomHost = rooms.get(code)
		if room and room.state == RoomHost.State.IN_MATCH and matches.get(code) == ctrl:
			room.back_to_lobby())
	ctrl.net_desync.connect(func(t): _log("room %s: DESYNC at tick %d" % [code, t]))
	matches[code] = ctrl
	ctrl.start_match(setup, delay)
	_log("room %s: match started (%s, %d players, delay %d)" % [code, setup.mode.mode_id, setup.slots.size(), delay])


func _end_match(code: String) -> void:
	var ctrl: MatchController = matches.get(code)
	if ctrl:
		matches.erase(code)
		ctrl.queue_free()


func _advertise() -> void:
	if _lobby_topic == "":
		return
	var list: Array = []
	for code: String in rooms:
		var room: RoomHost = rooms[code]
		if room.public:
			list.append(room.advert())
	rt.track(_lobby_topic, {"server": true, "host": server_name, "rooms": list, "build": NetProtocol.build_id()})


# --------------------------------------------------------------------------
# Realtime routing

func _on_broadcast(topic: String, event: String, payload: Dictionary) -> void:
	var room: RoomHost = _by_topic.get(topic)
	if room:
		room.on_broadcast(event, payload)


func _on_presence(topic: String, presence_state: Dictionary) -> void:
	var room: RoomHost = _by_topic.get(topic)
	if room:
		room.on_presence(presence_state)


func _log(text: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(), text])
