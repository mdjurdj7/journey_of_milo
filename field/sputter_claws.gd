extends Node3D
class_name SputterClaws

# The Sputter's claw idle - the attachment EnemyData.attachment_scene_path
# names, instantiated by FieldEnemy under the MODEL root after its
# material pass (see FieldEnemy._attach_scene()).
#
# Sputter.glb is one mesh with one surface, but that surface is 55
# separate pieces that share no vertices: the shell, each leg segment,
# each finger of each claw. The crab is a hermit crab - one big claw
# (glb -X, the crab's own right) and one small one near the centreline.
# Only the big claw moves: its upper finger opens against the fixed lower
# finger and closes again. The finger is chosen BY PIECE, not by vertex
# position - the two fingers overlap in position, but each is its own
# piece - so it moves rigidly and nothing tears at a boundary.
#
# How: at spawn the body mesh is rebuilt once with bone weights (every
# vertex on bone 0, "Body"; every vertex of a selected piece on bone 1,
# "Finger") and given a generated Skeleton3D, so the GPU does the
# turning. The body's material is untouched, so the hover highlight and
# the hit flash still tint the whole crab.
#
# Selection: a piece belongs to the finger when its centroid lies inside
# the finger box. The box is in GLB UNITS in the glb's own space (head
# toward +Z; times model_scale for metres), because it picks parts of the
# mesh and has to follow the mesh at any scale. Its lower Y edge is the
# height limit that parts the upper finger (centroids about 0.17) from
# the lower (about 0.08); its X and Z edges keep out the arm, the legs
# and the eyestalks.
#
# Hinge: derived, not placed - the centre of the finger's rearmost
# hinge_rear_fraction of vertices along the glb's +Z, plus hinge_offset.
# The finger turns about the horizontal axis across its own length (from
# the hinge toward its centroid), so a positive angle lifts the tip.
#
# Motion: at rest, then one open-and-close every claw_interval_min..max
# seconds, drawn fresh each time from this crab's own random generator,
# so no two crabs keep time and no one crab has a countable loop. Each
# movement is a cosine out-and-back over claw_seconds - zero angle and
# zero speed at both ends - at claw_degrees scaled by a random factor
# down to (1 - claw_amplitude_variation). The first movement waits a
# full draw after spawn, so the crab arrives at rest and nothing pops.
# Runs in _process at PROCESS_MODE_ALWAYS, like DragonflyWings - through
# the field's freeze for a fight and the reward screen alike. The attack
# lunge moves the whole body and plays on top.

const BODY_BONE := 0
const FINGER_BONE := 1

@export_group("Selection")
# The box the finger pieces' centroids lie in, glb units (see above).
@export var finger_box_min: Vector3 = Vector3(-0.40, 0.13, 0.14):
	set(value):
		finger_box_min = value
		_apply_selection()
@export var finger_box_max: Vector3 = Vector3(-0.16, 0.33, 0.49):
	set(value):
		finger_box_max = value
		_apply_selection()

@export_group("Hinge")
# The share of the finger's length, from its rear end along +Z, whose
# vertices set the hinge.
@export_range(0.01, 1.0, 0.01) var hinge_rear_fraction: float = 0.1:
	set(value):
		hinge_rear_fraction = value
		_apply_selection()
# Added to the derived hinge, glb units.
@export var hinge_offset: Vector3 = Vector3.ZERO:
	set(value):
		hinge_offset = value
		_apply_selection()

@export_group("Motion")
# Read each frame, so an edit takes at once.
# Degrees the finger opens at a movement's peak (positive lifts the tip).
@export var claw_degrees: float = 12.0
# One open-and-close, seconds.
@export var claw_seconds: float = 1.2
# Each movement's amplitude is claw_degrees times a random factor in
# [1 - this, 1].
@export_range(0.0, 1.0, 0.01) var claw_amplitude_variation: float = 0.35
# The rest between movements is drawn from this range, seconds. An edit
# redraws the rest in progress.
@export var claw_interval_min: float = 4.0:
	set(value):
		claw_interval_min = value
		_redraw_wait()
@export var claw_interval_max: float = 9.0:
	set(value):
		claw_interval_max = value
		_redraw_wait()

var _mesh_instance: MeshInstance3D = null
var _skeleton: Skeleton3D = null
var _skinned_mesh: ArrayMesh = null
var _source_material: Material = null
# Surface 0 of the glb's mesh, as surface_get_arrays() gives it.
var _arrays: Array = []
# Per vertex, which piece it belongs to; per piece, its centroid.
var _piece_of: PackedInt32Array = PackedInt32Array()
var _piece_centroids: PackedVector3Array = PackedVector3Array()
var _hinge: Vector3 = Vector3.ZERO
var _axis: Vector3 = Vector3.LEFT
var _ready_done: bool = false

var _rng := RandomNumberGenerator.new()
# Seconds of rest left before the next movement.
var _wait: float = 0.0
# Seconds into the movement running now; negative = at rest.
var _move_elapsed: float = -1.0
var _move_degrees: float = 0.0
var _last_angle: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	var parent := get_parent() as Node3D
	if parent == null:
		push_warning("SputterClaws: no model root above; the claws stay still.")
		return
	for node in parent.find_children("*", "MeshInstance3D", true, false):
		_mesh_instance = node as MeshInstance3D
		break
	if _mesh_instance == null or _mesh_instance.mesh == null:
		push_warning("SputterClaws: no body mesh under the model root; the claws stay still.")
		return
	var mesh: Mesh = _mesh_instance.mesh
	if mesh.get_surface_count() != 1:
		push_warning("SputterClaws: the body mesh has %d surfaces; only the first is rigged." % mesh.get_surface_count())
	_arrays = mesh.surface_get_arrays(0)
	_source_material = mesh.surface_get_material(0)
	_find_pieces()
	_build_skeleton()
	_ready_done = true
	_redraw_wait()
	_apply_selection()

func _process(delta: float) -> void:
	if not _ready_done:
		return
	if _move_elapsed >= 0.0:
		_move_elapsed += delta
		if _move_elapsed >= claw_seconds:
			_move_elapsed = -1.0
			_redraw_wait()
	else:
		_wait -= delta
		if _wait <= 0.0 and claw_seconds > 0.0:
			_move_elapsed = 0.0
			_move_degrees = claw_degrees * _rng.randf_range(1.0 - claw_amplitude_variation, 1.0)
	var angle: float = 0.0
	if _move_elapsed >= 0.0 and claw_seconds > 0.0:
		angle = _move_degrees * 0.5 * (1.0 - cos(TAU * _move_elapsed / claw_seconds))
	if angle != _last_angle:
		_apply_pose(angle)

func _redraw_wait() -> void:
	var low: float = maxf(minf(claw_interval_min, claw_interval_max), 0.0)
	var high: float = maxf(claw_interval_max, low)
	_wait = _rng.randf_range(low, high)

# Welds vertices that share a position (the import splits them at UV and
# normal seams), then joins every triangle's corners: what is left
# connected is one piece.
func _find_pieces() -> void:
	var vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = _arrays[Mesh.ARRAY_INDEX]
	var count: int = vertices.size()
	var parent_of := PackedInt32Array()
	parent_of.resize(count)
	var first_at: Dictionary = {}
	for index in count:
		var key := Vector3i((vertices[index] * 100000.0).round())
		var first: int = first_at.get(key, index)
		first_at[key] = first
		parent_of[index] = first
	for corner in range(0, indices.size() - 2, 3):
		var a: int = _root(parent_of, indices[corner])
		var b: int = _root(parent_of, indices[corner + 1])
		var c: int = _root(parent_of, indices[corner + 2])
		parent_of[b] = a
		parent_of[_root(parent_of, c)] = a
	var piece_of_root: Dictionary = {}
	_piece_of.resize(count)
	var sums: PackedVector3Array = PackedVector3Array()
	var totals: PackedInt32Array = PackedInt32Array()
	for index in count:
		var root: int = _root(parent_of, index)
		var piece: int = piece_of_root.get(root, sums.size())
		if piece == sums.size():
			piece_of_root[root] = piece
			sums.append(Vector3.ZERO)
			totals.append(0)
		_piece_of[index] = piece
		sums[piece] += vertices[index]
		totals[piece] += 1
	_piece_centroids.resize(sums.size())
	for piece in sums.size():
		_piece_centroids[piece] = sums[piece] / float(totals[piece])

func _root(parent_of: PackedInt32Array, index: int) -> int:
	var at: int = index
	while parent_of[at] != at:
		parent_of[at] = parent_of[parent_of[at]]
		at = parent_of[at]
	return at

# Two bones, both at rest where the mesh is: the finger's pose carries the
# whole hinge turn (see _apply_pose()), so the binds never change.
func _build_skeleton() -> void:
	_skeleton = Skeleton3D.new()
	_skeleton.name = "ClawSkeleton"
	_skeleton.add_bone("Body")
	_skeleton.add_bone("Finger")
	# Through the freeze with the rest of this node.
	_skeleton.process_mode = Node.PROCESS_MODE_ALWAYS
	_mesh_instance.add_child(_skeleton)
	var skin := Skin.new()
	skin.add_bind(BODY_BONE, Transform3D.IDENTITY)
	skin.add_bind(FINGER_BONE, Transform3D.IDENTITY)
	_mesh_instance.skin = skin
	_mesh_instance.skeleton = _mesh_instance.get_path_to(_skeleton)

# The finger's pieces from the box, the mesh re-weighted to them, and the
# hinge derived from them.
func _apply_selection() -> void:
	if not _ready_done:
		return
	var vertices: PackedVector3Array = _arrays[Mesh.ARRAY_VERTEX]
	var box := AABB(finger_box_min, finger_box_max - finger_box_min).abs()
	var chosen: Array[bool] = []
	chosen.resize(_piece_centroids.size())
	var chosen_count: int = 0
	for piece in _piece_centroids.size():
		chosen[piece] = box.has_point(_piece_centroids[piece])
		if chosen[piece]:
			chosen_count += 1
	var bones := PackedInt32Array()
	bones.resize(vertices.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(vertices.size() * 4)
	var finger: PackedVector3Array = PackedVector3Array()
	for index in vertices.size():
		var moves: bool = chosen[_piece_of[index]]
		bones[index * 4] = FINGER_BONE if moves else BODY_BONE
		weights[index * 4] = 1.0
		if moves:
			finger.append(vertices[index])
	var arrays: Array = _arrays.duplicate()
	arrays[Mesh.ARRAY_BONES] = bones
	arrays[Mesh.ARRAY_WEIGHTS] = weights
	_skinned_mesh = ArrayMesh.new()
	_skinned_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_skinned_mesh.surface_set_material(0, _source_material)
	_mesh_instance.mesh = _skinned_mesh
	print("SputterClaws: %d piece(s), %d vertices on the finger." % [chosen_count, finger.size()])
	if finger.is_empty():
		push_warning("SputterClaws: no piece's centroid is inside the finger box; nothing moves.")
		_hinge = Vector3.ZERO
		_axis = Vector3.LEFT
		_apply_pose(_last_angle)
		return
	_derive_hinge(finger)
	_apply_pose(_last_angle)

func _derive_hinge(finger: PackedVector3Array) -> void:
	var rear: float = INF
	var front: float = -INF
	var centroid: Vector3 = Vector3.ZERO
	for point in finger:
		rear = minf(rear, point.z)
		front = maxf(front, point.z)
		centroid += point
	centroid /= float(finger.size())
	var cut: float = rear + hinge_rear_fraction * (front - rear)
	var hinge_sum: Vector3 = Vector3.ZERO
	var hinge_count: int = 0
	for point in finger:
		if point.z <= cut:
			hinge_sum += point
			hinge_count += 1
	_hinge = hinge_sum / float(maxi(hinge_count, 1)) + hinge_offset
	var along := Vector3(centroid.x - _hinge.x, 0.0, centroid.z - _hinge.z)
	along = along.normalized() if along.length() > 0.0001 else Vector3.BACK
	# Across the finger, so a positive turn lifts the tip.
	_axis = along.cross(Vector3.UP).normalized()

# The finger turned `degrees` about the hinge, as a bone pose: the turn,
# then the shift that keeps the hinge point where it is.
func _apply_pose(degrees: float) -> void:
	_last_angle = degrees
	if _skeleton == null:
		return
	var turn := Quaternion(_axis, deg_to_rad(degrees))
	_skeleton.set_bone_pose_rotation(FINGER_BONE, turn)
	_skeleton.set_bone_pose_position(FINGER_BONE, _hinge - turn * _hinge)
