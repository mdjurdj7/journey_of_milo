extends Resource
class_name EncounterOption

# One encounter an EncounterSlot can stand: who is in it, the props that
# belong to them, and their route if they move. Every position here is
# in the slot's frame (EncounterSlot.to_floor()) - an XZ offset from the
# slot's anchor - so the same option can be authored into another slot.
#
# Its props are this encounter's own (the Wardling's hitching post, the
# Dunecur's bones): spawned only when this option stands, after all of
# the floor's own props. Standing rule: an option prop never draws from
# RunState.rng as it loads - the floor props' draws come first and in
# their own order, and an option's must not shift them. A prop that ever
# needs a roll at load takes it from its slot's own stream instead (see
# RegionField._spawn_option_props()).

# Unique across the region's slots - the run log names it, and a run
# never stands the same option twice.
@export var option_id: StringName = &""
# Relative chance against the slot's other options. Ignored when it is
# the only one.
@export var weight: float = 1.0
# The encounter, in spawn order. More than one = one cluster: contact
# with any starts one fight with all (FieldEnemy.group is the slot's id).
@export var members: Array[FloorEnemy] = []
# A cluster's contact zone (PackContact): metres out from the convex hull
# of its living members, wherever they stand or fly - between them is
# inside it. -1 = its largest member's EnemyData.contact_radius_m, taken
# at spawn. Read every physics frame, so a live edit takes at once.
# Ignored for a lone member, which keeps its own contact area.
@export var contact_margin_m: float = -1.0
# Placed only with this option. A top-level prop's X/Z is in the slot's
# frame and takes the slot's yaw on top of its own; parent_index counts
# within this array. A member's face_prop_index points in here.
@export var props: Array[FloorProp] = []
# A pack felled together - every member killed on the same turn of the
# Wanderer's (BattleController.felled_together()): this keepsake is
# offered after the win's reward, unless it is held already, and this
# line is said once over the last of them (Spectral, the enemy lines'
# own). Null / empty = nothing more for it.
@export var felled_together_keepsake: TrinketData = null
@export var felled_together_line: String = ""
# The members' route, waypoints in the slot's frame. Null = they stand.
@export var patrol: FloorPatrol = null
