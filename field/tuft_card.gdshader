shader_type spatial;
// A painted card on the sand - a dune-grass tuft (FieldScatter, a
// ScatterEntry's cards): the painting stood up as one flat card, turned
// to the camera's yaw so it always reads at close to its full painted
// width, never edge-on. The camera's ground forward comes in as a uniform
// (FieldScatter pushes it from the live camera), not from the view
// matrix, so the shadow pass turns each card exactly as the eye sees it.
//
// The painted look (wanderer_painted.gdshader): the image as the albedo,
// roughness 1, no specular, the light wrapped and the shadows on it eased
// (painted_light.gdshaderinc). Its light reads normal_up of the way from
// the card's face toward straight up, so it lights about as the sand
// under it does and keeps its painted value against it.
//
// The depth fog is the scene's own, left on here: a painted prop is
// fog_disabled and has it laid back by an enemy_fog.gdshader pass at
// fog_factor 1, the same curve - but that pass can't follow the sway
// below, so the card fogs itself. A hard cutout (alpha scissor, alpha to
// coverage under the project's MSAA) - never blended, so nothing sorts;
// the painted edges stay soft through the mipmaps and the coverage.
//
// Per instance: COLOR is its value jitter; INSTANCE_CUSTOM.x its yaw off
// the camera's (radians), .y 1 or -1 (mirrored), .z its presence - 1
// whole, 0 gone, dithered out between (FieldScatter's battle fade).
render_mode cull_disabled, depth_draw_opaque;

#include "res://field/painted_light.gdshaderinc"

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float alpha_scissor = 0.5;
// The card's own height in the mesh's units - the top, where the bend is
// full.
uniform float card_height = 0.3;
// The camera's forward on the ground, world XZ.
uniform vec2 camera_forward = vec2(0.0, -1.0);
// The top leans this far back from the camera, so the face tips up
// toward it.
uniform float lean_degrees = 15.0;
uniform float normal_up = 0.6;

// The wind (RegionField.get_wind_direction(), world XZ, downwind) and
// its parts, each a fraction of card_height at the top - see ScatterEntry's
// Cards group.
uniform vec2 wind_direction = vec2(0.866, 0.5);
uniform float wind_lean = 0.03;
uniform float sway_amount = 0.04;
uniform float sway_hz = 0.33;
uniform float flutter_amount = 0.012;
uniform float flutter_hz = 1.7;
// How much the place changes the phase, per metre.
uniform float phase_scale = 0.9;

varying float v_presence;

void vertex() {
	v_presence = INSTANCE_CUSTOM.z;
	if (INSTANCE_CUSTOM.y < 0.0) {
		UV.x = 1.0 - UV.x;
	}
	vec2 ahead = length(camera_forward) > 1.0e-4 ? normalize(camera_forward) : vec2(0.0, -1.0);
	float c = cos(INSTANCE_CUSTOM.x);
	float s = sin(INSTANCE_CUSTOM.x);
	ahead = vec2(ahead.x * c - ahead.y * s, ahead.x * s + ahead.y * c);
	vec3 forward = vec3(ahead.x, 0.0, ahead.y);
	vec3 right = vec3(-ahead.y, 0.0, ahead.x);
	float lean = radians(lean_degrees);
	float up = VERTEX.y;
	vec3 placed = right * VERTEX.x + vec3(0.0, up * cos(lean), 0.0) + forward * up * sin(lean);

	// Pinned at the base, the bend growing with the square of the height.
	float weight = clamp(up / max(card_height, 1.0e-4), 0.0, 1.0);
	weight *= weight;
	vec3 at = MODEL_MATRIX[3].xyz;
	float phase = dot(at.xz, vec2(1.0, 1.37)) * phase_scale;
	float t = TIME * 6.2831853;
	vec3 downwind = vec3(wind_direction.x, 0.0, wind_direction.y);
	vec3 across = vec3(-wind_direction.y, 0.0, wind_direction.x);
	float along = wind_lean + sway_amount * sin(t * sway_hz + phase) + flutter_amount * sin(t * flutter_hz + phase * 2.3);
	float aside = flutter_amount * 0.5 * sin(t * flutter_hz * 1.31 + phase * 1.7);
	placed += (downwind * along + across * aside) * card_height * weight;

	VERTEX = placed;
	vec3 facing = -forward * cos(lean) + vec3(0.0, sin(lean), 0.0);
	NORMAL = normalize(mix(facing, vec3(0.0, 1.0, 0.0), normal_up));
}

void fragment() {
	if (v_presence < 1.0) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (noise >= v_presence) {
			discard;
		}
	}
	vec4 painted = texture(albedo_texture, UV);
	ALBEDO = painted.rgb * albedo_tint.rgb * COLOR.rgb;
	ALPHA = painted.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor;
	ALPHA_ANTIALIASING_EDGE = 0.25;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(albedo_texture, 0));
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
