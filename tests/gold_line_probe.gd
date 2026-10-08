extends SceneTree

# Headless probe for the field HUD's GOLD line and the row's counting
# numerals: GOLD shows the run's gold as it stands when the field loads,
# add_gold() sets its target at once, the count eases out and lands on
# the exact total (a second add mid-count included), a spend counts down
# the same way, a hud_count_sec edit mid-count re-times the running
# count, HP / TOLL / DECK count too (and show at once on a load), and
# GOLD sits between TOLL and GLASSBONE -
# DECK, HP, TOLL, GOLD, GLASSBONE, then KEEPSAKE set apart - on TOLL's
# bottom edge.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/gold_line_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Loads the real region scene, as glassbone_probe does. Untyped against
# anything that names the RunState autoload (RegionField, the HUD lines):
# a SceneTree script compiles before the autoloads register.

const CASES := 6
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 120.0
# The row's count, stretched from its 0.35 s default so a mid-count read
# stays mid-count through a headless frame hitch.
const PROBE_COUNT_SEC := 1.0

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
	await _check_spend_counts_down()
	await _check_retime_retargets()
	await _check_other_counts()
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
	var count_time: float = _count_sec(line)
	_run_state.call("add_gold", 37)
	_expect_eq(int(line.get("_count_target")), 37, "add_gold(37) sets the target to 37 at once")
	await create_timer(count_time * 0.4).timeout
	var mid: int = int(str(line.get("_value_text")))
	_expect(mid > 0 and mid < 37, "...the numeral is counting (%d mid-way)" % mid)
	# Ease-out cubic is ~78% of the way at 40% of the time; linear is 40%.
	_expect(mid >= 22, "...eased out, well past the linear 40%% by 40%% of the time (%d of 37)" % mid)
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "37", "...and lands on exactly 37")
	_run_state.call("add_gold", 18)
	_expect_eq(int(line.get("_count_target")), 55, "A second add retargets to 55")
	await create_timer(count_time * 0.4).timeout
	_run_state.call("add_gold", 9)
	_expect_eq(int(line.get("_count_target")), 64, "...and a third, mid-count, to 64")
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "64", "...landing on exactly 64")
	_expect_eq(int(_run_state.get("gold")), 64, "RunState holds 64")
	await _teardown()
	_completed += 1

# A spend counts down the same way - after a count has landed, and
# mid-count too (a lower total re-targets the running count).
func _check_spend_counts_down() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	var count_time: float = _count_sec(line)
	_run_state.call("add_gold", 40)
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "40", "40 counted in")
	_expect(bool(_run_state.call("spend_gold", 15)), "spend_gold(15) goes through")
	_expect_eq(int(line.get("_count_target")), 25, "...the target falls to 25 at once")
	await create_timer(count_time * 0.4).timeout
	var mid: int = int(str(line.get("_value_text")))
	_expect(mid > 25 and mid < 40, "...the numeral counts down (%d mid-way)" % mid)
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "25", "...and lands on exactly 25")
	_run_state.call("add_gold", 30)
	await create_timer(count_time * 0.3).timeout
	_expect(bool(_run_state.call("spend_gold", 50)), "spend_gold(50) mid-count goes through")
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(line.get("_value_text")), "5", "...and the count lands on exactly 5")
	await _teardown()
	_completed += 1

# A hud_count_sec edit (the Remote tab) mid-count re-times the running
# count: from where the numeral stands, over the new time, landing on the
# exact total.
func _check_retime_retargets() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	var row_style: Resource = line.get("style")
	row_style.set("hud_count_sec", 3.0)
	_run_state.call("add_gold", 50)
	await create_timer(0.3).timeout
	var mid: int = int(str(line.get("_value_text")))
	_expect(mid > 0 and mid < 50, "Counting to 50 over 3 s (%d at 0.3 s)" % mid)
	row_style.set("hud_count_sec", 0.2)
	await process_frame
	_expect(int(str(line.get("_value_text"))) >= mid, "...the re-timed count starts from where it stood, not 0")
	await create_timer(0.5).timeout
	_expect_eq(str(line.get("_value_text")), "50", "...and lands on exactly 50 over the new 0.2 s")
	_expect_eq(int(line.get("_count_target")), 50, "...its target still 50")
	await _teardown()
	_completed += 1

# HP, TOLL and DECK count the same way - and a field loaded on a run
# already past its starting values shows them at once.
func _check_other_counts() -> void:
	_new_run()
	_run_state.call("lose_hp", 5)
	_run_state.call("set_toll", 3)
	var hp_before: int = int(_run_state.get("player_hp"))
	var deck_before: int = (_run_state.get("deck") as Array).size()
	await _load_field()
	var hp_line: Control = _field.get_node("FieldHUD/HPLine")
	var toll_line: Control = _field.get_node("FieldHUD/TollLine")
	var deck_panel: Control = _field.get_node("FieldHUD/DeckPanel")
	var count_time: float = _count_sec(hp_line)
	_expect_eq(str(hp_line.get("_value_text")), str(hp_before), "HP shows %d at once on the load" % hp_before)
	_expect_eq(str(toll_line.get("_value_text")), "3", "...TOLL 3")
	_expect_eq(str(deck_panel.call("_row_numeral")), str(deck_before), "...DECK %d" % deck_before)
	_run_state.call("lose_hp", 20)
	_run_state.call("set_toll", 13)
	_run_state.call("add_card", (_run_state.get("deck") as Array)[0])
	await create_timer(count_time * 0.4).timeout
	var hp_mid: int = int(str(hp_line.get("_value_text")))
	_expect(hp_mid < hp_before and hp_mid > hp_before - 20, "HP counts down (%d mid-way)" % hp_mid)
	var toll_mid: int = int(str(toll_line.get("_value_text")))
	_expect(toll_mid > 3 and toll_mid < 13, "...TOLL counts up (%d mid-way)" % toll_mid)
	await create_timer(count_time + 0.3).timeout
	_expect_eq(str(hp_line.get("_value_text")), str(hp_before - 20), "...HP lands on exactly %d" % (hp_before - 20))
	_expect_eq(str(toll_line.get("_value_text")), "13", "...TOLL on exactly 13")
	_expect_eq(str(deck_panel.call("_row_numeral")), str(deck_before + 1), "...DECK on exactly %d" % (deck_before + 1))
	await _teardown()
	_completed += 1

# The row is DECK, HP, TOLL, GOLD, GLASSBONE, then KEEPSAKE set apart:
# GOLD right beside TOLL and never moving as GLASSBONE and KEEPSAKE come;
# GLASSBONE right beside GOLD; KEEPSAKE hud_keepsake_gap_px past GOLD
# while GLASSBONE is hidden and past GLASSBONE once it shows; all on
# TOLL's bottom edge.
func _check_row_place() -> void:
	_new_run()
	await _load_field()
	var line: Control = _gold_line()
	var toll_line: Control = _field.get_node("FieldHUD/TollLine")
	var keepsake_line: Control = _field.get_node("FieldHUD/KeepsakeLine")
	var glassbone_line: Control = _field.get_node("FieldHUD/GlassboneLine")
	var row_style: Resource = line.get("style")
	var item_gap: float = float(row_style.get("hud_item_gap_px"))
	var keepsake_gap: float = float(row_style.get("hud_keepsake_gap_px"))
	var toll_right: float = toll_line.position.x + toll_line.size.x
	_expect(line.visible, "GOLD shows with GLASSBONE and KEEPSAKE hidden")
	_expect_eq(line.position.x, toll_right + item_gap, "GOLD sits hud_item_gap_px beside TOLL")
	var gold_x: float = line.position.x
	var gold_right: float = line.position.x + line.size.x
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	await process_frame
	_expect(keepsake_line.visible, "KEEPSAKE shows once one is held")
	_expect_eq(keepsake_line.position.x, gold_right + keepsake_gap, "...hud_keepsake_gap_px past GOLD while GLASSBONE is hidden")
	_run_state.call("add_glassbone", 1)
	await process_frame
	_expect_eq(glassbone_line.position.x, gold_right + item_gap, "GLASSBONE sits hud_item_gap_px beside GOLD")
	_expect_eq(keepsake_line.position.x, glassbone_line.position.x + glassbone_line.size.x + keepsake_gap, "...and KEEPSAKE moves to hud_keepsake_gap_px past it")
	_expect_eq(line.position.x, gold_x, "GOLD never moved")
	_expect_eq(line.position.y + line.size.y, toll_line.position.y + toll_line.size.y, "GOLD on the same bottom edge as TOLL")
	_expect_eq(glassbone_line.position.y + glassbone_line.size.y, toll_line.position.y + toll_line.size.y, "...and GLASSBONE")
	_expect_eq(keepsake_line.position.y + keepsake_line.size.y, toll_line.position.y + toll_line.size.y, "...and KEEPSAKE")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _count_sec(line: Control) -> float:
	return float((line.get("style") as Resource).get("hud_count_sec"))

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
	var row_style: Resource = _field.get("hud_row_style")
	_expect(is_equal_approx(float(row_style.get("hud_count_sec")), 0.35), "The row counts over 0.35 s by default")
	row_style.set("hud_count_sec", PROBE_COUNT_SEC)

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
