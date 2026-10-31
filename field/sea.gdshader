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

// Open-water crests: broad pale bands on the open sea, running along the
// floor mask's shore-distance contours (so parallel to the shore however
// it curves) and rolling in toward it - one every crest_spacing_m metres
// of shore distance, one passing any point every crest_period_s seconds.
// Each band has a soft shoreward front (crest_front of a spacing) and a
// longer fade seaward (crest_tail), and is cut along its length into
// stretches by noise every crest_breakup_scale metres, kept where it
// clears crest_breakup, a different cut per crest - so a few long crests
// with quiet water between, not stripes. Painted toward crest_color by up
// to crest_strength, as an overlay like the surface pattern; crest_calm
// takes that much of the surface pattern away between crests. Starts
// crest_shore_start metres out from the waterline (fading in over
// crest_shore_fade), so the foam line and swash are untouched; off over
// pools, and faded out near the grid's edge, where its distance stops
// growing. Off unless crests_enabled. crest_period_s should divide
// sea.gd's sea_time_period (7000) so the bands don't jump at the wrap.
uniform bool crests_enabled = false;
uniform vec4 crest_color : source_color = vec4(0.86, 0.9, 0.9, 1.0);
uniform float crest_strength : hint_range(0.0, 1.0) = 0.3;
uniform float crest_spacing_m = 9.0;
uniform float crest_period_s = 14.0;
uniform float crest_front : hint_range(0.0, 0.5) = 0.05;
uniform float crest_tail : hint_range(0.0, 1.0) = 0.25;
uniform float crest_breakup : hint_range(0.0, 1.0) = 0.45;
uniform float crest_breakup_scale = 7.0;
uniform float crest_shore_start = 3.0;
uniform float crest_shore_fade = 3.0;
uniform float crest_calm : hint_range(0.0, 1.0) = 0.0;

// Pool clarity: a pool's water, by the enclosure grid, is a few cm deep -
// inside shore_fade_width, so the open sea's depth curve leaves it all
// but invisible. Over a pool instead: the waterline softener runs over
// pool_edge_depth_m; the bed seen through it is coloured toward
// pool_tint_color by pool_filter (a filter, the colour scaled to its
// brightest channel, so the bed keeps its contrast) and absorbed at
// pool_absorption_scale of absorption; and the water's own colour, a
// veil over the bed, starts at pool_tint in place of shallow_alpha.
// Ground's half (the bed's and bank's detail and darkening) is pushed
// from Sea's same group. Off unless pool_clarity_enabled.
uniform bool pool_clarity_enabled = false;
uniform vec4 pool_tint_color : source_color = vec4(0.48, 0.78, 0.74, 1.0);
uniform float pool_tint : hint_range(0.0, 1.0) = 0.06;
uniform float pool_filter : hint_range(0.0, 1.0) = 0.3;
uniform float pool_edge_depth_m = 0.04;
uniform float pool_absorption_scale : hint_range(0.0, 1.0) = 0.5;
// The pool's own surface, so it reads as water over the bed rather than a
// tint on it: pool_sheen of sky_reflect_color, swelling and thinning with
// the same drifting ripple field the normal uses; and fine
// glints toward pool_glint_color - thin lines where a drifting noise every
// pool_glint_scale_m metres crosses its midline, within pool_glint_width of
// it, broken by a second layer, moving at pool_glint_speed - at up to
// pool_glint_strength. Both fade in with the pool's own waterline.
uniform float pool_sheen : hint_range(0.0, 1.0) = 0.14;
uniform vec4 pool_glint_color : source_color = vec4(0.96, 0.97, 0.95, 1.0);
uniform float pool_glint_strength : hint_range(0.0, 1.0) = 0.35;
uniform float pool_glint_scale_m = 3.0;
uniform float pool_glint_width : hint_range(0.0, 1.0) = 0.2;
uniform float pool_glint_speed = 0.06;

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
// The ground's own landmass distance grid, handed over by Sea._push_
// landmass_distance() - the hookup this shader's wave calming was always
// meant to grow into, arriving now because standing pools are its first
// consumer. Channel g is "the nearest water here is enclosed": a pool,
// not the sea. Foam and swash are the sea's edge behaviours and are
// scaled away over one; the depth tint, the absorption and the sky
// reflection are properties of water itself and are not.
uniform sampler2D landmass_distance_tex : filter_linear, repeat_disable;
uniform vec2 landmass_distance_origin = vec2(0.0);
uniform float landmass_distance_cell = 0.25;
uniform vec2 landmass_distance_dims = vec2(1.0);
uniform bool landmass_distance_ready = false;

uniform vec4 foam_color : source_color = vec4(0.66, 0.70, 0.70, 1.0);
uniform float foam_width = 0.25;
uniform float foam_strength : hint_range(0.0, 1.0) = 0.35;
uniform float edge_noise_scale = 4.0;
// Broken foam: above 0, the foam line is cut into lace - two octaves of
// value noise every foam_breakup_scale metres, drifting along the long
// wave at foam_drift_speed, kept only where they clear foam_breakup
// (eased over foam_breakup_softness) - in place of the edge noise's
// gentle 60-100% patchiness. swash_breakup shares the same lace into the
// swash front, at a lower cut so more of it stays. 0 (the default) is
// the continuous line and front as they were.
uniform float foam_breakup : hint_range(0.0, 1.0) = 0.0;
uniform float foam_breakup_scale = 1.2;
uniform float foam_breakup_softness = 0.12;
uniform float foam_drift_speed = 0.05;
uniform float swash_breakup : hint_range(0.0, 1.0) = 0.0;
// Textured foam: with foam_mask_enabled, a tiling greyscale foam mask
// (white = foam) cuts the foam line and - swash_breakup of the way - the
// swash front, IN PLACE of the procedural lace above, one tile every
// foam_mask_scale_m metres of world XZ, its value times foam_mask_
// strength. Only inside those two bands, never the open sea. Static in
// world space - the bands move over it - and sampled at the same XZ by
// ground.gdshader's run-up edge (Sea.set_foam_mask() hands it over), so
// sea foam and run-up show the same lace. Read as linear data, red only.
uniform bool foam_mask_enabled = false;
uniform sampler2D foam_mask : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float foam_mask_scale_m = 3.0;
uniform float foam_mask_strength = 1.0;
// The mask's motion with the swash (see foam_mask_motion()): metres the
// lace is carried shoreward at the top of each run-up, along the floor
// mask's own shoreward direction. 0 (the default) leaves it still.
uniform float foam_travel_m = 0.0;

// Swash: a periodic wash of foam-coloured water that advances from
// swash_start_depth to the waterline over the first part of each
// swash_period cycle, brightening as it nears the line, holds, then
// recedes and fades. The band is swash_band_width metres of water DEPTH
// either side of its moving centre depth. Phase and per-cycle amplitude
// come from the shared swash_phase()/swash_cycle_amplitude() below -
// the SAME code ground.gdshader runs (see there) so the ground's wet
// band breathes in step with each wash at the same stretch of beach.
// Reads as a FRONT: a crisp leading edge on the shoreward side
// (smoothstep over swash_edge_width of depth), a soft trailing edge over
// swash_band_width toward deeper water, no patch noise, and its own
// swash_color - lighter than foam_color - so the front is the brightest
// thing near the line. Composited as its own overlay on top of the foam
// line (which stays as a floor under it). Never past the waterline:
// gated by depth like the foam. swash_period must divide sea.gd's
// sea_time_period so the phase doesn't jump at the time wrap (7 into
// 7000: fine).
uniform vec4 swash_color : source_color = vec4(0.82, 0.84, 0.82, 1.0);
uniform float swash_strength : hint_range(0.0, 1.0) = 0.7;
uniform float swash_period = 7.0;
uniform float swash_start_depth = 0.6;
uniform float swash_band_width = 0.2;
uniform float swash_edge_width = 0.05;
// Phase offset along the shore: the noise at swash_phase_noise_scale
// (slow - ~24m features) shifts the phase by (noise - 0.5) x swash_phase_
// spread of a cycle, so the whole shore stays within +-spread/2 of one
// cycle of itself and the front reads as one wave arriving a little
// earlier or later along the beach, not as unrelated patches.
uniform float swash_phase_noise_scale = 24.0;
uniform float swash_phase_spread : hint_range(0.0, 1.0) = 0.15;

// Edge: a thin softener only - alpha ramps 0 -> shallow_alpha over the
// first shore_fade_width metres of water depth, so the waterline reads as
// a line, not a haze (the old multi-metre noised fade was the haze). The
// ground's own wet band carries the transition inland; this doesn't
// duplicate it. Still what keeps flat water from rendering over dry land
// where the sea mesh reaches inland of the real shoreline (depth 0 ->
// alpha 0).
uniform float shore_fade_width : hint_range(0.01, 5.0) = 0.3;

// Distance fog - this material is fog_disabled (see render_mode), so it
// reproduces the WorldEnvironment's depth fog itself: the SAME curve,
// smoothstep(fog_near_distance, fog_far_distance, view distance) (Godot's
// FOG_MODE_DEPTH at curve 1.0 is exactly that), applied as the SAME kind
// of term - an unlit flat colour blended over the finished pixel, after
// the overlays (see the composite in fragment()), never into ALBEDO
// where the sun would light it. Keep fog_near/far/color equal to the
// environment's depth begin/end/colour and the shore and the water plane
// fog at the same rate at the same distance. fog_strength scales it
// (1 = matches the environment's density 1.0).
uniform vec4 fog_color : source_color = vec4(0.86, 0.87, 0.86, 1.0);
uniform float fog_near_distance = 14.0;
uniform float fog_far_distance = 28.0;
uniform float fog_strength : hint_range(0.0, 1.0) = 1.0;

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

// The foam lace's own noise (see foam_breakup's doc). Not hash() /
// value_noise() above: their float hash magnifies the last bit of its
// input, and neighbouring cells reach a shared corner by different
// arithmetic (floor(p) against i + 1), so corners disagree and the noise
// steps along its lattice - hard-edged squares once thresholded, worse
// as the drift carries p into hundreds of cells. Those two stay as they
// are because landmass_side_distance() mirrors ground.gd's GDScript copy.
// This is ground.gdshader's integer hash, exact at every corner.
float lace_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p + 0.5)) + ivec2(1 << 20));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = h * 747796405u + 2891336453u;
	h = ((h >> ((h >> 28u) + 4u)) ^ h) * 277803737u;
	h = (h >> 22u) ^ h;
	return float(h) * (1.0 / 4294967295.0);
}

float lace_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = lace_hash(i);
	float b = lace_hash(i + vec2(1.0, 0.0));
	float c = lace_hash(i + vec2(0.0, 1.0));
	float d = lace_hash(i + vec2(1.0, 1.0));
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

// --- Swash phase: SHARED by sea.gdshader and ground.gdshader, keep byte-identical ---
// Both shaders declare the same uniforms (sea_time, swash_period,
// swash_phase_noise_scale, swash_phase_spread, surface_noise with the
// same sampler hints - all pushed from sea.gd) and run this exact code
// at the same world XZ, so the sea's wash and the ground's wet band
// agree on where in the cycle every stretch of beach is. Edit one, paste
// to the other.
//
// swash_phase(): 0..1 through one cycle, offset per stretch of shore by
// the slow noise at swash_phase_noise_scale - but only by
// (noise - 0.5) x swash_phase_spread of a cycle, so the whole shore is
// within +-spread/2 of one cycle of itself: one continuous front that
// lands a little earlier here and later there, never unrelated patches.
// swash_cycle_amplitude(): 0.6..1, a fixed random per cycle per stretch
// (the noise at twice the phase scale, re-sampled at a golden-ratio step
// per cycle index), so some washes are bigger than others and that too
// varies slowly along the shore.
// 0..1: is the water at this XZ a pool rather than the sea? See the
// uniform block above.
float landmass_enclosure_at(vec2 world_xz) {
	if (!landmass_distance_ready) {
		return 0.0;
	}
	vec2 uv = ((world_xz - landmass_distance_origin) / max(landmass_distance_cell, 0.001) + 0.5) / max(landmass_distance_dims, vec2(1.0));
	return texture(landmass_distance_tex, uv).g;
}

float swash_phase(vec2 world_xz, float time) {
	float offset = (texture(surface_noise, world_xz / max(swash_phase_noise_scale, 0.001)).r - 0.5) * swash_phase_spread;
	return fract(time / max(swash_period, 0.001) + offset);
}

float swash_cycle_amplitude(vec2 world_xz, float time) {
	vec2 phase_uv = world_xz / max(swash_phase_noise_scale, 0.001);
	float offset = (texture(surface_noise, phase_uv).r - 0.5) * swash_phase_spread;
	float cycle = floor(time / max(swash_period, 0.001) + offset);
	float n = texture(surface_noise, phase_uv * 0.5 + vec2(cycle * 0.618, cycle * 0.382)).r;
	return mix(0.6, 1.0, n);
}
// --- end shared block ---

// Where in the cycle the wash does what - fixed shape, not tuning:
// advance for the first 40%, hold at the line to 60% (while ground.
// gdshader's run-up sheet climbs 0.40-0.52 and holds to 0.60), recede to
// 80%, rest to 100%. ground.gdshader keys its run-up and wet mark off
// the same numbers - edit both together, or the front and the sheet
// stop meeting at the line at 0.40.
const float SWASH_ADVANCE_END = 0.4;
const float SWASH_HOLD_END = 0.6;
const float SWASH_RECEDE_END = 0.8;

// The wash's centre depth and intensity at a phase - centre runs
// swash_start_depth -> 0 over the advance (intensity rising to 1), sits
// at 0 through the hold, runs back out over the recede (intensity
// fading), and is off through the rest.
void swash_centre_and_intensity(float phase, out float centre, out float intensity) {
	if (phase < SWASH_ADVANCE_END) {
		float t = phase / SWASH_ADVANCE_END;
		centre = swash_start_depth * (1.0 - t);
		intensity = smoothstep(0.0, 1.0, t);
	} else if (phase < SWASH_HOLD_END) {
		centre = 0.0;
		intensity = 1.0;
	} else if (phase < SWASH_RECEDE_END) {
		float t = (phase - SWASH_HOLD_END) / (SWASH_RECEDE_END - SWASH_HOLD_END);
		centre = swash_start_depth * t;
		intensity = 1.0 - smoothstep(0.0, 1.0, t);
	} else {
		centre = swash_start_depth;
		intensity = 0.0;
	}
}

// --- Foam mask motion - the same math as ground.gdshader's copy, so the
// sea's swash foam and the ground's run-up edge move as one. ---
// How far the lace has been carried this cycle, 0..1: pushed in through
// the advance and the run-up's climb, drawn back over the rest of the
// cycle (slower), home at the wrap.
const float FOAM_PUSH_END = 0.52;
float foam_travel(float phase) {
	if (phase < FOAM_PUSH_END) {
		return smoothstep(0.0, FOAM_PUSH_END, phase);
	}
	return 1.0 - smoothstep(FOAM_PUSH_END, 1.0, phase);
}

// How far the surf's lace has dissolved, 0..1: gone at the wrap (so the
// next wave's fresh lace can't pop), dense by the advance, thinning out
// from the recede (SWASH_HOLD_END) to nothing just before the wrap.
float foam_dissolve(float phase) {
	return max(1.0 - smoothstep(0.0, 0.08, phase), smoothstep(SWASH_HOLD_END, 0.95, phase));
}

// The floor mask's signed shore distance (r; ground's sign: negative on
// sand, positive in water). Not landmass_distance(), which is the old
// built-in coastline.
float mask_shore_distance_at(vec2 world_xz) {
	vec2 uv = ((world_xz - landmass_distance_origin) / max(landmass_distance_cell, 0.001) + 0.5) / max(landmass_distance_dims, vec2(1.0));
	return texture(landmass_distance_tex, uv).r;
}

// 0..1, the open-water crests here (see crests_enabled's doc), before
// strength, colour and the pool gate; zone is how far into the open
// water the crests run here (0 near the shore, off, or past the grid).
float open_crest_at(vec2 world_xz, float time, out float zone) {
	zone = 0.0;
	if (!crests_enabled || !landmass_distance_ready) {
		return 0.0;
	}
	float d = mask_shore_distance_at(world_xz);
	float shore_in = smoothstep(crest_shore_start, crest_shore_start + max(crest_shore_fade, 0.001), d);
	// The grid's own edge: within 4 m of it the distance is clamped, so
	// the contours stop following the shore.
	vec2 grid_size = landmass_distance_dims * max(landmass_distance_cell, 0.001);
	vec2 from_origin = world_xz - landmass_distance_origin;
	vec2 to_edge = min(from_origin, grid_size - from_origin);
	float in_grid = smoothstep(0.0, 4.0, min(to_edge.x, to_edge.y));
	zone = shore_in * in_grid;
	float phase = d / max(crest_spacing_m, 0.001) + time / max(crest_period_s, 0.001);
	float s = fract(phase);
	float front = max(crest_front, 0.001);
	float band = smoothstep(0.0, front, s) * (1.0 - smoothstep(front, front + max(crest_tail, 0.001), s));
	float crest_index = floor(phase);
	vec2 cut_p = world_xz / max(crest_breakup_scale, 0.001) + vec2(crest_index * 7.31, crest_index * -3.17);
	float cut = lace_noise(cut_p) * 0.7 + lace_noise(cut_p * 2.3 + vec2(5.7, 1.9)) * 0.3;
	float keep = smoothstep(crest_breakup - 0.12, crest_breakup + 0.12, cut);
	return band * keep * zone;
}

// Unit XZ toward land, down the mask distance's slope; zero where it is
// flat or there is no grid.
vec2 shoreward_at(vec2 world_xz) {
	if (!landmass_distance_ready) {
		return vec2(0.0);
	}
	float e = max(landmass_distance_cell, 0.01);
	vec2 g = vec2(
		mask_shore_distance_at(world_xz + vec2(e, 0.0)) - mask_shore_distance_at(world_xz - vec2(e, 0.0)),
		mask_shore_distance_at(world_xz + vec2(0.0, e)) - mask_shore_distance_at(world_xz - vec2(0.0, e)));
	return length(g) > 0.00001 ? -normalize(g) : vec2(0.0);
}

// The mask's uvs at this XZ: line_uv for the waterline's foam - carried
// in and back, never reshuffled, so it can't pop - and surf_uv for the
// swash and run-up - carried the same, plus a fresh tile offset each
// cycle, swapped while dissolve is 1. The cycle is swash_cycle_
// amplitude()'s, phase offset included. All still at foam_travel_m 0.
void foam_mask_motion(vec2 world_xz, float phase, float time, out vec2 line_uv, out vec2 surf_uv, out float dissolve) {
	float scale = max(foam_mask_scale_m, 0.01);
	vec2 carried = shoreward_at(world_xz) * foam_travel(phase) * foam_travel_m;
	line_uv = (world_xz - carried) / scale;
	surf_uv = line_uv;
	dissolve = 0.0;
	if (foam_travel_m > 0.0) {
		float offset = (texture(surface_noise, world_xz / max(swash_phase_noise_scale, 0.001)).r - 0.5) * swash_phase_spread;
		float cycle = floor(time / max(swash_period, 0.001) + offset);
		surf_uv += vec2(lace_hash(vec2(cycle, 3.0)), lace_hash(vec2(cycle, 11.0)));
		dissolve = foam_dissolve(phase);
	}
}

// The surf's mask value dissolved: holes widen and strands thin as
// dissolve rises (the faint parts go first), none left at 1.
float foam_surf_mask(float value, float dissolve) {
	return clamp((value - dissolve) / max(1.0 - dissolve, 0.001), 0.0, 1.0);
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

	// Pool clarity (see pool_clarity_enabled's doc): scaled by the
	// enclosure, so the open sea is untouched and nothing draws an edge
	// where a pool meets it.
	float pool_clear = pool_clarity_enabled ? landmass_enclosure_at(v_world_xz) : 0.0;
	edge_alpha = mix(edge_alpha, smoothstep(0.0, max(pool_edge_depth_m, 0.001), water_depth), pool_clear);
	water_rgb = mix(water_rgb, pool_tint_color.rgb, pool_clear);
	depth_alpha = mix(depth_alpha, mix(pool_tint, 1.0, depth_t), pool_clear);

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

	// Distance fog amount (see fog_color's own doc) - applied at the very
	// end of the composite below, not here.
	float fog_t = smoothstep(fog_near_distance, fog_far_distance, length(VERTEX)) * fog_strength;

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

	// Open-water crests (see crests_enabled's doc): off over pools, and
	// crest_calm quiets the surface pattern between them.
	float crest_zone;
	float crest = open_crest_at(v_world_xz, sea_time, crest_zone) * (1.0 - landmass_enclosure_at(v_world_xz));
	float crest_amount = crest * crest_strength * edge_alpha;
	pattern_amount *= 1.0 - crest_calm * crest_zone * (1.0 - crest);

	// The pool's surface (see pool_sheen's doc): the sheen joins the
	// surface pattern (both toward the sky colour), the glints go on top.
	float pool_surface = edge_alpha * pool_clear;
	float pool_sheen_amount = pool_sheen * pool_surface * smoothstep(-0.6, 0.8, ripple);
	pattern_amount = 1.0 - (1.0 - pattern_amount) * (1.0 - pool_sheen_amount);
	vec2 glint_p = v_world_xz / max(pool_glint_scale_m, 0.01);
	float glint_a = surface_noise_rotated(glint_p, 0.37, vec2(0.6, 0.2) * pool_glint_speed * sea_time);
	float glint_b = surface_noise_rotated(glint_p * 1.37, 1.91, vec2(-0.3, 0.5) * pool_glint_speed * sea_time);
	float glint_ridge = 1.0 - abs(glint_a * 2.0 - 1.0);
	float pool_glint_amount = pool_glint_strength * pool_surface * smoothstep(1.0 - max(pool_glint_width, 0.001), 1.0, glint_ridge) * smoothstep(0.45, 0.75, glint_b);

	// Foam: a band foam_width of water depth wide right at the true
	// waterline, patchy via value noise, breathing with the long wave's
	// own height at this point (not a generic timer). Computed here,
	// composited below as opaque paint over both the surface and the
	// seabed terms - see foam_color's own doc for why it can't live in
	// the surface colour.
	vec2 breathe_slope;
	float long_h = wave_height_and_slope(v_world_xz, sea_time, normalize(long_wave_direction), long_wave_length, long_wave_amplitude, long_wave_speed, breathe_slope);
	float breathe = 0.5 + 0.5 * (long_h / max(long_wave_amplitude, 0.0001));
	// Still water has no foam line and no swash - both are the sea's edge,
	// and a pool has no sea in it. Scaled rather than branched so the
	// transition across a pool's own boundary can't draw an edge of its
	// own.
	float sea_open = 1.0 - landmass_enclosure_at(v_world_xz);

	float foam_noise = value_noise(v_world_xz / max(edge_noise_scale, 0.001));
	float foam_edge = smoothstep(0.0, 0.05, water_depth) * (1.0 - smoothstep(0.05, max(foam_width, 0.06), water_depth));
	// The foam mask (see foam_mask_enabled's doc), else the procedural
	// lace (see foam_breakup's doc), else the old patchiness. Sampled
	// outside the branch so its mip selection keeps its derivatives.
	float foam_patch = mix(0.6, 1.0, foam_noise);
	float swash_patch = 1.0;
	float swash_ph = swash_phase(v_world_xz, sea_time);
	vec2 foam_line_uv;
	vec2 foam_surf_uv;
	float foam_surf_dissolve;
	foam_mask_motion(v_world_xz, swash_ph, sea_time, foam_line_uv, foam_surf_uv, foam_surf_dissolve);
	float foam_mask_value = clamp(texture(foam_mask, foam_line_uv).r * foam_mask_strength, 0.0, 1.0);
	float foam_surf_value = foam_surf_mask(texture(foam_mask, foam_surf_uv).r * foam_mask_strength, foam_surf_dissolve);
	if (foam_mask_enabled) {
		foam_patch = foam_mask_value;
		swash_patch = mix(1.0, foam_surf_value, swash_breakup);
	} else if (foam_breakup > 0.0) {
		vec2 lace_p = v_world_xz / max(foam_breakup_scale, 0.001) + normalize(long_wave_direction) * foam_drift_speed * sea_time;
		float lace = lace_noise(lace_p) * 0.6 + lace_noise(lace_p * 2.7 + vec2(13.1, -7.3)) * 0.4;
		float lace_soft = max(foam_breakup_softness, 0.001);
		foam_patch = smoothstep(foam_breakup - lace_soft, foam_breakup + lace_soft, lace);
		swash_patch = mix(1.0, smoothstep(foam_breakup - 0.15 - lace_soft, foam_breakup - 0.15 + lace_soft, lace), swash_breakup);
	}
	float foam_amount = foam_edge * foam_patch * mix(0.7, 1.0, breathe) * foam_strength * sea_open;

	// Swash (see swash_color's own doc): the front's leading edge is the
	// shoreward (shallower) side of the cycle's centre depth, crisp over
	// swash_edge_width; the trailing edge fades over swash_band_width
	// toward deeper water. No patch noise - the cycle amplitude and the
	// phase offset already vary it along the shore. Gated off dry sand by
	// depth like the foam; composited below as its own overlay above the
	// foam line. swash_ph is computed above, with the foam mask's motion.
	float swash_centre;
	float swash_intensity;
	swash_centre_and_intensity(swash_ph, swash_centre, swash_intensity);
	float swash_lead = smoothstep(swash_centre - max(swash_edge_width, 0.001), swash_centre, water_depth);
	float swash_trail = 1.0 - smoothstep(swash_centre, swash_centre + max(swash_band_width, 0.001), water_depth);
	float swash_amount = swash_lead * swash_trail * swash_intensity * swash_cycle_amplitude(v_world_xz, sea_time) * swash_strength * smoothstep(0.0, 0.03, water_depth) * sea_open * swash_patch;

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
	vec3 transmittance = exp(-water_depth * max(absorption, vec3(0.0)) * mix(1.0, pool_absorption_scale, pool_clear));
	behind *= transmittance;
	vec3 pool_filter_color = pool_tint_color.rgb / max(max(pool_tint_color.r, max(pool_tint_color.g, pool_tint_color.b)), 0.001);
	behind *= mix(vec3(1.0), pool_filter_color, pool_filter * edge_alpha * pool_clear);

	// Overlays paint over the whole mix, in order: the surface pattern
	// (toward the sky colour), the open-water crests, the foam line, then
	// the swash front on top.
	// Each replaces its amount of both the lit surface term and the see-
	// through term, so all read at full strength even where the water
	// itself is nearly transparent.
	vec3 surface = mix(albedo * water_amount, sky_reflect_color.rgb, pattern_amount);
	surface = mix(surface, crest_color.rgb, crest_amount);
	surface = mix(surface, pool_glint_color.rgb, pool_glint_amount);
	surface = mix(surface, foam_color.rgb, foam_amount);
	surface = mix(surface, swash_color.rgb, swash_amount);
	float overlay_amount = 1.0 - (1.0 - pattern_amount) * (1.0 - crest_amount) * (1.0 - pool_glint_amount) * (1.0 - foam_amount) * (1.0 - swash_amount);
	// Fog last, over everything, the way the environment fogs the opaque
	// pass: the lit term and the specular scale down by (1 - fog_t), the
	// unlit EMISSION carries the flat fog colour in. (The see-through
	// sample already holds the environment's own fog for the seabed, so
	// that share is fogged twice - it's the transparent fraction of water
	// past 14m, i.e. next to nothing.)
	ALBEDO = surface * (1.0 - fog_t);
	EMISSION = behind * (1.0 - water_amount) * (1.0 - overlay_amount) * (1.0 - fog_t) + fog_color.rgb * fog_t;
	ROUGHNESS = sea_roughness;
	SPECULAR = sea_specular * water_amount * (1.0 - fog_t);
	METALLIC = 0.0;
	ALPHA = 1.0;
}
