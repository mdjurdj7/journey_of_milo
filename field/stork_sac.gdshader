shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled;

// The marabou's throat sac greyed (StorkTells): a next pass over the body's
// own material that lays the body's albedo, desaturated, over the sac and
// nothing else, by grey_amount - 1 while it's Fed, 0 once it's Hungry.
// The sac is the body's red (a hue range, with enough saturation) inside a
// box on the model: the head is the same red, so hue alone can't tell
// them apart, and the atlas scatters both over many islands, so no UV
// rect can either - the box, in the mesh's own bounds (0-1 on each axis),
// is what separates them.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform sampler2D normal_texture : hint_normal, filter_linear_mipmap;
uniform bool use_normal_texture = false;
// The mesh's own bounds, model space - StorkTells sets them.
uniform vec3 bounds_position = vec3(0.0);
uniform vec3 bounds_size = vec3(1.0);
// The sac's box, as fractions of the bounds, and how soft its faces are.
uniform vec3 region_min = vec3(0.0, 0.45, 0.6);
uniform vec3 region_max = vec3(1.0, 0.7, 1.0);
uniform float region_softness = 0.03;
// The red: hue centre and half-width in degrees, and the least saturation
// that counts (the grey-pink skin around it stays as it is).
uniform float hue_center_degrees = 3.0;
uniform float hue_half_width_degrees = 22.0;
uniform float min_saturation = 0.3;
uniform float grey_amount : hint_range(0.0, 1.0) = 1.0;

varying vec3 bounds_fraction;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

float inside_box(vec3 f) {
	vec3 lo = smoothstep(region_min - region_softness, region_min + region_softness, f);
	vec3 hi = 1.0 - smoothstep(region_max - region_softness, region_max + region_softness, f);
	vec3 both = lo * hi;
	return both.x * both.y * both.z;
}

void vertex() {
	bounds_fraction = (VERTEX - bounds_position) / max(bounds_size, vec3(1.0e-6));
}

void fragment() {
	vec3 colour = texture(albedo_texture, UV).rgb;
	vec3 hsv = rgb_to_hsv(colour);
	float hue_off = abs(fract(hsv.x - hue_center_degrees / 360.0 + 0.5) - 0.5) * 360.0;
	float red = 1.0 - smoothstep(hue_half_width_degrees * 0.7, hue_half_width_degrees, hue_off);
	red *= smoothstep(min_saturation * 0.7, min_saturation, hsv.y);
	float mask = red * inside_box(bounds_fraction);
	ALBEDO = vec3(dot(colour, vec3(0.2126, 0.7152, 0.0722)));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	if (use_normal_texture) {
		NORMAL_MAP = texture(normal_texture, UV).rgb;
	}
	ALPHA = mask * grey_amount;
}
