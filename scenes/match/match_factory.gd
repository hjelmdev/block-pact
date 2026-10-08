class_name MatchFactory
extends RefCounted
## Convenience builders for common MatchSetups (menus use these).

const BOT_NAMES := ["Ada", "Byte", "Cog", "Dot", "Echo", "Flux", "Glitch", "Hex"]

const MODES := {
	&"classic_solo": "res://data/modes/classic_solo.tres",
	&"shared_competition": "res://data/modes/shared_competition.tres",
	&"pure_coop": "res://data/modes/pure_coop.tres",
	&"team_battle": "res://data/modes/team_battle.tres",
	&"knockout": "res://data/modes/knockout.tres",
	&"mayhem": "res://data/modes/mayhem.tres",
}


static func load_mode(mode_id: StringName) -> GameModeConfig:
	return load(MODES.get(mode_id, MODES[&"shared_competition"]))


static func all_modes() -> Array[GameModeConfig]:
	var out: Array[GameModeConfig] = []
	for id in MODES:
		out.append(load(MODES[id]))
	return out


static func human_slot(index: int, device: StringName = &"") -> PlayerSlot:
	var s := PlayerSlot.new()
	s.kind = PlayerSlot.Kind.LOCAL_HUMAN
	s.input_device = device if device != &"" else ControlSchemes.default_device()
	s.color_index = index
	s.display_name = Progress.display_name() if index == 0 else "Player %d" % (index + 1)
	if index == 0:
		s.user_id = Progress.user_id()
	return s


static func bot_slot(index: int, profile_id: StringName = &"normal", personality_id: StringName = &"auto") -> PlayerSlot:
	var s := PlayerSlot.new()
	s.kind = PlayerSlot.Kind.BOT
	s.bot_profile_id = profile_id
	s.color_index = index
	if personality_id == &"auto":
		# Mix of styles so every match has a thief, a greedy one, …
		var ids := BotPersonality.list_ids()
		personality_id = ids[maxi(index - 1, 0) % ids.size()]
	s.bot_personality_id = personality_id
	s.display_name = bot_name(index, personality_id)
	return s


static func bot_name(index: int, personality_id: StringName) -> String:
	var base: String = BOT_NAMES[index % BOT_NAMES.size()]
	var p := BotPersonality.load_personality(personality_id)
	if p == null:
		return base + "-bot"
	return "%s (%s)" % [base, TranslationServer.translate(p.name_key)]


static func quick_solo() -> MatchSetup:
	var m := MatchSetup.new()
	m.mode = load_mode(&"classic_solo")
	m.slots = [human_slot(0)]
	var o := MatchOptions.saved_options()
	o.erase("collision")
	m.rule_overrides = MatchOptions.to_rule_overrides(o)
	m.rule_overrides.erase("active_piece_collision")
	return m


static func vs_bots(bot_count: int = 1, profile_id: StringName = &"normal") -> MatchSetup:
	var m := MatchSetup.new()
	m.mode = load_mode(&"shared_competition")
	var slots: Array[PlayerSlot] = [human_slot(0)]
	for i in bot_count:
		slots.append(bot_slot(i + 1, profile_id))
	m.slots = slots
	return m


## Bots only – used for the animated main menu background.
static func attract_mode(players: int = 3) -> MatchSetup:
	var m := MatchSetup.new()
	m.mode = load_mode(&"shared_competition")
	var slots: Array[PlayerSlot] = []
	for i in players:
		slots.append(bot_slot(i, &"hard", &"builder"))
	m.slots = slots
	m.seed = randi()
	return m
