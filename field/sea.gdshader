shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Surface: soft sheen, not a mirror.
uniform vec4 sea_color : source_color = vec4(0.70, 0.74, 0.75, 1.0);
uniform float sea_roughness : hint_range(0.0, 1.0) = 0.2;

// Slow, subtle two-octave value-noise normal perturbation, no texture,
// so the surface reads as water rather than glass.
uniform float noise_amplitude = 0.03;
uniform float noise_scale = 6.0;
uniform float noise_speed = 0.05;

// Edge: alpha fades to 0 over shore_fade meters of scene-depth
// difference between this surface and whatever's behind it, so the
// water thins into the sand instead of cutting off at the mesh edge.
// edge_noise_amplitude/scale wander that fade distance so the
// waterline isn't a straight, uniform band.
uniform float shore_fade : hint_range(0.01, 20.0) = 3.0;
uniform float edge_noise_amplitude = 1.5;
uniform float edge_noise_scale = 4.0;

// Distance: blend toward fog_color between fog_near_distance and
// fog_far_distance (view-space distance, same smoothstep shape
// ground.gdshader's near/far tint uses) so far water dissolves into
// the horizon instead of holding a hard flat color to the fog line.
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
// doesn't repeat in an obviously periodic way.
float sea_height(vec2 world_xz, float time) {
	vec2 drift_a = vec2(time * noise_speed, time * noise_speed * 0.7);
	vec2 drift_b = vec2(-time * noise_speed * 1.3, time * noise_speed * 0.9);
	float h = value_noise(world_xz / max(noise_scale, 0.001) + drift_a);
	h += value_noise(world_xz / max(noise_scale * 0.35, 0.001) + drift_b) * 0.5;
	return h;
}

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_xz = world_pos.xz;
}

void fragment() {
	// World-space normal from finite-difference slopes of the same height
	// field, then rotated into view space (no non-uniform scale on this
	// mesh, so mat3(VIEW_MATRIX) alone is a valid normal transform).
	float epsilon = 0.5;
	float h_c = sea_height(v_world_xz, TIME);
	float h_x = sea_height(v_world_xz + vec2(epsilon, 0.0), TIME);
	float h_z = sea_height(v_world_xz + vec2(0.0, epsilon), TIME);

	vec3 world_normal = normalize(vec3(
		(h_c - h_x) * noise_amplitude / epsilon,
		1.0,
		(h_c - h_z) * noise_amplitude / epsilon
	));
	NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);

	// Edge fade: how far the opaque scene behind this fragment is from
	// the water surface, in view-space meters. Small near the shore
	// (ground rises to meet the water), large over open water (nothing
	// but far background behind it).
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

	// Distance: dissolve into the fog color toward the horizon.
	float dist = length(VERTEX);
	float fog_t = smoothstep(fog_near_distance, fog_far_distance, dist);
	vec3 albedo = mix(sea_color.rgb, fog_color.rgb, fog_t);

	ALBEDO = albedo;
	ROUGHNESS = sea_roughness;
	METALLIC = 0.0;
	ALPHA = edge_alpha;
}
