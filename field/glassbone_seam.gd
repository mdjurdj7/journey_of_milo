extends Node3D
class_name GlassboneSeam

# A pale shard of Glassbone standing out of the sand, worked once for
# glassbone_amount Glassbone. Floor 2 rolls it against the trough on the
# dragonflies' island (the island_reward event slot): the same rule as
# the trough's - inert while any member of guard_slot's encounter stands,
# read live every tick, so it wakes the moment the last of them falls.
# Class-neutral.
#
# Awake, the trough's distance language (PropApproach): inside approach_
# radius the world line shows - approach_line while the shard stands,
# return_line once it has been worked - once per visit into the radius;
# a left click on the shard in reach opens its choice (TroughChoice, this
# its host): "Work the seam (+1 Glassbone)" or Leave it. Working grants
# the Glassbone through RunState.add_glassbone(), says worked_line, and
# leaves the stump; Leave it changes nothing, and the next click opens it
# again. Either is logged ("seam").
#
# Once per run: worked ids live in a static set keyed by seam_id (the
# floor's slot/option path, set by RegionField), cleared by RunState.
# new_run() through reset_worked() - the trough's rule.
#
# The shard is shard_model_path (its base at y 0, Y up) with the Glassbone
# material over its whole mesh, its own maps ignored (glassbone_material_
# path - pale, slightly translucent, never glowing; its values are in
# 04_FIELD_ASSET_SPEC). Turned seam_yaw_degrees about its own axis, it
# leans lean_degrees toward the compass yaw lean_yaw_degrees - (cos, 0,
# -sin); floor 2's points it away from the island's approach - and sinks
# sink_fraction of its length along that axis into the sand at this
# node's XZ, so the rough foot is under and the smooth blade shows. The
# node grounds itself on the relief there and stays unrotated: every
# angle is the shard's. One box round what stands above the sand is its
# collision, MAKE_STATIC so the field's freeze leaves it in the space and
# the walk grid steps round it, and its click rect.
#
# Worked, the shard is gone: a stump - the shard's own mesh cut stump_
# height_m above the sand, capped by a low broken peak - a dark scar in
# the gouge material round its foot, and splinter_count pale splinters
# lying beside it, scattered by splinter_seed so every load lays them the
# same.

const CHOICE_SCENE_PATH := "res://battle/trough_choice.tscn"
const GROUP := &"seams"

@export_group("Shard")
@export_file("*.glb", "*.tscn") var shard_model_path: String = "res://assets/models/props/glassbone_shard/glassbone_shard.glb":
	set(value):
		shard_model_path = value
		if _shard != null:
			_shard.queue_free()
			_shard = null
		_rebuild()
# Its turn about its own axis, on top of the FloorProp's yaw.
@export var seam_yaw_degrees: float = 0.0:
	set(value):
		seam_yaw_degrees = value
		_rebuild()
# How far it leans from upright, and which way: a compass yaw, its top
# toward (cos, 0, -sin).
@export_range(0.0, 80.0, 0.5) var lean_degrees: float = 35.0:
	set(value):
		lean_degrees = value
		_rebuild()
@export var lean_yaw_degrees: float = 0.0:
	set(value):
		lean_yaw_degrees = value
		_rebuild()
# The share of its length under the sand, along its own axis.
@export_range(0.0, 0.9, 0.005) var sink_fraction: float = 0.375:
	set(value):
		sink_fraction = value
		_rebuild()
@export_file("*.tres") var glassbone_material_path: String = "res://field/glassbone_material.tres":
	set(value):
		glassbone_material_path = value
		_rebuild()
@export_group("")

@export_group("Worked")
@export_file("*.tres") var gouge_material_path: String = "res://field/glassbone_gouge_material.tres":
	set(value):
		gouge_material_path = value
		_rebuild()
# The stump: the shard cut this high above the sand, and its broken top's
# peak over the cut.
@export var stump_height_m: float = 0.06:
	set(value):
		stump_height_m = value
		_rebuild()
@export var stump_peak_m: float = 0.025:
	set(value):
		stump_peak_m = value
		_rebuild()
# The scar round its foot: its radius, how far each edge point strays
# from it (a share of it), how many points, its lift off the sand.
@export var scar_radius_m: float = 0.28:
	set(value):
		scar_radius_m = value
		_rebuild()
@export_range(0.0, 0.9, 0.01) var scar_jitter: float = 0.3:
	set(value):
		scar_jitter = value
		_rebuild()
@export var scar_points: int = 11:
	set(value):
		scar_points = value
		_rebuild()
@export var scar_lift_m: float = 0.004:
	set(value):
		scar_lift_m = value
		_rebuild()
# The splinters: how many, each one's length (min, max), width and
# thickness, how far from the stump they lie (min, max), and the seed that
# scatters them.
@export var splinter_count: int = 4:
	set(value):
		splinter_count = value
		_rebuild()
@export var splinter_length_m: Vector2 = Vector2(0.07, 0.15):
	set(value):
		splinter_length_m = value
		_rebuild()
@export var splinter_width_m: float = 0.018:
	set(value):
		splinter_width_m = value
		_rebuild()
@export var splinter_thickness_m: float = 0.008:
	set(value):
		splinter_thickness_m = value
		_rebuild()
@export var splinter_distance_m: Vector2 = Vector2(0.2, 0.42):
	set(value):
		splinter_distance_m = value
		_rebuild()
@export var splinter_seed: int = 7:
	set(value):
		splinter_seed = value
		_rebuild()
@export_group("")

@export_group("Work")
@export var glassbone_amount: int = 1
# The EncounterSlot.slot_id whose encounter guards it ("island" on floor
# 2, through the FloorProp's overrides). Empty = awake from the start.
@export var guard_slot: StringName = &""
# %d is glassbone_amount.
@export var work_text_format: String = "Work the seam (+%d Glassbone)"
@export var leave_text: String = "Leave it"
@export_group("")

@export_group("Approach")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		if _approach != null:
			_approach.set_radius(approach_radius)
@export_multiline var approach_line: String = "A pale shard in the sand, hard as glass."
@export_multiline var worked_line: String = "It comes away in one piece."
@export_multiline var return_line: String = "Only the scar is left."
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
@export_group("")

# Set by RegionField when it spawns the prop.
@export var seam_id: String = ""
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# seam_id -> true once worked this run.
static var _worked: Dictionary = {}

static func reset_worked() -> void:
	_worked.clear()

var _placement_yaw: float = 0.0
var _ground: Ground = null
var _shard: Node3D = null
var _stump: MeshInstance3D = null
var _scar: MeshInstance3D = null
var _splinters: MeshInstance3D = null
var _collision_body: StaticBody3D = null
var _collision_shape: CollisionShape3D = null
# What stands above the sand, in this node's frame: the shard's box, and
# the stump's once it's worked.
var _shard_box: AABB = AABB()
var _stump_box: AABB = AABB()
var _approach: PropApproach = null
var _choice: TroughChoice = null

# FloorProp's placement: XZ here (it grounds itself), the entry's yaw
# under seam_yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw
	_rebuild()

func _ready() -> void:
	add_to_group(GROUP)
	rotation = Vector3.ZERO
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("GlassboneSeam '%s': ground_path did not resolve to a Ground; not grounded." % name)
	else:
		_ground.relief_rebuilt.connect(_rebuild)
	_collision_body = StaticBody3D.new()
	_collision_body.name = "Collision"
	# RegionField's freeze would otherwise take the body out of the
	# physics space (the trough's reason).
	_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	_collision_shape = CollisionShape3D.new()
	_collision_shape.shape = BoxShape3D.new()
	_collision_body.add_child(_collision_shape)
	add_child(_collision_body)
	_stump = _remains_mesh("Stump", true)
	_scar = _remains_mesh("Scar", false)
	_splinters = _remains_mesh("Splinters", true)
	_rebuild()
	_spawn_approach()

func _remains_mesh(mesh_name: String, casts_shadow: bool) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = mesh_name
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visible = false
	add_child(mesh_instance)
	return mesh_instance

# Everything again: grounded, the shard placed, the remains cut and laid,
# the state shown.
func _rebuild() -> void:
	if not is_inside_tree() or _collision_body == null:
		return
	_ground_to_relief()
	var faces: PackedVector3Array = _place_shard()
	_build_stump(faces)
	_build_scar()
	_build_splinters()
	_apply_state()

# --- The shard ---

func _ground_to_relief() -> void:
	if _ground != null:
		global_position.y = _sand_height_at(global_position)

func _sand_height_at(world: Vector3) -> float:
	if _ground == null:
		return global_position.y
	var local: Vector3 = _ground.to_local(Vector3(world.x, 0.0, world.z))
	return _ground.get_height_at(Vector2(local.x, local.z))

# The sand under a point of this node's frame, in this node's frame.
func _sand_y(local_x: float, local_z: float) -> float:
	return _sand_height_at(to_global(Vector3(local_x, 0.0, local_z))) - global_position.y

func _shard_meshes() -> Array[MeshInstance3D]:
	var meshes: Array[MeshInstance3D] = []
	if _shard != null:
		for node in _shard.find_children("*", "MeshInstance3D", true, false):
			meshes.append(node as MeshInstance3D)
	return meshes

# The shard turned, leant and sunk, in its material, and its box above
# the sand; returns its triangles in this node's frame, for the stump.
func _place_shard() -> PackedVector3Array:
	var faces := PackedVector3Array()
	if _shard == null:
		var scene := load(shard_model_path) as PackedScene
		if scene == null:
			push_warning("GlassboneSeam '%s': could not load %s; no shard." % [name, shard_model_path])
			return faces
		_shard = scene.instantiate() as Node3D
		_shard.name = "Shard"
		add_child(_shard)
	var material: Material = _material(glassbone_material_path)
	var top: float = 0.0
	for mesh_instance in _shard_meshes():
		mesh_instance.material_override = material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var own: AABB = (_shard.global_transform.affine_inverse() * mesh_instance.global_transform) * mesh_instance.get_aabb()
		top = maxf(top, own.end.y)
	var lean: float = deg_to_rad(lean_degrees)
	var compass: float = deg_to_rad(lean_yaw_degrees)
	var toward := Vector3(cos(compass), 0.0, -sin(compass))
	var axis_dir: Vector3 = Vector3.UP * cos(lean) + toward * sin(lean)
	var spin := Basis(Vector3.UP, deg_to_rad(seam_yaw_degrees + _placement_yaw))
	var tilt: Basis = Basis(Vector3.UP.cross(toward).normalized(), lean) if lean > 0.0 else Basis.IDENTITY
	_shard.transform = Transform3D(tilt * spin, -axis_dir * top * sink_fraction)
	var to_here: Transform3D = global_transform.affine_inverse()
	var above := PackedVector3Array()
	for mesh_instance in _shard_meshes():
		if mesh_instance.mesh == null:
			continue
		var frame: Transform3D = to_here * mesh_instance.global_transform
		for vertex in mesh_instance.mesh.get_faces():
			var point: Vector3 = frame * vertex
			faces.append(point)
			if point.y >= 0.0:
				above.append(point)
	_shard_box = _box_of(above)
	return faces

static func _box_of(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for point in points:
		box = box.expand(point)
	return box

func _material(path: String) -> Material:
	return load(path) as Material if ResourceLoader.exists(path) else null

# --- What working it leaves ---

# The shard's own triangles below stump_height_m, and its broken top: a
# fan from a peak stump_peak_m over the cut's middle to the cut's rim.
func _build_stump(faces: PackedVector3Array) -> void:
	_stump.mesh = null
	_stump_box = AABB()
	if faces.is_empty():
		return
	var cut: float = stump_height_m
	var kept := PackedVector3Array()
	var rim := PackedVector3Array()
	for i in range(0, faces.size() - 2, 3):
		var corners: Array[Vector3] = [faces[i], faces[i + 1], faces[i + 2]]
		var polygon: Array[Vector3] = []
		for k in 3:
			var a: Vector3 = corners[k]
			var b: Vector3 = corners[(k + 1) % 3]
			if a.y <= cut:
				polygon.append(a)
			if (a.y <= cut) != (b.y <= cut):
				var crossing: Vector3 = a.lerp(b, (cut - a.y) / (b.y - a.y))
				polygon.append(crossing)
				rim.append(crossing)
		for k in range(1, polygon.size() - 1):
			kept.append_array([polygon[0], polygon[k], polygon[k + 1]])
	if kept.is_empty():
		return
	if not rim.is_empty():
		var middle := Vector3.ZERO
		for point in rim:
			middle += point
		middle /= float(rim.size())
		var ordered: Array[Vector3] = []
		for point in rim:
			ordered.append(point)
		ordered.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			return atan2(a.z - middle.z, a.x - middle.x) < atan2(b.z - middle.z, b.x - middle.x))
		var peak := Vector3(middle.x, cut + stump_peak_m, middle.z)
		for k in ordered.size():
			_append_up(kept, peak, ordered[k], ordered[(k + 1) % ordered.size()])
	var stood := PackedVector3Array()
	for point in kept:
		if point.y >= 0.0:
			stood.append(point)
	_stump_box = _box_of(stood)
	_stump.mesh = _mesh_of(kept)
	_stump.material_override = _material(glassbone_material_path)

# A triangle wound to face up.
static func _append_up(into: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).y < 0.0:
		into.append_array([a, c, b])
	else:
		into.append_array([a, b, c])

static func _mesh_of(triangles: PackedVector3Array) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for vertex in triangles:
		surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

# An uneven dark patch round the stump's foot, on the sand.
func _build_scar() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = splinter_seed + 1
	var count: int = maxi(scar_points, 3)
	var centre := Vector3(0.0, _sand_y(0.0, 0.0) + scar_lift_m, 0.0)
	var edge: Array[Vector3] = []
	for k in count:
		var angle: float = TAU * (float(k) + rng.randf_range(-0.3, 0.3)) / float(count)
		var radius: float = scar_radius_m * (1.0 + rng.randf_range(-scar_jitter, scar_jitter))
		var x: float = cos(angle) * radius
		var z: float = -sin(angle) * radius
		edge.append(Vector3(x, _sand_y(x, z) + scar_lift_m, z))
	var triangles := PackedVector3Array()
	for k in count:
		_append_up(triangles, centre, edge[k], edge[(k + 1) % count])
	_scar.mesh = _mesh_of(triangles)
	_scar.material_override = _material(gouge_material_path)

# Thin pale slivers lying flat beside it: each a long low diamond with a
# ridge along it.
func _build_splinters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = splinter_seed
	var triangles := PackedVector3Array()
	for n in maxi(splinter_count, 0):
		var angle: float = rng.randf_range(0.0, TAU)
		var distance: float = rng.randf_range(splinter_distance_m.x, splinter_distance_m.y)
		var length: float = rng.randf_range(splinter_length_m.x, splinter_length_m.y)
		var turn := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var x: float = cos(angle) * distance
		var z: float = -sin(angle) * distance
		var at := Vector3(x, _sand_y(x, z), z)
		var tip_a: Vector3 = at + turn * Vector3(length * 0.5, 0.0, 0.0)
		var tip_b: Vector3 = at + turn * Vector3(-length * 0.5, 0.0, 0.0)
		var side_a: Vector3 = at + turn * Vector3(length * 0.1, 0.0, splinter_width_m * 0.5)
		var side_b: Vector3 = at + turn * Vector3(-length * 0.1, 0.0, -splinter_width_m * 0.5)
		var ridge: Vector3 = at + Vector3(0.0, splinter_thickness_m, 0.0)
		for corner: Vector3 in [side_a, side_b]:
			_append_up(triangles, ridge, tip_a, corner)
			_append_up(triangles, ridge, tip_b, corner)
	_splinters.mesh = _mesh_of(triangles) if not triangles.is_empty() else null
	_splinters.material_override = _material(glassbone_material_path)

# The shard while it stands; the stump, scar and splinters once worked -
# and the collision round whichever stands.
func _apply_state() -> void:
	var worked: bool = is_worked()
	if _shard != null:
		_shard.visible = not worked
	_stump.visible = worked
	_scar.visible = worked
	_splinters.visible = worked
	var box: AABB = _standing_box()
	var shape := _collision_shape.shape as BoxShape3D
	shape.size = Vector3(maxf(box.size.x, 0.05), maxf(box.size.y, 0.05), maxf(box.size.z, 0.05))
	_collision_shape.position = box.get_center()

func _standing_box() -> AABB:
	return _stump_box if is_worked() else _shard_box

# --- The work ---

func _spawn_approach() -> void:
	_approach = PropApproach.new()
	_approach.name = "Approach"
	_approach.warning_label = "GlassboneSeam"
	_approach.can_speak = is_awake
	_approach.on_visit = func() -> void: _say(return_line if is_worked() else approach_line)
	_approach.can_open_from = can_open_from
	_approach.screen_rect = get_screen_rect
	_approach.open_requested.connect(_on_open_requested)
	add_child(_approach)
	_approach.set_radius(approach_radius)

# No member of guard_slot's encounter still standing (TroughProp.is_
# awake()'s test).
func is_awake() -> bool:
	if guard_slot == &"":
		return true
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.slot_id != guard_slot:
			continue
		if not enemy.is_queued_for_deletion() and not enemy.is_defeated():
			return false
	return true

func is_worked() -> bool:
	return _worked.has(_seam_id())

# Awake, not worked, and the Wanderer at `from` within approach_radius.
func can_open_from(from: Vector3) -> bool:
	if is_worked() or not is_awake():
		return false
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= approach_radius

func _on_open_requested() -> void:
	if _choice != null and is_instance_valid(_choice):
		return
	var region_field: RegionField = _approach.get_region_field()
	var hud := region_field.get_node_or_null(^"FieldHUD") as CanvasLayer if region_field != null else null
	if hud == null:
		push_warning("GlassboneSeam '%s': FieldHUD not found; no choice." % name)
		return
	var scene := load(CHOICE_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("GlassboneSeam '%s': could not load %s; no choice." % [name, CHOICE_SCENE_PATH])
		return
	_choice = scene.instantiate() as TroughChoice
	_choice.setup(self, region_field.wanderer, region_field)
	hud.add_child(_choice)

# TroughChoice's items: the work, then Leave it.
func get_choice_labels() -> Array[String]:
	var work_text: String = work_text_format % glassbone_amount if work_text_format.contains("%d") else work_text_format
	return [work_text, leave_text]

# TroughChoice's pick: 0 works it, the last leaves it. Logged either way.
func choose(index: int) -> void:
	var worked: bool = index == 0 and not is_worked()
	if worked:
		work()
	RunLogger.event("seam", {"worked": worked, "amount": glassbone_amount if worked else 0, "glassbone_after": RunState.glassbone})

# The Glassbone, the line, the stump - spent for the run. False, and
# nothing changes, when it was worked already.
func work() -> bool:
	if is_worked():
		return false
	_worked[_seam_id()] = true
	RunState.add_glassbone(glassbone_amount)
	print("GlassboneSeam '%s': worked, +%d Glassbone (now %d)." % [name, glassbone_amount, RunState.glassbone])
	if _approach != null:
		_approach.mark_said()
	_say(worked_line)
	_apply_state()
	return true

func _say(text: String) -> void:
	if _approach != null:
		_approach.say(text, hold_seconds, fade_seconds)

# seam_id if the spawner set one; else the floor's path and this node's
# name.
func _seam_id() -> String:
	if not seam_id.is_empty():
		return seam_id
	var region_field := get_node_or_null(region_field_path) as RegionField
	var floor_data: FloorData = region_field.get_floor_data() if region_field != null else null
	return "%s:%s" % [floor_data.resource_path if floor_data != null else "", name]

# What stands, its box on screen, grown by padding_px (TroughProp's rect).
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null:
		return Rect2()
	var box: AABB = _standing_box()
	if not box.has_volume():
		return Rect2()
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_global(box.get_endpoint(i))
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
