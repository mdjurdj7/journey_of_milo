extends StaticBody3D
class_name RockShelf

# A slab of stone standing in the sand - planes, not a painted bump. A
# heightfield can't draw stone (no edges, faces lit like the sand, colour
# doing all the work), so the shelf a floor used to paint into its
# elevation and rock masks is this instead, the masks flattened under it.
#
# The top is broken into plates: sites on a jittered grid (cell_spacing_m
# apart) inside the outline, each owning its Voronoi cell, each cell a
# plane tilted tilt_min..tilt_max degrees. Neighbouring plates don't
# agree at their shared edge, so every crease is a small step (a vertical
# wall, a step darker) - the edges that catch the light. Each plate's
# plane passes through its level at its own site: the local sand plus
# high_top_m on the far side, easing to low_top_m on the low side
# (low_side, an XZ direction). Rim plates facing the low side dip toward
# the edge, so their lip comes down near the sand and he can step up
# (Wanderer.step_height); every other rim plate rises toward its edge,
# so its lip stands clear and the face stops him. Walking off any side is
# a drop, allowed.
#
# Two passes settle the heights. The creases are relaxed - plates
# levelled toward each other until no step is over crease_step_max_m, or
# as near as two planes crossing along an edge allow - and then each rim
# plate's lip is set against the sand just outside it (at most
# low_lip_max_m on the low side, at least high_lip_min_m elsewhere) and
# held there while the inner plates relax again around it. Plate size is
# what bounds the crossings: a 15-degree plane pair differs by ~0.45 m
# per metre of shared edge, so cell_spacing_m much over 0.8 m leaves
# creases he can't step over.
#
# The sides are two planes per outline segment: the lip overhangs an
# undercut (deeper on the faces turned south and west, away from the sun
# the camera looks past - they throw the dark band), and below it a foot
# runs out and down sink_m under the sand, so the sand laps the slab
# with no seam. FLAT shaded - every triangle carries its plane's normal.
# Tinted stone through the props' shared flat material; steps, overhangs
# and feet a step darker through vertex colour.
#
# Its own material, so none of the ground shader's passes (wet band,
# wear, caustics, grain) touch it - only the light, its shadow and fog.
#
# Collision is the same triangles (a trimesh). What he stands on is also
# what his ground hold and his footprints read: it joins WALK_SURFACE_
# GROUP, and Ground.get_walk_height_at()/get_walk_surface_at() take the
# highest walk surface over the sand at an XZ.
#
# Placed from FloorData.props at the outline's centre (its node origin,
# never rotated); the outline is local XZ around it. Built on entering
# the tree, rebuilt with the relief (Ground.relief_rebuilt) and on any
# export change. The layout is fixed by layout_seed.

const WALK_SURFACE_GROUP := &"walk_surfaces"

@export_group("Shape")
# The slab's edge, local XZ (x = X, y = Z) around this node, in order.
@export var outline: PackedVector2Array = PackedVector2Array():
	set(value):
		outline = value
		_rebuild()
# XZ direction of the side he can step up from.
@export var low_side: Vector2 = Vector2(1.0, 0.0):
	set(value):
		low_side = value
		_rebuild()
# A plate's level over the sand at its own site, on the far side and on
# the low side.
@export var high_top_m: float = 0.4:
	set(value):
		high_top_m = value
		_rebuild()
@export var low_top_m: float = 0.25:
	set(value):
		low_top_m = value
		_rebuild()
# The lips against the sand lip_probe_out_m outside them: the low side's
# at most low_lip_max_m (under Wanderer.step_height - he steps up), every
# other side's at least high_lip_min_m (over it - the face stops him).
@export var low_lip_max_m: float = 0.3:
	set(value):
		low_lip_max_m = value
		_rebuild()
@export var high_lip_min_m: float = 0.45:
	set(value):
		high_lip_min_m = value
		_rebuild()
@export var lip_probe_out_m: float = 0.3:
	set(value):
		lip_probe_out_m = value
		_rebuild()
# The tallest step a crease is allowed before its plates are levelled
# toward each other (see _relax_creases()). Under Wanderer.step_height
# keeps every crease one he can walk over.
@export var crease_step_max_m: float = 0.25:
	set(value):
		crease_step_max_m = value
		_rebuild()
@export var cell_spacing_m: float = 0.75:
	set(value):
		cell_spacing_m = value
		_rebuild()
@export_range(0.0, 45.0, 0.5) var tilt_min_degrees: float = 12.0:
	set(value):
		tilt_min_degrees = value
		_rebuild()
@export_range(0.0, 45.0, 0.5) var tilt_max_degrees: float = 18.0:
	set(value):
		tilt_max_degrees = value
		_rebuild()
# Rim plates within this many degrees of low_side dip toward the edge.
@export_range(0.0, 180.0, 1.0) var low_arc_degrees: float = 55.0:
	set(value):
		low_arc_degrees = value
		_rebuild()
# How far a rising rim plate's tilt may turn off straight outward.
@export_range(0.0, 90.0, 1.0) var rim_tilt_spread_degrees: float = 60.0:
	set(value):
		rim_tilt_spread_degrees = value
		_rebuild()
@export var layout_seed: int = 1:
	set(value):
		layout_seed = value
		_rebuild()

@export_group("Sides")
# How far the undercut sits in under the lip: undercut_m on faces turned
# north and east, undercut_south_west_m on faces turned south or west.
@export var undercut_m: float = 0.08:
	set(value):
		undercut_m = value
		_rebuild()
@export var undercut_south_west_m: float = 0.24:
	set(value):
		undercut_south_west_m = value
		_rebuild()
# Where the undercut's deepest line sits, from the lip (0) to the sand (1).
@export_range(0.05, 0.95, 0.01) var undercut_height_fraction: float = 0.5:
	set(value):
		undercut_height_fraction = value
		_rebuild()
# The foot's reach past the lip line at the sand, and its depth under it.
@export var foot_out_m: float = 0.06:
	set(value):
		foot_out_m = value
		_rebuild()
@export var sink_m: float = 0.15:
	set(value):
		sink_m = value
		_rebuild()

@export_group("Colour")
@export var stone_color: Color = Color(0.56, 0.59, 0.50):
	set(value):
		stone_color = value
		_apply_material()
# Vertex-colour multipliers: a crease's step, the overhang under the lip,
# the foot below it; and how much each plate's own shade may vary.
@export_range(0.0, 1.0, 0.01) var step_shade: float = 0.86:
	set(value):
		step_shade = value
		_rebuild()
@export_range(0.0, 1.0, 0.01) var overhang_shade: float = 0.7:
	set(value):
		overhang_shade = value
		_rebuild()
@export_range(0.0, 1.0, 0.01) var foot_shade: float = 0.88:
	set(value):
		foot_shade = value
		_rebuild()
@export_range(0.0, 0.3, 0.01) var plate_shade_jitter: float = 0.05:
	set(value):
		plate_shade_jitter = value
		_rebuild()
@export_group("")

@export var ground_path: NodePath = ^"../Ground"

var _ground: Ground = null
var _mesh_instance: MeshInstance3D = null
var _collision: CollisionShape3D = null
var _material: StandardMaterial3D = null
# The plates: site (local XZ), level at the site (local Y) and gradient.
var _sites: PackedVector2Array = PackedVector2Array()
var _levels: PackedFloat32Array = PackedFloat32Array()
var _gradients: PackedVector2Array = PackedVector2Array()
# The creases: two ends per edge in _crease_ends, its two plates in
# _crease_plates (see _collect_creases()).
var _crease_ends: PackedVector2Array = PackedVector2Array()
var _crease_plates: PackedInt32Array = PackedInt32Array()
# Triangles as built: positions (local), one normal and one shade each.
var _positions: PackedVector3Array = PackedVector3Array()
var _normals: PackedVector3Array = PackedVector3Array()
var _shades: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	add_to_group(WALK_SURFACE_GROUP)
	# Raycast and stood on during a fight's freeze too.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var ground: Ground = _get_ground()
	if ground != null and not ground.relief_rebuilt.is_connected(_rebuild):
		ground.relief_rebuilt.connect(_rebuild)
	_rebuild()

# The top's world height at a world XZ, or -INF off the slab.
func get_top_height_at(world_xz: Vector2) -> float:
	var p: Vector2 = world_xz - Vector2(global_position.x, global_position.z)
	if _sites.is_empty() or not Geometry2D.is_point_in_polygon(p, outline):
		return -INF
	return global_position.y + _plate_height(_nearest_site(p), p)

# The top's world normal at a world XZ - its plate's plane; UP off it.
func get_top_normal_at(world_xz: Vector2) -> Vector3:
	var p: Vector2 = world_xz - Vector2(global_position.x, global_position.z)
	if _sites.is_empty() or not Geometry2D.is_point_in_polygon(p, outline):
		return Vector3.UP
	var g: Vector2 = _gradients[_nearest_site(p)]
	return Vector3(-g.x, 1.0, -g.y).normalized()

func _get_ground() -> Ground:
	if _ground == null and is_inside_tree():
		_ground = get_node_or_null(ground_path) as Ground
	return _ground

func _rebuild() -> void:
	if not is_inside_tree() or outline.size() < 3:
		return
	var ground: Ground = _get_ground()
	if ground == null:
		push_warning("RockShelf '%s': ground_path did not resolve to a Ground; not built." % name)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed
	_place_sites(rng)
	# Each plate's cell (in pieces where the outline is concave), and
	# whether it reaches the outline - a rim plate.
	var cells: Array[PackedVector2Array] = []
	var cell_plates := PackedInt32Array()
	var rim: Array[bool] = []
	for i in _sites.size():
		rim.append(false)
		for piece in _cell_pieces(i):
			cells.append(piece)
			cell_plates.append(i)
			for k in piece.size():
				if _distance_to_outline((piece[k] + piece[(k + 1) % piece.size()]) * 0.5) < 0.001:
					rim[i] = true
	var fixed: Array[bool] = _assign_planes(rng, rim)
	_collect_creases(cells, cell_plates)
	_relax_creases(fixed)
	# Then the lips are set against the sand outside them and the rim held
	# there, the inner plates taking up what that does to the creases.
	_set_lips(fixed, rim)
	_relax_creases(rim)
	_positions.clear()
	_normals.clear()
	_shades.clear()
	_build_top_and_steps(cells, cell_plates)
	_build_sides()
	_commit()

# --- Layout ---

func _place_sites(rng: RandomNumberGenerator) -> void:
	var spacing: float = maxf(cell_spacing_m, 0.3)
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		bounds = bounds.expand(p)
	_sites.clear()
	var y: float = bounds.position.y + spacing * 0.5
	while y < bounds.end.y:
		var x: float = bounds.position.x + spacing * 0.5
		while x < bounds.end.x:
			var site := Vector2(x, y) + Vector2(rng.randf_range(-0.3, 0.3), rng.randf_range(-0.3, 0.3)) * spacing
			if Geometry2D.is_point_in_polygon(site, outline) and _distance_to_outline(site) > spacing * 0.2:
				_sites.append(site)
			x += spacing
		y += spacing
	if _sites.size() < 2:
		_sites = PackedVector2Array([_centroid() + Vector2(-0.3, 0.0), _centroid() + Vector2(0.3, 0.0)])

# Each plate's level and tilt. A rim plate facing the low side dips
# toward its edge; any other rim plate rises toward it; an inner plate
# tilts any way. Returns which plates are held where they are when the
# creases are relaxed - the low-side rim, whose lips are the way up.
func _assign_planes(rng: RandomNumberGenerator, rim: Array[bool]) -> Array[bool]:
	var fixed: Array[bool] = []
	var centre: Vector2 = _centroid()
	var low: Vector2 = low_side.normalized() if low_side.length() > 0.0001 else Vector2(1.0, 0.0)
	var reach_low: float = -INF
	var reach_high: float = INF
	for p in outline:
		reach_low = maxf(reach_low, (p - centre).dot(low))
		reach_high = minf(reach_high, (p - centre).dot(low))
	_levels.clear()
	_gradients.clear()
	for i in _sites.size():
		var site: Vector2 = _sites[i]
		var t: float = clampf(inverse_lerp(reach_high, reach_low, (site - centre).dot(low)), 0.0, 1.0)
		_levels.append(_sand(site) + lerpf(high_top_m, low_top_m, t))
		var slope: float = tan(deg_to_rad(rng.randf_range(tilt_min_degrees, tilt_max_degrees)))
		var direction: Vector2
		var holds: bool = false
		if rim[i]:
			var outward: Vector2 = (_closest_on_outline(site) - site).normalized()
			if absf(rad_to_deg(outward.angle_to(low))) <= low_arc_degrees:
				# Dips toward its edge: the lip comes down to the sand.
				direction = -outward
				holds = true
			else:
				direction = outward.rotated(deg_to_rad(rng.randf_range(-rim_tilt_spread_degrees, rim_tilt_spread_degrees)))
		else:
			direction = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		_gradients.append(direction * slope)
		fixed.append(holds)
	return fixed

# Every edge two plates share: its ends and the two plates, lower index
# first - what the crease relaxation and the step walls work from.
func _collect_creases(cells: Array[PackedVector2Array], cell_plates: PackedInt32Array) -> void:
	_crease_ends.clear()
	_crease_plates.clear()
	for c in cells.size():
		var piece: PackedVector2Array = cells[c]
		var plate: int = cell_plates[c]
		for k in piece.size():
			var a: Vector2 = piece[k]
			var b: Vector2 = piece[(k + 1) % piece.size()]
			var other: int = _neighbour_across(plate, (a + b) * 0.5)
			if other < 0 or other < plate:
				continue
			_crease_ends.append_array(PackedVector2Array([a, b]))
			_crease_plates.append_array(PackedInt32Array([plate, other]))

# Plates are levelled toward each other, a share at a time, until no
# crease's step is over crease_step_max_m - or as near as two planes
# crossing along it allow. A held plate doesn't move; its neighbour
# takes the whole correction.
func _relax_creases(fixed: Array[bool]) -> void:
	for _pass in 40:
		var worst: float = 0.0
		for e in _crease_plates.size() >> 1:
			var i: int = _crease_plates[e * 2]
			var j: int = _crease_plates[e * 2 + 1]
			var step_a: float = _plate_height(i, _crease_ends[e * 2]) - _plate_height(j, _crease_ends[e * 2])
			var step_b: float = _plate_height(i, _crease_ends[e * 2 + 1]) - _plate_height(j, _crease_ends[e * 2 + 1])
			var step: float = step_a if absf(step_a) > absf(step_b) else step_b
			var excess: float = absf(step) - crease_step_max_m
			worst = maxf(worst, excess)
			if excess <= 0.0 or (fixed[i] and fixed[j]):
				continue
			# Both ends move together: where the planes cross along the edge,
			# settle for evening the two ends rather than overshooting one.
			var shift: float = signf(step) * excess
			var other_end: float = step_b if step == step_a else step_a
			if absf(other_end - shift) > crease_step_max_m:
				shift = (step_a + step_b) * 0.5
			if fixed[i]:
				_levels[j] += shift
			elif fixed[j]:
				_levels[i] -= shift
			else:
				_levels[i] -= shift * 0.5
				_levels[j] += shift * 0.5
		if worst <= 0.0:
			return

# Every rim plate's lip against the sand lip_probe_out_m outside it,
# along the whole run of outline it owns: a low-side plate is lowered
# until its highest lip is at most low_lip_max_m (he steps up anywhere
# along it), any other rim plate raised until its lowest lip is at least
# high_lip_min_m (the face stops him).
func _set_lips(low_rim: Array[bool], rim: Array[bool]) -> void:
	var lowest := PackedFloat32Array()
	var highest := PackedFloat32Array()
	for i in _sites.size():
		lowest.append(INF)
		highest.append(-INF)
	for k in outline.size():
		var a: Vector2 = outline[k]
		var b: Vector2 = outline[(k + 1) % outline.size()]
		var along: Vector2 = b - a
		var steps: int = maxi(int(ceil(along.length() / 0.1)), 1)
		var out: Vector2 = Vector2(along.y, -along.x).normalized()
		if out.dot((a + b) * 0.5 - _centroid()) < 0.0:
			out = -out
		for s in steps:
			var p: Vector2 = a + along * (float(s) + 0.5) / float(steps)
			var plate: int = _nearest_site(p)
			var lip: float = _plate_height(plate, p) - _sand(p + out * lip_probe_out_m)
			lowest[plate] = minf(lowest[plate], lip)
			highest[plate] = maxf(highest[plate], lip)
	for i in _sites.size():
		if not rim[i] or lowest[i] == INF:
			continue
		if low_rim[i]:
			_levels[i] -= maxf(highest[i] - low_lip_max_m, 0.0)
		else:
			_levels[i] += maxf(high_lip_min_m - lowest[i], 0.0)

func _plate_height(index: int, p: Vector2) -> float:
	return _levels[index] + _gradients[index].dot(p - _sites[index])

func _nearest_site(p: Vector2) -> int:
	var best: int = 0
	var best_distance: float = INF
	for i in _sites.size():
		var d: float = p.distance_squared_to(_sites[i])
		if d < best_distance:
			best_distance = d
			best = i
	return best

func _centroid() -> Vector2:
	var sum := Vector2.ZERO
	for p in outline:
		sum += p
	return sum / float(outline.size())

func _closest_on_outline(p: Vector2) -> Vector2:
	var best := outline[0]
	var best_distance: float = INF
	for k in outline.size():
		var q: Vector2 = Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % outline.size()])
		if p.distance_to(q) < best_distance:
			best_distance = p.distance_to(q)
			best = q
	return best

func _distance_to_outline(p: Vector2) -> float:
	return p.distance_to(_closest_on_outline(p))

# The sand as drawn at a local XZ, in local Y.
func _sand(p: Vector2) -> float:
	var world := Vector3(global_position.x + p.x, 0.0, global_position.z + p.y)
	var on_ground: Vector3 = _ground.to_local(world)
	var height: float = _ground.get_visible_height_at(Vector2(on_ground.x, on_ground.z))
	return _ground.to_global(Vector3(on_ground.x, height, on_ground.z)).y - global_position.y

# Site i's Voronoi cell inside the outline - more than one piece where
# the outline is concave.
func _cell_pieces(i: int) -> Array[PackedVector2Array]:
	var pieces: Array[PackedVector2Array] = [outline]
	var far: float = 1000.0
	for j in _sites.size():
		if j == i:
			continue
		var mid: Vector2 = (_sites[i] + _sites[j]) * 0.5
		var toward_j: Vector2 = (_sites[j] - _sites[i]).normalized()
		var along := Vector2(-toward_j.y, toward_j.x)
		var half := PackedVector2Array([mid + along * far, mid - along * far, mid - along * far - toward_j * far, mid + along * far - toward_j * far])
		var next: Array[PackedVector2Array] = []
		for piece in pieces:
			next.append_array(Geometry2D.intersect_polygons(piece, half))
		pieces = next
	return pieces

# --- Mesh ---

func _build_top_and_steps(cells: Array[PackedVector2Array], cell_plates: PackedInt32Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = layout_seed + 7919
	var plate_shades := PackedFloat32Array()
	for i in _sites.size():
		plate_shades.append(1.0 - rng.randf() * plate_shade_jitter)
	for c in cells.size():
		var piece: PackedVector2Array = cells[c]
		if piece.size() < 3:
			continue
		var plate: int = cell_plates[c]
		var g: Vector2 = _gradients[plate]
		var up := Vector3(-g.x, 1.0, -g.y).normalized()
		var indices: PackedInt32Array = Geometry2D.triangulate_polygon(piece)
		for t in range(0, indices.size(), 3):
			_add_triangle(_top_point(plate, piece[indices[t]]), _top_point(plate, piece[indices[t + 1]]), _top_point(plate, piece[indices[t + 2]]), up, plate_shades[plate])
	# The step at each crease, faced toward the lower plate.
	for e in _crease_plates.size() >> 1:
		var plate: int = _crease_plates[e * 2]
		var other: int = _crease_plates[e * 2 + 1]
		var a: Vector2 = _crease_ends[e * 2]
		var b: Vector2 = _crease_ends[e * 2 + 1]
		var ha: float = _plate_height(plate, a) - _plate_height(other, a)
		var hb: float = _plate_height(plate, b) - _plate_height(other, b)
		if absf(ha) < 0.005 and absf(hb) < 0.005:
			continue
		var across: Vector2 = (_sites[other] - _sites[plate]).normalized()
		var face := Vector3(across.x, 0.0, across.y) * (1.0 if ha + hb > 0.0 else -1.0)
		var a_hi: Vector3 = _top_point(plate, a)
		var b_hi: Vector3 = _top_point(plate, b)
		var a_lo: Vector3 = _top_point(other, a)
		var b_lo: Vector3 = _top_point(other, b)
		_add_triangle(a_hi, b_hi, b_lo, face, step_shade)
		_add_triangle(a_hi, b_lo, a_lo, face, step_shade)

# The site on the far side of an edge of `plate`'s cell, or -1 when the
# edge is the outline.
func _neighbour_across(plate: int, mid: Vector2) -> int:
	var own: float = mid.distance_to(_sites[plate])
	var best: int = -1
	var best_distance: float = INF
	for j in _sites.size():
		if j == plate:
			continue
		var d: float = mid.distance_to(_sites[j])
		if d < best_distance:
			best_distance = d
			best = j
	if best >= 0 and absf(best_distance - own) < 0.002:
		return best
	return -1

func _top_point(index: int, p: Vector2) -> Vector3:
	return Vector3(p.x, _plate_height(index, p), p.y)

func _build_sides() -> void:
	# The outline split where it passes from one plate to the next, so
	# each run of lip lies on one plane.
	var runs: Array[PackedVector2Array] = []
	var run_plates := PackedInt32Array()
	for k in outline.size():
		var a: Vector2 = outline[k]
		var b: Vector2 = outline[(k + 1) % outline.size()]
		var plate: int = _nearest_site(a.lerp(b, 0.001))
		var t0: float = 0.0
		for _guard in _sites.size():
			var next_t: float = 2.0
			var next_owner: int = -1
			var pa: Vector2 = a - _sites[plate]
			for j in _sites.size():
				if j == plate:
					continue
				# |p - s_j|^2 - |p - s_owner|^2 along the segment, linear in t.
				var qa: Vector2 = a - _sites[j]
				var start: float = qa.length_squared() - pa.length_squared()
				var rate: float = 2.0 * (b - a).dot(_sites[plate] - _sites[j])
				if rate >= 0.0:
					continue
				var t: float = -start / rate
				if t > t0 + 0.00001 and t < next_t:
					next_t = t
					next_owner = j
			if next_owner < 0 or next_t >= 1.0:
				break
			runs.append(PackedVector2Array([a.lerp(b, t0), a.lerp(b, next_t)]))
			run_plates.append(plate)
			plate = next_owner
			t0 = next_t
		runs.append(PackedVector2Array([a.lerp(b, t0), b]))
		run_plates.append(plate)

	var clockwise: bool = Geometry2D.is_polygon_clockwise(outline)
	var count: int = runs.size()
	var outwards := PackedVector2Array()
	for r in count:
		var d: Vector2 = (runs[r][1] - runs[r][0]).normalized()
		outwards.append(Vector2(-d.y, d.x) if clockwise else Vector2(d.y, -d.x))
	# Per junction (the start of run r): the undercut and foot points,
	# shared by the runs either side.
	var unders := PackedVector3Array()
	var feet := PackedVector3Array()
	for r in count:
		var previous: int = (r - 1 + count) % count
		var v: Vector2 = runs[r][0]
		var out: Vector2 = (outwards[r] + outwards[previous]).normalized()
		if out.length() < 0.001:
			out = outwards[r]
		var south_west: float = clampf(maxf(out.dot(Vector2(0.0, 1.0)), out.dot(Vector2(-1.0, 0.0))), 0.0, 1.0)
		var depth: float = lerpf(undercut_m, undercut_south_west_m, south_west)
		var lip: float = minf(_plate_height(run_plates[r], v), _plate_height(run_plates[previous], v))
		var under: Vector2 = v - out * depth
		unders.append(Vector3(under.x, lerpf(lip, _sand(v), undercut_height_fraction), under.y))
		var foot: Vector2 = v + out * foot_out_m
		feet.append(Vector3(foot.x, _sand(foot) - sink_m, foot.y))
	for r in count:
		var next: int = (r + 1) % count
		var face := Vector3(outwards[r].x, 0.0, outwards[r].y)
		var lip_a: Vector3 = _top_point(run_plates[r], runs[r][0])
		var lip_b: Vector3 = _top_point(run_plates[r], runs[r][1])
		_add_triangle(lip_a, lip_b, unders[next], face, overhang_shade)
		_add_triangle(lip_a, unders[next], unders[r], face, overhang_shade)
		_add_triangle(unders[r], unders[next], feet[next], face, foot_shade)
		_add_triangle(unders[r], feet[next], feet[r], face, foot_shade)
		# Where the lip changes plate, the sliver between the two lips.
		if run_plates[next] != run_plates[r]:
			var here: Vector2 = runs[r][1]
			_add_triangle(_top_point(run_plates[r], here), _top_point(run_plates[next], here), unders[next], face, overhang_shade)

# One flat triangle, wound front-facing (Godot's clockwise) toward
# `facing` - its own plane's normal, turned to that side.
func _add_triangle(a: Vector3, b: Vector3, c: Vector3, facing: Vector3, shade: float) -> void:
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() < 1e-10:
		return
	normal = normal.normalized()
	if normal.dot(facing) < 0.0:
		normal = -normal
		_positions.append_array(PackedVector3Array([a, b, c]))
	else:
		_positions.append_array(PackedVector3Array([a, c, b]))
	_normals.append(normal)
	_shades.append(shade)

func _commit() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for t in _normals.size():
		var shade: float = _shades[t]
		for v in 3:
			st.set_color(Color(shade, shade, shade))
			st.set_normal(_normals[t])
			st.add_vertex(_positions[t * 3 + v])
	var mesh: ArrayMesh = st.commit()
	if _mesh_instance == null:
		_mesh_instance = MeshInstance3D.new()
		_mesh_instance.name = "Mesh"
		add_child(_mesh_instance)
	_mesh_instance.mesh = mesh
	_apply_material()
	if _collision == null:
		_collision = CollisionShape3D.new()
		_collision.name = "Collision"
		add_child(_collision)
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(_positions)
	_collision.shape = shape

func _apply_material() -> void:
	if _mesh_instance == null:
		return
	if _material == null:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		_material.vertex_color_use_as_albedo = true
	_material.albedo_color = stone_color
	_mesh_instance.material_override = _material
