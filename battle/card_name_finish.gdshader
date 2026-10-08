shader_type canvas_item;
// A card name's rarity finish (CardView's NameLabel, Uncommon and up - see
// CardRarityFinish, battle/card_rarity_finish.tres): the glyphs' colour
// replaced by the tier's base with a faint fixed gradient toward its
// highlight across the word, and - only while a sweep runs - a narrow
// highlight band moving left to right. Each card has its own material, so
// one card's sweep is its own.
//
// Only COLOR.rgb is written: COLOR.a (the glyph's coverage times the
// card's modulate) is left as it is, so the unaffordable dim and the
// played fade apply to the name exactly as to ink.
//
// u runs 0..1 over the name's own width (text_width_px, the shaped
// string, not the label box), from the label-local x of each vertex.

uniform vec3 base_color : source_color = vec3(0.42, 0.33, 0.13);
uniform vec3 highlight_color : source_color = vec3(0.69, 0.56, 0.27);
uniform bool rainbow = false;
uniform vec3 hue_a : source_color = vec3(0.55, 0.44, 0.50);
uniform vec3 hue_b : source_color = vec3(0.37, 0.49, 0.53);
uniform vec3 hue_c : source_color = vec3(0.54, 0.54, 0.32);
uniform float rest_gradient_strength : hint_range(0.0, 1.0) = 0.12;
uniform float text_width_px = 100.0;
// The sweep's progress, 0..1; below 0 = no sweep (at rest).
uniform float sheen_t = -1.0;
uniform float sheen_width : hint_range(0.01, 1.0) = 0.16;
uniform float sheen_softness : hint_range(0.0, 1.0) = 0.75;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.85;

varying float local_x;

void vertex() {
	local_x = VERTEX.x;
}

void fragment() {
	float u = clamp(local_x / max(text_width_px, 1.0), 0.0, 1.0);
	vec3 colour = mix(base_color, highlight_color, rest_gradient_strength * u);
	if (sheen_t >= 0.0) {
		// The band's centre runs from fully off the left edge to fully off
		// the right one, so it enters and leaves the word cleanly.
		float centre = mix(-sheen_width, 1.0 + sheen_width, sheen_t);
		float offset = (u - centre) / sheen_width;
		float band = 1.0 - smoothstep(1.0 - sheen_softness, 1.0, abs(offset));
		vec3 band_colour = highlight_color;
		if (rainbow) {
			float h = clamp(offset * 0.5 + 0.5, 0.0, 1.0);
			band_colour = h < 0.5 ? mix(hue_a, hue_b, h * 2.0) : mix(hue_b, hue_c, h * 2.0 - 1.0);
		}
		colour = mix(colour, band_colour, band * sheen_strength);
	}
	COLOR.rgb = colour;
}
