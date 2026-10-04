extends Node3D
class_name HitchingPost

# A post someone sank to tie a beast to, and the beast still tied to it -
# floor 3's Wardling, a creature that stayed. A FloorProp: placed from
# FloorData.props, grounded on the relief, aged by placement alone (sunk
# sink_depth, leaning lean_degrees), never damaged.
#
# The model is hitching_post.glb (0.23 x 1.30 high x 0.28 glb units,
# origin at the base; an iron ring on a bracket on its +Z face) at
# model_scale, 0.923 for a 1.2 m post, on the props' shared flat material
# (Hull._get_shared_flat_material()) tinted post_tint - the hulls' tint:
# silvered wood a step darker than the sand. Its own textures are not used.
#
# Facing: the ring turns toward the tethered enemy (tether_enemy_index -
# the FloorData.enemies index, so RegionField's "FieldEnemy<n>"), with
# the FloorProp's yaw and ring_yaw_offset_degrees on top. No enemy: the
# FloorProp's yaw alone.
#
# The rope: a slack catenary from the ring (ring_point, glb units, the
# inside bottom of the ring) to the enemy's harness (FieldEnemy.get_
# harness_point()), a thin dark tube built here and rebuilt whenever
# either end moves - so it connects wherever the two are placed, and
# follows the body through a fight's turn, lunge and recoil (the rope
# runs at PROCESS_MODE_ALWAYS, through the battle freeze). Its length is
# rope_slack times the distance between its ends, measured while the
# field runs; frozen for a fight, the length holds, so a lunge takes up
# slack rather than growing rope. Decorative only: no collision, and the
# body is never held by it. Below the sand it lies on the sand.
#
# On his death the body goes (freed with the win, or sinking): the rope
# stays tied to the ring and its loose end drops, over rope_drop_seconds,
# to the sand under where the harness was, and lies there slack.

const MODEL_SCENE_PATH := "res://assets/models/props/hitching_post/hitching_post.glb"

@export_group("Model")
@export var model_scale: float = 0.923:
	set(value):
		model_scale = value
		_apply_model()
@export var post_tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		post_tint = value
		if _material != null:
			_material.albedo_color = value
@export var sink_depth: float = 0.08:
	set(value):
		sink_depth = value
		_apply_pose()
@export var lean_degrees: float = 3.5:
	set(value):
		lean_degrees = value
		_apply_pose()
# Which way the top leans, degrees round the post's own up from its ring
# face (+Z): 0 = toward the tethered enemy, as if pulled over the years.
@export var lean_direction_degrees: float = 0.0:
	set(value):
		lean_direction_degrees = value
		_apply_pose()
# On top of the ring's turn toward the enemy and the FloorProp's yaw.
@export var ring_yaw_offset_degrees: float = 0.0:
	set(value):
		ring_yaw_offset_degrees = value
		_apply_yaw()
@export_group("")

@export_group("Rope")
# FloorData.enemies index of the body the rope runs to; -1 = no rope.
@export var tether_enemy_index: int = -1:
	set(value):
		tether_enemy_index = value
		if is_node_ready():
			_find_enemy()
			_apply_yaw()
# Where the rope is tied: the inside bottom of the ring, glb units.
@export var ring_point: Vector3 = Vector3(0.015, 0.97, 0.12):
	set(value):
		ring_point = value
		_rope_dirty = true
# The rope's length over the straight distance between its ends.
@export var rope_slack: float = 1.15:
	set(value):
		rope_slack = value
		_rope_dirty = true
@export var rope_radius: float = 0.015:
	set(value):
		rope_radius = value
		_rope_dirty = true
@export var rope_segments: int = 24:
	set(value):
		rope_segments = value
		_rope_dirty = true
@export var rope_sides: int = 6:
	set(value):
		rope_sides = value
		_rope_dirty = true
@export var rope_color: Color = Color(0.13, 0.12, 0.11):
	set(value):
		rope_color = value
		if _rope_material != null:
			_rope_material.albedo_color = value
@export var rope_drop_seconds: float = 0.5
@export_group("")

@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _placement_yaw: float = 0.0
# Pose carries the sink and the lean; the model sits grounded under it.
var _pose: Node3D = null
var _model: Node3D = null
var _material: StandardMaterial3D = null
# The model's bbox in its own unscaled space.
var _model_aabb: AABB = AABB()
var _collision_box: BoxShape3D = null
var _collision_shape_node: CollisionShape3D = null
var _ground: Ground = null
var _enemy: FieldEnemy = null
var _rope: MeshInstance3D = null
var _rope_material: StandardMaterial3D = null
var _rope_dirty: bool = true
var _rope_length: float = 0.0
var _last_ring: Vector3 = Vector3.INF
var _last_end: Vector3 = Vector3.INF
# The harness where it was last seen, for the drop.
var _harness: Vector3 = Vector3.ZERO
var _has_harness: bool = false
# The drop: started once the body goes, from the harness to the sand.
var _dropping: bool = false
var _drop_elapsed: float = 0.0
var _drop_to: Vector3 = Vector3.ZERO

# FloorProp's placement (RegionField._spawn_floor_props()): XZ here, Y
# from the relief; the entry's yaw on top of the ring's facing.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw

func _ready() -> void:
	# The rope follows the body through the battle freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_spawn_model()
	_spawn_rope()
	_find_enemy()
	_apply_yaw()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("HitchingPost '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_model() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("HitchingPost: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	_pose = Node3D.new()
	_pose.name = "Pose"
	add_child(_pose)
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	_pose.add_child(_model)
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = post_tint
	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var mi_aabb: AABB = (_model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		_model_aabb = mi_aabb if not has_aabb else _model_aabb.merge(mi_aabb)
		has_aabb = true
	var collision_body := StaticBody3D.new()
	collision_body.name = "Collision"
	# The bundle's reason: RegionField's freeze would otherwise take the
	# body out of the physics space.
	collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_collision_box = BoxShape3D.new()
	_collision_shape_node = CollisionShape3D.new()
	_collision_shape_node.shape = _collision_box
	collision_body.add_child(_collision_shape_node)
	add_child(collision_body)
	_apply_model()

# The scale, the grounding (bbox bottom on Pose's origin) and the
# collision box round the scaled footprint, from the sand to the top.
func _apply_model() -> void:
	if _model == null:
		return
	_model.scale = Vector3.ONE * model_scale
	_model.position = Vector3(0.0, -_model_aabb.position.y * model_scale, 0.0)
	var size: Vector3 = _model_aabb.size * model_scale
	var height: float = maxf(size.y - sink_depth, 0.01)
	_collision_box.size = Vector3(size.x, height, size.z)
	var centre: Vector3 = _model_aabb.get_center() * model_scale
	_collision_shape_node.position = Vector3(centre.x, height * 0.5, centre.z)
	_rope_dirty = true

# The sink and the lean on Pose, round the post's base: the top moves
# toward lean_direction_degrees.
func _apply_pose() -> void:
	if _pose == null:
		return
	var direction := Vector3(sin(deg_to_rad(lean_direction_degrees)), 0.0, cos(deg_to_rad(lean_direction_degrees)))
	var axis: Vector3 = Vector3.UP.cross(direction).normalized()
	_pose.transform = Transform3D(Basis(axis, deg_to_rad(lean_degrees)), Vector3(0.0, -sink_depth, 0.0))
	_apply_model()

# The ring (+Z) toward the enemy, then the placement's and the offset's yaw.
func _apply_yaw() -> void:
	if not is_inside_tree():
		return
	var toward: float = 0.0
	if _enemy != null and is_instance_valid(_enemy):
		var offset := Vector3(_enemy.global_position.x - global_position.x, 0.0, _enemy.global_position.z - global_position.z)
		if offset.length() > 0.0001:
			toward = atan2(offset.x, offset.z)
	rotation = Vector3(0.0, toward + deg_to_rad(_placement_yaw + ring_yaw_offset_degrees), 0.0)
	_apply_pose()

func _find_enemy() -> void:
	_enemy = null
	if tether_enemy_index < 0:
		return
	var region_field := get_node_or_null(region_field_path)
	if region_field == null:
		push_warning("HitchingPost '%s': region_field_path did not resolve; no rope." % name)
		return
	_enemy = region_field.get_node_or_null(NodePath("FieldEnemy%d" % tether_enemy_index)) as FieldEnemy
	if _enemy == null:
		push_warning("HitchingPost '%s': no FieldEnemy%d to tie the rope to." % [name, tether_enemy_index])

func _ground_to_relief() -> void:
	if _ground == null:
		return
	global_position.y = _ground_height(global_position)
	_rope_dirty = true

func _ground_height(point: Vector3) -> float:
	if _ground == null:
		return point.y
	var local_xz: Vector3 = _ground.to_local(Vector3(point.x, 0.0, point.z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

func _spawn_rope() -> void:
	_rope = MeshInstance3D.new()
	_rope.name = "Rope"
	# Built in world space.
	_rope.top_level = true
	_rope.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_rope_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_rope_material.albedo_color = rope_color
	# A thin tube seen from every side; no winding to get wrong.
	_rope_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_rope.material_override = _rope_material
	add_child(_rope)

# Where the rope is tied, in the world.
func get_ring_point() -> Vector3:
	if _model == null:
		return global_position
	return _model.global_transform * ring_point

# The loose end, in the world: the harness while the body stands; once it
# has gone, dropping to (then lying on) the sand under the last harness.
func get_rope_end() -> Vector3:
	return _drop_to.lerp(_harness, 1.0 - _drop_fraction()) if _dropping else _harness

func _drop_fraction() -> float:
	if rope_drop_seconds <= 0.0:
		return 1.0
	var t: float = clampf(_drop_elapsed / rope_drop_seconds, 0.0, 1.0)
	return t * t

func _body_gone() -> bool:
	return _enemy == null or not is_instance_valid(_enemy) or _enemy.is_queued_for_deletion() or _enemy.is_settling()

func _process(delta: float) -> void:
	if _model == null or (tether_enemy_index < 0 and not _has_harness):
		_rope.visible = false
		return
	if not _dropping:
		if _body_gone():
			if not _has_harness:
				_rope.visible = false
				return
			_dropping = true
			_drop_elapsed = 0.0
			_drop_to = Vector3(_harness.x, _ground_height(_harness), _harness.z)
		else:
			_harness = _enemy.get_harness_point()
			_has_harness = true
	else:
		_drop_elapsed += delta
	var ring: Vector3 = get_ring_point()
	var end: Vector3 = get_rope_end()
	# The length is measured while the field runs and the body stands; a
	# fight's freeze and the drop keep it.
	var region_field := get_node_or_null(region_field_path) as Node
	var field_running: bool = region_field == null or region_field.can_process()
	if field_running and not _dropping:
		var length: float = ring.distance_to(end) * maxf(rope_slack, 1.0)
		if not is_equal_approx(length, _rope_length):
			_rope_length = length
			_rope_dirty = true
	if _rope_dirty or not ring.is_equal_approx(_last_ring) or not end.is_equal_approx(_last_end):
		_last_ring = ring
		_last_end = end
		_rope_dirty = false
		_build_rope(ring, end)

# Points along a catenary of _rope_length from `a` to `b` (straight when
# the rope is taut), lifted onto the sand wherever it would dip under.
func _rope_points(a: Vector3, b: Vector3) -> PackedVector3Array:
	var segments: int = maxi(rope_segments, 2)
	var points := PackedVector3Array()
	var across := Vector3(b.x - a.x, 0.0, b.z - a.z)
	var h: float = across.length()
	var v: float = b.y - a.y
	var chord: float = a.distance_to(b)
	var taut: bool = _rope_length <= chord * 1.0001 or h < 0.001
	var catenary_a: float = 1.0
	var x0: float = 0.0
	var direction: Vector3 = across / h if h > 0.0 else Vector3.ZERO
	if not taut:
		# sinh(z) / z = sqrt(L^2 - v^2) / h, z = h / 2a, by bisection.
		var target: float = sqrt(_rope_length * _rope_length - v * v) / h
		var lo: float = 0.0001
		var hi: float = 30.0
		for i in 60:
			var mid: float = (lo + hi) * 0.5
			if sinh(mid) / mid < target:
				lo = mid
			else:
				hi = mid
		catenary_a = h / (2.0 * (lo + hi) * 0.5)
		x0 = h * 0.5 - catenary_a * atanh(clampf(v / _rope_length, -0.999999, 0.999999))
	for i in segments + 1:
		var t: float = float(i) / float(segments)
		var point: Vector3
		if taut:
			point = a.lerp(b, t)
		else:
			var x: float = t * h
			var y: float = catenary_a * (cosh((x - x0) / catenary_a) - cosh(x0 / catenary_a))
			point = a + direction * x + Vector3.UP * y
		var floor_y: float = _ground_height(point) + rope_radius
		if point.y < floor_y:
			point.y = floor_y
		points.append(point)
	return points

# A thin tube of rope_sides round the points, in world space.
func _build_rope(a: Vector3, b: Vector3) -> void:
	var points: PackedVector3Array = _rope_points(a, b)
	var sides: int = maxi(rope_sides, 3)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in points.size():
		var tangent: Vector3 = (points[mini(i + 1, points.size() - 1)] - points[maxi(i - 1, 0)]).normalized()
		var side: Vector3 = tangent.cross(Vector3.UP)
		if side.length() < 0.001:
			side = tangent.cross(Vector3.RIGHT)
		side = side.normalized()
		var up: Vector3 = side.cross(tangent).normalized()
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for s in sides:
			var angle: float = TAU * float(s) / float(sides)
			var normal: Vector3 = side * cos(angle) + up * sin(angle)
			ring.append(points[i] + normal * rope_radius)
			ring_normals.append(normal)
		rings.append(ring)
		normals.append(ring_normals)
	for i in points.size() - 1:
		for s in sides:
			var n: int = (s + 1) % sides
			for corner: Vector2i in [Vector2i(i, s), Vector2i(i + 1, s), Vector2i(i + 1, n), Vector2i(i, s), Vector2i(i + 1, n), Vector2i(i, n)]:
				tool.set_normal(normals[corner.x][corner.y])
				tool.add_vertex(rings[corner.x][corner.y])
	_rope.mesh = tool.commit()
	_rope.global_transform = Transform3D.IDENTITY
	_rope.visible = true
