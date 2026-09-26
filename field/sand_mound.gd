extends MeshInstance3D
class_name SandMound

# The swell of sand over a buried body (the Siltjaw): made by FieldEnemy
# for a body whose rest height is under the sand, a child of the body,
# and all that shows of it while it is down - FieldEnemy hides the model
# and its contact shadow until it surfaces.
#
# The shape is an elongated dome, its crest crest_fraction of the way
# back from the front (the body's facing, local -Z), a raised-cosine bell
# over an egg-shaped footprint: highest at the crest, falling to nothing
# at the rim, flat where it meets the sand at both ends and both sides.
# The length is centred on the body's origin, forward_offset_m toward
# the front.
#
# It is built procedurally, like DragonflyWings' quads, in WORLD space:
# the node is top_level, so a fight's recoil or lunge never drags the
# sand with the body. Each vertex is the sand as drawn under it
# (Ground.get_visible_height_at() - the relief mesh's own triangles; the
# analytic get_height_at() stands up to a few centimetres off them on
# the hill's lifted face, which floated the rim there) plus the bell, so
# the mound lies on whatever the sand does under it, with its rim
# rim_sink_m under the sand all round: a rim at exactly the ground's
# height would fight it for the pixel. The sand is sampled once, when
# FieldEnemy first grounds the body where it was placed (resample()), and
# again only if the relief itself is rebuilt (a live terrain edit) or a
# shape export changes - the body never moves in the field, and a
# fight's lunge, recoil or turn is not the mound's to follow. A rise
# change only rescales the bell over the cached ground.
#
# set_rise() is the whole of its motion: 1 = full height, 0 = flattened
# into the sand and hidden. FieldEnemy drives it from the same lift its
# model rises on (_apply_model_lift()), so the sand falls away exactly as
# the body comes up through it, and swells back as it goes under.
#
# Colour: the ground's own sand (Ground.ground_color, read on every
# build), on the flat matte material the hulls use, with a darker ridge
# down the spine through vertex colour - pale sand with one dark line,
# seen from above. The ridge narrows with the footprint to a point at
# each end.

@export_group("Shape")
@export var length_m: float = 2.5:
	set(value):
		length_m = value
		_rebuild_grid()
@export var width_m: float = 1.2:
	set(value):
		width_m = value
		_rebuild_grid()
@export var height_m: float = 0.45:
	set(value):
		height_m = value
		_write_mesh()
# Where the crest sits, from the front (0) to the back (1).
@export_range(0.05, 0.95, 0.01) var crest_fraction: float = 0.33:
	set(value):
		crest_fraction = value
		_rebuild_grid()
# The length's centre, this far ahead of the body's origin (negative:
# behind it).
@export var forward_offset_m: float = 0.0:
	set(value):
		forward_offset_m = value
		_rebuild_grid()
# How far under the sand the rim sits.
@export var rim_sink_m: float = 0.03:
	set(value):
		rim_sink_m = value
		_write_mesh()

@export_group("Ridge")
# Across the widest point; it narrows with the footprint.
@export var ridge_width_m: float = 0.1:
	set(value):
		ridge_width_m = value
		_rebuild_grid()
# The blend from ridge to sand on each side.
@export var ridge_soft_m: float = 0.03:
	set(value):
		ridge_soft_m = value
		_rebuild_grid()
# The ridge's colour as a multiplier on the sand.
@export_range(0.0, 1.0, 0.01) var ridge_shade: float = 0.6:
	set(value):
		ridge_shade = value
		_write_mesh()

@export_group("Mesh")
@export var segments_long: int = 24:
	set(value):
		segments_long = value
		_rebuild_grid()
# Per side, from the ridge's soft edge out to the rim.
@export var segments_across: int = 8:
	set(value):
		segments_across = value
		_rebuild_grid()
var _ground: Ground = null
var _rise: float = 1.0
var _material: StandardMaterial3D = null
var _ready_done: bool = false
# The grid in the body's frame, row by row from the front: each vertex's
# local XZ, its bell (0..1) and its ridge weight (0..1); the triangles
# over it.
var _cols: int = 0
var _local_xz: PackedVector2Array = PackedVector2Array()
var _bell: PackedFloat32Array = PackedFloat32Array()
var _ridge: PackedFloat32Array = PackedFloat32Array()
var _indices: PackedInt32Array = PackedInt32Array()
# The last sample: each vertex's world XZ and the sand's world Y there,
# and where the body stood and faced when it was taken.
var _world_xz: PackedVector2Array = PackedVector2Array()
var _ground_y: PackedFloat32Array = PackedFloat32Array()
var _sampled: bool = false

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh = ArrayMesh.new()
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.vertex_color_use_as_albedo = true
	# The sand and the ridge are authored in sRGB, like the ground's own.
	_material.vertex_color_is_srgb = true
	_material.albedo_color = Color.WHITE
	material_override = _material
	_ready_done = true
	_rebuild_grid()

# The sand it lies on - FieldEnemy hands over its own Ground. Nothing is
# sampled until resample().
func set_ground(ground: Ground) -> void:
	_ground = ground

# 1 = full height, 0 = flat and hidden. Rescales the cached sample only.
func set_rise(rise: float) -> void:
	var clamped: float = clampf(rise, 0.0, 1.0)
	if is_equal_approx(clamped, _rise):
		return
	_rise = clamped
	_write_mesh()

func get_rise() -> float:
	return _rise

# Samples the sand under the body where it stands and faces now, and
# rebuilds - FieldEnemy calls it when the body is grounded at spawn and
# on a relief rebuild; the shape exports call it through _rebuild_grid().
func resample() -> void:
	if not _ready_done or _ground == null:
		return
	var anchor := get_parent() as Node3D
	if anchor == null:
		return
	_sample(anchor.global_position, anchor.global_rotation.y)
	_write_mesh()

# The body's frame -> world, yaw only: the sand never tilts with a
# recoil.
func _sample(anchor_position: Vector3, anchor_yaw: float) -> void:
	var frame := Transform3D(Basis(Vector3.UP, anchor_yaw), anchor_position)
	var count: int = _local_xz.size()
	_world_xz.resize(count)
	_ground_y.resize(count)
	for i in count:
		var world: Vector3 = frame * Vector3(_local_xz[i].x, 0.0, _local_xz[i].y)
		var on_ground: Vector3 = _ground.to_local(world)
		var height: float = _ground.get_visible_height_at(Vector2(on_ground.x, on_ground.z))
		_world_xz[i] = Vector2(world.x, world.z)
		_ground_y[i] = _ground.to_global(Vector3(on_ground.x, height, on_ground.z)).y
	_sampled = true

# The grid from the shape exports: rows from the front (-Z) to the back,
# each across from -X to +X - the relief mesh's own order, so the same
# winding faces up (see Ground._build_relief_indices()). Columns are
# fractions of the row's half-width, so every row ends on the rim and
# the two end rows close to a point; two columns each side pin the
# ridge's edge and its soft edge.
func _rebuild_grid() -> void:
	if not _ready_done:
		return
	var rows: int = maxi(segments_long, 2) + 1
	var outer: int = maxi(segments_across, 1)
	var half_width: float = maxf(width_m, 0.01) * 0.5
	var ridge_edge: float = clampf(ridge_width_m * 0.5 / half_width, 0.0, 0.9)
	var soft_edge: float = clampf(ridge_edge + maxf(ridge_soft_m, 0.0) / half_width, ridge_edge + 0.01, 0.95)
	# One side's fractions, centre out: 0, the ridge, then the soft edge
	# evenly out to the rim.
	var side: Array[float] = [ridge_edge]
	for k in outer + 1:
		side.append(lerpf(soft_edge, 1.0, float(k) / float(outer)))
	var fractions: Array[float] = []
	for k in range(side.size() - 1, -1, -1):
		fractions.append(-side[k])
	fractions.append(0.0)
	fractions.append_array(side)
	_cols = fractions.size()

	var length: float = maxf(length_m, 0.01)
	var crest: float = clampf(crest_fraction, 0.05, 0.95)
	var front_z: float = -forward_offset_m - length * 0.5
	_local_xz.resize(rows * _cols)
	_bell.resize(rows * _cols)
	_ridge.resize(rows * _cols)
	for row in rows:
		var s: float = float(row) / float(rows - 1)
		# 0 at the crest, 1 at either end.
		var t: float = (crest - s) / crest if s < crest else (s - crest) / (1.0 - crest)
		var row_half: float = half_width * sqrt(maxf(1.0 - t * t, 0.0))
		var z: float = front_z + s * length
		for col in _cols:
			var a: float = fractions[col]
			var r: float = sqrt(minf(t * t + a * a * (1.0 - t * t), 1.0))
			var i: int = row * _cols + col
			_local_xz[i] = Vector2(a * row_half, z)
			_bell[i] = 0.5 + 0.5 * cos(PI * r)
			_ridge[i] = 1.0 if absf(a) <= ridge_edge + 0.0001 else 0.0

	_indices.resize((rows - 1) * (_cols - 1) * 6)
	var n: int = 0
	for row in rows - 1:
		for col in _cols - 1:
			var top_left: int = row * _cols + col
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + _cols
			var bottom_right: int = bottom_left + 1
			_indices[n] = top_left
			_indices[n + 1] = top_right
			_indices[n + 2] = bottom_left
			_indices[n + 3] = top_right
			_indices[n + 4] = bottom_right
			_indices[n + 5] = bottom_left
			n += 6
	# A new grid needs its own sample - only once there is sand to take it
	# from (not at _ready(), before FieldEnemy has handed the Ground over).
	_sampled = false
	resample()

# The cached sand plus the bell at this rise; hidden once flat.
func _write_mesh() -> void:
	if not _ready_done:
		return
	visible = _rise > 0.0
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null or not _sampled or _rise <= 0.0 or _ground == null:
		return
	var count: int = _world_xz.size()
	var lift: float = (maxf(height_m, 0.0) + rim_sink_m) * _rise
	var vertices := PackedVector3Array()
	vertices.resize(count)
	for i in count:
		vertices[i] = Vector3(_world_xz[i].x, _ground_y[i] + lift * _bell[i] - rim_sink_m, _world_xz[i].y)

	# Smooth normals, each vertex the sum of its triangles'. This winding
	# faces up with (c - a) x (b - a); a closed end's collapsed triangles
	# add nothing.
	var normals := PackedVector3Array()
	normals.resize(count)
	for n in range(0, _indices.size(), 3):
		var a: Vector3 = vertices[_indices[n]]
		var b: Vector3 = vertices[_indices[n + 1]]
		var c: Vector3 = vertices[_indices[n + 2]]
		var face: Vector3 = (c - a).cross(b - a)
		for k in 3:
			normals[_indices[n + k]] += face
	for i in count:
		normals[i] = normals[i].normalized() if normals[i].length() > 0.000001 else Vector3.UP

	var sand: Color = _ground.ground_color
	var ridge := Color(sand.r * ridge_shade, sand.g * ridge_shade, sand.b * ridge_shade, 1.0)
	var colours := PackedColorArray()
	colours.resize(count)
	for i in count:
		colours[i] = sand.lerp(ridge, _ridge[i])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = _indices
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
