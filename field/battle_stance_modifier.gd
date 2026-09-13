extends SkeletonModifier3D
class_name BattleStanceModifier

# Widens the battle-ready stance while BattleIdle is the current clip: the
# back leg's UpLeg rotates backward and the front leg's forward (both
# about local X, a sagittal-plane swing), plus a small Hips yaw so the
# pelvis opens toward the enemy - a fencer's ready stance rather than
# BattleIdle's own square-on pose. Gated on current_animation rather than
# always-on: DrawSword/Slash/Brace each have their own leg motion this
# shouldn't fight (see Wanderer._on_card_played()/_resting_battle_
# animation() for how current_animation moves between those and BattleIdle
# mid-fight).
#
# Blending is SkeletonModifier3D's own built-in influence (0..1), not a
# hand-rolled weight - Wanderer tweens that directly (0->1 over enter_
# battle_stance()'s own duration, 1->0 over exit_battle_stance()'s
# animation_blend_time), so _process_modification() below always applies
# the full rotation and lets the engine blend it against the unmodified
# pose. Starts at 0 (set by Wanderer right after creating this) so it's
# inert on the field, not just in battle.
#
# Sign conventions (back leg +X = backward, front leg -X = forward, pelvis
# yaw direction) are best guesses at Mixamo's own local-axis conventions,
# same as LegSpreadCorrectionModifier's own doc - this project's "never
# run the game" rule means none of them are verified live. Flip the
# relevant sign below if a direction reads backward once actually seen.

const LEFT_UPLEG_SUFFIX := "LeftUpLeg"
const RIGHT_UPLEG_SUFFIX := "RightUpLeg"
const HIPS_SUFFIX := "Hips"
const BATTLE_IDLE_ANIMATION := "BattleIdle"

@export var battle_back_leg_degrees: float = 12.0
@export var battle_front_leg_degrees: float = 4.0
@export var battle_pelvis_yaw_degrees: float = 6.0
# Default true: he squares up with the sword in his right hand (see
# Wanderer.hand_mount_bone_suffix), so the left leg trails as the back leg.
@export var back_leg_is_left: bool = true

# Set imperatively by Wanderer right after instancing this (see its own
# _setup_battle_stance_modifier()) - not a NodePath export, since this
# node lives under the model's Skeleton3D, several hops from the
# AnimationPlayer it needs to read current_animation from.
var animation_player: AnimationPlayer = null

var _skeleton: Skeleton3D
var _left_upleg_idx: int = -1
var _right_upleg_idx: int = -1
var _hips_idx: int = -1

func _ready() -> void:
	_skeleton = get_skeleton()
	if _skeleton == null:
		push_warning("BattleStanceModifier: no parent Skeleton3D found; battle stance widening disabled.")
		return

	_left_upleg_idx = _find_bone_by_suffix(LEFT_UPLEG_SUFFIX)
	_right_upleg_idx = _find_bone_by_suffix(RIGHT_UPLEG_SUFFIX)
	_hips_idx = _find_bone_by_suffix(HIPS_SUFFIX)
	if _left_upleg_idx == -1:
		push_warning("BattleStanceModifier: no bone name ending in '%s' found; left leg widening disabled." % LEFT_UPLEG_SUFFIX)
	if _right_upleg_idx == -1:
		push_warning("BattleStanceModifier: no bone name ending in '%s' found; right leg widening disabled." % RIGHT_UPLEG_SUFFIX)
	if _hips_idx == -1:
		push_warning("BattleStanceModifier: no bone name ending in '%s' found; pelvis yaw disabled." % HIPS_SUFFIX)

func _find_bone_by_suffix(suffix: String) -> int:
	for bone_idx in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(bone_idx).ends_with(suffix):
			return bone_idx
	return -1

func _process_modification() -> void:
	if _skeleton == null or animation_player == null:
		return
	if animation_player.current_animation != BATTLE_IDLE_ANIMATION:
		return

	var back_bone_idx: int = _left_upleg_idx if back_leg_is_left else _right_upleg_idx
	var front_bone_idx: int = _right_upleg_idx if back_leg_is_left else _left_upleg_idx

	if back_bone_idx != -1:
		_rotate_local_x(back_bone_idx, deg_to_rad(battle_back_leg_degrees))
	if front_bone_idx != -1:
		_rotate_local_x(front_bone_idx, -deg_to_rad(battle_front_leg_degrees))

	if _hips_idx != -1:
		var yaw_sign := 1.0 if back_leg_is_left else -1.0
		_rotate_local_y(_hips_idx, yaw_sign * deg_to_rad(battle_pelvis_yaw_degrees))

# Same "post-multiply the already-animated pose" approach LegSpreadCorrection
# Modifier's own _rotate_local_z() uses, just about local X (a leg's
# forward/backward swing) instead of Z (its inward/outward spread).
func _rotate_local_x(bone_idx: int, angle: float) -> void:
	var current_rotation: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
	var correction := Quaternion(Vector3(1.0, 0.0, 0.0), angle)
	_skeleton.set_bone_pose_rotation(bone_idx, current_rotation * correction)

func _rotate_local_y(bone_idx: int, angle: float) -> void:
	var current_rotation: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
	var correction := Quaternion(Vector3(0.0, 1.0, 0.0), angle)
	_skeleton.set_bone_pose_rotation(bone_idx, current_rotation * correction)
