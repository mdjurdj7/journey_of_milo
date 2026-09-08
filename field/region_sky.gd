extends WorldEnvironment

@export var sky_color: Color = Color(0.93, 0.93, 0.91)
@export var horizon_color: Color = Color(0.86, 0.86, 0.84)
@export var fog_color: Color = Color(0.86, 0.86, 0.84)
@export var fog_density: float = 0.015
@export var fog_depth_begin: float = 20.0
@export var fog_depth_end: float = 320.0
@export var ambient_energy: float = 1.0

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_color
	sky_material.sky_horizon_color = horizon_color
	sky_material.ground_bottom_color = horizon_color
	sky_material.ground_horizon_color = horizon_color

	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density
	env.fog_depth_begin = fog_depth_begin
	env.fog_depth_end = fog_depth_end

	environment = env
