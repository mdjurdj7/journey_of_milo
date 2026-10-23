extends Resource
class_name RegionData

# A region's floors, in walking order. RegionField lists these (its
# `regions` export, picked by RunState.current_region_index) and plays
# floors[RunState.current_floor_index]; stepping off the last one ends
# the run, won (RegionField._on_floor_exited()), unless its
# loop_region_after_last_floor test switch sends it round to the first.
# Region-level facts (sea, sky, light, the tower's place) stay authored
# in the region's scene, not here.

@export var floors: Array[FloorData] = []

# The region's name as the zone intro shows it (ZoneIntro's title): in
# Spectral on the open sky, faded in over the hold and out before the
# camera comes down. Empty = no title; the move still plays.
@export var display_name: String = ""
