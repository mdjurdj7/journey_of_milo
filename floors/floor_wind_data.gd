extends Resource
class_name FloorWindData

# A floor's blowing sand - see FloorData.wind and FieldWind. RegionField
# makes one FieldWind for it; with none (the default) the floor's air is
# still, and RegionField.get_gust() stays 0.
#
# Four layers along the floor's one wind (RegionField.get_wind_direction()):
# low streaks of sand skimming the dry ground; gusts, the one shared value
# (RegionField.get_gust()) every layer and the tufts' sway read; plumes
# off the dune crests during a gust; and slow dust shadows sliding over
# the ground. Sand lifts only from dry sand - never the wet band, water,
# or exposed rock - read from the ground onto FieldWind's map.
#
# The map values (map_step_m, the crest ones) rebuild the map live; the
# rest are read every frame.

@export_group("Direction")
# The wind's own angle, degrees from +X toward +Z (as the ripples are),
# in place of the floor's ripple angle or RegionField.default_wind_angle_
# degrees - see RegionField.get_wind_direction(). use_angle off = the
# floor's.
@export var use_angle: bool = false:
	set(value):
		use_angle = value
		emit_changed()
@export var angle_degrees: float = 30.0:
	set(value):
		angle_degrees = value
		emit_changed()
@export_group("")

@export_group("Gusts")
# A gust starts every x..y seconds (start to start), drawn from the
# floor's own generator (the floor resource's path), so a load blows the
# same.
@export var gust_interval_s: Vector2 = Vector2(6.0, 12.0):
	set(value):
		gust_interval_s = value
		emit_changed()
# The wind rises over gust_rise_s, holds x..y seconds, falls over
# gust_fall_s; eased both ways.
@export var gust_rise_s: float = 0.5:
	set(value):
		gust_rise_s = value
		emit_changed()
@export var gust_hold_s: Vector2 = Vector2(2.0, 3.0):
	set(value):
		gust_hold_s = value
		emit_changed()
@export var gust_fall_s: float = 1.0:
	set(value):
		gust_fall_s = value
		emit_changed()
# The first gust waits at least this long after the load.
@export var first_gust_delay_s: float = 3.0:
	set(value):
		first_gust_delay_s = value
		emit_changed()
# The tufts' sway and lean (tuft_card.gdshader) grow by this fraction of
# themselves at a full gust: 1.2 = 2.2x.
@export var gust_sway_gain: float = 1.2:
	set(value):
		gust_sway_gain = value
		emit_changed()
@export_group("")

@export_group("Streaks")
# The most streaks alive at once (a full gust); calm keeps
# streak_calm_fraction of them, a fight battle_fraction of that.
@export var streak_count: int = 240:
	set(value):
		streak_count = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var streak_calm_fraction: float = 0.35:
	set(value):
		streak_calm_fraction = value
		emit_changed()
# Each lives this long, fading in and out over streak_fade of its life
# either end.
@export var streak_lifetime_s: float = 2.6:
	set(value):
		streak_lifetime_s = value
		emit_changed()
@export_range(0.0, 0.5, 0.01) var streak_fade: float = 0.3:
	set(value):
		streak_fade = value
		emit_changed()
# Born within this square's half-size round where the camera looks, so
# the frame always has some, wherever it is.
@export var streak_area_half_m: float = 15.0:
	set(value):
		streak_area_half_m = value
		emit_changed()
# Long along the wind x width across, metres; each streak x0.7..1.3.
@export var streak_size_m: Vector2 = Vector2(3.2, 0.4):
	set(value):
		streak_size_m = value
		emit_changed()
# Its centre above the sand, metres, drawn per streak from x..y.
@export var streak_height_m: Vector2 = Vector2(0.04, 0.3):
	set(value):
		streak_height_m = value
		emit_changed()
# Downwind metres a second, calm; a full gust adds gust_speed_gain of it.
@export var streak_speed_mps: float = 2.2:
	set(value):
		streak_speed_mps = value
		emit_changed()
@export var gust_speed_gain: float = 1.3:
	set(value):
		gust_speed_gain = value
		emit_changed()
# A streak only darkens what is behind it (wind_sand.gdshader): at its
# peak, at its heart, streak_alpha of the way toward streak_value times
# the sand - a neutral grey, so the sand's hue stays; never lighter.
@export_range(0.0, 1.0, 0.01) var streak_alpha: float = 0.4:
	set(value):
		streak_alpha = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var streak_value: float = 0.8:
	set(value):
		streak_value = value
		emit_changed()
# A wisp thins out over this last stretch before the ground (or anything)
# behind it, so it fades into a slope instead of being cut - short for a
# streak, which rides just over the sand.
@export var streak_soft_depth_m: float = 0.1:
	set(value):
		streak_soft_depth_m = value
		emit_changed()
@export_group("")

@export_group("Plumes")
# Off the dune crests while a gust blows: the most alive at once at a
# full gust, none calm; never in a fight.
@export var plume_count: int = 120:
	set(value):
		plume_count = value
		emit_changed()
@export var plume_lifetime_s: float = 1.8:
	set(value):
		plume_lifetime_s = value
		emit_changed()
# Long along the wind x tall, metres, at birth; grown by plume_grow by
# the end of its life.
@export var plume_size_m: Vector2 = Vector2(1.4, 0.45):
	set(value):
		plume_size_m = value
		emit_changed()
@export var plume_grow: float = 1.8:
	set(value):
		plume_grow = value
		emit_changed()
# Born on the crests within this square's half-size round where the
# camera looks.
@export var plume_area_half_m: float = 22.0:
	set(value):
		plume_area_half_m = value
		emit_changed()
# Born this high over its crest, metres, drawn per plume from x..y.
@export var plume_height_m: Vector2 = Vector2(0.4, 0.9):
	set(value):
		plume_height_m = value
		emit_changed()
# Downwind and upward metres a second.
@export var plume_speed_mps: float = 2.5:
	set(value):
		plume_speed_mps = value
		emit_changed()
@export var plume_rise_mps: float = 0.5:
	set(value):
		plume_rise_mps = value
		emit_changed()
# As streak_alpha / streak_value.
@export_range(0.0, 1.0, 0.01) var plume_alpha: float = 0.4:
	set(value):
		plume_alpha = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var plume_value: float = 0.8:
	set(value):
		plume_value = value
		emit_changed()
# As streak_soft_depth_m.
@export var plume_soft_depth_m: float = 0.6:
	set(value):
		plume_soft_depth_m = value
		emit_changed()
# A crest: sand at least crest_min_fraction of the way from the sea to
# the floor's highest drawn ground, standing crest_prominence_m over the
# ground crest_reach_m either side along some axis. Rebuilds the map.
@export_range(0.0, 1.0, 0.01) var crest_min_fraction: float = 0.55:
	set(value):
		crest_min_fraction = value
		emit_changed()
@export var crest_prominence_m: float = 0.08:
	set(value):
		crest_prominence_m = value
		emit_changed()
@export var crest_reach_m: float = 3.0:
	set(value):
		crest_reach_m = value
		emit_changed()
@export_group("")

@export_group("Dust shadow")
# Large faint patches darkening the ground (Ground's dust_shadow_*),
# sliding downwind: at most dust_shadow_strength darker, patches about
# dust_shadow_scale_m across (stretched dust_shadow_stretch along the
# wind), at dust_shadow_speed_mps - a gust adds gust_speed_gain of it.
@export_range(0.0, 0.3, 0.005) var dust_shadow_strength: float = 0.06:
	set(value):
		dust_shadow_strength = value
		emit_changed()
@export var dust_shadow_scale_m: float = 16.0:
	set(value):
		dust_shadow_scale_m = value
		emit_changed()
@export var dust_shadow_stretch: float = 2.0:
	set(value):
		dust_shadow_stretch = value
		emit_changed()
@export var dust_shadow_speed_mps: float = 1.0:
	set(value):
		dust_shadow_speed_mps = value
		emit_changed()
@export_group("")

@export_group("Fight")
# While a fight holds the field: streaks at this fraction of their count,
# no plumes.
@export_range(0.0, 1.0, 0.01) var battle_fraction: float = 0.45:
	set(value):
		battle_fraction = value
		emit_changed()
@export_group("")

@export_group("Map")
# The ground read onto FieldWind's map at this step, metres. Rebuilds it.
@export var map_step_m: float = 1.0:
	set(value):
		map_step_m = value
		emit_changed()
@export_group("")
