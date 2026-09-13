shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Surface: soft sheen, not a mirror.
uniform vec4 sea_color : source_color = vec4(0.52, 0.60, 0.64, 1.0);
uniform float sea_roughness : hint_range(0.0, 1.0) = 0.25;

// Slow, subtle two-octave value-noise normal perturbation, no texture -
// the THIRD, smallest-scale rate on top of the two real vertex-
// displacement waves below. Normal-only: never displaces VERTEX, just
// keeps the surface from reading as two perfectly smooth sine sheets.
uniform float noise_amplitude = 0.015;
uniform float noise_scale = 6.0;
uniform float noise_speed = 0.05;

// Driven from sea.gd's own _sea_time accumulator (_physics_process()),
// not the engine's built-in TIME - sea.gd keeps advancing this while
// RegionField is frozen for battle, so the drift never visibly stalls.
uniform float sea_time = 0.0;

// --- Waves: two analytic sine waves, vertex()-displaced ---
// Long, slow swell and a short, quick chop, each traveling along its own
// direction (long_wave_direction/short_wave_direction, unit XZ vectors -
// sea.gd derives these from its own *_angle_degrees exports so the two
// don't run parallel). Amplitudes are tiny on purpose - this is a flat,
// not surf.
uniform float long_wave_length = 14.0;
uniform float long_wave_amplitude = 0.03;
uniform float long_wave_speed = 0.25;
uniform vec2 long_wave_direction = vec2(1.0, 0.0);
uniform float short_wave_length = 3.0;
uniform float short_wave_amplitude = 0.01;
uniform float short_wave_speed = 0.6;
uniform vec2 short_wave_direction = vec2(0.5736, 0.8192);

// Wave amplitude fades to 0 over the last wave_fade_width meters before
// inner_wave_extent (from sea.gd's near shoreward edge) - this is what
// lets the coarse, undisplaced outer skirt mesh meet the fine inner patch
// with no seam: both evaluate this exact function at the exact same world
// position at the boundary, so they agree regardless of which mesh either
// vertex actually belongs to. near_edge_z/shore_forward_z are pushed from
// sea.gd's own already-computed near-edge math. Displacement math alone
// isn't sufficient to prevent a visible seam though - see
// wave_fade_factor()'s own doc for the vertex-position half of that fix,
// which lives in sea.gd's _rebuild_wave_meshes().
uniform float inner_wave_extent = 60.0;
uniform float wave_fade_width = 25.0;
uniform float near_edge_z = 0.0;
uniform float shore_forward_z = -1.0;

// Fresnel: blend toward fog_color (already the sky/horizon tone - see its
// own doc below) at grazing angles, sea_color's own depth-graded tone
// looking straight down.
uniform float fresnel_power = 4.0;

// Depth-based color: shallow_color reads as sand showing through a thin
// film of water, deep_color a touch darker/more saturated - both driven
// by the same depth_diff (view-space water depth in meters, from the
// depth texture) the shore alpha fade already computes below, so all
// three effects (alpha fade, depth color, foam) agree on what "how deep
// is the water here" means.
uniform vec4 shallow_color : source_color = vec4(0.62, 0.66, 0.64, 1.0);
uniform vec4 deep_color : source_color = vec4(0.34, 0.44, 0.50, 1.0);
uniform float shallow_depth = 0.3;
uniform float deep_saturate_depth = 3.0;

// Foam: a pale (not white) band foam_width meters of water-depth wide,
// hugging the true waterline (depth_diff -> 0) however it actually
// curves - not a fixed world-space line. Modulated by the same edge noise
// the shore alpha fade wanders by, and breathing with the long wave's own
// height at that point (not a generic timer) so it visibly pulses as an
// actual wave crest passes under it.
uniform vec4 foam_color : source_color = vec4(0.86, 0.88, 0.86, 1.0);
uniform float foam_width = 0.4;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.5;

// Edge: alpha fades to 0 over shore_fade meters of scene-depth
// difference between this surface and whatever's behind it, so the
// water thins into the sand instead of cutting off at the mesh edge.
// edge_noise_amplitude/scale wander that fade distance so the
// waterline isn't a straight, uniform band. Still the ONLY thing gating
// ALPHA - foam/depth-color above are layered on top of it, not a
// replacement (the sea mesh's near edge sits generously inland of the
// real shoreline; this depth-buffer read is what keeps flat water from
// rendering over dry land there).
uniform float shore_fade : hint_range(0.01, 20.0) = 3.0;
uniform float edge_noise_amplitude = 1.5;
uniform float edge_noise_scale = 4.0;

// Distance: blend toward fog_color between fog_near_distance and
// fog_far_distance (view-space distance, same smoothstep shape
// ground.gdshader's near/far tint uses) so far water dissolves into
// the horizon instead of holding a hard flat color to the fog line.
// Doubles as the fresnel target above - it's already the region's sky/
// horizon tone (see region_sky.gd's near-identical horizon_color
// default), so there's no separate "sky color" plumbing needed.
uniform vec4 fog_color : source_color = vec4(0.85, 0.87, 0.88, 1.0);
uniform float fog_near_distance = 60.0;
uniform float fog_far_distance = 250.0;

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

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

// Two octaves, each drifting slowly and independently so the pattern
// doesn't repeat in an obviously periodic way. Normal-only (see
// noise_amplitude's own doc) - this never displaces VERTEX.
float sea_height(vec2 world_xz, float time) {
	vec2 drift_a = vec2(time * noise_speed, time * noise_speed * 0.7);
	vec2 drift_b = vec2(-time * noise_speed * 1.3, time * noise_speed * 0.9);
	float h = value_noise(world_xz / max(noise_scale, 0.001) + drift_a);
	h += value_noise(world_xz / max(noise_scale * 0.35, 0.001) + drift_b) * 0.5;
	return h;
}

// 1 near the shore, smoothly fading to 0 by inner_wave_extent - see its
// own uniform doc above for why this is what keeps the inner/outer mesh
// boundary seamless.
//
// DIVIDES by shore_forward_z, not multiplies - deliberately different from
// ground.gdshader's own dist_from_shore(), which multiplies. That's fine
// there: it's only ever compared against empirically-tuned thresholds
// (shore_slope_start etc.), so an off-by-|forward|^2 scale doesn't matter.
// Here it has to land EXACTLY on sea.gd's geometric mesh boundary (placed
// via world_z = near_edge_z - shore_forward_z * distance), so this must be
// that formula's exact inverse - multiplying would only be correct when
// |shore_forward_z| == 1 (the field's forward running along pure Z), and
// silently mismatch the real mesh boundary by shore_forward_z^2 otherwise,
// reintroducing exactly the seam this function exists to prevent.
float wave_fade_factor(vec2 world_xz) {
	float safe_forward_z = shore_forward_z >= 0.0 ? max(shore_forward_z, 0.0001) : min(shore_forward_z, -0.0001);
	float seaward_dist = (near_edge_z - world_xz.y) / safe_forward_z;
	return 1.0 - smoothstep(inner_wave_extent - max(wave_fade_width, 0.001), inner_wave_extent, seaward_dist);
}

// A single traveling sine wave: height and its analytic (dh/dx, dh/dz)
// slope, exact (no finite-difference epsilon needed) since the height
// field here has a closed form. direction is assumed already normalized
// by the caller.
float wave_height_and_slope(vec2 world_xz, float time, vec2 direction, float wavelength, float amplitude, float speed, out vec2 slope) {
	float k = TAU / max(wavelength, 0.001);
	float phase = k * dot(world_xz, direction) - k * speed * time;
	float height = amplitude * sin(phase);
	float slope_common = amplitude * k * cos(phase);
	slope = slope_common * direction;
	return height;
}

// Sum of the long + short waves, shore-faded - the one function vertex()
// (for displacement) and fragment() (for its slope's normal contribution
// and foam's breathing) both call, so all three stay in agreement.
float combined_wave_height(vec2 world_xz, float time, out vec2 slope) {
	vec2 slope_long;
	vec2 slope_short;
	float h_long = wave_height_and_slope(world_xz, time, normalize(long_wave_direction), long_wave_length, long_wave_amplitude, long_wave_speed, slope_long);
	float h_short = wave_height_and_slope(world_xz, time, normalize(short_wave_direction), short_wave_length, short_wave_amplitude, short_wave_speed, slope_short);
	float fade = wave_fade_factor(world_xz);
	slope = (slope_long + slope_short) * fade;
	return (h_long + h_short) * fade;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;

	vec2 slope;
	VERTEX.y += combined_wave_height(v_world_xz, sea_time, slope);
}

void fragment() {
	// Normal: the two waves' analytic slope plus the small-scale noise's
	// finite-difference slope, combined under one sign convention -
	// normalize(-dh/dx, 1, -dh/dz). The noise term is unchanged from v1;
	// wave_slope is new.
	vec2 wave_slope;
	combined_wave_height(v_world_xz, sea_time, wave_slope);

	float epsilon = 0.5;
	float h_c = sea_height(v_world_xz, sea_time);
	float h_x = sea_height(v_world_xz + vec2(epsilon, 0.0), sea_time);
	float h_z = sea_height(v_world_xz + vec2(0.0, epsilon), sea_time);

	vec3 world_normal = normalize(vec3(
		-wave_slope.x + (h_c - h_x) * noise_amplitude / epsilon,
		1.0,
		-wave_slope.y + (h_c - h_z) * noise_amplitude / epsilon
	));
	vec3 view_normal = normalize(mat3(VIEW_MATRIX) * world_normal);
	NORMAL = view_normal;

	// Edge fade: how far the opaque scene behind this fragment is from
	// the water surface, in view-space meters - the same quantity used
	// below for depth color and foam, so all three agree on "how deep is
	// the water here."
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth = -view.z;
	float water_depth = -VERTEX.z;
	float depth_diff = max(scene_depth - water_depth, 0.0);

	float wander = (value_noise(v_world_xz / max(edge_noise_scale, 0.001)) - 0.5) * 2.0 * edge_noise_amplitude;
	float effective_fade = max(shore_fade + wander, 0.01);
	float edge_alpha = smoothstep(0.0, effective_fade, depth_diff);

	// Depth-based color: lighten toward shallow_color as depth_diff -> 0,
	// darken toward deep_color past shallow_depth, saturating by
	// deep_saturate_depth. Both segments meet at plain sea_color exactly
	// at shallow_depth.
	float shallow_t = 1.0 - smoothstep(0.0, max(shallow_depth, 0.001), depth_diff);
	float deep_t = smoothstep(shallow_depth, max(deep_saturate_depth, shallow_depth + 0.001), depth_diff);
	vec3 depth_albedo = mix(mix(sea_color.rgb, shallow_color.rgb, shallow_t), deep_color.rgb, deep_t);

	// Fresnel: reflected sky at grazing angles, the depth-graded tone
	// above looking straight down.
	vec3 view_dir = normalize(-VERTEX);
	float fresnel = pow(1.0 - clamp(dot(view_normal, view_dir), 0.0, 1.0), max(fresnel_power, 0.001));
	vec3 albedo = mix(depth_albedo, fog_color.rgb, fresnel);

	// Foam: a band foam_width of depth_diff wide right at the true
	// waterline, patchy via the same edge noise, breathing with the long
	// wave's own height at this point (not a generic timer).
	vec2 breathe_slope;
	float long_h = wave_height_and_slope(v_world_xz, sea_time, normalize(long_wave_direction), long_wave_length, long_wave_amplitude, long_wave_speed, breathe_slope);
	float breathe = 0.5 + 0.5 * (long_h / max(long_wave_amplitude, 0.0001));
	float foam_noise = value_noise(v_world_xz / max(edge_noise_scale, 0.001));
	float foam_edge = 1.0 - smoothstep(0.0, max(foam_width, 0.001), depth_diff);
	float foam_mask = foam_edge * mix(0.6, 1.0, foam_noise) * mix(0.7, 1.0, breathe);
	albedo = mix(albedo, foam_color.rgb, foam_mask * foam_strength);

	// Distance: dissolve into the fog color toward the horizon. Applied
	// last so far water always fully resolves to it regardless of the
	// depth/fresnel/foam layering above.
	float dist = length(VERTEX);
	float fog_t = smoothstep(fog_near_distance, fog_far_distance, dist);
	albedo = mix(albedo, fog_color.rgb, fog_t);

	ALBEDO = albedo;
	ROUGHNESS = sea_roughness;
	METALLIC = 0.0;
	ALPHA = edge_alpha;
}
