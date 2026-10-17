extends Node3D
class_name StandingPool

# A small standing pool an encounter brings with it - the Glower's, beside
# floor 2's crab, where the mask paints no pool. Nothing of its own is
# drawn: it stamps an ellipse into the ground's shader (Ground.set_pool_
# stamp()), which draws it as the ground's own pools are drawn - still,
# pool_color off the sky, a damp rim round it - and takes it away again
# when this leaves the tree. The relief under it is untouched, so it is
# water to look at, not to wade: the body resting in it sinks into the
# sand under the surface by its own EnemyData.sink_m.
#
# Placed from data (a FloorProp in the encounter option: position and
# yaw, in the slot's frame); its size through overrides. Keep it clear of
# the sea's run-up (Ground.swash_runup_distance) plus its rim, or the
# wash runs over it.

# Semi-axes, metres: x along its length, y across.
@export var radii: Vector2 = Vector2(0.8, 0.6):
	set(value):
		radii = value
		_push()
# Its length's facing, degrees round Y: +X turns to (cos, 0, -sin), as
# every prop's does. From FloorProp.yaw_degrees.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		_push()
@export var ground_path: NodePath = ^"../../Ground"

var _ground: Ground = null

func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("StandingPool '%s': ground_path did not resolve to a Ground; no pool drawn." % name)
		return
	_push()

func _exit_tree() -> void:
	if _ground != null and is_instance_valid(_ground):
		_ground.clear_pool_stamp(self)

func _push() -> void:
	if _ground == null or not is_inside_tree():
		return
	_ground.set_pool_stamp(self, Vector2(global_position.x, global_position.z), radii, yaw_degrees)
