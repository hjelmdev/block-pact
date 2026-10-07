class_name RealtimeClient
extends Node
## Minimal Supabase Realtime client (Phoenix channels, protocol 1.0.0 JSON).
## Supports what the game needs: Broadcast (signaling, lobby messages) and
## Presence (who is in a room, public room list). Works on web and desktop
## via WebSocketPeer.

signal connected()
signal disconnected(reason: String)
signal channel_joined(topic: String)
signal channel_error(topic: String, message: String)
signal broadcast_received(topic: String, event: String, payload: Dictionary)
## Full presence state for a channel: key -> metas[0] (Dictionary)
signal presence_changed(topic: String, state: Dictionary)

const HEARTBEAT_SEC := 25.0

var url: String = ""
var access_token: String = ""

var _ws := WebSocketPeer.new()
var _state := WebSocketPeer.STATE_CLOSED
var _ref := 0
var _hb_timer := 0.0
## topic -> {join_ref, joined, presence_key, presence: {key: meta}, pending_track}
var _channels: Dictionary = {}
var _outbox: Array[String] = []


func connect_to_server(p_url: String) -> Error:
	url = p_url
	_ws = WebSocketPeer.new()
	_ws.inbound_buffer_size = 1 << 20
	_ws.outbound_buffer_size = 1 << 20
	var err := _ws.connect_to_url(url)
	_state = _ws.get_ready_state()
	return err


func is_open() -> bool:
	return _ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func close() -> void:
	for topic: String in _channels.keys():
		leave(topic)
	_ws.close()


## Joins `realtime:<name>`. presence_key identifies this client in Presence.
func join(name: String, presence_key: String = "", receive_self := false) -> String:
	var topic := "realtime:" + name
	_ref += 1
	var join_ref := str(_ref)
	_channels[topic] = {"join_ref": join_ref, "joined": false, "presence_key": presence_key,
			"presence": {}, "pending_track": null}
	var payload := {
		"config": {
			"broadcast": {"ack": false, "self": receive_self},
			"presence": {"enabled": presence_key != "", "key": presence_key},
			"postgres_changes": [],
			"private": false,
		},
	}
	if access_token != "":
		payload["access_token"] = access_token
	_push(topic, "phx_join", payload, join_ref, join_ref)
	return topic


func leave(topic: String) -> void:
	if not _channels.has(topic):
		return
	_push(topic, "phx_leave", {}, _channels[topic].join_ref)
	_channels.erase(topic)


func broadcast(topic: String, event: String, payload: Dictionary) -> void:
	if not _channels.has(topic):
		return
	_push(topic, "broadcast", {"type": "broadcast", "event": event, "payload": payload}, _channels[topic].join_ref)


## Publishes this client's presence metadata (sent once the join succeeded).
func track(topic: String, meta: Dictionary) -> void:
	if not _channels.has(topic):
		return
	var ch: Dictionary = _channels[topic]
	if ch.joined:
		_push(topic, "presence", {"type": "presence", "event": "track", "payload": meta}, ch.join_ref)
	else:
		ch.pending_track = meta


func presence(topic: String) -> Dictionary:
	return _channels.get(topic, {}).get("presence", {})


func is_joined(topic: String) -> bool:
	return _channels.has(topic) and _channels[topic].joined


func _process(delta: float) -> void:
	_ws.poll()
	var st := _ws.get_ready_state()
	if st != _state:
		var prev := _state
		_state = st
		if st == WebSocketPeer.STATE_OPEN:
			_hb_timer = 0.0
			for m in _outbox:
				_ws.send_text(m)
			_outbox.clear()
			connected.emit()
		elif st == WebSocketPeer.STATE_CLOSED and prev != WebSocketPeer.STATE_CLOSED:
			for topic: String in _channels:
				_channels[topic].joined = false
			disconnected.emit("%d %s" % [_ws.get_close_code(), _ws.get_close_reason()])
	if st != WebSocketPeer.STATE_OPEN:
		return
	_hb_timer += delta
	if _hb_timer >= HEARTBEAT_SEC:
		_hb_timer = 0.0
		_push("phoenix", "heartbeat", {}, null)
	while _ws.get_available_packet_count() > 0:
		var text := _ws.get_packet().get_string_from_utf8()
		var msg: Variant = JSON.parse_string(text)
		if msg is Dictionary:
			_handle(msg)


func _handle(msg: Dictionary) -> void:
	var topic: String = msg.get("topic", "")
	var event: String = msg.get("event", "")
	var payload: Variant = msg.get("payload", {})
	if not _channels.has(topic):
		return
	var ch: Dictionary = _channels[topic]
	match event:
		"phx_reply":
			if msg.get("ref") == ch.join_ref and not ch.joined:
				if payload.get("status", "") == "ok":
					ch.joined = true
					channel_joined.emit(topic)
					if ch.pending_track != null:
						var meta: Dictionary = ch.pending_track
						ch.pending_track = null
						track(topic, meta)
				else:
					channel_error.emit(topic, str(payload.get("response", payload)))
		"broadcast":
			broadcast_received.emit(topic, str(payload.get("event", "")), payload.get("payload", {}))
		"presence_state":
			ch.presence = {}
			for key: String in payload:
				var metas: Array = payload[key].get("metas", [])
				if not metas.is_empty():
					ch.presence[key] = metas.back()
			presence_changed.emit(topic, ch.presence)
		"presence_diff":
			for key: String in payload.get("leaves", {}):
				ch.presence.erase(key)
			for key: String in payload.get("joins", {}):
				var metas: Array = payload.joins[key].get("metas", [])
				if not metas.is_empty():
					ch.presence[key] = metas.back()
			presence_changed.emit(topic, ch.presence)
		"phx_error", "phx_close":
			ch.joined = false
			channel_error.emit(topic, event)
		"system":
			if str(payload.get("status", "")) == "error":
				channel_error.emit(topic, str(payload.get("message", "")))


func _push(topic: String, event: String, payload: Dictionary, join_ref: Variant, ref: Variant = null) -> void:
	if ref == null:
		_ref += 1
		ref = str(_ref)
	var msg := {"topic": topic, "event": event, "payload": payload, "ref": ref, "join_ref": join_ref}
	var text := JSON.stringify(msg)
	if _ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_ws.send_text(text)
	else:
		_outbox.append(text)
