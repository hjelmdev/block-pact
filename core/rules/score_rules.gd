class_name ScoreRules
extends Resource
## Data-driven scoring model. Subclass and override [method evaluate_clear]
## for radically different scoring; most tweaks are just exported values.

enum SpecialMode {
	## Multiplies only the special cell owner's share of the row (Model A).
	OWNER_SHARE,
	## Multiplies the whole row for everyone who contributed (Model B).
	WHOLE_ROW,
	## Multiplies only the finisher bonus (Model C).
	FINISHER_BONUS,
}

@export var row_base_value: int = 100
## Multiplier on the total clear value indexed by lines cleared at once.
## Default 1/3/5/8 means a 4-line clear is worth 8 rows, not 4.
@export var multi_line_totals: PackedFloat32Array = PackedFloat32Array([0.0, 1.0, 3.0, 5.0, 8.0])
## Bonus to the player whose piece completed the row(s), per row.
@export var completion_bonus: int = 50
## Bonus per combo step (consecutive clearing locks by the same player).
@export var combo_bonus: int = 50
@export var special_mode: SpecialMode = SpecialMode.OWNER_SHARE
## Multiply everything by the current level.
@export var scale_with_level: bool = true
@export var soft_drop_points_per_row: int = 1
@export var hard_drop_points_per_row: int = 2


## board_rows: Array of Array of {x, owner, special} for each full row.
func evaluate_clear(board_rows: Array, row_ys: PackedInt32Array, finisher_id: int, combo: int,
		level: int, width: int, special_types: Dictionary) -> LineClearResult:
	var result := LineClearResult.new()
	result.finisher_id = finisher_id
	result.combo = combo
	result.level = level
	var n := row_ys.size()
	var level_mult := level if scale_with_level else 1
	var totals_index := mini(n, multi_line_totals.size() - 1)
	var row_value := float(row_base_value) * multi_line_totals[totals_index] / float(maxi(n, 1))
	row_value *= level_mult

	var finisher_mult := 1
	for i in n:
		var row := LineClearResult.ClearedRow.new()
		row.y = row_ys[i]
		row.cells = board_rows[i]
		var specials_by_owner := {}
		var whole_row_mult := 1
		for cell: Dictionary in row.cells:
			var owner: int = cell.owner
			if owner < 0:
				continue
			row.counts[owner] = row.counts.get(owner, 0) + 1
			var sp: int = cell.special
			if sp > 0 and special_types.has(sp):
				var t: SpecialBlockType = special_types[sp]
				result.specials_triggered.append(t.key)
				if not t.is_multiplier():
					continue
				specials_by_owner[owner] = specials_by_owner.get(owner, 1) * t.multiplier
				whole_row_mult *= t.multiplier
				if owner == finisher_id:
					finisher_mult *= t.multiplier
		for owner: int in row.counts:
			var share := row_value * float(row.counts[owner]) / float(width)
			var mult := 1
			match special_mode:
				SpecialMode.OWNER_SHARE:
					mult = specials_by_owner.get(owner, 1)
				SpecialMode.WHOLE_ROW:
					mult = whole_row_mult
			row.multipliers[owner] = mult
			var pts := roundi(share * mult)
			row.points[owner] = pts
			result.awards[owner] = result.awards.get(owner, 0) + pts
		result.rows.append(row)

	if finisher_id >= 0:
		var bonus := completion_bonus * n * level_mult
		if special_mode == SpecialMode.FINISHER_BONUS:
			bonus *= finisher_mult
		result.finisher_bonus = bonus
		if combo > 1:
			result.combo_bonus = combo_bonus * (combo - 1) * level_mult
		result.awards[finisher_id] = result.awards.get(finisher_id, 0) + bonus + result.combo_bonus
	return result
