extends MeshInstance3D
class_name Sea

const AMBIENCE_PATH := "res://assets/audio/Floor_0/ocean_waves.mp3"

# Sea's one color source — no push from region_sky.gd or anywhere else.
# Also the fresnel target below - see fresnel_power's own doc.
@export var sea_color: Color = Color(0.52, 0.60, 0.64):
	set(value):
		sea_color = value
		_apply_uniform("sea_color", value)

# Soft sheen, not a mirror.
@export var sea_roughness: float = 0.25:
	set(value):
		sea_roughness = value
		_apply_uniform("sea_roughness", value)

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

@export_group("Waves")
# Long, slow swell and short, quick chop - real vertex displacement (see
# _rebuild_wave_meshes()'s mesh-resolution exports below for why that
# needs its own mesh, not just this shader). Angles are independent so
# the two don't run parallel; sea.gdshader receives the derived direction
# vectors, not the angles themselves.
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

@export_group("Fresnel")
# Blends sea_color toward fog_color (already the sky/horizon tone - see
# its own doc) at grazing angles. Higher = the reflected-sky band stays
# narrower, closer to the true horizon.
@export var fresnel_power: float = 4.0:
	set(value):
		fresnel_power = value
		_apply_uniform("fresnel_power", value)

@export_group("Depth Color")
# Driven by the same view-space depth_diff the shore alpha fade already
# reads from the depth texture - see shore_fade's own doc. shallow_color
# is sand showing through a thin film of water; deep_color is a touch
# darker/more saturated past shallow_depth, saturating by
# deep_saturate_depth.
@export var shallow_color: Color = Color(0.62, 0.66, 0.64):
	set(value):
		shallow_color = value
		_apply_uniform("shallow_color", value)
@export var deep_color: Color = Color(0.34, 0.44, 0.50):
	set(value):
		deep_color = value
		_apply_uniform("deep_color", value)
@export var shallow_depth: float = 0.3:
	set(value):
		shallow_depth = value
		_apply_uniform("shallow_depth", value)
@export var deep_saturate_depth: float = 3.0:
	set(value):
		deep_saturate_depth = value
		_apply_uniform("deep_saturate_depth", value)

@export_group("Foam")
# A pale (not white) band, foam_width meters of water-DEPTH wide (not a
# lateral distance), hugging the true waterline however it actually
# curves. Layered on top of the depth color/fresnel above, not a
# replacement for the shore alpha fade below - see shore_fade's own doc
# for why that has to stay. Modulated by the same edge noise the alpha
# fade wanders by, and breathes with the long wave's own height at that
# point rather than a generic timer.
@export var foam_color: Color = Color(0.86, 0.88, 0.86):
	set(value):
		foam_color = value
		_apply_uniform("foam_color", value)
@export var foam_width: float = 0.4:
	set(value):
		foam_width = value
		_apply_uniform("foam_width", value)
@export_range(0.0, 1.0) var foam_strength: float = 0.5:
	set(value):
		foam_strength = value
		_apply_uniform("foam_strength", value)

@export_group("Wave Mesh")
# Same split as ground.gd's fine relief mesh vs. coarse dressing frame:
# an inner patch (self's own mesh) covering inner_wave_extent meters out
# from the near shoreward edge at inner_wave_spacing resolution, and a
# coarse outer skirt (_outer_skirt) covering the rest of sea_depth at
# outer_wave_spacing - the far skirt is fogged out anyway, so it doesn't
# need to resolve the waves at all. Both meshes share one ShaderMaterial,
# so the outer skirt reading as flat isn't a per-mesh toggle - it falls
# out naturally from wave_fade_factor() in the shader, which fades
# displacement to 0 by inner_wave_extent purely as a function of world
# position, seamlessly at whatever position the two meshes actually meet.
#
# outer_wave_spacing only coarsens the SKIRT'S OWN DEPTH (Z) subdivision -
# see _rebuild_wave_meshes(), which deliberately gives the skirt the exact
# same WIDTH (X) column count/spacing as the inner patch. Two independently
# generated PlaneMesh resources meeting edge-to-edge is a classic T-junction
# crack source even where both sides are mathematically flat (zero
# displacement doesn't help if the two edges don't share the same vertex
# X-positions to begin with) - matching column count is what actually
# makes the shared edge watertight, not the displacement math alone.
@export var inner_wave_extent: float = 60.0:
	set(value):
		inner_wave_extent = value
		_apply_uniform("inner_wave_extent", value)
		_rebuild_if_ready()
@export var inner_wave_spacing: float = 1.0:
	set(value):
		inner_wave_spacing = value
		_rebuild_if_ready()
@export var outer_wave_spacing: float = 20.0:
	set(value):
		outer_wave_spacing = value
		_rebuild_if_ready()
# How many meters before inner_wave_extent the wave amplitude starts
# easing to 0 - widen this if the inner/outer boundary is visible as a
# seam; shader-only, no mesh rebuild needed.
@export var wave_fade_width: float = 25.0:
	set(value):
		wave_fade_width = value
		_apply_uniform("wave_fade_width", value)

# Edge fade: alpha fades to 0 over shore_fade meters of scene-depth
# difference between the water surface and whatever's behind it (the
# depth texture), so the water thins into the sand instead of cutting
# off at the mesh edge. edge_noise_amplitude/scale wander that fade
# distance so the waterline isn't a straight, uniform band. Still the
# only thing gating ALPHA - depth color and foam above are layered on
# top of it, not a replacement: the sea mesh's near edge sits generously
# inland of the real shoreline (see _rebuild_wave_meshes()), and this
# depth-buffer read is what keeps flat water from rendering over dry
# land there.
@export var shore_fade: float = 3.0:
	set(value):
		shore_fade = value
		_apply_uniform("shore_fade", value)
@export var edge_noise_amplitude: float = 1.5:
	set(value):
		edge_noise_amplitude = value
		_apply_uniform("edge_noise_amplitude", value)
@export var edge_noise_scale: float = 4.0:
	set(value):
		edge_noise_scale = value
		_apply_uniform("edge_noise_scale", value)

# Distance: blends toward fog_color between fog_near_distance and
# fog_far_distance so far water dissolves into the horizon. Also the
# fresnel target above - it's already the region's sky/horizon tone (see
# region_sky.gd's near-identical horizon_color default), so there's no
# separate sky-color plumbing.
@export var fog_color: Color = Color(0.85, 0.87, 0.88):
	set(value):
		fog_color = value
		_apply_uniform("fog_color", value)
@export var fog_near_distance: float = 60.0:
	set(value):
		fog_near_distance = value
		_apply_uniform("fog_near_distance", value)
@export var fog_far_distance: float = 250.0:
	set(value):
		fog_far_distance = value
		_apply_uniform("fog_far_distance", value)

# Plane X spans the field's full width plus width_margin on each side,
# so it runs well past the fog regardless of field_extents; Z is a flat
# sea_depth back from the near (shore) edge, split into the inner/outer
# meshes above.
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
	_apply_all_uniforms()

	# self is the inner (fine, displaced) patch; _outer_skirt is the
	# coarse, effectively-flat far skirt - see inner_wave_extent's own doc.
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

	_spawn_ambience()

	_ready_complete = true

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
# hairline seam even where both sides evaluate to zero displacement -
# matching displacement math alone (wave_fade_factor() reaching exactly 0
# at the boundary; see its own doc) doesn't fix a vertex-position mismatch.
# Column count is a small, uniform cost across the whole skirt (not just
# its inner edge) - simpler and just as cheap as a tapering LOD skirt would
# be, since the real vertex-count savings here come from coarsening depth,
# not width.
func _rebuild_wave_meshes() -> void:
	var full_width: float = _field_width() + width_margin * 2.0
	var outer_depth: float = maxf(sea_depth - inner_wave_extent, 0.0)
	var shared_width_subdivisions: int = _subdivisions_for(full_width, inner_wave_spacing)

	var inner_plane := PlaneMesh.new()
	inner_plane.size = Vector2(full_width, inner_wave_extent)
	inner_plane.subdivide_width = shared_width_subdivisions
	inner_plane.subdivide_depth = _subdivisions_for(inner_wave_extent, inner_wave_spacing)
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
# RegionField.get_forward() (never assumed to be -Z), extending further
# away from the Tower from there: the inner patch spans the first
# inner_wave_extent meters of that, the outer skirt the remaining
# sea_depth - inner_wave_extent beyond it. self (the inner patch)'s own
# position is what global_position sets; _outer_skirt's position is
# local to self, so it's the world-space gap between the two centers.
func _position_relative_to_spawn() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	var field_center_x: float = region_field.global_position.x if region_field else 0.0

	var near_edge_z := _compute_near_edge_z()
	var outer_depth: float = maxf(sea_depth - inner_wave_extent, 0.0)
	var inner_center_z := near_edge_z - _forward.z * inner_wave_extent / 2.0
	var outer_center_z := near_edge_z - _forward.z * (inner_wave_extent + outer_depth / 2.0)

	global_position = Vector3(field_center_x, sea_level, inner_center_z)
	_outer_skirt.position = Vector3(0.0, 0.0, outer_center_z - inner_center_z)

	# wave_fade_factor() in the shader needs to know where "near the
	# shore" is in world space - pushed here (not _apply_all_uniforms())
	# since it depends on the Wanderer's spawn position, not available
	# until this function's first real call.
	_apply_uniform("near_edge_z", near_edge_z)
	_apply_uniform("shore_forward_z", _forward.z)

	var half_width := (_field_width() + width_margin * 2.0) / 2.0
	print("Sea: near edge z=%.2f, inner extent=%.1fm, outer extent=%.1fm, X extent=[%.2f, %.2f]" % [near_edge_z, inner_wave_extent, outer_depth, global_position.x - half_width, global_position.x + half_width])

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
	_sea_time += delta
	_apply_uniform("sea_time", _sea_time)

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
	_apply_uniform("sea_color", sea_color)
	_apply_uniform("sea_roughness", sea_roughness)
	_apply_uniform("noise_amplitude", noise_amplitude)
	_apply_uniform("noise_scale", noise_scale)
	_apply_uniform("noise_speed", noise_speed)

	_apply_uniform("long_wave_length", long_wave_length)
	_apply_uniform("long_wave_amplitude", long_wave_amplitude)
	_apply_uniform("long_wave_speed", long_wave_speed)
	_apply_uniform("long_wave_direction", _direction_from_angle(long_wave_angle_degrees))
	_apply_uniform("short_wave_length", short_wave_length)
	_apply_uniform("short_wave_amplitude", short_wave_amplitude)
	_apply_uniform("short_wave_speed", short_wave_speed)
	_apply_uniform("short_wave_direction", _direction_from_angle(short_wave_angle_degrees))

	_apply_uniform("fresnel_power", fresnel_power)

	_apply_uniform("shallow_color", shallow_color)
	_apply_uniform("deep_color", deep_color)
	_apply_uniform("shallow_depth", shallow_depth)
	_apply_uniform("deep_saturate_depth", deep_saturate_depth)

	_apply_uniform("foam_color", foam_color)
	_apply_uniform("foam_width", foam_width)
	_apply_uniform("foam_strength", foam_strength)

	_apply_uniform("inner_wave_extent", inner_wave_extent)
	_apply_uniform("wave_fade_width", wave_fade_width)

	_apply_uniform("shore_fade", shore_fade)
	_apply_uniform("edge_noise_amplitude", edge_noise_amplitude)
	_apply_uniform("edge_noise_scale", edge_noise_scale)
	_apply_uniform("fog_color", fog_color)
	_apply_uniform("fog_near_distance", fog_near_distance)
	_apply_uniform("fog_far_distance", fog_far_distance)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)
