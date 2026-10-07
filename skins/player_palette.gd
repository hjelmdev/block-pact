class_name PlayerPalette
extends Resource
## Ordered list of player appearances (seat colors). Up to 8+ entries.

@export var palette_name: String = "Default"
@export var appearances: Array[PlayerAppearance] = []


func get_appearance(index: int) -> PlayerAppearance:
	if appearances.is_empty():
		var a := PlayerAppearance.new()
		a.color = Color.from_hsv(fposmod(index * 0.137, 1.0), 0.7, 1.0)
		return a
	return appearances[posmod(index, appearances.size())]


func get_color(index: int) -> Color:
	return get_appearance(index).color


func size() -> int:
	return appearances.size()
