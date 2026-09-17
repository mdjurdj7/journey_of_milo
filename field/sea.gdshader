shader_type spatial;
// fog_disabled: the see-through component is a screen-texture sample
// (see refraction_strength below) that already carries the environment's
// fog, so letting the environment fog this surface again would fog the
// seabed twice. The water's own colour still dissolves toward fog_color
// with distance via the shader's own fog_near/far blend in fragment().
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx, fog_disabled;

// Surface: matte, not a mirror. The sun's GGX lobe at roughness 0.7 with
// sea_specular 0.12 (Godot maps SPECULAR to F0 = 0.08 x value, so ~0.01)
// peaks at well under 1% of the light's radiance in the mirror direction
// - broad and faint by construction, so no white patch can appear from
// any camera angle. (At the old 0.25 / 0.5 the same lobe peaked near
// full white.) sea_specular is scaled by the water amount in fragment()
// so invisible water carries no highlight at all.
uniform float sea_roughness : hint_range(0.0, 1.0) = 0.7;
uniform float sea_specular : hint_range(0.0, 1.0) = 0.12;

// The surface ripple: a slow two-octave field (sea_height(), sampling the
// baked surface_noise tile) scrolling at noise_speed - the THIRD,
// smallest-scale rate on top of the two analytic waves below. Read twice in
// fragment(): as a finite-difference NORMAL perturbation scaled by
// noise_amplitude (the light's specular responds to that), and as a
// direct modulation of the sky-reflection amount scaled by
// ripple_strength (see sky_reflect_color below) - the latter is what
// actually reads as slow movement from the top-down camera, where the
// normal wobble alone barely changes the view angle. Never displaces
// VERTEX.
uniform float noise_amplitude = 0.015;
uniform float noise_scale = 6.0;
uniform float noise_speed = 0.05;
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.35;

// Driven from sea.gd's own _sea_time accumulator (_physics_process()),
// not the engine's built-in TIME - sea.gd keeps advancing this while
// RegionField is frozen for battle, so the drift never visibly stalls.
uniform float sea_time = 0.0;

// --- Waves: two analytic sine waves, normal-only ---
// Long, slow swell and a short, quick chop, each traveling along its own
// direction (long_wave_direction/short_wave_direction, unit XZ vectors -
// sea.gd derives these from its own *_angle_degrees exports so the two
// don't run parallel). Their slope goes into the per-fragment normal and
// the long wave's height drives the foam's breathing; they no longer
// displace vertices (see vertex()). Amplitudes are tiny on purpose -
// this is a flat, not surf.
uniform float long_wave_length = 14.0;
uniform float long_wave_amplitude = 0.03;
uniform float long_wave_speed = 0.25;
uniform vec2 long_wave_direction = vec2(1.0, 0.0);
uniform float short_wave_length = 3.0;
uniform float short_wave_amplitude = 0.01;
uniform float short_wave_speed = 0.6;
uniform vec2 short_wave_direction = vec2(0.5736, 0.8192);

// Wave amplitude fades to 0 over wave_calm_distance meters as the water
// approaches the actual shoreline (the same landmass shape ground.gd's
// wet band and RegionField's wade drain both key off - see
// landmass_distance()'s own doc below), full amplitude everywhere else.
// This is also what keeps the inner (fine) mesh and outer (coarse) skirt
// seamless where they meet: both share one material and evaluate this
// exact function at the exact same world position, so they agree
// regardless of which mesh a given vertex belongs to, wherever that
// meeting edge happens to fall - the fade no longer needs to be anchored
// to inner_wave_extent itself for that (it isn't, any more).
uniform float wave_calm_distance = 2.0;
// near_edge_z/shore_forward_z still mean exactly what they always did
// (Sea's own near-edge/forward reference, pushed from sea.gd's already-
// computed math) - shore_forward_z is reused below as the sign convention
// for the seaward edge (forward points inland); near_edge_z doubles as
// the curve's seaward reference (see landmass_curve_t()'s own doc) since
// it's numerically the same point by construction.
uniform float near_edge_z = 0.0;
uniform float shore_forward_z = -1.0;
// The rest of the landmass shape, mirrored from ground.gd's own GDScript
// (_landmass_curve_t()/_landmass_distance()/_seaward_distance()) - same
// dual-port approach this file's hash()/value_noise() already use for
// ground.gdshader's identical functions. Pushed from sea.gd, which reads
// them off Ground/RegionField directly (see Sea._push_landmass_uniforms()).
uniform float landmass_half_width_inland = 12.0;
uniform float landmass_half_width_seaward = 18.0;
uniform float landmass_width_curve_power = 1.0;
uniform float shoreline_noise_scale = 6.0;
uniform float shoreline_noise_amplitude = 2.5;
uniform float landmass_inland_z = 0.0;
uniform float landmass_seaward_edge_z = 0.0;

// Sky reflection: a Schlick-shaped blend toward sky_reflect_color -
// sky_reflect_min of it looking straight down, rising to full at grazing
// angles with fresnel_power. The floor matters: from the field camera's
// ~45 degree pitch, pow(1 - NdotV, 4) alone is ~0.01, i.e. no reflection
// at all, and the water reads as its flat base colour. The floor is what
// lets it sit lighter than the sand; ripple_strength (above) then
// modulates this same term so the reflection visibly drifts.
uniform vec4 sky_reflect_color : source_color = vec4(0.94, 0.95, 0.96, 1.0);
uniform float sky_reflect_min : hint_range(0.0, 1.0) = 0.05;
uniform float fresnel_power = 4.0;

// Depth-driven tint: water_depth is the VERTICAL metres of water under
// each fragment (depth texture, converted from view-space Z in
// fragment()). Colour runs shallow_color -> deep_color and alpha
// shallow_alpha -> 1.0 over the same smoothstep(0, depth_opaque, depth),
// so shallow water is mostly the sand showing through tinted and past
// depth_opaque it's opaque deep_color. Muted teal - green-leaning against
// the ground's pale warm sand (dry_color (0.74, 0.70, 0.60)) and the
// grey-blue horizon, darker with depth so the three hues stay distinct.
uniform vec4 shallow_color : source_color = vec4(0.62, 0.72, 0.70, 1.0);
uniform vec4 deep_color : source_color = vec4(0.30, 0.46, 0.50, 1.0);
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.15;
// 2.0 = the field's own maximum water depth (landmass_below_sea_depth),
// so the deepest water actually reaches deep_color; larger values leave
// warm sand showing through everywhere and grey the water out.
uniform float depth_opaque = 2.0;

// Absorption: the see-through seabed sample is multiplied by a per-
// channel transmittance exp(-water_depth * absorption) before it's mixed
// in, so the sand seen through the water darkens and cools with depth -
// red absorbed fastest, blue least, like real water. Caustics ride on the
// seabed sample, so they dim with depth by the same law. Applied to the
// refracted sample only; the surface's own colour (shallow/deep tint) is
// untouched.
uniform vec3 absorption = vec3(1.4, 0.7, 0.5);

// Refraction: the see-through component isn't plain alpha blending any
// more - it's the screen texture sampled at SCREEN_UV displaced by the
// ripple's own surface slope (the finite-difference slope of sea_height(),
// rotated into view space) x refraction_strength, so the seabed wobbles
// with the surface. Composited the way BaseMaterial3D's refraction does
// it: the refracted sample goes to EMISSION (already lit, must not be lit
// again), ALBEDO/SPECULAR are scaled by the water amount, ALPHA is 1.0
// (the material stays in the transparent pass, which is what makes the
// screen/depth textures available at all). The displacement is scaled by
// the water amount too, so where the water is invisible (depth 0, the
// mesh over dry sand) the sample is exactly the pixel behind - no wobble
// on dry land. refraction_strength is UV units at unit slope; the ripple
// slope runs to ~1, so ~0.01 is about 5-10 px at 1080p.
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float refraction_strength = 0.01;

// Surface pattern: what makes the plane itself read as a surface from
// directly above. Two scrolling samples of the surface_noise tile - at
// surface_pattern_scale (~3m per tile) and a third of it (~1m) - moving in different directions
// at different speeds (the small one faster), summed into a soft field
// whose upper half becomes bright ridges painted toward sky_reflect_
// color by up to 2 x surface_pattern_strength (so the mean lift is about
// the strength itself, peaks twice that). Brighten-only: nothing goes
// darker than the depth tint. Composited as an OVERLAY on the final
// surface/seabed mix (see fragment()), gated only by the waterline edge
// - so it reads identically in the shallows and in deep water, and the
// refracted seabed underneath is covered, not tinted: a pattern ON the
// water, distinct from the caustics under it. Scrolls on sea_time like
// the ripple.
uniform float surface_pattern_strength : hint_range(0.0, 0.5) = 0.10;
uniform float surface_pattern_scale = 3.0;
uniform float surface_pattern_speed = 0.4;

// Foam: a thin bright line at the waterline - foam_width metres of water
// DEPTH wide (~2-3x that laterally at the beach's slope), hugging the
// true waterline however it curves. A touch lighter than shallow_color,
// not white. Composited as its own opaque paint on top of the final
// surface/seabed mix (see fragment()), NOT folded into the surface colour
// - the water is nearly transparent exactly where foam lives, so a foam
// term inside the surface colour was scaled to nothing. Its own 5cm
// fade-in from depth 0 keeps it off dry sand. Patchy via value noise at
// edge_noise_scale, and breathing with the long wave's own height at
// that point (not a generic timer) so it visibly pulses as an actual
// wave crest passes under it.
uniform vec4 foam_color : source_color = vec4(0.74, 0.82, 0.80, 1.0);
uniform float foam_width = 0.25;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.5;
uniform float edge_noise_scale = 4.0;

// Edge: a thin softener only - alpha ramps 0 -> shallow_alpha over the
// first shore_fade_width metres of water depth, so the waterline reads as
// a line, not a haze (the old multi-metre noised fade was the haze). The
// ground's own wet band carries the transition inland; this doesn't
// duplicate it. Still what keeps flat water from rendering over dry land
// where the sea mesh reaches inland of the real shoreline (depth 0 ->
// alpha 0).
uniform float shore_fade_width : hint_range(0.01, 5.0) = 0.3;

// Distance: blend toward fog_color between fog_near_distance and
// fog_far_distance (view-space distance, same smoothstep shape
// ground.gdshader's near/far tint uses) so far water dissolves into
// the horizon instead of holding a hard flat color to the fog line. The
// region's sky/horizon tone (see region_sky.gd's near-identical
// horizon_color default); the near-field sky reflection has its own
// sky_reflect_color above, deliberately paler than this.
uniform vec4 fog_color : source_color = vec4(0.85, 0.87, 0.88, 1.0);
uniform float fog_near_distance = 60.0;
uniform float fog_far_distance = 250.0;
// Scales the blend above; 0 (default) turns the sea's own fog off
// entirely and deep_color runs to the horizon.
uniform float fog_strength : hint_range(0.0, 1.0) = 0.0;

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

// Every surface field that is SEEN - the ripple normal and the surface
// pattern - samples surface_noise, a seamless FastNoiseLite Perlin tile
// baked by sea.gd (see its _create_surface_noise()), rather than any
// procedural noise evaluated here. value_noise() above is kept only for
// the SDF-shoreline mirror (landmass_side_distance(), which must match
// ground.gd's own port) and the foam's patchiness. History: the value
// noise put lattice-aligned creases into the ripple (a derivative of it)
// that scrolled as straight seams; a hash-based gradient noise replaced
// it and produced large flat-edged blocks instead, since fract(p * 123)
// style hashes lose precision once the ever-growing sea_time drift pushes
// the cell coordinates into the hundreds. A texture has neither problem:
// exact values at any coordinate (repeat_enable wraps them), bilinear
// between texels, mipmapped for the far skirt. One tile = one unit of
// UV, so sampling at world_xz / scale makes a tile span scale metres.
uniform sampler2D surface_noise : filter_linear_mipmap, repeat_enable;

float surface_noise_at(vec2 uv) {
	return texture(surface_noise, uv).r;
}

// The same tile sampled on a rotated UV frame - give every octave/layer
// its own angle so their tiles never line up (a rotated seamless tile is
// still seamless under repeat). The scroll drift is added AFTER the
// rotation, in texture space, so that a drift of a whole number of tiles
// is invisible - that's what lets sea.gd wrap sea_time (see its
// sea_time_period) without any layer popping: at the wrap every drift
// vector lands on an integer, and an integer shift of a repeating tile
// is a no-op. (Added before the rotation it would be rotated into a
// non-integer shift and pop.)
float surface_noise_rotated(vec2 uv, float angle_radians, vec2 drift) {
	float c = cos(angle_radians);
	float s = sin(angle_radians);
	return surface_noise_at(vec2(c * uv.x - s * uv.y, s * uv.x + c * uv.y) + drift);
}

// Two octaves, each drifting slowly and independently so the pattern
// doesn't repeat in an obviously periodic way, on two differently
// rotated tile frames. Range ~[0, 1.5], mean 0.75 - fragment() relies on
// that when it remaps to a signed ripple. Normal-only (see
// noise_amplitude's own doc) - this never displaces VERTEX; the normal
// takes its derivative by two offset taps in fragment().
float sea_height(vec2 world_xz, float time) {
	vec2 drift_a = vec2(time * noise_speed, time * noise_speed * 0.7);
	vec2 drift_b = vec2(-time * noise_speed * 1.3, time * noise_speed * 0.9);
	float h = surface_noise_rotated(world_xz / max(noise_scale, 0.001), 0.0, drift_a);
	h += surface_noise_rotated(world_xz / max(noise_scale * 0.35, 0.001), 0.61, drift_b) * 0.5;
	return h;
}

// 0 at the inland wall's own Z (landmass_inland_z), 1 at the curve's
// seaward reference (near_edge_z), clamped beyond both - mirrors ground.gd's
// _landmass_curve_t() exactly (same clamp-past-1 reasoning: the shape stays
// open-ended toward the sea, the half-width just holds at
// landmass_half_width_seaward past that point rather than closing off).
float landmass_curve_t(float world_z) {
	float span = near_edge_z - landmass_inland_z;
	if (abs(span) < 0.0001) {
		return 0.0;
	}
	float linear_t = clamp((world_z - landmass_inland_z) / span, 0.0, 1.0);
	return pow(linear_t, max(landmass_width_curve_power, 0.0001));
}

// Mirrors ground.gd's _landmass_distance() - left/right only, noised,
// no rounding at either end (see ground.gd's own doc on why there are no
// corners left to round once both ends are open).
float landmass_side_distance(vec2 world_xz) {
	float t = landmass_curve_t(world_xz.y);
	float local_half_width = mix(landmass_half_width_inland, landmass_half_width_seaward, t);
	float noise = (value_noise(world_xz / max(shoreline_noise_scale, 0.001)) - 0.5) * 2.0 * shoreline_noise_amplitude;
	return abs(world_xz.x) - local_half_width + noise;
}

// Mirrors ground.gd's _seaward_distance() - a plain straight ramp along Z,
// no rounding, no noise. DIVIDES... no, MULTIPLIES by shore_forward_z here,
// matching ground.gd's own convention (forward points inland, so
// subtracting forward.z*distance moves seaward) - safe unconditionally
// since this is a sign flip, not a geometric-boundary division (contrast
// the old wave_fade_factor(), which divided because it had to land exactly
// on a specific meshed boundary; this is just "which side of a line").
float landmass_seaward_distance(float world_z) {
	float edge_z = landmass_seaward_edge_z != 0.0 ? landmass_seaward_edge_z : near_edge_z;
	return (edge_z - world_z) * shore_forward_z;
}

// Mirrors ground.gd's get_landmass_distance() - whichever edge (left/
// right's noised landmass_side_distance(), or seaward's plain landmass_
// seaward_distance()) a position is furthest past wins, same max()
// combination ground.gd uses to decide which edge actually submerges a
// point.
float landmass_distance(vec2 world_xz) {
	return max(landmass_side_distance(world_xz), landmass_seaward_distance(world_xz.y));
}

// 0 landward of the shoreline (calm - flat water right at the sand), 1 by
// wave_calm_distance meters past it (full amplitude - open water), reading
// the same noised/ramped shoreline the wet band and wade drain use instead
// of a straight world-space line, so calming (and, upstream in vertex(),
// the real vertex displacement) actually follows wherever the shore
// really is - including its own wander - rather than a fixed line that
// can drift out of sync with it (the bug this function replaces).
float wave_fade_factor(vec2 world_xz) {
	return smoothstep(0.0, max(wave_calm_distance, 0.001), landmass_distance(world_xz));
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

// Sum of the long + short waves, shore-faded. Fragment-only now: its
// slope feeds the per-fragment normal (and the long wave alone feeds the
// foam's breathing). vertex() no longer displaces - see its own doc.
float combined_wave_height(vec2 world_xz, float time, out vec2 slope) {
	vec2 slope_long;
	vec2 slope_short;
	float h_long = wave_height_and_slope(world_xz, time, normalize(long_wave_direction), long_wave_length, long_wave_amplitude, long_wave_speed, slope_long);
	float h_short = wave_height_and_slope(world_xz, time, normalize(short_wave_direction), short_wave_length, short_wave_amplitude, short_wave_speed, slope_short);
	float fade = wave_fade_factor(world_xz);
	slope = (slope_long + slope_short) * fade;
	return (h_long + h_short) * fade;
}

// No vertex displacement any more - the plane is exactly flat and every
// visible quantity (normal, pattern, depth, refraction) is evaluated per
// fragment from v_world_xz, so mesh resolution can't show through as
// edges anywhere. The waves' +-4cm of height was invisible from the
// field camera anyway; what they contribute (their slope in the normal)
// is unchanged. Also makes the depth-buffer water depth exact and steady
// instead of breathing with the surface.
void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;
}

void fragment() {
	// Normal, per fragment: the two waves' analytic slope plus the ripple
	// noise's finite-difference slope, combined under one sign convention
	// - normalize(-dh/dx, 1, -dh/dz). Nothing here comes from the mesh's
	// own vertex normals.
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

	// Water depth: how far the opaque scene behind this fragment (the
	// ground, or whatever stands in the water) is below the surface, in
	// VERTICAL metres. The depth texture gives a view-space Z difference;
	// that's a distance along the camera's axis, not down through the
	// water - from a 45 degree pitch it overstates depth by ~1.4x and
	// changes with view angle. Converted through the world-space view ray:
	// both the surface point and the ground point sit on the same ray, so
	// their height difference is (ray length difference) x |ray.y|, and
	// ray length per unit of view Z is 1 / |ray_view.z|. The one depth
	// quantity tint, alpha, edge and foam all read, so they agree on "how
	// deep is the water here."
	float depth_raw = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_depth_view = -view.z;
	float surface_depth_view = -VERTEX.z;
	float depth_diff_view = max(scene_depth_view - surface_depth_view, 0.0);
	vec3 ray_view = normalize(VERTEX);
	vec3 ray_world = normalize(mat3(INV_VIEW_MATRIX) * ray_view);
	float vertical_per_view_z = max(-ray_world.y, 0.0) / max(-ray_view.z, 0.001);
	float water_depth = depth_diff_view * vertical_per_view_z;

	// Depth-driven tint and opacity: one curve for both (see shallow_color's
	// own doc), so the colour takes over exactly as the sand stops showing
	// through.
	float depth_t = smoothstep(0.0, max(depth_opaque, 0.001), water_depth);
	vec3 water_rgb = mix(shallow_color.rgb, deep_color.rgb, depth_t);
	float depth_alpha = mix(shallow_alpha, 1.0, depth_t);

	// Edge: the thin waterline softener (see shore_fade_width's own doc).
	float edge_alpha = smoothstep(0.0, max(shore_fade_width, 0.001), water_depth);

	// Sky reflection: Schlick with a floor (see sky_reflect_color's own
	// doc), then modulated by the same ripple field the normal above was
	// perturbed by - h_c is sea_height()'s two-octave sum, range ~[0, 1.5]
	// around 0.75, remapped to [-1, 1]. Reflection only: the base colour
	// and alpha are untouched by it, so the ripple reads as light moving
	// on the surface, not the water changing.
	vec3 view_dir = -ray_view;
	float n_dot_v = clamp(dot(view_normal, view_dir), 0.0, 1.0);
	float fresnel = sky_reflect_min + (1.0 - sky_reflect_min) * pow(1.0 - n_dot_v, max(fresnel_power, 0.001));
	float ripple = (h_c - 0.75) / 0.75;
	float sky_t = clamp(fresnel * (1.0 + ripple * ripple_strength), 0.0, 1.0);
	vec3 albedo = mix(water_rgb, sky_reflect_color.rgb, sky_t);

	// Distance: dissolve into the fog color toward the horizon. Applied
	// last to the surface colour so far water always fully resolves to it
	// regardless of the depth/reflection layering above.
	float dist = length(VERTEX);
	float fog_t = smoothstep(fog_near_distance, fog_far_distance, dist) * fog_strength;
	albedo = mix(albedo, fog_color.rgb, fog_t);

	// Surface pattern (see surface_pattern_strength's own doc): two
	// scrolling noise layers summed, upper half -> bright ridges. Computed
	// here, composited below as an OVERLAY on the final surface/seabed mix
	// (not folded into the water colour, which is scaled by water_amount
	// and so vanishes exactly where the water is transparent) - gated only
	// by edge_alpha, i.e. "is there water here at all", so it reads the
	// same in the shallows as in deep water.
	float pattern_scale = max(surface_pattern_scale, 0.001);
	vec2 pattern_drift_a = vec2(0.7, 0.4) * surface_pattern_speed * sea_time;
	vec2 pattern_drift_b = vec2(-0.3, 0.9) * surface_pattern_speed * 1.7 * sea_time;
	float pattern_a = surface_noise_rotated(v_world_xz / pattern_scale, 1.13, pattern_drift_a);
	float pattern_b = surface_noise_rotated(v_world_xz / (pattern_scale / 3.0), 2.31, pattern_drift_b);
	float pattern = smoothstep(0.45, 0.85, pattern_a * 0.6 + pattern_b * 0.4);
	float pattern_amount = pattern * surface_pattern_strength * 2.0 * edge_alpha;

	// Foam: a band foam_width of water depth wide right at the true
	// waterline, patchy via value noise, breathing with the long wave's
	// own height at this point (not a generic timer). Computed here,
	// composited below as opaque paint over both the surface and the
	// seabed terms - see foam_color's own doc for why it can't live in
	// the surface colour.
	vec2 breathe_slope;
	float long_h = wave_height_and_slope(v_world_xz, sea_time, normalize(long_wave_direction), long_wave_length, long_wave_amplitude, long_wave_speed, breathe_slope);
	float breathe = 0.5 + 0.5 * (long_h / max(long_wave_amplitude, 0.0001));
	float foam_noise = value_noise(v_world_xz / max(edge_noise_scale, 0.001));
	float foam_edge = smoothstep(0.0, 0.05, water_depth) * (1.0 - smoothstep(0.05, max(foam_width, 0.06), water_depth));
	float foam_amount = foam_edge * mix(0.6, 1.0, foam_noise) * mix(0.7, 1.0, breathe) * foam_strength;

	// Composite (see refraction_strength's own doc): water_amount is what
	// ALPHA used to be. The see-through part is the screen texture behind
	// this fragment, displaced by the ripple slope, into EMISSION; the
	// water's own lit colour is ALBEDO scaled to the remainder. SPECULAR
	// scales too, or the light's highlight would show at full strength
	// over invisible water. Also fades in with the edge, so far-shore
	// pixels never get pulled onto dry sand.
	float water_amount = depth_alpha * edge_alpha;
	vec2 ripple_slope = vec2(h_c - h_x, h_c - h_z) / epsilon;
	vec2 ripple_view = (mat3(VIEW_MATRIX) * vec3(ripple_slope.x, 0.0, ripple_slope.y)).xy;
	vec2 refracted_uv = SCREEN_UV + ripple_view * refraction_strength * water_amount;
	vec3 behind = textureLod(screen_texture, refracted_uv, 0.0).rgb;
	// Absorption through this fragment's own column of water (see
	// absorption's doc) - the depth at SCREEN_UV, not at the refracted UV;
	// the offset is a few pixels, the difference is nothing.
	vec3 transmittance = exp(-water_depth * max(absorption, vec3(0.0)));
	behind *= transmittance;

	// Overlays paint over the whole mix, in order: the surface pattern
	// (toward the sky colour), then foam on top. Each replaces its amount
	// of both the lit surface term and the see-through term, so both read
	// at full strength even where the water itself is nearly transparent.
	vec3 surface = mix(albedo * water_amount, sky_reflect_color.rgb, pattern_amount);
	surface = mix(surface, foam_color.rgb, foam_amount);
	float overlay_amount = 1.0 - (1.0 - pattern_amount) * (1.0 - foam_amount);
	ALBEDO = surface;
	EMISSION = behind * (1.0 - water_amount) * (1.0 - overlay_amount);
	ROUGHNESS = sea_roughness;
	SPECULAR = sea_specular * water_amount;
	METALLIC = 0.0;
	ALPHA = 1.0;
}
