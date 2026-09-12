extends Node
class_name FootprintSpawner

# Leaves a fading mark on the ground each time a foot bone plants - fires
# on the plant itself, not toe-off: a foot's downward velocity (in
# body-space Y, relative to the Wanderer) has to first clear
# min_descent_speed during the current swing, then drop below
# plant_epsilon (the foot has stopped coming down) while at or below
# max_plant_height. A plain "position below a height threshold" check
# fires late, at toe-off, since a planted foot stays below that height
# for its whole ground-contact phase, not just the instant it lands.
# footfall_cooldown still blocks the same foot from re-triggering for a
# short while regardless. Watches bone height/velocity only, independent
# of which clip is actually playing (Idle/Walk/Run/battle), so it works
# the same under all of them without per-clip handling.
#
# Built purely in code - instantiated via FootprintSpawner.new() and
# added as a child of the Wanderer via setup(), not part of any .tscn.
# Spawned footprint meshes are parented under Ground instead of under
# the Wanderer or this node, since they're marks on the terrain that
# must stay put in world space regardless of where the Wanderer walks
# to next.

# Emitted for every detected footfall, before the water-tier check below
# decides whether a visual mark actually spawns - so a listener like
# FootstepAudio hears every plant (footsteps still make a sound in
# standing water) even on the footfalls that leave no mark.
signal footfall(world_position: Vector3)

const LEFT_TOE_SUFFIX := "LeftToeBase"
const LEFT_FOOT_SUFFIX := "LeftFoot"
const RIGHT_TOE_SUFFIX := "RightToeBase"
const RIGHT_FOOT_SUFFIX := "RightFoot"

@export var min_descent_speed: float = 0.4
@export var plant_epsilon: float = 0.05
@export var max_plant_height: float = 0.05
@export var footfall_cooldown: float = 0.3
# Used instead of footfall_cooldown while Wanderer.is_dashing() - Run's
# own foot-plant cadence is faster than Walk's, and the plain cooldown
# above throttled footfalls (and the footstep sounds/prints they drive)
# to a walking pace even during a dash.
@export var dash_footfall_cooldown: float = 0.12

@export var footprint_size: Vector2 = Vector2(0.3, 0.12)
@export var footprint_height_offset: float = 0.01
# How much darker than Ground.ground_color a footprint's base tone is,
# via Color.darkened() - before dry/wet opacity is applied on top.
@export var footprint_darken: float = 0.15

# Three wetness tiers, all read from Ground.get_wetness_at() at the
# footprint's own spawn point - below dry_wetness_threshold is "dry",
# from there up to water_wetness_threshold is "wet" (the shore band),
# and at/above water_wetness_threshold is standing water, where no
# footprint spawns at all (there's nothing solid to leave a print in).
@export var dry_wetness_threshold: float = 0.35
@export var water_wetness_threshold: float = 0.8
@export var dry_opacity: float = 0.22
@export var wet_opacity: float = 0.5
@export var dry_lifetime: float = 4.0
@export var wet_lifetime: float = 20.0

@export var max_footprints: int = 40

var _wanderer: Wanderer
var _ground: Ground
var _skeleton: Skeleton3D

# Per-foot state, index 0 = left, 1 = right. _foot_previous_y stays at
# INF until that foot's first sample, so the very first frame never
# derives a (garbage) velocity from it. _foot_swing_exceeded_min_descent
# is the "has this swing's downward speed cleared min_descent_speed yet"
# latch - cleared the moment the foot rises back above max_plant_height
# (a fresh swing) or the moment a footfall actually fires (so reaching
# plant_epsilon again immediately after, without a fresh descent, can't
# double-fire before the cooldown alone would have blocked it anyway).
var _foot_bone_indices: Array[int] = [-1, -1]
var _foot_previous_y: Array[float] = [INF, INF]
var _foot_swing_exceeded_min_descent: Array[bool] = [false, false]
var _foot_cooldowns: Array[float] = [0.0, 0.0]

# Pool: parallel arrays, one entry per slot, rather than a Dictionary/
# custom class - simple enough at this size and keeps every slot's
# fields explicitly typed. New slots are appended (up to max_footprints)
# until the pool is full, then _next_pool_index round-robins through all
# of them in the order they were first created - since slots are always
# filled/recycled in that same fixed order, the next one in line is
# always the one used longest ago, which is exactly "oldest recycled"
# without needing to track ages to find it.
var _pool_meshes: Array[MeshInstance3D] = []
var _pool_materials: Array[StandardMaterial3D] = []
var _pool_spawn_time: Array[float] = []
var _pool_lifetime: Array[float] = []
var _pool_base_opacity: Array[float] = []
var _next_pool_index: int = 0

var _footprint_mesh: PlaneMesh
var _footprint_texture: GradientTexture2D

func setup(model: Node3D, wanderer: Wanderer, ground: Ground) -> void:
	_wanderer = wanderer
	_ground = ground
	if _ground == null:
		push_warning("FootprintSpawner: no Ground given; footprints disabled.")
		return

	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if _skeleton == null:
		push_warning("FootprintSpawner: no Skeleton3D found under model; footprints disabled.")
		return

	_foot_bone_indices[0] = _find_foot_bone(LEFT_TOE_SUFFIX, LEFT_FOOT_SUFFIX)
	_foot_bone_indices[1] = _find_foot_bone(RIGHT_TOE_SUFFIX, RIGHT_FOOT_SUFFIX)
	if _foot_bone_indices[0] == -1:
		push_warning("FootprintSpawner: no bone matching '%s' or '%s' found; left footprints disabled." % [LEFT_TOE_SUFFIX, LEFT_FOOT_SUFFIX])
	if _foot_bone_indices[1] == -1:
		push_warning("FootprintSpawner: no bone matching '%s' or '%s' found; right footprints disabled." % [RIGHT_TOE_SUFFIX, RIGHT_FOOT_SUFFIX])

	_build_footprint_mesh()

# Prefers the toe bone (closer to the actual ground-contact point) and
# falls back to the foot bone if this rig has no toe bone - same
# preference Wanderer's own _find_grounding_bones() already uses.
func _find_foot_bone(toe_suffix: String, foot_suffix: String) -> int:
	var toe_idx := _find_bone_by_suffix(toe_suffix)
	if toe_idx != -1:
		return toe_idx
	return _find_bone_by_suffix(foot_suffix)

func _find_bone_by_suffix(suffix: String) -> int:
	for bone_idx in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(bone_idx).ends_with(suffix):
			return bone_idx
	return -1

# A soft circular blob - white fading to transparent via GradientTexture2D's
# own FILL_RADIAL, no shader needed - that each spawned footprint's own
# non-uniform transform scale stretches into an ellipse. Same technique
# ContactShadow already uses; duplicated rather than shared since this is
# only the second occurrence (see CLAUDE.md: extract a helper once a
# third one exists, not before).
func _build_footprint_mesh() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	_footprint_texture = GradientTexture2D.new()
	_footprint_texture.gradient = gradient
	_footprint_texture.width = 32
	_footprint_texture.height = 32
	_footprint_texture.fill = GradientTexture2D.FILL_RADIAL
	_footprint_texture.fill_from = Vector2(0.5, 0.5)
	_footprint_texture.fill_to = Vector2(1.0, 0.5)

	_footprint_mesh = PlaneMesh.new()
	_footprint_mesh.size = Vector2.ONE

func _process(delta: float) -> void:
	if _skeleton == null or _wanderer == null or _ground == null:
		return

	for side in 2:
		_foot_cooldowns[side] = maxf(_foot_cooldowns[side] - delta, 0.0)
		var bone_idx: int = _foot_bone_indices[side]
		if bone_idx == -1:
			continue

		var bone_world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(bone_idx).origin
		var body_y: float = _wanderer.to_local(bone_world).y
		var previous_y: float = _foot_previous_y[side]
		_foot_previous_y[side] = body_y

		if is_inf(previous_y) or delta <= 0.0:
			continue # first sample for this foot - no velocity to derive yet

		# Positive while descending (Y decreasing), matching
		# min_descent_speed/plant_epsilon's own "speed of coming down" framing.
		var downward_velocity: float = (previous_y - body_y) / delta

		if body_y > max_plant_height:
			_foot_swing_exceeded_min_descent[side] = false
			continue

		if downward_velocity >= min_descent_speed:
			_foot_swing_exceeded_min_descent[side] = true

		if _foot_swing_exceeded_min_descent[side] and downward_velocity < plant_epsilon and _foot_cooldowns[side] <= 0.0:
			_foot_cooldowns[side] = dash_footfall_cooldown if _wanderer.is_dashing() else footfall_cooldown
			_foot_swing_exceeded_min_descent[side] = false
			_spawn_footprint(bone_world)

	_update_pool()

func _spawn_footprint(bone_world: Vector3) -> void:
	footfall.emit(bone_world)

	var local_xz: Vector3 = _ground.to_local(Vector3(bone_world.x, 0.0, bone_world.z))
	var wetness: float = _ground.get_wetness_at(Vector2(local_xz.x, local_xz.z))
	if wetness >= water_wetness_threshold:
		return # standing water - nothing solid to leave a mark in

	var height: float = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
	var normal: Vector3 = _sample_normal(local_xz.x, local_xz.z)
	var facing: Vector3 = -_wanderer.global_transform.basis.z

	var slot: int = _acquire_pool_slot()
	var mesh_instance: MeshInstance3D = _pool_meshes[slot]
	var material: StandardMaterial3D = _pool_materials[slot]

	mesh_instance.global_transform = _footprint_transform(bone_world, height, normal, facing)
	mesh_instance.visible = true

	var is_wet: bool = wetness >= dry_wetness_threshold
	var base_opacity: float = wet_opacity if is_wet else dry_opacity
	var lifetime: float = wet_lifetime if is_wet else dry_lifetime

	var albedo: Color = _ground.ground_color.darkened(footprint_darken)
	albedo.a = base_opacity
	material.albedo_color = albedo

	_pool_spawn_time[slot] = Time.get_ticks_msec() / 1000.0
	_pool_lifetime[slot] = lifetime
	_pool_base_opacity[slot] = base_opacity

# Finite-difference estimate of the terrain normal at (local_x, local_z) -
# same central-difference-gradient formula the relief mesh's own normals
# used before the SurfaceTool rewrite, just evaluated here directly
# against get_height_at() since a footprint decal has no mesh triangles
# of its own to derive a normal from.
func _sample_normal(local_x: float, local_z: float) -> Vector3:
	var eps := 0.1
	var h_x0: float = _ground.get_height_at(Vector2(local_x - eps, local_z))
	var h_x1: float = _ground.get_height_at(Vector2(local_x + eps, local_z))
	var h_z0: float = _ground.get_height_at(Vector2(local_x, local_z - eps))
	var h_z1: float = _ground.get_height_at(Vector2(local_x, local_z + eps))
	var slope_x: float = (h_x1 - h_x0) / (2.0 * eps)
	var slope_z: float = (h_z1 - h_z0) / (2.0 * eps)
	return Vector3(-slope_x, 1.0, -slope_z).normalized()

# Builds an orthonormal basis with local +Y along the terrain normal
# (tilts the decal flush with the slope) and local +X along the
# Wanderer's own facing, projected flat onto the normal's tangent plane
# (aligns the decal's long axis with facing) - then scales those local
# axes by footprint_size so the plane (a unit square) becomes the
# actual ellipse footprint (length along facing, width across it).
func _footprint_transform(bone_world: Vector3, height: float, normal: Vector3, facing: Vector3) -> Transform3D:
	var up: Vector3 = normal
	var forward: Vector3 = facing - facing.dot(up) * up
	if forward.length() < 0.0001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()
	var right: Vector3 = forward.cross(up).normalized()

	var basis := Basis(forward, up, right).scaled(Vector3(footprint_size.x, 1.0, footprint_size.y))
	var origin := Vector3(bone_world.x, height + footprint_height_offset, bone_world.z)
	return Transform3D(basis, origin)

func _acquire_pool_slot() -> int:
	if _pool_meshes.size() < max_footprints:
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _footprint_mesh
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_texture = _footprint_texture
		material.disable_receive_shadows = true
		mesh_instance.material_override = material
		mesh_instance.visible = false
		_ground.add_child(mesh_instance)

		_pool_meshes.append(mesh_instance)
		_pool_materials.append(material)
		_pool_spawn_time.append(0.0)
		_pool_lifetime.append(1.0)
		_pool_base_opacity.append(0.0)
		return _pool_meshes.size() - 1

	var slot: int = _next_pool_index
	_next_pool_index = (_next_pool_index + 1) % max_footprints
	return slot

# Linear fade from each slot's own base_opacity to 0 over its own
# lifetime (dry_lifetime or wet_lifetime, fixed at spawn time), hiding
# the mesh once fully faded rather than leaving a zero-alpha quad
# rendering forever.
func _update_pool() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	for slot in _pool_meshes.size():
		var mesh_instance: MeshInstance3D = _pool_meshes[slot]
		if not mesh_instance.visible:
			continue

		var elapsed: float = now - _pool_spawn_time[slot]
		var lifetime: float = _pool_lifetime[slot]
		if elapsed >= lifetime:
			mesh_instance.visible = false
			continue

		var fade_t: float = 1.0 - (elapsed / lifetime)
		var material: StandardMaterial3D = _pool_materials[slot]
		var albedo: Color = material.albedo_color
		albedo.a = _pool_base_opacity[slot] * fade_t
		material.albedo_color = albedo
