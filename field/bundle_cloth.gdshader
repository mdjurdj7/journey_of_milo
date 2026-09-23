shader_type spatial;

// The bundle's cloth: the shared flat material's rules (Hull.
// _get_shared_flat_material() - fully rough, no specular, no metal, lit
// by the scene like everything else) with a procedural pass on the
// albedo. Nothing is sampled from a texture; the glb's own textures are
// ignored, as the hull's are.
//
//   Weave - value noise at two scales in the model's own space, so it
//           stays on the cloth when the bundle turns or sinks. Low
//           amplitude, and cool: where the weave dips, the tint leans
//           toward weave_cool as well as darkening.
//   Creases - the rope's creases read from the mesh's smooth normals:
//           screen-space curvature (the normal's change against the
//           position's), and only the concave side darkens.
//
// Driven entirely by BundleProp's exports (see its Cloth group).

uniform vec3 tint : source_color = vec3(0.50, 0.47, 0.42);
uniform float weave_scale_fine = 90.0;
uniform float weave_scale_coarse = 22.0;
uniform float weave_amplitude = 0.07;
uniform vec3 weave_cool : source_color = vec3(0.90, 0.95, 1.0);
uniform float crease_darkening = 0.25;
uniform float crease_curvature_scale = 0.04;

varying vec3 object_position;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// -1..1
float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash(i);
	float n100 = hash(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash(i + vec3(1.0, 1.0, 1.0));
	float x00 = mix(n000, n100, u.x);
	float x10 = mix(n010, n110, u.x);
	float x01 = mix(n001, n101, u.x);
	float x11 = mix(n011, n111, u.x);
	return mix(mix(x00, x10, u.y), mix(x01, x11, u.y), u.z) * 2.0 - 1.0;
}

void vertex() {
	object_position = VERTEX;
}

void fragment() {
	float weave = value_noise(object_position * weave_scale_fine) * 0.6
		+ value_noise(object_position * weave_scale_coarse) * 0.4;
	vec3 albedo = tint * (1.0 + weave_amplitude * weave);
	albedo *= mix(vec3(1.0), weave_cool, clamp(-weave, 0.0, 1.0));

	// Signed curvature from the view-space normal and position: positive
	// where the surface bends away (a bulge), negative in a crease.
	vec3 dn_x = dFdx(NORMAL);
	vec3 dn_y = dFdy(NORMAL);
	vec3 dp_x = dFdx(VERTEX);
	vec3 dp_y = dFdy(VERTEX);
	float curvature = dot(dn_x, dp_x) / max(dot(dp_x, dp_x), 1e-8)
		+ dot(dn_y, dp_y) / max(dot(dp_y, dp_y), 1e-8);
	float crease = clamp(-curvature * crease_curvature_scale, 0.0, 1.0);
	albedo *= 1.0 - crease_darkening * crease;

	ALBEDO = albedo;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}
