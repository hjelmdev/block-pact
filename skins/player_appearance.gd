class_name PlayerAppearance
extends Resource
## Visual identity of one player seat. Gameplay only knows player ids;
## this maps an id to a color + an optional accessibility pattern.

@export var color_name: String = "Cyan"
@export var color: Color = Color(0.2, 0.8, 1.0)
## Overlay used when "color patterns" (colorblind aid) is enabled.
@export var pattern: Texture2D
