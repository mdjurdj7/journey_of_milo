shader_type spatial;
// depth_draw_opaque and never writing ALPHA: see wanderer_flat.gdshader -
// the same opaque-pass reasoning applies here. cull_disabled, as the
// glb's own material is double-sided: in the battle pose the skinning
// turns part of his left palm away from the camera, and back-face
// culling left a hole there (sand showing through). Back faces get the
// flipped normal, so they light like the front. fog_disabled: whoever
// wears it lays the depth fog back over it with an enemy_fog.gdshader
// next_pass (the Wanderer at fog_factor 1, as the scene would fog him; a
// painted enemy at its own share - FieldEnemy.refresh_fog()).
render_mode cull_disabled, depth_draw_opaque, fog_disabled;

// TEXTURED: a hand-painted albedo (tools/paint_texture.py) under soft
// light - roughness 1, no specular, no normal map, the light wrapped past
// the terminator and the shadows on him eased. Loaded at runtime by
// wanderer.gd for the body and the sword; the sword leaves albedo_tint
// white and never flashes.
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_disable;

// Multiplied into the texture - white is the texture as painted.
uniform vec4 albedo_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How far the light wraps past the terminator: 0 is plain Lambert, 1
// lights everything but the exact back. Scaled so a surface facing the
// light is fully lit at any wrap.
uniform float wrap : hint_range(0.0, 1.0) = 0.6;

// How much of a shadow lands on him: 1 is as dark as anywhere else, 0
// none. Every shadow on him at once (his own and anything else's) -
// light() only sees them combined.
uniform float self_shadow_strength : hint_range(0.0, 1.0) = 0.5;

// Battle hit-flash, as in wanderer_flat.gdshader: tweened by wanderer.gd's
// _tween_shader_flash(), 0 at rest, 1 fully flash_color.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How much of the body is left: 1 whole, 0 gone. Below 1 the surface is
// dithered out (screen-space noise, a discard - never ALPHA, which would
// take it off the opaque pass). A painted enemy's death dissolve
// (FieldEnemy._set_death_presence()); the Wanderer leaves it at 1.
uniform float presence : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	if (presence < 1.0) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (noise >= presence) {
			discard;
		}
	}
	vec3 albedo = texture(albedo_texture, UV).rgb * albedo_tint.rgb;
	ALBEDO = mix(albedo, flash_color.rgb, flash_amount);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

void light() {
	float lit = max((dot(NORMAL, LIGHT) + wrap) / (1.0 + wrap), 0.0);
	float shadow = mix(1.0, ATTENUATION, self_shadow_strength);
	DIFFUSE_LIGHT += LIGHT_COLOR * shadow * lit / PI;
}
