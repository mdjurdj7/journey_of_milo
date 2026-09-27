shader_type canvas_item;

// The card's paper (CardView's Paper node), through the one shared
// battle/card_paper_material.tres - tune it there and every card follows,
// live. Uncoated stock, not aged paper: the bone moves by a hair, in two
// layers tuned apart, and nothing else - no speckle, fibre or stain.
//   grain: an unevenness in tone with a finer tooth mixed in.
//   tonal variation: a broad drift in paper density, one to three soft
//   shifts across a card's width.
// Each strength is that layer's peak swing in brightness (0.015 = +-1.5%)
// about the bone; 0 turns the layer off, both 0 is the flat bone.
//
// CardView draws the face as a rounded box whose alpha is the corner mask
// and whose red channel carries the card's seed, so no two cards are cut
// from the same place on the sheet. The noise is in the card's own
// pixels, so it scales and moves with the card and never swims.

uniform float paper_grain_strength : hint_range(0.0, 0.1) = 0.015;
uniform float paper_tonal_variation_strength : hint_range(0.0, 0.1) = 0.01;
// The card's field colour - CardView.field_color. Keep the two matched.
uniform vec4 bone : source_color = vec4(0.94, 0.91, 0.86, 1.0);
// The tone's wavelength and the tooth's, in 1x card pixels, and how much
// of the swing is tooth.
uniform float tone_scale_px = 70.0;
uniform float tooth_scale_px = 2.5;
uniform float tooth_weight : hint_range(0.0, 1.0) = 0.35;
// The tonal drift's longest wavelength in 1x card pixels - 220 on a
// 200 px card is one to three soft shifts across it.
uniform float tonal_scale_px = 220.0;

varying vec2 local;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Smooth value noise in -1..1.
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x);
	float b = mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x);
	return mix(a, b, u.y) * 2.0 - 1.0;
}

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 p = local + vec2(COLOR.r * 917.0, COLOR.r * 313.0);
	float tone = value_noise(p / tone_scale_px) * 0.65 + value_noise(p / (tone_scale_px * 0.37) + 17.0) * 0.35;
	float tooth = value_noise(p / tooth_scale_px);
	float grain = mix(tone, tooth, tooth_weight);
	// The drift is three slow plane waves, each card turning and phasing
	// them by its seed - smooth by construction, with none of value
	// noise's grid, and too long to repeat on one card.
	float seed = COLOR.r * TAU;
	float drift = 0.0;
	for (int i = 0; i < 3; i++) {
		float k = float(i);
		float angle = seed * (1.0 + k * 1.7) + k * 2.1;
		float wavelength = tonal_scale_px / (1.0 + k * 0.45);
		drift += sin(dot(local, vec2(cos(angle), sin(angle))) * TAU / wavelength + seed * (3.0 + k)) * (1.0 - k * 0.3);
	}
	drift /= 2.1;
	float swing = grain * paper_grain_strength + drift * paper_tonal_variation_strength;
	COLOR = vec4(clamp(bone.rgb * (1.0 + swing), 0.0, 1.0), COLOR.a);
}
