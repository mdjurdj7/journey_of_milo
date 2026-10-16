extends RefCounted
class_name PaintedProp

# The painted look a model prop wears on the sand, as the enemies and the
# Wanderer do: the model's own colour map under wanderer_painted.gdshader
# (roughness 1, no specular, no normal map, cull disabled), times a tint,
# and - since that shader is fog_disabled - the depth fog laid back over
# it by an enemy_fog.gdshader pass, filled from the field's RegionSky.
# Shared by BelongingsObject, the workbench (Wagon), the Handcart and the
# BaskingSlab; each keeps its own material, fog pass and fog_factor.

const PAINTED_SHADER_PATH := "res://field/wanderer_painted.gdshader"
const FOG_SHADER_PATH := "res://field/enemy_fog.gdshader"

# `colour_map_path` under the painted shader, times `albedo_tint`. No fog
# pass: a prop on the sand sets fog_pass() as its next_pass, a screen's
# render doesn't. Null when the shader or the map fails to load - the
# caller falls back as it sees fit.
static func material(colour_map_path: String, albedo_tint: Color) -> ShaderMaterial:
	var shader := load(PAINTED_SHADER_PATH) as Shader
	var texture: Texture2D = load(colour_map_path) as Texture2D if ResourceLoader.exists(colour_map_path) else null
	if shader == null or texture == null:
		push_warning("PaintedProp: painted material failed to load (%s, %s)." % [PAINTED_SHADER_PATH, colour_map_path])
		return null
	var painted := ShaderMaterial.new()
	painted.shader = shader
	painted.set_shader_parameter("albedo_texture", texture)
	painted.set_shader_parameter("albedo_tint", albedo_tint)
	return painted

# The enemy_fog.gdshader overlay a painted material carries as its
# next_pass. Null, with a warning, when the shader fails to load.
static func fog_pass() -> ShaderMaterial:
	var shader := load(FOG_SHADER_PATH) as Shader
	if shader == null:
		push_warning("PaintedProp: fog pass shader failed to load (%s); unfogged." % FOG_SHADER_PATH)
		return null
	var pass_material := ShaderMaterial.new()
	pass_material.shader = shader
	return pass_material

# The field's depth fog into `fog`, at `fog_factor` - as the Wanderer's is
# (Wanderer.refresh_fog()). A no-op without either.
static func push_fog(fog: ShaderMaterial, sky: RegionSky, fog_factor: float) -> void:
	if fog == null or sky == null:
		return
	fog.set_shader_parameter("fog_color", sky.fog_color)
	fog.set_shader_parameter("fog_energy", sky.fog_light_energy)
	fog.set_shader_parameter("fog_begin", sky.current_fog_depth_begin())
	fog.set_shader_parameter("fog_end", sky.current_fog_depth_end())
	fog.set_shader_parameter("fog_density", sky.fog_density)
	fog.set_shader_parameter("fog_factor", fog_factor)

# Every mesh under `model` wears `dress` and casts a shadow; returns their
# merged AABB in `frame`'s space (composed first, then the box - `frame`
# may already be yawed or tilted). An empty AABB for a model with no mesh.
static func dress_model(model: Node3D, dress: Material, frame: Node3D) -> AABB:
	var box := AABB()
	var has_box := false
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.material_override = dress
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var local: AABB = (frame.global_transform.affine_inverse() * mesh_instance.global_transform) * mesh_instance.get_aabb()
		box = local if not has_box else box.merge(local)
		has_box = true
	return box
