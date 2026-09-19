shader_type spatial;
render_mode cull_disabled;

// The Keeper's material (see field/keeper.gd): her albedo texture times a
// tint, flat matte, plus a slow wind on the cloak hem and on her hair.
//
// This exists as a ShaderMaterial rather than the StandardMaterial3D it
// replaces for one reason: StandardMaterial3D has no vertex stage, and
// the hem needs one. Everything else here is a faithful re-expression of
// what that material already did - albedo_texture x albedo_color,
// roughness 1, specular 0, metallic 0, culling off (the glb's own
// material declares doubleSided: true; see Keeper._build_material()).
// Keep the two in step: the fallback path in keeper.gd still builds a
// StandardMaterial3D when the shader or texture won't load, and it is
// meant to look the same minus the motion.
//
// TWO masks, hem and hair, each with its own band and amplitude.
//
// The hair mask took three passes to get right, so the measurements are
// recorded here rather than rediscovered. A luminance-only mask does NOT
// work: luma < 0.35 alone takes 30% of the mesh, 81% of her FOOT
// vertices, and only 8.8% of her crown - it separates dark cloth from
// pale cloth at every height, not hair from anything. A radius-only test
// doesn't work either: it picks up the same band the pale robe occupies.
// The THREE conditions together do work - local y in [hair_y_min, hair_
// y_max], radius from the head's vertical axis past hair_radial_min, and
// albedo luma under hair_luma_threshold - selecting 377 of 6198 vertices,
// y 1.102..1.463, radius 0.140..0.386, 354 of them inside a single 90 deg
// sector. That set is hair and not a sleeve, confirmed two ways: its
// normals span 8 of 12 sectors about its own long axis (an open shell; a
// limb is a closed tube and fills all 12), and a flood-fill through dark
// vertices alone climbs to y 1.602 - the scalp - while never descending
// below y 1.102 into the torso, which a sleeve would.
//
// Beware the radius reference: measured about the HEAD's own axis (see
// head_axis_xz), not the model origin or the whole-mesh centroid. Against
// the centroid the hair reads as part of a "smoothly narrowing dome" and
// disappears entirely, because it lies inside the dome radius at the
// crown and only flares lower down.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// The hem BAND, in local metres above her feet. The glb's origin is at
// her feet (measured: bbox min y exactly 0.0, max 1.650), and the model
// node carries yaw only, so VERTEX.y IS metres above the ground here -
// no offset, no scale to undo.
//
// Weight is 0 at or below boot_top, smoothsteps up to 1 at hem_height,
// then smoothsteps back down to 0 at waist_height. A band rather than
// the falling ramp this started as: the ramp put its MAXIMUM travel at
// y=0, which is exactly where her boots meet the sand, so the one part
// that must look planted was the part that moved most. Now the boots are
// pinned, the skirt at hem_height carries the full throw, and the cloak
// is still by the waist.
uniform float boot_top = 0.18;
uniform float hem_height = 0.45;
uniform float waist_height = 0.95;
// Metres of displacement at full weight and a full gust.
uniform float wind_amplitude = 0.08;
// Cycles per second through the gust noise below - slow.
uniform float wind_speed = 0.4;
// WORLD space, pushed by keeper.gd (normally the direction she faces, so
// the wind runs out toward the water; see its _apply_wind()). Converted
// to model space per vertex rather than pre-baked, so a live face_
// direction edit re-aims the wind with nothing to re-push.
uniform vec3 wind_direction_world = vec3(0.0, 0.0, -1.0);
// How much the gust's phase varies ACROSS the hem, so the skirt ripples
// instead of sliding as one rigid piece. 0 moves the whole hem together.
uniform float wind_phase_scale = 0.6;

// --- Hair ---
// The selection, measured against this asset (see the header). All three
// conditions have to hold; each alone selects the wrong thing.
uniform float hair_y_min = 1.05;
uniform float hair_y_max = 1.55;
// Radius from head_axis_xz. The hood dome sits inside ~0.12; the hair
// runs 0.14 out to 0.386 at the tips.
uniform float hair_radial_min = 0.14;
uniform float hair_radial_tip = 0.38;
// Compared against sRGB luma, the space the 0.35 figure was measured in -
// NOT the linear value texture() returns. See hair_weight() for the
// conversion and why it matters.
uniform float hair_luma_threshold = 0.35;
// The head's own vertical axis in model space (x, z) - the XZ centroid of
// the vertices above y 1.40. Measured -0.031, 0.128; it is NOT the model
// origin, and using the origin instead loses the mask entirely.
uniform vec2 head_axis_xz = vec2(-0.031, 0.128);
uniform float hair_amplitude = 0.06;
// Multiplies the gust's rate for the hair only - lighter than wet wool,
// so it moves quicker than the hem off the same noise.
uniform float hair_gust_scale = 1.4;

float hash11(float n) {
	return fract(sin(n) * 43758.5453123);
}

// Value noise on one axis - the same smoothstep-interpolated shape
// ground.gdshader's own _value_noise() uses, one dimension instead of two.
float vnoise1(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash11(i), hash11(i + 1.0), f);
}

// Two octaves, signed, spanning -1..1: a slow swell with a faster, weaker
// flutter on top. The second octave's rate is deliberately irrational-ish
// (2.17) so the two never line up into an obvious repeat.
float gust(float t) {
	float slow = (vnoise1(t) - 0.5) * 2.0;
	float fast = (vnoise1(t * 2.17 + 13.7) - 0.5) * 2.0;
	return slow * 0.667 + fast * 0.333;
}

// 0 below boot_top, 1 at hem_height, 0 again at waist_height. The two
// max()es only keep the three edges strictly ordered - smoothstep is
// undefined when edge0 >= edge1, so a bad export combination would
// otherwise produce garbage rather than simply a narrow band.
float hem_band(float y) {
	float hem = max(hem_height, boot_top + 0.001);
	float waist = max(waist_height, hem + 0.001);
	return smoothstep(boot_top, hem, y) * (1.0 - smoothstep(hem, waist, y));
}

// The hair mask: the three measured conditions, each as a soft edge
// rather than a hard cut so neighbouring vertices don't pop apart.
// Weight runs 0 at the hood end (small radius, high y) to 1 at the tips
// (large radius, low y), which is the shape the spec asks for and also
// the only one that keeps the roots welded to the scalp.
//
// textureLod, not texture: the vertex stage has no derivatives, so a
// plain texture() call won't compile here. And the sample comes back
// LINEAR (albedo_texture is declared source_color, so Godot converts on
// read), while hair_luma_threshold is an sRGB number - the 0.35 that was
// measured off the image. pow(x, 1/2.2) puts them in the same space; skip
// it and 0.35 silently becomes ~0.63 sRGB and the mask swallows the robe.
// uv is passed in rather than read off the UV built-in: built-ins only
// exist inside the stage functions, so referring to UV here doesn't
// compile.
float hair_weight(vec3 v, vec2 uv) {
	float r = length(v.xz - head_axis_xz);
	float band = smoothstep(hair_y_min - 0.06, hair_y_min, v.y)
		* (1.0 - smoothstep(hair_y_max - 0.10, hair_y_max, v.y));
	float radial = smoothstep(hair_radial_min, max(hair_radial_tip, hair_radial_min + 0.001), r);
	vec3 lin = textureLod(albedo_texture, uv, 0.0).rgb;
	float lum = pow(clamp(dot(lin, vec3(0.2126, 0.7152, 0.0722)), 0.0, 1.0), 1.0 / 2.2);
	float dark = 1.0 - smoothstep(hair_luma_threshold - 0.06, hair_luma_threshold, lum);
	return band * radial * dark;
}

void vertex() {
	float hair = hair_weight(VERTEX, UV);
	float weight = hem_band(VERTEX.y);
	if (weight > 0.0 || hair > 0.0) {
		vec3 dir_world = wind_direction_world;
		if (length(dir_world) > 0.0001) {
			// World -> model. MODEL_MATRIX carries her facing yaw and the
			// model node's own yaw offset, so this stays correct however
			// those two are set.
			vec3 dir_model = (inverse(MODEL_MATRIX) * vec4(normalize(dir_world), 0.0)).xyz;
			if (length(dir_model) > 0.0001) {
				vec3 dir = normalize(dir_model);
				// One shared phase so the two masks read as the same wind;
				// the hair just runs through it hair_gust_scale times faster.
				float spread = dot(VERTEX.xz, vec2(1.0, 1.0)) * wind_phase_scale;
				float phase = TIME * wind_speed + spread;
				VERTEX += dir * gust(phase) * wind_amplitude * weight;
				VERTEX += dir * gust(phase * hair_gust_scale) * hair_amplitude * hair;
			}
		}
	}
}

void fragment() {
	// Exactly what the StandardMaterial3D did: the texture times the tint,
	// fully rough, no specular, no metal. ALPHA is deliberately never
	// written - writing it would push her onto the transparent pipeline,
	// and the albedo jpg has no alpha to honour anyway.
	ALBEDO = texture(albedo_texture, UV).rgb * tint.rgb;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
