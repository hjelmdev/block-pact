class_name ChatFilter
extends RefCounted
## Cleans chat text on both send and receive (never trust the sender):
## trims, collapses whitespace, caps the length, strips BBCode-ish markup
## and masks words from res://data/chat_blocklist.txt (one per line, # comments).

const MAX_LENGTH := 120
const BLOCKLIST_PATH := "res://data/chat_blocklist.txt"

static var _words: PackedStringArray = []
static var _loaded := false


static func clean(text: String) -> String:
	text = text.replace("\n", " ").replace("\t", " ").replace("[", "(").replace("]", ")")
	while text.contains("  "):
		text = text.replace("  ", " ")
	text = text.strip_edges().left(MAX_LENGTH)
	if text == "":
		return ""
	_load()
	var lower := text.to_lower()
	for w in _words:
		var from := 0
		while true:
			var i := lower.find(w, from)
			if i < 0:
				break
			text = text.substr(0, i) + "*".repeat(w.length()) + text.substr(i + w.length())
			from = i + w.length()
	return text


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(BLOCKLIST_PATH, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges().to_lower()
		if line != "" and not line.begins_with("#"):
			_words.append(line)
