extends Node3D
class_name FieldScatter

# The floor's ground scatter - worm casts, shells, stones, samphire - from
# FloorData.scatter_sets: small, still, non-blocking, in sparse clusters
# with open sand between them, densest at the water's edge and rare in the
# open, never on the worn band. RegionField makes one once the exit
# channel is cut (_spawn_floor_scatter()), so the ground, the props, the
# enemies and the gate it keeps clear of all exist.
#
# Placement is deterministic: each entry's own generator, seeded from the
# floor resource's path and the entry's name - never the global one - so
# the same floor lies the same every load, and a live edit to any value
# (an entry's, the floor's scatter_density / scatter_budget, an export
# here) places it all again the same way.
#
# The ground is read once per build onto a grid of sample_step_m cells:
# how far inland, whether the nearest water is a pool, the drawn height,
# the band of the wet-to-dry gradient it falls in (ScatterEntry's zones),
# its weight off the worn band, and whether an exclusion covers it.
# Cluster centres go by Poisson-disc (dart throwing at a spacing from the
# entry's density) over the cells its zones allow; each cluster's items
# fall Gaussian about it, so it thins at its edges, each tested exactly
# where it lands. Kept clear of:
#   - water deeper than the entry's wet_edge_m (the drawn height against
#     the sea - the painted line is ragged);
#   - a stamped standing pool (Ground.set_pool_stamp()) and its damp rim,
#     plus pool_margin_m;
#   - the worn band: nothing within wear_keep_out_m of its centreline
#     (the band's half-width plus its edge noise - the noise itself is
#     the shader's and can't be matched here), coming back over
#     wear_ramp_m; and the floor's painted wear;
#   - every static body's footprint (props, ledges) grown by prop_margin_m
#     - his walk-up to anything stops at that edge - or a ledge's by the
#     entry's own ledge_margin_m, when it has one; the gate's shapes by
#     gate_margin_m; a rock shelf's outline by shelf_margin_m; the spawn
#     by spawn_clear_m;
#   - the battle frame's feet: a lone enemy's body and the ring his stance
#     can land on - every spot RegionField's stance rule can give, its
#     stance_distance_min()..stance_distance() for that enemy (its near
#     edge plus battle_gap_min_m..battle_gap_m), centred on it, widened
#     by feet_margin_m either way; a cluster's line, stance to far member
#     with the line's possible shift, as a capsule; a patrolled pack's
#     waypoints.
# Nothing here has collision: the walk grid, the click and the Wanderer's
# steps never see it.
#
# A CONTOUR entry (a tideline) instead follows the line contour_inland_m
# inland of the water - traced over the same grid (marching squares
# through the cell centres) and chained end to end - broken into
# segments and gaps drawn from the line's own generator, wandering either
# side of it, each item turned along it; tested where it lands as any
# item is.
#
# Drawn as one MultiMeshInstance3D per entry (ScatterMeshes' model - its
# glb or a placeholder - sized to the entry, its thinnest side turned down
# for a stone), on the shared flat material tinted by the entry with each
# item's value jitter as its instance colour - or scatter_sway.gdshader,
# the same rules, for a kind with wind. Set into the sand by its sink
# fraction of its height, tilted to the slope. Scene fog as any prop.
# Shadows only where the entry casts them. A kind with its own colour map
# (colour_map_path) wears it under the painted shader instead, as the
# model props do (PaintedProp), the depth fog laid back over it by its
# fog pass at the props' full share, refilled whenever RegionSky's fog
# changes; a kind may sink by a depth in metres (sink_range_m) and be
# sized from its model (model_scale).
#
# An entry may follow the walkable edge (ScatterEntry's Edge group): each
# cell also carries its signed distance to the floor's ledges - into the
# floor +, onto the bank - (a chamfer distance from the cells their lines
# cross, signed by the spawn's side of each closed ledge) - or, on a floor
# without ledges, to exposed rock's edge; its cluster centres are kept by
# a weight from that distance and two noises of its own.
#
# A wide kind (a stone) may be tested at its edge as well as its centre
# (footprint_test), and be solid: every entry placed after it keeps off
# its items' footprints. An entry may cluster round another's items
# instead of over its zones (around_entries) - tufts in a ring round some
# of the stones - so a set lists its stones first.
#
# An entry with cards (dune-grass tufts - ScatterEntry's Cards group)
# instead stands each item up as one of its painted cards, picked by
# weight, upright whatever the slope: one MultiMeshInstance3D per card on
# tuft_card.gdshader, which turns every card to the camera's yaw - pushed
# here each frame from the live camera - and sways it in the floor's one
# wind (RegionField.get_wind_direction()). Such an entry may keep off
# exposed rock (avoid_rock) and off each enemy's whole stance area
# (stance_clearance_m). With battle_fade, a card fades out while a fight
# holds the frame and it stands between the battle camera and a fighter's
# feet, tall enough to hide them - the sight line from the camera's
# battle eye (CameraRig.get_battle_eye()) down to each foot, read every
# frame as the fighters move - and back in once it doesn't; over the
# camera's battle swing. This node processes through the field's battle
# freeze for that (PROCESS_MODE_ALWAYS).
#
# Every cell also carries the dry ground's marks over its band: ROCK_EDGE
# for sand within rock_edge_width_m of exposed rock (the ground shader's
# rule - steep past Ground.rock_slope_min where rock_mask allows - read
# per cell), DUNE_FLANK for sand sloping past dune_flank_slope_degrees.

signal rebuilt

# A placed item before it has a model: on the drawn surface, its turn
# (the slope, a tilt off it, a yaw) at unit size, how wide it is, and its
# value off the entry's tint (1 = the tint).
class Spot extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var basis: Basis = Basis.IDENTITY
	var size: float = 0.0
	var shade: float = 1.0
	# Set into the sand this far, metres (the entry's sink_range_m); below
	# 0 = by its sink_fraction.
	var sink: float = -1.0
	# A card's (entry.cards): which, its yaw off the camera's, mirrored,
	# and its width - `size` is then its height.
	var card: int = -1
	var card_yaw: float = 0.0
	var mirrored: bool = false
	var width: float = 0.0

# One card's MultiMesh of an entry, and each instance's custom data
# (tuft_card.gdshader's INSTANCE_CUSTOM: yaw, mirror, presence now).
class CardLayer extends RefCounted:
	var entry: ScatterEntry = null
	var instance: MultiMeshInstance3D = null
	var material: ShaderMaterial = null
	var spots: Array[Spot] = []
	var custom: PackedColorArray = PackedColorArray()

# Somewhere nothing lies: a disc, a ring, a capsule (the segment a-b), or
# a polygon grown by a margin.
class KeepOut extends RefCounted:
	enum Kind { DISC, RING, CAPSULE, POLYGON }
	var kind: Kind = Kind.DISC
	var a: Vector2 = Vector2.ZERO
	var b: Vector2 = Vector2.ZERO
	var inner: float = 0.0
	var outer: float = 0.0
	var polygon: PackedVector2Array = PackedVector2Array()
	# A ledge's footprint (a LedgeBarrier segment): an entry may grow it by
	# its own ledge_margin_m instead of `outer`.
	var ledge: bool = false
	# Kept for a fight that rolled (_add_battle_keepouts()): an item it
	# turns away is dropped, not made up elsewhere (see Allowed.BATTLE).
	var battle: bool = false
	# Its shape's bounds, worked out on the first ask - a point outside them
	# grown by the reach skips the exact test (a floor's ledges give
	# hundreds of footprints).
	var _bounds: Rect2 = Rect2()
	var _has_bounds: bool = false

	# `ledge_margin` at or over 0 replaces a ledge's own margin.
	func contains(p: Vector2, ledge_margin: float = -1.0) -> bool:
		var reach: float = ledge_margin if ledge and ledge_margin >= 0.0 else outer
		if not _has_bounds:
			_bounds = _shape_bounds()
			_has_bounds = true
		if not _bounds.grow(reach + 1.0e-3).has_point(p):
			return false
		match kind:
			Kind.DISC:
				return p.distance_to(a) <= reach
			Kind.RING:
				var d: float = p.distance_to(a)
				return d >= inner and d <= reach
			Kind.CAPSULE:
				return FieldScatter.segment_distance(p, a, b) <= reach
			Kind.POLYGON:
				if Geometry2D.is_point_in_polygon(p, polygon):
					return true
				for i in polygon.size():
					if FieldScatter.segment_distance(p, polygon[i], polygon[(i + 1) % polygon.size()]) <= reach:
						return true
		return false

	func _shape_bounds() -> Rect2:
		var box := Rect2(a, Vector2.ZERO)
		if kind == Kind.CAPSULE:
			box = box.expand(b)
		elif kind == Kind.POLYGON and not polygon.is_empty():
			box = Rect2(polygon[0], Vector2.ZERO)
			for point in polygon:
				box = box.expand(point)
		return box

@export_group("Zones")
# The grid the ground is read onto, metres a cell.
@export var sample_step_m: float = 0.5:
	set(value):
		sample_step_m = value
		_queue_rebuild(true)
# Inland of the water line to here is the shoreline (or a pool's rim);
# past it the open interior.
@export var shoreline_width_m: float = 3.0:
	set(value):
		shoreline_width_m = value
		_queue_rebuild(true)
# The wet band: sand drawn no higher than this above the sea. -1 = the
# ground's own (Ground.shore_slope_start).
@export var wet_band_height_m: float = -1.0:
	set(value):
		wet_band_height_m = value
		_queue_rebuild(true)
# Sand this near exposed rock is its edge (ZONE_ROCK_EDGE); a cell is rock
# where the ground's rule gives it this much stone or more.
@export var rock_edge_width_m: float = 1.5:
	set(value):
		rock_edge_width_m = value
		_queue_rebuild(true)
@export_range(0.0, 1.0, 0.01) var rock_threshold: float = 0.5:
	set(value):
		rock_threshold = value
		_queue_rebuild(true)
# Sand sloping past this many degrees is a dune flank (ZONE_DUNE_FLANK).
@export var dune_flank_slope_degrees: float = 8.0:
	set(value):
		dune_flank_slope_degrees = value
		_queue_rebuild(true)
@export_group("")

@export_group("Worn Band")
# Nothing within this of the band's centreline. -1 = the band's own
# half-width, half its edge and both its noises (Ground.wear_half_width +
# wear_edge_width / 2 + wear_edge_noise_amplitude + wear_fray_amplitude)
# - the furthest it is ever drawn.
@export var wear_keep_out_m: float = -1.0:
	set(value):
		wear_keep_out_m = value
		_queue_rebuild(true)
# ...and back to full over this much more.
@export var wear_ramp_m: float = 1.5:
	set(value):
		wear_ramp_m = value
		_queue_rebuild(true)
# Painted wear (FloorData.wear_mask) above this keeps scatter off, fading
# in over 0.2 more.
@export_range(0.0, 1.0, 0.01) var wear_mask_threshold: float = 0.1:
	set(value):
		wear_mask_threshold = value
		_queue_rebuild(true)
@export_group("")

@export_group("Exclusions")
@export var prop_margin_m: float = 0.6:
	set(value):
		prop_margin_m = value
		_queue_rebuild(true)
@export var gate_margin_m: float = 1.5:
	set(value):
		gate_margin_m = value
		_queue_rebuild(true)
@export var shelf_margin_m: float = 0.3:
	set(value):
		shelf_margin_m = value
		_queue_rebuild(true)
@export var spawn_clear_m: float = 1.5:
	set(value):
		spawn_clear_m = value
		_queue_rebuild(true)
# A stamped standing pool (Ground.set_pool_stamp() - the Glower's): nothing
# on it or its damp rim (Ground.pool_stamp_rim), nor within this more.
@export var pool_margin_m: float = 0.15:
	set(value):
		pool_margin_m = value
		_queue_rebuild(false)
# An enemy's body: its model's half-diagonal plus this.
@export var body_margin_m: float = 0.3:
	set(value):
		body_margin_m = value
		_queue_rebuild(true)
# The Wanderer's feet at his stance: this either side of where he can
# stand, and his own radius for a cluster's line.
@export var feet_margin_m: float = 0.6:
	set(value):
		feet_margin_m = value
		_queue_rebuild(true)
@export var wanderer_radius_m: float = 0.4:
	set(value):
		wanderer_radius_m = value
		_queue_rebuild(true)
@export_group("")

@export_group("Battle Fade")
# A card hides a foot when it stands within its half-width plus this of
# the sight line, on the camera's side, its top over the line. Read every
# frame, so a live edit takes at once.
@export var battle_fade_margin_m: float = 0.35
# Seconds to fade out or back. Below 0 = the camera's own battle swing
# (CameraRig.battle_transition_time).
@export var battle_fade_seconds: float = -1.0
@export_group("")

var _field: RegionField = null
var _ground: Ground = null
var _floor: FloorData = null
var _sea_level: float = 0.0
# The spawn as it was when set up - RegionField.get_spawn_position() is
# the Wanderer's live position, and a later rebuild must not follow him.
var _spawn: Vector2 = Vector2.ZERO
var _wear_points: PackedVector2Array = PackedVector2Array()
var _keepouts: Array[KeepOut] = []
# Every enemy where it stands, for an entry's enemy_clearance_m; and as
# (x, z, stance distance) for its stance_clearance_m.
var _enemy_points: PackedVector2Array = PackedVector2Array()
var _enemy_stances: PackedVector3Array = PackedVector3Array()
# Where an item may lie. BATTLE: turned away only by the fights that
# rolled - the battle keep-outs, an entry's enemy_clearance_m and stance_
# clearance_m - so it is dropped but counted as laid: in its entry's count,
# its cluster's spacing and the floor's budget. Every other item then
# lies where it would with no fight there, and no kind takes up another's
# dropped share: each kind's count stays near its own whatever rolled.
enum Allowed { YES, NO, BATTLE }
# Items dropped as Allowed.BATTLE: the floor's, and the entry being placed's.
var _charged_count: int = 0
var _entry_charged: int = 0
# Traced contours by inland level, cleared with the grid.
var _contours: Dictionary = {}
var _rebuild_queued: bool = false
var _grid_dirty: bool = true

# The grid: its corner and size, and per cell (row-major): inland metres,
# drawn height, zone bit, weight off the worn band (0..1), excluded.
var _grid_origin: Vector2 = Vector2.ZERO
var _grid_cols: int = 0
var _grid_rows: int = 0
var _cell_inland: PackedFloat32Array = PackedFloat32Array()
var _cell_height: PackedFloat32Array = PackedFloat32Array()
var _cell_zone: PackedByteArray = PackedByteArray()
var _cell_wear: PackedFloat32Array = PackedFloat32Array()
# Excluded by a keep-out other than a battle one.
var _cell_excluded: PackedByteArray = PackedByteArray()
# Excluded by anything but a ledge, for an entry with its own ledge margin.
var _cell_excluded_off_ledges: PackedByteArray = PackedByteArray()
# Inside a battle keep-out (KeepOut.battle): no cluster centres there.
var _cell_battle: PackedByteArray = PackedByteArray()
var _cell_rock: PackedByteArray = PackedByteArray()
# Signed metres to the walkable edge: into the floor +, onto the bank -.
var _cell_edge: PackedFloat32Array = PackedFloat32Array()
# Metres to the nearest rock cell (_mark_dry_ground()).
var _rock_distance: PackedFloat32Array = PackedFloat32Array()

# Every entry placed, in order, and each one's spots.
var _entries: Array[ScatterEntry] = []
var _spots: Dictionary = {}
var _item_count: int = 0
var _build_msec: int = 0
# The footprints later entries keep off: every item of a solid entry, as
# (x, z, half its width).
var _solids: PackedVector3Array = PackedVector3Array()
# The painted kinds' fog passes, refilled from the sky when its fog changes.
var _fog_passes: Array[ShaderMaterial] = []
var _instances: Array[MultiMeshInstance3D] = []
var _card_layers: Array[CardLayer] = []
# The camera forward last pushed to the cards.
var _card_forward: Vector2 = Vector2.ZERO
# The gust and its sway gain last pushed to the cards.
var _card_gust: Vector2 = Vector2(-1.0, -1.0)

# From RegionField once its exit channel is cut: what to read, and the
# first build, deferred so every prop and enemy has placed itself.
func setup(field: RegionField) -> void:
	_field = field
	# The battle fade runs while the field is frozen for the fight.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ground = field.get_node_or_null(field.ground_path) as Ground
	_floor = field.get_floor_data()
	var spawn: Vector3 = field.get_spawn_position()
	_spawn = Vector2(spawn.x, spawn.z)
	_wear_points = field.get_wear_path()
	var sea := field.get_node_or_null(^"Sea")
	_sea_level = float(sea.get("sea_level")) if sea != null else 0.0
	if _floor != null and not _floor.changed.is_connected(_on_floor_changed):
		_floor.changed.connect(_on_floor_changed)
	if _ground != null and not _ground.relief_rebuilt.is_connected(_on_relief_rebuilt):
		_ground.relief_rebuilt.connect(_on_relief_rebuilt)
	if _ground != null and not _ground.pool_stamps_changed.is_connected(_on_pool_stamps_changed):
		_ground.pool_stamps_changed.connect(_on_pool_stamps_changed)
	var sky: RegionSky = field.get_region_sky()
	if sky != null and not sky.fog_changed.is_connected(_push_fog):
		sky.fog_changed.connect(_push_fog)
	_queue_rebuild(true)

func _exit_tree() -> void:
	if _floor != null and _floor.changed.is_connected(_on_floor_changed):
		_floor.changed.disconnect(_on_floor_changed)

func _on_floor_changed() -> void:
	_queue_rebuild(false)

func _on_relief_rebuilt() -> void:
	_queue_rebuild(true)

func _on_pool_stamps_changed() -> void:
	_queue_rebuild(false)

# One rebuild at the end of the frame however many edits asked; the
# ground's grid only when something it reads has changed.
func _queue_rebuild(grid: bool) -> void:
	_grid_dirty = _grid_dirty or grid
	if _rebuild_queued or _field == null or not is_inside_tree():
		return
	_rebuild_queued = true
	call_deferred("rebuild")

# Reads the ground (when it has changed) and places every entry again.
func rebuild() -> void:
	_rebuild_queued = false
	if _field == null or _ground == null or not _ground.is_built():
		return
	var started: int = Time.get_ticks_msec()
	if _grid_dirty:
		_build_keepouts()
		_build_grid()
		_contours.clear()
		_grid_dirty = false
	_place_all()
	_draw_all()
	_build_msec = Time.get_ticks_msec() - started
	print("FieldScatter: %d items, %d kinds, over a %d x %d grid, in %d ms" % [_item_count, _entries.size(), _grid_cols, _grid_rows, _build_msec])
	rebuilt.emit()

# --- Reading the ground ---

func _build_grid() -> void:
	var rect: Rect2 = _field.get_wall_rect()
	if rect.size == Vector2.ZERO and _ground.has_landmass_mask():
		rect = _ground.get_landmass_bounds()
	var step: float = maxf(sample_step_m, 0.1)
	_grid_origin = rect.position
	_grid_cols = maxi(int(ceil(rect.size.x / step)), 1)
	_grid_rows = maxi(int(ceil(rect.size.y / step)), 1)
	var count: int = _grid_cols * _grid_rows
	_cell_inland.resize(count)
	_cell_height.resize(count)
	_cell_zone.resize(count)
	_cell_wear.resize(count)
	_cell_excluded.resize(count)
	_cell_excluded_off_ledges.resize(count)
	_cell_battle.resize(count)
	_cell_rock.resize(count)
	var wet_band: float = wet_band_height_m if wet_band_height_m >= 0.0 else _ground.shore_slope_start
	for row in _grid_rows:
		for col in _grid_cols:
			var i: int = row * _grid_cols + col
			var p: Vector2 = cell_centre(col, row)
			var inland: float = -_ground.get_landmass_distance(p)
			var height: float = _ground.get_visible_height_at(p)
			_cell_inland[i] = inland
			_cell_height[i] = height
			_cell_zone[i] = _zone_at(p, inland, height, wet_band)
			_cell_wear[i] = wear_weight(p)
			_cell_excluded[i] = 1 if is_excluded(p, -1.0, false) else 0
			_cell_excluded_off_ledges[i] = 1 if _cell_excluded[i] != 0 and _excluded_off_ledges(p) else 0
			_cell_battle[i] = 1 if _in_battle_keepout(p) else 0
	_mark_dry_ground()
	_mark_edge_distance()

# Over each cell's band, the dry ground's marks: its slope from the drawn
# heights either side; rock where the ground shader would draw stone
# there (that slope past Ground.rock_slope_min, ramping over rock_slope_
# blend, times rock_mask) to rock_threshold; ROCK_EDGE on sand within
# rock_edge_width_m of rock (a chamfer distance over the grid), DUNE_FLANK
# on sand sloping past dune_flank_slope_degrees.
func _mark_dry_ground() -> void:
	var step: float = maxf(sample_step_m, 0.1)
	var count: int = _grid_cols * _grid_rows
	var slopes := PackedFloat32Array()
	slopes.resize(count)
	var any_rock: bool = false
	for row in _grid_rows:
		for col in _grid_cols:
			var i: int = row * _grid_cols + col
			var west: int = maxi(col - 1, 0)
			var east: int = mini(col + 1, _grid_cols - 1)
			var north: int = maxi(row - 1, 0)
			var south: int = mini(row + 1, _grid_rows - 1)
			var dx: float = (_cell_height[row * _grid_cols + east] - _cell_height[row * _grid_cols + west]) / (step * float(maxi(east - west, 1)))
			var dz: float = (_cell_height[south * _grid_cols + col] - _cell_height[north * _grid_cols + col]) / (step * float(maxi(south - north, 1)))
			var slope: float = rad_to_deg(atan(Vector2(dx, dz).length()))
			slopes[i] = slope
			var stone: float = smoothstep(_ground.rock_slope_min, _ground.rock_slope_min + maxf(_ground.rock_slope_blend, 0.001), slope) * _ground.get_rock_mask_at(cell_centre(col, row))
			_cell_rock[i] = 1 if stone >= rock_threshold else 0
			any_rock = any_rock or _cell_rock[i] != 0
	var near_rock := PackedFloat32Array()
	near_rock.resize(count)
	near_rock.fill(INF)
	if any_rock:
		for i in count:
			if _cell_rock[i] != 0:
				near_rock[i] = 0.0
		var diagonal: float = step * sqrt(2.0)
		for row in _grid_rows:
			for col in _grid_cols:
				var i: int = row * _grid_cols + col
				if col > 0:
					near_rock[i] = minf(near_rock[i], near_rock[i - 1] + step)
				if row > 0:
					near_rock[i] = minf(near_rock[i], near_rock[i - _grid_cols] + step)
					if col > 0:
						near_rock[i] = minf(near_rock[i], near_rock[i - _grid_cols - 1] + diagonal)
					if col < _grid_cols - 1:
						near_rock[i] = minf(near_rock[i], near_rock[i - _grid_cols + 1] + diagonal)
		for row in range(_grid_rows - 1, -1, -1):
			for col in range(_grid_cols - 1, -1, -1):
				var i: int = row * _grid_cols + col
				if col < _grid_cols - 1:
					near_rock[i] = minf(near_rock[i], near_rock[i + 1] + step)
				if row < _grid_rows - 1:
					near_rock[i] = minf(near_rock[i], near_rock[i + _grid_cols] + step)
					if col < _grid_cols - 1:
						near_rock[i] = minf(near_rock[i], near_rock[i + _grid_cols + 1] + diagonal)
					if col > 0:
						near_rock[i] = minf(near_rock[i], near_rock[i + _grid_cols - 1] + diagonal)
	_rock_distance = near_rock
	for i in count:
		if _cell_rock[i] != 0:
			continue
		if near_rock[i] <= rock_edge_width_m:
			_cell_zone[i] |= ScatterEntry.ZONE_ROCK_EDGE
		if slopes[i] >= dune_flank_slope_degrees:
			_cell_zone[i] |= ScatterEntry.ZONE_DUNE_FLANK

# Each cell's signed distance to the walkable edge - see the header. The
# cells every ledge line crosses are its zero; a chamfer pass spreads the
# distance; a cell on the far side of a closed ledge from the spawn is
# onto the bank. Without ledges: rock's edge - sand +, rock -.
func _mark_edge_distance() -> void:
	var count: int = _grid_cols * _grid_rows
	_cell_edge.resize(count)
	var lines: Array[PackedVector2Array] = []
	if _floor != null:
		for ledge in _floor.ledges:
			var line := PackedVector2Array()
			for point in ledge:
				line.append(_spawn + point)
			if line.size() >= 2:
				lines.append(line)
	if lines.is_empty():
		for i in count:
			var d: float = _rock_distance[i] if not _rock_distance.is_empty() else INF
			if _cell_rock[i] != 0:
				d = -_inside_distance(i)
			_cell_edge[i] = d
		return
	var step: float = maxf(sample_step_m, 0.1)
	var near := PackedFloat32Array()
	near.resize(count)
	near.fill(INF)
	for line in lines:
		for k in line.size() - 1:
			var a: Vector2 = line[k]
			var b: Vector2 = line[k + 1]
			var samples: int = maxi(int(ceil(a.distance_to(b) / (step * 0.5))), 1)
			for n in samples + 1:
				var cell: int = _cell_at(a.lerp(b, float(n) / float(samples)))
				if cell >= 0:
					near[cell] = 0.0
	_chamfer(near, step)
	var spawn_inside: Array[bool] = []
	for line in lines:
		spawn_inside.append(_closed(line) and Geometry2D.is_point_in_polygon(_spawn, line))
	for i in count:
		var p: Vector2 = _grid_point(i)
		var outside: bool = false
		for k in lines.size():
			if _closed(lines[k]) and Geometry2D.is_point_in_polygon(p, lines[k]) != spawn_inside[k]:
				outside = true
				break
		_cell_edge[i] = -near[i] if outside else near[i]

# A rock cell's distance to the nearest sand, for the edge without ledges.
func _inside_distance(cell: int) -> float:
	var col: int = cell % _grid_cols
	var row: int = floori(float(cell) / float(_grid_cols))
	var step: float = maxf(sample_step_m, 0.1)
	for reach in range(1, 9):
		for dr in range(-reach, reach + 1):
			for dc in range(-reach, reach + 1):
				var c: int = col + dc
				var r: int = row + dr
				if c >= 0 and r >= 0 and c < _grid_cols and r < _grid_rows and _cell_rock[r * _grid_cols + c] == 0:
					return float(reach) * step
	return 9.0 * step

static func _closed(line: PackedVector2Array) -> bool:
	return line.size() >= 4 and line[0].distance_to(line[line.size() - 1]) < 0.05

# Two chamfer passes over the grid: each cell the least of its own and
# its neighbours' plus the step between them.
func _chamfer(field: PackedFloat32Array, step: float) -> void:
	var diagonal: float = step * sqrt(2.0)
	for row in _grid_rows:
		for col in _grid_cols:
			var i: int = row * _grid_cols + col
			if col > 0:
				field[i] = minf(field[i], field[i - 1] + step)
			if row > 0:
				field[i] = minf(field[i], field[i - _grid_cols] + step)
				if col > 0:
					field[i] = minf(field[i], field[i - _grid_cols - 1] + diagonal)
				if col < _grid_cols - 1:
					field[i] = minf(field[i], field[i - _grid_cols + 1] + diagonal)
	for row in range(_grid_rows - 1, -1, -1):
		for col in range(_grid_cols - 1, -1, -1):
			var i: int = row * _grid_cols + col
			if col < _grid_cols - 1:
				field[i] = minf(field[i], field[i + 1] + step)
			if row < _grid_rows - 1:
				field[i] = minf(field[i], field[i + _grid_cols] + step)
				if col < _grid_cols - 1:
					field[i] = minf(field[i], field[i + _grid_cols + 1] + diagonal)
				if col > 0:
					field[i] = minf(field[i], field[i + _grid_cols - 1] + diagonal)

# An edge entry's weight per cell (0..1) - see ScatterEntry's Edge group.
# Its two noises seeded from the floor and the entry's name; each read
# over the grid as a rank, so the reach spans its whole range and the gaps
# are their share of the cells.
func _edge_weights(entry: ScatterEntry) -> PackedFloat32Array:
	var count: int = _cell_edge.size()
	var weights := PackedFloat32Array()
	weights.resize(count)
	var reach_noise := FastNoiseLite.new()
	reach_noise.seed = hash("%s:%s:reach" % [_floor.resource_path, entry.name])
	reach_noise.frequency = 1.0 / maxf(entry.edge_noise_wavelength_m, 0.5)
	var gap_noise := FastNoiseLite.new()
	gap_noise.seed = hash("%s:%s:gap" % [_floor.resource_path, entry.name])
	gap_noise.frequency = 1.0 / maxf(entry.edge_gap_wavelength_m, 0.5)
	var reach_raw := PackedFloat32Array()
	var gap_raw := PackedFloat32Array()
	reach_raw.resize(count)
	gap_raw.resize(count)
	for i in count:
		var p: Vector2 = _grid_point(i)
		reach_raw[i] = reach_noise.get_noise_2dv(p)
		gap_raw[i] = gap_noise.get_noise_2dv(p)
	var reach_sorted := reach_raw.duplicate()
	reach_sorted.sort()
	var gap_sorted := gap_raw.duplicate()
	gap_sorted.sort()
	var gap_cut: float = gap_sorted[clampi(int(entry.edge_gap_share * float(count)), 0, count - 1)] if entry.edge_gap_share > 0.0 else -INF
	var gap_soft: float = (gap_sorted[count - 1] - gap_sorted[0]) * 0.04
	for i in count:
		var d: float = _cell_edge[i]
		if is_inf(d):
			continue
		var w: float = 0.0
		if d < 0.0:
			w = 1.0 - smoothstep(entry.edge_onto_m, entry.edge_onto_m + maxf(entry.edge_onto_fade_m, 0.01), -d)
		else:
			var rank: float = float(reach_sorted.bsearch(reach_raw[i])) / float(maxi(count - 1, 1))
			var reach: float = lerpf(entry.edge_reach_m.x, entry.edge_reach_m.y, rank)
			w = 1.0 - smoothstep(entry.edge_core_m, maxf(reach, entry.edge_core_m + 0.01), d)
		w *= smoothstep(gap_cut - gap_soft, gap_cut + gap_soft, gap_raw[i])
		weights[i] = w
	return weights

func get_edge_distance(p: Vector2) -> float:
	var cell: int = _cell_at(p)
	return _cell_edge[cell] if cell >= 0 and cell < _cell_edge.size() else INF

# Whether exposed rock covers a point - its cell's (_mark_dry_ground()).
func is_rock(p: Vector2) -> bool:
	var cell: int = _cell_at(p)
	return cell >= 0 and _cell_rock[cell] != 0

# The band of the wet-to-dry gradient a point falls in: a pool's rim when
# the nearest water is enclosed, else the wet band while drawn low enough,
# else the shoreline out to shoreline_width_m, else the open interior.
func _zone_at(p: Vector2, inland: float, height: float, wet_band: float) -> int:
	if _ground.get_enclosure_at(p) >= 0.5:
		return ScatterEntry.ZONE_POOL_RIM if inland <= shoreline_width_m else ScatterEntry.ZONE_OPEN_INTERIOR
	if height - _sea_level <= wet_band:
		return ScatterEntry.ZONE_WET_BAND
	return ScatterEntry.ZONE_SHORELINE if inland <= shoreline_width_m else ScatterEntry.ZONE_OPEN_INTERIOR

func cell_centre(col: int, row: int) -> Vector2:
	var step: float = maxf(sample_step_m, 0.1)
	return _grid_origin + Vector2((float(col) + 0.5) * step, (float(row) + 0.5) * step)

# --- The worn band ---

# 1 clear of the band, 0 on it: nothing within the keep-out of its
# centreline, back to full over wear_ramp_m; less again where the floor's
# own painted wear is. An entry's own keep-out and ramp (its wear_keep_
# out_m / wear_ramp_m, at or over 0) replace the floor's.
func wear_weight(p: Vector2, keep_out_override: float = -1.0, ramp_override: float = -1.0) -> float:
	var weight: float = 1.0
	if _wear_points.size() >= 3:
		var keep_out: float = keep_out_override if keep_out_override >= 0.0 else get_wear_keep_out()
		var ramp: float = ramp_override if ramp_override >= 0.0 else wear_ramp_m
		weight = smoothstep(keep_out, keep_out + maxf(ramp, 0.001), wear_distance(p))
	var painted: float = _ground.get_wear_mask_at(p)
	if painted > 0.0:
		weight *= 1.0 - smoothstep(wear_mask_threshold, wear_mask_threshold + 0.2, painted)
	return weight

# How far outside a stamped pool's edge nothing goes: its damp rim plus
# pool_margin_m - the pool's keep-out, as get_wear_keep_out() is the band's.
func get_pool_keep_out() -> float:
	return _ground.pool_stamp_rim + pool_margin_m

func in_pool_keep_out(p: Vector2) -> bool:
	return _ground.get_pool_stamp_distance(p) < get_pool_keep_out()

func get_wear_keep_out() -> float:
	if wear_keep_out_m >= 0.0:
		return wear_keep_out_m
	return _ground.wear_half_width + _ground.wear_edge_width * 0.5 + _ground.wear_edge_noise_amplitude + _ground.wear_fray_amplitude

# Distance to the band's centreline - the shader's own curve (ground.
# gdshader wear_distance()): through three points a quadratic Bezier that
# passes the middle one, in 16 segments; through more, a Catmull-Rom chain
# with its ends doubled, 8 steps a span.
func wear_distance(p: Vector2) -> float:
	var best: float = INF
	var count: int = mini(_wear_points.size(), Ground.WEAR_MAX_POINTS)
	if count < 3:
		return best
	if count == 3:
		var start: Vector2 = _wear_points[0]
		var end: Vector2 = _wear_points[2]
		var handle: Vector2 = 2.0 * _wear_points[1] - 0.5 * (start + end)
		var previous: Vector2 = start
		for i in range(1, 17):
			var t: float = float(i) / 16.0
			var u: float = 1.0 - t
			var current: Vector2 = u * u * start + 2.0 * u * t * handle + t * t * end
			best = minf(best, segment_distance(p, previous, current))
			previous = current
		return best
	for span in count - 1:
		var p0: Vector2 = _wear_points[maxi(span - 1, 0)]
		var p1: Vector2 = _wear_points[span]
		var p2: Vector2 = _wear_points[mini(span + 1, count - 1)]
		var p3: Vector2 = _wear_points[mini(span + 2, count - 1)]
		var previous: Vector2 = p1
		for i in range(1, 9):
			var t: float = float(i) / 8.0
			var t2: float = t * t
			var current: Vector2 = 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t)
			best = minf(best, segment_distance(p, previous, current))
			previous = current
	return best

static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var h: float = clampf((p - a).dot(ab) / maxf(ab.dot(ab), 1.0e-6), 0.0, 1.0)
	return (p - a - ab * h).length()

# --- Exclusions ---

# `ledge_margin` at or over 0: ledges' footprints grown by that instead of
# prop_margin_m (an entry's ledge_margin_m). `battle` false leaves the
# battle keep-outs out (KeepOut.battle).
func is_excluded(p: Vector2, ledge_margin: float = -1.0, battle: bool = true) -> bool:
	for keepout in _keepouts:
		if (battle or not keepout.battle) and keepout.contains(p, ledge_margin):
			return true
	return false

func _excluded_off_ledges(p: Vector2) -> bool:
	for keepout in _keepouts:
		if not keepout.ledge and not keepout.battle and keepout.contains(p):
			return true
	return false

func _in_battle_keepout(p: Vector2) -> bool:
	for keepout in _keepouts:
		if keepout.battle and keepout.contains(p):
			return true
	return false

func get_keepouts() -> Array[KeepOut]:
	return _keepouts

func _build_keepouts() -> void:
	_keepouts.clear()
	for shape in _field.get_obstacle_shapes():
		var before: int = _keepouts.size()
		_add_footprint(shape, prop_margin_m)
		if shape.get_parent() is LedgeBarrier and _keepouts.size() > before:
			_keepouts[_keepouts.size() - 1].ledge = true
	var gate := _field.get_node_or_null(_field.exit_gate_path)
	if gate != null:
		for shape in gate.find_children("*", "CollisionShape3D", true, false):
			_add_footprint(shape as CollisionShape3D, gate_margin_m)
	for node in _field.find_children("*", "RockShelf", true, false):
		var shelf := node as RockShelf
		var outline := PackedVector2Array()
		for point in shelf.outline:
			var world: Vector3 = shelf.global_transform * Vector3(point.x, 0.0, point.y)
			outline.append(Vector2(world.x, world.z))
		if outline.size() >= 3:
			_keepouts.append(_polygon(outline, shelf_margin_m))
	_keepouts.append(_disc(_spawn, spawn_clear_m))
	_add_battle_keepouts()

# A collision shape's footprint - its box through its transform, flattened
# to XZ, the hull of the corners (NavGrid.footprint_cells()'s reading) -
# grown by `margin`.
func _add_footprint(shape_node: CollisionShape3D, margin: float) -> void:
	if shape_node == null or shape_node.shape == null or shape_node.disabled:
		return
	var box: AABB = shape_node.shape.get_debug_mesh().get_aabb()
	var points := PackedVector2Array()
	for i in 8:
		var corner: Vector3 = shape_node.global_transform * box.get_endpoint(i)
		points.append(Vector2(corner.x, corner.z))
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() >= 3:
		_keepouts.append(_polygon(hull, margin))
	elif not points.is_empty():
		_keepouts.append(_disc(points[0], margin))

# Where the battle frame puts feet. A lone enemy: its body, and the ring
# his stance lands on whichever way he came. A cluster: the line it
# fights in - from his stance behind the anchor to the far member past
# the line's furthest shift - for each member that could anchor it. A
# patrolled pack: wherever it can be when he reaches it, its waypoints.
func _add_battle_keepouts() -> void:
	var first_battle: int = _keepouts.size()
	_add_battle_keepouts_unmarked()
	for i in range(first_battle, _keepouts.size()):
		_keepouts[i].battle = true

func _add_battle_keepouts_unmarked() -> void:
	var groups: Dictionary = {}
	_enemy_points = PackedVector2Array()
	_enemy_stances = PackedVector3Array()
	for node in _field.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.is_queued_for_deletion() or not _field.is_ancestor_of(enemy):
			continue
		_enemy_points.append(_xz(enemy))
		_enemy_stances.append(Vector3(enemy.global_position.x, enemy.global_position.z, _field.stance_distance(enemy)))
		var key: StringName = enemy.group
		if key == &"":
			_add_lone_keepouts(enemy)
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(enemy)
	# Slot id -> waypoints, the floor's frame (RegionField.get_patrol_
	# routes()); a pack's group is its slot's id.
	var patrolled: Dictionary = _field.get_patrol_routes()
	for key: StringName in groups:
		var members: Array = groups[key]
		if patrolled.has(key):
			_add_patrol_keepouts(members, patrolled[key] as PackedVector2Array)
		elif members.size() == 1:
			_add_lone_keepouts(members[0] as FieldEnemy)
		else:
			_add_cluster_keepouts(members)

func _add_lone_keepouts(enemy: FieldEnemy) -> void:
	var at := Vector2(enemy.global_position.x, enemy.global_position.z)
	_keepouts.append(_disc(at, _half_diagonal(enemy) + body_margin_m))
	var ring := KeepOut.new()
	ring.kind = KeepOut.Kind.RING
	ring.a = at
	ring.inner = maxf(_field.stance_distance_min(enemy) - feet_margin_m, 0.0)
	ring.outer = _field.stance_distance(enemy) + feet_margin_m
	_keepouts.append(ring)

func _add_cluster_keepouts(members: Array) -> void:
	var anchors: Array = []
	var body: float = 0.0
	for member: FieldEnemy in members:
		if member.anchor:
			anchors.append(member)
		body = maxf(body, _half_diagonal(member))
		_keepouts.append(_disc(_xz(member), _half_diagonal(member) + body_margin_m))
	if anchors.is_empty():
		anchors = members
	var radius: float = maxf(body + body_margin_m, wanderer_radius_m + feet_margin_m)
	for anchor: FieldEnemy in anchors:
		var far: FieldEnemy = anchor
		for member: FieldEnemy in members:
			if _xz(member).distance_squared_to(_xz(anchor)) > _xz(far).distance_squared_to(_xz(anchor)):
				far = member
		var along: Vector2 = (_xz(far) - _xz(anchor)).normalized()
		if along == Vector2.ZERO:
			continue
		var gaps: float = 0.0
		for member: FieldEnemy in members:
			if member == anchor:
				continue
			var gap: float = member.enemy_data.cluster_gap_m if member.enemy_data != null else -1.0
			gaps += gap if gap >= 0.0 else _field.cluster_member_gap
		var line := KeepOut.new()
		line.kind = KeepOut.Kind.CAPSULE
		line.a = _xz(anchor) - along * _field.stance_distance(anchor)
		line.b = _xz(anchor) + along * (_field.battle_line_shift_max + gaps)
		line.outer = radius
		_keepouts.append(line)

func _add_patrol_keepouts(members: Array, waypoints: PackedVector2Array) -> void:
	var centroid := Vector2.ZERO
	var body: float = 0.0
	for member: FieldEnemy in members:
		centroid += _xz(member)
		body = maxf(body, _half_diagonal(member))
	centroid /= float(maxi(members.size(), 1))
	var spread: float = 0.0
	for member: FieldEnemy in members:
		spread = maxf(spread, _xz(member).distance_to(centroid))
	var stance: float = 0.0
	for member: FieldEnemy in members:
		stance = maxf(stance, _field.stance_distance(member))
	var reach: float = stance + feet_margin_m + spread + body
	_keepouts.append(_disc(centroid, reach))
	for waypoint in waypoints:
		_keepouts.append(_disc(_spawn + waypoint, reach))

func _half_diagonal(enemy: FieldEnemy) -> float:
	var box: AABB = enemy.get_model_aabb()
	return maxf(Vector2(box.size.x, box.size.z).length() * 0.5, wanderer_radius_m)

static func _xz(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)

static func _disc(at: Vector2, radius: float) -> KeepOut:
	var disc := KeepOut.new()
	disc.kind = KeepOut.Kind.DISC
	disc.a = at
	disc.outer = radius
	return disc

static func _polygon(points: PackedVector2Array, margin: float) -> KeepOut:
	var polygon := KeepOut.new()
	polygon.kind = KeepOut.Kind.POLYGON
	polygon.polygon = points
	polygon.outer = margin
	return polygon

# --- Placing ---

func _place_all() -> void:
	_entries.clear()
	_spots.clear()
	_solids.clear()
	_item_count = 0
	_charged_count = 0
	if _floor == null:
		return
	var budget: int = _floor.scatter_budget
	for scatter_set in _floor.scatter_sets:
		if scatter_set == null:
			continue
		for entry in scatter_set.entries:
			if entry == null or _entries.has(entry):
				continue
			_entries.append(entry)
			var left: int = budget - _item_count - _charged_count if budget > 0 else -1
			_entry_charged = 0
			var spots: Array[Spot] = _place_contour(entry, left) if entry.mode == ScatterEntry.Mode.CONTOUR else _place_entry(entry, left)
			_spots[entry] = spots
			_item_count += spots.size()
			_charged_count += _entry_charged
			if entry.solid:
				for spot in spots:
					_solids.append(Vector3(spot.position.x, spot.position.z, spot.size * 0.5))
			if budget > 0 and _item_count + _charged_count >= budget:
				push_warning("FieldScatter: the floor's budget of %d items is reached at '%s'; the rest are left out." % [budget, entry.name])

# One entry's spots: its clusters' centres over the cells it may centre
# in, then each cluster's items about its centre. `left` items at most
# (-1 = no cap).
func _place_entry(entry: ScatterEntry, left: int) -> Array[Spot]:
	var spots: Array[Spot] = []
	if left == 0:
		return spots
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [_floor.resource_path, entry.name])
	var spread_range := Vector2(minf(entry.cluster_spread_m.x, entry.cluster_spread_m.y), maxf(entry.cluster_spread_m.x, entry.cluster_spread_m.y))
	var centres: Array[Vector2] = []
	var edge_weights: PackedFloat32Array = _edge_weights(entry) if entry.edge_falloff else PackedFloat32Array()
	# Per centre: the footprint its ring of items lies outside (around_
	# entries), 0 for a cluster over the zones.
	var rings := PackedFloat32Array()
	if not entry.around_entries.is_empty():
		for source in _entries:
			if source == entry or not entry.around_entries.has(source.name):
				continue
			for spot in get_spots(source):
				if rng.randf() < entry.around_share:
					centres.append(Vector2(spot.position.x, spot.position.z))
					rings.append(spot.size * 0.5)
	else:
		_zone_centres(entry, rng, spread_range, centres, edge_weights)
		rings.resize(centres.size())
		rings.fill(0.0)
	var base_size: float = base_size_for(entry)
	for c in centres.size():
		var centre: Vector2 = centres[c]
		var count: int = rng.randi_range(mini(entry.items_per_cluster.x, entry.items_per_cluster.y), maxi(entry.items_per_cluster.x, entry.items_per_cluster.y))
		if not edge_weights.is_empty():
			# Fuller where the edge's weight is: half the count at the
			# weakest, all of it at full.
			var cell: int = _cell_at(centre)
			var w: float = edge_weights[cell] if cell >= 0 else 0.0
			count = maxi(roundi(float(count) * lerpf(0.5, 1.0, w)), mini(entry.items_per_cluster.x, entry.items_per_cluster.y))
		var spread: float = rng.randf_range(spread_range.x, spread_range.y)
		var cluster: Array[Vector2] = []
		var cluster_reach: Array[float] = []
		for attempt in count * 4:
			if cluster.size() >= count or (left >= 0 and spots.size() + _entry_charged >= left):
				break
			var offset := Vector2(rng.randfn(0.0, spread), rng.randfn(0.0, spread))
			if rings[c] > 0.0:
				# Out from the footprint's edge by the offset's length, its
				# way round by the offset's direction.
				offset = offset.normalized() * (rings[c] + offset.length()) if offset.length() > 1.0e-6 else Vector2(rings[c], 0.0)
			var p: Vector2 = centre + offset
			# Drawn every attempt, kept or not, so one item's fate never
			# shifts the next's draws.
			var keep_roll: float = rng.randf()
			var yaw: float = rng.randf() * TAU
			var tilt_axis: float = rng.randf() * TAU
			var tilt: float = rng.randf_range(-entry.tilt_jitter_degrees, entry.tilt_jitter_degrees)
			var factor: float = rng.randf_range(entry.scale_range.x, entry.scale_range.y)
			var shade: float = 1.0 + rng.randf_range(-entry.tint_jitter, entry.tint_jitter)
			# Drawn only for a kind that sinks by depth, so every other
			# kind's draws stay as they were.
			var sink: float = rng.randf_range(entry.sink_range_m.x, maxf(entry.sink_range_m.x, entry.sink_range_m.y)) if entry.sink_range_m.x >= 0.0 else -1.0
			var size: float = base_size * factor
			if not entry.cards.is_empty():
				var card_spot: Spot = _card_spot(entry, rng, factor, shade)
				if card_spot == null:
					continue
				var card_allowed: Allowed = _item_allowed(entry, p, keep_roll)
				if card_allowed == Allowed.NO:
					continue
				var reach: float = card_spot.width * entry.card_spacing_fraction
				var card_crowded: bool = false
				for k in cluster.size():
					if cluster[k].distance_to(p) < maxf(reach, cluster_reach[k]):
						card_crowded = true
						break
				if card_crowded:
					continue
				cluster.append(p)
				cluster_reach.append(reach)
				if card_allowed == Allowed.BATTLE:
					_entry_charged += 1
					continue
				card_spot.position = Vector3(p.x, _ground.get_visible_height_at(p), p.y)
				spots.append(card_spot)
				continue
			var allowed: Allowed = _item_allowed(entry, p, keep_roll, size * 0.5 if entry.footprint_test else 0.0)
			if allowed == Allowed.NO:
				continue
			var crowded: bool = false
			for other in cluster:
				if other.distance_to(p) < size * 1.2:
					crowded = true
					break
			if crowded:
				continue
			cluster.append(p)
			if allowed == Allowed.BATTLE:
				_entry_charged += 1
				continue
			var spot := Spot.new()
			spot.position = Vector3(p.x, _ground.get_visible_height_at(p), p.y)
			var jitter := Basis(Vector3(cos(tilt_axis), 0.0, sin(tilt_axis)), deg_to_rad(tilt))
			spot.basis = Basis(Quaternion(Vector3.UP, slope_normal(p))) * jitter * Basis(Vector3.UP, yaw)
			spot.size = size
			spot.shade = shade
			spot.sink = sink
			spots.append(spot)
	return spots

# A zone entry's cluster centres: Poisson-disc over the cells it may
# centre in (inside its area, when it has one), as many as its count or
# its density over that ground gives - an edge entry's each kept by its
# cell's weight (`weights`, empty for any other), its ground counted by
# them.
func _zone_centres(entry: ScatterEntry, rng: RandomNumberGenerator, spread_range: Vector2, centres: Array[Vector2], weights: PackedFloat32Array) -> void:
	var step: float = maxf(sample_step_m, 0.1)
	var cells := PackedInt32Array()
	var polygon := PackedVector2Array()
	for point in entry.area:
		polygon.append(_spawn + point)
	var weighted: float = 0.0
	for i in _cell_zone.size():
		if not weights.is_empty() and weights[i] <= 0.0:
			continue
		if _centre_allowed(entry, i) and (polygon.size() < 3 or Geometry2D.is_point_in_polygon(_grid_point(i), polygon)):
			cells.append(i)
			weighted += weights[i] if not weights.is_empty() else 1.0
	if cells.is_empty():
		return
	var area: float = weighted * step * step
	var target: int = 0
	if entry.cluster_count.x >= 0:
		target = rng.randi_range(entry.cluster_count.x, maxi(entry.cluster_count.x, entry.cluster_count.y))
	else:
		var expected: float = area / 100.0 * maxf(entry.clusters_per_100m2, 0.0) * maxf(_floor.scatter_density, 0.0)
		target = floori(expected + rng.randf())
	if target <= 0:
		return
	# Poisson-disc by dart throwing: centres no nearer each other than a
	# share of the spacing the density would give spread evenly.
	var spacing: float = maxf(0.6 * sqrt(area / float(target)), spread_range.y * 2.0)
	# An edge entry keeps a centre by its cell's weight - more throws for it.
	var throws: int = target * (90 if not weights.is_empty() else 30)
	for attempt in throws:
		if centres.size() >= target:
			break
		var cell: int = cells[rng.randi_range(0, cells.size() - 1)]
		var p: Vector2 = cell_centre(cell % _grid_cols, floori(float(cell) / float(_grid_cols))) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * step
		if not weights.is_empty() and rng.randf() >= weights[cell]:
			continue
		var clear: bool = true
		for other in centres:
			if other.distance_to(p) < spacing:
				clear = false
				break
		if clear:
			centres.append(p)

# An item's width across at a scale factor of 1: its model's own, turned
# to rest, times model_scale when that is set; else size_m.
static func base_size_for(entry: ScatterEntry) -> float:
	if entry.model_scale <= 0.0 or not entry.cards.is_empty():
		return entry.size_m
	var mesh: Mesh = ScatterMeshes.mesh_for(entry)
	var box: AABB = Transform3D(rest_basis(entry, mesh.get_aabb()), Vector3.ZERO) * mesh.get_aabb()
	return maxf(box.size.x, box.size.z) * entry.model_scale

# A card item's own draws - which card by weight, mirrored or not, its yaw
# off the camera's - made whether it's kept or not; null when the entry's
# cards can't be read. Upright: a tuft grows up, whatever the slope.
func _card_spot(entry: ScatterEntry, rng: RandomNumberGenerator, factor: float, shade: float) -> Spot:
	var pick: float = rng.randf()
	var mirror_roll: float = rng.randf()
	var yaw: float = deg_to_rad(rng.randf_range(-entry.card_yaw_jitter_degrees, entry.card_yaw_jitter_degrees))
	var total: float = 0.0
	for card in entry.cards:
		if card != null:
			total += maxf(card.weight, 0.0)
	if total <= 0.0:
		return null
	var index: int = -1
	var running: float = 0.0
	for k in entry.cards.size():
		var card: ScatterCard = entry.cards[k]
		if card == null or card.weight <= 0.0:
			continue
		index = k
		running += card.weight
		if pick * total < running:
			break
	var aspect: float = ScatterMeshes.card_aspect(entry.cards[index])
	if aspect <= 0.0:
		return null
	var spot := Spot.new()
	spot.card = index
	spot.size = entry.cards[index].height_m * factor
	spot.width = spot.size * aspect
	spot.card_yaw = yaw
	spot.mirrored = mirror_roll < 0.5
	spot.shade = shade
	return spot

# A cell a cluster of `entry` may centre in: one of its zones, inside its
# inland range, dry enough, clear of every exclusion and fully off the
# worn band (by its own keep-out when it has one).
func _centre_allowed(entry: ScatterEntry, cell: int) -> bool:
	if (_cell_zone[cell] & entry.zones) == 0:
		return false
	if in_pool_keep_out(_grid_point(cell)):
		return false
	if _has_own_wear(entry):
		if wear_weight(_grid_point(cell), _entry_keep_out(entry), entry.wear_ramp_m) < 1.0:
			return false
	elif _cell_wear[cell] < 1.0:
		return false
	if entry.ledge_margin_m < 0.0:
		if _cell_excluded[cell] != 0:
			return false
	elif _cell_excluded_off_ledges[cell] != 0 or (_cell_excluded[cell] != 0 and is_excluded(_grid_point(cell), entry.ledge_margin_m, false)):
		return false
	if entry.avoid_rock and _cell_rock[cell] != 0:
		return false
	# Off the fights as well: a cluster centres where it can lie whole.
	if _cell_battle[cell] != 0:
		return false
	var inland: float = _cell_inland[cell]
	if inland < entry.inland_range_m.x or inland > entry.inland_range_m.y:
		return false
	var over_land: float = _cell_height[cell] - _sea_level - (_ground.landmass_interior_height if _ground != null else 0.0)
	if over_land < entry.height_range_m.x or over_land > entry.height_range_m.y:
		return false
	return _cell_height[cell] >= _sea_level - entry.wet_edge_m

# Where one item lands, tested there: dry enough, clear of every
# exclusion and every solid footprint placed before it, and off the worn
# band - on its ramp kept by its weight against `keep_roll`, so the band's
# edge thins rather than cuts. With a `radius` (a footprint_test kind),
# eight points round that circle are tested as well, the band's weight
# the least of them.
# Allowed.BATTLE when the only thing in the way is a fight that rolled
# (see Allowed).
func _item_allowed(entry: ScatterEntry, p: Vector2, keep_roll: float, radius: float = 0.0) -> Allowed:
	for solid in _solids:
		if p.distance_to(Vector2(solid.x, solid.y)) < solid.z + radius:
			return Allowed.NO
	var points: PackedVector2Array = [p]
	if radius > 0.0:
		for k in 8:
			points.append(p + Vector2.from_angle(TAU * float(k) / 8.0) * radius)
	var weight: float = 1.0
	var battle: bool = false
	for q in points:
		var allowed: Allowed = _point_allowed(entry, q)
		if allowed == Allowed.NO:
			return Allowed.NO
		battle = battle or allowed == Allowed.BATTLE
		if _has_own_wear(entry):
			weight = minf(weight, wear_weight(q, _entry_keep_out(entry), entry.wear_ramp_m))
		else:
			weight = minf(weight, wear_weight(q))
	if keep_roll >= weight:
		return Allowed.NO
	return Allowed.BATTLE if battle else Allowed.YES

# Everything but the fights first, so Allowed.BATTLE means only they
# stand in the way.
func _point_allowed(entry: ScatterEntry, p: Vector2) -> Allowed:
	if _ground.get_visible_height_at(p) < _sea_level - entry.wet_edge_m:
		return Allowed.NO
	if in_pool_keep_out(p):
		return Allowed.NO
	if is_excluded(p, entry.ledge_margin_m, false):
		return Allowed.NO
	if entry.avoid_rock and is_rock(p):
		return Allowed.NO
	if _in_battle_keepout(p):
		return Allowed.BATTLE
	if entry.enemy_clearance_m > 0.0:
		for at in _enemy_points:
			if p.distance_to(at) < entry.enemy_clearance_m:
				return Allowed.BATTLE
	if entry.stance_clearance_m >= 0.0:
		for stance in _enemy_stances:
			if p.distance_to(Vector2(stance.x, stance.y)) < stance.z + entry.stance_clearance_m:
				return Allowed.BATTLE
	return Allowed.YES

static func _has_own_wear(entry: ScatterEntry) -> bool:
	return entry.wear_keep_out_share >= 0.0 or entry.wear_keep_out_m >= 0.0 or entry.wear_ramp_m >= 0.0

# An entry's own keep-out from the band's centreline: its share of the
# floor's (so it follows the band's width), else its metres, else -1
# (the floor's).
func _entry_keep_out(entry: ScatterEntry) -> float:
	if entry.wear_keep_out_share >= 0.0:
		return get_wear_keep_out() * entry.wear_keep_out_share
	return entry.wear_keep_out_m

# --- Contours ---

# One CONTOUR entry's spots: along each traced line at its inland
# distance, segments and gaps from the line's own generator (shared by
# every entry naming the same contour_line, so they break together), the
# line wandering either side by contour_wander_m; within a segment an item
# every contour_spacing_m (give or take a third), off the line by up to
# contour_across_jitter_m, turned along it give or take contour_yaw_
# jitter_degrees. Each tested where it lands, and in the entry's zones.
func _place_contour(entry: ScatterEntry, left: int) -> Array[Spot]:
	var spots: Array[Spot] = []
	if left == 0 or entry.contour_spacing_m <= 0.0:
		return spots
	var line_name: String = entry.contour_line if not entry.contour_line.is_empty() else entry.name
	var line_rng := RandomNumberGenerator.new()
	line_rng.seed = hash("%s:line:%s" % [_floor.resource_path, line_name])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:%s" % [_floor.resource_path, entry.name])
	var segment_range := Vector2(minf(entry.segment_length_m.x, entry.segment_length_m.y), maxf(entry.segment_length_m.x, entry.segment_length_m.y))
	var gap_range := Vector2(minf(entry.gap_length_m.x, entry.gap_length_m.y), maxf(entry.gap_length_m.x, entry.gap_length_m.y))
	for line in contour_lines(entry.contour_inland_m):
		var lengths := PackedFloat32Array([0.0])
		for i in range(1, line.size()):
			lengths.append(lengths[i - 1] + line[i - 1].distance_to(line[i]))
		var total: float = lengths[lengths.size() - 1]
		var phase_a: float = line_rng.randf() * TAU
		var phase_b: float = line_rng.randf() * TAU
		# Start part-way through a segment or a gap, so no line begins on
		# a break at its very end.
		var inside: bool = line_rng.randf() < 0.5
		var at: float = -line_rng.randf() * (segment_range.y if inside else gap_range.y)
		while at < total:
			var length: float = line_rng.randf_range(segment_range.x, segment_range.y) if inside else line_rng.randf_range(gap_range.x, gap_range.y)
			if inside:
				var along: float = maxf(at, 0.0) + rng.randf() * entry.contour_spacing_m * 0.5
				while along < minf(at + length, total):
					if left >= 0 and spots.size() + _entry_charged >= left:
						return spots
					var next: float = along + entry.contour_spacing_m * rng.randf_range(0.67, 1.33)
					var spot: Spot = _contour_spot(entry, rng, line, lengths, along, phase_a, phase_b)
					if spot != null:
						spots.append(spot)
					along = next
			at += length
			inside = not inside
	return spots

# One item at `along` metres down `line`: every draw made whether it's
# kept or not, so one item's fate never shifts the next's.
func _contour_spot(entry: ScatterEntry, rng: RandomNumberGenerator, line: PackedVector2Array, lengths: PackedFloat32Array, along: float, phase_a: float, phase_b: float) -> Spot:
	var across_jitter: float = rng.randf_range(-entry.contour_across_jitter_m, entry.contour_across_jitter_m)
	var yaw_jitter: float = deg_to_rad(rng.randf_range(-entry.contour_yaw_jitter_degrees, entry.contour_yaw_jitter_degrees))
	var flip: float = PI if rng.randf() < 0.5 else 0.0
	var keep_roll: float = rng.randf()
	var tilt_axis: float = rng.randf() * TAU
	var tilt: float = rng.randf_range(-entry.tilt_jitter_degrees, entry.tilt_jitter_degrees)
	var factor: float = rng.randf_range(entry.scale_range.x, entry.scale_range.y)
	var shade: float = 1.0 + rng.randf_range(-entry.tint_jitter, entry.tint_jitter)
	var i: int = 1
	while i < lengths.size() - 1 and lengths[i] < along:
		i += 1
	var a: Vector2 = line[i - 1]
	var b: Vector2 = line[i]
	var span: float = maxf(lengths[i] - lengths[i - 1], 1.0e-6)
	var tangent: Vector2 = (b - a) / span
	var normal := Vector2(-tangent.y, tangent.x)
	var wander: float = contour_wander(entry, along, phase_a, phase_b)
	var p: Vector2 = a.lerp(b, clampf((along - lengths[i - 1]) / span, 0.0, 1.0)) + normal * (wander + across_jitter)
	var cell: int = _cell_at(p)
	if cell < 0 or (_cell_zone[cell] & entry.zones) == 0:
		return null
	var allowed: Allowed = _item_allowed(entry, p, keep_roll)
	if allowed == Allowed.NO:
		return null
	if allowed == Allowed.BATTLE:
		_entry_charged += 1
		return null
	var spot := Spot.new()
	spot.position = Vector3(p.x, _ground.get_visible_height_at(p), p.y)
	var jitter := Basis(Vector3(cos(tilt_axis), 0.0, sin(tilt_axis)), deg_to_rad(tilt))
	# Its length - the model's X - along the line.
	var yaw: float = atan2(-tangent.y, tangent.x) + yaw_jitter + flip
	spot.basis = Basis(Quaternion(Vector3.UP, slope_normal(p))) * jitter * Basis(Vector3.UP, yaw)
	spot.size = entry.size_m * factor
	spot.shade = shade
	return spot

# How far off its traced line a contour wanders at `along` metres down it:
# two slow sines, at most contour_wander_m.
static func contour_wander(entry: ScatterEntry, along: float, phase_a: float, phase_b: float) -> float:
	return entry.contour_wander_m * (0.6 * sin(along / 3.1 + phase_a) + 0.4 * sin(along / 1.3 + phase_b))

# The grid cell under a point, or -1 off the grid.
func _cell_at(p: Vector2) -> int:
	var step: float = maxf(sample_step_m, 0.1)
	var col: int = floori((p.x - _grid_origin.x) / step)
	var row: int = floori((p.y - _grid_origin.y) / step)
	if col < 0 or row < 0 or col >= _grid_cols or row >= _grid_rows:
		return -1
	return row * _grid_cols + col

# The lines `level` metres inland of the water, as polylines in world XZ:
# marching squares over the grid's cell centres, each crossing on an edge
# between two cells, chained edge to edge (a saddle split by its centre).
# Lines under a metre are dropped. Cached per level until the grid is read
# again.
func contour_lines(level: float) -> Array[PackedVector2Array]:
	var lines: Array[PackedVector2Array] = []
	if _contours.has(level):
		lines.assign(_contours[level])
		return lines
	var points: Dictionary = {}
	var links: Dictionary = {}
	var ends: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(3, 2), Vector2i(0, 3)]
	for row in _grid_rows - 1:
		for col in _grid_cols - 1:
			var corners: Array[int] = [row * _grid_cols + col, row * _grid_cols + col + 1, (row + 1) * _grid_cols + col + 1, (row + 1) * _grid_cols + col]
			var values: Array[float] = []
			for corner in corners:
				values.append(_cell_inland[corner] - level)
			# Edges: 0 top (corner 0-1), 1 right (1-2), 2 bottom (3-2), 3 left (0-3).
			var keys: Array[int] = [_edge_key(col, row, true), _edge_key(col + 1, row, false), _edge_key(col, row + 1, true), _edge_key(col, row, false)]
			var crossed: Array[int] = []
			for edge in 4:
				var v0: float = values[ends[edge].x]
				var v1: float = values[ends[edge].y]
				if (v0 >= 0.0) != (v1 >= 0.0):
					crossed.append(edge)
					if not points.has(keys[edge]):
						var t: float = v0 / (v0 - v1)
						points[keys[edge]] = _grid_point(corners[ends[edge].x]).lerp(_grid_point(corners[ends[edge].y]), t)
			if crossed.size() == 2:
				_link(links, keys[crossed[0]], keys[crossed[1]])
			elif crossed.size() == 4:
				var centre: float = (values[0] + values[1] + values[2] + values[3]) * 0.25
				if (centre >= 0.0) == (values[0] >= 0.0):
					_link(links, keys[0], keys[1])
					_link(links, keys[2], keys[3])
				else:
					_link(links, keys[0], keys[3])
					_link(links, keys[1], keys[2])
	var visited: Dictionary = {}
	# Open lines from their ends first, then the closed loops left over;
	# the keys in a fixed order so the lines come out the same every time.
	var starts: Array = links.keys()
	starts.sort()
	for pass_index in 2:
		for start: int in starts:
			if visited.has(start) or (pass_index == 0 and (links[start] as Array).size() != 1):
				continue
			var line := PackedVector2Array()
			var previous: int = -1
			var current: int = start
			while current != -1 and not visited.has(current):
				visited[current] = true
				line.append(points[current])
				var next: int = -1
				for neighbour: int in links[current]:
					if neighbour != previous and not visited.has(neighbour):
						next = neighbour
						break
				previous = current
				current = next
			var length: float = 0.0
			for i in range(1, line.size()):
				length += line[i - 1].distance_to(line[i])
			if length >= 1.0:
				lines.append(line)
	_contours[level] = lines
	return lines

func _edge_key(col: int, row: int, horizontal: bool) -> int:
	return (row * (_grid_cols + 1) + col) * 2 + (0 if horizontal else 1)

func _grid_point(cell: int) -> Vector2:
	return cell_centre(cell % _grid_cols, floori(float(cell) / float(_grid_cols)))

static func _link(links: Dictionary, a: int, b: int) -> void:
	if not links.has(a):
		links[a] = []
	if not links.has(b):
		links[b] = []
	(links[a] as Array).append(b)
	(links[b] as Array).append(a)

# The drawn surface's normal at a point, from its heights either side.
func slope_normal(p: Vector2) -> Vector3:
	var e: float = 0.2
	var dx: float = _ground.get_visible_height_at(p + Vector2(e, 0.0)) - _ground.get_visible_height_at(p - Vector2(e, 0.0))
	var dz: float = _ground.get_visible_height_at(p + Vector2(0.0, e)) - _ground.get_visible_height_at(p - Vector2(0.0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()

# --- Drawing ---

const SWAY_SHADER_PATH := "res://field/scatter_sway.gdshader"

func _draw_all() -> void:
	for instance in _instances:
		if is_instance_valid(instance):
			remove_child(instance)
			instance.free()
	_instances.clear()
	_card_layers.clear()
	_fog_passes.clear()
	_card_forward = Vector2.ZERO
	for entry in _entries:
		var spots: Array[Spot] = get_spots(entry)
		if spots.is_empty():
			continue
		if not entry.cards.is_empty():
			_draw_cards(entry, spots)
			continue
		var mesh: Mesh = ScatterMeshes.mesh_for(entry)
		var instance := MultiMeshInstance3D.new()
		instance.name = "Scatter_%s" % entry.name.validate_node_name()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if entry.cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.multimesh = _multimesh(entry, mesh, spots)
		instance.material_override = _material(entry, mesh)
		add_child(instance)
		_instances.append(instance)

# Every spot of an entry as an instance: the model turned to rest, its
# base centred on the origin and lowered by sink_fraction of its height
# (or by the spot's own sink, metres, after scaling),
# scaled to the spot's size across, then the spot's own turn and place;
# its colour the spot's value off the tint.
func _multimesh(entry: ScatterEntry, mesh: Mesh, spots: Array[Spot]) -> MultiMesh:
	var rest: Basis = rest_basis(entry, mesh.get_aabb())
	var box: AABB = Transform3D(rest, Vector3.ZERO) * mesh.get_aabb()
	var across: float = maxf(maxf(box.size.x, box.size.z), 1.0e-6)
	var base := Vector3(box.get_center().x, box.position.y + box.size.y * entry.sink_fraction, box.get_center().z)
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = spots.size()
	var bottom := Vector3(base.x, box.position.y, base.z)
	for i in spots.size():
		var spot: Spot = spots[i]
		var sized := Transform3D(Basis.from_scale(Vector3.ONE * (spot.size / across)), Vector3.ZERO)
		if spot.sink >= 0.0:
			# Its base on the sand, then down its own up by the depth.
			var sunk: Vector3 = spot.position - spot.basis.y.normalized() * spot.sink
			multimesh.set_instance_transform(i, Transform3D(spot.basis, sunk) * sized * Transform3D(rest, -bottom))
		else:
			multimesh.set_instance_transform(i, Transform3D(spot.basis, spot.position) * sized * Transform3D(rest, -base))
		# The jitter is a display value; the instance colour multiplies in
		# linear.
		multimesh.set_instance_color(i, Color(spot.shade, spot.shade, spot.shade).srgb_to_linear())
	return multimesh

# How a model is turned to rest before anything else: its thinnest axis
# up for FLATTEST_SIDE (a stone on its flattest side); as made otherwise -
# a cast lies flat as modelled, a shell is modelled dome up.
static func rest_basis(entry: ScatterEntry, box: AABB) -> Basis:
	if entry.resting != ScatterEntry.Resting.FLATTEST_SIDE:
		return Basis.IDENTITY
	if box.size.x < box.size.y and box.size.x <= box.size.z:
		return Basis(Vector3.BACK, PI * 0.5)
	if box.size.z < box.size.y and box.size.z < box.size.x:
		return Basis(Vector3.RIGHT, PI * 0.5)
	return Basis.IDENTITY

# The shared flat material (Hull._get_shared_flat_material()), tinted,
# reading the instance colour as albedo - or the sway shader's same rules
# for a kind with wind; or, for a kind with a colour map, the painted
# material with its fog pass (the flat one if the map won't load).
func _material(entry: ScatterEntry, mesh: Mesh) -> Material:
	if not entry.colour_map_path.is_empty():
		var painted: ShaderMaterial = PaintedProp.material(entry.colour_map_path, entry.tint)
		if painted != null:
			var fog: ShaderMaterial = PaintedProp.fog_pass()
			if fog != null:
				painted.next_pass = fog
				_fog_passes.append(fog)
				PaintedProp.push_fog(fog, _field.get_region_sky(), 1.0)
			return painted
	if entry.wind > 0.0:
		var sway := ShaderMaterial.new()
		sway.shader = load(SWAY_SHADER_PATH) as Shader
		sway.set_shader_parameter("tint", entry.tint)
		sway.set_shader_parameter("sway_amount", entry.wind)
		sway.set_shader_parameter("sway_height", mesh.get_aabb().size.y)
		return sway
	var flat := Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	flat.vertex_color_use_as_albedo = true
	flat.albedo_color = entry.tint
	return flat

# Every painted kind's fog pass from the sky's fog as it stands - the
# props' full share.
func _push_fog() -> void:
	if _field == null:
		return
	for fog in _fog_passes:
		PaintedProp.push_fog(fog, _field.get_region_sky(), 1.0)

const CARD_SHADER_PATH := "res://field/tuft_card.gdshader"

# A card entry's spots, one MultiMeshInstance3D per card they use: each
# instance at its spot, scaled from the card's height to its own, its
# base lowered by sink_fraction of that; its colour the value jitter, its
# custom data (yaw, mirror, presence 1).
func _draw_cards(entry: ScatterEntry, spots: Array[Spot]) -> void:
	var shader := load(CARD_SHADER_PATH) as Shader
	for index in entry.cards.size():
		var card: ScatterCard = entry.cards[index]
		var mine: Array[Spot] = []
		for spot in spots:
			if spot.card == index:
				mine.append(spot)
		if mine.is_empty() or card == null:
			continue
		var mesh: Mesh = ScatterMeshes.card_mesh(card)
		var texture: Texture2D = ScatterMeshes.card_texture(card)
		if mesh == null or texture == null or shader == null:
			continue
		var layer := CardLayer.new()
		layer.entry = entry
		layer.spots = mine
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = true
		multimesh.use_custom_data = true
		multimesh.mesh = mesh
		multimesh.instance_count = mine.size()
		layer.custom.resize(mine.size())
		for i in mine.size():
			var spot: Spot = mine[i]
			var factor: float = spot.size / maxf(card.height_m, 1.0e-6)
			var sunk := Vector3(0.0, spot.size * entry.sink_fraction, 0.0)
			multimesh.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ONE * factor), spot.position - sunk))
			multimesh.set_instance_color(i, Color(spot.shade, spot.shade, spot.shade).srgb_to_linear())
			layer.custom[i] = Color(spot.card_yaw, -1.0 if spot.mirrored else 1.0, 1.0, 0.0)
			multimesh.set_instance_custom_data(i, layer.custom[i])
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("albedo_texture", texture)
		material.set_shader_parameter("albedo_tint", entry.tint)
		material.set_shader_parameter("alpha_scissor", entry.card_alpha_scissor)
		material.set_shader_parameter("card_height", card.height_m)
		material.set_shader_parameter("lean_degrees", entry.card_lean_degrees)
		material.set_shader_parameter("normal_up", entry.card_normal_up)
		var wind: Vector3 = _field.get_wind_direction()
		material.set_shader_parameter("wind_direction", Vector2(wind.x, wind.z))
		material.set_shader_parameter("wind_lean", entry.wind_lean)
		material.set_shader_parameter("sway_amount", entry.wind)
		material.set_shader_parameter("sway_hz", entry.wind_sway_hz)
		material.set_shader_parameter("flutter_amount", entry.wind_flutter)
		material.set_shader_parameter("flutter_hz", entry.wind_flutter_hz)
		layer.material = material
		var instance := MultiMeshInstance3D.new()
		instance.name = "Scatter_%s_%d" % [entry.name.validate_node_name(), index]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if entry.cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.multimesh = multimesh
		instance.material_override = material
		add_child(instance)
		layer.instance = instance
		_instances.append(instance)
		_card_layers.append(layer)
	_push_card_forward()
	_card_gust = Vector2(-1.0, -1.0)
	_push_card_gust()

func _process(delta: float) -> void:
	if _card_layers.is_empty():
		return
	_push_card_forward()
	_push_card_gust()
	_advance_battle_fade(delta)

# The floor's gust (RegionField.get_gust()) and its FloorWindData.gust_
# sway_gain into every card's material, when either has changed - the
# tufts lean and sway harder as it rises.
func _push_card_gust() -> void:
	if _field == null:
		return
	var floor_data: FloorData = _field.get_floor_data()
	var gain: float = floor_data.wind.gust_sway_gain if floor_data != null and floor_data.wind != null else 0.0
	var now := Vector2(_field.get_gust(), gain)
	if now.is_equal_approx(_card_gust):
		return
	_card_gust = now
	for layer in _card_layers:
		layer.material.set_shader_parameter("gust", now.x)
		layer.material.set_shader_parameter("gust_sway_gain", now.y)

# The live camera's forward on the ground into every card's material, when
# it has moved - a camera looking straight down keeps the last.
func _push_card_forward() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return
	var forward: Vector3 = -camera.global_transform.basis.z
	var ground := Vector2(forward.x, forward.z)
	if ground.length() < 1.0e-4:
		return
	ground = ground.normalized()
	if _card_forward != Vector2.ZERO and ground.distance_to(_card_forward) < 1.0e-4:
		return
	_card_forward = ground
	for layer in _card_layers:
		layer.material.set_shader_parameter("camera_forward", ground)

# Every battle_fade card toward gone while a fight holds the frame and it
# hides a fighter's feet from the battle eye (hides_feet()), toward whole
# otherwise, at one fade a battle_fade_seconds.
func _advance_battle_fade(delta: float) -> void:
	var rig: CameraRig = null
	if _field != null:
		rig = _field.get_node_or_null(_field.camera_rig_path) as CameraRig
	var framing: bool = rig != null and rig.is_battle_framing()
	var eye := Vector3.ZERO
	var feet := PackedVector3Array()
	if framing:
		eye = rig.get_battle_eye()
		feet = rig.get_battle_feet()
	var seconds: float = battle_fade_seconds
	if seconds < 0.0:
		seconds = rig.battle_transition_time if rig != null else 0.6
	var step: float = delta / maxf(seconds, 1.0e-3)
	for layer in _card_layers:
		if not layer.entry.battle_fade:
			continue
		for i in layer.spots.size():
			var target: float = 0.0 if framing and hides_feet(layer.spots[i], eye, feet) else 1.0
			var custom: Color = layer.custom[i]
			if custom.b == target:
				continue
			custom.b = move_toward(custom.b, target, step)
			layer.custom[i] = custom
			layer.instance.multimesh.set_instance_custom_data(i, custom)

# Whether a card at `spot` hides any of `feet` from `eye`: on the camera's
# side of the foot, within its half-width plus battle_fade_margin_m of the
# sight line across, its top over the line where it stands.
func hides_feet(spot: Spot, eye: Vector3, feet: PackedVector3Array) -> bool:
	var at := Vector2(spot.position.x, spot.position.z)
	var top: float = spot.position.y + spot.size
	var reach: float = spot.width * 0.5 + battle_fade_margin_m
	for foot in feet:
		var to_eye := Vector2(eye.x - foot.x, eye.z - foot.z)
		var run: float = to_eye.length()
		if run < 1.0e-3:
			continue
		var direction: Vector2 = to_eye / run
		var offset: Vector2 = at - Vector2(foot.x, foot.z)
		var along: float = offset.dot(direction)
		if along < -reach or along > run:
			continue
		if absf(offset.cross(direction)) > reach:
			continue
		var sight: float = foot.y + maxf(along, 0.0) * (eye.y - foot.y) / run
		if top > sight:
			return true
	return false

func get_card_layers() -> Array[CardLayer]:
	return _card_layers

func get_instances() -> Array[MultiMeshInstance3D]:
	return _instances

# --- Reading the result ---

func get_entries() -> Array[ScatterEntry]:
	return _entries

func get_spots(entry: ScatterEntry) -> Array[Spot]:
	var spots: Array[Spot] = []
	if _spots.has(entry):
		spots.assign(_spots[entry])
	return spots

func get_item_count() -> int:
	return _item_count

# Every cell centre of dry open sand (ShoreFlock's ground): in one of
# `zones` (0 = any) within `inland` of the water, path_distance from the
# worn band's centreline, clear of every keep-out, exposed rock and solid
# scatter, and stance_clearance beyond each enemy's stance distance.
func open_ground(zones: int, inland: Vector2, path_distance: Vector2, stance_clearance: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in _cell_zone.size():
		if zones != 0 and (_cell_zone[i] & zones) == 0:
			continue
		if _cell_inland[i] < inland.x or _cell_inland[i] > inland.y:
			continue
		if _cell_excluded[i] != 0 or _cell_battle[i] != 0 or _cell_rock[i] != 0 or _cell_height[i] < _sea_level:
			continue
		var p: Vector2 = _grid_point(i)
		var from_path: float = wear_distance(p)
		if from_path < path_distance.x or from_path > path_distance.y:
			continue
		var clear: bool = true
		for stance in _enemy_stances:
			if p.distance_to(Vector2(stance.x, stance.y)) < stance.z + stance_clearance:
				clear = false
				break
		for solid in _solids:
			if clear and p.distance_to(Vector2(solid.x, solid.y)) < solid.z:
				clear = false
		if clear:
			points.append(p)
	return points

# Placed at least once, with no rebuild waiting - the grid and every
# placement there to read.
func is_built() -> bool:
	return not _cell_zone.is_empty() and not _rebuild_queued

func get_sea_level() -> float:
	return _sea_level

func get_build_msec() -> int:
	return _build_msec
