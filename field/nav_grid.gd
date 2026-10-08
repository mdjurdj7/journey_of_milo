extends RefCounted
class_name NavGrid

# Where the Wanderer can walk on this floor, as a grid for AStarGrid2D -
# built when the floor loads (RegionField._build_nav_grid()), from the
# floor's own data and nothing authored for it: Ground's walk heights
# (rock shelves and the channel's carve included), Sea.sea_level, and the
# collision shapes of the floor's static bodies (hulls, the Keeper,
# props, the ledge barriers along FloorData.ledges).
#
# A cell is cell_size metres square, covering `rect` (the boundary walls'
# rectangle - nothing past them is in the grid). Blocked:
# - deep water: past the drawn shoreline (Ground.get_landmass_distance(),
#   channels included), the seabed under the cell more than
#   deep_water_depth below sea level. Shallower water, painted shoals included, is walkable at
#   shallows_cost (AStarGrid2D's weight_scale), so a route wades only when
#   the dry way round costs more, or when its target is in the water;
# - a climb past what he can take: a step to a neighbouring cell higher
#   than the larger of step_height and his 45-degree slope over one cell
#   (both cells of it);
# - every static body's footprint.
# Slopes and footprints are inflated by `inflation` (his radius plus a
# margin), so a path never brushes them; deep water isn't (he can wade
# into it - it is only never planned through).
#
# Per query (find_path()), the contact zones of the enemies in the way are
# stamped solid and lifted again after - they move (patrols) and die, so
# they never live in the base grid. So is a dynamic obstacle (the closed
# channel's Blocker) while it stands.
#
# A target that is solid or unreachable resolves to the nearest point that
# can be reached (an open cell near it, then AStarGrid2D's partial path).
# The path is smoothed by line of sight (_smooth()), never across a cell
# costlier than the raw path's own between the same two points - so a
# smoothed path never wades where the planned one didn't.

var cell_size: float = 0.35
var inflation: float = 0.5
var deep_water_depth: float = 0.6
var shallows_cost: float = 6.0
var step_height: float = 0.35
var max_slope_degrees: float = 45.0

var origin: Vector2 = Vector2.ZERO
var cols: int = 0
var rows: int = 0
var sea_level: float = 0.0
var heights: PackedFloat32Array = PackedFloat32Array()
# Per cell: 0 dry, 1 shallow water (costed), 2 deep water (solid).
var water: PackedByteArray = PackedByteArray()
# Per cell: 1 when solid in the base grid (terrain, footprints, deep water).
var base_solid: PackedByteArray = PackedByteArray()
var astar: AStarGrid2D = null
var build_msec: int = 0

# Cells a query stamped solid, to lift again.
var _stamped: Array[Vector2i] = []

# --- Build ---

# `shapes`: every static collision shape to stamp (RegionField picks them -
# the ground, walk surfaces and the boundary walls left out).
func build(ground: Ground, sea: float, rect: Rect2, shapes: Array[CollisionShape3D]) -> void:
	var started: int = Time.get_ticks_msec()
	sea_level = sea
	origin = rect.position
	cols = maxi(int(ceil(rect.size.x / cell_size)), 1)
	rows = maxi(int(ceil(rect.size.y / cell_size)), 1)
	var count: int = cols * rows
	heights.resize(count)
	water.resize(count)
	base_solid.resize(count)
	water.fill(0)
	base_solid.fill(0)
	for z in rows:
		for x in cols:
			var centre: Vector2 = cell_centre(Vector2i(x, z))
			var local: Vector3 = ground.to_local(Vector3(centre.x, 0.0, centre.y))
			var local_height: float = ground.get_walk_height_at(Vector2(local.x, local.z))
			var height: float = ground.to_global(Vector3(local.x, local_height, local.z)).y
			var i: int = z * cols + x
			heights[i] = height
			# Water only past the drawn shoreline (Ground's own line, channels
			# included) - a floor with no sea has ground below sea level and
			# nothing on it.
			if ground.get_landmass_distance(centre) <= 0.0:
				continue
			var depth: float = sea_level - height
			if depth > deep_water_depth:
				water[i] = 2
			elif depth > 0.0:
				water[i] = 1
	# What he can't stand on or next to, before inflation.
	var blocked := PackedByteArray()
	blocked.resize(count)
	blocked.fill(0)
	var max_rise: float = maxf(step_height, cell_size * tan(deg_to_rad(max_slope_degrees)))
	for z in rows:
		for x in cols:
			var i: int = z * cols + x
			if x + 1 < cols and absf(heights[i] - heights[i + 1]) > max_rise:
				blocked[i] = 1
				blocked[i + 1] = 1
			if z + 1 < rows and absf(heights[i] - heights[i + cols]) > max_rise:
				blocked[i] = 1
				blocked[i + cols] = 1
	for shape in shapes:
		for cell in footprint_cells(shape):
			blocked[cell.y * cols + cell.x] = 1
	# Inflated by his radius and a margin.
	var offsets: Array[Vector2i] = _disc(inflation)
	for z in rows:
		for x in cols:
			if blocked[z * cols + x] == 0:
				continue
			for offset in offsets:
				var cx: int = x + offset.x
				var cz: int = z + offset.y
				if cx >= 0 and cz >= 0 and cx < cols and cz < rows:
					base_solid[cz * cols + cx] = 1
	for i in count:
		if water[i] == 2:
			base_solid[i] = 1
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, cols, rows)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for z in rows:
		for x in cols:
			var i: int = z * cols + x
			if base_solid[i] == 1:
				astar.set_point_solid(Vector2i(x, z), true)
			elif water[i] == 1:
				astar.set_point_weight_scale(Vector2i(x, z), shallows_cost)
	build_msec = Time.get_ticks_msec() - started

# The cells a collision shape stands on: its debug mesh's box through the
# shape's transform, flattened to XZ - the hull of the eight corners.
func footprint_cells(shape_node: CollisionShape3D) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if shape_node == null or shape_node.shape == null or shape_node.disabled:
		return cells
	var box: AABB = shape_node.shape.get_debug_mesh().get_aabb()
	var points := PackedVector2Array()
	for i in 8:
		var corner: Vector3 = shape_node.global_transform * box.get_endpoint(i)
		points.append(Vector2(corner.x, corner.z))
	var hull: PackedVector2Array = Geometry2D.convex_hull(points)
	if hull.size() < 3:
		return cells
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for point in hull:
		low = low.min(point)
		high = high.max(point)
	var from: Vector2i = world_to_cell(low)
	var to: Vector2i = world_to_cell(high)
	for z in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			var cell := Vector2i(x, z)
			if in_bounds(cell) and Geometry2D.is_point_in_polygon(cell_centre(cell), hull):
				cells.append(cell)
	# A sliver thinner than a cell (a ledge wall) still blocks the cells it
	# crosses: its centre line, walked at a quarter cell.
	if cells.is_empty():
		var a: Vector2 = (hull[0] + hull[1]) * 0.5
		var half: int = hull.size() >> 1
		var b: Vector2 = (hull[half] + hull[(half + 1) % hull.size()]) * 0.5
		var steps: int = maxi(int(ceil(a.distance_to(b) / (cell_size * 0.25))), 1)
		for s in steps + 1:
			var cell: Vector2i = world_to_cell(a.lerp(b, float(s) / float(steps)))
			if in_bounds(cell) and not cells.has(cell):
				cells.append(cell)
	return cells

# --- Cells ---

func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < cols and cell.y < rows

func world_to_cell(world_xz: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((world_xz.x - origin.x) / cell_size)), 0, cols - 1), clampi(int(floor((world_xz.y - origin.y) / cell_size)), 0, rows - 1))

func cell_centre(cell: Vector2i) -> Vector2:
	return origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size

func height_at_cell(cell: Vector2i) -> float:
	return heights[cell.y * cols + cell.x]

func is_open(cell: Vector2i) -> bool:
	return in_bounds(cell) and not astar.is_point_solid(cell)

func is_deep(cell: Vector2i) -> bool:
	return in_bounds(cell) and water[cell.y * cols + cell.x] == 2

func cost_at(cell: Vector2i) -> float:
	return astar.get_point_weight_scale(cell)

# Cells within `radius` metres of a cell's centre, as offsets.
func _disc(radius: float) -> Array[Vector2i]:
	var offsets: Array[Vector2i] = []
	var reach: int = int(ceil(radius / cell_size))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			if Vector2(dx, dz).length() * cell_size <= radius + 0.001:
				offsets.append(Vector2i(dx, dz))
	return offsets

# The open cell nearest `cell`, ring by ring out to max_cells; `cell`
# itself when open, and Vector2i(-1, -1) when nothing is near.
func nearest_open(cell: Vector2i, max_cells: int = 60) -> Vector2i:
	if is_open(cell):
		return cell
	for ring in range(1, max_cells + 1):
		var best := Vector2i(-1, -1)
		var best_distance: float = INF
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var candidate := Vector2i(cell.x + dx, cell.y + dz)
				if is_open(candidate):
					var distance: float = Vector2(dx, dz).length()
					if distance < best_distance:
						best_distance = distance
						best = candidate
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

# From `point` toward `toward`, the first open cell - the near side of
# whatever stands at `point` (a hull clicked).
func nearest_open_toward(point: Vector2, toward: Vector2) -> Vector2:
	var distance: float = point.distance_to(toward)
	var steps: int = maxi(int(ceil(distance / (cell_size * 0.5))), 1)
	for s in steps + 1:
		var cell: Vector2i = world_to_cell(point.lerp(toward, float(s) / float(steps)))
		if is_open(cell):
			return cell_centre(cell)
	return toward

# --- Queries ---

# A path from `from` to `to` (world XZ), as world-XZ waypoints - `from`
# first. `zones`: [centre (Vector2), radius (float)] pairs stamped solid
# for this query; `dynamic`: shapes stamped the same way (the Blocker).
# Empty when there is nowhere to go.
func find_path(from: Vector2, to: Vector2, zones: Array = [], dynamic: Array[CollisionShape3D] = []) -> PackedVector2Array:
	var result := PackedVector2Array()
	if astar == null:
		return result
	_stamp(zones, dynamic)
	var start: Vector2i = world_to_cell(from)
	var opened_start: bool = false
	if not is_open(start):
		# Standing inside an inflated margin or a zone: leave from where he is.
		opened_start = true
		astar.set_point_solid(start, false)
	var goal_cell: Vector2i = world_to_cell(to)
	var target_open: bool = is_open(goal_cell)
	var goal: Vector2i = goal_cell if target_open else nearest_open(goal_cell)
	if goal.x < 0:
		goal = start
	var cells: Array[Vector2i] = astar.get_id_path(start, goal, true)
	if not cells.is_empty():
		var smoothed: Array[Vector2i] = _smooth(cells)
		result.append(from)
		for i in range(1, smoothed.size()):
			result.append(cell_centre(smoothed[i]))
		# Reached the very cell clicked: end on the point itself.
		if target_open and cells.back() == goal_cell:
			if result.size() > 1:
				result[result.size() - 1] = to
			else:
				result.append(to)
	if opened_start:
		astar.set_point_solid(start, true)
	_lift()
	return result

func _stamp(zones: Array, dynamic: Array[CollisionShape3D]) -> void:
	_stamped.clear()
	for zone: Array in zones:
		var centre: Vector2 = zone[0]
		var radius: float = zone[1]
		var reach: int = int(ceil(radius / cell_size))
		var middle: Vector2i = world_to_cell(centre)
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var cell := Vector2i(middle.x + dx, middle.y + dz)
				if is_open(cell) and cell_centre(cell).distance_to(centre) <= radius:
					astar.set_point_solid(cell, true)
					_stamped.append(cell)
	var offsets: Array[Vector2i] = _disc(inflation)
	for shape in dynamic:
		for cell in footprint_cells(shape):
			for offset in offsets:
				var inflated: Vector2i = cell + offset
				if is_open(inflated):
					astar.set_point_solid(inflated, true)
					_stamped.append(inflated)

func _lift() -> void:
	for cell in _stamped:
		astar.set_point_solid(cell, false)
	_stamped.clear()

# Line-of-sight smoothing: from each kept cell, on to the farthest cell of
# the raw path the straight line reaches across open cells no costlier
# than the raw path's own between them.
func _smooth(cells: Array[Vector2i]) -> Array[Vector2i]:
	if cells.size() <= 2:
		return cells
	var kept: Array[Vector2i] = [cells[0]]
	var i: int = 0
	while i < cells.size() - 1:
		var best: int = i + 1
		var allowed: float = maxf(cost_at(cells[i]), cost_at(cells[i + 1]))
		for j in range(i + 2, cells.size()):
			allowed = maxf(allowed, cost_at(cells[j]))
			if _line_clear(cells[i], cells[j], allowed):
				best = j
			else:
				break
		kept.append(cells[best])
		i = best
	return kept

# Every cell the straight line between two cell centres crosses - walked
# at a quarter cell - open and no costlier than `allowed`.
func _line_clear(a: Vector2i, b: Vector2i, allowed: float) -> bool:
	var from: Vector2 = Vector2(a) + Vector2(0.5, 0.5)
	var to: Vector2 = Vector2(b) + Vector2(0.5, 0.5)
	var steps: int = maxi(int(ceil(from.distance_to(to) * 4.0)), 1)
	for s in steps + 1:
		var point: Vector2 = from.lerp(to, float(s) / float(steps))
		var cell := Vector2i(int(floor(point.x)), int(floor(point.y)))
		if not is_open(cell) or cost_at(cell) > allowed + 0.001:
			return false
	return true
