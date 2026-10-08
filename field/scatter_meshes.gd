extends RefCounted
class_name ScatterMeshes

# The model each ScatterEntry is drawn with (FieldScatter): its glb - the
# entry's mesh_path, else assets/models/props/scatter/<name>.glb when that
# file exists - or, until one does, a placeholder made here, at real size:
#   CAST         a lugworm cast: a low loose coil of thin tube, ~7 cm
#                across, ~1.5 cm high
#   SHELL        a shallow ribbed cup, ~4 cm, convex up
#   STONE_ROUND  a smooth flattened ellipsoid
#   STONE_FLAT   a flatter, longer one
#   STRAND       a strand of dried seaweed: a thin flattened ribbon, ~35 cm
#                long, ~4.5 cm wide, 1 cm high, slightly curved, its ends
#                tapering - lying along its length on X (a tideline turns
#                it along the line)
#   TWIG         a tiny twig: a thin rod, ~10 cm, slightly bent, along X
# Every mesh has smooth normals - a glb that arrives without any (Meshy's
# samphire carries positions only) gets them generated here. One mesh per
# path or kind, shared by every floor.

const SCATTER_MODEL_DIR := "res://assets/models/props/scatter"

static var _cache: Dictionary = {}

# The mesh for `entry`, and whether it is the placeholder.
static func mesh_for(entry: ScatterEntry) -> Mesh:
	var path: String = model_path_for(entry)
	var key: String = path if not path.is_empty() else "placeholder:%d" % entry.placeholder
	if _cache.has(key):
		return _cache[key]
	var mesh: Mesh = _load_glb_mesh(path) if not path.is_empty() else null
	if mesh == null:
		mesh = placeholder(entry.placeholder)
	_cache[key] = mesh
	return mesh

# The glb `entry` is drawn with, or "" for its placeholder.
static func model_path_for(entry: ScatterEntry) -> String:
	if not entry.mesh_path.is_empty() and ResourceLoader.exists(entry.mesh_path):
		return entry.mesh_path
	var by_name: String = "%s/%s.glb" % [SCATTER_MODEL_DIR, entry.name]
	if not entry.name.is_empty() and ResourceLoader.exists(by_name):
		return by_name
	return ""

# The first mesh in the glb, its node's transform baked in, with normals.
static func _load_glb_mesh(path: String) -> Mesh:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("ScatterMeshes: '%s' didn't load; using the placeholder." % path)
		return null
	var root: Node = scene.instantiate()
	var found: MeshInstance3D = null
	for node in root.find_children("*", "MeshInstance3D", true, false):
		if (node as MeshInstance3D).mesh != null:
			found = node as MeshInstance3D
			break
	if found == null:
		root.free()
		push_warning("ScatterMeshes: no mesh in '%s'; using the placeholder." % path)
		return null
	var baked := Transform3D.IDENTITY
	var node: Node = found
	while node != null and node != root:
		if node is Node3D:
			baked = (node as Node3D).transform * baked
		node = node.get_parent()
	var tool := SurfaceTool.new()
	tool.create_from(found.mesh, 0)
	var arrays: Array = tool.commit_to_arrays()
	root.free()
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	var has_normals: bool = normals is PackedVector3Array and not (normals as PackedVector3Array).is_empty() and (normals as PackedVector3Array)[0] != Vector3.ZERO
	tool = SurfaceTool.new()
	tool.create_from_arrays(arrays)
	if not baked.is_equal_approx(Transform3D.IDENTITY):
		var mesh_baked: ArrayMesh = tool.commit()
		tool = SurfaceTool.new()
		tool.append_from(mesh_baked, 0, baked)
	if not has_normals:
		tool.generate_normals()
		print("ScatterMeshes: '%s' has no normals; generated." % path)
	else:
		print("ScatterMeshes: '%s' brings its own normals." % path)
	return tool.commit()

static func placeholder(kind: ScatterEntry.PlaceholderKind) -> Mesh:
	match kind:
		ScatterEntry.PlaceholderKind.SHELL:
			return _shell()
		ScatterEntry.PlaceholderKind.STONE_ROUND:
			return _stone(Vector3(1.0, 0.45, 0.78), 11)
		ScatterEntry.PlaceholderKind.STONE_FLAT:
			return _stone(Vector3(1.0, 0.32, 0.62), 23)
		ScatterEntry.PlaceholderKind.STRAND:
			return _strand()
		ScatterEntry.PlaceholderKind.TWIG:
			return _twig()
	return _cast()

# A thin tube wound in a loose, low coil - a lugworm's cast: 1.7 turns,
# opening out from the middle, rising a little over each turn it laps.
static func _cast() -> Mesh:
	var tube_radius: float = 0.0042
	var sides: int = 6
	var steps: int = 56
	var turns: float = 1.7
	var path := PackedVector3Array()
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var angle: float = t * turns * TAU
		var radius: float = lerpf(0.006, 0.03, sqrt(t))
		var lift: float = tube_radius + 0.0035 * (1.0 - t) + 0.0012 * sin(angle * 2.0)
		path.append(Vector3(cos(angle) * radius, lift, sin(angle) * radius))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for i in path.size():
		var ahead: Vector3 = path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]
		ahead = ahead.normalized()
		var side: Vector3 = ahead.cross(Vector3.UP).normalized()
		var up: Vector3 = side.cross(ahead).normalized()
		# The ends taper shut.
		var t: float = float(i) / float(steps)
		var taper: float = clampf(minf(t, 1.0 - t) * 10.0, 0.25, 1.0)
		var ring := PackedVector3Array()
		for s in sides:
			var a: float = float(s) / float(sides) * TAU
			ring.append(path[i] + (side * cos(a) + up * sin(a)) * tube_radius * taper)
		rings.append(ring)
	for i in rings.size() - 1:
		for s in sides:
			var n: int = (s + 1) % sides
			_quad(tool, rings[i][s], rings[i + 1][s], rings[i + 1][n], rings[i][n], (path[i] + path[i + 1]) * 0.5)
	tool.generate_normals()
	return tool.commit()

# A shallow cup, dome up, ribbed from the hinge out, its underside closed
# flat - about 4 cm across, 1 cm high.
static func _shell() -> Mesh:
	var radius: float = 0.02
	var height: float = 0.01
	var ribs: float = 14.0
	var rings: int = 6
	var segments: int = 28
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid: Array[PackedVector3Array] = []
	for r in rings + 1:
		var u: float = float(r) / float(rings)
		var ring := PackedVector3Array()
		for s in segments:
			var a: float = float(s) / float(segments) * TAU
			var rib: float = 1.0 + 0.05 * cos(a * ribs) * u
			# Slightly longer than wide, the hinge end blunt.
			var reach: float = radius * u * rib * (1.0 + 0.12 * cos(a))
			ring.append(Vector3(cos(a) * reach * 0.88, height * (1.0 - u * u), sin(a) * reach))
		grid.append(ring)
	# The dome faces away from a point under it, the floor from one above.
	var under := Vector3(0.0, -height, 0.0)
	var over := Vector3(0.0, height * 2.0, 0.0)
	var top := Vector3(0.0, height, 0.0)
	for s in segments:
		var n: int = (s + 1) % segments
		_tri(tool, top, grid[1][n], grid[1][s], under)
	for r in range(1, rings):
		for s in segments:
			var n: int = (s + 1) % segments
			_quad(tool, grid[r][s], grid[r][n], grid[r + 1][n], grid[r + 1][s], under)
	for s in segments:
		var n: int = (s + 1) % segments
		_tri(tool, Vector3.ZERO, grid[rings][s], grid[rings][n], over)
	tool.generate_normals()
	return tool.commit()

# A smooth ellipsoid, `axes` times 10 cm across / high / deep (thinnest
# up - its flattest side down), a little uneven by `variant` so the two
# differ.
static func _stone(axes: Vector3, variant: int) -> Mesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = variant
	var lat: int = 8
	var lon: int = 14
	var bumps := PackedFloat32Array()
	for i in 4:
		bumps.append(rng.randf_range(-0.07, 0.07))
	var grid: Array[PackedVector3Array] = []
	for y in lat + 1:
		var v: float = float(y) / float(lat)
		var phi: float = v * PI
		var ring := PackedVector3Array()
		for x in lon:
			var theta: float = float(x) / float(lon) * TAU
			var wobble: float = 1.0 + bumps[0] * cos(theta * 2.0) + bumps[1] * sin(theta * 3.0) + bumps[2] * cos(phi * 2.0) + bumps[3] * sin(theta + phi)
			var p := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta)) * wobble
			ring.append(Vector3(p.x * axes.x, (p.y + 1.0) * axes.y, p.z * axes.z) * 0.05)
		grid.append(ring)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in lat:
		for x in lon:
			var n: int = (x + 1) % lon
			_quad(tool, grid[y][x], grid[y][n], grid[y + 1][n], grid[y + 1][x], Vector3(0.0, axes.y * 0.05, 0.0))
	tool.generate_normals()
	return tool.commit()

# A dried strand: a flattened ribbon along X, bowed a little sideways,
# widest and thickest in the middle and tapering to its ends, closed at
# both. Its cross-section is a flat box: top, bottom and two thin
# edges.
static func _strand() -> Mesh:
	var length: float = 0.35
	var width: float = 0.045
	var thickness: float = 0.01
	var bow: float = 0.03
	var stations: int = 14
	var rings: Array[PackedVector3Array] = []
	var centres := PackedVector3Array()
	for i in stations + 1:
		var t: float = float(i) / float(stations)
		var x: float = (t - 0.5) * length
		var swell: float = sin(t * PI)
		var half_width: float = width * 0.5 * (0.3 + 0.7 * swell)
		var half_height: float = thickness * 0.5 * (0.4 + 0.6 * swell)
		var z: float = bow * (1.0 - pow(2.0 * t - 1.0, 2.0))
		var centre := Vector3(x, half_height, z)
		centres.append(centre)
		var ring := PackedVector3Array()
		ring.append(centre + Vector3(0.0, half_height, -half_width))
		ring.append(centre + Vector3(0.0, half_height, half_width))
		ring.append(centre + Vector3(0.0, -half_height, half_width))
		ring.append(centre + Vector3(0.0, -half_height, -half_width))
		rings.append(ring)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in stations:
		for side in 4:
			var n: int = (side + 1) % 4
			_quad(tool, rings[i][side], rings[i + 1][side], rings[i + 1][n], rings[i][n], (centres[i] + centres[i + 1]) * 0.5)
	# The ends, closed - faced away from the strand's middle.
	_quad(tool, rings[0][0], rings[0][1], rings[0][2], rings[0][3], centres[1])
	_quad(tool, rings[stations][0], rings[stations][1], rings[stations][2], rings[stations][3], centres[stations - 1])
	tool.generate_normals()
	return tool.commit()

# A tiny twig: a thin rod along X, bent a little, its ends closed.
static func _twig() -> Mesh:
	var length: float = 0.1
	var radius: float = 0.003
	var sides: int = 5
	var stations: int = 6
	var rings: Array[PackedVector3Array] = []
	var centres := PackedVector3Array()
	for i in stations + 1:
		var t: float = float(i) / float(stations)
		var centre := Vector3((t - 0.5) * length, radius, 0.008 * sin(t * PI))
		centres.append(centre)
		var ring := PackedVector3Array()
		for s in sides:
			var a: float = float(s) / float(sides) * TAU
			ring.append(centre + Vector3(0.0, sin(a), cos(a)) * radius * (1.0 - 0.3 * t))
		rings.append(ring)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in stations:
		for s in sides:
			var n: int = (s + 1) % sides
			_quad(tool, rings[i][s], rings[i + 1][s], rings[i + 1][n], rings[i][n], (centres[i] + centres[i + 1]) * 0.5)
	for s in range(1, sides - 1):
		_tri(tool, rings[0][0], rings[0][s], rings[0][s + 1], centres[1])
		_tri(tool, rings[stations][0], rings[stations][s], rings[stations][s + 1], centres[stations - 1])
	tool.generate_normals()
	return tool.commit()

# One triangle, wound so its front - the side SurfaceTool.generate_
# normals() points its normal to, Plane(a, b, c) - faces away from
# `inside`, whichever order the corners came in.
static func _tri(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, inside: Vector3) -> void:
	var facing: Vector3 = Plane(a, b, c).normal
	if facing.dot((a + b + c) / 3.0 - inside) < 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	tool.add_vertex(a)
	tool.add_vertex(b)
	tool.add_vertex(c)

# A quad a-b-c-d as two triangles, facing away from `inside`.
static func _quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, inside: Vector3) -> void:
	_tri(tool, a, b, c, inside)
	_tri(tool, a, c, d, inside)
