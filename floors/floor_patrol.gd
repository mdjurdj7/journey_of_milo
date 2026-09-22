extends Resource
class_name FloorPatrol

# A route for one cluster (FloorEnemy.group) - see FloorData.patrols.
# RegionField spawns a PackPatrol for each of these (RegionField._spawn_
# floor_patrols()) that flies the group's members between the waypoints
# as a loose flock: every member aims at the same waypoint plus its own
# offset from the group's authored centroid, so the pack keeps its shape
# without moving in lockstep. A group without one of these never moves.

# The cluster this route belongs to.
@export var group: StringName = &""
# The loop, in order: world XZ offsets from the floor's spawn, like
# FloorEnemy.position - each is where the GROUP'S CENTROID lands. The
# members start perched where they were authored; their first leg is to
# waypoint 0 (which is where they already are, when it is authored as
# their own centroid), and the loop wraps. Every member's spot -
# waypoint + its offset - must be dry with room to spare (0.8 m); a
# waypoint is not clamped to the land.
@export var waypoints: PackedVector2Array = PackedVector2Array()
# Seconds perched at each waypoint before the next leg, rolled between
# these two per perch.
@export var dwell_min_seconds: float = 2.0
@export var dwell_max_seconds: float = 5.0
