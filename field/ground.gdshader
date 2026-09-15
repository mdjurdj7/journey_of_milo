shader_type spatial;
// depth_draw_opaque forces this into the opaque depth/lighting/shadow pass
// regardless of blend mode - without it (and without ever writing ALPHA -
// fragment() below never does), the ground rendered unlit and didn't
// receive shadows: spatial's default blend mode is blend_mix, and an
// unwritten ALPHA under that mode doesn't reliably resolve to opaque in
// practice. Same fix, same root cause, as wanderer_flat.gdshader's own
// "invisible Wanderer" bug - never reintroduce blend_mix here.
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

// Near/far albedo darkening, applied before the wetness blend.
uniform vec4 near_color : source_color = vec4(0.78, 0.73, 0.62, 1.0);
uniform vec4 far_color : source_color = vec4(0.84, 0.83, 0.79, 1.0);
uniform float near_distance = 20.0;
uniform float far_distance = 120.0;

// Dry/wet sand blend.
uniform vec4 dry_color : source_color = vec4(0.82, 0.77, 0.66, 1.0);
uniform vec4 wet_color : source_color = vec4(0.35, 0.38, 0.40, 1.0);
uniform float wetness_scale = 30.0;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.5;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float wet_specular : hint_range(0.0, 1.0) = 0.4;
// When false, wetness_mask() (and therefore pool_factor, which reads it
// directly) returns 0 everywhere - "wet patches" and standing pools both
// off. shore_wetness_enabled is separate and gates shore_t() instead, so
// the shore can still read damp even with wet patches elsewhere off.
uniform bool wet_patches_enabled = false;
uniform bool shore_wetness_enabled = true;

// Standing pools, layered on top of the sand blend where wetness clears
// pool_threshold. pool_edge_width widens that into a fade-through-damp-
// sand transition instead of a hard edge. Meant to be the darkest thing
// on the ground, never the brightest — see set_pool_color_from_sky() in
// ground.gd.
uniform float pool_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float pool_edge_width : hint_range(0.0, 1.0) = 0.15;
uniform vec4 pool_color : source_color = vec4(0.696, 0.704, 0.68, 1.0);
uniform float pool_roughness : hint_range(0.0, 1.0) = 0.35;

// Ground relief no longer displaces vertices here - ground.gd bakes it
// directly into the relief mesh's own vertices (and the matching
// HeightMapShape3D) via Ground.get_height_at(), so collision and render
// share one source of truth instead of two independent approximations of
// the same noise. relief_amplitude/relief_noise_scale/relief_extent/
// relief_edge_fade live on as GDScript-only exports on Ground for that
// baking - this shader has no more use for them.

// Drift lines: a handful of faint, slightly warm bands running parallel to
// the shore, spaced inland from the water line. drift_line_count bounds
// how many fade in before the band dies out entirely. Value shift only,
// fragment-only - no vertex displacement, no normal perturbation.
uniform float drift_line_spacing = 6.0;
uniform float drift_line_width = 1.0;
uniform float drift_line_wobble = 1.5;
uniform float drift_line_wobble_scale = 10.0;
uniform int drift_line_count = 3;
uniform float drift_line_strength : hint_range(0.0, 1.0) = 0.05;
uniform vec4 drift_line_color : source_color = vec4(0.55, 0.48, 0.4, 1.0);

// Ripple marks: faint, fine-scale directional noise in wet sand only,
// stretched parallel to the shore (ripple_stretch) so it varies quickly
// perpendicular to it. A value shift, fragment-only like drift lines.
uniform float ripple_scale = 0.4;
uniform float ripple_stretch = 6.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.02;

// Sand grain: two small-scale value-noise octaves modulating albedo
// brightness only (never hue - see grain_value()'s own doc), plus a
// sparse dark speckle (shell fragments/dark grains) wherever a separate,
// higher-frequency noise clears speckle_threshold. Both are stronger on
// dry sand and suppressed on wet (see fragment()) - wet sand reads
// smoother/packed, not grainy.
uniform float grain_scale_fine = 0.15;
uniform float grain_scale_coarse = 0.6;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.04;
uniform float speckle_scale = 0.08;
uniform float speckle_threshold : hint_range(0.0, 1.0) = 0.92;
uniform float speckle_darken : hint_range(0.0, 1.0) = 0.15;

// Wet band: within shore_slope_start (meters) of ABOVE sea_level, sand
// wetness is pushed to 1.0 so it blends toward wet_color/wet_roughness/
// wet_specular like damp sand right at the shore — not toward
// pool_color, which stays driven by the plain noise mask so isolated
// standing pools don't turn into a strip along the whole shoreline.
// Height-based (v_world_height vs. sea_level below), not a straight line -
// this follows the landmass's own noised shoreline contour for free,
// since v_world_height already IS that shape (baked into the mesh by
// ground.gd's _relief_height()). sea_level is pushed from ground.gd (from
// Sea's own sea_level), not assumed.
uniform float shore_slope_start = 8.0;
uniform float sea_level = 0.0;

varying vec2 v_world_xz;
varying float v_world_height;

// Textureless value noise, ~[0,1].
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 0 = fully dry, 1 = fully wet. wetness_amount biases the large-scale
// patch noise toward more or less wet coverage overall. Unconditionally
// 0 when wet_patches_enabled is off - this is also what turns pools off,
// since pool_factor is driven directly by this, not a separate flag.
float wetness_mask(vec2 world_xz) {
	if (!wet_patches_enabled) {
		return 0.0;
	}
	float n = value_noise(world_xz / max(wetness_scale, 0.001));
	return clamp(n + (wetness_amount - 0.5) * 2.0, 0.0, 1.0);
}

// Height above sea_level, positive on the dry side - replaces the old
// straight-line dist_from_shore(): the baked relief height already IS the
// landmass's noised shoreline shape (see ground.gd's _relief_height()), so
// this needs no separate shoreline geometry of its own and follows every
// side's wander (and the noise) automatically. Negative under the sea
// plane itself, where this doesn't matter (occluded, except right at the
// fading shore edge, exactly where the effects driven by this should show
// through).
float dist_from_shore(float world_height) {
	return world_height - sea_level;
}

float shore_t(float world_height) {
	if (!shore_wetness_enabled) {
		return 0.0;
	}
	return 1.0 - smoothstep(0.0, max(shore_slope_start, 0.001), dist_from_shore(world_height));
}

// Wetness used for sand shading: the plain noise mask, boosted to 1 right
// at the shore. Kept separate from the noise mask alone (used for pools)
// so the shore band reads as wet sand rather than a strip of standing pool.
float sand_wetness_mask(vec2 world_xz, float world_height) {
	return max(wetness_mask(world_xz), shore_t(world_height));
}

// 2..drift_line_count faint bands, spaced drift_line_spacing apart starting
// at the water line, wobbled along the shore so they don't read as ruled
// lines, and fading out after drift_line_count of them.
float drift_line_mask(vec2 world_xz, float world_height) {
	float shore_dist = dist_from_shore(world_height);
	float spacing = max(drift_line_spacing, 0.001);

	float wobble = (value_noise(vec2(world_xz.x / max(drift_line_wobble_scale, 0.001), 91.7)) - 0.5) * 2.0 * drift_line_wobble;
	float phase = shore_dist + wobble;
	float local = mod(phase + spacing * 0.5, spacing) - spacing * 0.5;
	float line = 1.0 - smoothstep(0.0, max(drift_line_width, 0.001) * 0.5, abs(local));

	float envelope = 1.0 - smoothstep(0.0, spacing * float(max(drift_line_count, 1)), shore_dist);
	return line * envelope;
}

// Anisotropic noise: fine (ripple_scale) across the shore, stretched
// (ripple_stretch times coarser) along it, so it reads as ridges parallel
// to the shoreline rather than a uniform speckle.
float ripple_mask(vec2 world_xz, float world_height) {
	vec2 sample_pos = vec2(
		dist_from_shore(world_height) / max(ripple_scale, 0.001),
		world_xz.x / max(ripple_scale * ripple_stretch, 0.001)
	);
	return (value_noise(sample_pos + vec2(0.0, 251.3)) - 0.5) * 2.0;
}

// Two-octave small-scale value variation reading as sand grain texture -
// brightness only, never hue: this returns a signed [-1, 1]-ish scalar
// that fragment() applies as a uniform multiplier across ALBEDO's own
// R/G/B (1.0 + grain), which preserves each channel's ratio to the
// others (hue/saturation) and only shifts value. grain_scale_fine/
// _coarse are two independent octaves, not one noise sampled twice at
// the same scale, so the grain doesn't look like a single repeating tile.
float grain_value(vec2 world_xz) {
	float fine = value_noise(world_xz / max(grain_scale_fine, 0.001)) * 2.0 - 1.0;
	float coarse = value_noise(world_xz / max(grain_scale_coarse, 0.001)) * 2.0 - 1.0;
	return (fine + coarse) * 0.5;
}

// Sparse dark flecks (shell fragments/dark grains) - a much finer,
// independent noise thresholded rather than used as a smooth value shift,
// so it reads as scattered dark points instead of another grain octave.
float speckle_mask(vec2 world_xz) {
	float n = value_noise(world_xz / max(speckle_scale, 0.001));
	return step(speckle_threshold, n);
}

// VERTEX already holds the real, baked relief height (ground.gd wrote it
// directly into the relief mesh's own vertex data via get_height_at()) and
// NORMAL is left untouched on purpose: the built-in NORMAL input is already
// the mesh's own authored per-vertex normal (also baked by ground.gd, via
// SurfaceTool's generate_normals() over the same height field), correctly
// transformed - this shader has nothing to add to either one anymore.
void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;
	v_world_height = world_pos.y;
}

void fragment() {
	float base_wetness = wetness_mask(v_world_xz);
	float sand_wetness = sand_wetness_mask(v_world_xz, v_world_height);

	// VERTEX in fragment() is view-space; its length is distance from the camera.
	float dist = length(VERTEX);
	float near_far_t = smoothstep(near_distance, far_distance, dist);
	vec3 distance_tint = mix(near_color.rgb, far_color.rgb, near_far_t);

	vec3 dry = dry_color.rgb * distance_tint;
	vec3 wet = wet_color.rgb * distance_tint;

	vec3 sand_albedo = mix(dry, wet, sand_wetness);
	float sand_roughness = mix(1.0, wet_roughness, sand_wetness);
	float sand_specular = mix(0.0, wet_specular, sand_wetness);

	// Sand grain + speckle: both multiplicative and applied identically
	// across R/G/B, so they shift ALBEDO's value only, never its hue.
	// Suppressed on wet sand - wet sand reads smoother/packed, not
	// grainy - by the same sand_wetness driving the dry/wet blend above.
	float grain_suppression = 1.0 - sand_wetness;
	float grain = grain_value(v_world_xz) * grain_strength * grain_suppression;
	sand_albedo *= 1.0 + grain;

	float speckle = speckle_mask(v_world_xz) * speckle_darken * grain_suppression;
	sand_albedo *= 1.0 - speckle;

	// Drift lines: nudge the sand toward a slightly darker, slightly
	// warmer tone, at most drift_line_strength of the way there.
	float drift = drift_line_mask(v_world_xz, v_world_height);
	sand_albedo = mix(sand_albedo, drift_line_color.rgb, drift * drift_line_strength);

	// Ripple marks: a plain brightness shift in wet sand only.
	float ripple = ripple_mask(v_world_xz, v_world_height) * ripple_strength * sand_wetness;
	sand_albedo += ripple;

	// Pools are the wettest extreme of the plain noise mask (not the
	// shore-boosted one), blended in as a distinct final layer so they
	// keep reading as pale reflected sky regardless of the near/far tint
	// applied to the sand beneath them, and so the shore band reads as
	// wet sand rather than a strip of standing pool.
	float pool_factor = smoothstep(pool_threshold - pool_edge_width * 0.5, pool_threshold + pool_edge_width * 0.5, base_wetness);

	ALBEDO = mix(sand_albedo, pool_color.rgb, pool_factor);
	ROUGHNESS = mix(sand_roughness, pool_roughness, pool_factor);
	SPECULAR = mix(sand_specular, 1.0, pool_factor);
	METALLIC = 0.0;
}
