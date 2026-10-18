extends Node3D
class_name NettlebasketPose

# The Nettlebasket's idle - the attachment EnemyData.attachment_scene_path
# names, instantiated by FieldEnemy under the MODEL root after its
# material pass (see FieldEnemy._attach_scene()). The Nettle wears it too:
# each riding Nettle is the same mesh at a fraction of the scale.
#
# Nettlebasket.glb is one mesh, one surface, one connected piece: the
# claws are picked by vertex position, with weights that fade in from the
# shoulder so nothing tears. A CodeSkin with three bones - Body, and a
# claw on either side parented to it - does the moving on the GPU; the
# material is untouched, so the hover highlight and the hit flash still
# tint the whole body.
#
# Glb units, in the glb's own space: head toward +Z, the claws reaching
# forward from about z 0.15 on either side of the head (x about 0.2 to
# 0.45), the tail curled up at the rear.
#
# Motion, all of it small:
# - Breath: the body swells by breath_amount and settles, once every
#   breath_seconds - about its middle across and along, from its feet up,
#   so it never leaves the sand.
# - Claw flex: each claw on its own, at rest, then a slow open-and-close
#   every claw_interval_min..max seconds drawn from this body's own random
#   generator - out by claw_degrees (a random share down to 1 -
#   claw_amplitude_variation) and up by claw_lift_degrees, a cosine out
#   and back over claw_seconds. The first waits a full draw.
# - Rider sway: while seated on a carrier (FieldEnemy.is_seated()), a slow
#   rock about its feet, sway_degrees either way, once every sway_seconds
#   (times a random factor within sway_seconds_variation, per body), from
#   its own phase - so each Nettle on her back shifts in its own time.
# Runs in _process at PROCESS_MODE_ALWAYS, through the field's freeze for
# a fight; eases to rest once the body is defeated.

const BODY_BONE := 0
const LEFT_CLAW_BONE := 1
const RIGHT_CLAW_BONE := 2

@export_group("Selection")
# A vertex belongs to a claw by how far forward (+Z) and out to the side
# (|x|) it is: no weight behind claw_start_z or inside claw_start_x, full
# weight past claw_full_z and claw_full_x, a smooth blend between.
@export var claw_start_z: float = 0.1:
	set(value):
		claw_start_z = value
		_apply_selection()
@export var claw_full_z: float = 0.28:
	set(value):
		claw_full_z = value
		_apply_selection()
@export var claw_start_x: float = 0.1:
	set(value):
		claw_start_x = value
		_apply_selection()
@export var claw_full_x: float = 0.2:
	set(value):
		claw_full_x = value
		_apply_selection()
# The shoulder each claw turns about (the right one is this mirrored in
# x), glb units.
@export var claw_hinge: Vector3 = Vector3(0.3, 0.2, 0.14):
	set(value):
		claw_hinge = value
		_apply_selection()

@export_group("Breath")
# Read each frame.
@export_range(0.0, 0.2, 0.001) var breath_amount: float = 0.018
@export var breath_seconds: float = 3.4

@export_group("Claw flex")
# Read each frame; the rest range redraws the rest in progress.
@export var claw_degrees: float = 7.0
@export var claw_lift_degrees: float = 3.0
@export var claw_seconds: float = 2.4
@export_range(0.0, 1.0, 0.01) var claw_amplitude_variation: float = 0.35
@export var claw_interval_min: float = 3.0:
	set(value):
		claw_interval_min = value
		_redraw_waits()
@export var claw_interval_max: float = 8.0:
	set(value):
		claw_interval_max = value
		_redraw_waits()

@export_group("Rider sway")
# Read each frame.
@export var sway_degrees: float = 3.5
@export var sway_seconds: float = 2.8
@export_range(0.0, 0.9, 0.01) var sway_seconds_variation: float = 0.3

var _skin: CodeSkin = null
var _skeleton: Skeleton3D = null
var _ready_done: bool = false
var _rng := RandomNumberGenerator.new()
# The body's middle across and along (its feet at y 0), glb units.
var _middle: Vector3 = Vector3.ZERO
var _breath_phase: float = 0.0
var _sway_phase: float = 0.0
var _sway_rate: float = 1.0
# 1 alive, easing to 0 once defeated.
var _alive: float = 1.0
# Per claw (0 left, 1 right): rest left, seconds into the flex (negative
# = at rest), and its amplitude.
var _waits: Array[float] = [0.0, 0.0]
var _elapsed: Array[float] = [-1.0, -1.0]
var _amounts: Array[float] = [0.0, 0.0]

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_breath_phase = _rng.randf()
	_sway_phase = _rng.randf()
	_sway_rate = _rng.randf_range(1.0 - sway_seconds_variation, 1.0 + sway_seconds_variation)
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "NettlebasketSkeleton", "NettlebasketPose")
	if _skin == null:
		return
	_skeleton = _skin.skeleton
	_skin.set_bones(PackedStringArray(["Body", "LeftClaw", "RightClaw"]), PackedInt32Array([-1, 0, 0]), [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY] as Array[Transform3D])
	var vertices: PackedVector3Array = _skin.get_vertices()
	var box := AABB(vertices[0], Vector3.ZERO) if not vertices.is_empty() else AABB()
	for point in vertices:
		box = box.expand(point)
	_middle = Vector3(box.get_center().x, box.position.y, box.get_center().z)
	_ready_done = true
	_redraw_waits()
	_apply_selection()

func _body() -> FieldEnemy:
	var model := get_parent()
	return model.get_parent() as FieldEnemy if model != null else null

func _process(delta: float) -> void:
	if not _ready_done:
		return
	var body := _body()
	var alive: bool = body == null or not body.is_defeated()
	_alive = move_toward(_alive, 1.0 if alive else 0.0, delta)
	_breath_phase = fposmod(_breath_phase + delta / maxf(breath_seconds, 0.05), 1.0)
	_sway_phase = fposmod(_sway_phase + delta / maxf(sway_seconds * _sway_rate, 0.05), 1.0)
	for claw in 2:
		if _elapsed[claw] >= 0.0:
			_elapsed[claw] += delta
			if _elapsed[claw] >= claw_seconds:
				_elapsed[claw] = -1.0
				_waits[claw] = _draw_wait()
		else:
			_waits[claw] -= delta
			if _waits[claw] <= 0.0 and claw_seconds > 0.0 and alive:
				_elapsed[claw] = 0.0
				_amounts[claw] = _rng.randf_range(1.0 - claw_amplitude_variation, 1.0)
	var seated: bool = body != null and body.is_seated()
	_apply_pose(seated)

func _draw_wait() -> float:
	var low: float = maxf(minf(claw_interval_min, claw_interval_max), 0.0)
	return _rng.randf_range(low, maxf(claw_interval_max, low))

func _redraw_waits() -> void:
	for claw in 2:
		_waits[claw] = _draw_wait()

# Each vertex onto Body, or shared with its side's claw by the blend.
func _apply_selection() -> void:
	if not _ready_done:
		return
	var vertices: PackedVector3Array = _skin.get_vertices()
	var bones := PackedInt32Array()
	bones.resize(vertices.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(vertices.size() * 4)
	var on_claws: int = 0
	for index in vertices.size():
		var point: Vector3 = vertices[index]
		var share: float = smoothstep(claw_start_z, maxf(claw_full_z, claw_start_z + 0.001), point.z) * smoothstep(claw_start_x, maxf(claw_full_x, claw_start_x + 0.001), absf(point.x))
		bones[index * 4] = LEFT_CLAW_BONE if point.x < 0.0 else RIGHT_CLAW_BONE
		weights[index * 4] = share
		bones[index * 4 + 1] = BODY_BONE
		weights[index * 4 + 1] = 1.0 - share
		if share > 0.5:
			on_claws += 1
	_skin.apply_weights(bones, weights)
	print("NettlebasketPose: %d of %d vertices mostly on the claws." % [on_claws, vertices.size()])

func _apply_pose(seated: bool) -> void:
	if _skeleton == null:
		return
	# Breath: a swell about the middle, from the feet up.
	var swell: float = 1.0 + breath_amount * 0.5 * (1.0 - cos(TAU * _breath_phase)) * _alive
	var body_basis := Basis.from_scale(Vector3(swell, swell, 1.0 + (swell - 1.0) * 0.4))
	# Sway: a rock about the feet while seated.
	if seated:
		var rock: float = deg_to_rad(sway_degrees) * sin(TAU * _sway_phase) * _alive
		var pitch: float = deg_to_rad(sway_degrees) * 0.5 * sin(TAU * _sway_phase * 0.5 + 1.3) * _alive
		body_basis = Basis(Vector3.BACK, rock) * Basis(Vector3.RIGHT, pitch) * body_basis
	_skeleton.set_bone_pose_rotation(BODY_BONE, body_basis.get_rotation_quaternion())
	_skeleton.set_bone_pose_scale(BODY_BONE, body_basis.get_scale())
	_skeleton.set_bone_pose_position(BODY_BONE, _middle - body_basis * _middle)
	for claw in 2:
		var side: float = -1.0 if claw == 0 else 1.0
		var hinge := Vector3(claw_hinge.x * side, claw_hinge.y, claw_hinge.z)
		var amount: float = 0.0
		if _elapsed[claw] >= 0.0 and claw_seconds > 0.0:
			amount = _amounts[claw] * 0.5 * (1.0 - cos(TAU * _elapsed[claw] / claw_seconds)) * _alive
		# Out (away from the centreline) and up.
		var turn := Quaternion(Vector3.UP, deg_to_rad(claw_degrees) * amount * side) * Quaternion(Vector3.RIGHT, -deg_to_rad(claw_lift_degrees) * amount)
		var bone: int = LEFT_CLAW_BONE if claw == 0 else RIGHT_CLAW_BONE
		_skeleton.set_bone_pose_rotation(bone, turn)
		_skeleton.set_bone_pose_position(bone, hinge - turn * hinge)
