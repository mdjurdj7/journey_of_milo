extends SceneTree

# Headless probe for where fights stage, from the code's own placement:
# every encounter option of every slot on every floor of region 1, stood
# with RegionField.force_options and contacted from the main approach -
# the Wanderer put where the planned path from spawn first meets the
# target's contact zone. Once the battle frame has settled, each fight
# must have:
#   - no combatant on a face: the ground under its feet sloping past
#     FACE_SLOPE_MAX_DEG over half a metre, or rising or falling more
#     than FACE_JUMP_MAX_M within half a metre
#   - the Wanderer at least his minimum spacing (RegionField.stance_
#     distance_min()) from the enemy he faces
#   - the battle camera over the ground where it stands
#   - clear sight from the camera to every combatant's feet: the ground
#     nowhere more than FEET_SIGHT_TOLERANCE_M over the straight line to
#     them - for feet under water, to the water's surface over them (the
#     camera lifts its pitch until this holds, CameraRig.battle_pitch_max_
#     deg)
#   - no prop in the foreground: no corner of a prop's visual bounds in
#     the camera's frustum and PROP_NEARER_M or more nearer to it than the
#     nearest combatant. The fight's own props (its option's - the
#     Wardling's hitching post, the Dunecur's bones) belong in its frame
#     and are left out.
# The limits are this probe's own constants, below. Each fight also gets
# an INFO line - its settled battle pitch and whether the Tower is in its
# frame - never a failure.
# Every failure is printed (FAIL) with its floor, slot and option, and
# the probe goes on to the next fight; it fixes nothing.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/battle_placement_probe.gd
#
# Exit code 0 = every fight staged cleanly, 1 = any failure. Untyped
# against anything that names the RunState autoload.

const REGION_PATH := "res://floors/region1.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FACE_SLOPE_MAX_DEG := 30.0
const FACE_JUMP_MAX_M := 0.35
# How far past the contact zone's edge he is put, metres - just outside it.
const APPROACH_MARGIN := 0.3
# Above the ground at the camera, metres.
const CAMERA_GROUND_MIN := 0.3
# A prop is in the foreground only this much nearer the camera than the
# nearest combatant, metres.
const PROP_NEARER_M := 1.5
# The most of the frame's bottom fifth that terrain in front of the fight
# may cover, and how far over the lowest combatant's feet a hit must
# stand to count as terrain in the way rather than the fight's floor.
# How far the ground may stand over a sight line to the feet, metres -
# CameraRig.battle_feet_sight_tolerance_m.
const FEET_SIGHT_TOLERANCE_M := 0.05
# Points along the Tower's height tried for the INFO line.
const TOWER_SAMPLES := 12
# An encounter prop is the spawned one of its scene within this of where
# its slot puts it, metres.
const OWN_PROP_MATCH_M := 0.5
# A combatant's middle, metres over its feet, for the sight line.
const BODY_MIDDLE := 0.75
# The most game time the battle frame may take to settle (ProbePlay.
# settle_fight()), seconds - a cap, not a wait.
const SETTLE_MAX_SECONDS := 8.0
const SAFETY_SECONDS := 900.0

var _run_state: Node = null
var _field: Node = null
var _floor_data: FloorData = null
var _failures: int = 0
var _fights: int = 0
var _clean: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var region: Resource = load(REGION_PATH)
	var floors: Array = region.get("floors")
	for floor_index in floors.size():
		_floor_data = floors[floor_index] as FloorData
		for slot in _floor_data.slots:
			if slot == null:
				continue
			for option in slot.options:
				if option != null:
					await _check_fight(floor_index, slot, option)
	print("battle_placement_probe: %d of %d fights staged cleanly" % [_clean, _fights])
	if _failures == 0:
		print("battle_placement_probe: PASSED")
		quit(0)
	else:
		print("battle_placement_probe: %d FAILED" % _failures)
		quit(1)

func _check_fight(floor_index: int, slot: EncounterSlot, option: EncounterOption) -> void:
	var label: String = "Floor %d %s/%s" % [floor_index + 1, slot.slot_id, option.option_id]
	_fights += 1
	var failures_before: int = _failures
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	var forced: Dictionary[StringName, StringName] = {}
	forced[slot.slot_id] = option.option_id
	_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = _target_for(slot.slot_id)
	if target == null:
		_fail("%s: no enemy of the slot on the field" % label)
		await _teardown()
		return
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var ground: Node = _field.get_node("Ground")
	var spawn: Vector3 = _field.call("get_spawn_position")
	wanderer.global_position = _approach_point(spawn, target, ground)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() > 0:
		await ProbePlay.settle_fight(self, _field, layer.get_child(0).get("battle_controller"), SETTLE_MAX_SECONDS)
	var members: Array = _field.get("_battle_members")
	if members.is_empty():
		_fail("%s: no fight started" % label)
		await _teardown()
		return
	var anchor: Node3D = members[0]
	# Faces.
	for body: Node3D in [wanderer] + members:
		var face: Vector2 = _face_at(ground, _flat(body.global_position))
		if face.x > FACE_SLOPE_MAX_DEG or face.y > FACE_JUMP_MAX_M:
			_fail("%s: %s stands on a face at %s (%.1f degrees, %.2f m within half a metre)" % [label, _name_of(body, wanderer), _flat(body.global_position).snapped(Vector2(0.01, 0.01)), face.x, face.y])
	# His spacing.
	var gap: float = _flat(wanderer.global_position).distance_to(_flat(anchor.global_position))
	var minimum: float = float(_field.call("stance_distance_min", anchor))
	if gap < minimum - 0.01:
		_fail("%s: the Wanderer %.2f m from %s, under his minimum %.2f" % [label, gap, _name_of(anchor, wanderer), minimum])
	# The camera over the ground where it stands.
	var camera: Camera3D = _field.get_node("CameraPivot").get("camera")
	var under: float = float(ground.call("get_height_at", _flat(camera.global_position)))
	if camera.global_position.y - under < CAMERA_GROUND_MIN:
		_fail("%s: the battle camera is %.2f m over the ground" % [label, camera.global_position.y - under])
	# Sight to every combatant's feet.
	var nearest: float = INF
	var sea_level: float = float(_field.get_node("Sea").get("sea_level"))
	for body: Node3D in [wanderer] + members:
		var feet: Vector3 = body.global_position
		nearest = minf(nearest, camera.global_position.distance_to(feet + Vector3.UP * BODY_MIDDLE))
		feet.y = maxf(feet.y, sea_level)
		var blocked: float = _ground_over_ray(ground, camera.global_position, feet)
		if blocked > FEET_SIGHT_TOLERANCE_M:
			_fail("%s: the ground rises %.2f m over the camera's sight line to %s's feet" % [label, blocked, _name_of(body, wanderer)])
	# Props in the foreground - the fight's own left out.
	var own: Array[Node] = _own_props(slot, option, spawn)
	var props: Node = _field.get_node_or_null(^"Props")
	if props != null:
		for prop in props.get_children():
			if own.has(prop):
				continue
			var bounds: AABB = _visual_bounds(prop as Node3D)
			if not bounds.has_volume():
				continue
			for corner in 8:
				var point: Vector3 = bounds.get_endpoint(corner)
				if camera.is_position_in_frustum(point) and camera.global_position.distance_to(point) <= nearest - PROP_NEARER_M:
					_fail("%s: the prop %s is in the battle frame's foreground (%.1f m from the camera, the nearest combatant %.1f m)" % [label, prop.name, camera.global_position.distance_to(point), nearest])
					break
	# For the record: the pitch the frame settled at, and the Tower.
	print("INFO: %s: battle pitch %.0f degrees; the Tower %s" % [label, float(_field.get_node("CameraPivot").get("_battle_pitch_now")), "in frame" if _tower_in_frame(camera) else "not in frame"])
	if _failures == failures_before:
		_clean += 1
		print("%s: staged cleanly" % label)
	await _teardown()

# The slot's member the contact is made on: its anchor, else its first.
func _target_for(slot_id: StringName) -> Node3D:
	var first: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if node.get("slot_id") != slot_id:
			continue
		if bool(node.get("anchor")):
			return node as Node3D
		if first == null:
			first = node as Node3D
	return first

# Where the planned walk from spawn first comes within the target's
# contact zone, APPROACH_MARGIN short of it, on the ground - or, with no
# plan, the same distance out from the target toward spawn.
func _approach_point(spawn: Vector3, target: Node3D, ground: Node) -> Vector3:
	var reach: float = float(target.get("contact_radius")) + APPROACH_MARGIN
	var path: PackedVector3Array = _field.call("plan_path", spawn, target.global_position, target, true)
	var point := Vector3.INF
	for index in range(path.size() - 1, 0, -1):
		var a: Vector3 = path[index - 1]
		var b: Vector3 = path[index]
		if _flat(a).distance_to(_flat(target.global_position)) >= reach:
			var t: float = 1.0
			for step in 40:
				var at: Vector3 = a.lerp(b, float(step) / 40.0)
				if _flat(at).distance_to(_flat(target.global_position)) < reach:
					t = float(step - 1) / 40.0
					break
			point = a.lerp(b, maxf(t, 0.0))
			break
	if point == Vector3.INF:
		var back: Vector2 = (_flat(spawn) - _flat(target.global_position)).normalized()
		point = target.global_position + Vector3(back.x, 0.0, back.y) * reach
	point.y = float(ground.call("get_height_at", _flat(point)))
	return point

# The props the fight's option placed (EncounterOption.props, top level):
# the spawned prop of each one's scene within OWN_PROP_MATCH_M of where
# its slot puts it.
func _own_props(slot: EncounterSlot, option: EncounterOption, spawn: Vector3) -> Array[Node]:
	var own: Array[Node] = []
	var props: Node = _field.get_node_or_null(^"Props")
	if props == null:
		return own
	for entry in option.props:
		if entry == null or entry.scene == null or entry.parent_index >= 0:
			continue
		var at: Vector2 = _flat(spawn) + slot.to_floor(Vector2(entry.position.x, entry.position.z))
		for prop in props.get_children():
			if prop.scene_file_path == entry.scene.resource_path and _flat((prop as Node3D).global_position).distance_to(at) <= OWN_PROP_MATCH_M:
				own.append(prop)
	return own

# Whether any point up the Tower's height is in `camera`'s frustum.
func _tower_in_frame(camera: Camera3D) -> bool:
	var tower := _field.get_node_or_null(^"Tower") as VisualInstance3D
	if tower == null:
		return false
	var box: AABB = tower.global_transform * tower.get_aabb()
	var base := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	for sample in TOWER_SAMPLES:
		if camera.is_position_in_frustum(base + Vector3.UP * box.size.y * float(sample) / float(TOWER_SAMPLES - 1)):
			return true
	return false

# The most the ground rises over the straight ray from `from` to `to`
# (sampled along its length, ends left out), metres; 0 or less is clear.
func _ground_over_ray(ground: Node, from: Vector3, to: Vector3) -> float:
	var worst: float = -INF
	for step in range(2, 59):
		var point: Vector3 = from.lerp(to, float(step) / 60.0)
		worst = maxf(worst, float(ground.call("get_height_at", _flat(point))) - point.y)
	return worst

# The merged world bounds of every visual under `node`.
func _visual_bounds(node: Node3D) -> AABB:
	var bounds := AABB()
	var started: bool = false
	if node == null:
		return bounds
	for child in node.find_children("*", "VisualInstance3D", true, false):
		var visual := child as VisualInstance3D
		var box: AABB = visual.global_transform * visual.get_aabb()
		bounds = box if not started else bounds.merge(box)
		started = true
	return bounds

func _face_at(ground: Node, at: Vector2) -> Vector2:
	var e: float = 0.25
	var gx: float = (float(ground.call("get_height_at", at + Vector2(e, 0.0))) - float(ground.call("get_height_at", at - Vector2(e, 0.0)))) / (2.0 * e)
	var gz: float = (float(ground.call("get_height_at", at + Vector2(0.0, e))) - float(ground.call("get_height_at", at - Vector2(0.0, e)))) / (2.0 * e)
	var here: float = float(ground.call("get_height_at", at))
	var jump: float = 0.0
	for k in 8:
		var angle: float = TAU * float(k) / 8.0
		jump = maxf(jump, absf(float(ground.call("get_height_at", at + Vector2(cos(angle), sin(angle)) * 0.5)) - here))
	return Vector2(rad_to_deg(atan(Vector2(gx, gz).length())), jump)

func _name_of(body: Node3D, wanderer: Node3D) -> String:
	if body == wanderer:
		return "the Wanderer"
	var data: Resource = body.get("enemy_data")
	return String(data.get("enemy_name")) if data != null else String(body.name)

func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
