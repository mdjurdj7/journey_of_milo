extends Node3D
class_name GlassboneSeam

# A pale vein of Glassbone in a low rock, worked once for glassbone_
# amount Glassbone. Floor 2 rolls it against the trough on the
# dragonflies' island (the island_reward event slot): the same rule as
# the trough's - inert while any member of guard_slot's encounter stands,
# read live every tick, so it wakes the moment the last of them falls.
# Class-neutral.
#
# Awake, the trough's distance language (PropApproach): inside approach_
# radius the world line shows - approach_line while the vein is there,
# return_line once it has been worked - once per visit into the radius;
# a left click on the rock in reach opens its choice (TroughChoice, this
# its host): "Work the seam (+1 Glassbone)" or Leave it. Working grants
# the Glassbone through RunState.add_glassbone(), says worked_line, and
# leaves a dark gouge where the vein was; Leave it changes nothing, and
# the next click opens it again. Either is logged ("seam").
#
# Once per run: worked ids live in a static set keyed by seam_id (the
# floor's slot/option path, set by RegionField), cleared by RunState.
# new_run() through reset_worked() - the trough's rule.
#
# The rock is a BaskingSlab - basking_slab.glb on its own colour map,
# grounded, its box its collision - a stand-in until a seam model of its
# own exists. The vein is a strip laid along the rock's top: vein_samples
# points along its length (local X), wandering vein_wander_m either side,
# each point dropped onto the rock's own triangles from above and lifted
# vein_lift_m, so it hugs the stone. It wears the Glassbone material
# (glassbone_material_path - pale, slightly translucent, never glowing;
# its values are in 04_FIELD_ASSET_SPEC), and once worked the gouge
# material, gouge_width_scale wider - the vein taken, the scar left.

const CHOICE_SCENE_PATH := "res://battle/trough_choice.tscn"
const SLAB_SCENE_PATH := "res://field/basking_slab.tscn"
const GROUP := &"seams"

@export_group("Rock")
# The rock's facing, on top of the FloorProp's yaw.
@export var seam_yaw_degrees: float = 0.0:
	set(value):
		seam_yaw_degrees = value
		_apply_yaw()
@export var rock_scale: Vector3 = Vector3.ONE:
	set(value):
		rock_scale = value
		if _slab != null:
			_slab.model_scale = rock_scale
			_build_vein()
@export_group("")

@export_group("Vein")
@export_file("*.tres") var glassbone_material_path: String = "res://field/glassbone_material.tres":
	set(value):
		glassbone_material_path = value
		_apply_vein_material()
@export_file("*.tres") var gouge_material_path: String = "res://field/glassbone_gouge_material.tres":
	set(value):
		gouge_material_path = value
		_apply_vein_material()
# How much of the rock's length the vein runs, centred on it.
@export_range(0.1, 1.0, 0.01) var vein_length_fraction: float = 0.7:
	set(value):
		vein_length_fraction = value
		_build_vein()
@export var vein_width_m: float = 0.06:
	set(value):
		vein_width_m = value
		_build_vein()
# Its wander either side of the rock's spine, and how many times it
# crosses over along its length.
@export var vein_wander_m: float = 0.07:
	set(value):
		vein_wander_m = value
		_build_vein()
@export var vein_wander_cycles: float = 1.3:
	set(value):
		vein_wander_cycles = value
		_build_vein()
# Off the spine, across the rock (local Z), metres.
@export var vein_offset_m: float = 0.0:
	set(value):
		vein_offset_m = value
		_build_vein()
@export var vein_lift_m: float = 0.004:
	set(value):
		vein_lift_m = value
		_build_vein()
@export var vein_samples: int = 24:
	set(value):
		vein_samples = value
		_build_vein()
# The gouge, against the vein's width.
@export var gouge_width_scale: float = 1.4:
	set(value):
		gouge_width_scale = value
		_build_vein()
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
@export_multiline var approach_line: String = "A pale vein in the rock, hard as glass."
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
var _slab: BaskingSlab = null
var _vein: MeshInstance3D = null
var _approach: PropApproach = null
var _choice: TroughChoice = null

# FloorProp's placement: XZ here (the rock grounds itself), the entry's
# yaw under seam_yaw_degrees.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	_placement_yaw = yaw
	_apply_yaw()

func _ready() -> void:
	add_to_group(GROUP)
	_apply_yaw()
	var scene := load(SLAB_SCENE_PATH) as PackedScene
	_slab = scene.instantiate() as BaskingSlab if scene != null else null
	if _slab == null:
		push_warning("GlassboneSeam '%s': could not load %s; no rock." % [name, SLAB_SCENE_PATH])
		return
	_slab.name = "Rock"
	_slab.model_scale = rock_scale
	# One level below this node, so its paths reach one level further.
	_slab.ground_path = NodePath("../" + String(ground_path))
	_slab.region_field_path = NodePath("../" + String(region_field_path))
	add_child(_slab)
	_vein = MeshInstance3D.new()
	_vein.name = "Vein"
	_vein.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_slab.add_child(_vein)
	_build_vein()
	_spawn_approach()

func _apply_yaw() -> void:
	rotation = Vector3(0.0, deg_to_rad(seam_yaw_degrees + _placement_yaw), 0.0)

# --- The vein ---

# The rock's triangles in the slab's own frame.
func _rock_faces() -> PackedVector3Array:
	var faces := PackedVector3Array()
	if _slab == null:
		return faces
	var to_slab: Transform3D = _slab.global_transform.affine_inverse()
	for node in _slab.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == _vein or mesh_instance.mesh == null:
			continue
		var frame: Transform3D = to_slab * mesh_instance.global_transform
		for vertex in mesh_instance.mesh.get_faces():
			faces.append(frame * vertex)
	return faces

# The rock's top at a point of its own frame: the highest of its
# triangles a ray straight down crosses there, or null where none is.
static func _top_at(faces: PackedVector3Array, x: float, z: float, above: float) -> Variant:
	var from := Vector3(x, above, z)
	var best: Variant = null
	for i in range(0, faces.size() - 2, 3):
		var hit: Variant = Geometry3D.ray_intersects_triangle(from, Vector3.DOWN, faces[i], faces[i + 1], faces[i + 2])
		if hit == null:
			continue
		var point: Vector3 = hit
		if best == null or point.y > (best as Vector3).y:
			best = point
	return best

func _build_vein() -> void:
	if _vein == null or _slab == null or not is_inside_tree():
		return
	var faces: PackedVector3Array = _rock_faces()
	var box: AABB = _slab.get_body_aabb()
	if faces.is_empty() or not box.has_volume():
		_vein.mesh = null
		return
	var worked: bool = is_worked()
	var half_width: float = vein_width_m * 0.5 * (gouge_width_scale if worked else 1.0)
	var length: float = box.size.x * vein_length_fraction
	var start_x: float = box.get_center().x - length * 0.5
	var spine_z: float = box.get_center().z + vein_offset_m
	var above: float = box.end.y + 1.0
	var count: int = maxi(vein_samples, 2)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	for i in count:
		var t: float = float(i) / float(count - 1)
		var x: float = start_x + length * t
		var z: float = spine_z + sin(t * TAU * vein_wander_cycles) * vein_wander_m
		# The ends taper to a point.
		var taper: float = sin(t * PI)
		var w: float = half_width * clampf(taper * 1.6, 0.0, 1.0)
		for side: float in [-1.0, 1.0]:
			var top: Variant = _top_at(faces, x, z + side * w, above)
			var y: float = (top as Vector3).y if top != null else box.end.y
			vertices.append(Vector3(x, y + vein_lift_m, z + side * w))
			normals.append(Vector3.UP)
	var indices := PackedInt32Array()
	for i in count - 1:
		var a: int = i * 2
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_vein.mesh = mesh
	_apply_vein_material()

func _apply_vein_material() -> void:
	if _vein == null:
		return
	var path: String = gouge_material_path if is_worked() else glassbone_material_path
	_vein.material_override = load(path) as Material if ResourceLoader.exists(path) else null

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

# The Glassbone, the line, the gouge - spent for the run. False, and
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
	_build_vein()
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

# The rock's box on screen, grown by padding_px (TroughProp's rect).
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _slab == null:
		return Rect2()
	var box: AABB = _slab.get_body_aabb()
	if not box.has_volume():
		return Rect2()
	var to_world: Transform3D = _slab.global_transform
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = to_world * box.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)
