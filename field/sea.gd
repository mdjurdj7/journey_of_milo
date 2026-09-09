extends MeshInstance3D
class_name Sea

const AMBIENCE_PATH := "res://assets/audio/Floor_0/ocean_waves.mp3"

# Default is horizon_color's own default (0.87, 0.88, 0.85) * 0.85;
# region_sky.gd overwrites this at runtime via set_sea_color_from_sky(),
# same as Ground.pool_color. This export is only the fallback for when
# no sky node is present.
@export var sea_color: Color = Color(0.74, 0.75, 0.72):
	set(value):
		sea_color = value
		_apply_uniform("sea_color", value)

@export var sea_roughness: float = 0.35:
	set(value):
		sea_roughness = value
		_apply_uniform("sea_roughness", value)

@export var noise_amplitude: float = 0.03:
	set(value):
		noise_amplitude = value
		_apply_uniform("noise_amplitude", value)
@export var noise_speed: float = 0.05:
	set(value):
		noise_speed = value
		_apply_uniform("noise_speed", value)

@export var sea_size: Vector2 = Vector2(500.0, 400.0)

# Kept fractionally below 0.0 (Ground's plane) so the two don't z-fight
# along the shoreline where they meet.
@export var sea_level: float = -0.05

@export var wanderer_path: NodePath = ^"../Wanderer"
@export var sea_edge_distance: float = 18.0
@export var near_distance: float = 5.0
@export var far_distance: float = 60.0
@export var volume_db_max: float = 0.0
@export var volume_db_min: float = -40.0
@export var volume_time_constant: float = 0.5

var _material: ShaderMaterial
var _wanderer: Node3D
var _audio_player: AudioStreamPlayer
var _current_volume_db: float

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://field/sea.gdshader")
	_apply_all_uniforms()

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = sea_size
	plane_mesh.material = _material
	mesh = plane_mesh

	_wanderer = get_node_or_null(wanderer_path) as Node3D
	_position_relative_to_spawn()

	_spawn_ambience()

# Near edge sits sea_edge_distance behind the Wanderer's spawn point
# along the field's backward axis (-Z), extending further backward
# from there out to the fog.
func _position_relative_to_spawn() -> void:
	var spawn_z := _wanderer.global_position.z if _wanderer else 0.0
	var near_edge_z := spawn_z - sea_edge_distance
	position.z = near_edge_z - sea_size.y / 2.0
	position.y = sea_level

func _spawn_ambience() -> void:
	var stream := load(AMBIENCE_PATH) as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_current_volume_db = volume_db_min

	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = stream
	_audio_player.volume_db = _current_volume_db
	add_child(_audio_player)
	_audio_player.play()

# near_edge_z assumes the sea's local +Z faces inland (true for the -Z
# shoreward placement region_field.tscn uses); distance is measured
# along that same +Z (the field's forward axis) from the Wanderer to
# that edge, clamped to 0 once the Wanderer is at or past it.
func _physics_process(delta: float) -> void:
	if _audio_player == null or _wanderer == null:
		return

	var near_edge_z := global_position.z + sea_size.y / 2.0
	var distance := maxf(_wanderer.global_position.z - near_edge_z, 0.0)

	# smoothstep rather than a linear falloff so volume stays close to
	# volume_db_max through the early part of the range and only tapers
	# off as distance approaches far_distance.
	var t := smoothstep(near_distance, far_distance, distance)
	var target_volume_db: float = lerp(volume_db_max, volume_db_min, t)

	var blend := 1.0 - exp(-delta / maxf(volume_time_constant, 0.001))
	_current_volume_db = lerp(_current_volume_db, target_volume_db, blend)
	_audio_player.volume_db = _current_volume_db

func _apply_all_uniforms() -> void:
	_apply_uniform("sea_color", sea_color)
	_apply_uniform("sea_roughness", sea_roughness)
	_apply_uniform("noise_amplitude", noise_amplitude)
	_apply_uniform("noise_speed", noise_speed)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)

# Called by region_sky.gd so the sea always matches the sky's horizon
# color (darkened), without manual duplication. sea_color's own export
# default above is the fallback if no sky node pushes a value.
func set_sea_color_from_sky(sky_horizon_color: Color) -> void:
	sea_color = Color(sky_horizon_color.r * 0.85, sky_horizon_color.g * 0.85, sky_horizon_color.b * 0.85, 1.0)
