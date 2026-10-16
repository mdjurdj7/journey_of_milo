extends Resource
class_name ScatterEntry

# One kind of ground scatter - worm casts, shells, stones, samphire - as
# data: what it looks like, where on the wet-to-dry gradient it lies, and
# how thickly. A ScatterSet holds a floor's entries; FieldScatter places
# them at load and again, the same way, whenever any value here changes
# (every setter emits `changed`), so each is tunable live from the Remote
# tab. Nothing here is per floor: a floor picks its sets.
#
# Placement: cluster centres by Poisson-disc over the cells this entry's
# zones allow (inside `area`, when it has one), clusters_per_100m2 of that
# area - or cluster_count of them; items_per_cluster around each, Gaussian
# over a spread drawn per cluster from cluster_spread_m, so a cluster thins
# at its edges. A tight patch (samphire) is a cluster with many items and
# a small spread.
# Never on the worn band, in water past wet_edge_m, or inside an
# exclusion (FieldScatter).
#
# Or, in CONTOUR mode (a tideline), along a line a set distance inland of
# the water - contour_inland_m, wandering contour_wander_m either side -
# broken into segments with gaps between, items every contour_spacing_m
# along a segment, each turned roughly along the line. Entries that name
# the same contour_line share its segments (the strands and the twigs of
# one tideline).

enum Mode { CLUSTERS, CONTOUR }
# Appended: an inserted value would rewrite every .tres that stores one
# of these as an integer.
enum PlaceholderKind { CAST, SHELL, STONE_ROUND, STONE_FLAT, STRAND, TWIG }
# How it settles: FLAT lies on the sand as it is (a cast); CONVEX_UP turns
# its dome up (a shell, the way they come to rest); FLATTEST_SIDE turns
# its thinnest axis up (a stone).
enum Resting { FLAT, CONVEX_UP, FLATTEST_SIDE }
# Bit flags for `zones` - which bands of the wet-to-dry gradient a cluster
# may centre in (FieldScatter classifies every cell into one of the first
# four), and the dry ground's two marks a cell may carry on top of its
# band: DUNE_FLANK, a sloping sand face; ROCK_EDGE, sand at the foot of
# exposed rock. A cluster may centre where any of its zones' bits is set.
const ZONE_SHORELINE := 1
const ZONE_POOL_RIM := 2
const ZONE_WET_BAND := 4
const ZONE_OPEN_INTERIOR := 8
const ZONE_DUNE_FLANK := 16
const ZONE_ROCK_EDGE := 32

@export var name: String = "":
	set(value):
		name = value
		emit_changed()
# The model. Empty = assets/models/props/scatter/<name>.glb when that file
# exists, else the placeholder below, made in code.
@export_file("*.glb") var mesh_path: String = "":
	set(value):
		mesh_path = value
		emit_changed()
# Its own colour map under the painted shader, as the model props wear
# it (PaintedProp: the soft light, the depth fog laid back over it), times
# `tint` - set, tint_jitter is unused. Empty = the shared flat material.
@export_file("*.jpg", "*.png") var colour_map_path: String = "":
	set(value):
		colour_map_path = value
		emit_changed()
@export var placeholder: PlaceholderKind = PlaceholderKind.CAST:
	set(value):
		placeholder = value
		emit_changed()
@export var mode: Mode = Mode.CLUSTERS:
	set(value):
		mode = value
		emit_changed()

@export_group("Look")
# Across, metres, at a scale of 1 - the model is sized to this whatever
# its own units.
@export var size_m: float = 0.07:
	set(value):
		size_m = value
		emit_changed()
# Above 0: sized to the model's own width across times this, instead of
# size_m - a model made at its real size, scaled as a whole.
@export var model_scale: float = 0.0:
	set(value):
		model_scale = value
		emit_changed()
# Each item's size, a random factor from x to y.
@export var scale_range: Vector2 = Vector2(0.75, 1.25):
	set(value):
		scale_range = value
		emit_changed()
# Each item tilts this many degrees off the slope at most, at random.
@export_range(0.0, 30.0, 0.5) var tilt_jitter_degrees: float = 4.0:
	set(value):
		tilt_jitter_degrees = value
		emit_changed()
# Set into the sand by this fraction of its own height.
@export_range(0.0, 1.0, 0.01) var sink_fraction: float = 0.3:
	set(value):
		sink_fraction = value
		emit_changed()
# Set into the sand by a random depth from x to y metres, instead of
# sink_fraction. x below 0 = the fraction.
@export var sink_range_m: Vector2 = Vector2(-1.0, -1.0):
	set(value):
		sink_range_m = value
		emit_changed()
@export var resting: Resting = Resting.FLAT:
	set(value):
		resting = value
		emit_changed()
# The colour, on the shared flat material, and each item's value off it
# at random, up to this fraction either way.
@export var tint: Color = Color(0.6, 0.57, 0.49):
	set(value):
		tint = value
		emit_changed()
@export_range(0.0, 0.2, 0.005) var tint_jitter: float = 0.04:
	set(value):
		tint_jitter = value
		emit_changed()
# How far it sways, as a fraction of its height at the top - near zero for
# a stiff succulent; 0 = never moves (and the plain flat material).
@export_range(0.0, 0.2, 0.001) var wind: float = 0.0:
	set(value):
		wind = value
		emit_changed()
@export var cast_shadow: bool = false:
	set(value):
		cast_shadow = value
		emit_changed()
@export_group("")

@export_group("Where")
@export_flags("Shoreline", "Pool rim", "Wet band", "Open interior", "Dune flank", "Rock edge") var zones: int = ZONE_SHORELINE:
	set(value):
		zones = value
		emit_changed()
# Metres inland of the water line a cluster may centre, from x to y
# (negative is past it, into the water).
@export var inland_range_m: Vector2 = Vector2(0.0, 3.0):
	set(value):
		inland_range_m = value
		emit_changed()
# How far below the water's level an item may still sit, metres - 0 keeps
# it on dry sand; a little lets samphire stand at the very edge.
@export var wet_edge_m: float = 0.0:
	set(value):
		wet_edge_m = value
		emit_changed()
# Cluster centres only inside this polygon, world XZ from the floor's
# spawn (a floor's samphire kept to one shore). Empty = anywhere.
@export var area: PackedVector2Array = PackedVector2Array():
	set(value):
		area = value
		emit_changed()
# Nothing within this of any enemy - a tideline kept off the water's edge
# beside a fight. 0 = only the floor's battle-frame exclusions.
@export var enemy_clearance_m: float = 0.0:
	set(value):
		enemy_clearance_m = value
		emit_changed()
# Nothing within this beyond each enemy's stance distance (RegionField.
# stance_distance() for it) - the whole ground a fight's feet can stand
# on, whichever way he came. Below 0 = off.
@export var stance_clearance_m: float = -1.0:
	set(value):
		stance_clearance_m = value
		emit_changed()
# Kept this far off a ledge's wall (LedgeBarrier) instead of the floor's
# prop margin - grass grows right to the foot of the rock, where he can't
# walk up to it anyway. Below 0 = the prop margin, as any static body.
@export var ledge_margin_m: float = -1.0:
	set(value):
		ledge_margin_m = value
		emit_changed()
# Never on exposed rock (the ground's rock rule - FieldScatter).
@export var avoid_rock: bool = false:
	set(value):
		avoid_rock = value
		emit_changed()
# Tested at its edge as well as its centre - eight points round the
# circle of half its width - so a wide stone never reaches into the worn
# band, the water or a keep-out its centre clears.
@export var footprint_test: bool = false:
	set(value):
		footprint_test = value
		emit_changed()
# Every entry placed after it keeps off its items' footprints (half their
# width round each) - a tuft never grows through a stone.
@export var solid: bool = false:
	set(value):
		solid = value
		emit_changed()
# Clusters round the items of these entries (by name, placed before this
# one) instead of over its zones: around_share of them each get one, its
# items in a ring just outside the item's footprint, cluster_spread_m
# out from its edge - tufts grown round a stone. Empty = its zones.
@export var around_entries: PackedStringArray = PackedStringArray():
	set(value):
		around_entries = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var around_share: float = 0.5:
	set(value):
		around_share = value
		emit_changed()
# Its own keep-out from the worn band's centreline, and the ramp back to
# full past it, metres, instead of the floor's (FieldScatter's Worn Band) -
# a stream bank's grass reaching the water beside the path. Below 0 = the
# floor's.
@export var wear_keep_out_m: float = -1.0:
	set(value):
		wear_keep_out_m = value
		emit_changed()
# Or its keep-out as this share of the floor's (FieldScatter.get_wear_
# keep_out(): the band's half-width plus its edge noise, read from the
# ground), so it follows the band's width - wins over wear_keep_out_m.
# Below 0 = off.
@export var wear_keep_out_share: float = -1.0:
	set(value):
		wear_keep_out_share = value
		emit_changed()
@export var wear_ramp_m: float = -1.0:
	set(value):
		wear_ramp_m = value
		emit_changed()
@export_group("")

@export_group("Edge")
# Cluster centres by the walkable edge instead of evenly over its zones:
# a centre is kept by a weight from how far it lies from the edge - the
# floor's ledges (FloorData.ledges), signed into the floor (+) and onto
# the bank past it (-); exposed rock's edge on a floor without ledges -
# densest on the edge itself and the foot of the bank, edge_onto_m out
# over it, falling off into the floor to a reach that wanders along the
# edge between edge_reach_m's x and y (low-frequency noise at edge_noise_
# wavelength_m), with edge_gap_share of the edge left bare (a second noise
# at edge_gap_wavelength_m) - so it never reads as an even band. The
# density then counts each cell by its weight, and a cluster's item count
# by its centre's (from half at the weakest to full).
@export var edge_falloff: bool = false:
	set(value):
		edge_falloff = value
		emit_changed()
# Full weight this far past the edge onto the bank, fading to none over
# edge_onto_fade_m beyond.
@export var edge_onto_m: float = 1.0:
	set(value):
		edge_onto_m = value
		emit_changed()
@export var edge_onto_fade_m: float = 1.0:
	set(value):
		edge_onto_fade_m = value
		emit_changed()
# Full weight this far into the floor (the foot), then down to none at the
# local reach.
@export var edge_core_m: float = 0.6:
	set(value):
		edge_core_m = value
		emit_changed()
@export var edge_reach_m: Vector2 = Vector2(0.6, 6.0):
	set(value):
		edge_reach_m = value
		emit_changed()
@export var edge_noise_wavelength_m: float = 12.0:
	set(value):
		edge_noise_wavelength_m = value
		emit_changed()
@export_range(0.0, 0.9, 0.01) var edge_gap_share: float = 0.3:
	set(value):
		edge_gap_share = value
		emit_changed()
@export var edge_gap_wavelength_m: float = 8.0:
	set(value):
		edge_gap_wavelength_m = value
		emit_changed()
@export_group("")

@export_group("Cards")
# Painted cards instead of a model: each item one of these, by weight,
# stood up at its card's height times the item's scale_range factor
# (size_m unused), drawn by tuft_card.gdshader - turned to the camera's
# yaw, so never edge-on; the yaw jittered by card_yaw_jitter_degrees,
# half of them mirrored, leaning card_lean_degrees back from the camera.
# Its light reads card_normal_up of the way toward straight up, so it
# lights about as the sand it stands on. Empty = the model above.
@export var cards: Array[ScatterCard] = []:
	set(value):
		for card in cards:
			if card != null and card.changed.is_connected(emit_changed):
				card.changed.disconnect(emit_changed)
		cards = value
		for card in cards:
			if card != null and not card.changed.is_connected(emit_changed):
				card.changed.connect(emit_changed)
		emit_changed()
@export_range(0.0, 45.0, 0.5) var card_yaw_jitter_degrees: float = 12.0:
	set(value):
		card_yaw_jitter_degrees = value
		emit_changed()
@export_range(0.0, 45.0, 0.5) var card_lean_degrees: float = 15.0:
	set(value):
		card_lean_degrees = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var card_normal_up: float = 0.6:
	set(value):
		card_normal_up = value
		emit_changed()
# Two items of a cluster no nearer than this fraction of the wider one's
# width - tufts overlap, but never stand in one spot.
@export_range(0.0, 2.0, 0.01) var card_spacing_fraction: float = 0.35:
	set(value):
		card_spacing_fraction = value
		emit_changed()
# The cutout: texture alpha at or under this is cut away.
@export_range(0.0, 1.0, 0.01) var card_alpha_scissor: float = 0.5:
	set(value):
		card_alpha_scissor = value
		emit_changed()
# Wind on a card, along RegionField.get_wind_direction(), each a fraction
# of the card's height at its top (the base never moves, the bend grows
# with the square of the height up it): a steady lean downwind, `wind`
# (Look) as the slow main sway at wind_sway_hz, and a smaller faster
# flutter, part of it across the wind. The phase from where it stands.
@export_range(0.0, 0.2, 0.001) var wind_lean: float = 0.03:
	set(value):
		wind_lean = value
		emit_changed()
@export var wind_sway_hz: float = 0.33:
	set(value):
		wind_sway_hz = value
		emit_changed()
@export_range(0.0, 0.2, 0.001) var wind_flutter: float = 0.012:
	set(value):
		wind_flutter = value
		emit_changed()
@export var wind_flutter_hz: float = 1.7:
	set(value):
		wind_flutter_hz = value
		emit_changed()
# Faded out while a fight's camera would see a fighter's feet through it
# (FieldScatter.battle_fade_*), back when the fight ends.
@export var battle_fade: bool = false:
	set(value):
		battle_fade = value
		emit_changed()
@export_group("")

@export_group("Contour")
# CONTOUR mode only. The line: this far inland of the water, metres,
# wandering up to contour_wander_m either side along its length.
@export var contour_inland_m: float = 1.8:
	set(value):
		contour_inland_m = value
		emit_changed()
@export var contour_wander_m: float = 0.4:
	set(value):
		contour_wander_m = value
		emit_changed()
# The line's name for its segments' draw - entries naming the same one lie
# along the same broken line. Empty = this entry's own name.
@export var contour_line: String = "":
	set(value):
		contour_line = value
		emit_changed()
# Each segment's length and each gap's, metres, at random from x to y.
@export var segment_length_m: Vector2 = Vector2(1.5, 4.0):
	set(value):
		segment_length_m = value
		emit_changed()
@export var gap_length_m: Vector2 = Vector2(1.0, 3.0):
	set(value):
		gap_length_m = value
		emit_changed()
# Items along a segment this far apart, give or take a third.
@export var contour_spacing_m: float = 0.25:
	set(value):
		contour_spacing_m = value
		emit_changed()
# Each item off the line across it, up to this, metres; and turned along
# the line give or take this many degrees.
@export var contour_across_jitter_m: float = 0.06:
	set(value):
		contour_across_jitter_m = value
		emit_changed()
@export_range(0.0, 90.0, 0.5) var contour_yaw_jitter_degrees: float = 25.0:
	set(value):
		contour_yaw_jitter_degrees = value
		emit_changed()
@export_group("")

@export_group("Density")
# Clusters per 100 square metres of the ground its zones allow, before
# the floor's scatter_density.
@export var clusters_per_100m2: float = 2.0:
	set(value):
		clusters_per_100m2 = value
		emit_changed()
# Exactly this many clusters, a random count from x to y, instead of the
# density (the floor's scatter_density doesn't scale it). x below 0 = use
# the density.
@export var cluster_count: Vector2i = Vector2i(-1, -1):
	set(value):
		cluster_count = value
		emit_changed()
# Items in a cluster, from x to y inclusive.
@export var items_per_cluster: Vector2i = Vector2i(3, 7):
	set(value):
		items_per_cluster = value
		emit_changed()
# The Gaussian spread of a cluster's items about its centre, metres - each
# cluster's own, at random from x to y.
@export var cluster_spread_m: Vector2 = Vector2(0.5, 0.5):
	set(value):
		cluster_spread_m = value
		emit_changed()
@export_group("")
