extends Resource
class_name FloorPatrol

# A route for one encounter - see EncounterOption.patrol. RegionField
# spawns a PackPatrol for it (RegionField._spawn_floor_patrols()) that
# flies the option's members between the waypoints as a loose flock:
# every member aims at the same waypoint plus its own offset from the
# members' authored centroid, so the pack keeps its shape without moving
# in lockstep. An option without one never moves.

# The loop, in order: XZ offsets from the slot's anchor, in the slot's
# frame like FloorEnemy.position - each is where the members' CENTROID
# lands. The members start perched where they were authored; their
# first leg is to waypoint 0 (which is where they already are, when it is
# authored as their own centroid), and the loop wraps. Every member's
# spot - waypoint + its offset - must be dry with room to spare (0.8 m);
# a waypoint is not clamped to the land.
@export var waypoints: PackedVector2Array = PackedVector2Array()
# Seconds perched at each waypoint before the next leg, rolled between
# these two per perch.
@export var dwell_min_seconds: float = 2.0
@export var dwell_max_seconds: float = 5.0
