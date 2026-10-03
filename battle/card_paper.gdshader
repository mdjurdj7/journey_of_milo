shader_type canvas_item;

// The card's paper (CardView's Paper node), through the one shared
// battle/card_paper_material.tres - tune it there and every card follows,
// live. Worn uncoated stock: the bone moves by a hair and darkens a touch
// where hands have held it, and nothing else - no speckle, stain or burn.
//   grain: an unevenness in tone with a finer tooth mixed in.
//   tonal variation: a broad drift in paper density, one to three soft
//   shifts across a card's width.
//   edge tone: the outer few pixels slightly darker and warmer, fading
//   smoothly inward, its width wandering along the edge.
//   fray: the paper runs a little past the printed ink frame and its edge
//   is pulled back raggedly - worst at the corners, and only where the
//   card is big enough on screen for it to read as paper, not glitch.
// Each strength is that layer's peak swing in brightness (0.012 = +-1.2%)
// about the bone; 0 turns the layer off, all 0 is the flat bone.
//
// CardView draws the paper as a rounded box whose alpha is the corner mask,
// whose red channel carries the card's seed (so no two copies are cut from
// the same place on the sheet), whose green is the box's corner radius / 32
// and whose blue is how far it runs past the frame / 8 (CardView.paper_
// margin_px). Green 0 - the keepsake panel, which shares this paper - is
// no edge tone and no fray. The box's UVs run 0-1 over its rect, which is
// how the edge is found. The noise is in the card's own pixels, so it
// moves with the card and never swims.

uniform float paper_grain_strength : hint_range(0.0, 0.1) = 0.012;
uniform float paper_tonal_variation_strength : hint_range(0.0, 0.1) = 0.008;
// The card's field colour - CardView.field_color. Keep the two matched.
uniform vec4 bone : source_color = vec4(0.94, 0.91, 0.86, 1.0);
// The tone's wavelength in 1x card pixels, and how much of the swing is
// tooth.
uniform float tone_scale_px = 70.0;
uniform float tooth_weight : hint_range(0.0, 1.0) = 0.35;
// The tooth's wavelength in SCREEN pixels: it steps between octaves of the
// card's own noise as the card scales, so it stays this fine in a hand at
// 0.95 and inspected at 2.2 alike instead of blowing up with the card.
uniform float tooth_screen_px = 2.5;
// The tonal drift's longest wavelength in 1x card pixels - 220 on a
// 200 px card is one to three soft shifts across it.
uniform float tonal_scale_px = 220.0;
// Handled edges: how far in from the frame's outer edge the tone reaches
// (1x card pixels; the paper past the frame is all edge), how much
// darker it is at the very edge, and the warm multiply it leans toward
// there (white = no warmth). The width wanders by edge_tone_wander along
// the edge, a little differently on every card.
uniform float edge_tone_width_px = 6.0;
uniform float edge_tone_strength : hint_range(0.0, 0.2) = 0.03;
uniform vec4 edge_tone_warmth : source_color = vec4(1.0, 0.985, 0.955, 1.0);
uniform float edge_tone_wander : hint_range(0.0, 1.0) = 0.25;
// Fray: the most the paper's edge is pulled back, in 1x card pixels,
// along the sides and at the corners - keep both under CardView's paper_
// margin_px so the frame always sits on paper. Seeded per card. It fades
// in with the card's on-screen scale, from nothing at fray_scale_from to
// full at fray_scale_full.
uniform float fray_side_px : hint_range(0.0, 4.0) = 1.0;
uniform float fray_corner_px : hint_range(0.0, 4.0) = 1.5;
uniform float fray_scale_from = 0.9;
uniform float fray_scale_full = 1.6;

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
	// Screen pixels per card pixel, whatever the card's scale or turn.
	vec2 dx = dFdx(local);
	vec2 dy = dFdy(local);
	vec2 uv_dx = dFdx(UV);
	vec2 uv_dy = dFdy(UV);
	float card_px_per_screen = sqrt(max(abs(dx.x * dy.y - dx.y * dy.x), 1e-6));
	// The tooth: two neighbouring octaves of card-anchored noise, crossfaded
	// by the card's scale and renormalised so the swing holds mid-fade.
	float level = log2(tooth_screen_px * card_px_per_screen);
	float octave = floor(level);
	float t = level - octave;
	float fine = exp2(octave);
	float tooth = mix(value_noise(p / fine + 31.0), value_noise(p / (fine * 2.0) + 57.0), t);
	tooth /= sqrt((1.0 - t) * (1.0 - t) + t * t);
	float tone = value_noise(p / tone_scale_px) * 0.65 + value_noise(p / (tone_scale_px * 0.37) + 17.0) * 0.35;
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
	vec3 paper = bone.rgb * (1.0 + swing);
	// Edge tone, by distance in from the rounded edge: the box's size in
	// card pixels is how far `local` moves per unit of UV.
	float alpha = COLOR.a;
	if (COLOR.g > 0.0) {
		float radius = COLOR.g * 32.0;
		float margin = COLOR.b * 8.0;
		vec2 face = vec2(abs(dx.x) + abs(dy.x), abs(dx.y) + abs(dy.y))
			/ max(abs(uv_dx) + abs(uv_dy), vec2(1e-6));
		vec2 half_face = face * 0.5;
		vec2 q = abs((UV - 0.5) * face) - (half_face - radius);
		float inside = -(length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius);
		if (edge_tone_strength > 0.0 && edge_tone_width_px > 0.0) {
			float width = edge_tone_width_px * (1.0 + edge_tone_wander * value_noise(p / 40.0 + 91.0));
			float wear = 1.0 - smoothstep(0.0, width, inside - margin);
			wear *= wear;
			paper *= mix(vec3(1.0), edge_tone_warmth.rgb * (1.0 - edge_tone_strength), wear);
		}
		if (margin > 0.0) {
			// How far in the edge is pulled back here: a ragged seeded
			// amount, the corner cap in the rounded corners and the side
			// cap along the straights.
			float corner = smoothstep(-2.0, 2.0, min(q.x, q.y));
			float cap = mix(fray_side_px, fray_corner_px, corner);
			cap *= smoothstep(fray_scale_from, fray_scale_full, 1.0 / card_px_per_screen);
			float ragged = 0.5 + 0.5 * (value_noise(p / 3.0 + 7.0) * 0.6 + value_noise(p / 1.1 + 3.0) * 0.4);
			float pulled = cap * clamp(ragged, 0.0, 1.0);
			float aa = 0.5 * card_px_per_screen;
			alpha *= smoothstep(pulled - aa, pulled + aa, inside);
		}
	}
	COLOR = vec4(clamp(paper, 0.0, 1.0), alpha);
}
