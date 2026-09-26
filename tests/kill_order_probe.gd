extends SceneTree

# Headless regression probe for the fight's win-and-cleanup path. Loads
# the real region scene on floor 2 and floor 1, starts a fight by calling
# RegionField's contact handler on the pack's nearest member (a teleport
# doesn't move a body through the physics server, so the Area never
# fires headless), and kills the members the way _resolve_play() does -
# _report_damage() inside the resolution, _check_battle_end() after -
# in seven orders:
#
#   one_at_a_time      - one kill per turn, three turns; the last is
#                        queued on its Swarm as its last packmate dies,
#                        and must be queued on something else after
#   carve_two          - two in one card, then the last alone
#   carve_three        - all three in one card
#   last_normal        - two in one card, the last by a single attack
#   pair_anchor_first  - floor 2's required crab and its dragonfly, the
#                        crab first
#   pair_other_first   - the same pair, the dragonfly first
#   floor1_crab        - the one required crab on floor 1
#
# and asserts, after the win and the reward beat: no member of the pack
# left on the field, an EnemyStatus left under the HUD for each enemy
# outside the fight and none more (the rest of floor 2; none on floor 1),
# floor_cleared emitted by floor 1's crab and floor 2's pair and NOT by
# the optional island pack, no fight left open. The pair is contacted at
# its dragonfly from the west - the dragonfly nearest the Wanderer - and
# the crab (FloorEnemy.anchor) must still head the line.
#
# Run it before committing anything that touches region_field.gd,
# field_enemy.gd or battle_controller.gd, and say in the commit that it
# passed:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/kill_order_probe.gd
#
# Exit code 0 = every case passed, 1 = a failure (each printed as FAIL).
# Deliberately untyped against the project's own classes (get()/call()
# only): a SceneTree script is compiled before the autoloads register,
# and naming FieldEnemy or RunState at that point fails region_field.gd's
# compile with "Identifier not found: RunState" - the noise the ordinary
# compile probe exists to avoid.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const ENEMY_STATUS_SCRIPT_SUFFIX := "enemy_status.gd"
# Well past any case's own timings; a hang here quits with a failure
# rather than leaving a headless process behind.
const SAFETY_SECONDS := 240.0
# Physics frames after the last kill for the settle (0.4 s), the win's
# frees and the reward delay (0.6 s) to land.
const SETTLE_FRAMES := 90

var _field: Node3D = null
var _failures: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var run_state: Node = root.get_node("RunState")
	run_state.call("new_run", load(STARTING_CHARACTER_PATH))

	for order in ["one_at_a_time", "carve_two", "carve_three", "last_normal"]:
		run_state.set("current_floor_index", 1)
		await _run_case(order, &"island", false)
	for order in ["pair_anchor_first", "pair_other_first"]:
		run_state.set("current_floor_index", 1)
		await _run_case(order, &"crab", true)
	run_state.set("current_floor_index", 0)
	await _run_case("floor1_crab", &"", true)

	print("\nkill_order_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)

# One floor load, one fight, one kill order, the assertions.
# group: the FloorEnemy.group of the pack to fight (&"" = an ungrouped
# enemy, floor 1's crab). expect_cleared: whether the win clears the
# floor. The EnemyStatus count expected after it is the enemies outside
# the fight, counted from the field.
func _run_case(order: String, group: StringName, expect_cleared: bool) -> void:
	print("\n=== case: ", order)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	for i in 30:
		await physics_frame

	var pack: Array[Node3D] = []
	for node in get_nodes_in_group("enemies"):
		if node.get("group") == group:
			pack.append(node as Node3D)
	if pack.is_empty():
		_fail(order, "no enemies with group '%s' on the field" % group)
		await _teardown()
		return

	# The Wanderer stands just east of the easternmost member - the
	# island's approach - and that member is the contact. The crab's pair
	# the other way round: west of its westernmost, the dragonfly, so the
	# member he touches is not the one that anchors.
	var west: bool = group == &"crab"
	var side: float = -1.0 if west else 1.0
	var anchor: Node3D = pack[0]
	for member in pack:
		if member.global_position.x * side > anchor.global_position.x * side:
			anchor = member
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = anchor.global_position + Vector3(1.5 * side, 0.0, 0.0)
	await physics_frame
	# Deferred: RegionField's own handler runs from an Area signal, i.e.
	# never inside a physics callback, and disabling collision objects
	# from one is refused.
	_field.call_deferred("_on_enemy_contacted", anchor)
	for i in 10:
		await physics_frame

	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail(order, "no fight started")
		await _teardown()
		return
	var overlay: Node = layer.get_child(0)
	var controller: Node = overlay.get("battle_controller")
	var members: Array = (controller.get("enemies") as Array).duplicate()
	var combatants: Dictionary = controller.get("_combatants")
	print("fight members: ", members.size())
	if west:
		_check(order, members.size() == 2, "%d member(s) in the pair's fight, expected 2" % members.size())
		_check(order, members[0].get("anchor") == true, "'%s' heads the line, not the anchor" % members[0].name)


	match order:
		"one_at_a_time":
			var last: Node = members.back()
			for member in members:
				if member == members[members.size() - 2]:
					_check(order, _queue_simultaneous(combatants, last), "no simultaneous intent to queue on '%s'" % last.name)
				elif member == last:
					_check(order, not _queued_simultaneous(combatants, last), "the last of the pack is still queued on its Swarm")
				_kill(controller, combatants, member)
				controller.call("_check_battle_end")
				await create_timer(0.6).timeout
		"floor1_crab", "pair_anchor_first":
			for member in members:
				_kill(controller, combatants, member)
				controller.call("_check_battle_end")
				await create_timer(0.6).timeout
		"pair_other_first":
			var reversed: Array = members.duplicate()
			reversed.reverse()
			for member in reversed:
				_kill(controller, combatants, member)
				controller.call("_check_battle_end")
				await create_timer(0.6).timeout
		"carve_two", "last_normal":
			_kill(controller, combatants, members[0])
			_kill(controller, combatants, members[1])
			controller.call("_check_battle_end")
			await create_timer(0.6).timeout
			_kill(controller, combatants, members[2])
			controller.call("_check_battle_end")
		"carve_three":
			for member in members:
				_kill(controller, combatants, member)
			controller.call("_check_battle_end")

	for i in SETTLE_FRAMES:
		await physics_frame

	var left: int = 0
	var expect_statuses: int = 0
	for node in get_nodes_in_group("enemies"):
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			continue
		if node.get("group") == group:
			left += 1
			print("   still standing: ", node.name, " status=", node.get("enemy_status") != null)
		else:
			expect_statuses += 1
	var statuses: int = _status_count()
	var battle_open: bool = _field.get("_battle_open")
	var cleared: bool = _field.get("_floor_cleared_emitted")
	print("result: members left=%d statuses=%d battle_open=%s floor_cleared=%s" % [left, statuses, battle_open, cleared])

	_check(order, left == 0, "%d member(s) left on the field" % left)
	_check(order, statuses == expect_statuses, "%d EnemyStatus left under the HUD, expected %d" % [statuses, expect_statuses])
	_check(order, not battle_open, "the fight is still open")
	_check(order, layer.get_child_count() == 0, "the overlay is still up")
	_check(order, cleared == expect_cleared, "floor_cleared emitted=%s, expected %s" % [cleared, expect_cleared])
	await _teardown()

# What a card's damage does to a member, without the card: HP to 0, the
# hit reported through the controller's own path (which drops the member
# and emits enemy_defeated).
func _kill(controller: Node, combatants: Dictionary, member: Node) -> void:
	var combatant: RefCounted = combatants.get(member)
	if combatant == null:
		print("   (no combatant for ", member.name, ")")
		return
	combatant.set("hp", 0)
	controller.call("_report_damage", "player", combatant, 14, "card")

# Queues `member` on the first simultaneous intent (the Swarm) in its
# loop; false when it has none.
func _queue_simultaneous(combatants: Dictionary, member: Node) -> bool:
	var intents: Array = member.get("enemy_data").get("intents")
	for index in intents.size():
		if intents[index].get("simultaneous"):
			combatants.get(member).set("current_intent_index", index)
			return true
	return false

func _queued_simultaneous(combatants: Dictionary, member: Node) -> bool:
	var intents: Array = member.get("enemy_data").get("intents")
	var index: int = combatants.get(member).get("current_intent_index")
	return intents[index].get("simultaneous")

# EnemyStatus controls still alive under the field HUD.
func _status_count() -> int:
	var hud: Node = _field.get_node_or_null("FieldHUD")
	if hud == null:
		return -1
	var count: int = 0
	for child in hud.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(ENEMY_STATUS_SCRIPT_SUFFIX) and not child.is_queued_for_deletion():
			count += 1
	return count

func _check(order: String, condition: bool, message: String) -> void:
	if not condition:
		_fail(order, message)

func _fail(order: String, message: String) -> void:
	_failures += 1
	print("FAIL [%s]: %s" % [order, message])

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	await process_frame
