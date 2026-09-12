extends SkeletonModifier3D
class_name LegSpreadCorrectionModifier

# Corrects the A-pose leg spread baked into the Mixamo rig's own rest
# pose: rotates the upper-leg bones inward about their own local Z by
# correction_degrees (opposite signs per side) every time the skeleton
# updates. A SkeletonModifier3D runs after the AnimationPlayer/Tree has
# already written that frame's pose, so this stacks on top of whatever
# clip is currently playing (Idle, Walk, BattleIdle, DrawSword) instead
# of needing separate handling per clip.
#
# Bone names may be sanitized on import (Mixamo's own "mixamorig:LeftUpLeg"
# shows up here as "mixamorig_LeftUpLeg", but that exact prefix isn't
# guaranteed for every rig) - found by suffix match, not exact name, and
# push_warning's once per side if a match isn't found rather than
# silently doing nothing.
#
# Sign convention (left = +correction, right = -correction) is a best
# guess at Mixamo's own local Z convention for these bones, not verified
# live - if the fix visibly spreads the legs further apart instead of
# narrowing them, flip the sign on both _process_modification() calls
# below.

@export var correction_degrees: float = 6.0

const LEFT_BONE_SUFFIX := "LeftUpLeg"
const RIGHT_BONE_SUFFIX := "RightUpLeg"

var _skeleton: Skeleton3D
var _left_bone_idx: int = -1
var _right_bone_idx: int = -1

func _ready() -> void:
	_skeleton = get_skeleton()
	if _skeleton == null:
		push_warning("LegSpreadCorrectionModifier: no parent Skeleton3D found; leg spread correction disabled.")
		return

	_left_bone_idx = _find_bone_by_suffix(LEFT_BONE_SUFFIX)
	_right_bone_idx = _find_bone_by_suffix(RIGHT_BONE_SUFFIX)
	if _left_bone_idx == -1:
		push_warning("LegSpreadCorrectionModifier: no bone name ending in '%s' found; left leg spread correction disabled." % LEFT_BONE_SUFFIX)
	if _right_bone_idx == -1:
		push_warning("LegSpreadCorrectionModifier: no bone name ending in '%s' found; right leg spread correction disabled." % RIGHT_BONE_SUFFIX)

func _find_bone_by_suffix(suffix: String) -> int:
	for bone_idx in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(bone_idx).ends_with(suffix):
			return bone_idx
	return -1

func _process_modification() -> void:
	if _skeleton == null:
		return
	var angle: float = deg_to_rad(correction_degrees)
	if _left_bone_idx != -1:
		_rotate_local_z(_left_bone_idx, angle)
	if _right_bone_idx != -1:
		_rotate_local_z(_right_bone_idx, -angle)

# Post-multiplies the bone's own already-animated pose rotation with the
# correction, so the correction is expressed in the bone's own local
# frame (its own rig-defined Z axis) and adds inward rotation on top of
# whatever the current clip already set, rather than replacing it.
func _rotate_local_z(bone_idx: int, angle: float) -> void:
	var current_rotation: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
	var correction := Quaternion(Vector3(0.0, 0.0, 1.0), angle)
	_skeleton.set_bone_pose_rotation(bone_idx, current_rotation * correction)
