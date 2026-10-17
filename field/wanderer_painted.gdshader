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

// The map's saturated colours (rust on a fence's wire) turned toward
// rust_tint: a pixel's share is its saturation through rust_saturation
// (x to y, a smoothstep) times rust_amount, and it keeps its value - the
// tint takes the hue, the pixel's brightness scales it. 0 = as painted
// (every wearer but SandFence).
uniform float rust_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 rust_tint : source_color = vec4(0.30, 0.28, 0.26, 1.0);
uniform vec2 rust_saturation = vec2(0.25, 0.45);

// The light - wrap, self_shadow_strength and light() - shared with the
// passes laid over a painted body.
#include "res://field/painted_light.gdshaderinc"

// Battle hit-flash, as in wanderer_flat.gdshader: tweened by wanderer.gd's
// _tween_shader_flash(), 0 at rest, 1 fully flash_color.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// How much of the body is left: 1 whole, 0 gone. Below 1 the surface is
// dithered out (screen-space noise, a discard - never ALPHA, which would
// take it off the opaque pass). A painted enemy's death dissolve
// (FieldEnemy._set_death_presence()); the Wanderer leaves it at 1.
uniform float presence : hint_range(0.0, 1.0) = 1.0;
// A MultiMesh's per-item presence (FieldScatter's battle fade): the
// instance colour's alpha multiplies presence when set. Off for anything
// that isn't scatter - a model's own vertex alpha never dissolves it.
uniform bool instance_presence = false;

void fragment() {
	float present = instance_presence ? presence * COLOR.a : presence;
	if (present < 1.0) {
		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (noise >= present) {
			discard;
		}
	}
	vec3 painted = texture(albedo_texture, UV).rgb;
	if (rust_amount > 0.0) {
		float high = max(painted.r, max(painted.g, painted.b));
		float low = min(painted.r, min(painted.g, painted.b));
		float saturation = (high - low) / max(high, 0.001);
		float share = smoothstep(rust_saturation.x, rust_saturation.y, saturation) * rust_amount;
		float value = dot(painted, vec3(0.299, 0.587, 0.114));
		float tint_value = max(dot(rust_tint.rgb, vec3(0.299, 0.587, 0.114)), 0.001);
		painted = mix(painted, rust_tint.rgb * (value / tint_value), share);
	}
	vec3 albedo = painted * albedo_tint.rgb;
	ALBEDO = mix(albedo, flash_color.rgb, flash_amount);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
