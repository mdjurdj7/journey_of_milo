extends WorldEnvironment

@export var sky_top_color: Color = Color(0.82, 0.85, 0.86)
@export var horizon_color: Color = Color(0.87, 0.88, 0.85):
	set(value):
		horizon_color = value
		_push_pool_color()
@export var fog_color: Color = Color(0.87, 0.88, 0.85)
@export var fog_density: float = 0.006
@export var fog_depth_begin: float = 20.0
@export var fog_depth_end: float = 320.0
@export var fog_sky_affect: float = 1.0
@export var fog_aerial_perspective: float = 0.5
# Flat color fill instead of the sky's own color - AMBIENT_SOURCE_SKY was
# tinting every surface (sand most of all) noticeably blue, since the
# procedural sky's horizon/top colors lean cool. ambient_color's default
# is a warm off-white close to the sand's own dry tone instead.
@export var ambient_color: Color = Color(0.78, 0.77, 0.74):
	set(value):
		ambient_color = value
		_apply_ambient()
@export var ambient_energy: float = 0.7:
	set(value):
		ambient_energy = value
		_apply_ambient()
@export var ground_path: NodePath = ^"../Ground"

var _environment: Environment

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = horizon_color
	sky_material.ground_bottom_color = horizon_color
	sky_material.ground_horizon_color = horizon_color

	var sky := Sky.new()
	sky.sky_material = sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.fog_enabled = true
	_environment.fog_light_color = fog_color
	_environment.fog_density = fog_density
	_environment.fog_depth_begin = fog_depth_begin
	_environment.fog_depth_end = fog_depth_end
	_environment.fog_sky_affect = fog_sky_affect
	_environment.fog_aerial_perspective = fog_aerial_perspective
	_apply_ambient()

	environment = _environment

	_push_pool_color()

# Guarded the same way _push_pool_color() already is: ambient_color/
# ambient_energy's setters can fire during scene deserialization, before
# _ready() has built _environment.
func _apply_ambient() -> void:
	if _environment == null:
		return
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = ambient_color
	_environment.ambient_light_energy = ambient_energy

# Keeps Ground's standing-pool color matched to the sky's horizon color
# without manual duplication. Ground keeps its own pool_color export as
# the fallback if no sky node is present at ground_path.
func _push_pool_color() -> void:
	if not is_inside_tree():
		return
	var ground := get_node_or_null(ground_path) as Ground
	if ground:
		ground.set_pool_color_from_sky(horizon_color)
