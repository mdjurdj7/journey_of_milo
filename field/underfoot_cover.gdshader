shader_type spatial;
// fog_disabled: the body is out of the scene fog and FieldEnemy's
// enemy_fog.gdshader pass, last on the chain, fogs body and cover alike -
// as greyshelf_throat.gdshader.
render_mode blend_mix, depth_draw_never, cull_back, specular_disabled, fog_disabled;

// The Underfoot's sand cover (UnderfootPose): a next pass over the body's
// own material that lays sand over its back while it is Covered - by
// cover, 0 once Exposed. The sand is one colour with a little of the
// body's own pattern through it as grain; never lighter than the sand,
// no EMISSION, nothing that glows.
//
// Where: the back, faded off toward the rim so the disc's outline shows
// dark round the mound (CUSTOM0.r), and thinner over the eyes so they
// still show (CUSTOM0.g, at eye_opacity of the rest) - both measured on
// the rest pose, so the tilt and the tail can't slide them off.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform vec4 sand_colour : source_color = vec4(0.62, 0.55, 0.45, 1.0);
uniform float grain : hint_range(0.0, 1.0) = 0.12;
uniform float eye_opacity : hint_range(0.0, 1.0) = 0.35;
uniform float cover : hint_range(0.0, 1.0) = 0.88;

varying float back;
varying float eye;

void vertex() {
	back = CUSTOM0.r;
	eye = CUSTOM0.g;
}

void fragment() {
	vec3 body = texture(albedo_texture, UV).rgb;
	float luminance = dot(body, vec3(0.299, 0.587, 0.114));
	// The grain darkens where the pattern is dark and leaves the sand as
	// it is where it is pale.
	ALBEDO = sand_colour.rgb * (1.0 - grain + grain * clamp(luminance / 0.5, 0.0, 1.0));
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	ALPHA = clamp(cover * back * mix(1.0, eye_opacity, eye), 0.0, 1.0);
}
