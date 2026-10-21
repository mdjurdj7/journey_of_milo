extends Area3D
class_name TrailDrop

# Where floor 3's rim trail drops into the top arm (floor3_layout.json's
# rim_trail.drop_centre_world_xz): a marker for the drop's trigger to come
# - the HP it costs and the ambush below are their own change. It watches
# nothing yet: no signal is connected, nothing reads it. A FloorProp
# (position: the drop's centre; yaw: turns the box), standing tall enough
# over the bank that it needs no grounding.

# The box: across the trail (X), up (Y, centred a little over y 0 so it
# covers the bank's whole fall) and along it (Z), metres.
@export var size: Vector3 = Vector3(3.0, 3.0, 1.4):
	set(value):
		size = value
		_rebuild()

func _ready() -> void:
	_rebuild()

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var collision := get_node_or_null(^"Shape") as CollisionShape3D
	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = "Shape"
		add_child(collision)
	var box := collision.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		collision.shape = box
	box.size = size
	collision.position = Vector3(0.0, size.y * 0.5 - 0.5, 0.0)
