extends Node3D
class_name SandOverhang

# The overhang over the back of floor 2's pocket: a sculpted dune with an
# undercut face and a hollow beneath it (overhang.glb), the one thing on
# the floor the ground can't make - the ground is a heightfield, so it
# can neither overhang nor rise past Ground.elevation_max_height.
#
# Placed by RegionField from FloorData.props like any prop (set_floor_
# placement(): XZ from the floor, yaw onto yaw_degrees) and grounded on
# the relief just in front of its origin (ground_sample_offset) - the
# pocket floor, so the model's own cave floor can be sunk under it by a
# fixed amount wherever the floor ends up. The model then sits under this
# node at model_offset, scaled by model_scale, mirrored across when
# mirror_across is set and turned by model_yaw_degrees, all live. The
# defaults put the cache's three cards on the sand under the hollow's
# roof, ~1.3 m in from the lip, with ~2.0 m of roof over them.
#
# The painted bank is dropped to the pocket floor inside the model's
# footprint (floor 2's elevation mask) and ramps down to its rim outside
# it, so the model's own mass is the pocket's back and sides.
#
# The glb (origin at its base, ~6.5 x 2.4 x 6.6 m) is a thin double-
# skinned shell: its undercut face and hollow look along the model's +Z,
# its rear is a slope down to the ground, and it is open underneath. Its
# hollow has its own floor, a shallow dish ~0.1 m up; model_offset.y
# sinks that dish under the pocket floor so the painted floor (and the
# cache on it) is what shows, and the rim goes under the sand all round.
#
# The scale, mirror and yaw are baked into the vertices here, not set on
# a node: model_scale is not uniform (narrower across, taller), and a
# scaled or mirrored concave collision shape or a scaled normal would all
# come out wrong.
#
# Colour: the glb's textures are discarded at import. The whole model is
# sand (sand_tint, on the flat matte material the hulls use); the faces
# that look down are darker sand, through vertex colour worked out from
# each vertex's normal - full sand_tint down to a normal.y of
# shade_blend_start, sand_tint x underside_shade from shade_blend_end
# on, a smooth blend between. The key light is near overhead and the
# ambient flat, so the cave roof is lit by the ambient alone; the vertex
# colour deepens that without a texture or a new material.
#
# Collision: a trimesh of the same baked mesh, collision on both faces
# (the skin is ~5 cm thick; a one-sided face lets a capsule through from
# behind). He walks in under the lip and stops at the surface he can see,
# the cave's back wall. Nothing fades: past the lip the roof hides him
# from the field camera.

const MODEL_SCENE_PATH := "res://assets/models/props/overhang/overhang.glb"

@export_group("Model")
# Local to this node, which sits on the pocket floor. y is the sink: the
# cave's floor dish rises to ~0.17 m (model units) under the cards'
# ends, and 0.23 m puts it all under the sand there.
@export var model_offset: Vector3 = Vector3(-1.13, -0.23, -0.01):
	set(value):
		model_offset = value
		if _model_instance != null:
			_model_instance.position = model_offset
# Turns the model's +Z (its undercut face) onto this node's +X (the
# pocket's mouth).
@export var model_yaw_degrees: float = 90.0:
	set(value):
		model_yaw_degrees = value
		_rebuild()
# In the model's own axes, before the yaw: X across the hollow, Y up, Z
# from the rear slope out to the lip.
@export var model_scale: Vector3 = Vector3(0.85, 1.15, 0.85):
	set(value):
		model_scale = value
		_rebuild()
# Flips the model across (its X) before the yaw. The hollow's roof stops
# short on the model's -X side and leaves the cave open to the sky there;
# the field camera looks north from high in the south, so that side goes
# north, to the sea, and the model's solid +X side faces the camera.
@export var mirror_across: bool = true:
	set(value):
		mirror_across = value
		_rebuild()
@export_group("")

@export_group("Colour")
# Dry sand (Ground.ground_color, file 03's palette).
@export var sand_tint: Color = Color(0.74, 0.70, 0.60):
	set(value):
		sand_tint = value
		_recolour()
# The downward faces, as a multiplier on sand_tint.
@export_range(0.0, 1.0) var underside_shade: float = 0.8:
	set(value):
		underside_shade = value
		_recolour()
# The normal.y the darkening starts at and the one it is full from.
@export_range(-1.0, 0.0) var shade_blend_start: float = -0.2:
	set(value):
		shade_blend_start = value
		_recolour()
@export_range(-1.0, 0.0) var shade_blend_end: float = -0.7:
	set(value):
		shade_blend_end = value
		_recolour()
@export_group("")

@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
# Grounded on the relief this far in front of the origin (local +X) -
# the pocket floor, under the hollow.
@export var ground_sample_offset: float = 0.6:
	set(value):
		ground_sample_offset = value
		_ground_to_relief()
@export var ground_path: NodePath = ^"../../Ground"

var _model_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _body: StaticBody3D = null
var _shape_node: CollisionShape3D = null
var _ground: Ground = null
var _ready_done: bool = false
# The glb's surfaces as imported (Mesh.ARRAY_* arrays), and the baked
# ones - vertices and normals scaled and turned - the colours are written
# onto.
var _source_surfaces: Array[Array] = []
var _baked_surfaces: Array[Array] = []

# RegionField's placement (FloorProp): XZ here, Y from the relief, yaw
# onto yaw_degrees; it doesn't roll.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	_model_instance = MeshInstance3D.new()
	_model_instance.name = "Model"
	_model_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_model_instance.position = model_offset
	add_child(_model_instance)
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.vertex_color_use_as_albedo = true
	# The tints are authored like every other colour here, in sRGB.
	_material.vertex_color_is_srgb = true
	_material.albedo_color = Color.WHITE
	_model_instance.material_override = _material
	_body = StaticBody3D.new()
	_body.name = "Collision"
	# Kept in the physics space through RegionField's freeze, like every
	# prop that must stay solid (and clickable) under a fight.
	_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_model_instance.add_child(_body)
	_shape_node = CollisionShape3D.new()
	_shape_node.name = "Shape"
	_body.add_child(_shape_node)
	_load_source()
	_ready_done = true
	_rebuild()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("SandOverhang '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var sample: Vector3 = global_position + global_transform.basis.x.normalized() * ground_sample_offset
	var local_xz: Vector3 = _ground.to_local(Vector3(sample.x, 0.0, sample.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# The glb's mesh surfaces, in the scene root's frame.
func _load_source() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("SandOverhang: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	var root: Node3D = scene.instantiate() as Node3D
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_root: Transform3D = Transform3D.IDENTITY
		var n: Node = mi
		while n != root and n is Node3D:
			to_root = (n as Node3D).transform * to_root
			n = n.get_parent()
		var normal_basis: Basis = to_root.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arrays: Array = mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = to_root * verts[i]
				normals[i] = (normal_basis * normals[i]).normalized()
			var kept: Array = []
			kept.resize(Mesh.ARRAY_MAX)
			kept[Mesh.ARRAY_VERTEX] = verts
			kept[Mesh.ARRAY_NORMAL] = normals
			kept[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
			_source_surfaces.append(kept)
	root.free()

# Scale and yaw into the vertices, then the colours, the mesh and the
# collision.
func _rebuild() -> void:
	if not _ready_done:
		return
	var scale_xyz: Vector3 = model_scale
	if mirror_across:
		scale_xyz.x = -scale_xyz.x
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(model_yaw_degrees)) * Basis.from_scale(scale_xyz)
	var normal_basis: Basis = basis.inverse().transposed()
	# A mirror turns every triangle inside out; swapping two corners of
	# each puts the front faces back outside.
	var flip: bool = basis.determinant() < 0.0
	_baked_surfaces.clear()
	for source in _source_surfaces:
		var verts: PackedVector3Array = (source[Mesh.ARRAY_VERTEX] as PackedVector3Array).duplicate()
		var normals: PackedVector3Array = (source[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
		for i in verts.size():
			verts[i] = basis * verts[i]
			normals[i] = (normal_basis * normals[i]).normalized()
		var indices: PackedInt32Array = (source[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
		if flip:
			for t in range(0, indices.size() - 2, 3):
				var corner: int = indices[t + 1]
				indices[t + 1] = indices[t + 2]
				indices[t + 2] = corner
		var baked: Array = []
		baked.resize(Mesh.ARRAY_MAX)
		baked[Mesh.ARRAY_VERTEX] = verts
		baked[Mesh.ARRAY_NORMAL] = normals
		baked[Mesh.ARRAY_INDEX] = indices
		_baked_surfaces.append(baked)
	_recolour()
	var shape: ConcavePolygonShape3D = _model_instance.mesh.create_trimesh_shape() if _model_instance.mesh != null else null
	if shape != null:
		shape.backface_collision = true
	_shape_node.shape = shape

func _recolour() -> void:
	if not _ready_done:
		return
	var shade := Color(sand_tint.r * underside_shade, sand_tint.g * underside_shade, sand_tint.b * underside_shade, 1.0)
	var mesh := ArrayMesh.new()
	for baked in _baked_surfaces:
		var normals: PackedVector3Array = baked[Mesh.ARRAY_NORMAL]
		var colours := PackedColorArray()
		colours.resize(normals.size())
		for i in normals.size():
			var t: float = smoothstep(shade_blend_start, shade_blend_end, normals[i].y)
			colours[i] = sand_tint.lerp(shade, t)
		baked[Mesh.ARRAY_COLOR] = colours
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, baked)
	_model_instance.mesh = mesh
