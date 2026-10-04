shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

// One ink stroke (BrushStrokeEffect): matte and dark, never brighter than
// the scene - unshaded ink, no emission. UV.x runs along the stroke from
// where it starts (the Wanderer's side), UV.y across it. BrushStrokeEffect
// drives progress (the sweep) and fade, and pushes every other value from
// its own exports.

uniform vec4 ink_color : source_color = vec4(0.275, 0.086, 0.075, 1.0);
uniform float opacity : hint_range(0.0, 1.0) = 0.9;
// How much of the stroke has been laid down, 0-1 along its length; the
// leading edge is feathered over head_feather of the length.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float head_feather : hint_range(0.0, 0.5) = 0.04;
// 1 laid down, 0 gone.
uniform float fade : hint_range(0.0, 1.0) = 1.0;
// The width profile: 0 at both tips, full in the middle, this sharp.
uniform float taper_power : hint_range(0.05, 2.0) = 0.45;
// How far the edges bite in, as a fraction of the half-width, and how
// fine the bites are along the stroke.
uniform float edge_raggedness : hint_range(0.0, 1.0) = 0.35;
uniform float edge_frequency = 70.0;
// Dry-brush streaks: lighter runs along the stroke, this deep.
uniform float streak_strength : hint_range(0.0, 1.0) = 0.35;
uniform float streak_frequency = 16.0;
// Which stroke this is - no two cut from the same noise.
uniform float seed = 0.0;

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

void fragment() {
	float along = UV.x;
	float across = abs(UV.y * 2.0 - 1.0);
	// The edge: the taper, bitten into by noise along the stroke (both
	// edges their own), so it reads as a dragged brush, not a cut.
	float profile = pow(clamp(sin(PI * along), 0.0, 1.0), taper_power);
	float side = UV.y < 0.5 ? 0.0 : 37.0;
	float bite = (value_noise(vec2(along * edge_frequency + side, seed)) * 0.5 + 0.5) * 0.7
		+ (value_noise(vec2(along * edge_frequency * 3.1 + side, seed + 11.0)) * 0.5 + 0.5) * 0.3;
	float edge = profile * (1.0 - edge_raggedness * bite);
	float aa = max(fwidth(across), 0.001);
	float coverage = 1.0 - smoothstep(edge - aa, edge + aa, across);
	// Streaks: noise stretched along the stroke thins the ink in runs.
	float streak = value_noise(vec2(along * 3.0 + seed, UV.y * streak_frequency));
	coverage *= 1.0 - streak_strength * smoothstep(0.1, 0.9, streak);
	// The sweep: laid down up to progress, its head feathered.
	float laid = 1.0 - smoothstep(progress - head_feather, progress, along);
	ALBEDO = ink_color.rgb;
	ALPHA = clamp(ink_color.a * opacity * coverage * laid * fade, 0.0, 1.0);
}
