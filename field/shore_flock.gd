extends Node3D
class_name ShoreFlock

# A floor's small flock of shorebirds (FloorData.shore_flock, ShoreFlock-
# Data): made by RegionField with the scatter, it settles once the scatter
# has placed (it reads FieldScatter.open_ground()) and the walk grid is
# built, on a spot drawn from the floor's own generator that he can walk
# to from the spawn - see ShoreFlockData for where. Each ShoreBird idles
# on its own clock.
#
# When the Wanderer comes within flee_radius_m of any bird, or a fight
# opens with the flock still there, they all go: nearest him first, one
# after another over takeoff_spread_seconds, flying off downwind; each is
# freed out of view, and the flock with the last. They don't come back
# this load.
#
# Processes through the field's freeze (the fight's, a screen's) so a
# flight finishes; the idle holds while the field is frozen. Sits at the
# world origin unturned, so its birds' positions are world positions.
# Both models wear the painted shader with the props' fog pass, shared by
# every bird and refilled when RegionSky's fog changes.

var _field: RegionField = null
var _data: ShoreFlockData = null
var _scatter: FieldScatter = null
var _ground: Ground = null
var _materials: Array[ShaderMaterial] = []
var _fog_passes: Array[ShaderMaterial] = []
var _birds: Array[ShoreBird] = []
var _spot: Vector2 = Vector2.INF
var _placed: bool = false
var _fled: bool = false

func setup(field: RegionField, data: ShoreFlockData) -> void:
	_field = field
	_data = data
	_scatter = field.get_scatter()
	_ground = field.get_node_or_null(field.ground_path) as Ground
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sky: RegionSky = field.get_region_sky()
	if sky != null and not sky.fog_changed.is_connected(_push_fog):
		sky.fog_changed.connect(_push_fog)
	if not data.changed.is_connected(_on_data_changed):
		data.changed.connect(_on_data_changed)

func _exit_tree() -> void:
	if _data != null and _data.changed.is_connected(_on_data_changed):
		_data.changed.disconnect(_on_data_changed)

func get_spot() -> Vector2:
	return _spot

func get_birds() -> Array[ShoreBird]:
	var alive: Array[ShoreBird] = []
	for bird in _birds:
		if is_instance_valid(bird):
			alive.append(bird)
	return alive

func has_fled() -> bool:
	return _fled

# A live edit re-places the flock while it is still on the ground.
func _on_data_changed() -> void:
	if _fled:
		return
	for bird in _birds:
		if is_instance_valid(bird):
			bird.queue_free()
	_birds.clear()
	_placed = false

func _process(delta: float) -> void:
	if _field == null or get_tree().paused:
		return
	if not _placed:
		if _scatter == null or not _scatter.is_built() or _field.get_nav_grid() == null:
			return
		_placed = true
		_place()
		return
	if not _fled and (_field.is_battle_open() or _wanderer_near()):
		flee()
	var idle: bool = _field.can_process()
	var alive: int = 0
	for bird in _birds:
		if is_instance_valid(bird):
			bird.advance(delta, idle)
			alive += 1
	if _fled and alive == 0:
		queue_free()

func _wanderer_near() -> bool:
	var wanderer: Wanderer = _field.wanderer
	if wanderer == null:
		return false
	var at := Vector2(wanderer.global_position.x, wanderer.global_position.z)
	for bird in _birds:
		if is_instance_valid(bird) and at.distance_to(Vector2(bird.position.x, bird.position.z)) <= _data.flee_radius_m:
			return true
	return false

# Every bird away, nearest him first, over takeoff_spread_seconds.
func flee() -> void:
	if _fled:
		return
	_fled = true
	var wanderer: Wanderer = _field.wanderer
	var from := Vector2(wanderer.global_position.x, wanderer.global_position.z) if wanderer != null else _spot
	var order: Array[ShoreBird] = get_birds()
	order.sort_custom(func(a: ShoreBird, b: ShoreBird) -> bool:
		return from.distance_squared_to(Vector2(a.position.x, a.position.z)) < from.distance_squared_to(Vector2(b.position.x, b.position.z)))
	var wind3: Vector3 = _field.get_wind_direction()
	var downwind := Vector2(wind3.x, wind3.z)
	for i in order.size():
		var bird: ShoreBird = order[i]
		var share: float = float(i) / float(maxi(order.size() - 1, 1))
		var at := Vector2(bird.position.x, bird.position.z)
		bird.take_off(share * _data.takeoff_spread_seconds, at - from, downwind)

# The flock's spot and its birds - see ShoreFlockData.
func _place() -> void:
	var floor_data: FloorData = _field.get_floor_data()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:shore_flock" % (floor_data.resource_path if floor_data != null else ""))
	_spot = _pick_spot(rng)
	if _spot == Vector2.INF:
		push_warning("ShoreFlock: no open sand %.1f-%.1f m off the path he can walk to; no flock." % [_data.path_distance_m.x, _data.path_distance_m.y])
		return
	_build_materials()
	var count: int = rng.randi_range(mini(_data.bird_count.x, _data.bird_count.y), maxi(_data.bird_count.x, _data.bird_count.y))
	var spots: Array[Vector2] = []
	for attempt in count * 20:
		if spots.size() >= count:
			break
		var p: Vector2 = _spot + Vector2.from_angle(rng.randf() * TAU) * _data.spread_m * sqrt(rng.randf())
		var yaw: float = rng.randf() * TAU
		var bird_seed: int = rng.randi()
		var clear: bool = not _scatter.is_excluded(p) and not _scatter.is_rock(p) and _ground.get_visible_height_at(p) >= _scatter.get_sea_level()
		for other in spots:
			if other.distance_to(p) < _data.bird_spacing_m:
				clear = false
				break
		if not clear:
			continue
		spots.append(p)
		var bird := ShoreBird.new()
		bird.name = "ShoreBird%d" % _birds.size()
		add_child(bird)
		bird.setup(_data, _ground, _materials[0] if _materials.size() > 0 else null, _materials[1] if _materials.size() > 1 else null, p, yaw, _spot, bird_seed)
		_birds.append(bird)
	print("ShoreFlock: %d birds at (%.1f, %.1f)" % [_birds.size(), _spot.x, _spot.y])

# Open sand by the water first, any open sand after: in a shuffled order,
# the first he can walk to from the spawn.
func _pick_spot(rng: RandomNumberGenerator) -> Vector2:
	var nav: NavGrid = _field.get_nav_grid()
	var spawn3: Vector3 = _field.get_spawn_position()
	var spawn := Vector2(spawn3.x, spawn3.z)
	var tiers: Array[PackedVector2Array] = [
		_scatter.open_ground(_data.prefer_zones, _data.prefer_inland_m, _data.path_distance_m, _data.stance_clearance_m),
		_scatter.open_ground(0, Vector2(0.3, INF), _data.path_distance_m, _data.stance_clearance_m),
	]
	for points in tiers:
		var order: Array[int] = []
		for i in points.size():
			order.append(i)
		# Fisher-Yates on the floor's generator.
		for i in range(order.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var swap: int = order[i]
			order[i] = order[j]
			order[j] = swap
		for k in mini(order.size(), 40):
			var p: Vector2 = points[order[k]]
			var route: PackedVector2Array = nav.find_path(spawn, p)
			if not route.is_empty() and route[route.size() - 1].distance_to(p) < 0.05:
				return p
	return Vector2.INF

func _build_materials() -> void:
	_materials.clear()
	_fog_passes.clear()
	for path in [_data.standing_colour_map_path, _data.flying_colour_map_path]:
		var painted: ShaderMaterial = PaintedProp.material(path, _data.tint)
		if painted == null:
			continue
		var fog: ShaderMaterial = PaintedProp.fog_pass()
		if fog != null:
			painted.next_pass = fog
			_fog_passes.append(fog)
		_materials.append(painted)
	_push_fog()

# The props' full share of the sky's fog as it stands.
func _push_fog() -> void:
	if _field == null:
		return
	for fog in _fog_passes:
		PaintedProp.push_fog(fog, _field.get_region_sky(), 1.0)
