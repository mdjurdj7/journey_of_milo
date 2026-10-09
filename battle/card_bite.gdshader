shader_type canvas_item;

// Devour's bite (HandContainer.devour_card()): the card's top-left corner
// bitten off along a crescent whose edge is a row of pointed teeth, a
// tapered ink line along the cut and a faint darker band inside it, so
// the edge reads as torn paper. Drawn over the bitten card's own render (a
// SubViewport holding the card, `margin` px of room round it on every
// side), UV 0..1 across that render: the face shows everywhere but the
// bite. All lengths in the card's own px (card_size), from its top-left
// corner, y down.
// - The bite is a disc of `radius` round `centre` (just outside the
//   corner), its rim wobbling by up to `wobble` px.
// - Between the angles `arc_from` and `arc_to` (radians, atan2 of the rim
//   point from `centre`) the rim is `tooth_count` teeth pointing into the
//   card, each `tooth_height` px tall at its sharp point - every tooth's
//   height and width varied by up to `size_jitter` / `spacing_jitter` of
//   their mean, drawn from `seed` (one card's, so each bite differs).
// - The ink line is `ink_width` px at a tooth's root, `ink_tip_ratio` of
//   that at its point; then a `torn_px` band darkened by `torn_strength`.
// `progress` grows the bite from touching the corner (0) to whole (1).

uniform vec2 card_size = vec2(200.0, 280.0);
uniform float margin = 0.0;
uniform vec2 centre = vec2(-10.0, -12.0);
uniform float radius = 91.0;
uniform float arc_from = 0.1;
uniform float arc_to = 1.5;
uniform int tooth_count = 8;
uniform float tooth_height = 9.0;
uniform float size_jitter = 0.3;
uniform float spacing_jitter = 0.2;
uniform float wobble = 2.5;
uniform float seed = 0.0;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ink_color : source_color = vec4(0.1, 0.09, 0.08, 1.0);
uniform float ink_width = 2.5;
uniform float ink_tip_ratio = 0.5;
uniform float torn_px = 1.5;
uniform float torn_strength = 0.18;

const int MAX_TEETH = 16;

// The draw's modulate (a dimmed card's fade, the slide's) - before the
// fragment's COLOR folds the texture in.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// 0..1, the same for the same (i, salt) under one seed.
float noise(float i, float salt) {
	return fract(sin(i * 12.9898 + salt * 4.1414 + seed * 78.233) * 43758.5453);
}

// How far up a tooth the angle `a` sits: 0 at its roots, 1 at its point
// (times the tooth's own size) - and 0 off the arc.
float tooth_rise(float a) {
	int count = clamp(tooth_count, 1, MAX_TEETH);
	float total = 0.0;
	for (int i = 0; i < MAX_TEETH; i++) {
		if (i >= count) {
			break;
		}
		total += 1.0 + spacing_jitter * (2.0 * noise(float(i), 1.0) - 1.0);
	}
	float t = (a - arc_from) / (arc_to - arc_from) * total;
	if (t < 0.0 || t > total) {
		return 0.0;
	}
	float start = 0.0;
	for (int i = 0; i < MAX_TEETH; i++) {
		if (i >= count) {
			break;
		}
		float width = 1.0 + spacing_jitter * (2.0 * noise(float(i), 1.0) - 1.0);
		if (t <= start + width) {
			float u = (t - start) / width;
			// A sharp point with slightly hollow flanks.
			float shape = pow(1.0 - abs(2.0 * u - 1.0), 1.6);
			float size = 1.0 + size_jitter * (2.0 * noise(float(i), 2.0) - 1.0);
			return shape * size;
		}
		start += width;
	}
	return 0.0;
}

void fragment() {
	vec4 face = texture(TEXTURE, UV);
	// The render was drawn over transparent black, its colour premultiplied
	// - undone, so the card's edges and a dimmed card keep their tone.
	face.rgb /= max(face.a, 0.0001);
	vec2 p = UV * (card_size + 2.0 * margin) - margin;
	vec2 to_p = p - centre;
	float a = atan(to_p.y, to_p.x);
	float rise = tooth_rise(a);
	float shake = wobble * (0.6 * sin(a * 5.0 + seed * 6.2832) + 0.4 * sin(a * 11.0 + seed * 17.0));
	float r = mix(length(centre), radius, progress) + (shake + tooth_height * rise) * progress;
	// Radial distance to the edge, made a distance across it (the teeth's
	// flanks are steep), in card px. One screen pixel is `px` card px.
	float d = length(to_p) - r;
	float px = max(length(dFdx(p)), 0.0001);
	float slope = length(vec2(dFdx(d), dFdy(d))) / px;
	d /= max(slope, 0.5);
	float aa = 0.6 * px;
	float kept = smoothstep(-aa, aa, d);
	// Thicker at the roots, thinner toward the points - the pen's taper.
	float width = ink_width * mix(1.0, ink_tip_ratio, clamp(rise, 0.0, 1.0));
	float past_ink = smoothstep(width - aa, width + aa, d);
	float ink = kept * (1.0 - past_ink) * step(0.001, progress);
	float torn = past_ink * (1.0 - clamp((d - width) / max(torn_px, 0.001), 0.0, 1.0)) * step(0.001, progress);
	vec3 colour = face.rgb * (1.0 - torn_strength * torn);
	colour = mix(colour, ink_color.rgb, ink * ink_color.a);
	COLOR = vec4(colour, face.a * kept) * tint;
}
