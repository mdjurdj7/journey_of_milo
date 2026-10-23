extends StaticBody3D
class_name WalkSurface

# Something solid he walks on over the sand - a RockShelf's plates, say.
# It joins WALK_SURFACE_GROUP (each kind in its own _ready()), and
# Ground.get_walk_surface_at()/get_walk_height_at() take the highest one
# over the sand at an XZ: what his ground hold, his footprints and the
# walk grid read. The walk grid doesn't stamp it as an obstacle, nor does
# the click take it for one (RegionField); scatter keeps off its outline
# (FieldScatter).
#
# One height per XZ, like the sand: the highest surface over a point is
# what he stands on there, whatever is under it. Nothing walkable may lie
# beneath one.

const WALK_SURFACE_GROUP := &"walk_surfaces"

# The top's world height at a world XZ, or -INF off it.
func get_top_height_at(_world_xz: Vector2) -> float:
	return -INF

# The top's world normal at a world XZ; UP off it.
func get_top_normal_at(_world_xz: Vector2) -> Vector3:
	return Vector3.UP

# Its edge as world XZ, in order, for scatter's keep-out; empty for none.
func get_world_outline() -> PackedVector2Array:
	return PackedVector2Array()

# Whether his steps print on it (FootprintSpawner) - stone takes them,
# planks don't.
func takes_footprints() -> bool:
	return true
