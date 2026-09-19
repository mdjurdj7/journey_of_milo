extends Node3D
class_name Bird

# One bird perched on something (a hull's gunwale), that lifts off when
# the Wanderer comes within approach_radius and does not come back - once
# per run, like a Hull's world line (see _flown/_flight_id()); on a
# floor reload mid-run it's already gone at _ready(), a new run puts it
# back. No sound, no flock, no return.
#
# The mesh: a placeholder built from primitives in the project's flat
# material (Hull._get_shared_flat_material(), duplicated and tinted
# bird_tint) - a flattened capsule body along local -Z, a neck raised
# forward with the head on it, and two thin wing boxes on pivots at the
# body's sides, held half-open at rest (wing_rest_yaw_degrees - a
# cormorant drying). ~0.9m wingtip to wingtip spread, ~0.4m tall. Set
# bird_mesh to a PackedScene (a glb) and it replaces the placeholder:
# yawed by model_yaw_offset_degrees (the cormorant glb's beak is on +Z,
# the node's forward is -Z), grounded by its AABB so the feet sit on the
# perch whatever its origin. A glb is one merged surface (no wing pivots
# to find), so the flight animates the whole model - the path and the
# body bob, no wing beat - which is the price of a drop-in.
#
# The flight (see _take_flight()): the bird reparents to the field
# (keeps its world transform, sheds the hull's roll/pitch), rises
# rise_height over rise_seconds while turning to face its flight
# direction, then flies fly_distance along it climbing to fly_height
# over the rest of flight_seconds with an ease-in; the wings swing open
# over wing_open_seconds and then beat +-wing_beat_degrees at
# wing_beat_hz, the body bobs bob_height at the same rate. The
# environment's depth fog is what fades it. queue_free() at the end.

enum FlyDirection { SEAWARD, INLAND, LEFT, RIGHT }

@export var bird_mesh: PackedScene = null
# Yaw of a bird_mesh model under this node so its beak lies on the
# node's local -Z (the placeholder's forward): 180 for the cormorant
# glb, whose beak is on +Z. Unused by the placeholder.
@export var model_yaw_offset_degrees: float = 180.0:
	set(value):
		model_yaw_offset_degrees = value
		if _model != null and _body == null:
			_model.rotation = Vector3(0.0, deg_to_rad(model_yaw_offset_degrees), 0.0)
# Cormorant-dark: clearly darker than a Hull's hull_tint.
@export var bird_tint: Color = Color(0.28, 0.29, 0.31)
# Local position on the parent (the perch): the point the bird's feet
# rest on.
@export var perch_offset: Vector3 = Vector3.ZERO:
	set(value):
		perch_offset = value
		position = perch_offset
# How far the perched bird is turned on its perch, on top of whatever
# yaw it inherits from the thing it is standing on. Staging only: it
# decides what the camera sees of the bird at rest, nothing else.
#
# Kept separate from model_yaw_offset_degrees on purpose - that one
# corrects the ASSET (which way the glb's beak points) and would have to
# change if the model were swapped, while this one is about the shot.
# Folding the two together bakes a camera decision into an asset fix.
#
# Turns the NODE, not the model under it: _take_flight() reads this
# node's own global_rotation.y as the start of its turn-into-heading
# tween, so the bird visibly turns off its perch into the flight. Yawing
# the model instead would leave the node facing elsewhere and the bird
# would fly sideways. The lift-off heading itself is computed in world
# space by _flight_direction() and is untouched by this.
@export var perch_yaw_degrees: float = 0.0:
	set(value):
		perch_yaw_degrees = value
		rotation.y = deg_to_rad(perch_yaw_degrees)
# Larger than a Hull's world-line radius (2.5): the bird sees the
# Wanderer coming before he's at the hull.
@export var approach_radius: float = 4.0:
	set(value):
		approach_radius = value
		if _approach_shape != null:
			_approach_shape.radius = maxf(approach_radius, 0.0)
@export var flight_seconds: float = 2.2
# Relative to RegionField.get_forward() (spawn -> Tower): SEAWARD is
# -forward, away from the tower.
@export var fly_direction_bias: FlyDirection = FlyDirection.SEAWARD
# Added to the flight heading so it banks off rather than flying dead
# straight away from the tower.
@export var fly_yaw_offset_degrees: float = 25.0
@export var once_per_run: bool = true

@export_group("Flight")
@export var rise_height: float = 1.5
@export var rise_seconds: float = 0.5
@export var fly_distance: float = 14.0
@export var fly_height: float = 5.0
@export var wing_open_seconds: float = 0.3
@export var wing_beat_degrees: float = 25.0
@export var wing_beat_hz: float = 3.0
@export var bob_height: float = 0.07

@export_group("Placeholder")
@export var body_length: float = 0.55
@export var body_radius: float = 0.085
@export var head_radius: float = 0.075
# The neck runs from the body's upper front, this long, pitched up from
# horizontal by neck_pitch_degrees; the head sits on its end.
@export var neck_length: float = 0.18
@export var neck_radius: float = 0.028
@export var neck_pitch_degrees: float = 65.0
@export var wing_size: Vector3 = Vector3(0.36, 0.01, 0.09)
# How far the wings stand out from the body at rest: 0 = folded flat
# along it, 90 = fully spread. The lift-off opens them from here.
@export var wing_rest_yaw_degrees: float = 45.0:
	set(value):
		wing_rest_yaw_degrees = value
		if not _flying:
			_set_wings_at_rest()
# Instances live under a Hull under RegionField/Hulls, so RegionField is
# three levels up.
@export var region_field_path: NodePath = ^"../../.."

# Birds already flown this run, keyed by _flight_id() - static so it
# survives the reload_current_scene() a floor exit does. Cleared by
# RunState.new_run() via reset_flights().
static var _flown: Dictionary = {}

static func reset_flights() -> void:
	_flown.clear()

var _model: Node3D = null
var _material: StandardMaterial3D = null
var _wing_left: Node3D = null
var _wing_right: Node3D = null
var _body: Node3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
var _flying: bool = false

func _ready() -> void:
	position = perch_offset
	if once_per_run and _flown.has(_flight_id()):
		queue_free()
		return
	_spawn_model()
	_spawn_approach_area()

# Scene file + path from the scene root - the same bird on a reloaded
# floor has the same id.
func _flight_id() -> String:
	var root: Node = owner if owner != null else self
	return "%s:%s" % [root.scene_file_path, str(root.get_path_to(self))]

func _spawn_model() -> void:
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = bird_tint
	if bird_mesh != null:
		_model = bird_mesh.instantiate() as Node3D
		_model.name = "Model"
		_model.rotation = Vector3(0.0, deg_to_rad(model_yaw_offset_degrees), 0.0)
		add_child(_model)
		# Seat the model's bbox bottom on this node's origin (the perch
		# point) - same AABB-grounding idiom as Hull._apply_model_transform();
		# the yaw above is already in the transform the bbox is measured
		# through, so only Y is read from it.
		var combined_aabb: AABB
		var has_aabb := false
		for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh_instance as MeshInstance3D
			mi.material_override = _material
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			var mi_aabb_in_self: AABB = (_model.transform * _model.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
			combined_aabb = mi_aabb_in_self if not has_aabb else combined_aabb.merge(mi_aabb_in_self)
			has_aabb = true
		if has_aabb:
			_model.position.y = -combined_aabb.position.y
		return
	_model = Node3D.new()
	_model.name = "Placeholder"
	add_child(_model)

	# Body: a capsule (axis Y) laid along -Z, its underside on the perch.
	_body = Node3D.new()
	_body.name = "Body"
	_body.position = Vector3(0.0, body_radius, 0.0)
	_model.add_child(_body)
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = body_radius
	body_mesh.height = body_length
	var body_mi := _mesh_instance(body_mesh)
	body_mi.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
	body_mi.scale = Vector3(1.0, 0.8, 1.0)
	_body.add_child(body_mi)

	# Neck: a capsule from the body's upper front, pitched up and forward;
	# the head on its far end.
	var pitch: float = deg_to_rad(neck_pitch_degrees)
	var neck_base := Vector3(0.0, body_radius * 0.8, -(body_length * 0.5 - body_radius * 0.6))
	var neck_dir := Vector3(0.0, sin(pitch), -cos(pitch))
	var neck_mesh := CapsuleMesh.new()
	neck_mesh.radius = neck_radius
	neck_mesh.height = neck_length + neck_radius * 2.0
	var neck_mi := _mesh_instance(neck_mesh)
	neck_mi.position = neck_base + neck_dir * neck_length * 0.5
	# The capsule's axis is Y: tip it forward by (90 - pitch) about X.
	neck_mi.rotation = Vector3(-(PI * 0.5 - pitch), 0.0, 0.0)
	_body.add_child(neck_mi)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = head_radius
	head_mesh.height = head_radius * 2.0
	var head_mi := _mesh_instance(head_mesh)
	head_mi.position = neck_base + neck_dir * neck_length + Vector3(0.0, 0.0, -head_radius * 0.3)
	_body.add_child(head_mi)

	# Wings: pivots at the body's sides; each box extends outward along
	# the pivot's local X (right: +X, left: -X). Yawing a pivot swings its
	# box back along the body toward the tail (right +90, left -90 = fully
	# folded); at rest they stand at wing_rest_yaw_degrees short of that.
	_wing_right = _wing_pivot(1.0)
	_wing_left = _wing_pivot(-1.0)
	_body.add_child(_wing_right)
	_body.add_child(_wing_left)
	_set_wings_at_rest()

func _mesh_instance(mesh: Mesh) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi

func _wing_pivot(side: float) -> Node3D:
	var pivot := Node3D.new()
	pivot.name = "WingRight" if side > 0.0 else "WingLeft"
	pivot.position = Vector3(side * body_radius * 0.9, body_radius * 0.3, -body_length * 0.05)
	var wing_mesh := BoxMesh.new()
	wing_mesh.size = wing_size
	var wing_mi := _mesh_instance(wing_mesh)
	wing_mi.position = Vector3(side * wing_size.x * 0.5, 0.0, 0.0)
	pivot.add_child(wing_mi)
	return pivot

# Rest pose: each wing swung back from fully spread (yaw 0) by 90 -
# wing_rest_yaw_degrees, so wing_rest_yaw_degrees is how far it stands
# out from the body (right yaws +, left -), both flat.
func _set_wings_at_rest() -> void:
	if _wing_right == null:
		return
	var back: float = deg_to_rad(90.0 - clampf(wing_rest_yaw_degrees, 0.0, 90.0))
	_wing_right.rotation = Vector3(0.0, back, 0.0)
	_wing_left.rotation = Vector3(0.0, -back, 0.0)

# The approach trigger, same shape as Hull's: a sphere around the bird
# watching for the Wanderer (group "wanderer").
func _spawn_approach_area() -> void:
	_approach_area = Area3D.new()
	_approach_area.name = "ApproachArea"
	_approach_area.monitorable = false
	_approach_shape = SphereShape3D.new()
	_approach_shape.radius = maxf(approach_radius, 0.0)
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _approach_shape
	_approach_area.add_child(shape_node)
	add_child(_approach_area)
	_approach_area.body_entered.connect(_on_approach_body_entered)

func _on_approach_body_entered(body: Node3D) -> void:
	if _flying or not body.is_in_group("wanderer"):
		return
	_take_flight()

# The flight heading in world space: the bias direction relative to the
# field's forward, yawed by fly_yaw_offset_degrees.
func _flight_direction() -> Vector3:
	var forward := Vector3.FORWARD
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field != null:
		forward = region_field.get_forward()
	forward = Vector3(forward.x, 0.0, forward.z).normalized()
	if forward.length() < 0.0001:
		forward = Vector3.FORWARD
	var direction: Vector3
	match fly_direction_bias:
		FlyDirection.INLAND:
			direction = forward
		FlyDirection.LEFT:
			direction = Vector3.UP.cross(forward)
		FlyDirection.RIGHT:
			direction = forward.cross(Vector3.UP)
		_:
			direction = -forward
	return direction.rotated(Vector3.UP, deg_to_rad(fly_yaw_offset_degrees)).normalized()

func _take_flight() -> void:
	_flying = true
	if once_per_run:
		_flown[_flight_id()] = true
	if _approach_area != null:
		_approach_area.monitoring = false

	# Shed the perch's tilt: same world transform, parented to the field.
	var region_field := get_node_or_null(region_field_path) as Node3D
	if region_field != null:
		reparent(region_field, true)

	var direction: Vector3 = _flight_direction()
	var start: Vector3 = global_position
	var rise_end: Vector3 = start + Vector3.UP * rise_height
	var flight_end: Vector3 = rise_end + direction * fly_distance + Vector3.UP * maxf(fly_height - rise_height, 0.0)
	# Turn the short way round from the perch's current yaw.
	var current_yaw: float = global_rotation.y
	var heading: float = current_yaw + wrapf(atan2(-direction.x, -direction.z) - current_yaw, -PI, PI)
	var cruise_seconds: float = maxf(flight_seconds - rise_seconds, 0.05)

	var path := create_tween()
	path.set_parallel(true)
	path.tween_property(self, "global_position", rise_end, rise_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	path.tween_property(self, "global_rotation", Vector3(0.0, heading, 0.0), rise_seconds).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	path.chain().tween_property(self, "global_position", flight_end, cruise_seconds).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	path.chain().tween_callback(queue_free)

	if _wing_right != null:
		_animate_wings()
	_animate_bob()

# Open the rest of the way over wing_open_seconds (yaw to 0 from the
# rest pose), then beat: each half-beat
# is a rotation about the pivot's Z between +-wing_beat_degrees, looped
# for the rest of the flight (the bird is freed before the loop matters).
func _animate_wings() -> void:
	var open := create_tween()
	open.set_parallel(true)
	open.tween_property(_wing_right, "rotation:y", 0.0, wing_open_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	open.tween_property(_wing_left, "rotation:y", 0.0, wing_open_seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	open.chain().tween_callback(_beat_wings)

func _beat_wings() -> void:
	var half_beat: float = 0.5 / maxf(wing_beat_hz, 0.1)
	var amplitude: float = deg_to_rad(wing_beat_degrees)
	var beat := create_tween()
	beat.set_loops()
	beat.set_parallel(true)
	beat.tween_property(_wing_right, "rotation:z", amplitude, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	beat.tween_property(_wing_left, "rotation:z", -amplitude, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	beat.chain().tween_property(_wing_right, "rotation:z", -amplitude, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	beat.tween_property(_wing_left, "rotation:z", amplitude, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)

# The body rides up on the downbeat and settles on the upbeat - the
# placeholder's Body node, or the whole bird_mesh model (its one merged
# surface has no separate body to move).
func _animate_bob() -> void:
	var bobbing: Node3D = _body if _body != null else _model
	if bobbing == null:
		return
	var half_beat: float = 0.5 / maxf(wing_beat_hz, 0.1)
	var rest_y: float = bobbing.position.y
	var bob := create_tween()
	bob.set_loops()
	bob.tween_property(bobbing, "position:y", rest_y + bob_height, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	bob.tween_property(bobbing, "position:y", rest_y, half_beat).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
