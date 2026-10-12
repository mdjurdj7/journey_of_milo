shader_type spatial;
// depth_draw_opaque forces this into the opaque depth pass regardless of
// blend mode - without it (and without ever writing ALPHA - see fragment()
// below) the Wanderer rendered fully invisible: spatial's default blend
// mode is blend_mix, and an unwritten ALPHA under that mode did not
// reliably resolve to 1.0 in practice. Never write ALPHA here - depth_
// draw_opaque plus leaving it alone is what actually renders opaque; an
// explicit ALPHA = 1.0 line is not needed and should not be reintroduced.
// cull_disabled, as the glb's own material is double-sided: in the battle
// pose the skinning turns part of his left palm away from the camera, and
// back-face culling left a hole there (sand showing through). Back faces
// get the flipped normal, so they light like the front.
render_mode cull_disabled, depth_draw_opaque;

// Posterized flat-shading from an albedo texture: sample, convert to
// luminance, remap it through the two band cut-offs, quantize into
// tone_count discrete bands, then map each band through the
// dark->mid->light ramp below - never the sampled
// color itself, which only ever decides WHICH of the three authored tones
// a given texel lands on. Loaded at runtime by wanderer.gd (load(), never
// a hardcoded res:// default here) - this shader has no opinion on where
// the texture comes from, only what it does with it once set; wanderer.gd
// falls back to a plain flat StandardMaterial3D if that load ever fails.
// Mipmapped: at battle size the texture is minified a lot, and without
// mipmaps the band each pixel lands on flickers as he moves.
uniform sampler2D albedo_texture : filter_linear_mipmap, repeat_disable;

// How many discrete luminance bands to quantize into - 3 (the default)
// means every texel lands on exactly one of the three authored tones
// below with no blending between them. A higher count still only ever
// draws from those same three colors, interpolated across the extra
// steps, rather than needing more exported colors to fill in.
uniform int tone_count : hint_range(2, 8) = 3;

// Where the texture's luminance (as stored, not linearised) crosses from
// dark to mid and from mid to light at tone_count 3. Luminance is
// remapped piecewise so these land on the 1/3 and 2/3 band edges; a
// painted texture's own levels (tools/paint_texture.py prints them)
// are where to put them.
uniform float band_low_cutoff : hint_range(0.0, 1.0) = 0.333333;
uniform float band_high_cutoff : hint_range(0.0, 1.0) = 0.666667;

// The light's terminator, stepped to two values (lit or not) instead of
// a gradient over every fold. 0 is a hard step; above it, the step
// blends over this much N.L either side of the terminator. Cast shadows
// still darken through ATTENUATION as they do on every other material.
uniform float light_step_softness : hint_range(0.0, 1.0) = 0.0;

// Charcoal family, neutral-warm (a touch of red over blue, not a cool
// grey) - dark to light.
uniform vec4 tone_dark : source_color = vec4(0.125, 0.12, 0.115, 1.0);
uniform vec4 tone_mid : source_color = vec4(0.205, 0.195, 0.185, 1.0);
uniform vec4 tone_light : source_color = vec4(0.31, 0.295, 0.28, 1.0);

// Battle hit-flash (see wanderer.gd's own play_hit_flash()/_tween_shader_
// flash()): this ramp has no single albedo property a Tween could lerp
// directly, so flash_amount/flash_color are driven by a Tween instead and
// blended on top of the posterized ramp below - 0 (default, at rest) is a
// no-op, 1.0 is fully flash_color.
uniform float flash_amount : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	vec3 sampled = texture(albedo_texture, UV).rgb;
	float luminance = dot(sampled, vec3(0.299, 0.587, 0.114));
	float low = clamp(band_low_cutoff, 0.0001, 0.9998);
	float high = clamp(band_high_cutoff, low + 0.0001, 0.9999);
	if (luminance < low) {
		luminance = luminance / low / 3.0;
	} else if (luminance < high) {
		luminance = (1.0 + (luminance - low) / (high - low)) / 3.0;
	} else {
		luminance = (2.0 + (luminance - high) / (1.0 - high)) / 3.0;
	}

	int bands = max(tone_count, 2);
	int level = clamp(int(floor(luminance * float(bands))), 0, bands - 1);
	float t = float(level) / float(bands - 1);

	vec3 albedo = t < 0.5
		? mix(tone_dark.rgb, tone_mid.rgb, t * 2.0)
		: mix(tone_mid.rgb, tone_light.rgb, (t - 0.5) * 2.0);
	albedo = mix(albedo, flash_color.rgb, flash_amount);

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	METALLIC = 0.0;
}

// Replaces the Burley gradient: the same light, energy and shadows, but
// N.L is stepped to lit or unlit, and there is no specular term.
void light() {
	float n_dot_l = dot(NORMAL, LIGHT);
	float lit = step(0.0, n_dot_l);
	if (light_step_softness > 0.0) {
		lit = smoothstep(-light_step_softness, light_step_softness, n_dot_l);
	}
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * lit / PI;
}
