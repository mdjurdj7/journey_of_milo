shader_type spatial;
// depth_draw_opaque forces this into the opaque depth/lighting/shadow pass
// regardless of blend mode - without it (and without ever writing ALPHA -
// fragment() below never does), the ground rendered unlit and didn't
// receive shadows: spatial's default blend mode is blend_mix, and an
// unwritten ALPHA under that mode doesn't reliably resolve to opaque in
// practice. Same fix, same root cause, as wanderer_flat.gdshader's own
// "invisible Wanderer" bug - never reintroduce blend_mix here.
// Diffuse only: fragment() pins ROUGHNESS to 1.0 and SPECULAR to 0.0
// everywhere (dry, wet, pools). The wet band and pools used to drop to a
// glossy roughness/specular, which under the field's 45-degree light and
// camera read as white hotspots across the sand - the wet look now comes
// from albedo alone (wet_darken below). specular_schlick_ggx stays in
// render_mode only because it's the pipeline default; at SPECULAR 0 it
// contributes nothing.
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

// Near/far albedo tint, MULTIPLIED into the sand colour before the wetness
// blend. Neutral (white) at both ends by default so dry_color renders as
// authored - the WorldEnvironment's own fog/aerial perspective already
// handles distance lightening. Kept as a knob (e.g. a faint far tint)
// rather than removed.
uniform vec4 near_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 far_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float near_distance = 20.0;
uniform float far_distance = 120.0;

// Sand colour: high-key pale with a slight warm bias (R - B ~ +0.14) - a
// pale flat, not tan. Wet sand is the SAME colour darkened by wet_darken
// (multiplicative, so hue is preserved), never a separate colour: the
// shore band, the noise wet patches, and everything under the sea plane
// are all just darker sand.
uniform vec4 dry_color : source_color = vec4(0.74, 0.70, 0.60, 1.0);
uniform float wet_darken : hint_range(0.0, 1.0) = 0.72;
uniform float wetness_scale = 30.0;
uniform float wetness_amount : hint_range(0.0, 1.0) = 0.5;
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
// ground.gd. Albedo only now - no gloss (see render_mode's own doc).
uniform float pool_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float pool_edge_width : hint_range(0.0, 1.0) = 0.15;
uniform vec4 pool_color : source_color = vec4(0.696, 0.704, 0.68, 1.0);

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

// Wet band: within shore_slope_start metres of HEIGHT above sea_level,
// sand wetness is pushed to 1.0 so it darkens by wet_darken like damp
// sand right at the shore — not toward pool_color, which stays driven by
// the plain noise mask so isolated standing pools don't turn into a strip
// along the whole shoreline. Height-based (v_world_height vs. sea_level
// below), not a straight line - this follows the shoreline contour for
// free, since v_world_height already IS that shape (baked into the mesh
// by ground.gd's _relief_height()). Small on purpose: it's metres of
// HEIGHT, and the dry interior sits only ~0.5m above sea_level, so
// anything near that value makes the whole landmass read as wet (the old
// 8.0 did exactly that). 0.15 is a narrow strip at the waterline (~0.4m
// laterally at the mask ramp's slope). Below sea_level shore_t() is
// simply 1.0 - the darker sand continues down under the water, no
// separate colour. sea_level is pushed from ground.gd (from Sea's own
// sea_level), not assumed.
uniform float shore_slope_start = 0.15;
uniform float sea_level = 0.0;

// Swash surge on the wet band: as each wash reaches the waterline (see
// sea.gdshader's swash), shore_slope_start widens by up to
// wet_band_surge metres of height (x the cycle's own amplitude), then
// relaxes back over wet_dry_time seconds after the water recedes, so the
// sand stays visibly wet a moment after the wash pulls back. Stateless -
// a pure function of the shared phase, so it needs no history and can't
// drift. The phase inputs below (sea_time, swash_period, swash_phase_
// noise_scale, surface_noise) are all pushed by sea.gd - Sea owns the
// wrapped time and the noise tile; Ground reads the same objects so the
// phase computed here is the phase the sea's wash uses at this XZ.
uniform float wet_band_surge = 0.25;
uniform float wet_dry_time = 2.0;
uniform float sea_time = 0.0;
uniform float swash_period = 7.0;
uniform float swash_phase_noise_scale = 24.0;
uniform float swash_phase_spread : hint_range(0.0, 1.0) = 0.15;
uniform sampler2D surface_noise : filter_linear_mipmap, repeat_enable;
// The surge's shore gate: Ground's signed landmass distance (negative on
// sand, positive in water, 0 on the drawn line) as an R32F texture over
// the mask's padded distance grid - pushed once per mask rebuild by
// ground.gd's _push_mask_distance_texture(), one texel per grid cell.
// Everything swash-related on the ground is keyed to this distance, so
// none of it can reach the interior's own relief dips (5m+ inside the
// line) the way a height-only band did. landmass_distance_ready is false
// in SDF mode (no grid) - the run-up, its sheet and the surge are simply
// off there.
uniform sampler2D landmass_distance_tex : filter_linear, repeat_disable;
uniform vec2 landmass_distance_origin = vec2(0.0);
uniform float landmass_distance_cell = 0.25;
uniform vec2 landmass_distance_dims = vec2(1.0);
uniform bool landmass_distance_ready = false;

// Run-up: the ground draws the wash's continuation up the sand, since
// the sea plane is depth-tested away there. Each cycle the sheet slides
// from the drawn line to swash_runup_distance x the cycle's amplitude
// (swash_runup_envelope(): the sea's own centre-depth curve mirrored, so
// the two fronts move in step and meet at the line at the hold), then
// drains back. The sheet is a translucent film toward swash_sheet_color
// (darker/cooler than dry sand) at swash_sheet_alpha, with a bright
// leading edge swash_edge_width_ground wide toward swash_color (the
// sea's front colour). Behind it the sand stays wet as far as the sheet
// reached this cycle (swash_wet_footprint()), drying over wet_dry_time -
// that's the "how far it got" mark; wet_band_surge on top of that still
// breathes the height band right at the line.
uniform float swash_runup_distance = 1.2;
uniform vec4 swash_sheet_color : source_color = vec4(0.60, 0.66, 0.66, 1.0);
uniform float swash_sheet_alpha : hint_range(0.0, 1.0) = 0.45;
uniform float swash_edge_width_ground = 0.08;
uniform vec4 swash_color : source_color = vec4(0.82, 0.84, 0.82, 1.0);

// Caustics: a scrolling bright web on the sand BELOW sea_level, so the
// seabed reads as lit through moving water. Two Worley (cellular) layers
// at caustic_scale and 0.6x that, drifting in different directions at
// caustic_speed; each layer's cell BORDERS (F2 - F1 -> 0, sharpened by
// caustic_sharpness) are the bright lines, and the two are screen-
// blended so both webs show at full brightness where they cross. Value
// multiplier on the sand (1 + web * caustic_strength), hue preserved,
// fading to nothing over caustic_fade_depth metres below sea_level.
// Scrolls on the engine's TIME (no sea_time push here) - keeps moving
// through the battle freeze, same as the sea surface does.
uniform float caustic_strength : hint_range(0.0, 2.0) = 0.25;
uniform float caustic_scale = 0.6;
uniform float caustic_speed = 0.08;
uniform float caustic_fade_depth = 3.0;
uniform float caustic_sharpness = 4.0;
// Drift lines and ripple marks run at this multiple of their dry
// strength under sea_level, so the seabed keeps some structure through
// the water. Both are darken-only (see fragment()), so boosting them can
// never lift the sand above the wet base colour.
uniform float underwater_detail_boost = 1.5;

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

// The sea's cycle shape (sea.gdshader's SWASH_ADVANCE_END / _HOLD_END /
// _RECEDE_END): the wash reaches the line at 0.4, sits there to 0.6,
// is gone by 0.8. The sheet's own climb window sits inside the sea's
// hold: it starts climbing the sand the moment the front reaches the
// line (0.40), is fully up by SWASH_CLIMB_END (0.52), holds to 0.60,
// then drains back over the recede in step with the front. Edit these
// together with sea.gdshader's, or the front and the sheet stop meeting
// at the line at 0.40.
const float SWASH_ADVANCE_END = 0.4;
const float SWASH_CLIMB_END = 0.52;
const float SWASH_HOLD_END = 0.6;
const float SWASH_RECEDE_END = 0.8;

// 0..1: how far up the sand the sheet is right now, as a fraction of
// this cycle's full run-up. 0 until the sea front reaches the line
// (0.40), linear 0 -> 1 over the climb (0.40-0.52), 1 through the rest
// of the sea's hold (to 0.60), linear 1 -> 0 over the recede (0.60-
// 0.80), 0 through the rest.
float swash_runup_envelope(float phase) {
	if (phase < SWASH_ADVANCE_END) {
		return 0.0;
	}
	if (phase < SWASH_CLIMB_END) {
		return (phase - SWASH_ADVANCE_END) / (SWASH_CLIMB_END - SWASH_ADVANCE_END);
	}
	if (phase < SWASH_HOLD_END) {
		return 1.0;
	}
	if (phase < SWASH_RECEDE_END) {
		return 1.0 - (phase - SWASH_HOLD_END) / (SWASH_RECEDE_END - SWASH_HOLD_END);
	}
	return 0.0;
}

// 0..1: the furthest the sheet has reached so far this cycle, as a
// fraction of the full run-up - 0 before the climb, the run-up envelope
// during it, then 1 for the rest of the cycle. The wet footprint's
// inland extent.
float swash_reached_envelope(float phase) {
	if (phase < SWASH_ADVANCE_END) {
		return 0.0;
	}
	if (phase < SWASH_CLIMB_END) {
		return (phase - SWASH_ADVANCE_END) / (SWASH_CLIMB_END - SWASH_ADVANCE_END);
	}
	return 1.0;
}

// 0..1: how wet the swash has left the sand at a phase - 1 while the
// water is on it (through the hold), then exp(-t / wet_dry_time) from
// the moment it starts receding, forced to 0 over the last tenth of the
// cycle so a slow dry time can't leave a step at the phase wrap.
float swash_wet_decay(float phase) {
	float since_recede = max(phase - SWASH_HOLD_END, 0.0) * max(swash_period, 0.001);
	float decay = exp(-since_recede / max(wet_dry_time, 0.001));
	float wrap_guard = 1.0 - smoothstep(0.9, 1.0, phase);
	return decay * wrap_guard;
}

// The height-band surge's envelope: rises over the last tenth of the
// advance (the water arriving at the line), then the wet decay above.
float swash_wet_envelope(float phase) {
	return smoothstep(SWASH_ADVANCE_END - 0.1, SWASH_ADVANCE_END, phase) * swash_wet_decay(phase);
}

// Bilinear sample of the pushed distance grid, matching ground.gd's own
// _mask_distance_sample(): grid node i sits at origin + i * cell, texel
// i's centre at (i + 0.5) / dims, and repeat_disable clamps to the edge
// texel exactly as the CPU sampler clamps its index.
float landmass_distance_at(vec2 world_xz) {
	vec2 uv = ((world_xz - landmass_distance_origin) / max(landmass_distance_cell, 0.001) + 0.5) / max(landmass_distance_dims, vec2(1.0));
	return texture(landmass_distance_tex, uv).r;
}

// 0 deep inside the sand, 1 within half this cycle's full run-up of the
// drawn line (and on the water side), fading between - keeps the
// height-band surge tied to how far the wash actually gets.
float swash_shore_gate(float distance, float runup_max) {
	float reach = max(runup_max, 0.001);
	return smoothstep(-reach, -reach * 0.5, distance);
}

// The wet band's height threshold at this XZ right now: shore_slope_
// start plus the swash surge (wet_band_surge x this cycle's amplitude x
// the envelope above x the shore gate). distance/runup_max come from
// fragment(), which already has them.
float shore_band_height(float distance, float runup_max, float phase, float amplitude) {
	float surge = landmass_distance_ready ? wet_band_surge * amplitude * swash_wet_envelope(phase) * swash_shore_gate(distance, runup_max) : 0.0;
	return max(shore_slope_start + surge, 0.001);
}

float shore_t(float world_height, float band_height) {
	if (!shore_wetness_enabled) {
		return 0.0;
	}
	return 1.0 - smoothstep(0.0, band_height, dist_from_shore(world_height));
}

// The sheet's own wet footprint: 1 from the line up to as far as the
// sheet has reached this cycle (a 5cm edge so the mark has a visible
// limit), decaying by swash_wet_decay() once the water pulls back. Cut
// at the line (distance 0) - beyond it the sand is under water anyway.
float swash_wet_footprint(float distance, float reached, float phase) {
	float inland = smoothstep(-reached - 0.05, -reached, distance);
	float seaward = 1.0 - smoothstep(0.0, 0.05, distance);
	return inland * seaward * swash_wet_decay(phase);
}

// Wetness used for sand shading: the plain noise mask, boosted to 1 right
// at the shore. Kept separate from the noise mask alone (used for pools)
// so the shore band reads as wet sand rather than a strip of standing pool.
float sand_wetness_mask(vec2 world_xz, float world_height, float band_height) {
	return max(wetness_mask(world_xz), shore_t(world_height, band_height));
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

// Worley/cellular noise: one jittered feature point per unit cell (from
// the same hash() the value noise uses), 3x3 neighbourhood search. Returns
// (F1, F2) - distance to the nearest and second-nearest point - so the
// caller can read cell borders as F2 - F1 -> 0.
vec2 worley_f1_f2(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 neighbour = vec2(float(x), float(y));
			vec2 point = vec2(hash(cell + neighbour), hash(cell + neighbour + vec2(17.3, 41.9)));
			vec2 delta = neighbour + point - local;
			float d = dot(delta, delta);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return sqrt(vec2(f1, f2));
}

// One caustic layer: bright on the cell borders, dark inside the cells.
// F2 - F1 is 0 exactly on a border and grows toward the cell centre; the
// /0.5 puts a typical cell interior at ~1, and the pow sharpens the
// remaining band into a thin line.
float caustic_layer(vec2 p) {
	vec2 f = worley_f1_f2(p);
	float edge = clamp((f.y - f.x) / 0.5, 0.0, 1.0);
	return pow(1.0 - edge, max(caustic_sharpness, 0.001));
}

// Two layers at different scales, drifting in different directions,
// screen-blended (1 - (1-a)(1-b)) so both webs read at full brightness
// where they overlap and neither dims the other elsewhere.
float caustic_web(vec2 world_xz, float time) {
	float scale = max(caustic_scale, 0.001);
	vec2 drift_a = vec2(1.0, 0.35) * caustic_speed * time;
	vec2 drift_b = vec2(-0.45, 1.0) * caustic_speed * time;
	float a = caustic_layer(world_xz / scale + drift_a);
	float b = caustic_layer(world_xz / (scale * 0.6) + drift_b);
	return 1.0 - (1.0 - a) * (1.0 - b);
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
	// Swash state at this XZ, computed once: shared phase/amplitude (see
	// the shared block), this cycle's full run-up, where the sheet is
	// now, how far it has reached, and the signed shore distance. All
	// zero/inert without the distance grid (SDF mode).
	float swash_ph = swash_phase(v_world_xz, sea_time);
	float swash_amp = swash_cycle_amplitude(v_world_xz, sea_time);
	float runup_max = max(swash_runup_distance, 0.0) * swash_amp;
	float runup = runup_max * swash_runup_envelope(swash_ph);
	float reached = runup_max * swash_reached_envelope(swash_ph);
	float shore_distance = landmass_distance_ready ? landmass_distance_at(v_world_xz) : -1000.0;

	float base_wetness = wetness_mask(v_world_xz);
	float band_height = shore_band_height(shore_distance, runup_max, swash_ph, swash_amp);
	float sand_wetness = sand_wetness_mask(v_world_xz, v_world_height, band_height);
	// The run-up's own wet mark, on top of the height band: as far as the
	// sheet reached this cycle, drying back over wet_dry_time.
	if (landmass_distance_ready) {
		sand_wetness = max(sand_wetness, swash_wet_footprint(shore_distance, reached, swash_ph));
	}

	// VERTEX in fragment() is view-space; its length is distance from the camera.
	float dist = length(VERTEX);
	float near_far_t = smoothstep(near_distance, far_distance, dist);
	vec3 distance_tint = mix(near_color.rgb, far_color.rgb, near_far_t);

	// Wet sand is dry sand darkened, hue preserved (see wet_darken's doc).
	vec3 dry = dry_color.rgb * distance_tint;
	vec3 wet = dry * wet_darken;

	vec3 sand_albedo = mix(dry, wet, sand_wetness);

	// Sand grain + speckle: both multiplicative and applied identically
	// across R/G/B, so they shift ALBEDO's value only, never its hue.
	// Suppressed on wet sand - wet sand reads smoother/packed, not
	// grainy - by the same sand_wetness driving the dry/wet blend above.
	float grain_suppression = 1.0 - sand_wetness;
	float grain = grain_value(v_world_xz) * grain_strength * grain_suppression;
	sand_albedo *= 1.0 + grain;

	float speckle = speckle_mask(v_world_xz) * speckle_darken * grain_suppression;
	sand_albedo *= 1.0 - speckle;

	// Under sea_level the drift/ripple detail runs at underwater_detail_
	// boost x strength (see its own doc) - a short 5cm blend rather than a
	// hard step so the boost doesn't draw its own line at the waterline.
	float depth_below_sea = sea_level - v_world_height;
	float underwater = smoothstep(0.0, 0.05, depth_below_sea);
	float detail_boost = mix(1.0, underwater_detail_boost, underwater);

	// Drift lines: nudge the sand toward a slightly darker, slightly
	// warmer tone, at most drift_line_strength (boosted under water) of
	// the way there. Darken-only: the target is clamped per channel to
	// never exceed the sand it's blending from, so a drift_line_color
	// channel that happens to sit above the (wet, darkened) sand can't
	// lighten it - the hue nudge survives, the value can only go down.
	float drift = drift_line_mask(v_world_xz, v_world_height);
	vec3 drift_target = min(drift_line_color.rgb, sand_albedo);
	sand_albedo = mix(sand_albedo, drift_target, clamp(drift * drift_line_strength * detail_boost, 0.0, 1.0));

	// Ripple marks: a brightness shift in wet sand only - darken-only
	// (the signed noise is remapped to [0, 1] and subtracted), so ripples
	// can never lift wet sand back toward the dry value. Multiplicative,
	// same hue-preserving reasoning as grain/speckle above. Boosted under
	// water like the drift lines.
	float ripple = (0.5 + 0.5 * ripple_mask(v_world_xz, v_world_height)) * ripple_strength * detail_boost * sand_wetness;
	sand_albedo *= 1.0 - clamp(ripple, 0.0, 1.0);

	// Caustics: the one thing allowed to BRIGHTEN wet sand, and only under
	// sea_level - full strength just below the waterline (the 3cm ramp
	// keeps it from cutting a hard edge exactly there), gone by
	// caustic_fade_depth. Multiplicative, hue preserved.
	float caustic_fade = smoothstep(0.0, 0.03, depth_below_sea) * (1.0 - smoothstep(0.0, max(caustic_fade_depth, 0.001), depth_below_sea));
	sand_albedo *= 1.0 + caustic_web(v_world_xz, TIME) * caustic_strength * caustic_fade;

	// Run-up sheet (see swash_runup_distance's own doc): the thin film
	// between the drawn line and the sheet's current reach, cut at the
	// line (the sea draws from there), with its bright leading edge on
	// the inland end. Last, over everything on the sand - it's water on
	// top of it. Extent goes to 0 with the envelope, so nothing pops.
	if (landmass_distance_ready) {
		// x smoothstep(runup) so the two edges' overlap can't leave a
		// hairline at the line while the sheet is (nearly) drained.
		float sheet = smoothstep(-runup - 0.02, -runup, shore_distance) * (1.0 - smoothstep(-0.02, 0.0, shore_distance)) * smoothstep(0.0, 0.05, runup);
		float sheet_edge = sheet * (1.0 - smoothstep(0.0, max(swash_edge_width_ground, 0.001), shore_distance + runup));
		sand_albedo = mix(sand_albedo, swash_sheet_color.rgb, sheet * swash_sheet_alpha);
		sand_albedo = mix(sand_albedo, swash_color.rgb, sheet_edge);
	}

	// Pools are the wettest extreme of the plain noise mask (not the
	// shore-boosted one), blended in as a distinct final layer so they
	// keep reading as pale reflected sky regardless of the near/far tint
	// applied to the sand beneath them, and so the shore band reads as
	// wet sand rather than a strip of standing pool.
	float pool_factor = smoothstep(pool_threshold - pool_edge_width * 0.5, pool_threshold + pool_edge_width * 0.5, base_wetness);

	ALBEDO = mix(sand_albedo, pool_color.rgb, pool_factor);
	// Diffuse only, everywhere - see render_mode's own doc.
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
