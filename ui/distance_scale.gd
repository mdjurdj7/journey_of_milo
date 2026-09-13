extends RefCounted
class_name DistanceScale

# Maps a camera-to-target distance to a Control's own `scale`, so a
# floating, fixed-pixel-size UI element (HPBar, EnemyStatus) reads as
# proportionally sized whether the camera is close (battle) or far away
# (field) - unproject_position() alone only tracks the anchor's screen
# POSITION, never its apparent size, so without this the exact same
# Control would look oversized up close and undersized far away.
#
# near_distance/far_distance are the two reference distances the min/max
# scale are measured at - not validated against each other beyond the
# degenerate-range guard below; get the ordering backwards (near >= far)
# and every distance just reads as max_scale.
static func compute_scale(distance: float, near_distance: float, far_distance: float, min_scale: float, max_scale: float) -> float:
	if far_distance <= near_distance:
		return max_scale
	var t: float = clampf(inverse_lerp(near_distance, far_distance, distance), 0.0, 1.0)
	return lerpf(max_scale, min_scale, t)
