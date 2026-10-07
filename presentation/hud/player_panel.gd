class_name PlayerPanel
extends PanelContainer
## Compact status box for one player: color, name, score, combo, next/hold.

@export var count_up_speed: float = 6.0

var player_id: int = -1
var sim: MatchSimulation
var compact: bool = false

var _shown_score: float = 0.0
var _target_score: int = 0
var _color: Color = Color.WHITE
var _popup_tween: Tween
var _wants_previews := true

@onready var _swatch: ColorRect = %Swatch
@onready var _name: Label = %NameLabel
@onready var _team: Label = %TeamLabel
@onready var _rank: Label = %RankLabel
@onready var _score: Label = %ScoreLabel
@onready var _info: Label = %InfoLabel
@onready var _popup: Label = %PopupLabel
@onready var _previews: HBoxContainer = %Previews
@onready var _hold: MiniPieceView = %HoldView
@onready var _next: MiniPieceView = %NextView


func setup_panel(p_sim: MatchSimulation, p_player_id: int, color: Color, show_previews: bool, team_text: String) -> void:
	sim = p_sim
	player_id = p_player_id
	_color = color
	var p := sim.get_player(player_id)
	_name.text = p.display_name
	_team.text = team_text
	_team.visible = team_text != ""
	_swatch.color = color
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(color.r * 0.12, color.g * 0.12, color.b * 0.12, 0.92)
	sb.border_color = color.darkened(0.2)
	sb.set_border_width_all(0)
	sb.border_width_left = 4
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	add_theme_stylebox_override(&"panel", sb)
	_wants_previews = show_previews
	_previews.visible = show_previews
	_popup.modulate.a = 0.0
	sim.score_changed.connect(_on_score_changed)
	sim.combo_changed.connect(_on_combo_changed)
	sim.piece_spawned.connect(_on_piece_changed)
	sim.piece_held.connect(_on_piece_changed)
	_refresh_previews()
	_update_info(0)


func set_compact(value: bool) -> void:
	compact = value
	if is_node_ready():
		_previews.visible = not compact and _wants_previews
		_info.visible = not compact
		_refresh_previews()


## Shows the current placing; the leader gets a gold badge and border.
func set_rank(rank: int, is_leader: bool) -> void:
	_rank.visible = rank > 0
	_rank.text = "#%d" % rank
	_rank.add_theme_color_override(&"font_color", Color(1, 0.84, 0.3) if is_leader else Color(0.65, 0.68, 0.8))
	var sb := get_theme_stylebox(&"panel") as StyleBoxFlat
	if sb:
		sb.border_color = Color(1, 0.84, 0.3) if is_leader else _color.darkened(0.2)
		sb.border_width_top = 2 if is_leader else 0
		sb.border_width_right = 2 if is_leader else 0
		sb.border_width_bottom = 2 if is_leader else 0


## Global position where flying score particles should land.
func get_score_anchor_global() -> Vector2:
	return _score.get_global_rect().get_center()


func show_popup(points: int, multiplier: int) -> void:
	_popup.text = "+%d" % points + (" x%d" % multiplier if multiplier > 1 else "")
	_popup.add_theme_color_override(&"font_color", _color.lightened(0.35) if multiplier <= 1 else Color(1, 0.85, 0.3))
	if _popup_tween:
		_popup_tween.kill()
	_popup.modulate.a = 1.0
	_popup.scale = Vector2.ONE * (1.4 if multiplier > 1 else 1.15)
	_popup.pivot_offset = _popup.size * 0.5
	_popup_tween = create_tween()
	_popup_tween.tween_property(_popup, "scale", Vector2.ONE, 0.18)
	_popup_tween.tween_interval(0.7)
	_popup_tween.tween_property(_popup, "modulate:a", 0.0, 0.35)
	_score.pivot_offset = _score.size * 0.5
	var t := create_tween()
	t.tween_property(_score, "scale", Vector2.ONE * 1.12, 0.06)
	t.tween_property(_score, "scale", Vector2.ONE, 0.12)


func _process(delta: float) -> void:
	if absf(_shown_score - _target_score) > 0.5:
		_shown_score = lerpf(_shown_score, _target_score, minf(1.0, delta * count_up_speed))
		if absf(_shown_score - _target_score) < 1.0:
			_shown_score = _target_score
		_score.text = _format(int(round(_shown_score)))


func _on_score_changed(pid: int, score: int, _delta: int) -> void:
	if pid == player_id:
		_target_score = score


func _on_combo_changed(pid: int, combo: int) -> void:
	if pid == player_id:
		_update_info(combo)


func _on_piece_changed(pid: int) -> void:
	if pid == player_id:
		_refresh_previews()


func _update_info(combo: int) -> void:
	_info.text = tr("HUD_COMBO") % combo if combo > 1 else ""


func _refresh_previews() -> void:
	if not _previews.visible:
		return
	var p := sim.get_player(player_id)
	var next := p.next_pieces(1)
	_next.set_piece(next[0] if not next.is_empty() else null, _color)
	_hold.set_piece(p.hold_piece, _color, p.hold_used)
	_hold.visible = sim.config.hold_enabled


static func _format(v: int) -> String:
	var s := str(v)
	var out := ""
	var n := s.length()
	for i in n:
		out += s[i]
		var left := n - i - 1
		if left > 0 and left % 3 == 0:
			out += " "
	return out
