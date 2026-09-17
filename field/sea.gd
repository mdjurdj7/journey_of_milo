extends MeshInstance3D
class_name Sea

const AMBIENCE_PATH := "res://assets/audio/Floor_0/ocean_waves.mp3"

# Matte, not a mirror: at roughness 0.7 / specular 0.12 the sun's lobe
# peaks under 1% of its radiance even dead in the mirror direction, so no
# white patch from any angle - see sea.gdshader's own doc. (0.25 / 0.5
# put that same peak near full white.)
@export var sea_roughness: float = 0.7:
	set(value):
		sea_roughness = value
		_apply_uniform("sea_roughness", value)
@export_range(0.0, 1.0) var sea_specular: float = 0.12:
	set(value):
		sea_specular = value
		_apply_uniform("sea_specular", value)

# The surface ripple - one slow scrolling two-octave noise field read two
# ways in sea.gdshader (see its own doc on these): noise_amplitude is its
# NORMAL perturbation (what the light's specular responds to),
# ripple_strength is how much the same field modulates the sky reflection
# amount - the part that actually reads as slow movement from the top-
# down camera. Never displaces vertices.
@export var noise_amplitude: float = 0.015:
	set(value):
		noise_amplitude = value
		_apply_uniform("noise_amplitude", value)
@export var noise_scale: float = 6.0:
	set(value):
		noise_scale = value
		_apply_uniform("noise_scale", value)
@export var noise_speed: float = 0.05:
	set(value):
		noise_speed = value
		_apply_uniform("noise_speed", value)
@export_range(0.0, 1.0) var ripple_strength: float = 0.35:
	set(value):
		ripple_strength = value
		_apply_uniform("ripple_strength", value)

@export_group("Waves")
# Long, slow swell and short, quick chop - normal-only now (their slope
# goes into the per-fragment normal, the long wave's height drives the
# foam's breathing; no vertex displacement - see sea.gdshader's vertex()).
# Angles are independent so the two don't run parallel; sea.gdshader
# receives the derived direction vectors, not the angles themselves.
@export var long_wave_length: float = 14.0:
	set(value):
		long_wave_length = value
		_apply_uniform("long_wave_length", value)
@export var long_wave_amplitude: float = 0.03:
	set(value):
		long_wave_amplitude = value
		_apply_uniform("long_wave_amplitude", value)
@export var long_wave_speed: float = 0.25:
	set(value):
		long_wave_speed = value
		_apply_uniform("long_wave_speed", value)
@export var long_wave_angle_degrees: float = 0.0:
	set(value):
		long_wave_angle_degrees = value
		_apply_uniform("long_wave_direction", _direction_from_angle(value))
@export var short_wave_length: float = 3.0:
	set(value):
		short_wave_length = value
		_apply_uniform("short_wave_length", value)
@export var short_wave_amplitude: float = 0.01:
	set(value):
		short_wave_amplitude = value
		_apply_uniform("short_wave_amplitude", value)
@export var short_wave_speed: float = 0.6:
	set(value):
		short_wave_speed = value
		_apply_uniform("short_wave_speed", value)
@export var short_wave_angle_degrees: float = 55.0:
	set(value):
		short_wave_angle_degrees = value
		_apply_uniform("short_wave_direction", _direction_from_angle(value))

@export_group("Sky Reflection")
# Schlick-shaped blend toward sky_reflect_color: sky_reflect_min of it
# looking straight down, full at grazing angles, fresnel_power shaping
# the rise (higher = the reflected-sky band stays narrower, closer to the
# true horizon). The floor is what lets the water sit lighter than the
# sand from the field camera's ~45 degree pitch, where the pure fresnel
# term is ~0.01 - see sea.gdshader's own doc. Near-white by default,
# paler than fog_color (the far horizon tone) on purpose.
@export var sky_reflect_color: Color = Color(0.78, 0.81, 0.84):
	set(value):
		sky_reflect_color = value
		_apply_uniform("sky_reflect_color", value)
@export_range(0.0, 1.0) var sky_reflect_min: float = 0.05:
	set(value):
		sky_reflect_min = value
		_apply_uniform("sky_reflect_min", value)
@export var fresnel_power: float = 4.0:
	set(value):
		fresnel_power = value
		_apply_uniform("fresnel_power", value)

@export_group("Depth Color")
# Driven by the VERTICAL water depth under each fragment (from the depth
# texture - see sea.gdshader's own conversion). Colour runs shallow_color
# -> deep_color and alpha shallow_alpha -> 1.0 over the same curve,
# smoothstep(0, depth_opaque, depth): shallow water is mostly the sand
# showing through tinted, past depth_opaque it's opaque deep_color. Muted
# teal, set so the three field hues stay distinct: pale warm sand
# (Ground.ground_color (0.74, 0.70, 0.60)), teal water (green-leaning,
# darker with depth), near-white sky (sky_reflect_color / the horizon's
# grey-blue (0.62, 0.66, 0.70)). Shallow is close to the horizon in value
# but greener; deep is well below both.
@export var shallow_color: Color = Color(0.54, 0.60, 0.61):
	set(value):
		shallow_color = value
		_apply_uniform("shallow_color", value)
@export var deep_color: Color = Color(0.26, 0.36, 0.41):
	set(value):
		deep_color = value
		_apply_uniform("deep_color", value)
@export_range(0.0, 1.0) var shallow_alpha: float = 0.15:
	set(value):
		shallow_alpha = value
		_apply_uniform("shallow_alpha", value)
# 2.0 = the field's own maximum water depth (Ground.landmass_below_sea_
# depth), so the deepest water actually reaches deep_color - larger
# values leave warm sand showing through everywhere and grey the water.
@export var depth_opaque: float = 2.0:
	set(value):
		depth_opaque = value
		_apply_uniform("depth_opaque", value)
# Per-channel absorption (1/m) applied to the see-through seabed sample:
# transmittance = exp(-depth * absorption). Red absorbed fastest, blue
# least, so the sand seen through the water cools and darkens with depth
# (and the caustics on it dim by the same law). Surface colour untouched.
@export var absorption: Vector3 = Vector3(1.4, 0.7, 0.5):
	set(value):
		absorption = value
		_apply_uniform("absorption", value)

@export_group("Refraction")
# UV displacement of the see-through screen sample at unit ripple slope -
# see sea.gdshader's own doc on how the composite works and why the sea
# draws first among transparents (_ready()). ~0.01 is 5-10 px at 1080p.
@export var refraction_strength: float = 0.01:
	set(value):
		refraction_strength = value
		_apply_uniform("refraction_strength", value)

@export_group("Surface Pattern")
# The visible pattern ON the water plane (distinct from the caustics on
# the seabed under it): two scrolling noise layers at surface_pattern_
# scale and a third of it, drifting in different directions at different
# speeds, whose ridges paint the surface toward sky_reflect_color - mean
# lift about surface_pattern_strength, peaks twice that, never darker
# than the depth tint. An overlay on the final surface/seabed mix, gated
# only by the waterline edge, so it reads the same in the shallows as in
# deep water regardless of how transparent the water is there. See
# sea.gdshader's own doc.
@export_range(0.0, 0.5) var surface_pattern_strength: float = 0.05:
	set(value):
		surface_pattern_strength = value
		_apply_uniform("surface_pattern_strength", value)
@export var surface_pattern_scale: float = 3.0:
	set(value):
		surface_pattern_scale = value
		_apply_uniform("surface_pattern_scale", value)
@export var surface_pattern_speed: float = 0.4:
	set(value):
		surface_pattern_speed = value
		_apply_uniform("surface_pattern_speed", value)
# The baked noise tile both the surface pattern and the ripple sample
# (see _create_surface_noise()): how many noise features span one tile.
# A tile is surface_pattern_scale metres for the pattern's large layer,
# noise_scale metres for the ripple's - so at 2 periods a feature is
# ~1.5m on the pattern and ~3m on the ripple. Rebakes live.
@export var surface_noise_periods: float = 2.0:
	set(value):
		surface_noise_periods = value
		_apply_surface_noise_frequency()
@export var surface_noise_octaves: int = 3:
	set(value):
		surface_noise_octaves = value
		_apply_surface_noise_frequency()

# sea_time wraps to [0, sea_time_period) so it never grows without bound
# (float precision in every time-driven term would degrade over a long
# session). The period is chosen so every time-driven term is at exactly
# the same phase at the wrap as at 0, so nothing pops - each term's
# "cycles per second", times the period, must be a whole number:
#   ripple drifts (noise_speed 0.05 x (1, 0.7) and x (-1.3, 0.9)):
#     0.05, 0.035, 0.065, 0.045 tiles/s -> whole at multiples of 200 s
#   pattern drifts (0.4 x (0.7, 0.4) and 0.4 x 1.7 x (-0.3, 0.9)):
#     0.28, 0.16, 0.204, 0.612 tiles/s -> whole at multiples of 250 s
#   waves (speed / wavelength): long 0.25/14, short 0.6/3
#     -> whole at multiples of 56 s
#   swash (1 / swash_period): 7 s -> whole at multiples of 7 s
#   -> lcm(200, 250, 56, 7) = 7000 s (~1h57m).
# A whole number of tiles is invisible because the noise tile repeats and
# the drift is applied in texture space (see sea.gdshader's surface_
# noise_rotated()); a whole number of wave cycles is invisible because
# sin() repeats. The foam's breathing reads the long wave, so it wraps
# with it; nothing else reads sea_time. Retune if any of those speeds/
# lengths/scales change - the arithmetic above is specific to the
# defaults. Precision at 7000 s: the largest drift is 0.612 x 7000 =
# 4284 tiles, where float32 resolves ~0.0005 tiles = 0.1 texel - fine.
@export var sea_time_period: float = 7000.0

@export_group("Foam")
# A thin bright line at the waterline: foam_width metres of water DEPTH
# wide (not a lateral distance - ~2-3x that across the beach's slope),
# hugging the true waterline however it curves, a touch lighter than
# shallow_color rather than white. Composited as opaque paint over the
# final surface/seabed mix (not inside the surface colour, which is
# nearly transparent exactly there - see sea.gdshader's foam_color doc).
# Patchy via value noise at edge_noise_scale, and breathes with the long
# wave's own height at that point rather than a generic timer.
@export var foam_color: Color = Color(0.66, 0.70, 0.70):
	set(value):
		foam_color = value
		_apply_uniform("foam_color", value)
@export var foam_width: float = 0.25:
	set(value):
		foam_width = value
		_apply_uniform("foam_width", value)
@export_range(0.0, 1.0) var foam_strength: float = 0.35:
	set(value):
		foam_strength = value
		_apply_uniform("foam_strength", value)

@export_group("Swash")
# A periodic wash advancing from swash_start_depth to the waterline,
# holding, receding - see sea.gdshader's swash_strength doc. Ground's wet
# band breathes with it: Sea pushes the shared inputs (the wrapped time,
# swash_period, swash_phase_noise_scale and the surface_noise tile) into
# Ground (_push_swash_source()/_push_sea_time()) so both shaders compute
# the identical phase. swash_period must divide sea_time_period so the
# phase doesn't jump at the time wrap.
# Its own colour, lighter than foam_color, so the front is the brightest
# thing near the line; a crisp leading edge (swash_edge_width of depth)
# and a soft trailing edge (swash_band_width) - see sea.gdshader's own
# swash_color doc.
@export var swash_color: Color = Color(0.82, 0.84, 0.82):
	set(value):
		swash_color = value
		_apply_uniform("swash_color", value)
@export_range(0.0, 1.0) var swash_strength: float = 0.7:
	set(value):
		swash_strength = value
		_apply_uniform("swash_strength", value)
@export var swash_edge_width: float = 0.05:
	set(value):
		swash_edge_width = value
		_apply_uniform("swash_edge_width", value)
@export var swash_period: float = 7.0:
	set(value):
		swash_period = value
		_apply_uniform("swash_period", value)
		_push_swash_source()
@export var swash_start_depth: float = 0.6:
	set(value):
		swash_start_depth = value
		_apply_uniform("swash_start_depth", value)
@export var swash_band_width: float = 0.2:
	set(value):
		swash_band_width = value
		_apply_uniform("swash_band_width", value)
# Phase offset along the shore: the noise at swash_phase_noise_scale
# (slow, ~24m features) shifts each stretch's phase by (noise - 0.5) x
# swash_phase_spread of a cycle - so the whole shore is within
# +-spread/2 of a cycle of itself: one continuous front arriving a
# little earlier here and later there, never unrelated patches. Both
# pushed into Ground too (see _push_swash_source()).
@export var swash_phase_noise_scale: float = 24.0:
	set(value):
		swash_phase_noise_scale = value
		_apply_uniform("swash_phase_noise_scale", value)
		_push_swash_source()
@export_range(0.0, 1.0) var swash_phase_spread: float = 0.15:
	set(value):
		swash_phase_spread = value
		_apply_uniform("swash_phase_spread", value)
		_push_swash_source()
@export var edge_noise_scale: float = 4.0:
	set(value):
		edge_noise_scale = value
		_apply_uniform("edge_noise_scale", value)

@export_group("Wave Mesh")
# Same split as ground.gd's fine relief mesh vs. coarse dressing frame:
# an inner patch (self's own mesh) covering inner_wave_extent meters out
# from the near shoreward edge (plus mesh_inland_reach back toward the
# Tower, and width_margin to each side - the whole playable field and
# everything the camera can reach sit inside it) at inner_wave_spacing
# resolution, and a coarse outer skirt (_outer_skirt) covering the rest
# of sea_depth at outer_wave_spacing. Both meshes share one
# ShaderMaterial.
#
# The plane is exactly flat: sea.gdshader no longer displaces vertices,
# and evaluates the normal, ripple, surface pattern, depth and refraction
# per fragment from world position - so vertex spacing cannot show
# through as edges anywhere, and the inner/outer split is now only about
# vertex budget, not quality. inner_wave_spacing is kept fine (0.5m,
# ~200k vertices at the current extents) so the split stays ready for
# any future displacement. Sizing the inner patch tighter (e.g. from the
# painted land's bounds) would need a T-junction-safe frame of skirt
# strips around it; with nothing per-vertex left to save, one wide patch
# is the version with no seams to get wrong.
#
# outer_wave_spacing only coarsens the SKIRT'S OWN DEPTH (Z) subdivision -
# see _rebuild_wave_meshes(), which deliberately gives the skirt the exact
# same WIDTH (X) column count/spacing as the inner patch. Two independently
# generated PlaneMesh resources meeting edge-to-edge is a classic T-junction
# crack source even where both sides are mathematically flat - matching
# column count is what makes the shared edge watertight.
@export var inner_wave_extent: float = 60.0:
	set(value):
		inner_wave_extent = value
		_rebuild_if_ready()
@export var inner_wave_spacing: float = 0.5:
	set(value):
		inner_wave_spacing = value
		_rebuild_if_ready()
@export var outer_wave_spacing: float = 20.0:
	set(value):
		outer_wave_spacing = value
		_rebuild_if_ready()

# How many meters of open water it takes for wave amplitude to build back
# up to full as the water gets further past the actual shoreline (the same
# landmass shape ground.gd's wet band/RegionField's wade drain key off, not
# a fixed world-space line) - 0 right at the shore, full amplitude in open
# water. Widen this if the near-shore water still reads as too lively;
# shader-only, no mesh rebuild needed. Replaces the old inner_wave_extent-
# anchored wave_fade_width, which only ever calmed waves near the single
# seaward line Sea used to be positioned from - now that Sea covers the
# whole field (mesh_inland_reach) and the shoreline wraps three sides, a
# fixed line can't track it; see _push_landmass_uniforms()'s own doc for
# how the actual shoreline reaches this shader.
@export var wave_calm_distance: float = 2.0:
	set(value):
		wave_calm_distance = value
		_apply_uniform("wave_calm_distance", value)

# Edge: a thin waterline softener - alpha ramps 0 -> shallow_alpha over
# the first shore_fade_width metres of water depth, so the contour reads
# as a line rather than a haze (the old multi-metre noised shore_fade was
# the haze; the ground's own wet band carries the transition inland, so
# nothing here duplicates it). Still what keeps flat water from rendering
# over dry land: the sea mesh's near edge sits generously inland of the
# real shoreline (see _rebuild_wave_meshes()), and depth 0 -> alpha 0 is
# what hides it there.
@export var shore_fade_width: float = 0.3:
	set(value):
		shore_fade_width = value
		_apply_uniform("shore_fade_width", value)

# Distance fog: the sea material is fog_disabled (see sea.gdshader), so
# it reproduces the WorldEnvironment's depth fog itself with the same
# curve and the same unlit blend - keep these equal to the environment's
# fog_depth_begin / fog_depth_end / fog_color (14 / 28 / (0.86, 0.87,
# 0.86)) and fog_strength 1.0, and the shore and the water plane fog at
# the same rate at the same distance. The near-field reflection has its
# own, paler sky_reflect_color above.
@export var fog_color: Color = Color(0.86, 0.87, 0.86):
	set(value):
		fog_color = value
		_apply_uniform("fog_color", value)
@export_range(0.0, 1.0) var fog_strength: float = 1.0:
	set(value):
		fog_strength = value
		_apply_uniform("fog_strength", value)
@export var fog_near_distance: float = 14.0:
	set(value):
		fog_near_distance = value
		_apply_uniform("fog_near_distance", value)
@export var fog_far_distance: float = 28.0:
	set(value):
		fog_far_distance = value
		_apply_uniform("fog_far_distance", value)

# Plane X spans the field's full width plus width_margin on each side,
# so it runs well past the fog regardless of field_extents; Z is a flat
# sea_depth back from the near (shore) edge, split into the inner/outer
# meshes above.
@export var width_margin: float = 200.0
@export var sea_depth: float = 400.0
# How far past near_edge_z, back toward the Tower, the inner (fine) mesh
# also extends - lets one Sea plane cover the whole landmass (including
# inland of the inland wall/gate), not just the strip seaward of near_edge_z,
# so the ground's own height (not this mesh's edge) is what decides where
# water shows anywhere on the field. Independent of sea_edge_distance/
# get_near_edge_z() on purpose - those still mean exactly what they always
# did (the wade-line/shoreline-reference point other code reads), this only
# grows the MESH's own geometric reach around that same point. Reduces to
# the old inner-plane math exactly at 0 (see _position_relative_to_spawn()'s
# own formula) - not a behavior change for that case.
@export var mesh_inland_reach: float = 60.0:
	set(value):
		mesh_inland_reach = value
		_rebuild_if_ready()

# Kept fractionally below 0.0 (Ground's plane) so the two don't z-fight
# along the shoreline where they meet.
@export var sea_level: float = -0.05:
	set(value):
		sea_level = value
		_reposition_if_ready()

@export var region_field_path: NodePath = ^".."
@export var wanderer_path: NodePath = ^"../Wanderer"
@export var ground_path: NodePath = ^"../Ground"
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
var _surface_noise: NoiseTexture2D
var _outer_skirt: MeshInstance3D
var _wanderer: Node3D
var _audio_player: AudioStreamPlayer
var _current_volume_db: float
var _forward: Vector3 = Vector3.FORWARD
var _ready_complete: bool = false
var _sea_time: float = 0.0

func _ready() -> void:
	# RegionField freezes itself (and, by inheritance, Sea) on battle
	# contact, but the shader's normal drift must keep animating through
	# that freeze - see _physics_process()'s _sea_time accumulation below,
	# which is what the shader actually reads instead of the engine's own
	# TIME. The distance-based audio fade further down keeps running too,
	# but its only input (the Wanderer's position) is itself frozen while
	# the field is, so it just settles and stops changing - not a case of
	# field logic advancing during a freeze.
	process_mode = Node.PROCESS_MODE_ALWAYS

	_material = ShaderMaterial.new()
	_material.shader = load("res://field/sea.gdshader")
	# Drawn FIRST among transparent surfaces. sea.gdshader composites its
	# see-through component from the screen texture (opaque geometry only)
	# and writes ALPHA 1.0 - so any alpha-blended decal sorted before it
	# (the Wanderer's contact shadow, footprints, an enemy's spawn fade,
	# all sitting on the seabed while wading) would be replaced by the
	# capture and vanish. Lower priority makes those draw after the sea and
	# blend over it instead. Over dry sand the plane is depth-tested away
	# by the ground regardless, so this only matters in the water.
	_material.render_priority = -1
	_create_surface_noise()
	_apply_all_uniforms()
	# Ground precedes Sea in the scene, so its material already exists
	# here; the swash setters above re-push on any later change.
	_push_swash_source()

	# self is the inner (fine) patch; _outer_skirt is the coarse far skirt
	# - see inner_wave_extent's own doc.
	# Receives only - a flat expanse of water casting its own shadow onto
	# itself/the shore has nothing to gain and risks self-shadowing
	# artifacts on a surface that's already animating.
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_outer_skirt = MeshInstance3D.new()
	_outer_skirt.name = "OuterSkirt"
	_outer_skirt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_outer_skirt)

	_wanderer = get_node_or_null(wanderer_path) as Node3D
	_rebuild_wave_meshes()

	_push_landmass_uniforms()
	# Ground's landmass exports all trigger a relief_rebuilt on edit (see
	# RegionField's own use of the same signal for its walls) - reconnecting
	# here keeps wave_fade_factor()'s shoreline in sync with live shape
	# tuning too, not just the initial value at scene load.
	var ground := get_node_or_null(ground_path) as Ground
	if ground != null:
		ground.relief_rebuilt.connect(_push_landmass_uniforms)

	_spawn_ambience()

	_ready_complete = true

# The one noise tile the shader's surface pattern and ripple both sample
# (see sea.gdshader's surface_noise doc for why a texture and not
# procedural noise): seamless FastNoiseLite Perlin, 256x256, mipmapped,
# normalized to 0..1, pushed once as the surface_noise sampler - the
# shader's own uniform hints (repeat_enable, filter_linear_mipmap) do the
# wrapping/filtering. NoiseTexture2D bakes on a thread; the material
# samples whatever it holds and picks up the finished tile automatically.
const SURFACE_NOISE_SIZE: int = 256

func _create_surface_noise() -> void:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_surface_noise = NoiseTexture2D.new()
	_surface_noise.width = SURFACE_NOISE_SIZE
	_surface_noise.height = SURFACE_NOISE_SIZE
	_surface_noise.seamless = true
	_surface_noise.generate_mipmaps = true
	_surface_noise.normalize = true
	_surface_noise.noise = noise
	_apply_surface_noise_frequency()
	_apply_uniform("surface_noise", _surface_noise)

# FastNoiseLite's frequency is per texel here (NoiseTexture2D samples it
# at pixel coordinates), so periods-per-tile / tile-size-in-texels is the
# base frequency. Setting it on the FastNoiseLite triggers a rebake.
func _apply_surface_noise_frequency() -> void:
	if _surface_noise == null:
		return
	var noise := _surface_noise.noise as FastNoiseLite
	if noise == null:
		return
	noise.frequency = maxf(surface_noise_periods, 0.01) / float(SURFACE_NOISE_SIZE)
	noise.fractal_octaves = maxi(surface_noise_octaves, 1)

# The swash's shared inputs, into Ground (see the Swash export group's
# doc on why Sea is the single source): the one surface_noise texture
# object, swash_period and swash_phase_noise_scale once (and on change),
# the wrapped time every physics frame. Ground's own _apply_uniform()
# no-ops until its material exists, so an early call is harmless.
func _push_swash_source() -> void:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null or _surface_noise == null:
		return
	ground.set_swash_source(_surface_noise, swash_period, swash_phase_noise_scale, swash_phase_spread)

func _push_sea_time() -> void:
	var ground := get_node_or_null(ground_path) as Ground
	if ground != null:
		ground.set_sea_time(_sea_time)

# Guards sea_level/sea_edge_distance's setters: they can fire during
# scene deserialization before _ready() has built the meshes or resolved
# _wanderer, so only reposition once that initial setup is done.
func _reposition_if_ready() -> void:
	if _ready_complete:
		_position_relative_to_spawn()

# Same guard, for the exports that change mesh geometry (subdivisions/
# extent) rather than just position.
func _rebuild_if_ready() -> void:
	if _ready_complete:
		_rebuild_wave_meshes()

func _direction_from_angle(angle_degrees: float) -> Vector2:
	var angle_radians := deg_to_rad(angle_degrees)
	return Vector2(cos(angle_radians), sin(angle_radians))

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

# Sets _forward as a side effect. Split out from _position_relative_to_
# spawn() so get_near_edge_z() below can call it without needing the
# meshes to exist yet — unlike the rest of that function, this only
# touches _wanderer and region_field, both already safe to resolve early.
func _compute_near_edge_z() -> float:
	var region_field := get_node_or_null(region_field_path) as RegionField
	_forward = region_field.get_forward() if region_field else Vector3.FORWARD
	var spawn: Vector3 = _wanderer.global_position if _wanderer else Vector3.ZERO
	return (spawn - _forward * sea_edge_distance).z

# Lazily resolves _wanderer if needed, so this is safe to call from
# another node's _ready() regardless of node-ready order (ground.gd
# uses it for the wet-band shore line) — same reasoning as
# RegionField.get_forward().
func get_near_edge_z() -> float:
	if _wanderer == null:
		_wanderer = get_node_or_null(wanderer_path) as Node3D
	return _compute_near_edge_z()

# Builds the inner (fine) and outer (coarse) PlaneMeshes and repositions
# both - see inner_wave_extent's own doc for why there are two. Both use
# the exact same full_width AND THE SAME subdivide_width (column count) -
# the skirt only ever coarsens its own DEPTH (Z) subdivision. That's what
# actually makes the shared edge watertight: two independent PlaneMesh
# resources meeting edge-to-edge need identical vertex X-positions along
# that edge to avoid a T-junction crack, and a crack shows up as a visible
# hairline seam even on an exactly flat plane - only matching vertex
# positions fix it.
# Column count is a small, uniform cost across the whole skirt (not just
# its inner edge) - simpler and just as cheap as a tapering LOD skirt would
# be, since the real vertex-count savings here come from coarsening depth,
# not width.
func _rebuild_wave_meshes() -> void:
	var full_width: float = _field_width() + width_margin * 2.0
	var inner_depth: float = inner_wave_extent + mesh_inland_reach
	var outer_depth: float = maxf(sea_depth - inner_wave_extent, 0.0)
	var shared_width_subdivisions: int = _subdivisions_for(full_width, inner_wave_spacing)

	var inner_plane := PlaneMesh.new()
	inner_plane.size = Vector2(full_width, inner_depth)
	inner_plane.subdivide_width = shared_width_subdivisions
	inner_plane.subdivide_depth = _subdivisions_for(inner_depth, inner_wave_spacing)
	inner_plane.material = _material
	# A single PlaneMesh resource is one contiguous, engine-generated
	# vertex/index buffer - watertight internally by construction, no
	# multi-quad stitching to worry about here regardless of subdivision
	# count.
	mesh = inner_plane

	var outer_plane := PlaneMesh.new()
	outer_plane.size = Vector2(full_width, outer_depth)
	outer_plane.subdivide_width = shared_width_subdivisions
	outer_plane.subdivide_depth = _subdivisions_for(outer_depth, outer_wave_spacing)
	outer_plane.material = _material
	_outer_skirt.mesh = outer_plane

	_position_relative_to_spawn()

# Segment count for a PlaneMesh axis given a target vertex spacing -
# always at least 1 so a degenerate (zero-length) axis still builds a
# valid, if trivial, plane instead of an invalid subdivision count.
func _subdivisions_for(extent: float, spacing: float) -> int:
	return maxi(int(round(extent / maxf(spacing, 0.01))), 1)

# Centered in X on the field's own center (RegionField's world X —
# field_extents is always centered on RegionField's origin). Near edge
# sits sea_edge_distance behind the Wanderer's spawn point along
# RegionField.get_forward() (never assumed to be -Z). The inner patch spans
# mesh_inland_reach meters back toward the Tower from there PLUS
# inner_wave_extent meters further away from it; the outer skirt covers
# the remaining sea_depth - inner_wave_extent beyond that. self (the inner
# patch)'s own position is what global_position sets; _outer_skirt's
# position is local to self, so it's the world-space gap between the two
# centers.
func _position_relative_to_spawn() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	var field_center_x: float = region_field.global_position.x if region_field else 0.0

	var near_edge_z := _compute_near_edge_z()
	var inner_depth: float = inner_wave_extent + mesh_inland_reach
	var outer_depth: float = maxf(sea_depth - inner_wave_extent, 0.0)
	# The inner patch now runs from mesh_inland_reach meters inland of
	# near_edge_z out to inner_wave_extent meters seaward of it, so it's no
	# longer centered ON near_edge_z - centered on the midpoint of that
	# combined span instead. Reduces to the original near_edge_z - forward.z
	# * inner_wave_extent/2 exactly when mesh_inland_reach is 0.
	var inner_center_z := near_edge_z + _forward.z * (mesh_inland_reach - inner_wave_extent) / 2.0
	var outer_center_z := near_edge_z - _forward.z * (inner_wave_extent + outer_depth / 2.0)

	global_position = Vector3(field_center_x, sea_level, inner_center_z)
	_outer_skirt.position = Vector3(0.0, 0.0, outer_center_z - inner_center_z)

	# wave_fade_factor() in the shader needs to know where "near the
	# shore" is in world space - pushed here (not _apply_all_uniforms())
	# since it depends on the Wanderer's spawn position, not available
	# until this function's first real call. Still anchored on near_edge_z
	# alone (the seaward shore) - left/right/inland shorelines won't get
	# the same wave-calming fade. Flagged, not fixed, this round.
	_apply_uniform("near_edge_z", near_edge_z)
	_apply_uniform("shore_forward_z", _forward.z)

	var half_width := (_field_width() + width_margin * 2.0) / 2.0
	print("Sea: near edge z=%.2f, inner extent=%.1fm (incl. %.1fm inland reach), outer extent=%.1fm, X extent=[%.2f, %.2f]" % [near_edge_z, inner_depth, mesh_inland_reach, outer_depth, global_position.x - half_width, global_position.x + half_width])

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

func _physics_process(delta: float) -> void:
	_sea_time = fmod(_sea_time + delta, maxf(sea_time_period, 1.0))
	_apply_uniform("sea_time", _sea_time)
	_push_sea_time()

	if _audio_player == null or _wanderer == null:
		return

	# Distance is measured along _forward (not assumed +Z) from the
	# Wanderer to the near shoreward edge, clamped to 0 once the Wanderer
	# is at or past it. Calls _compute_near_edge_z() directly rather than
	# back-deriving it from global_position, which (post wave-mesh split)
	# is only the inner patch's own center, not the whole plane's.
	var near_edge_z := _compute_near_edge_z()
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
	_apply_uniform("sea_roughness", sea_roughness)
	_apply_uniform("sea_specular", sea_specular)
	_apply_uniform("noise_amplitude", noise_amplitude)
	_apply_uniform("noise_scale", noise_scale)
	_apply_uniform("noise_speed", noise_speed)
	_apply_uniform("ripple_strength", ripple_strength)

	_apply_uniform("long_wave_length", long_wave_length)
	_apply_uniform("long_wave_amplitude", long_wave_amplitude)
	_apply_uniform("long_wave_speed", long_wave_speed)
	_apply_uniform("long_wave_direction", _direction_from_angle(long_wave_angle_degrees))
	_apply_uniform("short_wave_length", short_wave_length)
	_apply_uniform("short_wave_amplitude", short_wave_amplitude)
	_apply_uniform("short_wave_speed", short_wave_speed)
	_apply_uniform("short_wave_direction", _direction_from_angle(short_wave_angle_degrees))

	_apply_uniform("sky_reflect_color", sky_reflect_color)
	_apply_uniform("sky_reflect_min", sky_reflect_min)
	_apply_uniform("fresnel_power", fresnel_power)

	_apply_uniform("shallow_color", shallow_color)
	_apply_uniform("deep_color", deep_color)
	_apply_uniform("shallow_alpha", shallow_alpha)
	_apply_uniform("depth_opaque", depth_opaque)
	_apply_uniform("absorption", absorption)
	_apply_uniform("refraction_strength", refraction_strength)

	_apply_uniform("surface_pattern_strength", surface_pattern_strength)
	_apply_uniform("surface_pattern_scale", surface_pattern_scale)
	_apply_uniform("surface_pattern_speed", surface_pattern_speed)

	_apply_uniform("foam_color", foam_color)
	_apply_uniform("foam_width", foam_width)
	_apply_uniform("foam_strength", foam_strength)
	_apply_uniform("edge_noise_scale", edge_noise_scale)

	_apply_uniform("swash_color", swash_color)
	_apply_uniform("swash_strength", swash_strength)
	_apply_uniform("swash_edge_width", swash_edge_width)
	_apply_uniform("swash_period", swash_period)
	_apply_uniform("swash_start_depth", swash_start_depth)
	_apply_uniform("swash_band_width", swash_band_width)
	_apply_uniform("swash_phase_noise_scale", swash_phase_noise_scale)
	_apply_uniform("swash_phase_spread", swash_phase_spread)

	_apply_uniform("wave_calm_distance", wave_calm_distance)

	_apply_uniform("shore_fade_width", shore_fade_width)
	_apply_uniform("fog_color", fog_color)
	_apply_uniform("fog_strength", fog_strength)
	_apply_uniform("fog_near_distance", fog_near_distance)
	_apply_uniform("fog_far_distance", fog_far_distance)

# Mirrors Ground's own landmass shape into the shader so wave_fade_factor()
# reads the exact same shoreline the wet band and wade drain do, instead of
# an independently-tuned line (the bug this exists to fix - see sea.gdshader's
# own wave_calm_distance doc). Reads Ground's exports directly (plain
# properties, no ordering hazard) plus two Z references that are themselves
# order-safe lazy getters: RegionField.get_inland_z() and this node's own
# get_near_edge_z(). landmass_seaward_edge_z is resolved here (0 means
# "use near_edge_z", same as Ground._seaward_edge_z()) rather than reading
# Ground's private cache, so this never touches Ground's internals directly.
func _push_landmass_uniforms() -> void:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return
	var region_field := get_node_or_null(region_field_path) as RegionField

	_apply_uniform("landmass_half_width_inland", ground.landmass_half_width_inland)
	_apply_uniform("landmass_half_width_seaward", ground.landmass_half_width_seaward)
	_apply_uniform("landmass_width_curve_power", ground.landmass_width_curve_power)
	_apply_uniform("shoreline_noise_scale", ground.shoreline_noise_scale)
	_apply_uniform("shoreline_noise_amplitude", ground.shoreline_noise_amplitude)
	_apply_uniform("landmass_inland_z", region_field.get_inland_z() if region_field else 0.0)
	_apply_uniform("landmass_seaward_edge_z", ground.landmass_seaward_edge_z)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)
