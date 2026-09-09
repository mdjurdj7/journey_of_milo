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
// sand transition instead of a hard edge.
uniform float pool_threshold : hint_range(0.0, 1.0) = 0.75;
uniform float pool_edge_width : hint_range(0.0, 1.0) = 0.15;
uniform vec4 pool_color : source_color = vec4(0.696, 0.704, 0.68, 1.0);
uniform float pool_roughness : hint_range(0.0, 1.0) = 0.35;

// Ground relief. Coupled to wetness: wet ground (and pools most of all)
// sinks, so pools sit in the low spots rather than coincidentally
// overlapping unrelated bumps. Fades to zero between relief_fade_start
// and relief_fade_end (distance from the camera) so the horizon stays
// flat instead of visibly bumpy at range.
uniform float relief_amplitude = 0.15;
uniform float relief_noise_scale = 8.0;
uniform float relief_fade_start = 40.0;
uniform float relief_fade_end = 80.0;

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

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;

	float wetness = wetness_mask(world_pos.xz);
	float bump = (value_noise(world_pos.xz / max(relief_noise_scale, 0.001)) - 0.5) * 2.0;
	float displacement = bump * relief_amplitude - wetness * relief_amplitude;

	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float relief_fade = 1.0 - smoothstep(relief_fade_start, relief_fade_end, cam_dist);
	VERTEX.y += displacement * relief_fade;
}

void fragment() {
	float wetness = wetness_mask(v_world_xz);

	// VERTEX in fragment() is view-space; its length is distance from the camera.
	float dist = length(VERTEX);
	float near_far_t = smoothstep(near_distance, far_distance, dist);
	vec3 distance_tint = mix(near_color.rgb, far_color.rgb, near_far_t);

	vec3 dry = dry_color.rgb * distance_tint;
	vec3 wet = wet_color.rgb * distance_tint;

	vec3 sand_albedo = mix(dry, wet, wetness);
	float sand_roughness = mix(1.0, wet_roughness, wetness);
	float sand_specular = mix(0.0, wet_specular, wetness);

	// Pools are the wettest extreme of the same mask, blended in as a
	// distinct final layer so they keep reading as pale reflected sky
	// regardless of the near/far tint applied to the sand beneath them.
	float pool_factor = smoothstep(pool_threshold - pool_edge_width * 0.5, pool_threshold + pool_edge_width * 0.5, wetness);

	ALBEDO = mix(sand_albedo, pool_color.rgb, pool_factor);
	ROUGHNESS = mix(sand_roughness, pool_roughness, pool_factor);
	SPECULAR = mix(sand_specular, 1.0, pool_factor);
	METALLIC = 0.0;
}
