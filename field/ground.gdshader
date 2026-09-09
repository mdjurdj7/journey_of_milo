shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Near/far albedo darkening, applied before the wetness blend.
uniform vec4 near_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 far_color : source_color = vec4(0.7, 0.7, 0.72, 1.0);
uniform float near_distance = 5.0;
uniform float far_distance = 60.0;

// Dry/wet sand blend.
uniform vec4 dry_color : source_color = vec4(0.72, 0.73, 0.66, 1.0);
uniform vec4 wet_color : source_color = vec4(0.35, 0.38, 0.40, 1.0);
uniform float wetness_scale = 30.0;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.5;
uniform float wet_roughness : hint_range(0.0, 1.0) = 0.15;
uniform float wet_specular : hint_range(0.0, 1.0) = 0.4;

// Standing pools, layered on top of the sand blend where wetness clears
// pool_threshold. pool_edge_width widens that into a fade-through-damp-
// sand transition instead of a hard edge. Meant to be the darkest thing
// on the ground, never the brightest — see set_pool_color_from_sky() in
// ground.gd.
uniform float pool_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float pool_edge_width : hint_range(0.0, 1.0) = 0.15;
uniform vec4 pool_color : source_color = vec4(0.696, 0.704, 0.68, 1.0);
uniform float pool_roughness : hint_range(0.0, 1.0) = 0.35;

// Ground relief. Coupled to wetness: wet ground (and pools most of all)
// sinks, so pools sit in the low spots rather than coincidentally
// overlapping unrelated bumps. Fades to zero between relief_fade_start
// and relief_fade_end (distance from the camera) so the horizon stays
// flat instead of visibly bumpy at range.
uniform float relief_amplitude = 0.3;
uniform float relief_noise_scale = 4.0;
uniform float relief_fade_start = 30.0;
uniform float relief_fade_end = 60.0;

// Drift lines: a handful of faint, slightly warm bands running parallel to
// the shore, spaced inland from the water line. drift_line_count bounds
// how many fade in before the band dies out entirely. Value shift only —
// no displacement — but folded into the normal at reduced weight (see
// drift_line_normal_amplitude) so they read as surface, not paint.
uniform float drift_line_spacing = 6.0;
uniform float drift_line_width = 1.0;
uniform float drift_line_wobble = 1.5;
uniform float drift_line_wobble_scale = 10.0;
uniform int drift_line_count = 3;
uniform float drift_line_strength : hint_range(0.0, 1.0) = 0.05;
uniform vec4 drift_line_color : source_color = vec4(0.55, 0.48, 0.4, 1.0);
uniform float drift_line_normal_amplitude = 0.02;

// Ripple marks: faint, fine-scale directional noise in wet sand only,
// stretched parallel to the shore (ripple_stretch) so it varies quickly
// perpendicular to it. A value shift, same reduced-weight normal folding
// as drift lines.
uniform float ripple_scale = 0.4;
uniform float ripple_stretch = 6.0;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.02;
uniform float ripple_normal_amplitude = 0.01;

// Wet band: within shore_slope_start (meters) of the water line, sand
// wetness is pushed to 1.0 so it blends toward wet_color/wet_roughness/
// wet_specular like damp sand right at the shore — not toward
// pool_color, which stays driven by the plain noise mask so isolated
// standing pools don't turn into a strip along the whole shoreline.
// water_line_z and water_forward_z are pushed from ground.gd (from
// Sea's near edge and RegionField's get_forward()), not assumed.
uniform float shore_slope_start = 8.0;
uniform float water_line_z = 0.0;
uniform float water_forward_z = -1.0;

varying vec2 v_world_xz;

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
// patch noise toward more or less wet coverage overall.
float wetness_mask(vec2 world_xz) {
	float n = value_noise(world_xz / max(wetness_scale, 0.001));
	return clamp(n + (wetness_amount - 0.5) * 2.0, 0.0, 1.0);
}

// Signed distance from the water line, positive on the inland/dry side,
// per the same forward-sign convention region_field.gd/sea.gd use.
// Negative under the sea plane itself, where this doesn't matter (occluded,
// except right at the fading shore edge, exactly where the effects driven
// by this should show through).
float dist_from_shore(vec2 world_xz) {
	return (world_xz.y - water_line_z) * water_forward_z;
}

float shore_t(vec2 world_xz) {
	return 1.0 - smoothstep(0.0, max(shore_slope_start, 0.001), dist_from_shore(world_xz));
}

// Wetness used for sand shading: the plain noise mask, boosted to 1 right
// at the shore. Kept separate from the noise mask alone (used for pools)
// so the shore band reads as wet sand rather than a strip of standing pool.
float sand_wetness_mask(vec2 world_xz) {
	return max(wetness_mask(world_xz), shore_t(world_xz));
}

// Plain relief bump, coupled to wetness so pools and damp sand sink.
// Not yet faded by camera distance — callers apply relief_fade themselves,
// since it's also needed unfaded for the normal computed at each sample.
float relief_height(vec2 world_xz) {
	float wetness = wetness_mask(world_xz);
	float bump = (value_noise(world_xz / max(relief_noise_scale, 0.001)) - 0.5) * 2.0;
	return bump * relief_amplitude - wetness * relief_amplitude;
}

// 2..drift_line_count faint bands, spaced drift_line_spacing apart starting
// at the water line, wobbled along the shore so they don't read as ruled
// lines, and fading out after drift_line_count of them.
float drift_line_mask(vec2 world_xz) {
	float shore_dist = dist_from_shore(world_xz);
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
float ripple_mask(vec2 world_xz) {
	vec2 sample_pos = vec2(
		dist_from_shore(world_xz) / max(ripple_scale, 0.001),
		world_xz.x / max(ripple_scale * ripple_stretch, 0.001)
	);
	return (value_noise(sample_pos + vec2(0.0, 251.3)) - 0.5) * 2.0;
}

// Combined pseudo-height used only to derive the vertex normal: relief at
// full amplitude (faded by camera distance same as the real displacement),
// plus drift lines and ripples at their own much smaller amplitudes so they
// shade as surface detail without actually displacing the mesh.
float surface_height(vec2 world_xz, float relief_fade) {
	float h = relief_height(world_xz) * relief_fade;
	h += drift_line_mask(world_xz) * drift_line_normal_amplitude;
	h += ripple_mask(world_xz) * ripple_normal_amplitude * sand_wetness_mask(world_xz);
	return h;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;

	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float relief_fade = 1.0 - smoothstep(relief_fade_start, relief_fade_end, cam_dist);

	VERTEX.y += relief_height(world_pos.xz) * relief_fade;

	// Central-difference gradient of the same height field feeding the
	// normal, so relief (and, at reduced weight, drift lines and ripples)
	// is shaded rather than just displaced.
	float eps = 0.05;
	float h_x0 = surface_height(world_pos.xz - vec2(eps, 0.0), relief_fade);
	float h_x1 = surface_height(world_pos.xz + vec2(eps, 0.0), relief_fade);
	float h_z0 = surface_height(world_pos.xz - vec2(0.0, eps), relief_fade);
	float h_z1 = surface_height(world_pos.xz + vec2(0.0, eps), relief_fade);
	NORMAL = normalize(vec3((h_x0 - h_x1) / (2.0 * eps), 1.0, (h_z0 - h_z1) / (2.0 * eps)));
}

void fragment() {
	float base_wetness = wetness_mask(v_world_xz);
	float sand_wetness = sand_wetness_mask(v_world_xz);

	// VERTEX in fragment() is view-space; its length is distance from the camera.
	float dist = length(VERTEX);
	float near_far_t = smoothstep(near_distance, far_distance, dist);
	vec3 distance_tint = mix(near_color.rgb, far_color.rgb, near_far_t);

	vec3 dry = dry_color.rgb * distance_tint;
	vec3 wet = wet_color.rgb * distance_tint;

	vec3 sand_albedo = mix(dry, wet, sand_wetness);
	float sand_roughness = mix(1.0, wet_roughness, sand_wetness);
	float sand_specular = mix(0.0, wet_specular, sand_wetness);

	// Drift lines: nudge the sand toward a slightly darker, slightly
	// warmer tone, at most drift_line_strength of the way there.
	float drift = drift_line_mask(v_world_xz);
	sand_albedo = mix(sand_albedo, drift_line_color.rgb, drift * drift_line_strength);

	// Ripple marks: a plain brightness shift in wet sand only.
	float ripple = ripple_mask(v_world_xz) * ripple_strength * sand_wetness;
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
