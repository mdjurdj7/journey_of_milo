extends Resource
class_name ShoreFlockData

# A small flock of shorebirds on a floor's open sand - see FloorData.
# shore_flock and ShoreFlock. RegionField makes one ShoreFlock for it once
# the scatter is placed; it settles where this says, idles, and takes off
# for good when the Wanderer comes near or a fight opens.
#
# Where: a spot drawn from the floor's own generator (the floor resource's
# path), on dry open sand path_distance_m from the worn band's
# centreline, clear of every scatter keep-out, exposed rock, solid
# scatter and each enemy's stance area grown by stance_clearance_m, and
# reachable on foot from the spawn - a spot in prefer_zones within
# prefer_inland_m of the water when there is one (a stream bank), else
# any open sand. The birds stand round it within spread_m.
#
# Placing values re-place the flock live (while it is still on the
# ground); the rest are read every frame.

@export_group("Placing")
# How many birds, from x to y inclusive.
@export var bird_count: Vector2i = Vector2i(3, 5):
	set(value):
		bird_count = value
		emit_changed()
# Metres from the worn band's centreline, x to y.
@export var path_distance_m: Vector2 = Vector2(3.5, 6.0):
	set(value):
		path_distance_m = value
		emit_changed()
# ScatterEntry zone bits a spot is preferred in (shoreline, pool rim, wet
# band - the water's edge), within prefer_inland_m of the water.
@export_flags("Shoreline", "Pool rim", "Wet band", "Open interior", "Dune flank", "Rock edge") var prefer_zones: int = 7:
	set(value):
		prefer_zones = value
		emit_changed()
@export var prefer_inland_m: Vector2 = Vector2(0.3, 3.0):
	set(value):
		prefer_inland_m = value
		emit_changed()
# Beyond each enemy's stance distance, as ScatterEntry.stance_clearance_m.
@export var stance_clearance_m: float = 1.0:
	set(value):
		stance_clearance_m = value
		emit_changed()
# The birds stand within this of the flock's spot, no two nearer than
# bird_spacing_m.
@export var spread_m: float = 0.8:
	set(value):
		spread_m = value
		emit_changed()
@export var bird_spacing_m: float = 0.3:
	set(value):
		bird_spacing_m = value
		emit_changed()
@export_group("")

@export_group("Look")
# The two models and their colour maps (each glb's own, saved beside it),
# under the painted shader with the props' fog pass. Both beak on +Z.
@export_file("*.glb") var standing_model_path: String = "res://assets/models/props/shorebird/shorebird.glb":
	set(value):
		standing_model_path = value
		emit_changed()
@export_file("*.jpg", "*.png") var standing_colour_map_path: String = "res://assets/models/props/shorebird/shorebird_albedo.jpg":
	set(value):
		standing_colour_map_path = value
		emit_changed()
@export_file("*.glb") var flying_model_path: String = "res://assets/models/props/shorebird/shorebird_flying.glb":
	set(value):
		flying_model_path = value
		emit_changed()
@export_file("*.jpg", "*.png") var flying_colour_map_path: String = "res://assets/models/props/shorebird/shorebird_flying_albedo.jpg":
	set(value):
		flying_colour_map_path = value
		emit_changed()
# Both models together, on their modelled size.
@export var model_scale: float = 1.0:
	set(value):
		model_scale = value
		emit_changed()
# The models' beak is on +Z; a bird's forward is its node's -Z.
@export var model_yaw_offset_degrees: float = 180.0:
	set(value):
		model_yaw_offset_degrees = value
		emit_changed()
# Multiplied into both colour maps - white is the map as painted.
@export var tint: Color = Color(1, 1, 1, 1):
	set(value):
		tint = value
		emit_changed()
@export_group("")

@export_group("Idle")
# Each bird on its own clock: a pause drawn from x to y seconds, then a
# peck, a hop or a turn, picked by these weights (x peck, y hop, z turn).
@export var pause_seconds: Vector2 = Vector2(0.5, 2.2)
@export var idle_weights: Vector3 = Vector3(0.45, 0.3, 0.25)
# A peck: the body tips forward this far round its hip and back.
@export var peck_degrees: float = 40.0
@export var peck_seconds: float = 0.28
# A hop: forward this far, x to y metres, this high, this quick.
@export var hop_distance_m: Vector2 = Vector2(0.05, 0.12)
@export var hop_height_m: float = 0.04
@export var hop_seconds: float = 0.18
# A turn: this many degrees either way, x to y, this quick.
@export var turn_degrees: Vector2 = Vector2(30.0, 120.0)
@export var turn_seconds: float = 0.2
# A bird farther than this from the flock's spot turns back toward it
# before it hops.
@export var leash_m: float = 1.0
@export_group("")

@export_group("Flight")
# The Wanderer within this, metres, and they go.
@export var flee_radius_m: float = 6.0
# The birds lift one after another over this many seconds.
@export var takeoff_spread_seconds: float = 0.3
# The wing beat: the model squashed vertically to flap_squash of its
# height and back, flap_hz times a second.
@export var flap_hz: float = 8.0
@export_range(0.0, 1.0, 0.01) var flap_squash: float = 0.35
# Speed along the ground and climb, metres a second; the climb eases off
# toward climb_height_m above where it took off.
@export var flight_speed_m: float = 4.5
@export var climb_speed_m: float = 2.0
@export var climb_height_m: float = 7.0
# It leaves between away-from-the-Wanderer (weighted away_weight against
# downwind's 1) and downwind (RegionField.get_wind_direction()), then
# curves on toward downwind at most curve_degrees_per_second, each bird's
# own heading off it by up to heading_jitter_degrees.
@export var away_weight: float = 1.0
@export var curve_degrees_per_second: float = 35.0
@export var heading_jitter_degrees: float = 20.0
# Gone once out of the camera's view - and after this many seconds aloft
# whatever the view.
@export var flight_cap_seconds: float = 10.0
@export_group("")
