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
# Floor 2 has no elevation layer: the model is the only raised ground,
# its own mass the pocket's back and sides.
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
#
# Barrier: the model's rear skin is ~37 degrees, walkable (his limit is
# 45), so on its own he could climb it and stand on the crest. A second
# body, invisible, stands on the footprint's outline: vertical faces from
# barrier_bottom_height over the pocket floor to barrier_top_margin over
# the model's top. It is open where he can walk in: a rim cell with a
# roof over it (barrier_walk_height up) and nothing in his way under it -
# the cave's mouth. It stops him at the rim, on the sand or on the
# slope's collar, and the cave is untouched. It is its own body
# (Barrier) so a check can tell it from the model.

const MODEL_SCENE_PATH := "res://assets/models/props/overhang/overhang.glb"

@export_group("Model")
# Local to this node, which sits on the pocket floor. y is the sink: the
# cave's floor dish rises to ~0.17 m (model units) under the cards'
# ends; 0.28 m puts it all under the sand there, and the rim under the
# flat sand all round.
@export var model_offset: Vector3 = Vector3(-1.13, -0.28, -0.01):
	set(value):
		model_offset = value
		if _model_instance != null:
			_model_instance.position = model_offset
		_rebuild_barrier()
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

@export_group("Barrier")
# Over the pocket floor (this node's origin). Above his step height, so
# the rim's own sand never catches him; below his waist, so he can't get
# a foot over it.
@export var barrier_bottom_height: float = 0.6:
	set(value):
		barrier_bottom_height = value
		_rebuild_barrier()
@export var barrier_top_margin: float = 0.5:
	set(value):
		barrier_top_margin = value
		_rebuild_barrier()
# A surface this high over the floor is a roof he walks under (his
# capsule is 1.8 m); one no higher than the tolerance is sand-level (the
# sunk cave floor, the buried rim). Between them is in his way.
@export var barrier_walk_height: float = 1.8:
	set(value):
		barrier_walk_height = value
		_rebuild_barrier()
@export var barrier_floor_tolerance: float = 0.05:
	set(value):
		barrier_floor_tolerance = value
		_rebuild_barrier()
# The grid the footprint is traced on; the outline is its cell edges.
@export var barrier_cell_size: float = 0.25:
	set(value):
		barrier_cell_size = value
		_rebuild_barrier()
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
var _barrier_shape_node: CollisionShape3D = null
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
	var barrier := StaticBody3D.new()
	barrier.name = "Barrier"
	barrier.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_model_instance.add_child(barrier)
	_barrier_shape_node = CollisionShape3D.new()
	_barrier_shape_node.name = "Shape"
	barrier.add_child(_barrier_shape_node)
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
	_rebuild_barrier()

# The footprint traced on a grid in the model's frame, from every baked
# triangle's height at each cell's centre. Then a wall quad on every
# outline edge, except where the cell inside is one he can walk into.
func _rebuild_barrier() -> void:
	if not _ready_done or _barrier_shape_node == null:
		return
	var cell: float = maxf(barrier_cell_size, 0.05)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var top: float = -INF
	for baked in _baked_surfaces:
		for v in baked[Mesh.ARRAY_VERTEX] as PackedVector3Array:
			lo = Vector2(minf(lo.x, v.x), minf(lo.y, v.z))
			hi = Vector2(maxf(hi.x, v.x), maxf(hi.y, v.z))
			top = maxf(top, v.y)
	if top == -INF:
		_barrier_shape_node.shape = null
		return
	# One empty cell of margin all round, so the outline is always closed.
	lo -= Vector2(cell, cell)
	var nx: int = int(ceil((hi.x - lo.x) / cell)) + 2
	var nz: int = int(ceil((hi.y - lo.y) / cell)) + 2
	# The floor is this node's origin; the model sits model_offset under it.
	var floor_y: float = -model_offset.y
	# Per cell: covered at all; anything in his body's height band over
	# the floor (solid to walk into); anything at or over his height (a
	# roof he can walk under).
	var covered := PackedByteArray()
	covered.resize(nx * nz)
	var body_band := PackedByteArray()
	body_band.resize(nx * nz)
	var roof := PackedByteArray()
	roof.resize(nx * nz)
	for baked in _baked_surfaces:
		var verts: PackedVector3Array = baked[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = baked[Mesh.ARRAY_INDEX]
		for t in range(0, indices.size() - 2, 3):
			var a: Vector3 = verts[indices[t]]
			var b: Vector3 = verts[indices[t + 1]]
			var c: Vector3 = verts[indices[t + 2]]
			var den: float = (b.x - a.x) * (c.z - a.z) - (c.x - a.x) * (b.z - a.z)
			if absf(den) < 1e-9:
				continue
			var i0: int = maxi(int(floor((minf(a.x, minf(b.x, c.x)) - lo.x) / cell - 0.5)), 0)
			var i1: int = mini(int(ceil((maxf(a.x, maxf(b.x, c.x)) - lo.x) / cell - 0.5)), nx - 1)
			var j0: int = maxi(int(floor((minf(a.z, minf(b.z, c.z)) - lo.y) / cell - 0.5)), 0)
			var j1: int = mini(int(ceil((maxf(a.z, maxf(b.z, c.z)) - lo.y) / cell - 0.5)), nz - 1)
			for i in range(i0, i1 + 1):
				for j in range(j0, j1 + 1):
					var px: float = lo.x + (float(i) + 0.5) * cell
					var pz: float = lo.y + (float(j) + 0.5) * cell
					var u: float = ((px - a.x) * (c.z - a.z) - (c.x - a.x) * (pz - a.z)) / den
					var w: float = ((b.x - a.x) * (pz - a.z) - (px - a.x) * (b.z - a.z)) / den
					if u < 0.0 or w < 0.0 or u + w > 1.0:
						continue
					var y: float = a.y + u * (b.y - a.y) + w * (c.y - a.y) - floor_y
					var k: int = i * nz + j
					covered[k] = 1
					if y >= barrier_walk_height:
						roof[k] = 1
					elif y > barrier_floor_tolerance:
						body_band[k] = 1
	# Holes in the trace (cells no triangle centre fell in, walled in by
	# covered ones) count as covered: only the outside is outside.
	var outside := PackedByteArray()
	outside.resize(nx * nz)
	var stack: Array[int] = [0]
	outside[0] = 1
	while not stack.is_empty():
		var k: int = stack.pop_back()
		var ki: int = k / nz
		var kj: int = k % nz
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ni: int = ki + d.x
			var nj: int = kj + d.y
			if ni < 0 or nj < 0 or ni >= nx or nj >= nz:
				continue
			var n: int = ni * nz + nj
			if outside[n] == 0 and covered[n] == 0:
				outside[n] = 1
				stack.append(n)
	var y0: float = floor_y + barrier_bottom_height
	var y1: float = top + barrier_top_margin
	var faces := PackedVector3Array()
	for i in nx:
		for j in nz:
			var k: int = i * nz + j
			if outside[k] == 1:
				continue
			# Open where he can walk in: a roof over the cell and nothing
			# in his way under it (the lip over bare sand, the cave floor
			# under its roof). Every other rim cell is walled.
			if roof[k] == 1 and body_band[k] == 0:
				continue
			var x0: float = lo.x + float(i) * cell
			var z0: float = lo.y + float(j) * cell
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ni: int = i + d.x
				var nj: int = j + d.y
				if ni >= 0 and nj >= 0 and ni < nx and nj < nz and outside[ni * nz + nj] == 0:
					continue
				var p: Vector2
				var q: Vector2
				if d.x == 1:
					p = Vector2(x0 + cell, z0)
					q = Vector2(x0 + cell, z0 + cell)
				elif d.x == -1:
					p = Vector2(x0, z0)
					q = Vector2(x0, z0 + cell)
				elif d.y == 1:
					p = Vector2(x0, z0 + cell)
					q = Vector2(x0 + cell, z0 + cell)
				else:
					p = Vector2(x0, z0)
					q = Vector2(x0 + cell, z0)
				faces.append_array([Vector3(p.x, y0, p.y), Vector3(q.x, y0, q.y), Vector3(q.x, y1, q.y), Vector3(p.x, y0, p.y), Vector3(q.x, y1, q.y), Vector3(p.x, y1, p.y)])
	if faces.is_empty():
		_barrier_shape_node.shape = null
		return
	var wall := ConcavePolygonShape3D.new()
	wall.backface_collision = true
	wall.set_faces(faces)
	_barrier_shape_node.shape = wall

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
