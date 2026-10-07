class_name LocalOAuthCatcher
extends Node
## Desktop/editor only: a tiny HTTP server on localhost that receives the
## OAuth redirect. Tokens arrive in the URL fragment (never sent to servers),
## so the first page load returns a small script that forwards the fragment
## as a query string to /cb, which we then parse.

signal tokens_received(fragment: String)

var port: int = 43117
var timeout_sec: float = 180.0

var _server := TCPServer.new()
var _peers: Array[StreamPeerTCP] = []
var _time := 0.0

const PAGE_FORWARD := "<html><body style='background:#111;color:#eee;font-family:sans-serif'><p>Signing in…</p><script>location.replace('/cb?' + location.hash.substring(1));</script></body></html>"
const PAGE_DONE := "<html><body style='background:#111;color:#eee;font-family:sans-serif'><h2>Block Pact</h2><p>You are signed in. You can close this tab and return to the game.</p></body></html>"


func _ready() -> void:
	if _server.listen(port, "127.0.0.1") != OK:
		push_warning("LocalOAuthCatcher: could not listen on port %d" % port)
		queue_free()


func _process(delta: float) -> void:
	_time += delta
	if _time > timeout_sec:
		queue_free()
		return
	while _server.is_connection_available():
		_peers.append(_server.take_connection())
	for peer: StreamPeerTCP in _peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_peers.erase(peer)
			continue
		var n := peer.get_available_bytes()
		if n <= 0:
			continue
		var req := peer.get_utf8_string(n)
		var first := req.get_slice("\r\n", 0)
		var path := first.get_slice(" ", 1)
		if path.begins_with("/cb?"):
			_respond(peer, PAGE_DONE)
			tokens_received.emit(path.trim_prefix("/cb?"))
		else:
			_respond(peer, PAGE_FORWARD)
		_peers.erase(peer)


func _respond(peer: StreamPeerTCP, html: String) -> void:
	var body := html.to_utf8_buffer()
	var head := "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % body.size()
	peer.put_data(head.to_utf8_buffer())
	peer.put_data(body)
	peer.disconnect_from_host()


func _exit_tree() -> void:
	_server.stop()
