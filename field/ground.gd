extends StaticBody3D

@export var ground_color: Color = Color(0.72, 0.73, 0.66)
@export var plane_size: Vector2 = Vector2(500.0, 500.0)

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = plane_size

	var material := StandardMaterial3D.new()
	material.albedo_color = ground_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	plane_mesh.material = material

	mesh_instance.mesh = plane_mesh

	var boundary := WorldBoundaryShape3D.new()
	boundary.plane = Plane(Vector3.UP, 0.0)
	collision_shape.shape = boundary
