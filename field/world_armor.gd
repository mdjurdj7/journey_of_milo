extends Node3D
class_name WorldArmor

# One worn piece (TrinketData.slot WORN) lying on the sand - where an
# elite fell (RegionField's win), or where the Wanderer set the last one
# down when he took another. A plain field object: its body (the piece's
# field_model_path, else a placeholder block) seated on the relief by its
# own bounds. No glow, no beam, no floating icon. It says nothing: a
# fight's piece is named by the find line once the reward has closed
# (RegionField, FindLine).
#
# Within reach, a click on it opens its plate (RegionField._try_examine_
# armor(), ArmorExamine): TAKE wears it - whatever was worn is set down
# here in turn - and this one goes (take()); LEAVE leaves it lying, to be
# taken any time on this floor. Nothing is remembered past the floor: the
# scene reloads on the floor transition and the piece goes with it.

const GROUP := &"worn_drops"

@export var piece: TrinketData = null
# How near the Wanderer must be (ground distance) to open it with a click.
@export var reach_radius: float = 2.5
# Metres it lies over the relief: on something the relief doesn't draw -
# where floor 4's Adder fell, on its basking slab (FieldEnemy.height_offset,
# passed on by RegionField). 0 = on the sand.
@export var height_offset: float = 0.0:
	set(value):
		height_offset = value
		seat()
@export var ground_path: NodePath = ^"../Ground"
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)

@export_group("Placeholder")
# The body when the piece names no model: a low block of this size and
# colour - plainly a placeholder.
@export var placeholder_size: Vector3 = Vector3(0.36, 0.08, 0.26):
	set(value):
		placeholder_size = value
		_rebuild_body()
@export var placeholder_color: Color = Color(0.36, 0.32, 0.27):
	set(value):
		placeholder_color = value
		_rebuild_body()
@export_group("")

var _body: Node3D = null
# The body's bounds in this node's space, measured as it's built.
var _aabb: AABB = AABB()
var _taken: bool = false
# Its plate has been looked at once - or the Wanderer set it down himself:
# every later look is at the examine scale, not first loot's reveal
# (RegionField.open_armor_examine(), ArmorExamine.reveal_scale).
var revealed: bool = false

func _ready() -> void:
	add_to_group(GROUP)
	if piece == null:
		push_warning("WorldArmor: spawned with no piece; freeing rather than lying empty.")
		queue_free()
		return
	_rebuild_body()

# The body, built again from the piece (and the placeholder's settings),
# then seated: its lowest point on the relief.
func _rebuild_body() -> void:
	if not is_inside_tree() or piece == null:
		return
	if _body != null:
		_body.queue_free()
		_body = null
	if not piece.field_model_path.is_empty():
		var scene := load(piece.field_model_path) as PackedScene
		if scene != null:
			_body = scene.instantiate() as Node3D
		else:
			push_warning("WorldArmor: could not load %s; a placeholder block instead." % piece.field_model_path)
	if _body == null:
		var block := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = placeholder_size
		var material := StandardMaterial3D.new()
		material.albedo_color = placeholder_color
		mesh.material = material
		block.mesh = mesh
		_body = block
	_body.name = "Body"
	add_child(_body)
	_aabb = _measure_body()
	# Grounded by its bounds: a model's origin may be its centre.
	_body.position = Vector3(0.0, -_aabb.position.y, 0.0)
	_aabb.position.y = 0.0
	seat()

func _measure_body() -> AABB:
	var box := AABB()
	var first: bool = true
	var meshes: Array[Node] = _body.find_children("*", "MeshInstance3D", true, false)
	if _body is MeshInstance3D:
		meshes.append(_body)
	for node in meshes:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		# Composed into this node's space before the bounds (a yawed body).
		var to_here: Transform3D = global_transform.affine_inverse() * mesh_instance.global_transform
		var bounds: AABB = to_here * mesh_instance.get_aabb()
		box = bounds if first else box.merge(bounds)
		first = false
	return box

# This node onto the relief at its own XZ - Ground's own frame, the same
# idiom RewardSpread uses - raised by height_offset.
func seat() -> void:
	if not is_inside_tree():
		return
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return
	var local: Vector3 = ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	var height: float = ground.get_height_at(Vector2(local.x, local.z))
	global_position = Vector3(global_position.x, height + height_offset, global_position.z)

func _in_reach(from: Vector3) -> bool:
	var offset := Vector3(from.x - global_position.x, 0.0, from.z - global_position.z)
	return offset.length() <= reach_radius

# Whether a click from `from` (the Wanderer's position) may open it.
func can_open_from(from: Vector3) -> bool:
	return not _taken and _in_reach(from)

# The body's bounds on screen, grown by padding_px - BundleProp's rule, so
# a small thing on the sand is as easy to click as an enemy.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _aabb.size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = global_transform * _aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

# Taken: off the sand - it shrinks into the ground where it lay and goes.
# Nothing flies anywhere: a worn piece has no deck to fly to.
func take() -> void:
	if _taken:
		return
	_taken = true
	remove_from_group(GROUP)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.0, 0.01, 1.0), 0.25)
	tween.tween_callback(queue_free)

func is_taken() -> bool:
	return _taken
