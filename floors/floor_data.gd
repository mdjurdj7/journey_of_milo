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
# Optional painted wear on the same canvas again: white is walked sand,
# and the value scales it, so a mid grey is a fainter trace than the
# band Ground draws along this floor's own route. Onto Ground.wear_mask,
# which combines the two by max() and gates both at the waterline. Null
# = only the derived band.
@export var wear_mask: Texture2D = null
# Normalized image coords of the pixel that sits on `spawn`.
@export var mask_origin: Vector2 = Vector2(0.5, 0.5)
# The four Ground values that set how wet the floor reads, pushed onto
# Ground's own exports of the same names (landmass_interior_height,
# landmass_falloff_width, relief_amplitude, caustic_strength).
@export var interior_height: float = 0.25
@export var falloff: float = 4.0
# Ground.landmass_underwater_falloff_width: how many metres past the
# drawn line the seabed takes to reach full depth. The region's own 6 m
# is right for an open shore; a floor with a WADE - a gap between two
# shores only a few metres wide - never gets past the shallow end of
# that ramp, so its crossing reads as wet sand however it is painted.
@export var underwater_falloff: float = 6.0
@export var relief_amplitude: float = 0.15
@export var caustic_strength: float = 0.15
# The relief mesh's own size and density, onto Ground's exports of the
# same names - a floor whose painted land runs past the default extent
# (Z -35..35 at 100 x 70, centred on spawn) needs its own, or the land
# beyond it is flat dressing with no relief and no collision. Keep
# subdivisions near 0.35 m a vertex: the shoreline contour reads as
# faceted much past that. Defaults are the region scene's own values,
# so a floor that says nothing gets exactly what it always had.
@export var relief_extent: Vector2 = Vector2(100.0, 70.0)
@export var relief_subdivisions: Vector2i = Vector2i(285, 199)
# RegionField.wade_drain_enabled for this floor: whether standing past the
# shoreline costs HP (the rates stay RegionField's own, region-wide).
@export var wade_drain_enabled: bool = false

@export_group("Ambience")
# This floor's sea/wind balance, as offsets on the beds' own base levels
# (Sea.volume_db_max/min for the sea, WindAmbience.base_volume_db for the
# wind) - pushed by RegionField in _enter_tree(), before either bed
# spawns, so a floor starts at its own levels under the fade with no
# step. The low-pass sits on the Sea bus (default_bus_layout.tres) and is
# written on every floor load, 20000 (open) included - a global bus
# keeps whatever the last floor left on it.
@export var ambience_sea_db: float = 0.0
@export var ambience_wind_db: float = 0.0
@export var ambience_sea_lowpass_hz: float = 20000.0

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
# Routes for clusters that move between perches - one per group that
# does (see FloorPatrol). Empty: every enemy stands where it was put.
@export var patrols: Array[FloorPatrol] = []

@export_group("Gate")
# Beyond the first enemy's own position, along exit_direction - where the
# gate line lands.
@export var gate_distance_beyond_enemy: float = 6.0
# ExitGate.channel_bar_axis_offset: metres across from the gate line to
# the surfaced bar's centre, for a neck that isn't centred on the gate.
@export var gate_bar_axis_offset: float = 0.0
# ExitGate.channel_max_width: metres past which the channel stops
# widening with the walls and centres on the gate. 0 (the default) spans
# them, which is what every floor did before floor 2 grew an alcove.
@export var gate_channel_max_width: float = 0.0

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
# A bundle's rare draw (BundleProp.roll()) - the placeholder for trinkets
# and weapons until those exist. Null or empty = the bundle draws its
# rare card from its own pool instead.
@export var rare_pool: RewardPool = null
# Coin per won fight, inclusive both ends, rolled from RunState.rng.
@export var gold_min: int = 10
@export var gold_max: int = 18
