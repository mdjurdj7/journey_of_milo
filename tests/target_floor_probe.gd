extends SceneTree

# Headless probe for the enemy target floor: every enemy is a click and
# hover target at least RegionField.min_target_size_px each way, grown
# about its own centre (FieldEnemy.get_pick_rect()), on the field and in
# a fight alike. Guards the Nettles that were specks to hunt for. On floor
# 4 with its Nettlebasket pack stood (force_options):
#   - the field: each Nettle's pick rect at least the floor, about the
#     centre of its padded screen rect, and a click inside the floor but
#     outside that rect still picks an enemy
#   - the fight: the controller reads the field's floor; each Nettle's
#     target at least the floor, about the same centre; the Nettlebasket,
#     past the floor both ways, its padded rect unchanged; and a click on
#     a Nettle's grown edge, clear of every other target, hits it
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/target_floor_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 2
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const NETTLE_PATH := "res://battle/rules/enemies/nettle.tres"
const NETTLEBASKET_PATH := "res://battle/rules/enemies/nettlebasket.tres"
const FLOOR_4 := 3
const SLOT_ID := &"nettlebasket"
const OPTION_ID := &"nettlebasket"
# Half a pixel either way: the grown rect's edges are floats.
const EPSILON_PX := 0.5
# How far inside a grown edge the edge click lands.
const EDGE_INSET_PX := 2.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	await _load()
	if _field != null:
		await _check_field()
		await _check_fight()
	await _teardown()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("target_floor_probe: PASSED")
		quit(0)
	else:
		print("target_floor_probe: %d FAILED" % _failures)
		quit(1)

# On the field: the Nettles' pick rects, and a click in a Nettle's floor
# but outside its padded rect.
func _check_field() -> void:
	var camera: Camera3D = _field.get_viewport().get_camera_3d()
	var floor_px: float = float(_field.get("min_target_size_px"))
	var padding: float = float(_field.get("click_target_padding_px"))
	var nettles: Array[Node] = _of(get_nodes_in_group("enemies"), NETTLE_PATH)
	_expect(not nettles.is_empty(), "The pack stands its Nettles")
	for nettle: Node in nettles:
		var raw: Rect2 = nettle.call("get_screen_rect", camera, padding)
		if raw.size == Vector2.ZERO:
			print("INFO: a Nettle is behind the field camera; not checked there")
			continue
		var pick: Rect2 = nettle.call("get_pick_rect", camera, padding, floor_px)
		_check_floor("Field: a Nettle", raw, pick, floor_px)
		var outside: Vector2 = _edge_point(raw, pick)
		if outside != Vector2.INF:
			_expect(_field.call("_enemy_under_cursor", camera, outside) != null, "Field: a click on a Nettle's grown edge picks an enemy")
	_completed += 1

# In a fight with the pack: the floor the controller reads, each target's
# size, the Nettlebasket's unchanged, and an edge click.
func _check_fight() -> void:
	var basket: Node = _first(_of(get_nodes_in_group("enemies"), NETTLEBASKET_PATH))
	if basket == null:
		_fail("no Nettlebasket on floor 4")
		_completed += 1
		return
	_field.call_deferred("_on_enemy_contacted", basket)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on the Nettlebasket")
		_completed += 1
		return
	var controller: Node = overlay.get("battle_controller")
	await ProbePlay.settle_fight(self, _field, controller)
	var floor_px: float = float(_field.get("min_target_size_px"))
	_expect_eq(float(controller.get("min_target_size_px")), floor_px, "The fight reads the field's floor")
	var camera: Camera3D = _field.get_viewport().get_camera_3d()
	var padding: float = float(controller.get("target_padding_px"))
	controller.call("_refresh_enemy_rects")
	var rects: Dictionary = controller.get("_enemy_rects")
	var members: Array = controller.get("enemies")
	for member: Node in members:
		var raw: Rect2 = member.call("get_screen_rect", camera, padding)
		var target: Rect2 = rects.get(member, Rect2())
		if _is(member, NETTLE_PATH):
			_check_floor("Fight: a Nettle", raw, target, floor_px)
			var edge: Vector2 = _edge_point(raw, target)
			if edge == Vector2.INF:
				continue
			var clear: bool = true
			for other: Node in members:
				if other != member and (rects.get(other, Rect2()) as Rect2).has_point(edge):
					clear = false
			if clear:
				_expect(controller.call("_enemy_at", edge) == member, "Fight: a click on a Nettle's grown edge, clear of the rest, hits it")
			else:
				print("INFO: a Nettle's grown edge at %s meets another target; the nearer wins there" % edge.round())
		elif _is(member, NETTLEBASKET_PATH) and raw.size.x >= floor_px and raw.size.y >= floor_px:
			_expect(target.is_equal_approx(raw), "Fight: the Nettlebasket, past the floor, keeps its padded rect")
	_completed += 1

# A target at least the floor each way, about the padded rect's centre.
func _check_floor(label: String, raw: Rect2, pick: Rect2, floor_px: float) -> void:
	_expect(pick.size.x >= floor_px - EPSILON_PX and pick.size.y >= floor_px - EPSILON_PX, "%s's target is at least %d px each way (%s)" % [label, int(floor_px), pick.size.round()])
	_expect(pick.get_center().distance_to(raw.get_center()) <= EPSILON_PX, "%s's target keeps its centre" % label)

# A point inside `pick`, just inside its edge, outside `raw` - INF when
# the floor added nothing there.
func _edge_point(raw: Rect2, pick: Rect2) -> Vector2:
	var centre: Vector2 = pick.get_center()
	for point: Vector2 in [Vector2(pick.position.x + EDGE_INSET_PX, centre.y), Vector2(centre.x, pick.position.y + EDGE_INSET_PX)]:
		if pick.has_point(point) and not raw.has_point(point):
			return point
	return Vector2.INF

func _load() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	var forced: Dictionary[StringName, StringName] = {}
	forced[SLOT_ID] = OPTION_ID
	_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _of(nodes: Array[Node], data_path: String) -> Array[Node]:
	var found: Array[Node] = []
	for node in nodes:
		if _is(node, data_path):
			found.append(node)
	return found

func _is(node: Node, data_path: String) -> bool:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return false
	var data: Resource = node.get("enemy_data")
	return data != null and data.resource_path == data_path

func _first(nodes: Array[Node]) -> Node:
	return nodes[0] if not nodes.is_empty() else null

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
