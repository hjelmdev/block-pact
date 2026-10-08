class_name SpecialSet
extends Resource
## A named collection of special cell types (lobby option "Special blocks").

@export var types: Array[SpecialBlockType] = []
## Chance that a piece gets one special cell.
@export_range(0.0, 1.0) var chance: float = 0.15
