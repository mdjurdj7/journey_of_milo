extends WorldEnvironment

@export var sky_top_color: Color = Color(0.82, 0.85, 0.86)
@export var horizon_color: Color = Color(0.87, 0.88, 0.85):
	set(value):
		horizon_color = value
		_push_pool_color()
# The procedural sky's sun halo (ProceduralSkyMaterial.sun_angle_max) - 0
# for an overcast sky with no visible sun; under fog_sky_affect 1.0 the
# sky is fog-coloured anyway, but with any aerial perspective the halo
# bled through as a pale blob in the upper frame.
@export var sun_halo_degrees: float = 0.0
# Depth fog: a linear ramp from fog_depth_begin (camera metres) to full
# fog_density at fog_depth_end - FOG_MODE_DEPTH, so the far field is
# actually removed rather than hazed (exponential fog at a usable
# density never reaches opacity inside the field). Colour matched to
# the sky at the horizon, no aerial-perspective blend (a flat colour, so
# nothing in the sky - sun halo, gradient - shows through the fog).
@export var fog_mode: Environment.FogMode = Environment.FOG_MODE_DEPTH
@export var fog_color: Color = Color(0.87, 0.88, 0.85)
@export var fog_density: float = 1.0
@export var fog_depth_begin: float = 14.0
@export var fog_depth_end: float = 28.0
@export var fog_sky_affect: float = 1.0
@export var fog_aerial_perspective: float = 0.0
# Tonemapping shifts how the fog itself reads (AgX/Filmic both compress
# highlights differently than linear) - exposed here so that can be
# corrected independently of fog_color/fog_density above, which stay
# whatever "true" fog color/thickness the region wants regardless of
# which tonemapper is active.
@export var fog_light_energy: float = 1.0:
	set(value):
		fog_light_energy = value
		_apply_fog_light_energy()
# Flat color fill instead of the sky's own color - AMBIENT_SOURCE_SKY was
# tinting every surface (sand most of all) noticeably blue, since the
# procedural sky's horizon/top colors lean cool. Neutral grey (no warm
# light in Region 1); together with the sun it puts dry sand at ~0.87
# before AgX.
@export var ambient_color: Color = Color(0.85, 0.85, 0.85):
	set(value):
		ambient_color = value
		_apply_ambient()
@export var ambient_energy: float = 0.7:
	set(value):
		ambient_energy = value
		_apply_ambient()
@export var ground_path: NodePath = ^"../Ground"

@export_group("Tonemap")
# AgX by default - switch to FILMIC live (Remote tab) if AgX doesn't read
# right once seen live; there's no way to detect that from code, this
# export IS the fallback.
@export var tonemap_mode: Environment.ToneMapper = Environment.TONE_MAPPER_AGX:
	set(value):
		tonemap_mode = value
		_apply_tonemap()
@export var tonemap_exposure: float = 1.0:
	set(value):
		tonemap_exposure = value
		_apply_tonemap()
@export var tonemap_white: float = 6.0:
	set(value):
		tonemap_white = value
		_apply_tonemap()

@export_group("SSAO")
# Meant to seat the Wanderer/enemies into the ground - light_affect is
# deliberately low (0.2) so contact shadowing doesn't also darken the
# flats themselves toward mud; retune radius/intensity together with
# ambient_energy above if it starts to.
@export var ssao_enabled: bool = true:
	set(value):
		ssao_enabled = value
		_apply_ssao()
@export var ssao_radius: float = 1.5:
	set(value):
		ssao_radius = value
		_apply_ssao()
@export var ssao_intensity: float = 1.5:
	set(value):
		ssao_intensity = value
		_apply_ssao()
@export var ssao_detail: float = 0.5:
	set(value):
		ssao_detail = value
		_apply_ssao()
@export var ssao_light_affect: float = 0.2:
	set(value):
		ssao_light_affect = value
		_apply_ssao()

@export_group("SSIL")
# Off for now - cost. The knob stays exported (not deleted) so turning it
# back on later is a one-line flip, not a re-add.
@export var ssil_enabled: bool = false:
	set(value):
		ssil_enabled = value
		_apply_ssil()

@export_group("Glow")
# Off - the Art Direction Bible forbids a glowing focal point. Exported
# (not just left at Environment's own default) so that constraint is
# visible/enforced here rather than implicit.
@export var glow_enabled: bool = false:
	set(value):
		glow_enabled = value
		_apply_glow()

@export_group("Adjustments")
# A nudge toward the bible's muted palette, not a color grade - contrast/
# saturation both stay close to 1.0 on purpose.
@export var adjustments_enabled: bool = true:
	set(value):
		adjustments_enabled = value
		_apply_adjustments()
@export var adjustment_brightness: float = 1.0:
	set(value):
		adjustment_brightness = value
		_apply_adjustments()
@export var adjustment_contrast: float = 1.06:
	set(value):
		adjustment_contrast = value
		_apply_adjustments()
@export var adjustment_saturation: float = 0.92:
	set(value):
		adjustment_saturation = value
		_apply_adjustments()

var _environment: Environment

func _ready() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top_color
	sky_material.sky_horizon_color = horizon_color
	sky_material.ground_bottom_color = horizon_color
	sky_material.ground_horizon_color = horizon_color
	sky_material.sun_angle_max = sun_halo_degrees

	var sky := Sky.new()
	sky.sky_material = sky_material

	_environment = Environment.new()
	_environment.background_mode = Environment.BG_SKY
	_environment.sky = sky
	_environment.fog_enabled = true
	_environment.fog_mode = fog_mode
	_environment.fog_light_color = fog_color
	_environment.fog_density = fog_density
	_environment.fog_depth_begin = fog_depth_begin
	_environment.fog_depth_end = fog_depth_end
	_environment.fog_sky_affect = fog_sky_affect
	_environment.fog_aerial_perspective = fog_aerial_perspective
	_apply_ambient()
	_apply_fog_light_energy()
	_apply_tonemap()
	_apply_ssao()
	_apply_ssil()
	_apply_glow()
	_apply_adjustments()

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

func _apply_fog_light_energy() -> void:
	if _environment == null:
		return
	_environment.fog_light_energy = fog_light_energy

func _apply_tonemap() -> void:
	if _environment == null:
		return
	_environment.tonemap_mode = tonemap_mode
	_environment.tonemap_exposure = tonemap_exposure
	_environment.tonemap_white = tonemap_white

func _apply_ssao() -> void:
	if _environment == null:
		return
	_environment.ssao_enabled = ssao_enabled
	_environment.ssao_radius = ssao_radius
	_environment.ssao_intensity = ssao_intensity
	_environment.ssao_detail = ssao_detail
	_environment.ssao_light_affect = ssao_light_affect

func _apply_ssil() -> void:
	if _environment == null:
		return
	_environment.ssil_enabled = ssil_enabled

func _apply_glow() -> void:
	if _environment == null:
		return
	_environment.glow_enabled = glow_enabled

func _apply_adjustments() -> void:
	if _environment == null:
		return
	_environment.adjustment_enabled = adjustments_enabled
	_environment.adjustment_brightness = adjustment_brightness
	_environment.adjustment_contrast = adjustment_contrast
	_environment.adjustment_saturation = adjustment_saturation

# Keeps Ground's standing-pool color matched to the sky's horizon color
# without manual duplication. Ground keeps its own pool_color export as
# the fallback if no sky node is present at ground_path.
func _push_pool_color() -> void:
	if not is_inside_tree():
		return
	var ground := get_node_or_null(ground_path) as Ground
	if ground:
		ground.set_pool_color_from_sky(horizon_color)
