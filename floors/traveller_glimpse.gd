extends Resource
class_name TravellerGlimpse

# Someone glimpsed walking away on arrival - see FloorData.traveller_
# glimpse and Traveller. RegionField spawns one Traveller for it the first
# time a run stands on the floor; it walks this path and is gone the
# moment it is wholly outside the camera's frustum.

# The walk, in order: world-XZ points relative to the floor's spawn, as
# FloorData.wear_path_override's are. He stands on the first at load,
# mid-stride, and walks the rest; at the last he stops. Lay it to leave
# the arrival frame through its top edge - he is freed only out of frame -
# starting with his whole body just under that edge; control returns
# once he is gone (release_after_removal_seconds).
# The chance a run shows him, rolled the first time the run stands on
# the floor - never on two runs in a row. 1 = every run (but still never
# two in a row).
@export_range(0.0, 1.0) var chance_per_run: float = 0.25
@export var path: PackedVector2Array = PackedVector2Array()
# Walking pace along it, metres a second. Read live.
@export var speed: float = 1.3
# Seconds standing on the first point before he sets off. 0 = walking from
# the first frame.
@export var start_delay: float = 0.0
# The arrival hold on the visit that shows him: the player's control
# returns this long after he leaves the frame (Traveller.left_frame) - in
# place of the floor's FloorData.arrival_hold_seconds. 0 = the moment he
# is gone. Read live.
@export var release_after_removal_seconds: float = 0.0
# Seconds of hold at most, however long he takes - a traveller who never
# leaves the frame can't keep the player locked. Read live.
@export var hold_cap_seconds: float = 6.0
