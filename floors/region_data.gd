extends Resource
class_name RegionData

# A region's floors, in walking order. RegionField holds one of these
# (its `region` export) and plays floors[RunState.current_floor_index];
# stepping off the last one wraps back to the first for now (see
# RegionField._on_floor_exited() - "end of region"). Region-level facts
# (sea, sky, light, the tower's place) stay authored in the region's
# scene, not here.

@export var floors: Array[FloorData] = []
