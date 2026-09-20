extends Resource
class_name FloorProp

# One thing standing on a floor that isn't an enemy - a Hull, the Keeper,
# a Bird on a hull, a WorldCard lying on the sand - see FloorData.props.
# RegionField instantiates `scene` and places it (RegionField._spawn_
# floor_props()): a prop with set_floor_placement() (Hull, Keeper, Bird)
# is handed position/yaw/roll through it and maps them onto its own
# facing exports; a WorldCard has no facing and is simply grounded.

@export var scene: PackedScene = null
# For a top-level prop: X/Z are the offset from the floor's spawn, Y is
# ignored (props ground themselves on the relief). With parent_index set:
# the prop's LOCAL position on that parent, all three axes - a Bird's
# perch_offset on its hull.
@export var position: Vector3 = Vector3.ZERO
# Onto the prop's own yaw export: Hull.yaw_offset_degrees (on top of its
# bow-to-sea), Keeper.face_yaw_offset_degrees (on top of face_direction),
# Bird.perch_yaw_degrees.
@export var yaw_degrees: float = 0.0
# Hull.roll_degrees; ignored by props that don't roll.
@export var roll_degrees: float = 0.0
# Index into the same props array of the prop this one is a child of
# (the Bird on Hull1), or -1 for a child of the field's Props node. A
# parent must come EARLIER in the array than its children.
@export var parent_index: int = -1
# The one-time line this prop says on approach (Hull.world_line). Empty
# = says nothing, or keeps its own default (the Keeper's lines are hers).
@export_multiline var world_line: String = ""
# What a prop that offers cards rolls from: a RewardSpread (a cache on
# the sand) needs one; a belongings WorldCard uses it when set and falls
# back to the floor's own reward_pool when not. Ignored by props that
# don't offer cards.
@export var pool: RewardPool = null
# Anything else the scene's exports should be set to before it enters the
# tree, by property name: {"bird_mesh": <glb>, "face_direction": 3}.
# Applied with Object.set(), so a name the prop doesn't have is a silent
# no-op - keep to what the prop's script actually exports.
@export var overrides: Dictionary = {}
