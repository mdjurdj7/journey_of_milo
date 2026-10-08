shader_type spatial;
// An enemy's share of the depth fog, drawn as a second pass over its own
// body (FieldEnemy - the body material's next_pass): the body material is
// fog_disabled, and this lays the fog colour back over it at
// fog_factor x the environment's own depth-fog amount - the same curve,
// smoothstep(fog_begin, fog_end, view distance) x fog_density (Godot's
// FOG_MODE_DEPTH at depth_curve 1.0, as sea.gdshader reproduces it). At
// fog_factor 1 the body fogs exactly as the environment would fog it; at
// 0.4 it keeps its value as a dark figure while the scenery behind it
// fades. RegionField pushes the uniforms from RegionSky, live.
//
// Unshaded and blended, drawn on the body's own depth (no depth write),
// so it only ever lands on the body's visible surface. Cull disabled for
// the dragonfly's two-sided wings; on a closed body the back faces lose
// the depth test anyway. An alpha-scissor surface (the wings) hands over
// its albedo texture and threshold so the cut-away part stays clear.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

uniform vec3 fog_color : source_color = vec3(0.86, 0.87, 0.86);
// RegionSky.fog_light_energy - the environment scales its fog colour by
// it, in linear.
uniform float fog_energy = 1.0;
uniform float fog_begin = 14.0;
uniform float fog_end = 28.0;
uniform float fog_density = 1.0;
uniform float fog_factor : hint_range(0.0, 1.0) = 0.4;
uniform bool use_alpha_texture = false;
uniform sampler2D alpha_texture : source_color, filter_linear_mipmap;
uniform float alpha_scissor_threshold = 0.5;

void fragment() {
	if (use_alpha_texture && texture(alpha_texture, UV).a <= alpha_scissor_threshold) {
		discard;
	}
	float amount = smoothstep(fog_begin, fog_end, length(VERTEX)) * fog_density;
	ALBEDO = fog_color * fog_energy;
	ALPHA = clamp(amount * fog_factor, 0.0, 1.0);
}
