extends SceneTree

# Headless probe for the worn band's centreline (Ground.set_wear_path(),
# RegionField._aim_wear_path()): what each floor hands the ground shader.
# Floors 1 and 2 derive their three points (spawn, past the first enemy,
# the gate) and floor 3 overrides with its own three - all still the one
# three-point curve. A longer override (4 to 8 points) is handed over
# whole and in order, for the shader's chain through every point; past 8
# the rest are dropped. Headless has no renderer, so this reads the
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

# Floors 1-3: three points each, the one curve as ever - floors 1 and 2
# from spawn to their gate, floor 3 on its own override.
func _check_three_point_floors() -> void:
	for index in 3:
		await _load_field(index)
		var points: PackedVector2Array = _points()
		_expect_eq(_count(), 3, "Floor %d: a three-point band" % (index + 1))
		var spawn: Vector3 = _field.call("get_spawn_position")
		_expect(points.size() == MAX_POINTS and points[0].is_equal_approx(Vector2(spawn.x, spawn.z)), "...starting at spawn")
		var floor_data: Resource = _field.call("get_floor_data")
		var override: PackedVector2Array = floor_data.get("wear_path_override")
		if override.size() >= 3:
			for i in 3:
				_expect(points[i].is_equal_approx(Vector2(spawn.x + override[i].x, spawn.z + override[i].y)), "...point %d its override's" % i)
		else:
			var gate: Node3D = _field.get_node("ExitGate")
			_expect(points[2].is_equal_approx(Vector2(gate.global_position.x, gate.global_position.z)), "...ending at the gate")
		await _teardown()
	_completed += 1

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
