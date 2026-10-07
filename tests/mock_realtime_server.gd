extends SceneTree
## Tiny stand-in for Supabase Realtime (Phoenix protocol 1.0.0, broadcast +
## presence only) so online play can be tested without the internet.
## godot --headless --path . -s res://tests/mock_realtime_server.gd -- --port 4000

var server := TCPServer.new()
var clients: Array = []  # {ws, channels: {topic: presence_key}}
var presence: Dictionary = {}  # topic -> {key: meta}
var port := 4000
var _ref := 0


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var i := a.find("--port")
	if i >= 0:
		port = int(a[i + 1])
	var err := server.listen(port, "127.0.0.1")
	print("mock realtime listening on %d (%s)" % [port, err])


func _process(_delta: float) -> bool:
	while server.is_connection_available():
		var ws := WebSocketPeer.new()
		ws.accept_stream(server.take_connection())
		clients.append({"ws": ws, "channels": {}})
	for c in clients.duplicate():
		var ws: WebSocketPeer = c.ws
		ws.poll()
		var st := ws.get_ready_state()
		if st == WebSocketPeer.STATE_CLOSED:
			for topic: String in c.channels.keys():
				_leave(c, topic)
			clients.erase(c)
			continue
		if st != WebSocketPeer.STATE_OPEN:
			continue
		while ws.get_available_packet_count() > 0:
			var msg: Variant = JSON.parse_string(ws.get_packet().get_string_from_utf8())
			if msg is Dictionary:
				_handle(c, msg)
	return false


func _handle(c: Dictionary, m: Dictionary) -> void:
	var topic: String = m.get("topic", "")
	var ev: String = m.get("event", "")
	var p: Dictionary = m.get("payload", {})
	match ev:
		"heartbeat":
			_send(c, {"topic": "phoenix", "event": "phx_reply", "payload": {"status": "ok", "response": {}}, "ref": m.ref, "join_ref": null})
		"phx_join":
			var key: String = p.get("config", {}).get("presence", {}).get("key", "")
			c.channels[topic] = key
			_send(c, {"topic": topic, "event": "phx_reply", "payload": {"status": "ok", "response": {"postgres_changes": []}}, "ref": m.ref, "join_ref": m.join_ref})
			var state := {}
			for k: String in presence.get(topic, {}):
				state[k] = {"metas": [presence[topic][k]]}
			_send(c, {"topic": topic, "event": "presence_state", "payload": state, "ref": null, "join_ref": null})
		"phx_leave":
			_leave(c, topic)
		"presence":
			var key: String = c.channels.get(topic, "")
			if key == "":
				return
			_ref += 1
			var meta: Dictionary = p.get("payload", {}).duplicate()
			meta["phx_ref"] = str(_ref)
			if not presence.has(topic):
				presence[topic] = {}
			var old: Variant = presence[topic].get(key)
			presence[topic][key] = meta
			var diff := {"joins": {key: {"metas": [meta]}}, "leaves": {}}
			if old != null:
				diff.leaves[key] = {"metas": [old]}
			_fanout(topic, {"topic": topic, "event": "presence_diff", "payload": diff, "ref": null, "join_ref": null}, null)
		"broadcast":
			_fanout(topic, {"topic": topic, "event": "broadcast", "payload": {"type": "broadcast", "event": p.get("event", ""), "payload": p.get("payload", {})}, "ref": null, "join_ref": null}, c)


func _leave(c: Dictionary, topic: String) -> void:
	var key: String = c.channels.get(topic, "")
	c.channels.erase(topic)
	if key != "" and presence.has(topic) and presence[topic].has(key):
		var old = presence[topic][key]
		presence[topic].erase(key)
		_fanout(topic, {"topic": topic, "event": "presence_diff", "payload": {"joins": {}, "leaves": {key: {"metas": [old]}}}, "ref": null, "join_ref": null}, null)


func _fanout(topic: String, msg: Dictionary, except_client) -> void:
	for c in clients:
		if c == except_client or not c.channels.has(topic):
			continue
		_send(c, msg)


func _send(c: Dictionary, msg: Dictionary) -> void:
	var ws: WebSocketPeer = c.ws
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))
