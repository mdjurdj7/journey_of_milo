shader_type spatial;
// One wisp of blowing sand (FieldWind's streaks and plumes; their motion
// is wind_sand_particles.gdshader's): a soft ribbon size_m long along the
// wind and wide across it, turned about the wind's axis to face the
// camera, grown to grow times its size by the end of its life. Tapered
// at both ends, soft across, broken into strands by noise of its own - no
// sprite, no hard edge.
//
// It only darkens: what is behind it is multiplied toward darken_to (a
// neutral grey) by the particle's alpha, so on sand it reads as the
// sand a touch darker under whatever light and shade fall there, never
// lighter and never warmer. Unshaded, so a fragment costs next to
// nothing - a wisp covers a lot of screen. The scene fog is already in
// what it darkens; it fades out itself from fade_distance.x to .y metres
// from the camera instead. Soft against what stands behind it: it thins
// out over the last soft_depth_m before the depth there, so a ribbon
// crossing a slope fades into it instead of being cut.
render_mode world_vertex_coords, blend_mul, unshaded, fog_disabled, depth_draw_never, cull_disabled;

uniform vec2 size_m = vec2(3.2, 0.4);
uniform float grow = 1.0;
uniform vec2 wind_dir = vec2(0.866, 0.5);
uniform float darken_to = 0.9;
// 0 = a smooth ribbon, 1 = all strands.
uniform float breakup = 0.65;
uniform vec2 fade_distance = vec2(35.0, 60.0);
uniform float soft_depth_m = 0.5;
uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying float v_life;
varying float v_seed;
varying float v_strength;

float wisp_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float wisp_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(wisp_hash(i), wisp_hash(i + vec2(1.0, 0.0)), f.x), mix(wisp_hash(i + vec2(0.0, 1.0)), wisp_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	v_life = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.w;
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - centre;
	float scale = INSTANCE_CUSTOM.x * mix(1.0, grow, v_life);
	vec2 dir = length(wind_dir) > 0.0001 ? normalize(wind_dir) : vec2(1.0, 0.0);
	vec3 axis = vec3(dir.x, 0.0, dir.y);
	vec3 to_camera = CAMERA_POSITION_WORLD - centre;
	float distance_to_camera = length(to_camera);
	vec3 side = cross(axis, to_camera / max(distance_to_camera, 0.0001));
	side = length(side) > 0.0001 ? normalize(side) : vec3(0.0, 1.0, 0.0);
	VERTEX = centre + axis * local.x * size_m.x * scale + side * local.y * size_m.y * scale;
	v_strength = COLOR.a * (1.0 - smoothstep(fade_distance.x, fade_distance.y, distance_to_camera));
}

void fragment() {
	float along = UV.x;
	float across = (UV.y - 0.5) * 2.0;
	float taper = smoothstep(0.0, 0.4, along) * (1.0 - smoothstep(0.45, 1.0, along));
	float soft = exp(-across * across * 2.5) * (1.0 - smoothstep(0.8, 1.0, abs(across)));
	float strands = wisp_noise(vec2(along * 2.0 + v_seed * 37.0, across * 3.0 + v_seed * 11.0));
	strands = mix(1.0, smoothstep(0.2, 0.85, strands), breakup);
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = -behind.z / behind.w + VERTEX.z;
	float near_surface = clamp(gap / max(soft_depth_m, 0.001), 0.0, 1.0);
	float amount = clamp(v_strength * taper * soft * strands * near_surface, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0), vec3(min(darken_to, 1.0)), amount);
}
