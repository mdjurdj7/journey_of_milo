extends DirectionalLight3D
class_name OvercastLight

@export var elevation_degrees: float = 80.0:
	set(value):
		elevation_degrees = value
		_apply_rotation()
@export var azimuth_degrees: float = 0.0:
	set(value):
		azimuth_degrees = value
		_apply_rotation()
@export var energy: float = 1.0:
	set(value):
		energy = value
		light_energy = value
@export var color: Color = Color(0.82, 0.85, 0.88):
	set(value):
		color = value
		light_color = value

@export_group("Shadows")
@export var shadows_enabled: bool = true:
	set(value):
		shadows_enabled = value
		shadow_enabled = value
@export var shadow_max_distance: float = 80.0:
	set(value):
		shadow_max_distance = value
		directional_shadow_max_distance = value
# Softens the shadow's own penumbra (physically, a wider light disc) so
# edges read as soft rather than a hard cutout - matches an overcast sky's
# own diffuse, non-point light source.
@export var shadow_softness: float = 1.5:
	set(value):
		shadow_softness = value
		light_angular_distance = value
# Post-blur on top of shadow_softness's own penumbra. Named _amount, not
# shadow_blur, because Light3D already has a native property of that
# exact name - redeclaring it here would shadow (no pun intended) the
# engine's own property instead of adding a new tunable.
@export var shadow_blur_amount: float = 2.5:
	set(value):
		shadow_blur_amount = value
		shadow_blur = value
# How dark/opaque the shadow reads (1 = fully opaque, lower = lighter).
# Overcast light is soft and ambient-heavy, so a fully black shadow reads
# wrong - ~0.6 keeps it present without crushing shadowed detail to
# black. Named _darkness, not shadow_opacity, for the same reason
# shadow_blur_amount isn't named shadow_blur - Light3D already owns that
# exact property name.
@export var shadow_darkness: float = 0.6:
	set(value):
		shadow_darkness = value
		shadow_opacity = value

# Battle framing is a tight two-character medium shot (see CameraRig's
# own battle_distance_min..max/battle_fov), nowhere near as wide as the field
# exploration view shadow_max_distance above is tuned for - tightening to
# this during battle spends the same shadow map resolution over a much
# smaller area instead of most of it landing on ground the camera can't
# even see. shadow_max_distance itself (the export, not the native
# directional_shadow_max_distance property this pushes to) is left
# untouched by enter_battle()/exit_battle() below specifically so it
# stays the value exit_battle() restores.
@export var battle_shadow_max_distance: float = 15.0

func _ready() -> void:
	_apply_rotation()
	light_energy = energy
	light_color = color
	shadow_enabled = shadows_enabled
	light_angular_distance = shadow_softness
	shadow_blur = shadow_blur_amount
	shadow_opacity = shadow_darkness
	# 4-split PSSM (cascaded shadow maps) - a fixed technique choice, not
	# exposed as a tunable, so it's applied unconditionally whenever
	# shadows are on.
	directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	# Smooths the transition between PSSM cascades instead of a visible seam
	# where one split ends and the next begins - a fixed technique choice,
	# like the split count itself, not exposed as a tunable.
	directional_shadow_blend_splits = true
	directional_shadow_max_distance = shadow_max_distance
	sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	# Explicit rather than left to whatever the engine default happens to
	# be: a cull mask that excludes layer 1 would mean this light (and its
	# shadows) simply doesn't affect anything in this project - every mesh
	# here stays on the default layer 1 - regardless of light_energy,
	# which matches "shadows don't render at any light energy" exactly.
	light_cull_mask = 1

func _apply_rotation() -> void:
	rotation_degrees = Vector3(-elevation_degrees, azimuth_degrees, 0.0)

# Called by region_field.gd on enemy contact.
func enter_battle() -> void:
	directional_shadow_max_distance = battle_shadow_max_distance

# Called by region_field.gd once the battle resolves. Reads shadow_max_
# distance (the export), not a separately cached value - enter_battle()
# never touches that export, only the native property it feeds, so it's
# always still holding the field value here.
func exit_battle() -> void:
	directional_shadow_max_distance = shadow_max_distance
