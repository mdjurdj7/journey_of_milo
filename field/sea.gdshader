shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 sea_color : source_color = vec4(0.74, 0.75, 0.72, 1.0);
uniform float sea_roughness : hint_range(0.0, 1.0) = 0.35;

// Slow, subtle two-octave value-noise normal perturbation, no texture,
// so the plane reads as water rather than glass.
uniform float noise_amplitude = 0.03;
uniform float noise_speed = 0.05;
uniform float noise_scale = 6.0;

varying vec2 v_world_xz;

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
	ALBEDO = sea_color.rgb;
	ROUGHNESS = sea_roughness;
	METALLIC = 0.0;
}
