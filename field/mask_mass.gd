extends Node3D
class_name MaskMass

# A solid mass standing where a painting on the floor's landmass canvas
# says - region 2 floor 1's willow clumps and the reed thicket walling
# its edge, each a stand-in until modelled vegetation replaces it. One
# mesh, built from the mask on a grid of cell_m over rect: every vertex
# inside (the mask past half) is lifted off the relief by a height
# between height_range_m - a slow noise across the floor, seeded by
# layout_seed, never the run's generator - eased up over rise_m in from
# the outline on a quarter circle, so a willow with a wide rise_m comes
# out a rounded mass and the thicket, with a narrow one, a wall with a
# soft top. Vertices outside sit sink_m under the relief, so the mass
# meets the ground without a lip.
#
# Flat colour, matte, fogged as any standard material is (the shared flat
# look Hull and the Pier's graybox wear). No collision: the floor's ledges
# fence every mass, so nothing here needs stopping. Placed from data (a
# FloorProp at the spawn, no yaw): rect is in metres from this node, the
# floor's own world XZ. Rebuilt with the relief (Ground.relief_rebuilt)
# and on any edit.

@export_group("Shape")
# On the same canvas as the floor's landmass mask: white = the mass.
@export var mask: Texture2D = null:
	set(value):
		mask = value
		_rebuild()
# The grid's extent, XZ metres from this node - the mask's outlines with
# a little room; the mask is only read inside it.
@export var rect: Rect2 = Rect2():
	set(value):
		rect = value
		_rebuild()
@export var cell_m: float = 0.5:
	set(value):
		cell_m = value
		_rebuild()
# Full height, metres over the relief, from x to y across the floor.
@export var height_range_m: Vector2 = Vector2(3.0, 5.0):
	set(value):
		height_range_m = value
		_rebuild()
# How far in from the outline the mass reaches its full height.
@export var rise_m: float = 1.5:
	set(value):
		rise_m = value
		_rebuild()
# The height noise's feature size, metres.
@export var noise_wavelength_m: float = 8.0:
	set(value):
		noise_wavelength_m = value
		_rebuild()
@export var layout_seed: int = 1:
	set(value):
		layout_seed = value
		_rebuild()
@export var sink_m: float = 0.2:
	set(value):
		sink_m = value
		_rebuild()
@export_group("")

@export_group("Look")
@export var mass_color: Color = Color(0.34, 0.35, 0.3):
	set(value):
		mass_color = value
		_apply_material()
@export var cast_shadow: bool = true:
	set(value):
		cast_shadow = value
		if _mesh_instance != null:
			_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"

var _ground: Ground = null
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null

func _ready() -> void:
	var ground: Ground = _get_ground()
	if ground != null and not ground.relief_rebuilt.is_connected(_rebuild):
		ground.relief_rebuilt.connect(_rebuild)
	_rebuild()

func _get_ground() -> Ground:
	if _ground == null and is_inside_tree():
		_ground = get_node_or_null(ground_path) as Ground
	return _ground

func _rebuild() -> void:
	if not is_inside_tree() or mask == null or not rect.has_area():
		return
	var ground: Ground = _get_ground()
	if ground == null:
		push_warning("MaskMass '%s': ground_path did not resolve to a Ground; not built." % name)
		return
	if not ground.is_built():
		return
	var step: float = maxf(cell_m, 0.1)
	var cols: int = ceili(rect.size.x / step)
	var rows: int = ceili(rect.size.y / step)
	var width: int = cols + 1
	var count: int = width * (rows + 1)
	# The relief under every vertex (this node's Y) and whether it's in.
	var floor_y := PackedFloat32Array()
	floor_y.resize(count)
	var inside := PackedByteArray()
	inside.resize(count)
	var any: bool = false
	for row in rows + 1:
		for col in width:
			var i: int = row * width + col
			var local := Vector3(rect.position.x + col * step, 0.0, rect.position.y + row * step)
			var on_ground: Vector3 = ground.to_local(to_global(local))
			var ground_xz := Vector2(on_ground.x, on_ground.z)
			floor_y[i] = to_local(ground.to_global(Vector3(on_ground.x, ground.get_height_at(ground_xz), on_ground.z))).y
			var is_in: bool = ground.get_canvas_painting_at(mask, ground_xz) >= 0.5
			inside[i] = 1 if is_in else 0
			any = any or is_in
	if not any:
		push_warning("MaskMass '%s': no part of its mask lies inside rect; not built." % name)
		return
	var depth: PackedFloat32Array = _depth_in(inside, width, rows + 1, step)
	var noise := FastNoiseLite.new()
	noise.seed = layout_seed
	noise.frequency = 1.0 / maxf(noise_wavelength_m, 0.1)
	var positions := PackedVector3Array()
	positions.resize(count)
	for row in rows + 1:
		for col in width:
			var i: int = row * width + col
			var x: float = rect.position.x + col * step
			var z: float = rect.position.y + row * step
			var lift: float = -sink_m
			if inside[i] == 1:
				var full: float = lerpf(height_range_m.x, height_range_m.y, clampf(noise.get_noise_2d(x, z) * 0.5 + 0.5, 0.0, 1.0))
				var t: float = clampf(depth[i] / maxf(rise_m, 0.01), 0.0, 1.0)
				lift = full * sqrt(1.0 - (1.0 - t) * (1.0 - t))
			positions[i] = Vector3(x, floor_y[i] + lift, z)
	var normals := PackedVector3Array()
	normals.resize(count)
	for row in rows + 1:
		for col in width:
			var left: Vector3 = positions[row * width + maxi(col - 1, 0)]
			var right: Vector3 = positions[row * width + mini(col + 1, cols)]
			var back: Vector3 = positions[maxi(row - 1, 0) * width + col]
			var front: Vector3 = positions[mini(row + 1, rows) * width + col]
			normals[row * width + col] = (front - back).cross(right - left).normalized()
	# A cell is drawn when any corner is in; the rest of the grid isn't.
	var indices := PackedInt32Array()
	for row in rows:
		for col in cols:
			var a: int = row * width + col
			var b: int = a + 1
			var c: int = a + width
			var d: int = c + 1
			if inside[a] + inside[b] + inside[c] + inside[d] == 0:
				continue
			indices.append_array(PackedInt32Array([a, b, c, b, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mass"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_material()

# Metres from each inside vertex to the nearest outside one (0 outside),
# by a two-pass chamfer over the grid - near enough Euclidean for a
# profile eased over a metre or two.
static func _depth_in(inside: PackedByteArray, width: int, height: int, step: float) -> PackedFloat32Array:
	var diagonal: float = step * sqrt(2.0)
	var depth := PackedFloat32Array()
	depth.resize(width * height)
	for i in depth.size():
		depth[i] = INF if inside[i] == 1 else 0.0
	for row in height:
		for col in width:
			var i: int = row * width + col
			if depth[i] == 0.0:
				continue
			var best: float = depth[i]
			if col > 0:
				best = minf(best, depth[i - 1] + step)
			if row > 0:
				best = minf(best, depth[i - width] + step)
				if col > 0:
					best = minf(best, depth[i - width - 1] + diagonal)
				if col < width - 1:
					best = minf(best, depth[i - width + 1] + diagonal)
			depth[i] = best
	for row in range(height - 1, -1, -1):
		for col in range(width - 1, -1, -1):
			var i: int = row * width + col
			if depth[i] == 0.0:
				continue
			var best: float = depth[i]
			if col < width - 1:
				best = minf(best, depth[i + 1] + step)
			if row < height - 1:
				best = minf(best, depth[i + width] + step)
				if col < width - 1:
					best = minf(best, depth[i + width + 1] + diagonal)
				if col > 0:
					best = minf(best, depth[i + width - 1] + diagonal)
			depth[i] = best
	# A grid with no outside vertex at all: full height everywhere.
	for i in depth.size():
		if is_inf(depth[i]):
			depth[i] = 1000.0
	return depth

func _apply_material() -> void:
	if _mesh_instance == null:
		return
	if _material == null:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		# Both faces: an outline's last drawn cell can stand near upright.
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = mass_color
	_mesh_instance.material_override = _material
