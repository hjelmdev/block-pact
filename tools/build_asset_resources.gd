extends SceneTree
## Regenerates the default presentation resources: block skin, player
## palette, sound library, UI theme, GameAssets config, achievements and an
## empty backend config. Run after tools/generate_assets.py + an import:
##   godot --headless --path . --import
##   godot --headless --path . -s res://tools/build_asset_resources.gd
## After that, tweak everything in the inspector – these are plain .tres files.

const TEX := "res://skins/default/textures/"
const PAT := "res://skins/default/patterns/"


func _init() -> void:
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://skins/shaders/block_tint.gdshader")
	ResourceSaver.save(shader_mat, "res://skins/default/block_tint_material.tres")

	var skin := BlockSkin.new()
	skin.cell_texture = load(TEX + "block_base.png")
	skin.cell_material = load("res://skins/default/block_tint_material.tres")
	skin.grid_texture = load(TEX + "cell_bg.png")
	skin.ghost_texture = load(TEX + "ghost.png")
	skin.glow_texture = load(TEX + "glow.png")
	skin.particle_texture = load(TEX + "particle.png")
	skin.special_overlays = {
		&"x2": load(TEX + "special_x2.png"),
		&"x3": load(TEX + "special_x3.png"),
		&"x5": load(TEX + "special_x5.png"),
	}
	ResourceSaver.save(skin, "res://skins/default/default_block_skin.tres")

	var palette := PlayerPalette.new()
	var colors := [
		["Cyan", Color(0.25, 0.85, 1.0), "diagonal"],
		["Purple", Color(0.72, 0.45, 1.0), "dots"],
		["Green", Color(0.35, 0.95, 0.45), "cross"],
		["Yellow", Color(1.0, 0.86, 0.25), "stripes"],
		["Orange", Color(1.0, 0.55, 0.2), "checker"],
		["Pink", Color(1.0, 0.42, 0.72), "ring"],
		["Red", Color(1.0, 0.3, 0.3), "diamond"],
		["Blue", Color(0.32, 0.5, 1.0), "none"],
	]
	var apps: Array[PlayerAppearance] = []
	for c in colors:
		var a := PlayerAppearance.new()
		a.color_name = c[0]
		a.color = c[1]
		a.pattern = load(PAT + c[2] + ".png")
		apps.append(a)
	palette.appearances = apps
	ResourceSaver.save(palette, "res://skins/default/default_palette.tres")

	var lib := SoundLibrary.new()
	var events: Array[SoundEvent] = []
	var defs := [
		# id, file, volume_db, pitch_random, polyphony
		[Sfx.MOVE, "move", -6.0, 0.05, 2],
		[Sfx.ROTATE, "rotate", -4.0, 0.05, 2],
		[Sfx.SOFT_DROP, "soft_drop", -10.0, 0.0, 1],
		[Sfx.HARD_DROP, "hard_drop", 0.0, 0.08, 3],
		[Sfx.LOCK, "lock", -3.0, 0.1, 3],
		[Sfx.HOLD, "hold", -4.0, 0.0, 1],
		[Sfx.LINE_1, "line_1", -2.0, 0.0, 2],
		[Sfx.LINE_2, "line_2", -2.0, 0.0, 2],
		[Sfx.LINE_3, "line_3", -1.0, 0.0, 2],
		[Sfx.LINE_4, "line_4", 0.0, 0.0, 2],
		[Sfx.COMBO, "combo", -3.0, 0.0, 2],
		[Sfx.SPECIAL, "special_x", 0.0, 0.0, 2],
		[Sfx.SCORE_ARRIVE, "score_arrive", -8.0, 0.1, 4],
		[Sfx.LEVEL_UP, "level_up", -2.0, 0.0, 1],
		[Sfx.TOP_OUT, "top_out", -2.0, 0.0, 1],
		[Sfx.GAME_OVER, "game_over", -2.0, 0.0, 1],
		[Sfx.COUNTDOWN, "countdown", -4.0, 0.0, 1],
		[Sfx.GO, "go", -3.0, 0.0, 1],
		[Sfx.STEAL, "steal", -2.0, 0.0, 2],
		[Sfx.LEAD_CHANGE, "lead_change", -4.0, 0.0, 1],
		[Sfx.LEAD_LOST, "lead_lost", -3.0, 0.0, 1],
		[Sfx.UI_CLICK, "ui_click", -6.0, 0.05, 2],
		[Sfx.UI_BACK, "ui_back", -6.0, 0.0, 2],
	]
	for d in defs:
		var e := SoundEvent.new()
		e.id = d[0]
		var streams: Array[AudioStream] = [load("res://audio/sfx/%s.wav" % d[1])]
		e.streams = streams
		e.volume_db = d[2]
		e.pitch_random = d[3]
		e.max_polyphony = d[4]
		events.append(e)
	lib.events = events
	lib.music = load("res://audio/music/theme_loop.wav")
	ResourceSaver.save(lib, "res://audio/default_sound_library.tres")

	var theme := _build_theme()
	ResourceSaver.save(theme, "res://ui/theme/main_theme.tres")

	var ga := GameAssets.new()
	ga.block_skin = load("res://skins/default/default_block_skin.tres")
	ga.player_palette = load("res://skins/default/default_palette.tres")
	ga.sound_library = load("res://audio/default_sound_library.tres")
	ga.ui_theme = load("res://ui/theme/main_theme.tres")
	var icons := {}
	for n in ["left", "right", "down", "hard_drop", "rotate_cw", "rotate_ccw", "hold", "pause"]:
		icons[StringName(n)] = load("res://ui/icons/%s.png" % n)
	ga.icons = icons
	ResourceSaver.save(ga, "res://config/game_assets.tres")

	if not ResourceLoader.exists("res://config/backend_config.tres"):
		ResourceSaver.save(BackendConfig.new(), "res://config/backend_config.tres")

	_achievement(&"first_line", "First Pact", "Complete your first row.", AchievementDefinition.Stat.LINES_FINISHED, 1)
	_achievement(&"quad", "Four on the Floor", "Clear 4 rows with one piece.", AchievementDefinition.Stat.BEST_CLEAR, 4)
	_achievement(&"combo_5", "Chain Reaction", "Reach a 5x combo.", AchievementDefinition.Stat.MAX_COMBO, 5)
	_achievement(&"x5_cashout", "Cash Out", "Get one of your special blocks cleared.", AchievementDefinition.Stat.SPECIALS, 1)
	_achievement(&"builder_100", "Master Builder", "Have 100 of your cells cleared in one match.", AchievementDefinition.Stat.CELLS_CLEARED, 100)
	_achievement(&"score_10k", "Five Digits", "Score 10 000 points in one match.", AchievementDefinition.Stat.SCORE, 10000)
	_achievement(&"winner", "Greed Pays", "Win a multiplayer match.", AchievementDefinition.Stat.WON_MULTIPLAYER, 1)

	print("Asset resources written.")
	quit()


func _achievement(id: StringName, title: String, desc: String, stat: AchievementDefinition.Stat, threshold: int) -> void:
	var a := AchievementDefinition.new()
	a.id = id
	a.title = title
	a.description = desc
	a.stat = stat
	a.threshold = threshold
	ResourceSaver.save(a, "res://data/achievements/%s.tres" % id)


func _box(bg: Color, border: Color, border_w := 2, radius := 8, margin := 10.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = margin
	sb.content_margin_right = margin
	sb.content_margin_top = margin * 0.6
	sb.content_margin_bottom = margin * 0.6
	return sb


func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 17
	var accent := Color(0.36, 0.85, 1.0)
	var text := Color(0.9, 0.92, 1.0)
	var bg := Color(0.09, 0.11, 0.17, 0.96)

	t.set_stylebox(&"panel", &"PanelContainer", _box(bg, Color(0.2, 0.24, 0.36), 2, 12, 16.0))
	for cls in [&"Button", &"OptionButton"]:
		t.set_stylebox(&"normal", cls, _box(Color(0.13, 0.16, 0.25), Color(0.22, 0.27, 0.4)))
		t.set_stylebox(&"hover", cls, _box(Color(0.17, 0.21, 0.33), accent.darkened(0.3)))
		t.set_stylebox(&"pressed", cls, _box(Color(0.1, 0.3, 0.42), accent))
		t.set_stylebox(&"focus", cls, _box(Color(0, 0, 0, 0), accent, 2))
		t.set_stylebox(&"disabled", cls, _box(Color(0.1, 0.11, 0.15), Color(0.16, 0.17, 0.22)))
		t.set_color(&"font_color", cls, text)
		t.set_color(&"font_hover_color", cls, Color.WHITE)
		t.set_color(&"font_pressed_color", cls, Color.WHITE)
		t.set_color(&"font_focus_color", cls, Color.WHITE)
		t.set_color(&"font_disabled_color", cls, Color(0.45, 0.47, 0.55))
	t.set_stylebox(&"normal", &"LineEdit", _box(Color(0.04, 0.05, 0.09), Color(0.2, 0.25, 0.38)))
	t.set_stylebox(&"focus", &"LineEdit", _box(Color(0, 0, 0, 0), accent))
	t.set_color(&"font_color", &"LineEdit", Color.WHITE)
	t.set_color(&"font_placeholder_color", &"LineEdit", Color(0.5, 0.53, 0.65))
	t.set_color(&"caret_color", &"LineEdit", accent)
	t.set_color(&"font_color", &"Label", text)
	t.set_stylebox(&"panel", &"PopupMenu", _box(Color(0.08, 0.1, 0.16), Color(0.25, 0.3, 0.45), 2, 6, 6.0))
	t.set_constant(&"v_separation", &"PopupMenu", 10)
	t.set_stylebox(&"slider", &"HSlider", _box(Color(0.15, 0.18, 0.28), Color(0, 0, 0, 0), 0, 4, 3.0))
	t.set_stylebox(&"grabber_area", &"HSlider", _box(accent.darkened(0.3), Color(0, 0, 0, 0), 0, 4, 3.0))
	t.set_stylebox(&"grabber_area_highlight", &"HSlider", _box(accent, Color(0, 0, 0, 0), 0, 4, 3.0))
	return t
