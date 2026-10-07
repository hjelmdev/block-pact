class_name Sfx
extends RefCounted
## Ids of every sound event the game can trigger. A SoundLibrary maps these
## to actual audio files. Missing ids are simply silent.

const MOVE := &"move"
const ROTATE := &"rotate"
const SOFT_DROP := &"soft_drop"
const HARD_DROP := &"hard_drop"
const LOCK := &"lock"
const HOLD := &"hold"
const LINE_1 := &"line_1"
const LINE_2 := &"line_2"
const LINE_3 := &"line_3"
const LINE_4 := &"line_4"
const COMBO := &"combo"
const SPECIAL := &"special_x"
const SCORE_ARRIVE := &"score_arrive"
const LEVEL_UP := &"level_up"
const TOP_OUT := &"top_out"
const GAME_OVER := &"game_over"
const COUNTDOWN := &"countdown"
const GO := &"go"
const STEAL := &"steal"
const LEAD_CHANGE := &"lead_change"
const LEAD_LOST := &"lead_lost"
const UI_CLICK := &"ui_click"
const UI_BACK := &"ui_back"


static func line_clear(count: int) -> StringName:
	match clampi(count, 1, 4):
		1:
			return LINE_1
		2:
			return LINE_2
		3:
			return LINE_3
	return LINE_4
