shader_type spatial;
render_mode blend_mix, cull_back, diffuse_burley, specular_schlick_ggx;

// Look-dev only: stylized stone for RuinPavingTest (see region_field.tscn,
// applied via surface_material_override on its three PavingSlab_0X
// children). Temporary and isolated — revert by deleting this file plus
// the ShaderMaterial/ext_resource and the three override blocks in
// region_field.tscn; the meshes fall back to their imported glTF material.
//
// Painterly ruined stone: a cool muted blue-gray base broken up by broad,
// low-frequency light/dark patches, with a few warmer worn patches mixed
// in at restrained strength. Normal break-up is a small per-vertex jitter
// only — VERTEX is never displaced, so each slab's modeled silhouette and
// bevels stay exactly as authored.

uniform vec4 base_color : source_color = vec4(0.36, 0.4, 0.44, 1.0);
uniform vec4 shade_color : source_color = vec4(0.22, 0.25, 0.29, 1.0);
uniform vec4 warm_worn_color : source_color = vec4(0.5, 0.44, 0.37, 1.0);

// Broad, low-frequency light/dark patches across each slab.
uniform float value_noise_scale = 1.8;
uniform float value_noise_strength : hint_range(0.0, 1.0) = 0.6;

// Sparser, larger warm "worn" patches mixed into the cool base.
uniform float warm_noise_scale = 2.6;
uniform float warm_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float warm_strength : hint_range(0.0, 1.0) = 0.35;

// Restrained, shading-only normal break-up — a small per-vertex jitter
// added to the existing normal (not a reconstructed height field), so it
// perturbs every face — top and sides alike — about its own orientation
// instead of assuming one.
uniform float normal_break_scale = 0.6;
uniform float normal_break_amplitude : hint_range(0.0, 0.05) = 0.015;

uniform float stone_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float stone_specular : hint_range(0.0, 1.0) = 0.25;

varying vec3 v_object_pos;

// Textureless value noise, ~[0,1]. Same construction as ground.gdshader's;
// kept local rather than shared since this is the only other consumer
// (see CLAUDE.md: extract shared helpers only once a third one exists).
float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// Object space so the pattern travels with each slab instance rather
	// than sliding as RuinPavingTest is placed/rotated in the world.
	v_object_pos = VERTEX;

	float n1 = value_noise(VERTEX.xz / max(normal_break_scale, 0.001));
	float n2 = value_noise(VERTEX.zy / max(normal_break_scale, 0.001) + vec2(17.0, 5.0));
	float n3 = value_noise(VERTEX.xy / max(normal_break_scale, 0.001) + vec2(0.0, 31.0));
	vec3 jitter = (vec3(n1, n2, n3) - 0.5) * 2.0 * normal_break_amplitude;
	NORMAL = normalize(NORMAL + jitter);
}

void fragment() {
	float value_n = value_noise(v_object_pos.xz / max(value_noise_scale, 0.001));
	vec3 varied = mix(base_color.rgb, shade_color.rgb, value_n * value_noise_strength);

	float warm_n = value_noise(v_object_pos.xz / max(warm_noise_scale, 0.001) + vec2(91.7, 0.0));
	float warm_mask = smoothstep(warm_threshold - 0.12, warm_threshold + 0.12, warm_n);
	vec3 albedo = mix(varied, warm_worn_color.rgb, warm_mask * warm_strength);

	ALBEDO = albedo;
	ROUGHNESS = stone_roughness;
	SPECULAR = stone_specular;
	METALLIC = 0.0;
}
