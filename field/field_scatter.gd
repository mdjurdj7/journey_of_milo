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
#   - the worn band: nothing within wear_keep_out_m of its centreline
#     (the band's half-width plus its edge noise - the noise itself is
#     the shader's and can't be matched here), coming back over
#     wear_ramp_m; and the floor's painted wear;
#   - every static body's footprint (props, ledges) grown by prop_margin_m
#     - his walk-up to anything stops at that edge; the gate's shapes by
#     gate_margin_m; a rock shelf's outline by shelf_margin_m; the spawn
#     by spawn_clear_m;
#   - the battle frame's feet: a lone enemy's body and the ring his stance
#     can land on (RegionField.battle_spacing_min..battle_spacing, widened
#     by feet_margin_m either way); a cluster's line, stance to far member
#     with the line's possible shift, as a capsule; a patrolled pack's
#     waypoints.
# Nothing here has collision: the walk grid, the click and the Wanderer's
# steps never see it.

signal rebuilt

# A placed item before it has a model: on the drawn surface, its turn
# (the slope, a tilt off it, a yaw) at unit size, how wide it is, and its
# value off the entry's tint (1 = the tint).
class Spot extends RefCounted:
	var position: Vector3 = Vector3.ZERO
	var basis: Basis = Basis.IDENTITY
	var size: float = 0.0
	var shade: float = 1.0

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

	func contains(p: Vector2) -> bool:
		match kind:
			Kind.DISC:
				return p.distance_to(a) <= outer
			Kind.RING:
				var d: float = p.distance_to(a)
				return d >= inner and d <= outer
			Kind.CAPSULE:
				return FieldScatter.segment_distance(p, a, b) <= outer
			Kind.POLYGON:
				if Geometry2D.is_point_in_polygon(p, polygon):
					return true
				for i in polygon.size():
					if FieldScatter.segment_distance(p, polygon[i], polygon[(i + 1) % polygon.size()]) <= outer:
						return true
		return false

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
@export_group("")

@export_group("Worn Band")
# Nothing within this of the band's centreline. -1 = the band's own
# half-width plus its edge noise (Ground.wear_half_width + wear_edge_
# noise_amplitude) - the furthest it is ever drawn.
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

var _field: RegionField = null
var _ground: Ground = null
var _floor: FloorData = null
var _sea_level: float = 0.0
# The spawn as it was when set up - RegionField.get_spawn_position() is
# the Wanderer's live position, and a later rebuild must not follow him.
var _spawn: Vector2 = Vector2.ZERO
var _wear_points: PackedVector2Array = PackedVector2Array()
var _keepouts: Array[KeepOut] = []
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
var _cell_excluded: PackedByteArray = PackedByteArray()

# Every entry placed, in order, and each one's spots.
var _entries: Array[ScatterEntry] = []
var _spots: Dictionary = {}
var _item_count: int = 0
var _build_msec: int = 0

# From RegionField once its exit channel is cut: what to read, and the
# first build, deferred so every prop and enemy has placed itself.
func setup(field: RegionField) -> void:
	_field = field
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
	_queue_rebuild(true)

func _exit_tree() -> void:
	if _floor != null and _floor.changed.is_connected(_on_floor_changed):
		_floor.changed.disconnect(_on_floor_changed)

func _on_floor_changed() -> void:
	_queue_rebuild(false)

func _on_relief_rebuilt() -> void:
	_queue_rebuild(true)

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
		_grid_dirty = false
	_place_all()
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
			_cell_excluded[i] = 1 if is_excluded(p) else 0

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
# own painted wear is.
func wear_weight(p: Vector2) -> float:
	var weight: float = 1.0
	if _wear_points.size() >= 3:
		var keep_out: float = get_wear_keep_out()
		weight = smoothstep(keep_out, keep_out + maxf(wear_ramp_m, 0.001), wear_distance(p))
	var painted: float = _ground.get_wear_mask_at(p)
	if painted > 0.0:
		weight *= 1.0 - smoothstep(wear_mask_threshold, wear_mask_threshold + 0.2, painted)
	return weight

func get_wear_keep_out() -> float:
	if wear_keep_out_m >= 0.0:
		return wear_keep_out_m
	return _ground.wear_half_width + _ground.wear_edge_noise_amplitude

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

func is_excluded(p: Vector2) -> bool:
	for keepout in _keepouts:
		if keepout.contains(p):
			return true
	return false

func get_keepouts() -> Array[KeepOut]:
	return _keepouts

func _build_keepouts() -> void:
	_keepouts.clear()
	for shape in _field.get_obstacle_shapes():
		_add_footprint(shape, prop_margin_m)
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
	var groups: Dictionary = {}
	for node in _field.get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.is_queued_for_deletion() or not _field.is_ancestor_of(enemy):
			continue
		var key: StringName = enemy.group
		if key == &"":
			_add_lone_keepouts(enemy)
			continue
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(enemy)
	var patrolled: Dictionary = {}
	if _floor != null:
		for patrol in _floor.patrols:
			if patrol != null:
				patrolled[patrol.group] = patrol
	for key: StringName in groups:
		var members: Array = groups[key]
		if patrolled.has(key):
			_add_patrol_keepouts(members, patrolled[key] as FloorPatrol)
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
	ring.inner = maxf(_field.battle_spacing_min - feet_margin_m, 0.0)
	ring.outer = _field.battle_spacing + feet_margin_m
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
		line.a = _xz(anchor) - along * _field.battle_spacing
		line.b = _xz(anchor) + along * (_field.battle_line_shift_max + gaps)
		line.outer = radius
		_keepouts.append(line)

func _add_patrol_keepouts(members: Array, patrol: FloorPatrol) -> void:
	var centroid := Vector2.ZERO
	var body: float = 0.0
	for member: FieldEnemy in members:
		centroid += _xz(member)
		body = maxf(body, _half_diagonal(member))
	centroid /= float(maxi(members.size(), 1))
	var spread: float = 0.0
	for member: FieldEnemy in members:
		spread = maxf(spread, _xz(member).distance_to(centroid))
	var reach: float = _field.battle_spacing + feet_margin_m + spread + body
	_keepouts.append(_disc(centroid, reach))
	for waypoint in patrol.waypoints:
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
	_item_count = 0
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
			var left: int = budget - _item_count if budget > 0 else -1
			var spots: Array[Spot] = _place_entry(entry, left)
			_spots[entry] = spots
			_item_count += spots.size()
			if budget > 0 and _item_count >= budget:
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
	var step: float = maxf(sample_step_m, 0.1)
	var cells := PackedInt32Array()
	for i in _cell_zone.size():
		if _centre_allowed(entry, i):
			cells.append(i)
	if cells.is_empty():
		return spots
	var area: float = float(cells.size()) * step * step
	var expected: float = area / 100.0 * maxf(entry.clusters_per_100m2, 0.0) * maxf(_floor.scatter_density, 0.0)
	var target: int = floori(expected + rng.randf())
	if target <= 0:
		return spots
	# Poisson-disc by dart throwing: centres no nearer each other than a
	# share of the spacing the density would give spread evenly.
	var spacing: float = maxf(0.6 * sqrt(area / float(target)), entry.cluster_spread_m * 2.0)
	var centres: Array[Vector2] = []
	for attempt in target * 30:
		if centres.size() >= target:
			break
		var cell: int = cells[rng.randi_range(0, cells.size() - 1)]
		var p: Vector2 = cell_centre(cell % _grid_cols, floori(float(cell) / float(_grid_cols))) + Vector2(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.5, 0.5)) * step
		var clear: bool = true
		for other in centres:
			if other.distance_to(p) < spacing:
				clear = false
				break
		if clear:
			centres.append(p)
	for centre in centres:
		var count: int = rng.randi_range(mini(entry.items_per_cluster.x, entry.items_per_cluster.y), maxi(entry.items_per_cluster.x, entry.items_per_cluster.y))
		var cluster: Array[Vector2] = []
		for attempt in count * 4:
			if cluster.size() >= count or (left >= 0 and spots.size() >= left):
				break
			var p: Vector2 = centre + Vector2(rng.randfn(0.0, entry.cluster_spread_m), rng.randfn(0.0, entry.cluster_spread_m))
			# Drawn every attempt, kept or not, so one item's fate never
			# shifts the next's draws.
			var keep_roll: float = rng.randf()
			var yaw: float = rng.randf() * TAU
			var tilt_axis: float = rng.randf() * TAU
			var tilt: float = rng.randf_range(-entry.tilt_jitter_degrees, entry.tilt_jitter_degrees)
			var factor: float = rng.randf_range(entry.scale_range.x, entry.scale_range.y)
			var shade: float = 1.0 + rng.randf_range(-entry.tint_jitter, entry.tint_jitter)
			var size: float = entry.size_m * factor
			if not _item_allowed(entry, p, keep_roll):
				continue
			var crowded: bool = false
			for other in cluster:
				if other.distance_to(p) < size * 1.2:
					crowded = true
					break
			if crowded:
				continue
			cluster.append(p)
			var spot := Spot.new()
			spot.position = Vector3(p.x, _ground.get_visible_height_at(p), p.y)
			var jitter := Basis(Vector3(cos(tilt_axis), 0.0, sin(tilt_axis)), deg_to_rad(tilt))
			spot.basis = Basis(Quaternion(Vector3.UP, slope_normal(p))) * jitter * Basis(Vector3.UP, yaw)
			spot.size = size
			spot.shade = shade
			spots.append(spot)
	return spots

# A cell a cluster of `entry` may centre in: one of its zones, inside its
# inland range, dry enough, clear of every exclusion and fully off the
# worn band.
func _centre_allowed(entry: ScatterEntry, cell: int) -> bool:
	if (_cell_zone[cell] & entry.zones) == 0 or _cell_excluded[cell] != 0 or _cell_wear[cell] < 1.0:
		return false
	var inland: float = _cell_inland[cell]
	if inland < entry.inland_range_m.x or inland > entry.inland_range_m.y:
		return false
	return _cell_height[cell] >= _sea_level - entry.wet_edge_m

# Where one item lands, tested there: dry enough, clear of every
# exclusion, and off the worn band - on its ramp kept by its weight
# against `keep_roll`, so the band's edge thins rather than cuts.
func _item_allowed(entry: ScatterEntry, p: Vector2, keep_roll: float) -> bool:
	if _ground.get_visible_height_at(p) < _sea_level - entry.wet_edge_m:
		return false
	if is_excluded(p):
		return false
	return keep_roll < wear_weight(p)

# The drawn surface's normal at a point, from its heights either side.
func slope_normal(p: Vector2) -> Vector3:
	var e: float = 0.2
	var dx: float = _ground.get_visible_height_at(p + Vector2(e, 0.0)) - _ground.get_visible_height_at(p - Vector2(e, 0.0))
	var dz: float = _ground.get_visible_height_at(p + Vector2(0.0, e)) - _ground.get_visible_height_at(p - Vector2(0.0, e))
	return Vector3(-dx, 2.0 * e, -dz).normalized()

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

func get_sea_level() -> float:
	return _sea_level

func get_build_msec() -> int:
	return _build_msec
