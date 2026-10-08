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
var _power_row: HBoxContainer
var _power_icon: TextureRect
var _power_label: Label
var _shown_powerup: int = -1

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
	if p.lives >= 0:
		sim.board_effect.connect(func(e):
			if e.key == &"knockout" and e.owner == player_id:
				_update_lives())
		_update_lives()
	if sim.powerups_enabled():
		_build_power_row()
		sim.powerup_changed.connect(func(pid, _id):
			if pid == player_id:
				_flash_power())


func _update_lives() -> void:
	var p := sim.get_player(player_id)
	_team.visible = true
	if not p.alive:
		_team.text = tr("HUD_OUT")
		_team.add_theme_color_override(&"font_color", Color(1, 0.4, 0.35))
		modulate = Color(1, 1, 1, 0.45)
		return
	var start := maxi(sim._win.starting_lives(), p.lives)
	_team.text = "♥".repeat(p.lives) + "♡".repeat(maxi(start - p.lives, 0))
	_team.add_theme_color_override(&"font_color", Color(1, 0.4, 0.45))
	var t := create_tween()
	_team.pivot_offset = _team.size * 0.5
	t.tween_property(_team, "scale", Vector2.ONE * 1.5, 0.08)
	t.tween_property(_team, "scale", Vector2.ONE, 0.25)


func _build_power_row() -> void:
	_power_row = HBoxContainer.new()
	_power_row.add_theme_constant_override(&"separation", 6)
	_power_icon = TextureRect.new()
	_power_icon.custom_minimum_size = Vector2(22, 22)
	_power_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_power_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_power_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_power_label = Label.new()
	_power_label.add_theme_font_size_override(&"font_size", 12)
	_power_label.add_theme_color_override(&"font_color", Color(0.85, 0.88, 1.0))
	_power_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_power_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_power_row.add_child(_power_icon)
	_power_row.add_child(_power_label)
	$VBox.add_child(_power_row)
	$VBox.move_child(_power_row, _info.get_index() + 1)


func _flash_power() -> void:
	if _power_icon == null:
		return
	_power_icon.pivot_offset = _power_icon.size * 0.5
	var t := create_tween()
	t.tween_property(_power_icon, "scale", Vector2.ONE * 1.6, 0.08)
	t.tween_property(_power_icon, "scale", Vector2.ONE, 0.2)


func _update_power_row() -> void:
	var p := sim.get_player(player_id)
	var held := sim.get_powerup_type(p.powerup)
	if p.powerup != _shown_powerup:
		_shown_powerup = p.powerup
		_power_icon.texture = (held.icon if held.icon else Assets.icon(StringName("pu_" + String(held.key)))) if held else null
		_power_icon.modulate = Color.WHITE if held else Color(1, 1, 1, 0.2)
	var parts: PackedStringArray = []
	if held and not compact:
		parts.append(tr("POWERUP_" + String(held.key).to_upper()))
	if p.bomb_armed or (p.active and p.active.bomb):
		parts.append(tr("POWERUP_BOMB"))
	if p.slow_ticks > 0:
		parts.append("%s %ds" % [tr("POWERUP_SLOW"), ceili(p.slow_ticks / 60.0)])
	if p.double_ticks > 0:
		parts.append("x2 %ds" % ceili(p.double_ticks / 60.0))
	if p.rush_ticks > 0:
		parts.append("%s %ds" % [tr("POWERUP_RUSH"), ceili(p.rush_ticks / 60.0)])
	_power_label.text = " · ".join(parts)
	_power_label.add_theme_color_override(&"font_color", Color(1, 0.55, 0.45) if p.rush_ticks > 0 else Color(0.85, 0.88, 1.0))


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
	if _power_row and sim:
		_update_power_row()
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
