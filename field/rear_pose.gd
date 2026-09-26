extends Node3D
class_name RearPose

# The Siltjaw rearing while its charge is queued: the front of the body
# lifts about a pivot near its middle, so the head and mandibles come up
# off the sand, and holds there until the charge lands or breaks. An
# attachment like DragonflyWings (EnemyData.attachment_scene_path) -
# FieldEnemy instances it under the model root and calls set_rearing()
# (see FieldEnemy.set_rearing(), driven by BattleController).
#
# Procedural, no clips: at _ready() the body's own mesh is skinned once
# onto a two-bone Skeleton3D made here. Every vertex behind the pivot
# follows the still root bone; every vertex ahead of it follows a
# "front" bone whose rest sits on the pivot; across bend_blend_m at the
# pivot the weight blends from one to the other, so the body bends there
# rather than creasing. Rearing is that one bone rotating - the GPU does
# the rest, and a held pose costs nothing per frame. The segments inside
# the blend bunch as it bends - a thick neck at 45 degrees, a visible
# knot close up at 65 (at the battle frame's distance it still reads).
# Rotating the body whole and lifting it so the tail stays on the sand
# was tried and stood it on its tail at 65, so there is no such mode.
#
# Directions come from the body, not the asset: forward is the body's -Z
# and up its +Y, taken into the mesh's own space through the transforms
# FieldEnemy has already set (scale, yaw offset, grounding), so the pivot
# and the bend sit right whichever way a glb faces.

# How far the front comes up, degrees.
@export_range(0.0, 90.0, 0.5) var rear_degrees: float = 45.0:
	set(value):
		rear_degrees = value
		_measure()
		if _target > 0.0:
			_target = rear_degrees
			_set_angle(rear_degrees)
# The pivot: this far forward of the body's middle, and this far above
# its underside, metres.
@export var pivot_forward_m: float = 0.1:
	set(value):
		pivot_forward_m = value
		_rebuild()
@export var pivot_up_m: float = 0.15:
	set(value):
		pivot_up_m = value
		_rebuild()
# The length over which the body goes from flat to fully reared,
# centred on the pivot, metres.
@export var bend_blend_m: float = 0.5:
	set(value):
		bend_blend_m = value
		_rebuild()
# Up, and back down when the charge lands or is interrupted.
@export var rear_seconds: float = 0.5
@export var drop_seconds: float = 0.4

var _mesh_instance: MeshInstance3D = null
var _source_mesh: Mesh = null
var _skeleton: Skeleton3D = null
# In the mesh's own space: the pivot, the bend axis (forward x up, so a
# positive angle lifts the front) and up; metres per mesh unit.
var _pivot: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3.RIGHT
var _up: Vector3 = Vector3.UP
var _metres_per_unit: float = 1.0
# The source mesh's vertices and each one's weight on the front bone.
var _vertices: PackedVector3Array = PackedVector3Array()
var _weights: PackedFloat32Array = PackedFloat32Array()
# At rear_degrees: how much higher the top of the body stands, metres.
var _full_extra: float = 0.0
var _angle: float = 0.0
var _target: float = 0.0
var _tween: Tween = null
var _ready_done: bool = false

func _ready() -> void:
	var model := get_parent() as Node3D
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh != null and not is_ancestor_of(mi):
			_mesh_instance = mi
			break
	if _mesh_instance == null:
		push_warning("RearPose: no mesh under '%s' to rear; nothing to do." % model.name)
		return
	_source_mesh = _mesh_instance.mesh
	_skeleton = Skeleton3D.new()
	_skeleton.name = "RearSkeleton"
	add_child(_skeleton)
	_ready_done = true
	_rebuild()

# FieldEnemy.set_rearing(): up to rear_degrees over rear_seconds, or down
# over drop_seconds (see the easing below); returns how long that takes - 0 when it is
# already heading there. Through the battle freeze (PAUSE_PROCESS).
func set_rearing(on: bool) -> float:
	if not _ready_done:
		return 0.0
	var target: float = rear_degrees if on else 0.0
	if is_equal_approx(target, _target):
		return 0.0
	_target = target
	var seconds: float = maxf(rear_seconds if on else drop_seconds, 0.0)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	if seconds <= 0.0:
		_set_angle(target)
		return 0.0
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Up eases in and out; down eases out - it gives way at once and lands
	# soft, so a charge broken mid-turn settles on the very frame its ring
	# closes (BattleController._resolve_play()) rather than after a pause.
	_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT if on else Tween.EASE_OUT)
	_tween.tween_method(_set_angle, _angle, target, seconds)
	return seconds

# How much higher than flat the top of the body stands right now, metres
# - FieldEnemy adds it to its head height, so the intent and the camera
# fit clear a reared head.
func get_rear_lift() -> float:
	if rear_degrees <= 0.0:
		return 0.0
	return _full_extra * clampf(_angle / rear_degrees, 0.0, 1.0)

# The skin, from the exports: the pivot and axes in mesh space, each
# vertex's weight, the mesh rebuilt once with bones/weights, the two
# bones and their binds.
func _rebuild() -> void:
	if not _ready_done:
		return
	var body := get_parent().get_parent() as Node3D
	if body == null:
		return
	var to_body: Transform3D = body.global_transform.affine_inverse() * _mesh_instance.global_transform
	var from_body: Basis = to_body.basis.inverse()
	var forward: Vector3 = (from_body * Vector3.FORWARD).normalized()
	_up = (from_body * Vector3.UP).normalized()
	_axis = forward.cross(_up).normalized()
	_metres_per_unit = to_body.basis.get_scale().x

	var surface: Array = _source_mesh.surface_get_arrays(0)
	_vertices = surface[Mesh.ARRAY_VERTEX]
	var front_lo: float = INF
	var front_hi: float = -INF
	var floor_level: float = INF
	var side_lo: float = INF
	var side_hi: float = -INF
	for v in _vertices:
		front_lo = minf(front_lo, v.dot(forward))
		front_hi = maxf(front_hi, v.dot(forward))
		floor_level = minf(floor_level, v.dot(_up))
		side_lo = minf(side_lo, v.dot(_axis))
		side_hi = maxf(side_hi, v.dot(_axis))
	var pivot_front: float = (front_lo + front_hi) * 0.5 + pivot_forward_m / _metres_per_unit
	_pivot = forward * pivot_front + _up * (floor_level + pivot_up_m / _metres_per_unit) + _axis * ((side_lo + side_hi) * 0.5)

	var half_blend: float = maxf(bend_blend_m, 0.001) * 0.5 / _metres_per_unit
	_weights.resize(_vertices.size())
	var bones := PackedInt32Array()
	var bone_weights := PackedFloat32Array()
	bones.resize(_vertices.size() * 4)
	bone_weights.resize(_vertices.size() * 4)
	for i in _vertices.size():
		var w: float = smoothstep(pivot_front - half_blend, pivot_front + half_blend, _vertices[i].dot(forward))
		_weights[i] = w
		bones[i * 4] = 0
		bones[i * 4 + 1] = 1
		bone_weights[i * 4] = 1.0 - w
		bone_weights[i * 4 + 1] = w
	surface[Mesh.ARRAY_BONES] = bones
	surface[Mesh.ARRAY_WEIGHTS] = bone_weights
	var skinned := ArrayMesh.new()
	skinned.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
	skinned.surface_set_material(0, _source_mesh.surface_get_material(0))
	_mesh_instance.mesh = skinned

	_skeleton.clear_bones()
	_skeleton.add_bone("body")
	_skeleton.add_bone("front")
	_skeleton.set_bone_parent(1, 0)
	_skeleton.set_bone_rest(0, Transform3D.IDENTITY)
	_skeleton.set_bone_rest(1, Transform3D(Basis.IDENTITY, _pivot))
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	skin.add_bind(1, Transform3D(Basis.IDENTITY, _pivot).affine_inverse())
	# The skeleton in the mesh's own space, so bind, rest and vertex all
	# share one frame.
	_skeleton.global_transform = _mesh_instance.global_transform
	_mesh_instance.skin = skin
	_mesh_instance.skeleton = _mesh_instance.get_path_to(_skeleton)
	_measure()
	_set_angle(_angle)

# At rear_degrees: how far the body's top rises - one pass over the
# vertices, the same linear blend the GPU does.
func _measure() -> void:
	if not _ready_done or _vertices.is_empty():
		return
	var turn := Basis(_axis, deg_to_rad(rear_degrees))
	var top_flat: float = -INF
	var top_reared: float = -INF
	for i in _vertices.size():
		var v: Vector3 = _vertices[i]
		var reared: Vector3 = _pivot + turn * (v - _pivot)
		top_flat = maxf(top_flat, v.dot(_up))
		top_reared = maxf(top_reared, v.lerp(reared, _weights[i]).dot(_up))
	_full_extra = (top_reared - top_flat) * _metres_per_unit

# The front bone at `degrees` about the bend axis, on the pivot (its
# rest).
func _set_angle(degrees: float) -> void:
	_angle = degrees
	if _skeleton == null or _skeleton.get_bone_count() < 2:
		return
	_skeleton.set_bone_pose_position(0, Vector3.ZERO)
	_skeleton.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	_skeleton.set_bone_pose_position(1, _pivot)
	_skeleton.set_bone_pose_rotation(1, Quaternion(_axis, deg_to_rad(degrees)))
