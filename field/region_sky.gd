extends WorldEnvironment

@export var sky_top_color: Color = Color(0.82, 0.85, 0.86)
@export var horizon_color: Color = Color(0.87, 0.88, 0.85):
	set(value):
		horizon_color = value
		_push_pool_color()
		_push_sea_color()
@export var fog_color: Color = Color(0.87, 0.88, 0.85)
@export var fog_density: float = 0.006
@export var fog_depth_begin: float = 20.0
@export var fog_depth_end: float = 320.0
@export var fog_sky_affect: float = 1.0
@export var fog_aerial_perspective: float = 0.5
@export var ambient_energy: float = 1.0
@export var ground_path: NodePath = ^"../Ground"
@export var sea_path: NodePath = ^"../Sea"

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
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
	env.fog_sky_affect = fog_sky_affect
	env.fog_aerial_perspective = fog_aerial_perspective

	environment = env

	_push_pool_color()
	_push_sea_color()

# Keeps Ground's standing-pool color matched to the sky's horizon color
# without manual duplication. Ground keeps its own pool_color export as
# the fallback if no sky node is present at ground_path.
func _push_pool_color() -> void:
	if not is_inside_tree():
		return
	var ground := get_node_or_null(ground_path) as Ground
	if ground:
		ground.set_pool_color_from_sky(horizon_color)

# Keeps the Sea's color matched to the sky's horizon color (darkened),
# without manual duplication. Sea keeps its own sea_color export as the
# fallback if no sky node is present at sea_path.
func _push_sea_color() -> void:
	if not is_inside_tree():
		return
	var sea := get_node_or_null(sea_path) as Sea
	if sea:
		sea.set_sea_color_from_sky(horizon_color)
