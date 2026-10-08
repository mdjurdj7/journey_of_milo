extends SceneTree

# Headless regression probe for a LINE floor's exit (FloorData.exit_kind,
# ExitGate.setup_hold_line(), the Wanderer's Hold Line group): while a
# required fight stands he won't cross the gate line, however he moves,
# and once the floor is cleared he walks on into the trigger. Loads the
# real region scene: floor 1 only to check it is still a CHANNEL floor
# with no line, then floor 2, and runs in order:
#
#   click  - from the worn band's end, GATE_APPROACH_M short of the line,
#            a click target well past it: he eases to rest ON the line,
#            hold_line_reached fires once, he turns to face the nearest
#            required enemy, and the world line is said over him - at
#            a fixed point (where he stopped, at head height) that stays
#            put as he then walks back WALK_AWAY_SECONDS (and returns)
#   keys   - move_forward held into the line, then move_forward and
#            move_right together: he stays on it, and slides along it
#   dash   - a dash straight at it from DASH_START_M short: reined in
#   rearm  - set back REARM_START_M, a click past the line again: a
#            second arrival, a second look back, and no second line
#   open   - ExitGate.open() (what floor_cleared calls): the line lifts,
#            and the same click walks him into the TriggerArea
#
# Fails on: any frame past the line by more than OVERSHOOT_LIMIT_M before
# open(); at rest further short of it than SHORT_LIMIT_M; an arrival
# count other than expected; the look back not within FACING_LIMIT_DEG
# of the enemy after LOOK_SECONDS; the world line said other than once,
# or with other text; floor_exited before open(), or not after it; floor
# 1 holding a line or floor 2 having a channel. It also prints how the
# stop and the turn measure - rest time, stop point, turn time, where
# the enemy and the line land on screen - for the report, not the gate.
#
# Run it before committing anything that touches the hold line (wanderer.
# gd's Hold Line group, exit_gate.gd's LINE mode, RegionField's hold-line
# handler):
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/hold_line_probe.gd
#
# Exit code 0 = every check passed. Untyped against the project's own
# classes (get()/call() only), for the autoload reason kill_order_probe.
# gd's own header gives.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const CHANNEL_FLOOR_INDEX := 0
const LINE_FLOOR_INDEX := 1
const SAFETY_SECONDS := 200.0
const LOAD_FRAMES := 30
const SETTLE_FRAMES := 30
const GATE_APPROACH_M := 6.0
const PAST_LINE_TARGET_M := 5.0
const DASH_START_M := 3.0
const REARM_START_M := 2.0
const CASE_SECONDS := 3.0
const LOOK_SECONDS := 2.0
const OVERSHOOT_LIMIT_M := 0.02
const SHORT_LIMIT_M := 0.10
const FACING_LIMIT_DEG := 10.0
const EXPECTED_LINE := "Not with that still behind him."
# The click case's walk back from the line, while its world line is up.
const WALK_AWAY_SECONDS := 0.8
const WALK_AWAY_M := 4.0
const ANCHOR_LIMIT_M := 0.01

var _failures: int = 0
var _field: Node3D = null
var _wanderer: CharacterBody3D = null
var _gate: Node3D = null
var _forward: Vector3 = Vector3.ZERO
var _right: Vector3 = Vector3.ZERO
var _reached: int = 0
var _exited: bool = false
var _opened: bool = false
var _worst_past_m: float = -INF
var _line_shows: int = 0
var _line_texts: Array[String] = []
var _line_was_visible: bool = false
# The turn, timed from the arrival itself: frames since it, the facing
# still to go then, and when 90% of it was done.
var _frame: int = 0
var _arrival_frame: int = -1
var _arrival_error_deg: float = 0.0
var _turn_90_frame: int = -1

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var run_state: Node = root.get_node("RunState")
	run_state.call("new_run", load(STARTING_CHARACTER_PATH))

	await _load_floor(run_state, CHANNEL_FLOOR_INDEX)
	print("\n=== floor 1")
	_check(not bool(_wanderer.call("has_hold_line")), "floor 1 holds no line")
	_check(int(_gate.get("exit_kind")) == 0, "floor 1's gate is a CHANNEL")
	await _unload()

	await _load_floor(run_state, LINE_FLOOR_INDEX)
	print("\n=== floor 2")
	_check(int(_gate.get("exit_kind")) == 1, "floor 2's gate is a LINE")
	_check(bool(_wanderer.call("has_hold_line")), "floor 2 holds a line")
	_check((_field.get_node("Ground").get("channels") as Array).is_empty(), "floor 2 has no channel")
	_check((_gate.get("blocker_shape") as CollisionShape3D).disabled, "floor 2's Blocker is off")
	# Nothing may start a fight meanwhile; the enemies still stand.
	for node in get_nodes_in_group("enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	_wanderer.connect("hold_line_reached", _on_reached)
	_gate.connect("floor_exited", func() -> void: _exited = true)
	_forward = -_gate.global_transform.basis.z
	_forward.y = 0.0
	_forward = _forward.normalized()
	_right = Vector3(-_forward.z, 0.0, _forward.x)
	var monitor := LineMonitor.new()
	monitor.probe = self
	monitor.process_priority = 1000
	monitor.process_physics_priority = 1000
	root.add_child(monitor)

	await _case_click()
	await _case_keys()
	await _case_dash()
	await _case_rearm()
	await _case_open()

	print("\n--- line: said %d time(s) %s; worst past the line before open %+.3f m" % [_line_shows, _line_texts, _worst_past_m])
	_check(_line_shows == 1, "the world line is said once")
	_check(_line_texts.size() == 1 and _line_texts[0] == EXPECTED_LINE, "the world line reads '%s'" % EXPECTED_LINE)
	_check(_worst_past_m <= OVERSHOOT_LIMIT_M, "never past the line before open (worst %+.3f m)" % _worst_past_m)
	monitor.queue_free()
	await _unload()
	print("\nhold_line_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)

# Runs after the Wanderer every physics frame: how far past the line he
# is, and each time the world line fades up from nothing.
class LineMonitor extends Node:
	var probe: Object = null

	func _physics_process(_delta: float) -> void:
		probe.call("_monitor")

func _on_reached() -> void:
	_reached += 1
	_arrival_frame = _frame
	_arrival_error_deg = _look_error_deg()
	_turn_90_frame = -1

# Degrees between his facing and the nearest required enemy's bearing.
func _look_error_deg() -> float:
	var enemy: Node3D = _field.call("_nearest_required_enemy", _wanderer.global_position) as Node3D
	if enemy == null:
		return 0.0
	var to_enemy: Vector3 = enemy.global_position - _wanderer.global_position
	return absf(rad_to_deg(angle_difference(_wanderer.rotation.y, atan2(-to_enemy.x, -to_enemy.z))))

func _monitor() -> void:
	if _wanderer == null or _gate == null:
		return
	_frame += 1
	if _arrival_frame >= 0 and _turn_90_frame < 0 and _look_error_deg() <= _arrival_error_deg * 0.1:
		_turn_90_frame = _frame
	if not _opened:
		_worst_past_m = maxf(_worst_past_m, _along())
	var line := _field.get_node_or_null("FieldHUD/WorldVoiceLine") as Label
	var visible: bool = line != null and line.modulate.a > 0.001
	if visible and not _line_was_visible:
		_line_shows += 1
		_line_texts.append(line.text)
	_line_was_visible = visible

func _case_click() -> void:
	print("\n=== case: click")
	await _place(-GATE_APPROACH_M)
	var reached_before: int = _reached
	_wanderer.call("set_move_target", _gate.global_position + _forward * PAST_LINE_TARGET_M)
	var rest_seconds: float = await _run_until_rest(CASE_SECONDS)
	var arrived_at: Vector3 = _wanderer.global_position
	print("at rest after %.2f s, %+.3f m along the line's normal, at (%.2f, %.2f)" % [rest_seconds, _along(), arrived_at.x, arrived_at.z])
	_check_at_line("click")
	_check(_reached == reached_before + 1, "click: one arrival (%d)" % (_reached - reached_before))
	await _check_look_back("click")
	await _report_screen()
	await _check_line_anchor_fixed(arrived_at)

func _case_keys() -> void:
	print("\n=== case: keys")
	var reached_before: int = _reached
	Input.action_press("move_forward")
	await _frames(CASE_SECONDS)
	print("forward held: %+.3f m along" % _along())
	_check_at_line("keys forward")
	var across_before: float = _wanderer.global_position.dot(_right)
	Input.action_press("move_right")
	await _frames(1.0)
	var slid: float = _wanderer.global_position.dot(_right) - across_before
	Input.action_release("move_right")
	Input.action_release("move_forward")
	await _frames(0.5)
	print("forward+right held 1 s: slid %+.2f m along the line, %+.3f m along its normal" % [slid, _along()])
	_check(slid > 1.0, "keys: slides along the line (%.2f m)" % slid)
	_check_at_line("keys slide")
	_check(_reached == reached_before, "keys: no new arrival without leaving (%d)" % (_reached - reached_before))

func _case_dash() -> void:
	print("\n=== case: dash")
	await _place(-DASH_START_M)
	Input.action_press("move_forward")
	Input.action_press("dash")
	await physics_frame
	Input.action_release("dash")
	await _frames(1.5)
	Input.action_release("move_forward")
	await _frames(0.5)
	print("dash from %.1f m: %+.3f m along" % [DASH_START_M, _along()])
	_check_at_line("dash")

func _case_rearm() -> void:
	print("\n=== case: rearm")
	await _place(-REARM_START_M)
	var reached_before: int = _reached
	_wanderer.call("set_move_target", _gate.global_position + _forward * PAST_LINE_TARGET_M)
	await _run_until_rest(CASE_SECONDS)
	_check_at_line("rearm")
	_check(_reached == reached_before + 1, "rearm: a second arrival (%d)" % (_reached - reached_before))
	await _check_look_back("rearm")

func _case_open() -> void:
	print("\n=== case: open")
	_check(not _exited, "no floor_exited before open")
	_opened = true
	_gate.call("open")
	_check(not bool(_wanderer.call("has_hold_line")), "open lifts the line")
	_wanderer.call("set_move_target", _gate.global_position + _forward * PAST_LINE_TARGET_M)
	var elapsed: float = 0.0
	while not _exited and elapsed < CASE_SECONDS:
		await physics_frame
		elapsed += 1.0 / 60.0
	print("after open: floor_exited %s at %+.2f m along" % [_exited, _along()])
	_check(_exited, "open: he walks into the trigger")

# Where he stops and what the frame holds there: the nearest required
# enemy's screen position, the line's box, and his own head and feet.
func _report_screen() -> void:
	var camera: Camera3D = root.get_camera_3d()
	if camera == null:
		print("screen: no camera")
		return
	var size: Vector2 = root.get_visible_rect().size
	var enemy: Node3D = _field.call("_nearest_required_enemy", _wanderer.global_position) as Node3D
	if enemy != null:
		var at: Vector2 = camera.unproject_position(enemy.global_position)
		print("screen %dx%d: enemy '%s' at (%.0f, %.0f)%s, %.2f m from him" % [size.x, size.y, enemy.get("enemy_id"), at.x, at.y, "" if Rect2(Vector2.ZERO, size).has_point(at) else " - OUT OF FRAME", enemy.global_position.distance_to(_wanderer.global_position)])
	var head: Vector2 = camera.unproject_position(_wanderer.global_position + Vector3.UP * float(_wanderer.call("get_head_height")))
	var feet: Vector2 = camera.unproject_position(_wanderer.global_position)
	print("screen: his head (%.0f, %.0f), feet (%.0f, %.0f)" % [head.x, head.y, feet.x, feet.y])
	var line := _field.get_node_or_null("FieldHUD/WorldVoiceLine") as Label
	if line != null:
		var font: Font = line.get_theme_font("font")
		var text_width: float = font.get_string_size(line.text, HORIZONTAL_ALIGNMENT_LEFT, -1, line.get_theme_font_size("font_size")).x if font != null else 0.0
		print("screen: line box %s, text ~%.0f px wide, a %.2f" % [Rect2(line.position, line.size), text_width, line.modulate.a])

# The world line sits over a fixed point - where he stopped, at head
# height plus the line's clearance - and stays there while he walks away.
func _check_line_anchor_fixed(arrived_at: Vector3) -> void:
	var line := _field.get_node_or_null("FieldHUD/WorldVoiceLine") as Label
	if line == null:
		_check(false, "anchor: the world line exists")
		return
	var spoken: Variant = line.call("get_anchor_point")
	_check(spoken is Vector3, "anchor: the line is still over a world point")
	if not spoken is Vector3:
		return
	var height: float = float(_wanderer.call("get_head_height")) + float(_field.get("hold_line_world_line_head_clearance"))
	var expected: Vector3 = arrived_at + Vector3.UP * height
	_check((spoken as Vector3).distance_to(expected) <= ANCHOR_LIMIT_M, "anchor: said over where he stopped, at head height (%s vs %s)" % [spoken, expected])
	var from: Vector3 = _wanderer.global_position
	_wanderer.call("set_move_target", from - _forward * WALK_AWAY_M)
	for i in roundi(WALK_AWAY_SECONDS * 60.0):
		await physics_frame
	var moved: float = from.distance_to(_wanderer.global_position)
	var after: Variant = line.call("get_anchor_point")
	print("anchor: he walked %.2f m; line over %s" % [moved, after])
	_check(moved > 0.5, "anchor: he walked away from the line (%.2f m)" % moved)
	_check(after is Vector3 and (after as Vector3).distance_to(spoken as Vector3) <= ANCHOR_LIMIT_M, "anchor: the line stayed where it was said (%s, then %s)" % [spoken, after])
	# Back to rest on the line, where the keys case starts from (that
	# arrival is before its own count).
	_wanderer.call("set_move_target", _gate.global_position + _forward * PAST_LINE_TARGET_M)
	await _run_until_rest(CASE_SECONDS)

func _check_look_back(label: String) -> void:
	var enemy: Node3D = _field.call("_nearest_required_enemy", _wanderer.global_position) as Node3D
	if enemy == null:
		_check(false, "%s: a required enemy to look back at" % label)
		return
	await _frames(LOOK_SECONDS)
	var end_error: float = _look_error_deg()
	var ninety_seconds: float = float(_turn_90_frame - _arrival_frame) / 60.0 if _turn_90_frame >= 0 else -1.0
	print("%s: look back %.0f deg to go at arrival, 90%% of it turned %.2f s after, %.1f deg off %.1f s later" % [label, _arrival_error_deg, ninety_seconds, end_error, LOOK_SECONDS])
	_check(end_error <= FACING_LIMIT_DEG, "%s: faces the enemy (%.1f deg off)" % [label, end_error])

func _check_at_line(label: String) -> void:
	var along: float = _along()
	_check(along <= OVERSHOOT_LIMIT_M and along >= -SHORT_LIMIT_M, "%s: at the line (%+.3f m)" % [label, along])

# Metres past the line along its normal - negative is short of it.
func _along() -> float:
	return (_wanderer.global_position - _gate.global_position).dot(_forward)

# Stands him `along` metres from the line (negative = short of it), on the
# gate's own line across, facing forward, and lets him settle.
func _place(along: float) -> void:
	_wanderer.call("clear_move_target")
	var spot: Vector3 = _gate.global_position + _forward * along
	var ground: Node = _field.get_node("Ground")
	var local: Vector3 = (ground as Node3D).to_local(Vector3(spot.x, 0.0, spot.z))
	spot.y = float(ground.call("get_height_at", Vector2(local.x, local.z))) + 0.05
	_wanderer.global_position = spot
	_wanderer.velocity = Vector3.ZERO
	_wanderer.rotation.y = atan2(-_forward.x, -_forward.z)
	for i in SETTLE_FRAMES:
		await physics_frame

# Frames until he is at rest (planar speed under the walk threshold) and
# has no click target left, or `limit` seconds; returns the time taken.
func _run_until_rest(limit: float) -> float:
	var elapsed: float = 0.0
	var threshold: float = float(_wanderer.get("walk_speed_threshold"))
	while elapsed < limit:
		await physics_frame
		elapsed += 1.0 / 60.0
		var speed: float = Vector2(_wanderer.velocity.x, _wanderer.velocity.z).length()
		if speed < threshold and not bool(_wanderer.call("has_move_target")) and elapsed > 0.2:
			return elapsed
	return elapsed

func _frames(seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		await physics_frame

func _load_floor(run_state: Node, index: int) -> void:
	run_state.set("current_floor_index", index)
	run_state.set("run_opening_pending", false)
	run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	for i in LOAD_FRAMES:
		await physics_frame
	_wanderer = _field.get_node("Wanderer") as CharacterBody3D
	_gate = _field.get_node("ExitGate") as Node3D

func _unload() -> void:
	_field.queue_free()
	_field = null
	_wanderer = null
	_gate = null
	for i in 5:
		await physics_frame

func _check(ok: bool, what: String) -> void:
	print("%s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1
