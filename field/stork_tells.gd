extends Node3D
class_name StorkTells

# The marabou's tells (the Blackback's body): its throat sac greyed while
# it's Fed and reddening when it turns Hungry, and a bill clatter before
# each attack. An attachment (EnemyData.attachment_scene_path), like
# RearPose - FieldEnemy instances it under the model root once the body's
# material pass is over, so the body's own material is already there to
# lay the sac's pass on.
#
# The sac: a next pass on the body's material (field/stork_sac.gdshader)
# lays the body's albedo, desaturated, over the sac's red - picked out by
# hue inside a box on the model, the head being the same red. grey_amount
# is fed_desaturation while it's Fed and 0 once it's Hungry, faded over
# fade_seconds; show_status() (FieldEnemy, from BattleController.enemy_
# status_gained) switches it. The field shows it Fed - it is, until the
# Nipper falls - and each fight's opening statuses set it again at once.
#
# The clatter (play_windup(), from FieldEnemy.play_attack_snap()): the body
# mesh jitters - a fast, small, decaying shake of position and tilt -
# for clatter_seconds, and the lunge waits for it. The model has no
# skeleton or separate bill, so it's the whole body. Runs in _process at
# PROCESS_MODE_ALWAYS, like RearPose: the field is frozen through a fight.

const SAC_SHADER_PATH := "res://field/stork_sac.gdshader"

@export_group("Throat Sac")
# Grey while Fed: 1 is the sac's red fully desaturated, 0 none.
@export_range(0.0, 1.0) var fed_desaturation: float = 1.0:
	set(value):
		fed_desaturation = value
		_apply_grey()
# How long the red takes to come back when it turns Hungry.
@export var fade_seconds: float = 0.6
# The statuses that set the sac: grey while grey_status is held, red from
# when red_status is gained (the Blackback's Fed and Hungry).
@export var grey_status: StatusData = null
@export var red_status: StatusData = null
# The sac's red: hue centre and half-width (degrees), least saturation.
@export var hue_center_degrees: float = 3.0:
	set(value):
		hue_center_degrees = value
		_push_sac()
@export var hue_half_width_degrees: float = 22.0:
	set(value):
		hue_half_width_degrees = value
		_push_sac()
@export_range(0.0, 1.0) var min_saturation: float = 0.3:
	set(value):
		min_saturation = value
		_push_sac()
# The sac's box on the model, as fractions of the mesh's bounds (x across,
# y up from the feet, z from tail to bill).
@export var region_min: Vector3 = Vector3(0.0, 0.45, 0.6):
	set(value):
		region_min = value
		_push_sac()
@export var region_max: Vector3 = Vector3(1.0, 0.7, 1.0):
	set(value):
		region_max = value
		_push_sac()
@export_range(0.0, 0.2) var region_softness: float = 0.03:
	set(value):
		region_softness = value
		_push_sac()

@export_group("Bill Clatter")
# How long the clatter runs before the attack lunges, seconds.
@export var clatter_seconds: float = 0.35
# Its size at the start, decaying to nothing: metres of shake, and degrees
# of tilt.
@export var clatter_shake_m: float = 0.018
@export var clatter_tilt_degrees: float = 2.5

var _body: MeshInstance3D = null
var _sac: ShaderMaterial = null
# 1 Fed (grey at fed_desaturation), 0 Hungry (red).
var _fed: float = 1.0
var _fade: Tween = null
var _clatter_left: float = 0.0
var _rest: Transform3D = Transform3D.IDENTITY
var _random := RandomNumberGenerator.new()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	_random.randomize()
	for child in get_parent().get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh != null:
			_body = child as MeshInstance3D
			break
	if _body == null:
		push_warning("StorkTells: no body mesh beside it; no sac, no clatter.")
		return
	_rest = _body.transform
	var body_material := _body.material_override as BaseMaterial3D
	if body_material == null:
		body_material = _body.get_active_material(0) as BaseMaterial3D
	if body_material == null:
		push_warning("StorkTells: the body has no material to lay the sac on.")
		return
	_sac = ShaderMaterial.new()
	_sac.shader = load(SAC_SHADER_PATH) as Shader
	_sac.set_shader_parameter("albedo_texture", body_material.albedo_texture)
	_sac.set_shader_parameter("normal_texture", body_material.normal_texture)
	_sac.set_shader_parameter("use_normal_texture", body_material.normal_texture != null)
	var bounds: AABB = _body.mesh.get_aabb()
	_sac.set_shader_parameter("bounds_position", bounds.position)
	_sac.set_shader_parameter("bounds_size", bounds.size)
	body_material.next_pass = _sac
	_push_sac()
	_apply_grey()

# A status this enemy now holds (FieldEnemy.show_status()): grey_status
# greys the sac at once, red_status brings the red back - over
# fade_seconds when `animate`, at once at a fight's opening.
func show_status(status: StatusData, animate: bool) -> void:
	if status == null:
		return
	if status == grey_status:
		_set_fed(1.0, false)
	elif status == red_status:
		_set_fed(0.0, animate)

# FieldEnemy.play_attack_snap(): the bill clatters, and the lunge waits for
# it. Returns how long.
func play_windup(_out_time: float) -> float:
	if _body == null or clatter_seconds <= 0.0:
		return 0.0
	_clatter_left = clatter_seconds
	set_process(true)
	return clatter_seconds

func _process(delta: float) -> void:
	if _body == null:
		set_process(false)
		return
	_clatter_left -= delta
	if _clatter_left <= 0.0:
		_body.transform = _rest
		set_process(false)
		return
	# Metres to the mesh's own units: the model root carries the scale.
	var model_root := get_parent() as Node3D
	var scale_to_mesh: float = 1.0 / maxf(model_root.scale.x if model_root != null else 1.0, 0.0001)
	var left: float = _clatter_left / clatter_seconds
	var shake := Vector3(_random.randf_range(-1.0, 1.0), _random.randf_range(-0.4, 0.4), _random.randf_range(-1.0, 1.0)) * clatter_shake_m * left * scale_to_mesh
	var tilt := Basis.from_euler(Vector3(deg_to_rad(_random.randf_range(-1.0, 1.0) * clatter_tilt_degrees * left), 0.0, deg_to_rad(_random.randf_range(-1.0, 1.0) * clatter_tilt_degrees * left)))
	_body.transform = Transform3D(_rest.basis * tilt, _rest.origin + shake)

func _set_fed(target: float, animate: bool) -> void:
	if _fade != null and _fade.is_valid():
		_fade.kill()
	if not animate or fade_seconds <= 0.0:
		_fed = target
		_apply_grey()
		return
	_fade = create_tween()
	_fade.tween_method(func(value: float) -> void:
		_fed = value
		_apply_grey(), _fed, target, fade_seconds)

func _apply_grey() -> void:
	if _sac != null:
		_sac.set_shader_parameter("grey_amount", fed_desaturation * _fed)

func _push_sac() -> void:
	if _sac == null:
		return
	_sac.set_shader_parameter("hue_center_degrees", hue_center_degrees)
	_sac.set_shader_parameter("hue_half_width_degrees", hue_half_width_degrees)
	_sac.set_shader_parameter("min_saturation", min_saturation)
	_sac.set_shader_parameter("region_min", region_min)
	_sac.set_shader_parameter("region_max", region_max)
	_sac.set_shader_parameter("region_softness", region_softness)
