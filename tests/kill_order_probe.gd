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
#   card_kill_then_turn - the first killed by a real Slash played at it
#                        (request_play() / confirm_target()), then End
#                        Turn: the enemy turn must run through without a
#                        script error, the two left alive and the next
#                        player turn begun - then the two killed
#   pair_anchor_first  - floor 2's required pair, the Sputter and the
#                        Underfoot, the Sputter first
#   pair_other_first   - the same pair, the Underfoot first
#   floor1_crab        - the one required crab on floor 1
#   nettlebasket       - floor 4's Nettlebasket and her three Nettles:
#                        while she hasn't Signalled, a Nettle shows no
#                        intent and takes no turn; the Nettles killed,
#                        she never queues her Signal again and her
#                        queued move changes from turn to turn - then
#                        she is killed
#
# and asserts, after the win and the reward beat: no member of the pack
# left on the field, an EnemyStatus left under the HUD for each enemy
# outside the fight and none more (the rest of floor 2; none on floor 1),
# floor_cleared emitted by floor 1's crab and floor 2's pair and NOT by
# the optional island pack, no fight left open. The pair is contacted at
# its Underfoot from the west - the Underfoot nearest the Wanderer - and
# the Sputter (FloorEnemy.anchor) must still head the line.
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
const SAFETY_SECONDS := 300.0
# After the last kill, the fight waits on its blow and the last death
# before it is won (BattleController._maybe_win()): up to WIN_WAIT_SECONDS
# for that, then physics frames for the win's frees and the reward delay
# (0.6 s) to land.
const WIN_WAIT_SECONDS := 6.0
const SETTLE_FRAMES := 90
const SLASH_PATH := "res://cards/data/slash.tres"
# card_kill_then_turn: the enemy turn after the kill, up to this long.
const ENEMY_TURN_WAIT_SECONDS := 20.0
# Frames the field runs on once the killed body is freed, for anything
# still reading it.
const BODY_GONE_FRAMES := 30

# Every script error while installed (OS.add_logger()) - one doesn't stop
# a headless probe, it just abandons the function (the game, under the
# debugger, stops on it), so a case that must run clean counts them itself.
class ErrorCounter extends Logger:
	var errors: Array[String] = []
	var _lock: Mutex = Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT:
			return
		_lock.lock()
		errors.append("%s:%d %s(): %s" % [file, line, function, rationale if rationale != "" else code])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass

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
	# A deck of Slashes, so the first hand has the single-target card;
	# the starting deck back after.
	var starting_deck: Variant = run_state.get("deck")
	var slashes: Array[CardData] = []
	for i in 10:
		slashes.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
	run_state.set("deck", slashes)
	run_state.set("current_floor_index", 1)
	await _run_case("card_kill_then_turn", &"island", false)
	run_state.set("deck", starting_deck)
	for order in ["pair_anchor_first", "pair_other_first"]:
		run_state.set("current_floor_index", 1)
		await _run_case(order, &"crab", true)
	run_state.set("current_floor_index", 0)
	await _run_case("floor1_crab", &"", true)
	run_state.set("current_floor_index", 3)
	await _run_case("nettlebasket", &"nettlebasket", false)

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
	# Floor 2's island stands its trio - the orders above are three kills -
	# and its crab the Sputter's pair, whichever way the run's seed would
	# roll them.
	var force: Dictionary[StringName, StringName] = {&"island": &"dragonfly_trio", &"crab": &"sputter_underfoot"}
	_field.set("force_options", force)
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
	# the other way round: west of its westernmost, the Underfoot, so the
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
		"nettlebasket":
			await _check_nettlebasket(order, controller, combatants, members)
		"card_kill_then_turn":
			await _check_card_kill_then_turn(order, controller, combatants, members)

	var start: int = ProbePlay.cap_msec()
	while bool(_field.get("_battle_open")) and ProbePlay.cap_msec() - start < int(WIN_WAIT_SECONDS * 1000.0):
		await physics_frame
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

# Floor 4's Nettlebasket (members[0], the anchor) and her Nettles. Turn
# by turn until she has Signalled: before her Signal a Nettle shows no
# intent and takes no turn (Combatant.dormant); after it, none sleeps.
# Then the Nettles killed, three enemy turns: never her Signal queued
# again (pack_only), and not one move every turn. Her own move order and
# numbers are left alone. Then she is killed.
func _check_nettlebasket(order: String, controller: Node, combatants: Dictionary, members: Array) -> void:
	await ProbePlay.settle_fight(self, _field, controller)
	var basket: Node = members[0]
	var nettles: Array = members.slice(1)
	_check(order, nettles.size() == 3, "%d Nettle(s) in her fight, expected 3" % nettles.size())
	var basket_data: Resource = basket.get("enemy_data")
	var signalled: bool = false
	for turn in basket_data.get("intents").size():
		var queued: Resource = _queued_intent(combatants, basket)
		var signal_turn: bool = int(queued.get("type")) == EnemyIntent.IntentType.SIGNAL
		for nettle in nettles:
			_check(order, (controller.call("get_intent_preview", nettle) as Dictionary).is_empty(), "'%s' shows an intent before the Signal" % nettle.name)
		await controller.call("end_turn")
		await ProbePlay.settle(self, controller)
		for nettle in nettles:
			var nettle_combatant: RefCounted = combatants.get(nettle)
			if signal_turn:
				_check(order, not bool(nettle_combatant.get("dormant")), "'%s' still dormant after her Signal" % nettle.name)
			else:
				_check(order, bool(nettle_combatant.get("dormant")) and int(nettle_combatant.get("turns_taken")) == 0, "'%s' took a turn before her Signal" % nettle.name)
		if signal_turn:
			signalled = true
			break
	_check(order, signalled, "she never Signalled in a loop of her moves")
	for nettle in nettles:
		_kill(controller, combatants, nettle)
	controller.call("_check_battle_end")
	await create_timer(0.6).timeout
	var seen: Array[String] = []
	for turn in 3:
		var queued: Resource = _queued_intent(combatants, basket)
		_check(order, int(queued.get("type")) != EnemyIntent.IntentType.SIGNAL, "her Signal queued with no Nettle left")
		if not seen.has(str(queued.get("intent_name"))):
			seen.append(str(queued.get("intent_name")))
		await controller.call("end_turn")
		await ProbePlay.settle(self, controller)
	_check(order, seen.size() > 1, "alone, she queued one move every turn (%s)" % ", ".join(seen))
	_kill(controller, combatants, basket)
	controller.call("_check_battle_end")

# Floor 2's island trio: the first dragonfly killed by a Slash played at
# it through the hand, as a player would, its death seen through; then End
# Turn, and the enemy turn must finish, the two others alive and the next
# player turn begun - and no script error from the kill until its body is
# freed and the field has run on past it (the fight's first member, which
# RegionField read every frame once it was gone). Then the two are killed.
func _check_card_kill_then_turn(order: String, controller: Node, combatants: Dictionary, members: Array) -> void:
	await ProbePlay.settle_fight(self, _field, controller)
	_check(order, members.size() == 3, "%d dragonfly(s) in the fight, expected 3" % members.size())
	var errors := ErrorCounter.new()
	OS.add_logger(errors)
	var first: Node = members[0]
	var first_combatant: RefCounted = combatants.get(first)
	# One Slash's worth left, so the card is the kill.
	first_combatant.set("hp", 1)
	controller.get("player").set("energy", 99)
	var views: Array = controller.get("_hand_container").call("_card_views")
	_check(order, not views.is_empty(), "no card in hand to play")
	if not views.is_empty():
		controller.call("request_play", views[0])
		if bool(controller.call("is_awaiting_target")):
			controller.call("confirm_target", first)
		await ProbePlay.settle(self, controller)
		_check(order, await ProbePlay.settle_kills(self, controller), "the Slash's kill never settled")
	_check(order, int(first_combatant.get("hp")) <= 0, "the Slash left the first dragonfly at %d HP" % int(first_combatant.get("hp")))
	var turn_before: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	var turned: bool = await ProbePlay.wait_until(self, func() -> bool:
		return int(controller.get("_player_turn")) > turn_before and ProbePlay.is_settled(controller), ENEMY_TURN_WAIT_SECONDS)
	_check(order, turned, "the enemy turn after the kill never handed back a player turn")
	var freed: bool = await ProbePlay.wait_until(self, func() -> bool:
		return not is_instance_valid(first), ENEMY_TURN_WAIT_SECONDS)
	_check(order, freed, "the first dragonfly's body was never freed")
	for i in BODY_GONE_FRAMES:
		await process_frame
	OS.remove_logger(errors)
	if not errors.errors.is_empty():
		_fail(order, "%d script error(s) after the kill, the first: %s" % [errors.errors.size(), errors.errors[0]])
	var alive: int = 0
	for member in members.slice(1):
		var combatant: RefCounted = combatants.get(member)
		if combatant != null and int(combatant.get("hp")) > 0:
			alive += 1
	_check(order, alive == 2, "%d dragonfly(s) alive after the enemy turn, expected 2" % alive)
	for member in members.slice(1):
		_kill(controller, combatants, member)
	controller.call("_check_battle_end")

func _queued_intent(combatants: Dictionary, member: Node) -> Resource:
	var intents: Array = member.get("enemy_data").get("intents")
	return intents[int(combatants.get(member).get("current_intent_index"))]

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
