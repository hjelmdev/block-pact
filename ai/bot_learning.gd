class_name BotLearning
extends RefCounted
## In-game learning for the "adaptive" bot: a (1+1) evolution strategy.
## Every match the adaptive bot plays with a slightly mutated version of its
## current weights. If the trial did better than the running average, the
## mutation is kept. The result is saved to user://bots/adaptive.tres, which
## BotProfile.load_profile() prefers over the shipped profile.

const STATE_PATH := "user://bots/adaptive_state.cfg"
const PROFILE_ID := &"adaptive"


## Returns the profile the adaptive bot should use in the next match.
static func trial_profile() -> BotProfile:
	var base := BotProfile.load_profile(PROFILE_ID)
	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var trial: PackedFloat32Array = cfg.get_value("es", "trial", PackedFloat32Array())
	if trial.size() != BotProfile.WEIGHT_NAMES.size():
		trial = _mutate(base.get_weights())
		cfg.set_value("es", "trial", trial)
		_save_cfg(cfg)
	var p: BotProfile = base.duplicate()
	p.set_weights(trial)
	return p


## Feed the result of a finished match. `bot_score` is the adaptive bot's
## score, `match_scores` all scores in the match.
static func report(bot_score: int, match_scores: Array) -> void:
	var avg := 0.0
	for s: int in match_scores:
		avg += s
	avg /= maxf(1.0, match_scores.size())
	var fitness := float(bot_score) / maxf(avg, 1.0)

	var cfg := ConfigFile.new()
	cfg.load(STATE_PATH)
	var base_fit: float = cfg.get_value("es", "base_fitness", 0.0)
	var games: int = cfg.get_value("es", "games", 0)
	var base := BotProfile.load_profile(PROFILE_ID)
	var trial: PackedFloat32Array = cfg.get_value("es", "trial", base.get_weights())
	if games == 0 or fitness >= base_fit:
		base.set_weights(trial)
		base.id = PROFILE_ID
		DirAccess.make_dir_recursive_absolute(BotProfile.USER_DIR)
		ResourceSaver.save(base, BotProfile.USER_DIR + "adaptive.tres")
	base_fit = fitness if games == 0 else lerpf(base_fit, maxf(base_fit, fitness), 0.3)
	cfg.set_value("es", "base_fitness", base_fit)
	cfg.set_value("es", "games", games + 1)
	cfg.set_value("es", "trial", _mutate(base.get_weights()))
	_save_cfg(cfg)


static func _mutate(w: PackedFloat32Array) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := w.duplicate()
	for i in out.size():
		if rng.randf() < 0.3:
			out[i] += rng.randfn(0.0, 0.2) * maxf(absf(out[i]), 0.2)
	return out


static func _save_cfg(cfg: ConfigFile) -> void:
	DirAccess.make_dir_recursive_absolute(BotProfile.USER_DIR)
	cfg.save(STATE_PATH)
