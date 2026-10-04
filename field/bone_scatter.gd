extends Node3D
class_name BoneScatter

# Old animal bones scattered on the sand where something feeds - floor
# 4's Dunecur stands over them at the mouth of the exit neck, facing them
# (FloorEnemy.face_prop_index). Aged by how they lie, never broken: each
# piece sunk part of its own thickness into the sand and tilted a little,
# its tilt drawn from tilt_seed, so the scatter is the same every load.
#
# Each piece is a kind (skull, long bone, rib, vertebra, pelvis), a place
# - X/Z metres in this node's frame and a yaw, degrees - and a length,
# metres. A kind with a model in model_paths (indexed by PieceKind, ""
# for none) loads that glb, scaled so its longest side is the piece's
# length; without one it is a placeholder built from primitives. Either
# way it takes the project's flat matte material (Hull's shared one,
# roughness 1, no specular) tinted bone_tint - a step darker than the
# sand, the way props are (Art Bible, Props flat-shaded).
#
# No collision: he walks over them. Grounded on the relief piece by
# piece, and again on every relief rebuild, as Hull is.

enum PieceKind { SKULL, LONG_BONE, RIB, VERTEBRA, PELVIS }

@export var ground_path: NodePath = ^"../../Ground"

@export_group("Look")
@export var bone_tint: Color = Color(0.50, 0.485, 0.44):
	set(value):
		bone_tint = value
		if _material != null:
			_material.albedo_color = value
# How much of each piece's own thickness lies under the sand, 0..1.
@export_range(0.0, 1.0) var sink_fraction: float = 0.45:
	set(value):
		sink_fraction = value
		_ground_pieces()
# The most a piece leans off level, degrees, about either of its
# horizontal axes - drawn per piece from tilt_seed.
@export_range(0.0, 45.0) var tilt_degrees: float = 14.0:
	set(value):
		tilt_degrees = value
		_ground_pieces()
@export var tilt_seed: int = 4:
	set(value):
		tilt_seed = value
		_ground_pieces()
@export_group("")

@export_group("Pieces")
# One entry per piece, the three arrays in step.
@export var piece_kinds: Array[PieceKind] = []:
	set(value):
		piece_kinds = value
		_rebuild()
# x, z: metres in this node's frame; y: the piece's yaw, degrees.
@export var piece_places: PackedVector3Array = PackedVector3Array():
	set(value):
		piece_places = value
		_rebuild()
@export var piece_lengths: PackedFloat32Array = PackedFloat32Array():
	set(value):
		piece_lengths = value
		_rebuild()
# A glb per PieceKind, in its order; "" keeps that kind's placeholder.
@export var model_paths: Array[String] = ["", "", "", "", ""]:
	set(value):
		model_paths = value
		_rebuild()
@export_group("")

var _ground: Ground = null
var _material: StandardMaterial3D = null
# One holder per piece, its mesh children seated so the holder's origin
# is the piece's centre - and how thick the piece stands, metres.
var _pieces: Array[Node3D] = []
var _thickness: PackedFloat32Array = PackedFloat32Array()
var _ready_done: bool = false

func _ready() -> void:
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = bone_tint
	_ready_done = true
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("BoneScatter '%s': ground_path did not resolve to a Ground; not grounded." % name)
	else:
		_ground.relief_rebuilt.connect(_ground_pieces)
	_rebuild()

# RegionField's placement for a top-level FloorProp: XZ on the floor, the
# yaw turning the whole scatter. Roll is ignored.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	rotation.y = deg_to_rad(yaw)

func get_piece_count() -> int:
	return _pieces.size()

# Each piece's centre in the world, for a probe or a still.
func get_piece_positions() -> PackedVector3Array:
	var points := PackedVector3Array()
	for piece in _pieces:
		points.append(piece.global_position)
	return points

func _rebuild() -> void:
	if not _ready_done:
		return
	for piece in _pieces:
		piece.queue_free()
	_pieces.clear()
	_thickness.clear()
	var count: int = mini(piece_kinds.size(), mini(piece_places.size(), piece_lengths.size()))
	if count != piece_kinds.size() or count != piece_places.size() or count != piece_lengths.size():
		push_warning("BoneScatter '%s': piece_kinds, piece_places and piece_lengths differ in length; using the first %d." % [name, count])
	for i in count:
		var holder := Node3D.new()
		holder.name = "Piece%d" % i
		add_child(holder)
		var length: float = maxf(piece_lengths[i], 0.01)
		var kind: PieceKind = piece_kinds[i]
		var path: String = model_paths[kind] if kind < model_paths.size() else ""
		var thickness: float = _add_model(holder, path, length) if not path.is_empty() else -1.0
		if thickness < 0.0:
			thickness = _add_placeholder(holder, kind, length)
		for node in holder.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.material_override = _material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_pieces.append(holder)
		_thickness.append(thickness)
	_ground_pieces()

# A glb scaled so its longest side is `length`, its bbox centred on the
# holder. Its thickness, or -1 when it won't load.
func _add_model(holder: Node3D, path: String, length: float) -> float:
	var scene := load(path) as PackedScene
	if scene == null:
		push_warning("BoneScatter: could not load %s; a placeholder instead." % path)
		return -1.0
	var model := scene.instantiate() as Node3D
	holder.add_child(model)
	var box: AABB = AABB()
	var first: bool = true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var piece_box: AABB = (model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		box = piece_box if first else box.merge(piece_box)
		first = false
	var longest: float = maxf(box.get_longest_axis_size(), 0.0001)
	var scale_factor: float = length / longest
	model.scale = Vector3.ONE * scale_factor
	model.position = -box.get_center() * scale_factor
	return box.size.y * scale_factor

# The placeholder for `kind`, `length` long along the holder's X, centred
# on it. Returns its thickness.
func _add_placeholder(holder: Node3D, kind: PieceKind, length: float) -> float:
	match kind:
		PieceKind.SKULL:
			# An elongated, flattened ovoid, a second smaller one for the jaw.
			_add_sphere(holder, Vector3.ZERO, Vector3(length, length * 0.42, length * 0.5))
			_add_sphere(holder, Vector3(length * 0.22, -length * 0.08, 0.0), Vector3(length * 0.55, length * 0.18, length * 0.32))
			return length * 0.42
		PieceKind.LONG_BONE:
			# A shaft with a knuckle at each end.
			var radius: float = length * 0.06
			_add_capsule(holder, Vector3.ZERO, radius, length * 0.9, 0.0)
			for side in [-1.0, 1.0]:
				_add_sphere(holder, Vector3(side * length * 0.42, 0.0, 0.0), Vector3.ONE * radius * 2.6)
			return radius * 2.6
		PieceKind.RIB:
			# A shallow arc of short segments.
			var segments: int = 4
			var radius: float = length * 0.035
			var arc: float = deg_to_rad(70.0)
			var bend: float = length / arc
			for s in segments:
				var a0: float = -arc * 0.5 + arc * float(s) / float(segments)
				var a1: float = -arc * 0.5 + arc * float(s + 1) / float(segments)
				var p0 := Vector3(sin(a0) * bend, 0.0, (1.0 - cos(a0)) * bend)
				var p1 := Vector3(sin(a1) * bend, 0.0, (1.0 - cos(a1)) * bend)
				_add_capsule(holder, (p0 + p1) * 0.5, radius, p0.distance_to(p1) + radius * 2.0, atan2(p1.z - p0.z, p1.x - p0.x))
			return radius * 2.0
		PieceKind.VERTEBRA:
			# A short drum on its side and the spur off its top.
			var drum := CylinderMesh.new()
			drum.top_radius = length * 0.5
			drum.bottom_radius = length * 0.5
			drum.height = length * 0.6
			var mi := MeshInstance3D.new()
			mi.mesh = drum
			mi.rotation_degrees = Vector3(0.0, 0.0, 90.0)
			holder.add_child(mi)
			_add_capsule(holder, Vector3(0.0, length * 0.45, 0.0), length * 0.12, length * 0.8, 0.0, true)
			return length
		PieceKind.PELVIS:
			# A broad flattened plate, two wings off a narrow middle.
			for side in [-1.0, 1.0]:
				_add_sphere(holder, Vector3(0.0, 0.0, side * length * 0.22), Vector3(length * 0.8, length * 0.2, length * 0.45))
			return length * 0.2
	return 0.1

func _add_sphere(holder: Node3D, at: Vector3, size: Vector3) -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.position = at
	mi.scale = size
	holder.add_child(mi)

# A capsule lying along X, turned `yaw` radians about Y - or standing up,
# when `upright`.
func _add_capsule(holder: Node3D, at: Vector3, radius: float, height: float, yaw: float, upright: bool = false) -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0)
	capsule.radial_segments = 12
	capsule.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = capsule
	mi.position = at
	if not upright:
		mi.rotation = Vector3(0.0, -yaw, deg_to_rad(90.0))
	holder.add_child(mi)

# Each piece at its place: yawed, tilted by its own seeded draw, and its
# centre sunk sink_fraction of its thickness into the relief under it.
func _ground_pieces() -> void:
	if not _ready_done or not is_inside_tree():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = tilt_seed
	for i in _pieces.size():
		var place: Vector3 = piece_places[i]
		var tilt_x: float = rng.randf_range(-tilt_degrees, tilt_degrees)
		var tilt_z: float = rng.randf_range(-tilt_degrees, tilt_degrees)
		var piece: Node3D = _pieces[i]
		piece.position = Vector3(place.x, 0.0, place.z)
		piece.rotation_degrees = Vector3(tilt_x, place.y, tilt_z)
		var height: float = _height_at(piece.global_position)
		var centre_y: float = height + _thickness[i] * (0.5 - sink_fraction)
		piece.global_position = Vector3(piece.global_position.x, centre_y, piece.global_position.z)

func _height_at(world: Vector3) -> float:
	if _ground == null:
		return 0.0
	var local: Vector3 = _ground.to_local(world)
	return _ground.get_height_at(Vector2(local.x, local.z))
