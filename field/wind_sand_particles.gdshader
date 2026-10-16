shader_type particles;
// A floor's blowing sand (FieldWind): where each streak or plume is born,
// how it travels and how it fades. The draw pass (wind_sand.gdshader)
// shapes it.
//
// The ground comes in as FieldWind's map: per texel the drawn height (r)
// and whether its sand can lift (g: dry sand, not the wet band, water or
// exposed rock), map_step metres apart from map_origin. A streak is born
// on dry sand within area_half of area_center (where the camera looks),
// rides the ground at its own height above it, and fades out over
// anything that isn't dry. A plume (from_crests) is born at one of
// crest_count crest points within area_half of area_center (crest_points: x, height, z) height_range
// over it, rises at rise metres a second and fades over its life.
//
// Moves at speed downwind, plus gust_speed_gain of it at a full gust -
// gust is pushed every frame, so a gust speeds what is already in the
// air. COLOR.a is how strongly it darkens now. CUSTOM: x its size (0.7..1.3), y its age (0..1 of LIFETIME), z its
// height over the sand, w its own seed (0..1).
render_mode disable_velocity, disable_force;

uniform sampler2D ground_map : filter_linear, repeat_disable;
uniform vec2 map_origin = vec2(0.0);
uniform float map_step = 1.0;
uniform vec2 map_cells = vec2(1.0);
uniform sampler2D crest_points : filter_nearest, repeat_disable;
uniform int crest_count = 0;
uniform bool from_crests = false;
uniform vec2 area_center = vec2(0.0);
uniform float area_half = 15.0;
uniform vec2 wind_dir = vec2(0.866, 0.5);
uniform float speed = 2.0;
uniform float gust = 0.0;
uniform float gust_speed_gain = 1.0;
uniform float rise = 0.0;
uniform vec2 height_range = vec2(0.04, 0.3);
uniform float fade = 0.3;
uniform float peak_alpha = 0.15;

uint wind_hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

float wind_rand(inout uint seed) {
	seed = wind_hash(seed + uint(1013904223));
	return float(seed % uint(65536)) / 65535.0;
}

vec2 map_uv(vec2 xz) {
	return ((xz - map_origin) / map_step + 0.5) / map_cells;
}

vec2 map_at(vec2 xz) {
	vec2 uv = map_uv(xz);
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec2(0.0);
	}
	return texture(ground_map, uv).rg;
}

void start() {
	uint seed = wind_hash(NUMBER + uint(1) + RANDOM_SEED);
	vec3 at = vec3(0.0);
	bool found = false;
	if (from_crests) {
		for (int i = 0; i < 8 && crest_count > 0; i++) {
			int index = min(int(wind_rand(seed) * float(crest_count)), crest_count - 1);
			vec3 crest = texelFetch(crest_points, ivec2(index, 0), 0).xyz;
			vec2 off = abs(crest.xz - area_center);
			if (max(off.x, off.y) <= area_half) {
				at = crest;
				at.xz += (vec2(wind_rand(seed), wind_rand(seed)) - 0.5) * map_step;
				found = true;
				break;
			}
		}
	} else {
		for (int i = 0; i < 6; i++) {
			vec2 xz = area_center + (vec2(wind_rand(seed), wind_rand(seed)) * 2.0 - 1.0) * area_half;
			vec2 here = map_at(xz);
			if (here.g > 0.5) {
				at = vec3(xz.x, here.r, xz.y);
				found = true;
				break;
			}
		}
	}
	ACTIVE = found;
	float size = mix(0.7, 1.3, wind_rand(seed));
	float lift = mix(height_range.x, height_range.y, wind_rand(seed));
	CUSTOM = vec4(size, 0.0, lift, wind_rand(seed));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = at + vec3(0.0, lift, 0.0);
	VELOCITY = vec3(0.0);
	COLOR = vec4(1.0, 1.0, 1.0, 0.0);
}

void process() {
	CUSTOM.y = min(CUSTOM.y + DELTA / max(LIFETIME, 0.001), 1.0);
	vec2 dir = length(wind_dir) > 0.0001 ? normalize(wind_dir) : vec2(1.0, 0.0);
	float now_speed = speed * (1.0 + gust * gust_speed_gain) * mix(0.8, 1.2, CUSTOM.w);
	vec3 at = TRANSFORM[3].xyz;
	at.xz += dir * now_speed * DELTA;
	float alpha = smoothstep(0.0, fade, CUSTOM.y) * (1.0 - smoothstep(1.0 - fade, 1.0, CUSTOM.y));
	if (from_crests) {
		at.y += rise * DELTA;
	} else {
		vec2 here = map_at(at.xz);
		at.y = here.r + CUSTOM.z;
		alpha *= smoothstep(0.3, 0.7, here.g);
	}
	TRANSFORM[3].xyz = at;
	VELOCITY = vec3(dir.x, 0.0, dir.y) * now_speed;
	COLOR = vec4(1.0, 1.0, 1.0, peak_alpha * alpha);
}
