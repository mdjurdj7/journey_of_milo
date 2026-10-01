extends SceneTree

# Headless probe for the field HUD's GOLD line: it shows the run's gold
# as it stands when the field loads, add_gold() sets its target at once,
# the count-up lands on the exact total (a second add mid-count included),
# and it sits at the end of the row, on TOLL's bottom edge.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/gold_line_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Loads the real region scene, as glassbone_probe does. Untyped against
# anything that names the RunState autoload (RegionField, the HUD lines):
# a SceneTree script compiles before the autoloads register.

const CASES := 3
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 120.0

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
	await _check_starting_value()
	await _check_count_up()
	await _check_row_place()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("gold_line_probe: PASSED")
		quit(0)
	else:
		print("gold_line_probe: %d FAILED" % _failures)
		quit(1)

# GOLD reads what the run holds when the field loads - 0 on a new run,
# and a carried total as it stands, with no count from 0.
func _check_starting_value() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	_expect(line.visible, "GOLD is shown on 0")
	_expect_eq(str(line.get("label_text")), "GOLD", "...under the label GOLD")
	_expect_eq(str(line.get("_value_text")), "0", "...reading 0 on a new run")
	await _teardown()
	_new_run()
	_run_state.call("add_gold", 23)
	await _load_field()
	_expect_eq(str(_gold_line().get("_value_text")), "23", "A carried 23 shows as 23 at once")
	await _teardown()
	_completed += 1

# add_gold() sets the target at once; the numeral counts and lands on the
# exact total - and on the new one when a second add comes mid-count.
func _check_count_up() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	var count_time: float = float(line.get("count_up_time"))
	_run_state.call("add_gold", 37)
	_expect_eq(int(line.get("_target")), 37, "add_gold(37) sets the target to 37 at once")
	await create_timer(count_time * 0.4).timeout
	var mid: int = int(str(line.get("_value_text")))
	_expect(mid > 0 and mid < 37, "...the numeral is counting (%d mid-way)" % mid)
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "37", "...and lands on exactly 37")
	_run_state.call("add_gold", 18)
	_expect_eq(int(line.get("_target")), 55, "A second add retargets to 55")
	await create_timer(count_time * 0.4).timeout
	_run_state.call("add_gold", 9)
	_expect_eq(int(line.get("_target")), 64, "...and a third, mid-count, to 64")
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "64", "...landing on exactly 64")
	_expect_eq(int(_run_state.get("gold")), 64, "RunState holds 64")
	await _teardown()
	_completed += 1

# The end of the row: past TOLL with KEEPSAKE and GLASSBONE hidden, past
# GLASSBONE once that shows, on TOLL's bottom edge.
func _check_row_place() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	var toll_line: Control = _field.get_node("FieldHUD/TollLine")
	var glassbone_line: Control = _field.get_node("FieldHUD/GlassboneLine")
	var toll_right: float = toll_line.position.x + toll_line.size.x
	_expect(line.position.x > toll_right and line.position.x < toll_right + 40.0, "GOLD sits right beside TOLL while KEEPSAKE and GLASSBONE are hidden")
	_run_state.call("add_glassbone", 1)
	await process_frame
	_expect(line.position.x > glassbone_line.position.x + glassbone_line.size.x, "...and moves past GLASSBONE once it shows")
	_expect_eq(line.position.y + line.size.y, toll_line.position.y + toll_line.size.y, "...on the same bottom edge as TOLL")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _gold_line() -> Control:
	return _field.get_node("FieldHUD/GoldLine") as Control

func _load_field() -> void:
	_run_state.set("current_floor_index", 0)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: " + message)
