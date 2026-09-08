extends DirectionalLight3D

@export var elevation_degrees: float = 80.0
@export var azimuth_degrees: float = 0.0
@export var energy: float = 0.4
@export var color: Color = Color(0.82, 0.85, 0.88)
@export var shadows_enabled: bool = true
@export var shadow_softness: float = 4.0

func _ready() -> void:
	rotation_degrees = Vector3(-elevation_degrees, azimuth_degrees, 0.0)
	light_energy = energy
	light_color = color
	shadow_enabled = shadows_enabled
	light_angular_distance = shadow_softness
	sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
