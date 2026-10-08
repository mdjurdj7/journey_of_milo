shader_type spatial;

// The shared flat material's rules (Hull._get_shared_flat_material():
// roughness 1, no specular, no metal) for a ground-scatter kind that
// stirs in the wind - samphire, a stiff succulent: a barely perceptible
// sway, near zero, pinned at the base and growing toward the top, no
// bounce. A ShaderMaterial only because StandardMaterial3D has no vertex
// stage. Scene fog as any prop has it.
//
// Per instance (FieldScatter's MultiMesh): the colour, the tint's value
// jitter, multiplied in as COLOR; the phase from where it stands, so no
// two clumps keep time.

uniform vec4 tint : source_color = vec4(0.45, 0.50, 0.40, 1.0);
// The sway at the top, as a fraction of sway_height - FieldScatter sets
// both, sway_height in the mesh's own units.
uniform float sway_amount = 0.02;
uniform float sway_height = 1.0;
// Full cycles a second, and how much the place changes the phase.
uniform float sway_speed = 0.18;
uniform float sway_phase_scale = 1.3;

void vertex() {
	float weight = smoothstep(0.0, max(sway_height, 1.0e-6), VERTEX.y);
	weight *= weight;
	vec3 at = MODEL_MATRIX[3].xyz;
	float phase = dot(at.xz, vec2(1.0, 1.37)) * sway_phase_scale;
	float t = TIME * sway_speed * 6.2831853 + phase;
	float reach = sway_amount * sway_height * weight;
	VERTEX.x += reach * sin(t);
	VERTEX.z += reach * 0.6 * sin(t * 0.73 + 1.9);
}

void fragment() {
	ALBEDO = tint.rgb * COLOR.rgb;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
