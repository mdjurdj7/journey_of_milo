extends SceneTree

# Headless regression probe for the exit gate's drain and the Wanderer's
# ground hold (Wanderer._hold_above_visible_ground()). While the channel
# drains, the bar surfaces in the shader only; mesh and collision catch
# up in one bake when the tween ends (ExitGate._on_drained()), and the
# hold is what keeps him on the drawn sand in between. The only channel
# he can reach mid-drain is the strip between the near bank and the
# Blocker's near face (the Blocker comes down with the bake), so every
# case stands him there. Loads the real region scene on floor 1 and
# floor 2, and for each drain_seconds in DRAIN_DURATIONS runs:
#
#   stand - on the bar's centre line at the gate line before open(),
#           standing through the drain and the bake
#   walk  - from land WALK_START_ALONG_M spawn-side of the gate line,
#           walking forward into the strip as open() is called, then on
#           along the surfaced bar once the Blocker is down - into the
#           TriggerArea, which sits inside the old Blocker's footprint
#           (RegionField.transition_distance), so the floor ends there
#
# and reports, per case: how many physics frames the hold fired (put him
# back onto the drawn surface) during the drain and after the bake, the
# lowest his feet sat against the drawn surface (what renders), and
# after the bake the lowest against the collision under him and the
# fastest fall. Fails on a sink (feet more than SINK_LIMIT_M under the
# drawn sand), a drop (after the bake: under the collision, falling, or
# not grounded at the end), the hold firing after the bake at all, or a
# walk that never reaches floor_exited. Once floor_exited fires the field
# freezes (RegionField._on_floor_exited()), and so does the recording.
#
# Run it before committing anything that touches exit_gate.gd, the
# channel parts of ground.gd, or the Wanderer's ground hold:
#
#   Godot_v4.7.1.exe --headless --fixed-fps 60 --path . -s res://tests/drain_probe.gd
#
# --fixed-fps 60 gives one physics step and one tween step per frame, so
# the counts repeat run to run. Exit code 0 = every case passed.
#
# The hold has no counter of its own; a firing is read from outside, by a
# monitor node that runs after the Wanderer each physics frame: the hold
# is on, his feet sit exactly on the drawn surface, and they moved this
# frame. A held frame between firings leaves him where the last one put
# him while the sand keeps rising, so it never matches.
#
# Untyped against the project's own classes (get()/call() only), for the
# autoload reason kill_order_probe.gd's own header gives.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const DRAIN_DURATIONS: Array[float] = [4.0, 2.0]
const FLOOR_INDICES: Array[int] = [0, 1]
const SAFETY_SECONDS := 400.0
const LOAD_FRAMES := 30
const SETTLE_FRAMES := 60
# Physics frames past the bake: long enough for a drop to show.
const AFTER_FRAMES := 90
# Along the gate's forward from its line. The strip runs from the near
# bank (ExitGate.channel_near_offset spawn-side) to the Blocker's near
# face (blocker_inland_offset - blocker_depth / 2 inland); these stay
# inside it with the capsule's radius to spare.
const STAND_ALONG_M := 0.0
const WALK_START_ALONG_M := -4.0
const WALK_STRIP_ALONG_M := 0.3
# Past the old Blocker - through the TriggerArea, the floor's end.
const WALK_BAR_ALONG_M := 5.0
const SINK_LIMIT_M := 0.06
const DROP_LIMIT_M := 0.05
const FALL_SPEED_LIMIT := 1.0
const FIRE_EPSILON_M := 0.00001

var _field: Node3D = null
var _failures: int = 0
var _summary: Array[String] = []

# Two of these run every physics frame: one at priority -1000, before the
# Wanderer (what renders: the previous step's position against the sand
# the tween has since raised), one at 1000, after him (whether the hold
# fired this step).
class HoldMonitor extends Node:
	var probe: Object = null
	var after: bool = false

	func _physics_process(_delta: float) -> void:
		if after:
			probe.call("_after_wanderer")
		else:
			probe.call("_before_wanderer")

var _wanderer: CharacterBody3D = null
var _ground: Node3D = null
var _gate: Node3D = null
var _tolerance: float = 0.03
var _drained: bool = false
var _exited: bool = false
var _recording: bool = false
var _y_before: float = 0.0
var _fires_drain: int = 0
var _fires_after: int = 0
var _held_frames: int = 0
var _min_gap_drawn: float = INF
var _min_gap_collision_after: float = INF
var _max_fall_after: float = 0.0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var run_state: Node = root.get_node("RunState")
	run_state.call("new_run", load(STARTING_CHARACTER_PATH))

	for floor_index in FLOOR_INDICES:
		for seconds in DRAIN_DURATIONS:
			for mode in ["stand", "walk"]:
				run_state.set("current_floor_index", floor_index)
				run_state.set("run_opening_pending", false)
				run_state.set("title_pending", false)
				await _run_case(floor_index, seconds, mode)

	print("\n--- summary")
	for line in _summary:
		print(line)
	print("\ndrain_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)

func _run_case(floor_index: int, seconds: float, mode: String) -> void:
	var label: String = "floor %d, %.1f s, %s" % [floor_index + 1, seconds, mode]
	print("\n=== case: ", label)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	for i in LOAD_FRAMES:
		await physics_frame

	# Nothing else on the field may start a fight or cost HP meanwhile.
	for node in get_nodes_in_group("enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	_field.set("wade_drain_enabled", false)

	_wanderer = _field.get_node("Wanderer") as CharacterBody3D
	_ground = _field.get_node("Ground") as Node3D
	_gate = _field.get_node("ExitGate") as Node3D
	_tolerance = float(_wanderer.get("ground_penetration_tolerance_m"))
	_reset_stats()
	_gate.connect("floor_exited", func() -> void: _exited = true)

	var forward: Vector3 = -_gate.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right: Vector3 = Vector3(-forward.z, 0.0, forward.x)
	var bar_line: Vector3 = _gate.global_position + right * float(_gate.get("channel_bar_axis_offset"))
	bar_line.y = 0.0

	var start_along: float = STAND_ALONG_M if mode == "stand" else WALK_START_ALONG_M
	var start: Vector3 = bar_line + forward * start_along
	start.y = _collision_height(start) + 0.3
	_wanderer.global_position = start
	_wanderer.velocity = Vector3.ZERO
	for i in SETTLE_FRAMES:
		await physics_frame
	print("settled at gate-relative along %+.1f m, feet %.3f m, on floor %s" % [start_along, _wanderer.global_position.y, _wanderer.is_on_floor()])

	for after in [false, true]:
		var monitor: HoldMonitor = HoldMonitor.new()
		monitor.probe = self
		monitor.after = after
		monitor.process_physics_priority = 1000 if after else -1000
		_field.add_child(monitor)

	if mode == "walk":
		_wanderer.call("set_move_target", bar_line + forward * WALK_STRIP_ALONG_M)
	_gate.set("drain_seconds", seconds)
	_recording = true
	_gate.call("open")

	var frames: int = 0
	var limit: int = int((seconds + 2.0) * Engine.physics_ticks_per_second)
	while not _drained and frames < limit:
		await physics_frame
		frames += 1
		_drained = (_gate.get("blocker_shape") as CollisionShape3D).disabled
	if not _drained:
		_fail(label, "the gate never finished draining")
		await _teardown()
		return
	print("drained after %d physics frames" % frames)

	if mode == "walk":
		_wanderer.call("set_move_target", bar_line + forward * WALK_BAR_ALONG_M)
	for i in AFTER_FRAMES:
		await physics_frame
	_recording = false

	var along_end: float = (_wanderer.global_position - _gate.global_position).dot(forward)
	var grounded_end: bool = _wanderer.is_on_floor() or bool(_wanderer.get("_ground_hold_active"))
	var line: String = "%s: hold fired %d during the drain (%d frames held), %d after the bake; lowest vs drawn sand %+.3f m; after the bake lowest vs collision %+.3f m, fastest fall %.2f m/s; ended %+.1f m along, grounded %s, floor_exited %s" % [label, _fires_drain, _held_frames, _fires_after, _min_gap_drawn, _min_gap_collision_after, _max_fall_after, along_end, grounded_end, _exited]
	print(line)
	_summary.append(line)

	_check(label, _min_gap_drawn >= -SINK_LIMIT_M, "sank %.3f m under the drawn sand" % -_min_gap_drawn)
	_check(label, _min_gap_collision_after >= -DROP_LIMIT_M, "after the bake, %.3f m under the collision" % -_min_gap_collision_after)
	_check(label, _max_fall_after <= FALL_SPEED_LIMIT, "after the bake, falling at %.2f m/s" % _max_fall_after)
	_check(label, _fires_after == 0, "the hold fired %d time(s) after the bake" % _fires_after)
	_check(label, grounded_end, "not grounded at the end")
	if mode == "walk":
		_check(label, _exited, "never reached floor_exited (ended %+.1f m along)" % along_end)
	else:
		_check(label, not _exited, "floor_exited fired while standing")
	await _teardown()

func _before_wanderer() -> void:
	if not _recording:
		return
	_y_before = _wanderer.global_position.y
	_min_gap_drawn = minf(_min_gap_drawn, _y_before - _drawn_height(_wanderer.global_position))

func _after_wanderer() -> void:
	if not _recording:
		return
	var y: float = _wanderer.global_position.y
	var held: bool = bool(_wanderer.get("_ground_hold_active"))
	var fired: bool = held and absf(y - _drawn_height(_wanderer.global_position)) < FIRE_EPSILON_M and absf(y - _y_before) > FIRE_EPSILON_M
	if _drained:
		if fired:
			_fires_after += 1
		_min_gap_collision_after = minf(_min_gap_collision_after, y - _collision_height(_wanderer.global_position))
		_max_fall_after = maxf(_max_fall_after, -_wanderer.velocity.y)
	else:
		if fired:
			_fires_drain += 1
		if held:
			_held_frames += 1

# The surface as drawn - exactly what the hold itself reads.
func _drawn_height(at: Vector3) -> float:
	var local: Vector3 = _ground.to_local(Vector3(at.x, 0.0, at.z))
	return float(_ground.call("get_visible_height_at", Vector2(local.x, local.z)))

# The collision under a point, by a ray that ignores the Wanderer.
func _collision_height(at: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = _field.get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(Vector3(at.x, 20.0, at.z), Vector3(at.x, -20.0, at.z))
	if _wanderer != null:
		query.exclude = [_wanderer.get_rid()]
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return -INF
	return (hit["position"] as Vector3).y

func _reset_stats() -> void:
	_drained = false
	_exited = false
	_recording = false
	_fires_drain = 0
	_fires_after = 0
	_held_frames = 0
	_min_gap_drawn = INF
	_min_gap_collision_after = INF
	_max_fall_after = 0.0

func _check(label: String, condition: bool, message: String) -> void:
	if not condition:
		_fail(label, message)

func _fail(label: String, message: String) -> void:
	_failures += 1
	print("FAIL [%s]: %s" % [label, message])

func _teardown() -> void:
	_recording = false
	if _field != null:
		_field.queue_free()
		_field = null
	_wanderer = null
	_ground = null
	_gate = null
	await process_frame
