extends Node3D
class_name CameraRig

@export var target_path: NodePath = ^"../Wanderer"
@export var distance: float = 9.0
@export var pitch_degrees: float = 18.0
@export var look_offset: Vector3 = Vector3(0.0, 1.0, 0.0)
@export var framing_bias: float = 0.3
@export var follow_smoothing: float = 6.0
@export var max_follow_speed: float = 10.0
@export var fov: float = 40.0:
	set(value):
		fov = value
		if is_instance_valid(camera):
			camera.fov = fov

# Battle framing: side-on, perpendicular to the Wanderer->enemy line, on
# whichever side keeps the Wanderer screen-left. Distance and look target
# are fitted to the combatants every frame (see _fit_battle_frame());
# pitch/fov are fixed. Blended in/out of the follow framing above over
# battle_transition_time, both ways.
@export var battle_pitch: float = 12.0
@export var battle_fov: float = 35.0
@export var battle_transition_time: float = 0.6

@export_group("Follow bounds")
# How far inland the follow framing will go: the look target is held
# at a plane perpendicular to the field's forward (see set_inland_limit()
# - RegionField hands over the plane's point and get_forward(), so no
# axis is assumed) while the Wanderer walks on past it and rises in the
# frame. camera_inland_limit_z mirrors that point's z for Remote-tab
# tuning; on the ±Z forward every floor has today it IS the limit line.
# The battle fit is untouched - _place_camera() blends the bounded follow
# target against the fitted battle target, so the bound fades out with
# the follow framing itself.
@export var inland_limit_enabled: bool = true
@export var camera_inland_limit_z: float = 0.0:
	set(value):
		camera_inland_limit_z = value
		_inland_limit_point.z = value
# Optional sideways bound, off by default: the look target stays within
# camera_side_limit_x either side of the forward line through the inland
# limit point.
@export var side_limit_enabled: bool = false
@export var camera_side_limit_x: float = 0.0
# The bound is applied as an eased offset, not a snap: the pull-back
# from the Wanderer's real position settles (~95%) in this many seconds,
# both into the limit and back out of it - once he's inside the bounds
# again the offset decays to nothing and the follow is exact.
@export var limit_ease_time: float = 0.3

@export_group("Battle fit")
# Horizontal room past the outermost bodies' bbox edges, metres at the
# combatants' depth, averaged over both sides: the two sides split
# 2 * battle_margin so the enemy side gets battle_enemy_room_ratio times
# the Wanderer's (3.0 / 1.1 -> 2.86 m Wanderer-side, 3.14 m enemy-side).
@export var battle_margin: float = 3.0
@export var battle_enemy_room_ratio: float = 1.1
# The fitted distance never comes closer than min (1.18x the old fixed
# 9 m frame - one crab at spacing 4 fits at ~9.5 m, so min is what a
# single-crab fight actually gets) nor further than max, however wide the
# cluster spreads.
@export var battle_distance_min: float = 10.62
@export var battle_distance_max: float = 22.0
# Vertical placement, all as fractions of viewport height: the lowest
# combatant's HP readout - hanging readout_allowance under its feet
# (HPBar/EnemyStatus's bar_offset, ~0.45 m, is what this stands in for)
# - sits hand_clearance above the card hand's resting top edge (passed in
# by RegionField from the real overlay layout, see enter_battle()), so
# the feet themselves land hand_clearance + readout_allowance above it;
# and the tallest head stays head_clearance below the top of the frame -
# room for the intent display above it. The head limit pushes the
# distance out only for bodies taller than ~3 m; below that the
# horizontal fit or battle_distance_min governs.
@export var hand_clearance: float = 0.12
@export var readout_allowance: float = 0.085
@export var head_clearance: float = 0.10

@export_group("Threshold look")
# The "look up" at a floor's threshold (see look_up()): the follow frame
# tilts from pitch_degrees down to this over the seconds RegionField
# passes, the camera staying on its distance-orbit round the Wanderer,
# the view swinging to the tower and the look-at point going to the
# tower's base - so the tower is seen at every threshold, low in the
# frame with the Wanderer's back in the foreground.
@export var look_up_pitch_degrees: float = 15.0

@export_group("Battle DOF")
# Far blur only (near stays off - see _update_dof()) - reads as "the
# background falls away" behind the fight without ever blurring either
# combatant. far_distance is the fitted battle distance + this, not the
# live blended eff_distance _place_camera() computes - a fixed depth
# relationship to the battle camera's own resting distance, so it doesn't
# shift as the transition blends in.
@export var battle_dof_far_extra_distance: float = 8.0
@export var battle_dof_far_transition: float = 12.0
@export var battle_dof_amount: float = 0.06

var _target: Node3D

# The follow bound's plane: a point on it and the field forward as its
# normal (see set_inland_limit()). Zero forward = no bound, until
# RegionField sets one.
var _inland_limit_point: Vector3 = Vector3.ZERO
var _inland_forward: Vector3 = Vector3.ZERO
# The eased pull-back from the Wanderer's real position that the bounds
# currently apply - see _advance_follow_bounds().
var _bound_offset: Vector3 = Vector3.ZERO

# Set by micro_shake(), consumed and counted down by _apply_shake() -
# see that method's own doc.
var _shake_offset: Vector3 = Vector3.ZERO
var _shake_frames_remaining: int = 0

# The threshold look (see look_up()): 0 = none, 1 = fully on the tower.
# Only ever rises - the floor change that follows is a scene reload, and
# a fresh rig starts at 0.
var _look_up_blend: float = 0.0
var _look_up_elapsed: float = 0.0
var _look_up_seconds: float = 0.0
var _look_up_target: Vector3 = Vector3.ZERO
var _look_up_active: bool = false

# The free pose (see set_free_pose()): a camera transform that is NOT an
# orbit of anything, blended over whatever _place_camera() has just set.
# _free_blend 1 = the free pose outright, 0 = the placed pose untouched;
# the owner (ZoneIntro) drives the blend, this rig only applies it.
var _free_pose_active: bool = false
var _free_blend: float = 0.0
var _free_position: Vector3 = Vector3.ZERO
var _free_yaw: float = 0.0
var _free_pitch: float = 0.0
var _free_fov: float = 40.0

var _battle_wanderer: Wanderer
var _battle_enemies: Array[FieldEnemy] = []
# Where the card hand's resting top edge sits, as a fraction of viewport
# height from the top (0.79 at 1080p today) - measured by RegionField
# from the live BattleOverlay and handed to enter_battle().
var _hand_top_fraction: float = 1.0
# Last valid fitted frame, kept for the exit transition in case the
# Wanderer or an enemy (e.g. a defeated one) is freed while blending back
# out - and reused by _update_dof() as the resting battle distance.
var _battle_last_target: Vector3
var _battle_last_forward: Vector3 = Vector3.FORWARD
var _battle_last_distance: float = 0.0

# One measured combatant, in world units: its ground position, feet and
# head heights, and how far its bbox reaches sideways.
class BattleBody:
	var position: Vector3
	var feet_y: float
	var head_y: float
	var half_width: float

# 0 = pure follow framing, 1 = pure battle framing. Animated by
# _advance_battle_blend() from _blend_from to _blend_to over
# battle_transition_time, eased rather than linear.
var _battle_blend: float = 0.0
var _blend_from: float = 0.0
var _blend_to: float = 0.0
var _blend_elapsed: float = 0.0

@onready var camera: Camera3D = $Camera3D

# Camera3D itself has no dof_blur_* properties in Godot 4 - those live on
# a CameraAttributes resource assigned to Camera3D.attributes instead (see
# _update_dof()). Practical, not Physical - no exposure/lens simulation
# needed here, just the far-blur knobs battle_dof_* below already name.
var _camera_attributes: CameraAttributesPractical

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node3D
	camera.fov = fov
	_camera_attributes = CameraAttributesPractical.new()
	camera.attributes = _camera_attributes
	if _target:
		global_position = _target.global_position
		_place_camera()

# Called by region_field.gd on enemy contact, once the BattleOverlay is in
# the tree so the hand's resting top edge can be measured from its real
# layout (hand_top_fraction, viewport-height fraction from the top).
# enemies is the whole cluster the fight holds; the first one defines the
# framing axis with the Wanderer.
func enter_battle(wanderer: Wanderer, enemies: Array[FieldEnemy], hand_top_fraction: float) -> void:
	_battle_wanderer = wanderer
	_battle_enemies = enemies
	_hand_top_fraction = hand_top_fraction
	_start_blend(1.0)

# Called by region_field.gd once the battle stub resolves. Follow mode
# resumes as the blend eases back to 0.
func exit_battle() -> void:
	_start_blend(0.0)

# Called by RegionField when the Wanderer reaches a floor's far end, before
# the fade: over `seconds` the frame lifts toward `target` (the tower's
# base) - see look_up_pitch_degrees' own doc for the shape. Runs through
# the field's transition freeze because this node is PROCESS_MODE_ALWAYS.
func look_up(target: Vector3, seconds: float) -> void:
	_look_up_target = target
	_look_up_seconds = seconds
	_look_up_elapsed = 0.0
	_look_up_active = true

func _advance_look_up(delta: float) -> void:
	if not _look_up_active:
		return
	_look_up_elapsed = minf(_look_up_elapsed + delta, _look_up_seconds)
	var t := 1.0 if _look_up_seconds <= 0.0 else _look_up_elapsed / _look_up_seconds
	_look_up_blend = smoothstep(0.0, 1.0, t)

# The zone intro's opening shot (see ZoneIntro): a camera placed freely -
# `yaw` and `pitch` are Node3D rotation.y / rotation.x in radians, zero
# roll - and held at full weight (blend 1) until set_free_blend() says
# otherwise. Re-callable while held, so the owner's pose exports can
# re-apply live. Also snaps the pivot onto the target, so the follow pose
# under it starts converged rather than easing in from wherever the rig
# stood. Applied at once, not next physics tick: the first frame after
# this is already the free pose.
func set_free_pose(position: Vector3, yaw: float, pitch: float, fov_value: float) -> void:
	_free_position = position
	_free_yaw = yaw
	_free_pitch = pitch
	_free_fov = fov_value
	if not _free_pose_active:
		_free_pose_active = true
		_free_blend = 1.0
	if _target != null:
		global_position = _target.global_position
		_place_camera()
	_apply_free_pose()

# The blend weight, 1 = free pose, 0 = the follow pose _place_camera()
# computes that same frame - which is what makes the landing exact: the
# end values are never stored, always the live ones. Reaching 0 clears
# the free pose entirely.
func set_free_blend(blend: float) -> void:
	if not _free_pose_active:
		return
	_free_blend = clampf(blend, 0.0, 1.0)
	if _free_blend <= 0.0:
		clear_free_pose()

func clear_free_pose() -> void:
	_free_pose_active = false
	_free_blend = 0.0

func has_free_pose() -> bool:
	return _free_pose_active

# Over the pose _place_camera() has just set: position, yaw, pitch and
# fov each lerped (yaw through lerp_angle) by _free_blend, and the basis
# rebuilt from yaw + pitch alone - so the horizon stays level through the
# whole move, whatever the two ends are. The follow pose's yaw/pitch are
# read back off the camera's own basis (look_at() leaves zero roll), so
# nothing here duplicates _place_camera()'s geometry.
func _apply_free_pose() -> void:
	if not _free_pose_active:
		return
	var follow_forward: Vector3 = -camera.global_transform.basis.z
	var follow_yaw: float = atan2(-follow_forward.x, -follow_forward.z)
	var follow_pitch: float = asin(clampf(follow_forward.y, -1.0, 1.0))
	var blended_position: Vector3 = camera.global_position.lerp(_free_position, _free_blend)
	var blended_yaw: float = lerp_angle(follow_yaw, _free_yaw, _free_blend)
	var blended_pitch: float = lerpf(follow_pitch, _free_pitch, _free_blend)
	camera.global_transform = Transform3D(Basis.from_euler(Vector3(blended_pitch, blended_yaw, 0.0)), blended_position)
	camera.fov = lerpf(camera.fov, _free_fov, _free_blend)

# Called by RegionField once the ExitGate is placed (and again on any
# live edit of its own limit exports): the bound is the plane through
# `point` with `forward` (get_forward()) as its normal - "inland" is
# whichever side forward points to, never an assumed axis.
func set_inland_limit(point: Vector3, forward: Vector3) -> void:
	_inland_limit_point = point
	camera_inland_limit_z = point.z
	_inland_forward = Vector3(forward.x, 0.0, forward.z).normalized() if forward.length() > 0.0001 else Vector3.ZERO

# Where the bounds would hold `raw` (the Wanderer's position): pulled
# back along forward to the inland plane, and sideways to within
# camera_side_limit_x of the forward line, each only when enabled.
func _bounded_position(raw: Vector3) -> Vector3:
	if _inland_forward == Vector3.ZERO:
		return raw
	var bounded := raw
	var rel := raw - _inland_limit_point
	if inland_limit_enabled:
		var over: float = rel.dot(_inland_forward)
		if over > 0.0:
			bounded -= _inland_forward * over
	if side_limit_enabled:
		var right := _inland_forward.cross(Vector3.UP).normalized()
		var side: float = rel.dot(right)
		var excess: float = absf(side) - camera_side_limit_x
		if excess > 0.0:
			bounded -= right * signf(side) * excess
	return bounded

# Eases _bound_offset toward whatever pull-back the bounds want this
# frame - exponential, ~95% settled in limit_ease_time. Only the offset
# is eased, never the follow itself, so inside the bounds (offset -> 0)
# the frame tracks the Wanderer exactly as before.
func _advance_follow_bounds(delta: float) -> void:
	var wanted: Vector3 = _bounded_position(_target.global_position) - _target.global_position
	if limit_ease_time <= 0.0:
		_bound_offset = wanted
		return
	_bound_offset = _bound_offset.lerp(wanted, 1.0 - exp(-3.0 * delta / limit_ease_time))

func _start_blend(target: float) -> void:
	_blend_from = _battle_blend
	_blend_to = target
	_blend_elapsed = 0.0

func _advance_battle_blend(delta: float) -> void:
	_blend_elapsed = minf(_blend_elapsed + delta, battle_transition_time)
	var t := 1.0 if battle_transition_time <= 0.0 else _blend_elapsed / battle_transition_time
	_battle_blend = lerpf(_blend_from, _blend_to, smoothstep(0.0, 1.0, t))

func _physics_process(delta: float) -> void:
	if _target == null:
		return

	_advance_battle_blend(delta)
	_advance_follow_bounds(delta)
	_advance_look_up(delta)

	var smoothed: Vector3 = global_position.lerp(_target.global_position, 1.0 - exp(-follow_smoothing * delta))
	var motion := smoothed - global_position

	# Below max_follow_speed this is identical to the plain lerp. Above it
	# (a dash burst) the step is clamped so the target visibly leads the
	# frame instead of the camera snapping to keep up.
	var max_step := max_follow_speed * delta
	if motion.length() > max_step:
		motion = motion.normalized() * max_step

	global_position += motion

	_place_camera()
	_apply_free_pose()
	_update_dof()
	_apply_shake()

# Called by BattleFeedback on any damage_dealt (see its own doc) - magnitude
# is BattleFeedback's own max_offset already scaled by that hit's damage,
# not a tunable of this rig's. Held for exactly 2 physics frames: since
# _place_camera() fully recomputes camera.global_position from scratch
# every frame (never incrementally), re-adding this same offset on top of
# that fresh base for 2 frames reads as a brief snap rather than a
# compounding drift, and the 3rd frame's own _place_camera() call (with
# _shake_frames_remaining already at 0) renders with no offset at all.
func micro_shake(magnitude: float) -> void:
	if magnitude <= 0.0:
		return
	var shake_direction := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	shake_direction = shake_direction.normalized() if shake_direction.length() > 0.0001 else Vector2.RIGHT
	_shake_offset = Vector3(shake_direction.x, shake_direction.y, 0.0) * magnitude
	_shake_frames_remaining = 2

func _apply_shake() -> void:
	if _shake_frames_remaining <= 0:
		return
	camera.position += _shake_offset
	_shake_frames_remaining -= 1

# The rig never rotates, so this is a fixed world direction — the follow
# framing's viewing axis.
func _rig_ground_forward() -> Vector3:
	var forward := -global_transform.basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()

# Perpendicular to the a->b line, on the side that puts a screen-left:
# right = ground_forward x UP, and UP x axis is exactly the ground_forward
# choice that makes (a - midpoint), which points opposite axis, fall on
# the negative (left) side of that right vector.
func _battle_ground_forward(a_pos: Vector3, b_pos: Vector3) -> Vector3:
	var axis := Vector3(b_pos.x - a_pos.x, 0.0, b_pos.z - a_pos.z)
	if axis.length() < 0.0001:
		return _rig_ground_forward()
	return Vector3.UP.cross(axis).normalized()

# Every combatant still alive, measured: feet at body-local
# model_ground_offset (the same "feet at body floor" convention both
# bodies ground their models by), head = feet + scaled bbox height.
func _battle_bodies() -> Array[BattleBody]:
	var bodies: Array[BattleBody] = []
	if is_instance_valid(_battle_wanderer):
		var body := BattleBody.new()
		body.position = _battle_wanderer.global_position
		body.feet_y = body.position.y + _battle_wanderer.model_ground_offset
		body.head_y = body.feet_y + _battle_wanderer.get_head_height()
		body.half_width = _battle_wanderer.get_half_width()
		bodies.append(body)
	for enemy in _battle_enemies:
		if not is_instance_valid(enemy):
			continue
		var body := BattleBody.new()
		body.position = enemy.global_position
		body.feet_y = body.position.y + enemy.model_ground_offset
		body.head_y = body.feet_y + enemy.get_head_height()
		body.half_width = enemy.get_half_width()
		bodies.append(body)
	return bodies

# Metres of world height per metre of camera distance that land on
# normalised screen row y (half-heights from centre, +up) for a point on
# the combatants' line, with the camera pitched down by pitch_rad and
# looking straight at that line: y = h cos(p) / ((d - h sin(p)) t)
# solved for h/d, t = tan(fov/2). Exact for points at the look target's
# depth, which is where every body on the framing axis sits.
func _height_per_distance(y: float, pitch_rad: float, tan_half_fov: float) -> float:
	return y * tan_half_fov / (cos(pitch_rad) + y * tan_half_fov * sin(pitch_rad))

# Fits distance and look target to the live combatants. Horizontal: the
# bodies' bbox extents projected onto the Wanderer->first-enemy axis (=
# screen right, since the camera sits perpendicular to it), plus the
# split battle_margin room, must span the frame width at that depth.
# Vertical: with the camera looking exactly at the returned target, the
# lowest feet land hand_clearance + readout_allowance above the hand's
# top edge (the readout under them is what clears the hand); if the
# tallest head would then break head_clearance, the distance grows until
# it doesn't. Whichever of the two (or battle_distance_min) is largest
# wins, capped at battle_distance_max. Returns false and leaves the last
# frame in place when nothing is left to frame.
func _fit_battle_frame() -> bool:
	if not is_instance_valid(_battle_wanderer):
		return false
	var bodies := _battle_bodies()
	if bodies.size() < 2:
		return false

	var wanderer_pos: Vector3 = bodies[0].position
	var first_enemy_pos: Vector3 = bodies[1].position
	var forward := _battle_ground_forward(wanderer_pos, first_enemy_pos)
	# (UP x axis) x UP is the axis itself flattened - screen right, from
	# the Wanderer toward the enemies.
	var right := forward.cross(Vector3.UP).normalized()

	var lo: float = INF
	var hi: float = -INF
	var feet_min: float = INF
	var head_max: float = -INF
	for body in bodies:
		var s: float = (body.position - wanderer_pos).dot(right)
		lo = minf(lo, s - body.half_width)
		hi = maxf(hi, s + body.half_width)
		feet_min = minf(feet_min, body.feet_y)
		head_max = maxf(head_max, body.head_y)

	var room_wanderer: float = 2.0 * battle_margin / (1.0 + battle_enemy_room_ratio)
	var room_enemy: float = room_wanderer * battle_enemy_room_ratio
	var left_edge: float = lo - room_wanderer
	var right_edge: float = hi + room_enemy

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var aspect: float = viewport_size.x / maxf(viewport_size.y, 1.0)
	var tan_half_fov := tan(deg_to_rad(battle_fov) * 0.5)
	var pitch_rad := deg_to_rad(battle_pitch)

	var distance_horizontal: float = (right_edge - left_edge) * 0.5 / (tan_half_fov * aspect)

	# Screen rows, half-heights from centre, +up: the hand's top edge
	# lifted by the clearance plus the readout hanging under the feet, and
	# the top edge dropped by its own clearance.
	var feet_row: float = (0.5 - _hand_top_fraction + hand_clearance + readout_allowance) * 2.0
	var head_row: float = 1.0 - head_clearance * 2.0
	var feet_k := _height_per_distance(feet_row, pitch_rad, tan_half_fov)
	var head_k := _height_per_distance(head_row, pitch_rad, tan_half_fov)
	var distance_vertical: float = 0.0
	if head_k - feet_k > 0.0001:
		distance_vertical = (head_max - feet_min) / (head_k - feet_k)

	var fitted_distance: float = clampf(maxf(distance_horizontal, distance_vertical), battle_distance_min, battle_distance_max)

	var target := wanderer_pos + right * ((left_edge + right_edge) * 0.5)
	target.y = feet_min - feet_k * fitted_distance

	_battle_last_target = target
	_battle_last_forward = forward
	_battle_last_distance = fitted_distance
	return true

func _place_camera() -> void:
	# The Wanderer's position held back by the follow bounds (see
	# _advance_follow_bounds()) - the battle target below never is.
	var follow_target := _target.global_position + _bound_offset + look_offset
	var follow_forward := _rig_ground_forward()

	# Refit every frame while the fight holds bodies - the Wanderer is still
	# walking into its stance during the swing in - else the last frame.
	_fit_battle_frame()
	var battle_target := _battle_last_target
	var battle_forward := _battle_last_forward

	var look_target: Vector3 = follow_target.lerp(battle_target, _battle_blend)
	var ground_forward: Vector3 = follow_forward.lerp(battle_forward, _battle_blend)
	ground_forward = follow_forward if ground_forward.length() < 0.0001 else ground_forward.normalized()

	var eff_pitch: float = lerpf(pitch_degrees, battle_pitch, _battle_blend)
	var eff_distance: float = lerpf(distance, _battle_last_distance, _battle_blend)
	var eff_fov: float = lerpf(fov, battle_fov, _battle_blend)
	# The battle frame's vertical placement is baked into its look target
	# (see _fit_battle_frame()), so the follow bias fades to none.
	var eff_framing_bias: float = lerpf(framing_bias, 0.0, _battle_blend)
	# The threshold look, over whichever of the two framings above is
	# current: the viewing axis swings toward the target, the pitch drops
	# to look_up_pitch_degrees, and (below) the aim goes to the target
	# itself. The orbit centre stays the look target, so the camera stays
	# with the Wanderer and only its eyes lift.
	if _look_up_blend > 0.0:
		var to_target := Vector3(_look_up_target.x - look_target.x, 0.0, _look_up_target.z - look_target.z)
		if to_target.length() > 0.0001:
			var swung: Vector3 = ground_forward.lerp(to_target.normalized(), _look_up_blend)
			ground_forward = ground_forward if swung.length() < 0.0001 else swung.normalized()
		eff_pitch = lerpf(eff_pitch, look_up_pitch_degrees, _look_up_blend)
	var pitch_rad := deg_to_rad(eff_pitch)

	# Sphere of radius `eff_distance` around the look target: pitch swings
	# the camera between ground level (0) and directly overhead (90).
	camera.global_position = look_target - ground_forward * eff_distance * cos(pitch_rad) + Vector3.UP * eff_distance * sin(pitch_rad)
	camera.fov = eff_fov

	# Push the look-at point past the subject along the ground so the
	# camera aims a bit above them instead of dead-on, leaving them
	# eff_framing_bias of the frame height below screen center.
	var frame_half_height := eff_distance * tan(deg_to_rad(eff_fov) * 0.5)
	var biased_target := look_target + ground_forward * frame_half_height * eff_framing_bias
	if _look_up_blend > 0.0:
		biased_target = biased_target.lerp(_look_up_target, _look_up_blend)

	camera.look_at(biased_target)

# dof_active covers both directions of the transition: _blend_to > 0 makes
# it true the instant enter_battle() sets a battle target, even before
# _battle_blend itself has risen off 0 (so the very first tick's rise is
# already visible); _battle_blend > 0 keeps it true through the whole
# exit fade-out even once _blend_to has already dropped back to 0, so DOF
# doesn't cut off abruptly mid-fade - only once _battle_blend actually
# reaches 0 does this go false again. Drives _camera_attributes (see its
# own doc), not Camera3D directly - it has no dof_blur_* properties of
# its own in Godot 4.
func _update_dof() -> void:
	var dof_active: bool = _battle_blend > 0.0 or _blend_to > 0.0
	_camera_attributes.dof_blur_near_enabled = false
	_camera_attributes.dof_blur_far_enabled = dof_active
	if dof_active:
		_camera_attributes.dof_blur_far_distance = _battle_last_distance + battle_dof_far_extra_distance
		_camera_attributes.dof_blur_far_transition = battle_dof_far_transition
		_camera_attributes.dof_blur_amount = battle_dof_amount * _battle_blend
