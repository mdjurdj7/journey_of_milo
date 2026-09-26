extends MeshInstance3D
class_name SandMound

# The swell of sand over a buried body (the Siltjaw): made by FieldEnemy
# for a body whose rest height is under the sand, a child of the body,
# and all that shows of it while it is down - FieldEnemy hides the model
# and its contact shadow until it surfaces. It should read as the ground
# rising, not as something lying on it.
#
# The shape is a low, broad dome, its crest crest_fraction of the way
# back from the front (the body's facing, local -Z), over an egg-shaped
# footprint. The profile is a raised cosine raised to falloff_power: at
# 1 the plain bell, and above it the outer part flattens out - at the
# default 2 the outer third rises less than 7% of the height, with no
# slope to speak of, so there is no edge to trace. The length is centred
# on the body's origin, forward_offset_m toward the front.
#
# It is built procedurally, like DragonflyWings' quads, in WORLD space:
# the node is top_level, so a fight's recoil or lunge never drags the
# sand with the body. Each vertex is the sand as drawn under it
# (Ground.get_visible_height_at() - the relief mesh's own triangles; the
# analytic get_height_at() stands up to a few centimetres off them on
# the hill's lifted face) plus the bell, so the mound lies on whatever
# the sand does under it, and its rim IS the sand: the profile is
# tangent to it there. That tangency is what hides the edge - drawn
# through the ground's own shader the mound has no colour of its own, so
# only its slope can outline it, and a rim sunk even 1 cm under the sand
# crossed it where the bell was still steep enough to catch the light.
# A rim at the ground's height fights it for the pixel, but both are the
# same shader at the same XZ - a fight between identical colours.
# rim_sink_m (0) and rim_band are kept for a floor where that shows.
#
# The sand is sampled once, when FieldEnemy first grounds the body where
# it was placed (resample()), and again only if the relief itself is
# rebuilt (a live terrain edit) or a shape export changes - the body
# never moves in the field, and a fight's lunge, recoil or turn is not
# the mound's to follow. A rise change only rescales the cached sample.
#
# set_rise() is the whole of its motion: 1 = full height, 0 = flattened
# into the sand and hidden. FieldEnemy drives it from the same lift its
# model rises on (_apply_model_lift()), so the sand falls away exactly as
# the body comes up through it, and swells back as it goes under.
#
# Colour: drawn with the ground's own material (Ground.get_sand_material(),
# the one instance its uniforms go to), so every vertex takes the tint,
# grain, speckle, wetness and wear of the sand at its XZ and height, live.
# The one dark mark is the crack along the crest: a broken line of short
# segments with gaps, each tapering to a point and wandering a little
# off the spine, laid crack_raise_m over the surface as thin strips of
# the same mesh. They darken themselves through vertex colour, which
# ground.gdshader multiplies into its final albedo (white everywhere
# else) - sand cracked open, not a moulded seam. Laid out from
# crack_seed, so the same mound always cracks the same way.

@export_group("Shape")
@export var length_m: float = 4.0:
	set(value):
		length_m = value
		_rebuild_grid()
@export var width_m: float = 2.2:
	set(value):
		width_m = value
		_rebuild_grid()
@export var height_m: float = 0.22:
	set(value):
		height_m = value
		_write_mesh()
# The profile's power on the raised cosine: 1 = the plain bell; higher
# flattens the outer part further (see the header).
@export_range(1.0, 4.0, 0.05) var falloff_power: float = 2.0:
	set(value):
		falloff_power = value
		_rebuild_grid()
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
# How far under the sand the rim sits. 0 = on it, tangent (see the
# header for why that is the default).
@export var rim_sink_m: float = 0.0:
	set(value):
		rim_sink_m = value
		_write_mesh()
# The outer fraction of the way from crest to rim over which it dips to
# rim_sink_m - inside that it stands on the sand, the bell alone.
@export_range(0.01, 0.5, 0.01) var rim_band: float = 0.3:
	set(value):
		rim_band = value
		_rebuild_grid()

@export_group("Crack")
# How much of the length the crack runs, centred on the crest.
@export_range(0.05, 1.0, 0.01) var crack_extent: float = 0.5:
	set(value):
		crack_extent = value
		_rebuild_grid()
# Each segment at its widest; it tapers to a point at both ends, and its
# darkness fades from the middle out to its edges.
@export var crack_width_m: float = 0.04:
	set(value):
		crack_width_m = value
		_rebuild_grid()
# Its darkest, as a multiplier on the sand in display (sRGB) terms - 0.35
# is the sand at 35% of its shown value.
@export_range(0.0, 1.0, 0.01) var crack_shade: float = 0.35:
	set(value):
		crack_shade = value
		_write_mesh()
# Each segment's length and each gap's, rolled between these.
@export var crack_segment_min_m: float = 0.12:
	set(value):
		crack_segment_min_m = value
		_rebuild_grid()
@export var crack_segment_max_m: float = 0.32:
	set(value):
		crack_segment_max_m = value
		_rebuild_grid()
@export var crack_gap_min_m: float = 0.06:
	set(value):
		crack_gap_min_m = value
		_rebuild_grid()
@export var crack_gap_max_m: float = 0.2:
	set(value):
		crack_gap_max_m = value
		_rebuild_grid()
# How far a segment may wander off the spine, either side.
@export var crack_wobble_m: float = 0.025:
	set(value):
		crack_wobble_m = value
		_rebuild_grid()
# Over the surface, so the strips never fight the dome under them.
@export var crack_raise_m: float = 0.004:
	set(value):
		crack_raise_m = value
		_write_mesh()
@export var crack_seed: int = 3:
	set(value):
		crack_seed = value
		_rebuild_grid()

@export_group("Mesh")
@export var segments_long: int = 40:
	set(value):
		segments_long = value
		_rebuild_grid()
# Per side, evenly from the spine out to the rim.
@export var segments_across: int = 14:
	set(value):
		segments_across = value
		_rebuild_grid()
# The crack's strips take a step this often along their length.
@export var crack_step_m: float = 0.04:
	set(value):
		crack_step_m = value
		_rebuild_grid()

var _ground: Ground = null
var _rise: float = 1.0
var _ready_done: bool = false
# Every vertex in the body's frame - the dome's grid first, row by row
# from the front, then the crack's strips: its local XZ, its bell (0..1),
# how far into the rim's dip it is (0..1), how dark it is (0..1 of the
# crack's shade) and whether it rides crack_raise_m over the surface;
# the triangles over them.
var _local_xz: PackedVector2Array = PackedVector2Array()
var _bell: PackedFloat32Array = PackedFloat32Array()
var _dip: PackedFloat32Array = PackedFloat32Array()
var _dark: PackedFloat32Array = PackedFloat32Array()
var _raised: PackedFloat32Array = PackedFloat32Array()
var _indices: PackedInt32Array = PackedInt32Array()
# The sample: each vertex's world XZ and the sand's world Y there.
var _world_xz: PackedVector2Array = PackedVector2Array()
var _ground_y: PackedFloat32Array = PackedFloat32Array()
var _sampled: bool = false

func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mesh = ArrayMesh.new()
	_ready_done = true
	_rebuild_grid()

# The sand it lies on - FieldEnemy hands over its own Ground, and the
# mound is drawn with that ground's material from here on. Nothing is
# sampled until resample().
func set_ground(ground: Ground) -> void:
	_ground = ground
	material_override = ground.get_sand_material() if ground != null else null

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

# The dome at a local XZ: r, 0 at the crest out to 1 on the rim, over the
# egg-shaped footprint - t runs 0 at the crest to 1 at either end along
# the length, and the row's half-width shrinks with it.
func _radius_at(local: Vector2) -> float:
	var length: float = maxf(length_m, 0.01)
	var crest: float = clampf(crest_fraction, 0.05, 0.95)
	var s: float = clampf((local.y + forward_offset_m + length * 0.5) / length, 0.0, 1.0)
	var t: float = (crest - s) / crest if s < crest else (s - crest) / (1.0 - crest)
	var row_half: float = maxf(width_m, 0.01) * 0.5 * sqrt(maxf(1.0 - t * t, 0.0))
	var a: float = clampf(absf(local.x) / row_half, 0.0, 1.0) if row_half > 0.0001 else 1.0
	return sqrt(minf(t * t + a * a * (1.0 - t * t), 1.0))

func _bell_at(r: float) -> float:
	return pow(0.5 + 0.5 * cos(PI * r), maxf(falloff_power, 1.0))

func _add_vertex(local: Vector2, dark: float, raised: float) -> void:
	var r: float = _radius_at(local)
	_local_xz.append(local)
	_bell.append(_bell_at(r))
	_dip.append(smoothstep(1.0 - clampf(rim_band, 0.01, 0.5), 1.0, r))
	_dark.append(dark)
	_raised.append(raised)

# A strip of quads from rows of `cols` vertices starting at `first`:
# rows run from the front (-Z) back, each across from -X to +X - the
# relief mesh's own order, so the same winding faces up (see
# Ground._build_relief_indices()).
func _add_quads(first: int, rows: int, cols: int) -> void:
	for row in rows - 1:
		for col in cols - 1:
			var top_left: int = first + row * cols + col
			var top_right: int = top_left + 1
			var bottom_left: int = top_left + cols
			var bottom_right: int = bottom_left + 1
			_indices.append_array(PackedInt32Array([top_left, top_right, bottom_left, top_right, bottom_right, bottom_left]))

# The dome's grid, then the crack. Grid columns are even fractions of the
# row's half-width, so every row ends on the rim and the two end rows
# close to a point.
func _rebuild_grid() -> void:
	if not _ready_done:
		return
	_local_xz.clear()
	_bell.clear()
	_dip.clear()
	_dark.clear()
	_raised.clear()
	_indices.clear()

	var rows: int = maxi(segments_long, 2) + 1
	var outer: int = maxi(segments_across, 2)
	var cols: int = outer * 2 + 1
	var length: float = maxf(length_m, 0.01)
	var half_width: float = maxf(width_m, 0.01) * 0.5
	var crest: float = clampf(crest_fraction, 0.05, 0.95)
	var front_z: float = -forward_offset_m - length * 0.5
	for row in rows:
		var s: float = float(row) / float(rows - 1)
		var t: float = (crest - s) / crest if s < crest else (s - crest) / (1.0 - crest)
		var row_half: float = half_width * sqrt(maxf(1.0 - t * t, 0.0))
		for col in cols:
			var a: float = float(col - outer) / float(outer)
			_add_vertex(Vector2(a * row_half, front_z + s * length), 0.0, 0.0)
	_add_quads(0, rows, cols)

	_build_crack(front_z + crest * length, length)

	# A new grid needs its own sample - only once there is sand to take it
	# from (not at _ready(), before FieldEnemy has handed the Ground over).
	_sampled = false
	resample()

# The crack along the crest: from crest_z, crack_extent of the length
# centred on it (clipped to the mound), segments and gaps rolled from
# crack_seed. Each segment is a strip three vertices across - dark down
# its middle, sand at its edges - stepping every crack_step_m, its width
# a sine taper to a point at each end and its line a small random walk
# off the spine, held within crack_wobble_m.
func _build_crack(crest_z: float, length: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = crack_seed
	var front: float = -forward_offset_m - length * 0.5
	var start: float = maxf(crest_z - crack_extent * length * 0.5, front)
	var finish: float = minf(crest_z + crack_extent * length * 0.5, front + length)
	var wobble: float = maxf(crack_wobble_m, 0.0)
	var offset: float = rng.randf_range(-wobble, wobble)
	var z: float = start + rng.randf_range(0.0, maxf(crack_gap_max_m, 0.0))
	while z < finish:
		var segment: float = minf(rng.randf_range(crack_segment_min_m, maxf(crack_segment_max_m, crack_segment_min_m)), finish - z)
		var steps: int = maxi(ceili(segment / maxf(crack_step_m, 0.005)), 2)
		var first: int = _local_xz.size()
		for step in steps + 1:
			var f: float = float(step) / float(steps)
			offset = clampf(offset + rng.randf_range(-1.0, 1.0) * wobble * 0.3, -wobble, wobble)
			var half: float = maxf(crack_width_m, 0.0) * 0.5 * sin(PI * f)
			var along: float = z + f * segment
			_add_vertex(Vector2(offset - half, along), 0.0, 1.0)
			_add_vertex(Vector2(offset, along), 1.0, 1.0)
			_add_vertex(Vector2(offset + half, along), 0.0, 1.0)
		_add_quads(first, steps + 1, 3)
		z += segment + rng.randf_range(crack_gap_min_m, maxf(crack_gap_max_m, crack_gap_min_m))

# The cached sand plus the bell at this rise; hidden once flat.
func _write_mesh() -> void:
	if not _ready_done:
		return
	visible = _rise > 0.0
	var array_mesh := mesh as ArrayMesh
	if array_mesh == null or not _sampled or _rise <= 0.0 or _ground == null:
		return
	var count: int = _world_xz.size()
	# The bell stands on the sand (dipping under it only over the rim band
	# when rim_sink_m is set); as the rise falls the dip spreads inward with
	# it, so a flattening mound sinks rather than lying on the sand.
	var lift: float = maxf(height_m, 0.0) * _rise
	var raise: float = maxf(crack_raise_m, 0.0) * _rise
	var vertices := PackedVector3Array()
	vertices.resize(count)
	for i in count:
		var sink: float = rim_sink_m * lerpf(1.0, _dip[i], _rise)
		vertices[i] = Vector3(_world_xz[i].x, _ground_y[i] + lift * _bell[i] - sink + raise * _raised[i], _world_xz[i].y)

	# Smooth normals, each vertex the sum of its triangles'. This winding
	# faces up with (c - a) x (b - a); a closed end's collapsed triangles
	# add nothing. The crack's strips follow the dome under them, so their
	# own faces give them its slope.
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

	# Multipliers on the shader's own albedo, which is linear: crack_shade
	# is a display-value fraction, so it goes through the sRGB curve first.
	var shade: float = Color(crack_shade, crack_shade, crack_shade).srgb_to_linear().r
	var colours := PackedColorArray()
	colours.resize(count)
	for i in count:
		var multiplier: float = lerpf(1.0, shade, _dark[i])
		colours[i] = Color(multiplier, multiplier, multiplier, 1.0)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colours
	arrays[Mesh.ARRAY_INDEX] = _indices
	array_mesh.clear_surfaces()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
