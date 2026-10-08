class_name TurnCredentials
extends Node
## Adds TURN servers to an ICE server list, fetched from the Supabase Edge
## Function "turn-credentials" (supabase/functions/turn-credentials). The
## credentials are short-lived, so they are refreshed before they expire.
##
## The list is changed in place: everything that already holds a reference
## to it (RoomHost, the Net client) uses the TURN servers for every new
## connection. If the function is missing or not set up, nothing changes
## and WebRTC simply runs with STUN.

signal updated(count: int)

const FUNCTION_PATH := "/functions/v1/turn-credentials"
const RETRY_SECONDS := 300.0

var config: BackendConfig
var ice_servers: Array
var _added: Array = []
var _timer: Timer


func _init(p_config: BackendConfig, p_ice_servers: Array) -> void:
	config = p_config
	ice_servers = p_ice_servers


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(refresh)
	add_child(_timer)
	# --no-stun (local tests) empties the list: then stay offline too.
	if config.turn_enabled and config.is_configured() and not ice_servers.is_empty():
		refresh()


func refresh() -> void:
	var http := HTTPRequest.new()
	http.timeout = 15.0
	add_child(http)
	var headers := PackedStringArray([
		"apikey: " + config.supabase_anon_key,
		"Authorization: Bearer " + config.supabase_anon_key,
		"Content-Type: application/json",
	])
	var err := http.request(config.base_url() + FUNCTION_PATH, headers, HTTPClient.METHOD_POST, "{}")
	if err != OK:
		http.queue_free()
		_timer.start(RETRY_SECONDS)
		return
	var result: Array = await http.request_completed
	http.queue_free()
	var data: Variant = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if int(result[1]) != 200 or not data is Dictionary or not data.get("iceServers") is Array:
		_timer.start(RETRY_SECONDS)
		return
	apply(data.iceServers)
	var ttl := float(data.get("ttl", 0))
	if ttl > 0.0:
		_timer.start(maxf(60.0, ttl * 0.5))


## Replaces the TURN servers added last time with `servers` (only entries
## that have turn: urls are kept – STUN is already configured).
func apply(servers: Array) -> void:
	for s in _added:
		ice_servers.erase(s)
	_added.clear()
	for s: Variant in servers:
		if not s is Dictionary or not s.has("urls"):
			continue
		var urls: Array = s.urls if s.urls is Array else [s.urls]
		var turn := urls.filter(func(u): return str(u).begins_with("turn"))
		if turn.is_empty():
			continue
		var entry := {"urls": turn}
		if s.has("username"):
			entry["username"] = str(s.username)
		if s.has("credential"):
			entry["credential"] = str(s.credential)
		ice_servers.append(entry)
		_added.append(entry)
	updated.emit(_added.size())
