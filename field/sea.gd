extends MeshInstance3D
class_name Sea

const AMBIENCE_PATH := "res://assets/audio/Floor_0/ocean_waves.mp3"

# Sea's one color source — no push from region_sky.gd or anywhere else.
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

# Plane X spans the field's full width plus width_margin on each side,
# so it runs well past the fog regardless of field_extents; Z is a flat
# sea_depth back from the near (shore) edge.
@export var width_margin: float = 200.0
@export var sea_depth: float = 400.0

# Kept fractionally below 0.0 (Ground's plane) so the two don't z-fight
# along the shoreline where they meet.
@export var sea_level: float = -0.05:
	set(value):
		sea_level = value
		_reposition_if_ready()

@export var region_field_path: NodePath = ^".."
@export var wanderer_path: NodePath = ^"../Wanderer"
@export var sea_edge_distance: float = 18.0:
	set(value):
		sea_edge_distance = value
		_reposition_if_ready()
@export var near_distance: float = 5.0
@export var far_distance: float = 60.0
@export var volume_db_max: float = 0.0
@export var volume_db_min: float = -40.0
@export var volume_time_constant: float = 0.5

var _material: ShaderMaterial
var _wanderer: Node3D
var _audio_player: AudioStreamPlayer
var _current_volume_db: float
var _forward: Vector3 = Vector3.FORWARD
var _ready_complete: bool = false

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://field/sea.gdshader")
	_apply_all_uniforms()

	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(_field_width() + width_margin * 2.0, sea_depth)
	plane_mesh.material = _material
	mesh = plane_mesh

	_wanderer = get_node_or_null(wanderer_path) as Node3D
	_position_relative_to_spawn()

	_spawn_ambience()

	_ready_complete = true

# Guards sea_level/sea_edge_distance's setters: they can fire during
# scene deserialization before _ready() has built the mesh or resolved
# _wanderer, so only reposition once that initial setup is done.
func _reposition_if_ready() -> void:
	if _ready_complete:
		_position_relative_to_spawn()

# region_field.gd's field_extents.x, read dynamically (no static type
# dependency between the two scripts) via the node at region_field_path.
# Falls back to 0 (so the plane is exactly width_margin*2 wide) if that
# node or property isn't present.
func _field_width() -> float:
	var region_field := get_node_or_null(region_field_path)
	if region_field:
		var extents = region_field.get("field_extents")
		if extents is Vector2:
			return extents.x
	return 0.0

# Centered in X on the field's own center (RegionField's world X —
# field_extents is always centered on RegionField's origin). Near edge
# sits sea_edge_distance behind the Wanderer's spawn point along
# RegionField.get_forward() (never assumed to be -Z), extending further
# away from the Tower from there; the plane's own center (what position
# actually sets) is a further half-depth back from that near edge, so
# the near edge itself, not the center, lands exactly on that line.
func _position_relative_to_spawn() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	var field_center_x := region_field.global_position.x if region_field else 0.0
	_forward = region_field.get_forward() if region_field else Vector3.FORWARD

	var spawn := _wanderer.global_position if _wanderer else Vector3.ZERO
	var near_edge_z := (spawn - _forward * sea_edge_distance).z
	var center_z := near_edge_z - _forward.z * sea_depth / 2.0

	global_position = Vector3(field_center_x, sea_level, center_z)

	var mesh_size: Vector2 = (mesh as PlaneMesh).size
	var half_width := mesh_size.x / 2.0
	print("Sea: near edge z=%.2f, X extent=[%.2f, %.2f]" % [near_edge_z, global_position.x - half_width, global_position.x + half_width])

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

# near_edge_z is the inverse of the center_z calc in
# _position_relative_to_spawn(). Distance is measured along _forward
# (not assumed +Z) from the Wanderer to that edge, clamped to 0 once
# the Wanderer is at or past it.
func _physics_process(delta: float) -> void:
	if _audio_player == null or _wanderer == null:
		return

	var near_edge_z := global_position.z + _forward.z * sea_depth / 2.0
	var distance := maxf((_wanderer.global_position.z - near_edge_z) * _forward.z, 0.0)

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
