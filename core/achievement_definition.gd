class_name AchievementDefinition
extends Resource
## Data-only achievement. Add new ones as .tres files in
## res://data/achievements/ – the Progress service picks them up.

enum Stat {
	SCORE,            ## final score in one match
	LINES_FINISHED,   ## rows you completed in one match
	CELLS_CLEARED,    ## your cells removed by line clears in one match
	MAX_COMBO,
	BEST_CLEAR,       ## most rows cleared with one piece (4 = quad)
	SPECIALS,         ## special cells of yours that were cleared
	WON_MULTIPLAYER,  ## 1 if ranked first in a match with 2+ players
	PIECES_PLACED,
}

@export var id: StringName = &""
@export var title: String = ""
@export_multiline var description: String = ""
@export var stat: Stat = Stat.SCORE
@export var threshold: int = 1
@export var icon: Texture2D
## Restrict to a game mode id (empty = any mode).
@export var mode_id: StringName = &""


func is_met(stats: Dictionary, current_mode: StringName) -> bool:
	if mode_id != &"" and mode_id != current_mode:
		return false
	return int(stats.get(stat, 0)) >= threshold
