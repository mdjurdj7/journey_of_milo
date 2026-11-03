extends Node3D
class_name MaskMass

# A mass of foliage standing where a painting on the floor's landmass
# canvas says - region 2 floor 1's willow clumps and the reed thicket
# walling its edge, each a stand-in until modelled vegetation replaces it.
# Packed lobes, never a sheet: squashed, lumpy ellipsoids (one shared lobe
# mesh, a MultiMesh of them) sunk into each other and into the ground,
# darker underneath and a little lighter on top.
#
# Where: the mask is read on a grid of cell_m over rect, and each inside
# cell knows how far it lies in from the outline. Sites are taken deepest
# first, jittered by layout_seed (never the run's generator), each a lobe
# lobe_size_m across - interior_lobe_size_m past band_m in - no wider
# than its distance to the outline plus overhang_m, so the silhouette is
# a scalloped run of lobe edges and never a cell step; a site closer than
# lobe_spacing of the two lobes' widths to one already taken tries a lobe
# a quarter narrower, then is dropped.
#
# How high: a lobe's top climbs from edge_height_m at the outline to the
# full height - height_range_m.x to .y by a slow noise across the floor -
# over rise_m in, give or take top_jitter_m, so the top line is never
# level. Within face_depth_m of the outline more lobes stack under it
# down into the ground - the face the camera sees; deeper in, one core
# lobe fills under it, hidden behind its neighbours' tops.
#
# Flat colour (mass_color times the lobes' shading), matte, fogged as any
# standard material is. No collision: the floor's ledges fence every
# mass. Placed from data (a FloorProp at the spawn, no yaw): rect is in
# metres from this node, the floor's own world XZ. Rebuilt with the
# relief (Ground.relief_rebuilt) and on any edit; the last build's time
# is get_build_msec().

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
# Full height of the tops, metres over the relief, from x to y across the
# floor.
@export var height_range_m: Vector2 = Vector2(3.0, 5.0):
	set(value):
		height_range_m = value
		_rebuild()
# The tops at the outline, metres over the relief.
@export var edge_height_m: float = 1.5:
	set(value):
		edge_height_m = value
		_rebuild()
# How far in from the outline the tops reach full height.
@export var rise_m: float = 1.5:
	set(value):
		rise_m = value
		_rebuild()
# Each lobe's top up or down by up to this, metres.
@export var top_jitter_m: float = 0.25:
	set(value):
		top_jitter_m = value
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
# How far the lowest lobes sink under the relief.
@export var sink_m: float = 0.2:
	set(value):
		sink_m = value
		_rebuild()
@export_group("")

@export_group("Lobes")
# A lobe's width, metres, from x to y.
@export var lobe_size_m: Vector2 = Vector2(1.5, 3.5):
	set(value):
		lobe_size_m = value
		_rebuild()
# Past band_m in from the outline, lobes this wide instead; band_m 0
# keeps lobe_size_m everywhere.
@export var band_m: float = 0.0:
	set(value):
		band_m = value
		_rebuild()
@export var interior_lobe_size_m: Vector2 = Vector2(3.5, 5.0):
	set(value):
		interior_lobe_size_m = value
		_rebuild()
# Within this of the outline, lobes stack down to the ground under each
# top (the face); deeper, one core lobe does. Below 0: everywhere.
@export var face_depth_m: float = -1.0:
	set(value):
		face_depth_m = value
		_rebuild()
# A site is dropped within this share of the two lobes' mean width of
# one already taken: under 1, lobes overlap.
@export_range(0.3, 1.5) var lobe_spacing: float = 0.75:
	set(value):
		lobe_spacing = value
		_rebuild()
# How far a lobe may reach past the outline, metres.
@export var overhang_m: float = 0.3:
	set(value):
		overhang_m = value
		_rebuild()
# Height over width, from x to y: under 1, flatter than round.
@export var squash_range: Vector2 = Vector2(0.55, 0.8):
	set(value):
		squash_range = value
		_rebuild()
# A lobe's tilt off upright, up to this many degrees.
@export var tilt_degrees: float = 20.0:
	set(value):
		tilt_degrees = value
		_rebuild()
# The shared lobe mesh's spheres: icospheres subdivided this often (1:
# 80 triangles, 2: 320), pushed in and out by this share of a radius.
@export_range(0, 3) var lobe_subdivisions: int = 2:
	set(value):
		lobe_subdivisions = value
		_lobe_mesh = null
		_rebuild()
@export_range(0.0, 0.4) var lobe_lumpiness: float = 0.08:
	set(value):
		lobe_lumpiness = value
		_lobe_mesh = null
		_rebuild()
# Smaller spheres swelling out of each lobe's upper half, and their size
# as a share of its radius: a clump, never one smooth ball.
@export_range(0, 8) var lobe_bumps: int = 5:
	set(value):
		lobe_bumps = value
		_lobe_mesh = null
		_rebuild()
@export_range(0.2, 0.8) var bump_size: float = 0.5:
	set(value):
		bump_size = value
		_lobe_mesh = null
		_rebuild()
@export_group("")

@export_group("Look")
@export var mass_color: Color = Color(0.34, 0.35, 0.3):
	set(value):
		mass_color = value
		_apply_material()
# A lobe's underside this much darker, its top this much lighter.
@export_range(0.0, 0.5) var underside_shade: float = 0.22:
	set(value):
		underside_shade = value
		_lobe_mesh = null
		_rebuild()
@export_range(0.0, 0.3) var top_light: float = 0.1:
	set(value):
		top_light = value
		_lobe_mesh = null
		_rebuild()
# Each lobe's value up or down by up to this share.
@export_range(0.0, 0.2) var tint_jitter: float = 0.07:
	set(value):
		tint_jitter = value
		_rebuild()
@export var cast_shadow: bool = true:
	set(value):
		cast_shadow = value
		if _instance != null:
			_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"

var _ground: Ground = null
var _instance: MultiMeshInstance3D = null
var _material: StandardMaterial3D = null
var _lobe_mesh: ArrayMesh = null
var _lobe_triangles: int = 0
var _build_msec: int = 0
var _lobe_count: int = 0

func _ready() -> void:
	var ground: Ground = _get_ground()
	if ground != null and not ground.relief_rebuilt.is_connected(_rebuild):
		ground.relief_rebuilt.connect(_rebuild)
	_rebuild()

func _get_ground() -> Ground:
	if _ground == null and is_inside_tree():
		_ground = get_node_or_null(ground_path) as Ground
	return _ground

# Milliseconds the last build took, and how many lobes it stood.
func get_build_msec() -> int:
	return _build_msec

func get_lobe_count() -> int:
	return _lobe_count

func _rebuild() -> void:
	if not is_inside_tree() or mask == null or not rect.has_area():
		return
	var ground: Ground = _get_ground()
	if ground == null:
		push_warning("MaskMass '%s': ground_path did not resolve to a Ground; not built." % name)
		return
	if not ground.is_built():
		return
	var started: int = Time.get_ticks_msec()
	var step: float = maxf(cell_m, 0.1)
	var cols: int = ceili(rect.size.x / step)
	var rows: int = ceili(rect.size.y / step)
	var count: int = cols * rows
	var inside := PackedByteArray()
	inside.resize(count)
	var any: bool = false
	for row in rows:
		for col in cols:
			var on_ground: Vector3 = ground.to_local(to_global(_cell_point(col, row, step)))
			var is_in: bool = ground.get_canvas_painting_at(mask, Vector2(on_ground.x, on_ground.z)) >= 0.5
			inside[row * cols + col] = 1 if is_in else 0
			any = any or is_in
	if not any:
		push_warning("MaskMass '%s': no part of its mask lies inside rect; not built." % name)
		return
	var depth: PackedFloat32Array = _depth_in(inside, cols, rows, step)
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	var noise := FastNoiseLite.new()
	noise.seed = layout_seed
	noise.frequency = 1.0 / maxf(noise_wavelength_m, 0.1)
	# Every inside cell once, deepest first (give or take a little), so the
	# middle's big lobes stand before the outline's small ones can crowd
	# them out.
	var ranked: Array[Vector2] = []
	for i in count:
		if inside[i] == 1:
			ranked.append(Vector2(depth[i] + rng.randf() * step * 2.0, i))
	ranked.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x > b.x)
	var order: Array[int] = []
	for entry in ranked:
		order.append(int(entry.y))
	# Taken sites by a coarse grid, for the spacing test.
	var largest: float = maxf(lobe_size_m.y, interior_lobe_size_m.y if band_m > 0.0 else 0.0)
	var bucket: float = maxf(largest * lobe_spacing, step)
	var buckets: Dictionary[Vector2i, PackedVector3Array] = {}
	var transforms: Array[Transform3D] = []
	var shades := PackedFloat32Array()
	for i in order:
		var col: int = i % cols
		var row: int = i / cols
		var at: Vector3 = _cell_point(col, row, step) + Vector3(rng.randf_range(-0.5, 0.5) * step, 0.0, rng.randf_range(-0.5, 0.5) * step)
		var d: float = depth[i]
		var sizes: Vector2 = interior_lobe_size_m if band_m > 0.0 and d > band_m else lobe_size_m
		var radius: float = minf(rng.randf_range(sizes.x, sizes.y) * 0.5, d + overhang_m)
		if radius < sizes.x * 0.25:
			continue
		var key := Vector2i(floori(at.x / bucket), floori(at.z / bucket))
		# Crowded at its width, it tries a narrower lobe before giving up.
		var fits: bool = false
		for share: float in [1.0, 0.75]:
			if radius * share < sizes.x * 0.25:
				break
			if not _crowded(buckets, key, at, radius * share):
				radius *= share
				fits = true
				break
		if not fits:
			continue
		var taken: PackedVector3Array = buckets.get(key, PackedVector3Array())
		taken.append(Vector3(at.x, radius, at.z))
		buckets[key] = taken
		var floor_y: float = _floor_y(ground, at)
		var full: float = lerpf(height_range_m.x, height_range_m.y, clampf(noise.get_noise_2d(at.x, at.z) * 0.5 + 0.5, 0.0, 1.0))
		var top: float = lerpf(edge_height_m, full, smoothstep(0.0, maxf(rise_m, 0.01), d)) + rng.randf_range(-top_jitter_m, top_jitter_m)
		top = maxf(top, 0.3)
		var squash: float = rng.randf_range(squash_range.x, squash_range.y)
		var tall: float = radius * squash
		var shade: float = 1.0 + rng.randf_range(-tint_jitter, tint_jitter)
		transforms.append(_lobe(rng, Vector3(at.x, floor_y + top - tall, at.z), radius, tall))
		shades.append(shade)
		var bottom: float = top - 2.0 * tall
		if bottom <= 0.0:
			continue
		if face_depth_m < 0.0 or d <= face_depth_m:
			# The face: lobes stacked down into the ground, each a little
			# wider and darker than the one over it.
			# Each keeps its own squash; the last sinks as deep as it must.
			var level_top: float = top - tall * 1.2
			var level: int = 1
			while level_top > 0.0 and level < 6:
				var r: float = minf(radius * rng.randf_range(0.9, 1.1), d + overhang_m)
				var t: float = r * rng.randf_range(squash_range.x, squash_range.y)
				var shift := Vector2(rng.randf_range(-0.35, 0.35), rng.randf_range(-0.35, 0.35)) * radius
				transforms.append(_lobe(rng, Vector3(at.x + shift.x, floor_y + level_top - t, at.z + shift.y), r, t))
				shades.append(shade * (1.0 - 0.08 * level))
				level_top -= t * 1.6
				level += 1
		else:
			# Deeper in: one core lobe under the top, ground to its middle.
			var core: float = (bottom + sink_m) * 0.5 + tall * 0.5
			transforms.append(_lobe(rng, Vector3(at.x, floor_y - sink_m + core, at.z), radius * 0.8, core))
			shades.append(shade * 0.85)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = _get_lobe_mesh()
	multimesh.instance_count = transforms.size()
	for k in transforms.size():
		multimesh.set_instance_transform(k, transforms[k])
		multimesh.set_instance_color(k, Color(shades[k], shades[k], shades[k]))
	if _instance == null:
		_instance = MultiMeshInstance3D.new()
		_instance.name = "Mass"
		add_child(_instance)
	_instance.multimesh = multimesh
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_apply_material()
	_lobe_count = transforms.size()
	_build_msec = Time.get_ticks_msec() - started
	print("MaskMass '%s': %d lobes (%d triangles) in %d ms" % [name, _lobe_count, _lobe_count * _lobe_triangles, _build_msec])

# Whether a lobe `radius` wide at `at` comes closer than lobe_spacing of
# the two widths to one already taken (`key` its bucket).
func _crowded(buckets: Dictionary[Vector2i, PackedVector3Array], key: Vector2i, at: Vector3, radius: float) -> bool:
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for other: Vector3 in buckets.get(key + Vector2i(dx, dz), PackedVector3Array()):
				if Vector2(at.x - other.x, at.z - other.z).length() < (radius + other.y) * lobe_spacing:
					return true
	return false

# A cell's centre, this node's XZ.
func _cell_point(col: int, row: int, step: float) -> Vector3:
	return Vector3(rect.position.x + (col + 0.5) * step, 0.0, rect.position.y + (row + 0.5) * step)

# The relief under a point of this node's XZ, as this node's Y.
func _floor_y(ground: Ground, at: Vector3) -> float:
	var on_ground: Vector3 = ground.to_local(to_global(at))
	return to_local(ground.to_global(Vector3(on_ground.x, ground.get_height_at(Vector2(on_ground.x, on_ground.z)), on_ground.z))).y

# A lobe `radius` wide and `tall` high (half-extents) centred at `centre`:
# turned any way about up, tipped up to tilt_degrees, a little longer one
# way than the other.
func _lobe(rng: RandomNumberGenerator, centre: Vector3, radius: float, tall: float) -> Transform3D:
	var yaw := Basis(Vector3.UP, rng.randf() * TAU)
	var lean_turn: float = rng.randf() * TAU
	var lean_axis := Vector3(cos(lean_turn), 0.0, sin(lean_turn))
	var lean := Basis(lean_axis, deg_to_rad(rng.randf_range(-tilt_degrees, tilt_degrees)))
	var stretch: float = rng.randf_range(0.85, 1.15)
	var scale := Basis.from_scale(Vector3(radius * stretch, tall, radius / stretch))
	return Transform3D(lean * yaw * scale, centre)

# The shared lobe: a clump - a unit icosphere with lobe_bumps smaller ones
# (bump_size of its radius) swelling out of its upper half, each gently
# lumpy - its vertex colour darker low on the clump and lighter high on
# it. Built once per look.
func _get_lobe_mesh() -> ArrayMesh:
	if _lobe_mesh != null:
		return _lobe_mesh
	var sphere: Array = _icosphere(lobe_subdivisions)
	var unit: Array[Vector3] = sphere[0]
	var unit_faces: PackedInt32Array = sphere[1]
	var lumps := FastNoiseLite.new()
	lumps.seed = layout_seed + 7919
	lumps.frequency = 0.55
	var shape_rng := RandomNumberGenerator.new()
	shape_rng.seed = layout_seed + 104729
	# Each part: its centre and radius in the lobe's unit frame.
	var parts: Array[Vector4] = [Vector4(0.0, 0.0, 0.0, 1.0)]
	for k in lobe_bumps:
		var turn: float = (float(k) + shape_rng.randf_range(-0.3, 0.3)) / maxf(float(lobe_bumps), 1.0) * TAU
		var rise: float = shape_rng.randf_range(0.15, 0.75)
		var out := Vector3(cos(turn) * sqrt(1.0 - rise * rise), rise, sin(turn) * sqrt(1.0 - rise * rise))
		var size: float = bump_size * shape_rng.randf_range(0.8, 1.15)
		var at: Vector3 = out * (1.0 - size * 0.45)
		parts.append(Vector4(at.x, at.y, at.z, size))
	var points := PackedVector3Array()
	var normals := PackedVector3Array()
	var faces := PackedInt32Array()
	for part: Vector4 in parts:
		var centre := Vector3(part.x, part.y, part.z)
		var base: int = points.size()
		var local_normals := PackedVector3Array()
		local_normals.resize(unit.size())
		var local_points := PackedVector3Array()
		local_points.resize(unit.size())
		for i in unit.size():
			var bump: float = 1.0 + lobe_lumpiness * lumps.get_noise_3dv(centre * 3.0 + unit[i])
			local_points[i] = centre + unit[i] * part.w * bump
		for f in range(0, unit_faces.size(), 3):
			var n: Vector3 = (local_points[unit_faces[f + 2]] - local_points[unit_faces[f]]).cross(local_points[unit_faces[f + 1]] - local_points[unit_faces[f]])
			for k in 3:
				local_normals[unit_faces[f + k]] += n
		for i in unit.size():
			points.append(local_points[i])
			normals.append(local_normals[i].normalized())
		for f: int in unit_faces:
			faces.append(base + f)
	# Darker low on the clump, lighter high on it, by the clump's own extent.
	var low: float = INF
	var high: float = -INF
	for point: Vector3 in points:
		low = minf(low, point.y)
		high = maxf(high, point.y)
	var colors := PackedColorArray()
	colors.resize(points.size())
	for i in points.size():
		var up: float = (points[i].y - low) / maxf(high - low, 0.001) * 2.0 - 1.0
		var value: float = 1.0 + top_light * maxf(up, 0.0) - underside_shade * maxf(-up, 0.0)
		colors[i] = Color(value, value, value)
	# The clump fills its unit box, as one sphere would.
	var reach: float = 0.0
	for point: Vector3 in points:
		reach = maxf(reach, maxf(absf(point.x), maxf(absf(point.z), absf(point.y))))
	for i in points.size():
		points[i] /= maxf(reach, 0.001)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = faces
	_lobe_mesh = ArrayMesh.new()
	_lobe_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_lobe_triangles = faces.size() / 3
	return _lobe_mesh

# A unit icosphere subdivided `subdivisions` times: [points, faces].
static func _icosphere(subdivisions: int) -> Array:
	var t: float = (1.0 + sqrt(5.0)) * 0.5
	# An Array, not a packed one: _midpoint() grows it in place.
	var points: Array[Vector3] = [
		Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1),
	]
	for i in points.size():
		points[i] = points[i].normalized()
	var faces := PackedInt32Array([
		0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
		1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
		4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
	])
	for _pass in subdivisions:
		var midpoints: Dictionary[Vector2i, int] = {}
		var finer := PackedInt32Array()
		for f in range(0, faces.size(), 3):
			var a: int = faces[f]
			var b: int = faces[f + 1]
			var c: int = faces[f + 2]
			var ab: int = _midpoint(points, midpoints, a, b)
			var bc: int = _midpoint(points, midpoints, b, c)
			var ca: int = _midpoint(points, midpoints, c, a)
			finer.append_array(PackedInt32Array([a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]))
		faces = finer
	return [points, faces]

static func _midpoint(points: Array[Vector3], midpoints: Dictionary[Vector2i, int], a: int, b: int) -> int:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if midpoints.has(key):
		return midpoints[key]
	points.append(((points[a] + points[b]) * 0.5).normalized())
	midpoints[key] = points.size() - 1
	return points.size() - 1

# Metres from each inside cell to the nearest outside one (0 outside), by
# a two-pass chamfer over the grid - near enough Euclidean for sizing
# lobes and easing the tops over a metre or two.
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
	# A grid with no outside cell at all: deep everywhere.
	for i in depth.size():
		if is_inf(depth[i]):
			depth[i] = 1000.0
	return depth

func _apply_material() -> void:
	if _instance == null:
		return
	if _material == null:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		_material.vertex_color_use_as_albedo = true
		# Both faces: where the ground cuts a sunk lobe, its inside shows
		# rather than the sand through it.
		_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = mass_color
	_instance.material_override = _material
