extends SceneTree

# Headless probe for the worn band's centreline (Ground.set_wear_path(),
# RegionField._aim_wear_path()): what each floor hands the ground shader.
# A floor with no override derives three points (spawn, past the first
# enemy, the gate) - the one three-point curve; one with an override has
# it handed over whole and in order, for the shader's chain through every
# point. On a floor with ledge lines the band drawn stays inside them. A
# longer override (4 to 8 points) is handed over whole; past 8 the rest
# are dropped. Headless has no renderer, so this reads the
# shader parameters RegionField pushed, not the pixels.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/wear_path_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const CASES := 3
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const MAX_POINTS := 8
const ROUTE: Array[Vector2] = [Vector2(0, 0), Vector2(0, -6), Vector2(-4, -12), Vector2(2, -18), Vector2(8, -24), Vector2(14, -28), Vector2(24.1, -33.5)]
const SAFETY_SECONDS := 200.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	await _check_three_point_floors()
	await _check_long_override()
	await _check_capped_at_eight()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("wear_path_probe: PASSED")
		quit(0)
	else:
		print("wear_path_probe: %d FAILED" % _failures)
		quit(1)

# Floors 1-3: no override, the derived three points from spawn to the
# gate; an override, every point of it, in order. Where ledge lines are,
# the band's curve stays inside them.
func _check_three_point_floors() -> void:
	for index in 3:
		await _load_field(index)
		var floor_data: Resource = _field.call("get_floor_data")
		var override: PackedVector2Array = floor_data.get("wear_path_override")
		var spawn: Vector3 = _field.call("get_spawn_position")
		var points: PackedVector2Array = _points()
		if override.size() >= 3:
			_expect_eq(_count(), mini(override.size(), MAX_POINTS), "Floor %d: its override handed over whole" % (index + 1))
			for i in mini(override.size(), MAX_POINTS):
				_expect(points[i].is_equal_approx(Vector2(spawn.x + override[i].x, spawn.z + override[i].y)), "...point %d where it was put" % i)
		else:
			_expect_eq(_count(), 3, "Floor %d: a derived three-point band" % (index + 1))
			_expect(points[0].is_equal_approx(Vector2(spawn.x, spawn.z)), "...starting at spawn")
			var gate: Node3D = _field.get_node("ExitGate")
			_expect(points[2].is_equal_approx(Vector2(gate.global_position.x, gate.global_position.z)), "...ending at the gate")
		var ledges: Array = floor_data.get("ledges")
		var outside: int = 0
		for p in _drawn_curve(points.slice(0, _count())):
			for ledge: PackedVector2Array in ledges:
				if not Geometry2D.is_point_in_polygon(p - Vector2(spawn.x, spawn.z), ledge):
					outside += 1
		_expect_eq(outside, 0, "Floor %d: the band's curve inside the floor's ledge lines" % (index + 1))
		await _teardown()
	_completed += 1

# The band's centreline as ground.gdshader draws it (world XZ): three
# points one quadratic through the middle one, four to eight a uniform
# Catmull-Rom chain through every point, its ends doubled.
func _drawn_curve(points: PackedVector2Array) -> PackedVector2Array:
	var line := PackedVector2Array()
	if points.size() == 3:
		var control: Vector2 = 2.0 * points[1] - 0.5 * (points[0] + points[2])
		for i in 201:
			var t: float = float(i) / 200.0
			var u: float = 1.0 - t
			line.append(u * u * points[0] + 2.0 * u * t * control + t * t * points[2])
		return line
	var last: int = points.size() - 1
	for span in last:
		var p0: Vector2 = points[maxi(span - 1, 0)]
		var p1: Vector2 = points[span]
		var p2: Vector2 = points[mini(span + 1, last)]
		var p3: Vector2 = points[mini(span + 2, last)]
		for i in 40:
			var t: float = float(i) / 40.0
			var t2: float = t * t
			line.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t2 * t))
	line.append(points[last])
	return line

# A seven-point override reaches the shader whole, in order.
func _check_long_override() -> void:
	var floor_data: Resource = load(FLOOR_3_PATH)
	var saved: PackedVector2Array = floor_data.get("wear_path_override")
	floor_data.set("wear_path_override", PackedVector2Array(ROUTE))
	await _load_field(2)
	var spawn: Vector3 = _field.call("get_spawn_position")
	var points: PackedVector2Array = _points()
	_expect_eq(_count(), ROUTE.size(), "A %d-point override: %d points" % [ROUTE.size(), ROUTE.size()])
	for i in ROUTE.size():
		_expect(points[i].is_equal_approx(Vector2(spawn.x + ROUTE[i].x, spawn.z + ROUTE[i].y)), "...point %d where it was put" % i)
	await _teardown()
	floor_data.set("wear_path_override", saved)
	_completed += 1

# Nine points: the first eight drawn.
func _check_capped_at_eight() -> void:
	var floor_data: Resource = load(FLOOR_3_PATH)
	var saved: PackedVector2Array = floor_data.get("wear_path_override")
	var nine := PackedVector2Array(ROUTE)
	nine.append(Vector2(26, -35))
	nine.append(Vector2(28, -36))
	floor_data.set("wear_path_override", nine)
	await _load_field(2)
	var spawn: Vector3 = _field.call("get_spawn_position")
	_expect_eq(_count(), MAX_POINTS, "Nine points: the band takes %d" % MAX_POINTS)
	_expect(_points()[MAX_POINTS - 1].is_equal_approx(Vector2(spawn.x + nine[MAX_POINTS - 1].x, spawn.z + nine[MAX_POINTS - 1].y)), "...the first %d" % MAX_POINTS)
	await _teardown()
	floor_data.set("wear_path_override", saved)
	_completed += 1

# --- Helpers ---

func _load_field(index: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", index)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _material() -> ShaderMaterial:
	return _field.get_node("Ground").get("_material") as ShaderMaterial

func _points() -> PackedVector2Array:
	var value: Variant = _material().get_shader_parameter("wear_points")
	return value if value is PackedVector2Array else PackedVector2Array()

func _count() -> int:
	return int(_material().get_shader_parameter("wear_point_count"))

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 2:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
