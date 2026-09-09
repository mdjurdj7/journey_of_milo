extends MeshInstance3D

@export var tower_color: Color = Color(0.30, 0.32, 0.33)
@export var height: float = 150.0
@export var base_radius: float = 9.0
@export var top_radius: float = 2.0
@export var distance_along_walk: float = 380.0

func _ready() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.height = height
	cylinder.bottom_radius = base_radius
	cylinder.top_radius = top_radius

	var material := StandardMaterial3D.new()
	material.albedo_color = tower_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	cylinder.material = material

	mesh = cylinder
	position = Vector3(0.0, height / 2.0, -distance_along_walk)
