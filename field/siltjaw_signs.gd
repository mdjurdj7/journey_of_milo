extends Node3D
class_name SiltjawSigns

# What a Siltjaw's spot shows when its slot rolls empty (floor 2's
# "siltjaw_gone" option): old burrow mounds slumped back toward the sand,
# and faint drag trails between them - something lived here and has gone.
# Static: no interaction, no collision, nothing said.
#
# Each sign is a SandMound, the Siltjaw's own swell of sand, drawn with
# the ground's material so it is the sand itself: the mounds low and
# soft (mound_*), their crest cracks faint; the trails long, narrow and
# barely raised, a faint broken line along their length - sand dragged
# over (trail_*). Never a groove: a SandMound only rises, and anything
# under the sand is hidden by it. Every offset and yaw is in this prop's frame (the slot's,
# through its option - EncounterOption.props), lengths along local -Z.
# Each SandMound samples the sand under its own anchor once the relief
# is built, and again on a relief rebuild, as a Siltjaw's mound does.
#
# FieldScatter keeps out of every sign (get_footprints()), as it keeps
# out of the Siltjaw's own spot when it stands.

@export_group("Mounds")
@export var mound_offsets: PackedVector2Array = PackedVector2Array([Vector2(-2.2, 0.6), Vector2(0.1, -0.3), Vector2(2.2, 0.8)]):
	set(value):
		mound_offsets = value
		_rebuild()
@export var mound_yaws_degrees: PackedFloat32Array = PackedFloat32Array([-25.0, 10.0, 35.0]):
	set(value):
		mound_yaws_degrees = value
		_rebuild()
# A live dig mound is 2.4 x 1.5 x 0.28; these have sat out the weather.
@export var mound_length_m: float = 1.9:
	set(value):
		mound_length_m = value
		_rebuild()
@export var mound_width_m: float = 1.25:
	set(value):
		mound_width_m = value
		_rebuild()
@export var mound_height_m: float = 0.12:
	set(value):
		mound_height_m = value
		_rebuild()
@export_range(1.0, 4.0, 0.05) var mound_falloff_power: float = 1.6:
	set(value):
		mound_falloff_power = value
		_rebuild()
@export_range(0.05, 1.0, 0.01) var mound_crack_extent: float = 0.3:
	set(value):
		mound_crack_extent = value
		_rebuild()
@export_range(0.0, 1.0, 0.01) var mound_crack_shade: float = 0.5:
	set(value):
		mound_crack_shade = value
		_rebuild()
@export_group("")

@export_group("Trails")
# Each trail's middle, its heading and its length.
@export var trail_offsets: PackedVector2Array = PackedVector2Array([Vector2(-1.05, 0.2), Vector2(1.15, 0.3), Vector2(0.5, -1.7)]):
	set(value):
		trail_offsets = value
		_rebuild()
@export var trail_yaws_degrees: PackedFloat32Array = PackedFloat32Array([72.0, 100.0, 160.0]):
	set(value):
		trail_yaws_degrees = value
		_rebuild()
@export var trail_lengths_m: PackedFloat32Array = PackedFloat32Array([2.0, 1.9, 2.6]):
	set(value):
		trail_lengths_m = value
		_rebuild()
@export var trail_width_m: float = 0.4:
	set(value):
		trail_width_m = value
		_rebuild()
@export var trail_height_m: float = 0.02:
	set(value):
		trail_height_m = value
		_rebuild()
# The line along it: how much of the length it runs, and how dark - faint.
@export_range(0.05, 1.0, 0.01) var trail_line_extent: float = 0.9:
	set(value):
		trail_line_extent = value
		_rebuild()
@export_range(0.0, 1.0, 0.01) var trail_line_shade: float = 0.75:
	set(value):
		trail_line_shade = value
		_rebuild()
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"

var _ground: Ground = null
# Per sign: its anchor (the SandMound's parent, whose frame it samples)
# and its footprint's length and width.
var _anchors: Array[Node3D] = []
var _sizes: Array[Vector2] = []

# FloorProp's placement (RegionField._spawn_prop_list()): XZ here, the
# signs ground themselves; yaw onto the frame.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)

func _ready() -> void:
	_ground = get_node_or_null(ground_path) as Ground
	_rebuild()
	if _ground != null:
		_ground.relief_rebuilt.connect(_resample)
		# relief_rebuilt's first emission is inside Ground's own _ready();
		# the first sample waits a frame, as FieldEnemy's does.
		await get_tree().process_frame
		_resample()

func _rebuild() -> void:
	if not is_node_ready():
		return
	for anchor in _anchors:
		if is_instance_valid(anchor):
			anchor.queue_free()
	_anchors.clear()
	_sizes.clear()
	for index in mound_offsets.size():
		var mound := SandMound.new()
		mound.length_m = mound_length_m
		mound.width_m = mound_width_m
		mound.height_m = mound_height_m
		mound.falloff_power = mound_falloff_power
		mound.crack_extent = mound_crack_extent
		mound.crack_shade = mound_crack_shade
		mound.crack_seed = index + 7
		_add_sign("Mound%d" % index, mound_offsets[index], _at(mound_yaws_degrees, index), mound, Vector2(mound_length_m, mound_width_m))
	for index in trail_offsets.size():
		var length: float = _at(trail_lengths_m, index) if index < trail_lengths_m.size() else 2.0
		var trail := SandMound.new()
		trail.length_m = length
		trail.width_m = trail_width_m
		trail.height_m = trail_height_m
		trail.falloff_power = 1.0
		trail.crest_fraction = 0.5
		trail.crack_extent = trail_line_extent
		trail.crack_shade = trail_line_shade
		trail.crack_seed = index + 21
		_add_sign("Trail%d" % index, trail_offsets[index], _at(trail_yaws_degrees, index), trail, Vector2(length, trail_width_m))
	_resample()

func _add_sign(sign_name: String, offset: Vector2, yaw_degrees: float, mound: SandMound, footprint: Vector2) -> void:
	var anchor := Node3D.new()
	anchor.name = sign_name
	anchor.position = Vector3(offset.x, 0.0, offset.y)
	anchor.rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
	add_child(anchor)
	mound.name = "SandMound"
	anchor.add_child(mound)
	if _ground != null:
		mound.set_ground(_ground)
	_anchors.append(anchor)
	_sizes.append(footprint)

static func _at(values: PackedFloat32Array, index: int) -> float:
	return values[index] if index < values.size() else 0.0

func _resample() -> void:
	for anchor in _anchors:
		if not is_instance_valid(anchor):
			continue
		var mound := anchor.get_node_or_null(^"SandMound") as SandMound
		if mound != null:
			mound.resample()

# Every sign's footprint on the ground: its length by its width, turned
# with it, as world XZ corners - what FieldScatter keeps out of.
func get_footprints() -> Array[PackedVector2Array]:
	var footprints: Array[PackedVector2Array] = []
	for index in _anchors.size():
		var anchor: Node3D = _anchors[index]
		if not is_instance_valid(anchor):
			continue
		var half: Vector2 = _sizes[index] * 0.5
		var corners := PackedVector2Array()
		for corner: Vector2 in [Vector2(-half.y, -half.x), Vector2(half.y, -half.x), Vector2(half.y, half.x), Vector2(-half.y, half.x)]:
			var world: Vector3 = anchor.global_transform * Vector3(corner.x, 0.0, corner.y)
			corners.append(Vector2(world.x, world.z))
		footprints.append(corners)
	return footprints
