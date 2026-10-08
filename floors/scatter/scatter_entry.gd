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
# may centre in (FieldScatter classifies every cell into one). DUNE_CREST
# and ROCK_EDGE are reserved for the dry set: nothing is classified so yet.
const ZONE_SHORELINE := 1
const ZONE_POOL_RIM := 2
const ZONE_WET_BAND := 4
const ZONE_OPEN_INTERIOR := 8
const ZONE_DUNE_CREST := 16
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
@export_flags("Shoreline", "Pool rim", "Wet band", "Open interior", "Dune crest", "Rock edge") var zones: int = ZONE_SHORELINE:
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
