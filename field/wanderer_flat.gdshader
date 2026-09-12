shader_type spatial;
// depth_draw_opaque forces this into the opaque depth pass regardless of
// blend mode - without it (and without ever writing ALPHA - see fragment()
// below) the Wanderer rendered fully invisible: spatial's default blend
// mode is blend_mix, and an unwritten ALPHA under that mode did not
// reliably resolve to 1.0 in practice. Never write ALPHA here - depth_
// draw_opaque plus leaving it alone is what actually renders opaque; an
// explicit ALPHA = 1.0 line is not needed and should not be reintroduced.
render_mode cull_back, diffuse_burley, specular_schlick_ggx, depth_draw_opaque;

// Posterized flat-shading from an albedo texture: sample, convert to
// luminance, quantize into tone_count discrete bands, then map each band
// through the dark->mid->light charcoal ramp below - never the sampled
// color itself, which only ever decides WHICH of the three authored tones
// a given texel lands on. Loaded at runtime by wanderer.gd (load(), never
// a hardcoded res:// default here) - this shader has no opinion on where
// the texture comes from, only what it does with it once set; wanderer.gd
// falls back to a plain flat StandardMaterial3D if that load ever fails.
uniform sampler2D albedo_texture : filter_linear, repeat_disable;

// How many discrete luminance bands to quantize into - 3 (the default)
// means every texel lands on exactly one of the three authored tones
// below with no blending between them. A higher count still only ever
// draws from those same three colors, interpolated across the extra
// steps, rather than needing more exported colors to fill in.
uniform int tone_count : hint_range(2, 8) = 3;

// Charcoal family, neutral-warm (a touch of red over blue, not a cool
// grey) - dark to light.
uniform vec4 tone_dark : source_color = vec4(0.125, 0.12, 0.115, 1.0);
uniform vec4 tone_mid : source_color = vec4(0.205, 0.195, 0.185, 1.0);
uniform vec4 tone_light : source_color = vec4(0.31, 0.295, 0.28, 1.0);

void fragment() {
	vec3 sampled = texture(albedo_texture, UV).rgb;
	float luminance = dot(sampled, vec3(0.299, 0.587, 0.114));

	int bands = max(tone_count, 2);
	int level = clamp(int(floor(luminance * float(bands))), 0, bands - 1);
	float t = float(level) / float(bands - 1);

	vec3 albedo = t < 0.5
		? mix(tone_dark.rgb, tone_mid.rgb, t * 2.0)
		: mix(tone_mid.rgb, tone_light.rgb, (t - 0.5) * 2.0);

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}
