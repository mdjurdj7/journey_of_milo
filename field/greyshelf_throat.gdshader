shader_type spatial;
// fog_disabled: the body is out of the scene fog and FieldEnemy's
// enemy_fog.gdshader pass, last on the chain, fogs body and throat
// alike - scene fog here as well would fade the throat at its own rate.
// blend_mul, unshaded: it multiplies the body as already drawn and lit,
// so the throat keeps whatever light the body's own material gives it
// (wanderer_painted.gdshader's or a StandardMaterial3D's), lit side and
// shadow side alike.
render_mode blend_mul, unshaded, depth_draw_never, cull_back, fog_disabled;

// The Greyshelf's throat deepening for the Gape (GreyshelfPose): a next
// pass over the body's own material that turns the body's blue, deepened
// and darkened, over the throat and nothing else, by deepen - 0 at rest,
// up with the rear, further with each Goaded stack. As a multiply: per
// channel the deepened colour over the body's own, mixed from 1 by the
// mask, so the lit result is the deepened albedo under the same light. Hue and value
// only, never lighter: the saturation rises to at most max_saturation and
// the value only falls, so it stays muted - no EMISSION, nothing that
// reads as a glow.
//
// Which skin is the throat: the body's blue (a hue range, with enough
// saturation - the grey skin round it is barely tinted) on vertices the
// pose marked as the throat and jaw in CUSTOM0.r, measured on the rest
// pose so the rear can't slide the mask off it.

// The body's own albedo (GreyshelfPose hands it over).
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
// The blue: hue centre and half-width in degrees, and the least
// saturation that counts.
uniform float hue_center_degrees = 207.0;
uniform float hue_half_width_degrees = 25.0;
uniform float min_saturation = 0.18;
// At full deepen: the saturation times (1 + saturation_gain), held under
// max_saturation, and the value times (1 - darken). darken 0.3 as a
// multiply reads as deep as 0.5 did as a lit blend_mix pass, whose own
// light sat a little above the body's.
uniform float saturation_gain = 0.8;
uniform float max_saturation = 0.6;
uniform float darken = 0.3;
uniform float deepen : hint_range(0.0, 1.0) = 0.0;

varying float throat;

vec3 rgb_to_hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv_to_rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void vertex() {
	throat = CUSTOM0.r;
}

void fragment() {
	vec3 colour = texture(albedo_texture, UV).rgb;
	vec3 hsv = rgb_to_hsv(colour);
	float hue_off = abs(fract(hsv.x - hue_center_degrees / 360.0 + 0.5) - 0.5) * 360.0;
	float blue = 1.0 - smoothstep(hue_half_width_degrees * 0.7, hue_half_width_degrees, hue_off);
	blue *= smoothstep(min_saturation * 0.7, min_saturation, hsv.y);
	float saturation = max(hsv.y, min(hsv.y * (1.0 + saturation_gain), max_saturation));
	float value = hsv.z * (1.0 - darken);
	vec3 deepened = hsv_to_rgb(vec3(hsv.x, saturation, value));
	// Never above 1: a higher saturation at a lower value is darker in
	// every channel.
	vec3 ratio = clamp(deepened / max(colour, vec3(1.0e-4)), 0.0, 1.0);
	float amount = clamp(blue * throat * deepen, 0.0, 1.0);
	ALBEDO = mix(vec3(1.0), ratio, amount);
}
