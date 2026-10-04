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
# Ground.elevation_max_height for this floor: the lift, in metres, that a
# white pixel of elevation_mask stands for. Per floor because a painting
# is authored against one - the same grey at another height is another
# slope. 1.2 is Ground's own default; floor 2 was painted at 1.8.
@export var elevation_max_height: float = 1.2
# Optional painted wear on the same canvas again: white is walked sand,
# and the value scales it, so a mid grey is a fainter trace than the
# band Ground draws along this floor's own route. Onto Ground.wear_mask,
# which combines the two by max() and gates both at the waterline. Null
# = only the derived band.
@export var wear_mask: Texture2D = null
# Optional exposed rock on the same canvas: white = the ground turns to
# stone here where it is steep (Ground.rock_mask). Null = no rock on the
# floor, however steep its sand.
@export var rock_mask: Texture2D = null
# Optional out-of-bounds ground on the same canvas: white = the outer
# surface (Ground.outer_mask) - its own colour and pebbles, so the floor's
# edge reads by surface where height doesn't. Null = sand everywhere, as
# every floor had it before.
@export var outer_mask: Texture2D = null
# Normalized image coords of the pixel that sits on `spawn`.
@export var mask_origin: Vector2 = Vector2(0.5, 0.5)
# Ground.landmass_mask_beyond_is_land: past every edge of `mask` is land,
# not water - for an inland floor with no coast, whose mask is white to
# its edges. False (the default) = water past the sides and bottom, the
# top row extended, as every coastal floor has it.
@export var mask_beyond_is_land: bool = false
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
# Ground's Basin Tint, for this floor: low ground toward basin_color,
# rising ground back to the dry sand, over basin_tint_heights (metres
# above the floor's land level - full at x, gone by y). Strength 0 (the
# default) is off.
@export var basin_color: Color = Color(0.66, 0.63, 0.55)
@export_range(0.0, 1.0) var basin_tint_strength: float = 0.0
@export var basin_tint_heights: Vector2 = Vector2(0.0, 1.2)
# Ground.wear_darken for this floor: how much darker the worn band is than
# the ground under it. 0.24 is the region's own value.
@export_range(0.0, 1.0) var wear_darken: float = 0.24
# Ground's Slope Tint, for this floor: faces past slope_tint_min degrees
# toward slope_tint_color (full slope_tint_blend further on) at
# slope_tint_strength - wind-packed sand, so a slope reads by value even
# where the sun shades it like flat ground - and flat ground over
# crest_min_height metres above the land level lighter by
# crest_light_strength. Strengths 0 (the default) are off.
@export var slope_tint_color: Color = Color(0.58, 0.57, 0.53)
@export_range(0.0, 1.0) var slope_tint_strength: float = 0.0
@export var slope_tint_min: float = 8.0
@export var slope_tint_blend: float = 12.0
@export_range(0.0, 1.0) var crest_light_strength: float = 0.0
@export var crest_min_height: float = 1.0
# Ground's Wind Ripples, for this floor: one direction across the dry open
# sand (degrees from +X toward +Z), crest-to-crest metres, strength and
# warp. Strength 0 (the default) is off.
@export var wind_ripple_angle: float = 30.0
@export var wind_ripple_scale: float = 0.45
@export_range(0.0, 0.5) var wind_ripple_strength: float = 0.0
@export var wind_ripple_warp: float = 0.5
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
# The depth fog for this floor, camera metres (RegionSky.fog_depth_begin /
# fog_depth_end): from begin to full at end. 0 for either (the default)
# keeps the region's own.
@export var fog_depth_begin: float = 0.0
@export var fog_depth_end: float = 0.0

@export_group("Layout")
# The Wanderer's start, world XZ. Every floor so far spawns at the
# origin and lets mask_origin do the shifting, which keeps the
# spawn->ForwardMarker forward exactly the region's own.
@export var spawn: Vector2 = Vector2.ZERO
# Unit XZ, the way OUT of this floor: the gate (its channel or its hold
# line - see exit_kind), the camera's inland bound, the worn band's end
# and the transition trigger all lie along it. Independent of the tower
# direction (which is where the sea isn't) - on region 1's floors so far
# the two agree.
@export var exit_direction: Vector2 = Vector2(0.0, -1.0)
@export var enemies: Array[FloorEnemy] = []
@export var props: Array[FloorProp] = []
# Routes for clusters that move between perches - one per group that
# does (see FloorPatrol). Empty: every enemy stands where it was put.
@export var patrols: Array[FloorPatrol] = []
# Invisible walls along the lips of raised faces painted too gentle to
# stop him on their own (LedgeBarrier) - one line per ledge, world XZ
# offsets from spawn in order along the lip. Empty: every face stops him
# or doesn't by its slope alone.
@export var ledges: Array[PackedVector2Array] = []
@export_group("Gate")
# How the way out is closed while required fights remain (ExitGate.
# exit_kind). CHANNEL: a tidal channel across the neck, a Blocker in it,
# drained to a bar on clear - for a floor with a real neck. LINE: nothing
# on the ground at all - the Wanderer himself won't cross the gate line
# (Wanderer.set_hold_line()) until the floor is cleared - for a floor that
# opens out rather than funnelling.
enum ExitKind { CHANNEL, LINE }
@export var exit_kind: ExitKind = ExitKind.CHANNEL
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
# Optional: world-XZ points relative to spawn that replace the derived
# spawn -> enemy -> gate band outright. Three (start, through, end): one
# curve, as the derived band is. Four to eight: a smooth curve through
# every one of them, for a route that turns more than once (floor 4's
# loop). Empty (the default) = derived.
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
