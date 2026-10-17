extends Node3D
class_name GlowerPose

# The Glower's body (EnemyData.attachment_scene_path): a pufferfish resting
# deflated in a shallow standing pool, swelling into its inflated self
# while it taunts. FieldEnemy instantiates it under the MODEL root after
# its material pass (FieldEnemy._attach_scene()).
#
# Deflated (the field, and most of a fight): the body is the enemy's own
# model, Glower_deflated.glb, one mesh of 34 separate pieces - the body,
# each fin, the spines, the eyes. The fins move BY PIECE, as SputterClaws'
# finger does: at spawn the mesh is rebuilt once with bone weights (every
# vertex on "Body", every vertex of a fin piece on that fin's bone) and a
# generated Skeleton3D (CodeSkin). A piece belongs to a fin when its
# centroid lies inside that fin's box, in GLB UNITS in the glb's own space
# (nose toward +Z), so it follows the mesh at any scale. The pectoral box
# is the left fin's (-X); its mirror across X picks the right one.
#
# Motion, all slow - a fish at rest in still water: the pectorals sweep
# about the vertical through their roots, out of step with each other;
# the tail fin wags about the vertical through its front edge; the dorsal
# sways about the body's length through its foot; and the whole body bobs
# bob_m up and down. Each hinge is derived from its own piece: the
# vertices of the innermost (pectoral), frontmost (tail) or lowest
# (dorsal) hinge_fraction of it. Runs in _process at PROCESS_MODE_ALWAYS,
# through the field's freeze for a fight and the reward screen alike.
#
# Inflated (show_held_statuses(), from BattleController._pose_for_intent()
# while it holds a status that taunts - Inflated, after its Puff): the
# deflated body hidden and Glower_inflated.glb shown in its place at
# inflated_scale, swelling from swell_from of that over swell_seconds
# with a small overshoot; back down over deflate_seconds when the status
# goes (its next move), then the deflated body again. The inflated body
# has no rig - puffed up, it holds still - but bobs with the rest. It
# wears the painted shader with its own colour map, handed to FieldEnemy
# as a tint material (get_tint_materials()) so the hover, the hit flash,
# the fog and the death reach it too. An escape (exit_battle_frame())
# lets it down at once.

const BODY_BONE := 0
const PECTORAL_LEFT_BONE := 1
const PECTORAL_RIGHT_BONE := 2
const TAIL_BONE := 3
const DORSAL_BONE := 4
# The painted shader every body wears (FieldEnemy's own) - named here, not
# read off FieldEnemy, so this compiles without the field behind it.
const PAINTED_SHADER_PATH := "res://field/wanderer_painted.gdshader"

@export_group("Selection")
# The boxes each fin piece's centroid lies in, glb units (see above).
@export var pectoral_box_min: Vector3 = Vector3(-0.17, 0.05, 0.18):
	set(value):
		pectoral_box_min = value
		_apply_selection()
@export var pectoral_box_max: Vector3 = Vector3(-0.09, 0.17, 0.28):
	set(value):
		pectoral_box_max = value
		_apply_selection()
@export var tail_box_min: Vector3 = Vector3(-0.03, 0.08, -0.50):
	set(value):
		tail_box_min = value
		_apply_selection()
@export var tail_box_max: Vector3 = Vector3(0.03, 0.26, -0.30):
	set(value):
		tail_box_max = value
		_apply_selection()
@export var dorsal_box_min: Vector3 = Vector3(-0.03, 0.23, -0.28):
	set(value):
		dorsal_box_min = value
		_apply_selection()
@export var dorsal_box_max: Vector3 = Vector3(0.03, 0.34, -0.08):
	set(value):
		dorsal_box_max = value
		_apply_selection()
# The share of each fin's vertices, from its root side, whose centre is
# its hinge.
@export_range(0.01, 1.0, 0.01) var hinge_fraction: float = 0.15:
	set(value):
		hinge_fraction = value
		_apply_selection()

@export_group("Motion")
# Read each frame, so an edit takes at once. Degrees at each swing's
# peak, and seconds for one full swing out and back.
@export var pectoral_degrees: float = 16.0
@export var pectoral_seconds: float = 2.2
@export var tail_degrees: float = 9.0
@export var tail_seconds: float = 3.1
@export var dorsal_degrees: float = 5.0
@export var dorsal_seconds: float = 3.7
# The bob: metres up and down from rest, and seconds for one.
@export var bob_m: float = 0.008
@export var bob_seconds: float = 3.4

@export_group("Inflated")
@export_file("*.glb") var inflated_scene_path: String = "res://assets/models/enemies/Glower/Glower_inflated.glb":
	set(value):
		inflated_scene_path = value
		_build_inflated()
@export_file("*.png", "*.jpg") var inflated_albedo_path: String = "res://assets/models/enemies/Glower/Glower_inflated_0.jpg":
	set(value):
		inflated_albedo_path = value
		_build_inflated()
# The inflated glb's scale against the deflated one's: 0.65 keeps the
# deflated fish's length (0.94 m to its 0.96) and tail, and doubles its
# height - one fish swelling.
@export var inflated_scale: float = 0.65:
	set(value):
		inflated_scale = value
		_apply_inflated_scale()
# The swell: from this share of inflated_scale up to all of it, over
# swell_seconds, with TRANS_BACK's overshoot.
@export_range(0.05, 1.0, 0.01) var swell_from: float = 0.5
@export var swell_seconds: float = 0.25
@export var deflate_seconds: float = 0.2

var _skin: CodeSkin = null
var _skeleton: Skeleton3D = null
var _piece_of: PackedInt32Array = PackedInt32Array()
var _piece_centroids: PackedVector3Array = PackedVector3Array()
# Per fin bone (1..4), its hinge and axis; index 0 unused.
var _hinges: PackedVector3Array = PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _axes: PackedVector3Array = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP, Vector3.FORWARD])
var _ready_done: bool = false
var _time: float = 0.0

var _inflated_root: Node3D = null
var _inflated_material: ShaderMaterial = null
var _inflated: bool = false
var _swell_tween: Tween = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_time = randf() * 100.0
	_skin = CodeSkin.on_body(get_parent() as Node3D, self, "FinSkeleton", "GlowerPose")
	if _skin != null:
		_skeleton = _skin.skeleton
		_find_pieces()
		var rests: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY, Transform3D.IDENTITY]
		_skin.set_bones(PackedStringArray(["Body", "PectoralLeft", "PectoralRight", "Tail", "Dorsal"]), PackedInt32Array([-1, -1, -1, -1, -1]), rests)
	_ready_done = true
	_apply_selection()
	_build_inflated()

func _process(delta: float) -> void:
	if not _ready_done:
		return
	_time += delta
	var bob: Vector3 = Vector3.UP * bob_m * sin(TAU * _time / maxf(bob_seconds, 0.01))
	if _inflated_root != null:
		_inflated_root.position = bob
	if _skeleton == null:
		return
	_skeleton.set_bone_pose_position(BODY_BONE, bob)
	_pose_fin(PECTORAL_LEFT_BONE, pectoral_degrees * sin(TAU * _time / maxf(pectoral_seconds, 0.01)), bob)
	_pose_fin(PECTORAL_RIGHT_BONE, -pectoral_degrees * sin(TAU * _time / maxf(pectoral_seconds, 0.01) + 1.3), bob)
	_pose_fin(TAIL_BONE, tail_degrees * sin(TAU * _time / maxf(tail_seconds, 0.01)), bob)
	_pose_fin(DORSAL_BONE, dorsal_degrees * sin(TAU * _time / maxf(dorsal_seconds, 0.01)), bob)

# A fin turned `degrees` about its hinge, as a bone pose - the turn, then
# the shift that keeps the hinge where it is - and lifted with the bob.
func _pose_fin(bone: int, degrees: float, bob: Vector3) -> void:
	var turn := Quaternion(_axes[bone], deg_to_rad(degrees))
	_skeleton.set_bone_pose_rotation(bone, turn)
	_skeleton.set_bone_pose_position(bone, _hinges[bone] - turn * _hinges[bone] + bob)

# --- Inflated ---

# The statuses the enemy holds now (FieldEnemy.show_held_statuses()):
# swollen while one of them taunts, deflated otherwise. Returns how long
# the change takes; 0 when there is none.
func show_held_statuses(statuses: Array[StatusData]) -> float:
	var taunting: bool = false
	for status in statuses:
		if status != null and status.taunts:
			taunting = true
	if taunting == _inflated or _inflated_root == null:
		return 0.0
	_inflated = taunting
	if _swell_tween != null and _swell_tween.is_valid():
		_swell_tween.kill()
	_swell_tween = create_tween()
	if taunting:
		_show_inflated(true)
		_inflated_root.scale = Vector3.ONE * inflated_scale * swell_from
		_swell_tween.tween_property(_inflated_root, "scale", Vector3.ONE * inflated_scale, swell_seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		return swell_seconds
	_swell_tween.tween_property(_inflated_root, "scale", Vector3.ONE * inflated_scale * swell_from, deflate_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_swell_tween.tween_callback(_show_inflated.bind(false))
	return deflate_seconds

# An escape (FieldEnemy.exit_battle_hover()): deflated at once.
func exit_battle_frame() -> void:
	if _swell_tween != null and _swell_tween.is_valid():
		_swell_tween.kill()
	_inflated = false
	_show_inflated(false)

# For the probes: whether it is swollen.
func is_inflated() -> bool:
	return _inflated

# The inflated body's material, for FieldEnemy's tint list.
func get_tint_materials() -> Array[Material]:
	var materials: Array[Material] = []
	if _inflated_material != null:
		materials.append(_inflated_material)
	return materials

func _show_inflated(on: bool) -> void:
	if _inflated_root != null:
		_inflated_root.visible = on
		if not on:
			_inflated_root.scale = Vector3.ONE * inflated_scale
	if _skin != null and _skin.mesh_instance != null:
		_skin.mesh_instance.visible = not on

# The inflated glb under this node, hidden, on the painted shader with
# its own colour map - rebuilt on an edit of either path.
func _build_inflated() -> void:
	if not _ready_done:
		return
	if _inflated_root != null:
		_inflated_root.queue_free()
		_inflated_root = null
	var scene := load(inflated_scene_path) as PackedScene
	if scene == null:
		push_warning("GlowerPose: inflated model failed to load (%s); it won't swell." % inflated_scene_path)
		return
	_inflated_root = scene.instantiate() as Node3D
	_inflated_root.name = "Inflated"
	add_child(_inflated_root)
	if _inflated_material == null:
		_inflated_material = ShaderMaterial.new()
		_inflated_material.shader = load(PAINTED_SHADER_PATH) as Shader
		_inflated_material.set_shader_parameter("albedo_tint", Color.WHITE)
	_inflated_material.set_shader_parameter("albedo_texture", load(inflated_albedo_path) as Texture2D)
	for node in _inflated_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		mi.material_override = _inflated_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_apply_inflated_scale()
	_show_inflated(_inflated)

func _apply_inflated_scale() -> void:
	if _inflated_root != null and (_swell_tween == null or not _swell_tween.is_running()):
		_inflated_root.scale = Vector3.ONE * inflated_scale

# --- Fins ---

# Welds vertices that share a position, then joins every triangle's
# corners: what is left connected is one piece (as SputterClaws does).
func _find_pieces() -> void:
	var vertices: PackedVector3Array = _skin.get_vertices()
	var indices: PackedInt32Array = _skin.arrays[Mesh.ARRAY_INDEX]
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

# Each piece to its fin's bone (or the body's), the mesh re-weighted, and
# each fin's hinge derived from its own vertices.
func _apply_selection() -> void:
	if not _ready_done or _skin == null:
		return
	var vertices: PackedVector3Array = _skin.get_vertices()
	var left := AABB(pectoral_box_min, pectoral_box_max - pectoral_box_min).abs()
	var right := AABB(Vector3(-pectoral_box_max.x, pectoral_box_min.y, pectoral_box_min.z), Vector3(pectoral_box_max.x - pectoral_box_min.x, pectoral_box_max.y - pectoral_box_min.y, pectoral_box_max.z - pectoral_box_min.z)).abs()
	var tail := AABB(tail_box_min, tail_box_max - tail_box_min).abs()
	var dorsal := AABB(dorsal_box_min, dorsal_box_max - dorsal_box_min).abs()
	var bone_of_piece := PackedInt32Array()
	bone_of_piece.resize(_piece_centroids.size())
	for piece in _piece_centroids.size():
		var centroid: Vector3 = _piece_centroids[piece]
		var bone: int = BODY_BONE
		if left.has_point(centroid):
			bone = PECTORAL_LEFT_BONE
		elif right.has_point(centroid):
			bone = PECTORAL_RIGHT_BONE
		elif tail.has_point(centroid):
			bone = TAIL_BONE
		elif dorsal.has_point(centroid):
			bone = DORSAL_BONE
		bone_of_piece[piece] = bone
	var bones := PackedInt32Array()
	bones.resize(vertices.size() * 4)
	var weights := PackedFloat32Array()
	weights.resize(vertices.size() * 4)
	var fin_points: Array[PackedVector3Array] = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	for index in vertices.size():
		var bone: int = bone_of_piece[_piece_of[index]]
		bones[index * 4] = bone
		weights[index * 4] = 1.0
		if bone != BODY_BONE:
			fin_points[bone].append(vertices[index])
	_skin.apply_weights(bones, weights)
	print("GlowerPose: fin vertices - pectorals %d / %d, tail %d, dorsal %d." % [fin_points[PECTORAL_LEFT_BONE].size(), fin_points[PECTORAL_RIGHT_BONE].size(), fin_points[TAIL_BONE].size(), fin_points[DORSAL_BONE].size()])
	# Root sides: the pectorals' innermost, the tail's frontmost, the
	# dorsal's lowest.
	_hinges[PECTORAL_LEFT_BONE] = _hinge_of(fin_points[PECTORAL_LEFT_BONE], Vector3.RIGHT)
	_hinges[PECTORAL_RIGHT_BONE] = _hinge_of(fin_points[PECTORAL_RIGHT_BONE], Vector3.LEFT)
	_hinges[TAIL_BONE] = _hinge_of(fin_points[TAIL_BONE], Vector3.BACK)
	_hinges[DORSAL_BONE] = _hinge_of(fin_points[DORSAL_BONE], Vector3.DOWN)
	for bone in [PECTORAL_LEFT_BONE, PECTORAL_RIGHT_BONE, TAIL_BONE, DORSAL_BONE]:
		if fin_points[bone].is_empty():
			push_warning("GlowerPose: no piece in fin box %d; that fin holds still." % bone)

# The centre of the hinge_fraction of `points` furthest along `toward`.
func _hinge_of(points: PackedVector3Array, toward: Vector3) -> Vector3:
	if points.is_empty():
		return Vector3.ZERO
	var low: float = INF
	var high: float = -INF
	for point in points:
		low = minf(low, point.dot(toward))
		high = maxf(high, point.dot(toward))
	var cut: float = high - hinge_fraction * (high - low)
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	for point in points:
		if point.dot(toward) >= cut:
			sum += point
			count += 1
	return sum / float(maxi(count, 1))
