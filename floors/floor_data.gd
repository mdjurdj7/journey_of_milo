extends Resource
class_name FloorData

# One floor of a region, as data: the painted landmass, where the
# Wanderer starts, which way out is, what stands on it, and what its
# fights pay. RegionField reads the current one (RegionData.floors[
# RunState.current_floor_index]) in its _enter_tree()/_ready() - see its
# own doc for which value lands where. Nothing floor-specific is authored
# in region_field.tscn any more; the scene is the REGION (sea, sky,
# light, tower, HUD), and a floor is one of these.

@export_group("Landmass")
# The painted land, white = sand - see Ground's own Landmass Mask group.
# Image up is the TOWER direction (RegionField.get_forward()), for every
# floor of a region alike, so the tower is at the top of every painting.
@export var mask: Texture2D = null
# Optional relief painted on the SAME canvas as `mask` (same size, origin,
# scale): white lifts the sand by Ground.elevation_max_height, clipped to
# the drawn shoreline - see Ground's elevation_mask. Null = flat floor.
@export var elevation_mask: Texture2D = null
# Normalized image coords of the pixel that sits on `spawn`.
@export var mask_origin: Vector2 = Vector2(0.5, 0.5)
# The four Ground values that set how wet the floor reads, pushed onto
# Ground's own exports of the same names (landmass_interior_height,
# landmass_falloff_width, relief_amplitude, caustic_strength).
@export var interior_height: float = 0.25
@export var falloff: float = 4.0
@export var relief_amplitude: float = 0.15
@export var caustic_strength: float = 0.15
# RegionField.wade_drain_enabled for this floor: whether standing past the
# shoreline costs HP (the rates stay RegionField's own, region-wide).
@export var wade_drain_enabled: bool = false

@export_group("Layout")
# The Wanderer's start, world XZ. Every floor so far spawns at the
# origin and lets mask_origin do the shifting, which keeps the
# spawn->ForwardMarker forward exactly the region's own.
@export var spawn: Vector2 = Vector2.ZERO
# Unit XZ, the way OUT of this floor: the gate channel, the camera's
# inland bound, the worn band's end and the transition trigger all lie
# along it. Independent of the tower direction (which is where the sea
# isn't) - on region 1's floors so far the two agree.
@export var exit_direction: Vector2 = Vector2(0.0, -1.0)
@export var enemies: Array[FloorEnemy] = []
@export var props: Array[FloorProp] = []

@export_group("Gate")
# Beyond the first enemy's own position, along exit_direction - where the
# gate line lands.
@export var gate_distance_beyond_enemy: float = 6.0
# ExitGate.channel_bar_axis_offset: metres across from the gate line to
# the surfaced bar's centre, for a neck that isn't centred on the gate.
@export var gate_bar_axis_offset: float = 0.0

@export_group("Wear")
# How far the worn band's middle point sits off the enemy along the
# exit's right (RegionField._aim_wear_path()).
@export var wear_path_mid_offset: float = 1.5
# Optional: three world-XZ points relative to spawn (start, through,
# end) that replace the derived spawn -> enemy -> gate band outright.
# Empty (the default) = derived.
@export var wear_path_override: PackedVector2Array = PackedVector2Array()

@export_group("Rewards")
# What a won fight offers. Null = no drop at all.
@export var reward_pool: RewardPool = null
# Coin per won fight, inclusive both ends, rolled from RunState.rng.
@export var gold_min: int = 10
@export var gold_max: int = 18
