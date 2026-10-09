shader_type canvas_item;

// Devour's bite (HandContainer.devour_card()): a crescent notch out of a
// card's left edge, its edge scalloped by tooth marks, a thin ink line
// along the cut. Drawn over the bitten card's own render (a SubViewport
// holding the card, `margin` px of room round it on every side), UV 0..1
// across that render: the card's face shows everywhere but the bite.
// The bite is a disc of `radius` px whose centre sits `radius` px left of
// `depth` px into the card (so it reaches `depth` in), at `centre_y` of
// the card's height - and round its rim, `tooth_count` small discs of
// `tooth_radius` px, `tooth_step` radians apart about the edge's middle:
// the bumps between them are the scallops. `progress` grows the bite from
// nothing (0) to whole (1). All in the card's own px (card_size).

uniform vec2 card_size = vec2(200.0, 280.0);
uniform float margin = 0.0;
uniform float depth = 40.0;
uniform float radius = 56.0;
uniform float centre_y = 0.44;
uniform float tooth_radius = 7.0;
uniform float tooth_step = 0.3;
uniform int tooth_count = 7;
uniform float progress : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ink_color : source_color = vec4(0.1, 0.09, 0.08, 1.0);
uniform float ink_width = 1.5;

// The vertex colour - the draw's modulate (a dimmed card's fade, the
// slide's) - before the fragment's COLOR folds the texture in.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

// Signed distance to the bite in px: negative inside it.
float bite_distance(vec2 p) {
	vec2 centre = vec2(depth * progress - radius, card_size.y * centre_y);
	vec2 to_p = p - centre;
	float d = length(to_p) - radius;
	// The nearest tooth and its neighbours, by angle from the bite's axis
	// (+x, into the card).
	float last = float(tooth_count - 1);
	float k = clamp(round(atan(to_p.y, to_p.x) / tooth_step + last * 0.5), 0.0, last);
	for (int i = -1; i <= 1; i++) {
		float j = k + float(i);
		if (j < 0.0 || j > last) {
			continue;
		}
		float angle = (j - last * 0.5) * tooth_step;
		vec2 tooth = centre + radius * vec2(cos(angle), sin(angle));
		d = min(d, length(p - tooth) - tooth_radius * progress);
	}
	return d;
}

void fragment() {
	vec4 face = texture(TEXTURE, UV);
	// The render was drawn over transparent black, its colour premultiplied
	// - undone, so the card's edges and a dimmed card keep their tone.
	face.rgb /= max(face.a, 0.0001);
	vec2 p = UV * (card_size + 2.0 * margin) - margin;
	float d = bite_distance(p);
	// About a pixel of anti-aliasing at the cut.
	float aa = max(fwidth(d), 0.001);
	float kept = smoothstep(-aa, aa, d);
	// The ink line just outside the cut, on the card's face only.
	float rim = kept * (1.0 - smoothstep(ink_width - aa, ink_width + aa, d)) * step(0.001, progress);
	vec3 colour = mix(face.rgb, ink_color.rgb, rim * ink_color.a);
	COLOR = vec4(colour, face.a * kept) * tint;
}
