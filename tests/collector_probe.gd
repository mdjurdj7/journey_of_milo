extends SceneTree

# Headless probe for the collector (Collector, CollectorScreen) and
# Samphire, the card it always stocks:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/collector_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
#   placed   - floor 4's FloorData puts a Collector at (11, -22.5) in the
#              east bay, facing west (yaw 90), grounded, with its line and
#              collector_pool, wired to open its screen
#   data     - collector_pool: the 26 Wanderer pool cards and the three
#              neutral pool cards, 29, no starter, no Endure, no Samphire;
#              Samphire in no pool at all; Samphire's own data
#   screen   - a collector on floor 4 opens its screen with the field
#              locked: five rolled cards, distinct, from the pool, then
#              Samphire; prices by rarity; LEAVE closes and unlocks
#   buy      - an affordable card: gold down by its price, deck up one,
#              the slot empty; an unaffordable one: nothing; Samphire
#              bought: in the deck, its slot empty; reopened, the same
#              stock minus both
#   removal  - HAND ONE OVER opens the deck picking, above the screen;
#              a cancel spends nothing; a pick spends 50 and the card
#              leaves; then it's spent - inert, and still on reopening
#   restock  - a new run on a new collector rolls its own stock
#   consumed - Samphire played in a real fight heals 8 (clamped at max
#              HP) and, when the fight ends, has left RunState.deck
#              (RegionField._apply_consumed_removals())
#
# The field cases place their own collector on floor 4 - the probe
# doesn't depend on where floor data puts one. Untyped against anything
# that names the RunState autoload (RegionField, Collector,
# CollectorScreen, DeckView's panel): a SceneTree script compiles before
# the autoloads register.

const CASES := 7
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const COLLECTOR_SCENE_PATH := "res://field/collector.tscn"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const POOLS_DIR := "res://cards/pools/"
const SAMPHIRE_PATH := "res://cards/neutral/samphire.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const RARITY_FINISH_PATH := "res://battle/card_rarity_finish.tres"
const NEUTRAL_IN_STOCK: Array[String] = ["Left Hand", "Second Thoughts", "Untouched"]
const STARTER_ONLY: Array[String] = ["Slash", "Bite Down", "Brace", "Reckoning", "Down Payment"]
const FLOOR_4 := 3
const SPOT := Vector3(11.0, 0.0, -22.5)
const PRICES: Dictionary = {1: 40, 2: 55, 3: 80, 4: 120}
const SAMPHIRE_PRICE := 8
const REMOVAL_PRICE := 50
const STOCK := 5
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _collector: Node3D = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_check_data()
	await _check_placed()
	await _check_screen()
	await _check_buy()
	await _check_removal()
	await _check_restock()
	await _check_consumed()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("collector_probe: PASSED")
		quit(0)
	else:
		print("collector_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var pool := load(COLLECTOR_POOL_PATH) as RewardPool
	var wanderer := load(WANDERER_POOL_PATH) as RewardPool
	var names: Array[String] = []
	for card in pool.entries:
		names.append(card.card_name)
	_expect_eq(names.size(), 29, "collector_pool holds 29 cards")
	for card in wanderer.entries:
		_expect(names.has(card.card_name), "...including the Wanderer pool's %s" % card.card_name)
	for card_name in NEUTRAL_IN_STOCK:
		_expect(names.has(card_name), "...and the neutral %s" % card_name)
	for card_name in STARTER_ONLY:
		_expect(not names.has(card_name), "...never the starter %s" % card_name)
	_expect(not names.has("Endure"), "...nor Endure")
	_expect(not names.has("Samphire"), "...nor Samphire")
	for file in DirAccess.get_files_at(POOLS_DIR):
		if not file.ends_with(".tres"):
			continue
		var any := load(POOLS_DIR + file) as RewardPool
		for card in any.entries:
			_expect(card.resource_path != SAMPHIRE_PATH, "Samphire is in no pool (%s holds it)" % file)
	var samphire := load(SAMPHIRE_PATH) as CardData
	_expect_eq(samphire.card_name, "Samphire", "Samphire")
	_expect(samphire.card_type == CardData.CardType.SKILL and samphire.cost == 1, "...a 1-Energy Skill")
	_expect_eq(samphire.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(samphire.removal_scope, CardData.RemovalScope.CONSUMED, "...Consumed")
	_expect(samphire.effects.size() == 1 and samphire.effects[0].effect_type == CardEffect.EffectType.HEAL and samphire.effects[0].value == 8, "...one Heal for 8")
	_expect_eq(samphire.description, "Heal 8.\nConsumed.", "...reading Heal 8. / Consumed.")
	_completed += 1

# --- Floor 4's own ---

func _check_placed() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 20:
		await physics_frame
	var placed: Array[Node] = get_nodes_in_group("collectors")
	_expect_eq(placed.size(), 1, "Floor 4 places one collector")
	if placed.size() == 1:
		var collector := placed[0] as Node3D
		var spawn: Vector3 = _field.call("get_spawn_position")
		var offset := Vector2(collector.global_position.x - spawn.x, collector.global_position.z - spawn.z)
		_expect(offset.distance_to(Vector2(SPOT.x, SPOT.z)) < 0.01, "...at (11, -22.5) from spawn (got %s)" % offset)
		_expect(is_equal_approx(rad_to_deg(collector.rotation.y), 90.0), "...facing west, yaw 90")
		var ground: Node = _field.get_node("Ground")
		var local: Vector3 = (ground as Node3D).to_local(collector.global_position)
		_expect(absf(collector.global_position.y - float(ground.call("get_height_at", Vector2(local.x, local.z)))) < 0.01, "...grounded on the relief")
		_expect_eq(str(collector.get("world_line")), "It is sorting what it has.", "...with its line")
		_expect_eq((collector.get("stock_pool") as Resource).resource_path, COLLECTOR_POOL_PATH, "...stocked from collector_pool")
		_expect(collector.is_connected("open_requested", Callable(_field, "open_collector_screen")), "...and wired to open its screen")
	await _teardown()
	_completed += 1

# --- The screen ---

func _check_screen() -> void:
	await _load_floor_4(500)
	var screen: Node = _open()
	if screen != null:
		_expect_eq(_field.process_mode, Node.PROCESS_MODE_DISABLED, "The screen locks the field")
		var cards: Array = screen.call("get_slot_cards")
		_expect_eq(cards.size(), STOCK + 1, "Six slots: five rolled, then the fixed one")
		var pool := load(COLLECTOR_POOL_PATH) as RewardPool
		var rolled: Array[String] = []
		for index in STOCK:
			var card: CardData = cards[index]
			_expect(card != null and pool.entries.has(card), "Slot %d is a pool card" % index)
			if card != null:
				_expect(not rolled.has(card.card_name), "...distinct (%s)" % card.card_name)
				rolled.append(card.card_name)
				_expect_eq(int(screen.call("_price_at", index)), int(PRICES[card.rarity]), "...%s at its rarity's price" % card.card_name)
		var fixed: CardData = cards[STOCK]
		_expect(fixed != null and fixed.resource_path == SAMPHIRE_PATH, "The sixth is Samphire")
		_expect(not rolled.has("Samphire"), "...and Samphire is not in the roll")
		_expect_eq(int(screen.call("_price_at", STOCK)), SAMPHIRE_PRICE, "...at 8")
		_check_tiers(screen, cards)
		screen.call("_activate", int(screen.call("_leave_index")))
		await process_frame
		_expect(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "LEAVE closes it")
		_expect_eq(_field.process_mode, Node.PROCESS_MODE_INHERIT, "...and unlocks the field")
	await _teardown()
	_completed += 1

func _check_buy() -> void:
	await _load_floor_4(0)
	var screen: Node = _open()
	if screen != null:
		var cards: Array = screen.call("get_slot_cards")
		var first: CardData = cards[0]
		var price: int = int(PRICES[first.rarity])
		_add_gold(price - 1)
		var deck_before: int = (_run_state.get("deck") as Array).size()
		screen.call("_activate", 0)
		_expect_eq(int(_run_state.get("gold")), price - 1, "Unaffordable by 1: no gold spent")
		_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...no card")
		_expect((screen.call("get_slot_cards") as Array)[0] != null, "...and the card stays")
		_add_gold(1 + SAMPHIRE_PRICE)
		screen.call("_activate", 0)
		_expect_eq(int(_run_state.get("gold")), SAMPHIRE_PRICE, "Affordable: its price spent")
		_expect_eq((_run_state.get("deck") as Array).size(), deck_before + 1, "...the deck one up")
		_expect(_deck_has(first.card_name), "...with %s in it" % first.card_name)
		_expect((screen.call("get_slot_cards") as Array)[0] == null, "...and the slot empty")
		screen.call("_activate", STOCK)
		_expect_eq(int(_run_state.get("gold")), 0, "Samphire bought for 8")
		_expect(_deck_has("Samphire"), "...Samphire in the deck")
		_expect((screen.call("get_slot_cards") as Array)[STOCK] == null, "...its slot empty")
		screen.call("close")
		await process_frame
		var again: Node = _open()
		if again != null:
			var reopened: Array = again.call("get_slot_cards")
			_expect(reopened[0] == null, "Reopened: the bought slot still empty")
			_expect(reopened[STOCK] == null, "...Samphire still gone")
			for index in range(1, STOCK):
				_expect(reopened[index] == cards[index], "...slot %d the same card" % index)
			again.call("close")
	await _teardown()
	_completed += 1

func _check_removal() -> void:
	await _load_floor_4(REMOVAL_PRICE)
	var screen: Node = _open()
	if screen != null:
		var deck_before: int = (_run_state.get("deck") as Array).size()
		screen.call("_activate", int(screen.call("_removal_index")))
		var picker: Node = screen.get("_picker")
		_expect(picker != null and bool(picker.get("pick_mode")), "HAND ONE OVER opens the deck picking")
		if picker != null:
			_expect(int((picker.get_parent() as CanvasLayer).layer) > int(screen.get("layer")), "...above the screen")
			picker.call("close")
			await process_frame
			_expect_eq(int(_run_state.get("gold")), REMOVAL_PRICE, "A cancel spends nothing")
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...and keeps the deck")
			_expect(bool(screen.call("_removal_open")), "...and the removal is still on offer")
		screen.call("_activate", int(screen.call("_removal_index")))
		picker = screen.get("_picker")
		if picker != null:
			var handed: CardData = (_run_state.get("deck") as Array)[0]
			picker.emit_signal("card_picked", handed)
			picker.call("close")
			await process_frame
			_expect_eq(int(_run_state.get("gold")), 0, "A pick spends 50")
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before - 1, "...and the card leaves the deck")
			_expect(not (_run_state.get("deck") as Array).has(handed), "...that very card")
		_add_gold(200)
		_expect(not bool(screen.call("_removal_open")), "Once used, HAND ONE OVER is inert, gold or not")
		screen.call("close")
		await process_frame
		var again: Node = _open()
		if again != null:
			_expect(not bool(again.call("_removal_open")), "...and still spent on reopening")
			again.call("close")
	await _teardown()
	_completed += 1

# A new run, a new collector: its own roll from the reseeded generator.
func _check_restock() -> void:
	var stocks: Array[String] = []
	for run in 3:
		await _load_floor_4(0)
		var screen: Node = _open()
		if screen != null:
			var names: Array[String] = []
			for card: CardData in screen.call("get_slot_cards"):
				names.append(card.card_name if card != null else "-")
			stocks.append(", ".join(names))
			screen.call("close")
		await _teardown()
	_expect(stocks.size() == 3 and not (stocks[0] == stocks[1] and stocks[1] == stocks[2]), "Three new runs don't all roll the same stock (%s)" % " | ".join(stocks))
	_completed += 1

# Samphire in a real fight on floor 1: played, it heals 8 and leaves
# rotation; the fight won, it has left the run's deck. Clamping at max
# HP through the same effect, rules-level.
func _check_consumed() -> void:
	var fresh := Combatant.new(70)
	fresh.hp = 67
	var ctx := EffectContext.new()
	ctx.player = fresh
	HealEffect.new().resolve((load(SAMPHIRE_PATH) as CardData).effects[0], ctx)
	_expect_eq(fresh.hp, 70, "Heal 8 at 67/70 stops at 70")

	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	cards.append((load(SAMPHIRE_PATH) as CardData).duplicate() as CardData)
	for i in 4:
		cards.append((load(BRACE_PATH) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_hp", 20)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_fail("no enemy on floor 1")
	else:
		(_field.get_node("Wanderer") as Node3D).global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
		await physics_frame
		_field.call_deferred("_on_enemy_contacted", target)
		for i in 10:
			await physics_frame
		var layer: Node = _field.get_node("BattleLayer")
		var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
		if overlay == null:
			_fail("no fight started on floor 1")
		else:
			await create_timer(2.5).timeout
			var controller: Node = overlay.get("battle_controller")
			var player: Combatant = controller.get("player")
			var samphire_view: Node = null
			for view: Node in controller.get("_hand_container").call("_card_views"):
				if (view.get("card_data") as CardData).card_name == "Samphire":
					samphire_view = view
			if samphire_view == null:
				_fail("Samphire isn't in the opening hand of five")
			else:
				var hp_before: int = player.hp
				player.energy = 9
				controller.call("request_play", samphire_view)
				for i in 120:
					await process_frame
					if not bool(controller.get("_input_locked")):
						break
				await create_timer(0.6).timeout
				_expect_eq(player.hp, hp_before + 8, "Samphire heals 8 (%d -> %d)" % [hp_before, player.hp])
				var deck: Deck = controller.get("deck")
				_expect(_has_name(deck.exhaust_pile, "Samphire"), "...and leaves rotation")
				_expect(_deck_has("Samphire"), "...still in the run's deck until the fight ends")
				var combatants: Dictionary = controller.get("_combatants")
				for member in (controller.get("enemies") as Array).duplicate():
					var combatant: RefCounted = combatants.get(member)
					if combatant != null:
						combatant.set("hp", 0)
						controller.call("_report_damage", "player", combatant, 99, "card")
				controller.call("_check_battle_end")
				await create_timer(1.6).timeout
				_expect(not _deck_has("Samphire"), "The fight over: Samphire has left RunState.deck")
				_expect_eq((_run_state.get("deck") as Array).size(), 4, "...the deck down to the four Braces")
	await _teardown()
	_completed += 1

# --- Helpers ---

# Each slot - Samphire's too - names its card's tier directly under the
# face, above where the price line sits; and each finished name sheened
# once as the stock arrived.
func _check_tiers(screen: Node, cards: Array) -> void:
	var finish := load(RARITY_FINISH_PATH) as CardRarityFinish
	var views: Array = screen.get("_views")
	for slot in cards.size():
		var card: CardData = cards[slot]
		if card == null:
			continue
		_expect_eq(str(screen.call("tier_label_at", slot)), finish.tier_label_text(card.rarity), "Slot %d (%s) names its tier under it" % [slot, card.card_name])
		var face: Rect2 = screen.call("_slot_rect", slot)
		var origin: Vector2 = screen.call("tier_label_origin", slot)
		var tier_room: float = float(screen.call("_tier_line_height"))
		_expect(origin.y > face.end.y and origin.y <= face.end.y + tier_room, "...between its face and its price (%s, face bottom %.0f, room %.0f)" % [origin, face.end.y, tier_room])
		var view: CardView = views[slot]
		var expected: int = 1 if finish.has_finish(card.rarity) else 0
		_expect_eq(view.get_name_sheens_started(), expected, "...and its name sheened %d time(s) on arrival" % expected)

# A new run on floor 4 with `gold`, and a collector of our own at its
# spot, stocked from collector_pool and wired to the field as RegionField
# wires a placed one.
func _load_floor_4(gold: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_add_gold(gold)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 20:
		await physics_frame
	_collector = (load(COLLECTOR_SCENE_PATH) as PackedScene).instantiate() as Node3D
	_collector.set("ground_path", NodePath("../Ground"))
	_collector.set("region_field_path", NodePath(".."))
	_collector.set("stock_pool", load(COLLECTOR_POOL_PATH))
	_collector.call("set_floor_placement", SPOT, 90.0, 0.0)
	_field.add_child(_collector)
	await physics_frame

# The collector's screen, opened the way its click opens it.
func _open() -> Node:
	if not bool(_field.call("open_collector_screen", _collector)):
		_fail("open_collector_screen refused")
		return null
	var screen: Node = _child_with_script(_field, "collector_screen.gd")
	if screen == null:
		_fail("no CollectorScreen opened")
	return screen

func _add_gold(amount: int) -> void:
	if amount > 0:
		_run_state.call("add_gold", amount)

func _deck_has(card_name: String) -> bool:
	return _has_name(_run_state.get("deck") as Array, card_name)

func _has_name(cards: Array, card_name: String) -> bool:
	for card: CardData in cards:
		if card.card_name == card_name:
			return true
	return false

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
	_collector = null
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
