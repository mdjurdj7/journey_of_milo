extends SceneTree

# Headless probe for elite rewards: a fight with an elite in it (EnemyData.
# is_elite - the Wardling) pays the floor's gold times RegionField.
# elite_gold_multiplier, rounded, and rolls its card at the pool's elite
# rarity rates (no Common while a higher tier has a card); floor 5's
# region-end Greyshelf (FloorEnemy.card_reward TOP_TIER_FIRST) offers
# three distinct cards from the top tier down - three Rares while Ultra
# Rare is empty - at the floor's own gold, with its Glassbone; an
# ordinary fight - alone or a cluster - none of it. The reward screen's
# gold and rates are read straight off it.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/elite_reward_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Field cases load the real region scene and start fights through
# RegionField's contact handler, the way glassbone_probe does. Untyped
# against anything that names the RunState autoload: a SceneTree script
# compiles before the autoloads register. Each elite range is disjoint
# from its floor's own (15-22 against 23-33 on floor 3; 35-45 against
# 53-68 on floor 5), so landing in one says which rule paid.

const CASES := 4
const RARITY_FINISH_PATH := "res://battle/card_rarity_finish.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const REGION_PATH := "res://floors/region1.tres"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const BLACKBACK_PATH := "res://battle/rules/enemies/blackback.tres"
const FLOOR_1 := 0
const FLOOR_3 := 2
const FLOOR_5 := 4
const SAFETY_SECONDS := 300.0

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
	await _check_wardling()
	await _check_ordinary(FLOOR_1, SPUTTER_PATH, "The floor 1 Sputter")
	await _check_ordinary(FLOOR_3, BLACKBACK_PATH, "The Blackback and its Nipper")
	await _check_region_end()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("elite_reward_probe: PASSED")
		quit(0)
	else:
		print("elite_reward_probe: %d FAILED" % _failures)
		quit(1)

# The Wardling: elite gold (floor 3's 15-22 x 1.5 -> 23-33) and elite
# rates; its three cards, taken from the screen, hold no Common.
func _check_wardling() -> void:
	var reward: Node = await _win(FLOOR_3, WARDLING_PATH)
	if reward != null:
		var multiplier: float = float(_field.get("elite_gold_multiplier"))
		_expect(is_equal_approx(multiplier, 1.5), "elite_gold_multiplier is 1.5")
		var span: Vector2i = _gold_range(FLOOR_3)
		var low: int = roundi(span.x * multiplier)
		var high: int = roundi(span.y * multiplier)
		var gold: int = int(reward.get("_gold"))
		_expect(gold >= low and gold <= high, "The Wardling pays elite gold, %d-%d (got %d)" % [low, high, gold])
		_expect(bool(reward.get("_elite_rates")), "...and rolls its card at the elite rates")
		var card_index: int = _line_ids(reward).find("card")
		_expect(card_index >= 0, "...with a card line")
		if card_index >= 0:
			reward.call("_take_line", card_index)
			var offered: Array = reward.get("_offered")
			_expect_eq(offered.size(), 3, "...three cards offered")
			for card: CardData in offered:
				_expect(card.rarity != CardData.CardRarity.COMMON, "...none Common (%s)" % card.card_name)
			_check_offer_tiers(reward, offered)
		reward.call("close")
	await _teardown()
	_completed += 1

# An ordinary fight: the floor's own gold, the normal rates.
func _check_ordinary(floor_index: int, enemy_path: String, label: String) -> void:
	var reward: Node = await _win(floor_index, enemy_path)
	if reward != null:
		var span: Vector2i = _gold_range(floor_index)
		var gold: int = int(reward.get("_gold"))
		_expect(gold >= span.x and gold <= span.y, "%s pays the floor's gold, %d-%d (got %d)" % [label, span.x, span.y, gold])
		_expect(not bool(reward.get("_elite_rates")), "...at the normal rates")
		_expect(not bool(reward.get("_top_tier")), "...not top tier first")
		reward.call("close")
	await _teardown()
	_completed += 1

# Floor 5's region-end Greyshelf, placed with card_reward TOP_TIER_FIRST:
# not elite, so the floor's own gold and no elite rates; its card line
# offers three distinct cards from the top tier down - three Rares while
# no Ultra Rare exists - and its Glassbone x1 is a line of its own.
func _check_region_end() -> void:
	var region: Resource = load(REGION_PATH)
	var floors: Array = region.get("floors")
	var placement: Resource = (floors[FLOOR_5].get("enemies") as Array)[0]
	_expect_eq(int(placement.get("card_reward")), FloorEnemy.CardReward.TOP_TIER_FIRST, "Floor 5's region-end fight is placed TOP_TIER_FIRST")
	_expect_eq((placement.get("enemy_data") as Resource).resource_path, GREYSHELF_PATH, "...the Greyshelf")
	_expect(not bool((placement.get("enemy_data") as Resource).get("is_elite")), "...not elite")
	var reward: Node = await _win(FLOOR_5, GREYSHELF_PATH)
	if reward != null:
		var span: Vector2i = _gold_range(FLOOR_5)
		var gold: int = int(reward.get("_gold"))
		_expect(gold >= span.x and gold <= span.y, "It pays floor 5's own gold, %d-%d (got %d)" % [span.x, span.y, gold])
		_expect(not bool(reward.get("_elite_rates")), "...not at the elite rates")
		_expect(bool(reward.get("_top_tier")), "...but top tier first")
		_expect_eq(int(reward.get("_glassbone")), 1, "...and Glassbone x1")
		_expect(_line_ids(reward).has("glassbone"), "...on a line of its own")
		var card_index: int = _line_ids(reward).find("card")
		_expect(card_index >= 0, "...with a card line")
		if card_index >= 0:
			reward.call("_take_line", card_index)
			var offered: Array = reward.get("_offered")
			_expect_eq(offered.size(), 3, "...three cards offered")
			var names: Array[String] = []
			for card: CardData in offered:
				_expect_eq(card.rarity, CardData.CardRarity.RARE, "...each a Rare (%s)" % card.card_name)
				if not names.has(card.card_name):
					names.append(card.card_name)
			_expect_eq(names.size(), offered.size(), "...all distinct")
			_check_offer_tiers(reward, offered)
		reward.call("close")
	await _teardown()
	_completed += 1

# --- Helpers ---

# The open choice names each card's tier under it - the right word,
# centred under its own face, below its bottom edge - and each card's
# name sheened once as the offer arrived (none for a Common).
func _check_offer_tiers(reward: Node, offered: Array) -> void:
	var finish := load(RARITY_FINISH_PATH) as CardRarityFinish
	var faces: Array = reward.get("_choice_faces")
	var views: Array = reward.get("_card_views")
	_expect_eq(faces.size(), offered.size(), "...a face rect per offered card")
	for index in mini(faces.size(), offered.size()):
		var card: CardData = offered[index]
		var face: Rect2 = faces[index]
		_expect_eq(str(reward.call("tier_label_at", index)), finish.tier_label_text(card.rarity), "...%s's tier named under it" % card.card_name)
		var origin: Vector2 = reward.call("tier_label_origin", index)
		_expect(origin.y > face.end.y and origin.x >= face.position.x and origin.x < face.get_center().x, "...below its own face (%s at %s, face %s)" % [card.card_name, origin, face])
		var view: CardView = views[index]
		var expected: int = 1 if finish.has_finish(card.rarity) else 0
		_expect_eq(view.get_name_sheens_started(), expected, "...and its name sheened %d time(s) on arrival" % expected)

# A new run on the floor, the fight with the first enemy whose data is
# `enemy_path` won, and the reward screen it opens - or null (a FAIL is
# recorded).
func _win(floor_index: int, enemy_path: String) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == enemy_path:
			target = node as Node3D
			break
	if target == null:
		_fail("no %s on floor %d" % [enemy_path, floor_index + 1])
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	_kill_all(overlay.get("battle_controller"))
	await create_timer(1.6).timeout
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	if reward == null:
		_fail("winning on floor %d opened no reward screen" % (floor_index + 1))
	return reward

func _gold_range(floor_index: int) -> Vector2i:
	var region: Resource = load(REGION_PATH)
	var floor_data: Resource = (region.get("floors") as Array)[floor_index]
	return Vector2i(int(floor_data.get("gold_min")), int(floor_data.get("gold_max")))

# Every member to 0 through the controller's own damage path, then the
# end check - kill_order_probe's _kill().
func _kill_all(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: RefCounted = combatants.get(member)
		if combatant == null:
			continue
		combatant.set("hp", 0)
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

func _line_ids(reward: Node) -> Array[String]:
	var ids: Array[String] = []
	for line in reward.get("_lines") as Array:
		ids.append(str((line as RefCounted).get("id")))
	return ids

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

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
	print("FAIL: " + message)
