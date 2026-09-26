extends Resource
class_name FloorRoam

# One enemy that drifts about a patch of a floor rather than standing
# still - see FloorData.roams. RegionField spawns a Roamer for each of
# these (RegionField._spawn_floor_roams()) that walks the named enemy
# aimlessly and slowly within `area`, off the worn band, on dry sand. Not
# a route: there are no waypoints and no stops (a pack that goes
# somewhere is a FloorPatrol).

# Which of FloorData.enemies roams, by index into that array.
@export var enemy_index: int = -1
# Where it may be: world XZ offsets from the floor's spawn, like
# FloorEnemy.position (x = X, y = Z) - `position` is the rect's min
# corner. The Roamer also keeps it on dry sand and off the worn band on
# its own, so this can be loose against the shore; keep it clear of other
# enemies' contact areas and of props by hand. The enemy's authored
# position should lie inside it.
@export var area: Rect2 = Rect2()
# Its walking pace, metres a second - the Roamer breathes around it
# (Roamer.speed_variation) but never stops.
@export var speed_mps: float = 0.35
# How far its body stays from the worn band's centre line (RegionField.
# get_wear_path()), metres - more than its own contact radius, so walking
# the band never brushes it and it never stands across the way.
@export var band_keep_off_m: float = 3.0
