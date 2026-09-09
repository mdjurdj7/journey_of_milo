extends CharacterBody3D
class_name FieldEnemy

signal contacted(enemy: FieldEnemy)

@export var enemy_id: StringName = &"enemy"
@export var contact_radius: float = 2.0

var _contacted: bool = false

@onready var contact_area: Area3D = $ContactArea
@onready var contact_shape: CollisionShape3D = $ContactArea/CollisionShape3D

func _ready() -> void:
	var shape := SphereShape3D.new()
	shape.radius = contact_radius
	contact_shape.shape = shape

	contact_area.body_entered.connect(_on_body_entered)
	contact_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if _contacted or not body.is_in_group("wanderer"):
		return
	_contacted = true
	contacted.emit(self)

# Reset the once-only guard when the Wanderer leaves, so a return visit
# (e.g. after an ESCAPE push-back) can trigger contact again.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_contacted = false
