shader_type canvas_item;
// Tints a grayscale shade map with the draw color (player color):
//   shade 0.0 -> dark edge, 0.5 -> player color, 1.0 -> highlight.
// Keeps one color identity per player while giving every cell a pixel
// gradient. Swap/tune this in the BlockSkin's cell_material.

uniform float edge_darkness : hint_range(0.0, 1.0) = 0.55;
uniform float highlight_amount : hint_range(0.0, 1.0) = 0.55;
uniform float saturation_boost : hint_range(0.0, 2.0) = 1.1;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float s = tex.r;
	vec3 base = COLOR.rgb;
	float l = dot(base, vec3(0.299, 0.587, 0.114));
	base = clamp(mix(vec3(l), base, saturation_boost), 0.0, 1.0);
	vec3 dark = base * (1.0 - edge_darkness);
	vec3 light = mix(base, vec3(1.0), highlight_amount);
	vec3 c = s < 0.5 ? mix(dark, base, s * 2.0) : mix(base, light, (s - 0.5) * 2.0);
	COLOR = vec4(c, tex.a * COLOR.a);
}
