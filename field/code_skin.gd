extends RefCounted
class_name CodeSkin

# A body's own mesh skinned onto a Skeleton3D made in code - the rig an
# attachment builds when the glb has none (RearPose's rear, SputterClaws'
# finger, HeadTurn's neck). The attachment decides the bones and each
# vertex's weights; this does the plumbing they all share: finding the
# body mesh under the model root, the skeleton (a child of that mesh, in
# its own space, so rests, binds and vertices share one frame), the skin
# (each bind the inverse of its bone's rest in mesh space) and the mesh
# rebuilt with the weights. The body's material is carried over to the
# rebuilt mesh and its material_override is never touched, so the hover
# highlight and the hit flash still tint the whole body.
#
# The skeleton runs at PROCESS_MODE_ALWAYS: a pose set during the field's
# freeze for a fight (or the reward screen) still has to draw.

var mesh_instance: MeshInstance3D = null
var skeleton: Skeleton3D = null
# Surface 0 of the body mesh as the glb has it, before any weights.
var arrays: Array = []
var _material: Material = null

# The skin for the first mesh under `model` that isn't inside `skip` (the
# attachment itself), or null - with a warning naming `label` - when
# there is none. Only surface 0 is rigged.
static func on_body(model: Node3D, skip: Node, skeleton_name: String, label: String) -> CodeSkin:
	if model == null:
		push_warning("%s: no model root above; nothing to rig." % label)
		return null
	var found: MeshInstance3D = null
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and (skip == null or not skip.is_ancestor_of(mi)):
			found = mi
			break
	if found == null:
		push_warning("%s: no body mesh under '%s'; nothing to rig." % [label, model.name])
		return null
	if found.mesh.get_surface_count() != 1:
		push_warning("%s: the body mesh has %d surfaces; only the first is rigged." % [label, found.mesh.get_surface_count()])
	var skin := CodeSkin.new()
	skin.mesh_instance = found
	skin.arrays = found.mesh.surface_get_arrays(0)
	skin._material = found.mesh.surface_get_material(0)
	skin.skeleton = Skeleton3D.new()
	skin.skeleton.name = skeleton_name
	skin.skeleton.process_mode = Node.PROCESS_MODE_ALWAYS
	found.add_child(skin.skeleton)
	return skin

func get_vertices() -> PackedVector3Array:
	return arrays[Mesh.ARRAY_VERTEX]

# The bones, replacing any there were: names, each one's parent index (-1
# for a root) and its rest relative to that parent, in mesh space. The
# binds follow from the rests, and the skin is handed to the mesh.
func set_bones(names: PackedStringArray, parents: PackedInt32Array, rests: Array[Transform3D]) -> void:
	skeleton.clear_bones()
	var globals: Array[Transform3D] = []
	var skin := Skin.new()
	for bone in names.size():
		skeleton.add_bone(names[bone])
		if parents[bone] >= 0:
			skeleton.set_bone_parent(bone, parents[bone])
		skeleton.set_bone_rest(bone, rests[bone])
		var global_rest: Transform3D = rests[bone] if parents[bone] < 0 else globals[parents[bone]] * rests[bone]
		globals.append(global_rest)
		skin.add_bind(bone, global_rest.affine_inverse())
	mesh_instance.skin = skin
	mesh_instance.skeleton = mesh_instance.get_path_to(skeleton)

# The mesh rebuilt with four bones and four weights per vertex, the body's
# material on it. `custom0`, when given, is four floats per vertex a
# shader pass reads as CUSTOM0 - measured on the rest pose, so it stays
# on the same skin however the bones move it (GreyshelfPose's throat).
func apply_weights(bones: PackedInt32Array, weights: PackedFloat32Array, custom0: PackedFloat32Array = PackedFloat32Array()) -> void:
	var surface: Array = arrays.duplicate()
	surface[Mesh.ARRAY_BONES] = bones
	surface[Mesh.ARRAY_WEIGHTS] = weights
	var flags: int = 0
	if not custom0.is_empty():
		surface[Mesh.ARRAY_CUSTOM0] = custom0
		flags = Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	var skinned := ArrayMesh.new()
	skinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface, [], {}, flags)
	skinned.surface_set_material(0, _material)
	mesh_instance.mesh = skinned
