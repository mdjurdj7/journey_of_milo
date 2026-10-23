extends SceneTree

# Headless probe for the collector (Collector, CollectorScreen) and
# Samphire, the card it always stocks:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/collector_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
#   placed   - floor 4's FloorData puts one Collector on the floor,
#              grounded, with its line, wired to open its screen
#   data     - the neutral pool offers only neutral, rewardable cards -
#              the four named ones, never Samphire or a starter; Samphire
#              in no pool at all; Samphire's own data
#   screen   - a collector on floor 4 opens its screen with the field
#              locked: its class cards from the run's class pool, its
#              neutral cards from the neutral pool, then Samphire; each
#              at the collector's own price for it; the
#              camera eased off its rest and back after LEAVE, which
#              closes and unlocks
#   buy      - a card opens to look at with TAKE FOR its price; with the
#              price short by one TAKE does nothing; affordable: gold down
#              by its price, deck up one, its slot empty and the others
#              where they were, the purchase line said; Samphire likewise;
#              reopened, the same stock minus both
#   goods    - one worn piece and one keepsake from the shop's tables,
#              the weapon only by its chance (always at 1, never at 0),
#              each at the collector's price for its kind; type lines by
#              the rule; CHOOSE opens its plate with TAKE FOR its price,
#              inert while short; BACK takes nothing (a weapon too);
#              taken, the price spent, it equipped at once and its line
#              gone; a good held when the screen opens isn't listed
#   bedroll  - the Bedroll is listed only while none is carried; bought,
#              its price spent, carried from the collector, gone from the
#              list - and still gone once that one is used
#   removal  - the removal line opens the deck picking, above the screen,
#              its heading the world line; a cancel spends nothing; a card
#              lifted shows its confirm and DECK n -> n-1; confirmed, the
#              removal's price spent once and exactly that card gone; then
#              its line is gone, and still on reopening; short of the
#              price it can't be chosen
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

const CASES := 9
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAMURAI_PATH := "res://run/data/samurai.tres"
const COLLECTOR_SCENE_PATH := "res://field/collector.tscn"
const POOLS_DIR := "res://cards/pools/"
const SAMPHIRE_PATH := "res://cards/neutral/samphire.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const RARITY_FINISH_PATH := "res://battle/card_rarity_finish.tres"
const NEUTRAL_POOL_PATH := "res://cards/pools/neutral_pool.tres"
const NEUTRAL_IN_STOCK: Array[String] = ["Left Hand", "Second Thoughts", "Untouched"]
const STARTER_ONLY: Array[String] = ["Slash", "Bite Down", "Endure"]
const FLOOR_4 := 3
const FLOOR_4_PATH := "res://floors/region1_floor4.tres"
# Where the field cases put their own collector, from spawn - any
# walkable spot on floor 4.
const SPOT := Vector3(-24.4, 0.0, -21.6)
const SPOT_YAW := -6.3
# Kind values of CollectorScreen.Kind, read off its lines untyped.
const KIND_WORN := 0
const KIND_KEEPSAKE := 1
const KIND_WEAPON := 2
const KIND_REMOVAL := 3
const KIND_BEDROLL := 4
const SAFETY_SECONDS := 300.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

var _run_state: Node = null
var _field: Node = null
var _collector: Node3D = null
# The collector's rolled card slots (class + neutral), before Samphire's.
var _stock: int = 0
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
	await _check_goods()
	await _check_bedroll()
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
	var neutral := load(NEUTRAL_POOL_PATH) as RewardPool
	var neutral_rng := RandomNumberGenerator.new()
	neutral_rng.seed = 1
	var names: Array[String] = []
	for card in neutral.roll(999, neutral_rng, null, load(CHARACTER_PATH) as CharacterData):
		_expect(card.card_class == &"", "The neutral pool offers only neutral cards (%s)" % card.card_name)
		names.append(card.card_name)
	for card_name in NEUTRAL_IN_STOCK:
		_expect(names.has(card_name), "...the neutral %s among them" % card_name)
	for card_name in STARTER_ONLY:
		_expect(not names.has(card_name), "...never the starter %s" % card_name)
	_expect(not names.has("Samphire"), "...nor Samphire")
	for file in DirAccess.get_files_at(POOLS_DIR):
		if not file.ends_with(".tres"):
			continue
		var any := load(POOLS_DIR + file) as RewardPool
		for card in any.entries:
			_expect(card.resource_path != SAMPHIRE_PATH, "Samphire is in no pool (%s holds it)" % file)
		# Nor offered by one, its folder scans included (the Samurai's
		# reads cards/neutral/, where it lives): every card the pool can
		# give, for either class.
		for character_path: String in [CHARACTER_PATH, SAMURAI_PATH]:
			var character := load(character_path) as CharacterData
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			var offered: Array[CardData] = any.roll(999, rng, null, character)
			offered.append_array(any.roll_by_rarity(999, rng, null, false, character))
			offered.append_array(any.roll_top_tier(999, rng, null, character))
			for card: CardData in offered:
				_expect(card.resource_path != SAMPHIRE_PATH, "%s never offers Samphire (%s)" % [file, character.character_name])
	var samphire := load(SAMPHIRE_PATH) as CardData
	_expect_eq(samphire.card_name, "Samphire", "Samphire")
	_expect(samphire.card_type == CardData.CardType.SKILL, "...a Skill")
	_expect_eq(samphire.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(samphire.removal_scope, CardData.RemovalScope.CONSUMED, "...Consumed")
	_expect(samphire.effects.size() == 1 and samphire.effects[0].effect_type == CardEffect.EffectType.HEAL, "...one Heal")
	_expect_eq(samphire.description, "Heal {heal}.\nConsumed.", "...reading Heal {heal}. / Consumed.")
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
		var ledges: Array = (load(FLOOR_4_PATH) as Resource).get("ledges")
		var inside: bool = ledges.is_empty() or Geometry2D.is_point_in_polygon(offset, ledges[0])
		for i in range(1, ledges.size()):
			inside = inside and not Geometry2D.is_point_in_polygon(offset, ledges[i])
		_expect(inside, "...on the floor: inside its boundary ledge line, outside the rest (%s)" % offset)
		var ground: Node = _field.get_node("Ground")
		var local: Vector3 = (ground as Node3D).to_local(collector.global_position)
		_expect(absf(collector.global_position.y - float(ground.call("get_height_at", Vector2(local.x, local.z)))) < 0.01, "...grounded on the relief")
		_expect_eq(str(collector.get("world_line")), "It is sorting what it has.", "...with its line")
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
		_expect_eq(cards.size(), _stock + 1, "The rolled slots, then the fixed one")
		var class_pool: RewardPool = _field.call("run_reward_pool", _field.call("get_floor_data"))
		var character := load(CHARACTER_PATH) as CharacterData
		var class_count: int = int(_collector.get("class_card_count"))
		var rolled: Array[String] = []
		for index in _stock:
			var card: CardData = cards[index]
			if index < class_count:
				_expect(card != null and card.card_class == character.card_class and _pool_offers(class_pool, card), "Slot %d is a class card from the class pool" % index)
			else:
				_expect(card != null and card.card_class == &"" and _pool_offers(load(NEUTRAL_POOL_PATH) as RewardPool, card), "Slot %d is a neutral card from the neutral pool" % index)
			if card != null:
				_expect(not rolled.has(card.card_name), "...distinct (%s)" % card.card_name)
				rolled.append(card.card_name)
				_expect_eq(int(screen.call("price_at", index)), int(_collector.call("price_of", card)), "...%s at the collector's price for it" % card.card_name)
		var fixed: CardData = cards[_stock]
		_expect(fixed != null and fixed.resource_path == SAMPHIRE_PATH, "The sixth is Samphire")
		_expect(not rolled.has("Samphire"), "...and Samphire is not in the roll")
		_expect_eq(int(screen.call("price_at", _stock)), int(_collector.get("fixed_price")), "...at its fixed price")
		_check_sheens(screen, cards)
		var camera: Camera3D = screen.call("get_camera")
		var rest: float = float(screen.call("get_camera_rest_offset"))
		var ease_sec: float = float(screen.get("camera_ease_seconds"))
		if camera == null:
			_fail("The field has a camera for the screen to ease")
		else:
			await ProbePlay.wait_until(self, func() -> bool: return absf(camera.h_offset - rest) > 0.01, ease_sec + 1.0)
			_expect(absf(camera.h_offset - rest) > 0.01, "The camera eases off its rest while the screen is open (%.2f)" % camera.h_offset)
		screen.call("activate", int(screen.call("leave_index")))
		await process_frame
		_expect(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "LEAVE closes it")
		_expect_eq(_field.process_mode, Node.PROCESS_MODE_INHERIT, "...and unlocks the field")
		if camera != null:
			await ProbePlay.wait_until(self, func() -> bool: return absf(camera.h_offset - rest) < 0.001, ease_sec + 1.0)
			_expect(absf(camera.h_offset - rest) < 0.001, "...and the camera eases back to rest (%.3f)" % camera.h_offset)
	await _teardown()
	_completed += 1

func _check_buy() -> void:
	await _load_floor_4(0)
	var screen: Node = _open()
	if screen != null:
		var cards: Array = screen.call("get_slot_cards")
		var first: CardData = cards[0]
		var price: int = int(screen.call("price_at", 0))
		var samphire_price: int = int(screen.call("price_at", _stock))
		_add_gold(price - 1)
		var deck_before: int = (_run_state.get("deck") as Array).size()
		screen.call("activate", 0)
		_expect(bool(screen.call("is_card_open")), "A card clicked opens to look at")
		_expect_eq(str(screen.call("take_text_at", 0)), str(screen.get("take_format")) % price, "...with TAKE FOR its price")
		screen.call("take_open_card")
		_expect_eq(int(_run_state.get("gold")), price - 1, "Short by 1: TAKE spends nothing")
		_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...adds no card")
		_expect(bool(screen.call("is_card_open")), "...and the card stays open")
		screen.call("back_out_of_card")
		_expect(not bool(screen.call("is_card_open")), "BACK puts it down")
		_expect((screen.call("get_slot_cards") as Array)[0] != null, "...the card still on offer")
		_add_gold(1 + samphire_price)
		screen.call("activate", 0)
		screen.call("take_open_card")
		_expect_eq(int(_run_state.get("gold")), samphire_price, "Affordable: exactly its price spent")
		_expect_eq((_run_state.get("deck") as Array).size(), deck_before + 1, "...the deck one up")
		_expect(_deck_has(first.card_name), "...with %s in it" % first.card_name)
		var after: Array = screen.call("get_slot_cards")
		_expect_eq(after.size(), cards.size(), "...the row the same length")
		_expect(after[0] == null, "...its slot empty")
		for index in range(1, cards.size()):
			_expect(after[index] == cards[index], "...slot %d unmoved" % index)
		_expect(bool(screen.call("is_purchase_line_showing")), "...and the purchase line said")
		screen.call("activate", _stock)
		screen.call("take_open_card")
		_expect_eq(int(_run_state.get("gold")), 0, "Samphire bought for its price")
		_expect(_deck_has("Samphire"), "...Samphire in the deck")
		_expect((screen.call("get_slot_cards") as Array)[_stock] == null, "...its slot empty")
		screen.call("close")
		await process_frame
		var again: Node = _open()
		if again != null:
			var reopened: Array = again.call("get_slot_cards")
			_expect(reopened[0] == null, "Reopened: the bought slot still empty")
			_expect(reopened[_stock] == null, "...Samphire still gone")
			for index in range(1, _stock):
				_expect(reopened[index] == cards[index], "...slot %d the same card" % index)
			again.call("close")
	await _teardown()
	_completed += 1

# The shop's equipment: one worn piece and one keepsake from its tables,
# a weapon by its chance - forced to 1 here, then 0.
func _check_goods() -> void:
	await _load_floor_4(0)
	_collector.set("weapon_chance", 1.0)
	# The stock rolled as the floor loaded: again, at this chance.
	_collector.call("reroll_stock")
	var worn_table := load(str(_collector.get("worn_table_path"))) as KeepsakeTable
	var keepsake_table := load(str(_collector.get("keepsake_table_path"))) as KeepsakeTable
	var screen: Node = _open()
	if screen != null:
		var worn_line: int = _line_of_kind(screen, KIND_WORN)
		var keepsake_line: int = _line_of_kind(screen, KIND_KEEPSAKE)
		var weapon_line: int = _line_of_kind(screen, KIND_WEAPON)
		_expect(worn_line >= 0 and keepsake_line >= 0 and weapon_line >= 0, "One worn piece, one keepsake and (at chance 1) a weapon")
		_expect_eq(_lines_of_kind(screen, KIND_WORN) + _lines_of_kind(screen, KIND_KEEPSAKE) + _lines_of_kind(screen, KIND_WEAPON), 3, "...one of each")
		var worn: TrinketData = _item_at(screen, worn_line)
		var keepsake: TrinketData = _item_at(screen, keepsake_line)
		var weapon: WeaponData = _item_at(screen, weapon_line)
		_expect(worn != null and _table_has(worn_table, worn), "...the worn piece from the shop's worn table")
		_expect(keepsake != null and _table_has(keepsake_table, keepsake), "...the keepsake from the shop's keepsake table")
		var carried: WeaponData = _run_state.get("weapon")
		var character := load(CHARACTER_PATH) as CharacterData
		_expect(weapon != null and weapon != carried and (weapon.card_class == &"" or weapon.card_class == character.card_class), "...a weapon for the class, not the one carried")
		var worn_price: int = int(_collector.get("worn_price"))
		var weapon_price: int = int(_collector.get("weapon_price"))
		_expect_eq(int(screen.call("line_price", worn_line)), worn_price, "The worn piece at the worn price")
		_expect_eq(int(screen.call("line_price", keepsake_line)), int(_collector.get("keepsake_price")), "The keepsake at the keepsake price")
		_expect_eq(int(screen.call("line_price", weapon_line)), weapon_price, "The weapon at the weapon price")
		var max_hp: int = int(_run_state.get("player_max_hp"))
		var separator: String = str(screen.get("type_separator"))
		if worn != null:
			var worn_type: String = str(screen.get("worn_kind_text"))
			if worn.max_hp_bonus > 0:
				worn_type += separator + str(screen.get("max_hp_format")) % [max_hp, max_hp + worn.max_hp_bonus]
			_expect_eq(str(screen.call("type_line_at", worn_line)), worn_type, "Nothing worn: the worn piece's type line by the rule")
		_expect_eq(str(screen.call("type_line_at", keepsake_line)), str(screen.get("keepsake_kind_text")), "No keepsake held: its kind alone")
		if carried != null:
			_expect_eq(str(screen.call("type_line_at", weapon_line)), str(screen.get("weapon_kind_text")) + separator + (str(screen.get("replaces_format")) % carried.display_name).to_upper(), "A weapon REPLACES the one carried")

		# Short of the price: the plate opens, TAKE inert.
		screen.call("activate", int(screen.call("line_focus_index", worn_line)))
		var offer: Node = screen.call("get_offer")
		_expect(offer != null, "CHOOSE opens the plate, gold or not")
		if offer != null:
			_expect(int((offer as CanvasLayer).layer) > int(screen.get("layer")), "...above the screen")
			var plate: Node = offer.call("get_plate")
			_expect_eq(str(plate.get("take_text")), str(screen.get("take_format")) % worn_price, "...TAKE FOR its price")
			_expect_eq(str(plate.get("leave_text")), str(screen.get("back_text")), "...and BACK")
			_expect(not bool(plate.get("take_enabled")), "...TAKE inert while short")
			plate.call("activate", 0)
			await process_frame
			_expect(screen.call("get_offer") != null, "...choosing it does nothing")
			_expect(_run_state.get("worn") == null, "...nothing worn")
			offer.call("close", false)
			await _offer_gone(screen)

		# Paid for: taken, worn, its line gone.
		_add_gold(worn_price + weapon_price)
		var gold_before: int = int(_run_state.get("gold"))
		screen.call("activate", int(screen.call("line_focus_index", _line_of(screen, worn))))
		offer = screen.call("get_offer")
		if offer != null:
			var plate: Node = offer.call("get_plate")
			_expect(bool(plate.get("take_enabled")), "Affordable: TAKE live")
			plate.call("activate", 0)
			await _offer_gone(screen)
			_expect_eq(int(_run_state.get("gold")), gold_before - worn_price, "...exactly its price spent")
			_expect(_run_state.get("worn") == worn, "...worn at once")
			_expect_eq(_line_of(screen, worn), -1, "...and its line gone")
			_expect(bool(screen.call("is_purchase_line_showing")), "...the purchase line said")

		# The weapon: BACK leaves it on sale, nothing spent.
		gold_before = int(_run_state.get("gold"))
		screen.call("activate", int(screen.call("line_focus_index", _line_of(screen, weapon))))
		offer = screen.call("get_offer")
		if offer != null:
			offer.call("close", false)
			await _offer_gone(screen)
			_expect(screen.call("get_offer") == null, "A weapon's plate closes on BACK")
			_expect_eq(int(_run_state.get("gold")), gold_before, "...nothing spent")
			_expect(_run_state.get("weapon") == carried, "...the weapon carried kept")
		screen.call("activate", int(screen.call("line_focus_index", _line_of(screen, weapon))))
		offer = screen.call("get_offer")
		if offer != null:
			(offer.call("get_plate") as Node).call("activate", 0)
			await _offer_gone(screen)
			_expect(_run_state.get("weapon") == weapon, "Taken, the weapon is carried at once")
			_expect_eq(int(_run_state.get("gold")), gold_before - weapon_price, "...for exactly its price")
			_expect_eq(_line_of(screen, weapon), -1, "...and its line gone")
		screen.call("close")
		await process_frame
		# Held when the screen opens: not listed.
		_run_state.call("equip_keepsake", keepsake)
		var again: Node = _open()
		if again != null:
			_expect_eq(_line_of(again, worn), -1, "Reopened: the taken goods stay gone")
			_expect_eq(_line_of(again, keepsake), -1, "...and a keepsake already held isn't listed")
			again.call("close")
	await _teardown()

	await _load_floor_4(0)
	_collector.set("weapon_chance", 0.0)
	_collector.call("reroll_stock")
	var without: Node = _open()
	if without != null:
		_expect_eq(_line_of_kind(without, KIND_WEAPON), -1, "At chance 0, no weapon")
		without.call("close")
	await _teardown()
	_completed += 1

# The Bedroll: one per collector, listed only while none is carried.
func _check_bedroll() -> void:
	await _load_floor_4(0)
	var price: int = int(_collector.get("bedroll_price"))
	_run_state.call("take_bedroll", "belongings")
	var screen: Node = _open()
	if screen != null:
		_expect_eq(_line_of_kind(screen, KIND_BEDROLL), -1, "Carrying a Bedroll: the collector's isn't listed")
		screen.call("close")
		await process_frame
	_run_state.call("use_bedroll")
	_add_gold(price)
	screen = _open()
	if screen != null:
		var line: int = _line_of_kind(screen, KIND_BEDROLL)
		_expect(line >= 0, "Its own used: the collector's is listed")
		_expect_eq(int(screen.call("line_price", line)), price, "...at the Bedroll's price")
		_expect_eq(str(screen.call("type_line_at", line)), str(screen.get("bedroll_kind_text")), "...its kind alone")
		screen.call("activate", int(screen.call("line_focus_index", line)))
		var offer: Node = screen.call("get_offer")
		_expect(offer != null, "CHOOSE opens its plate")
		if offer != null:
			(offer.call("get_plate") as Node).call("activate", 0)
			await _offer_gone(screen)
			_expect(bool(_run_state.get("has_bedroll")), "Bought: carried")
			_expect_eq(str(_run_state.get("bedroll_source")), "collector", "...from the collector")
			_expect_eq(int(_run_state.get("gold")), 0, "...exactly its price spent")
			_expect_eq(_line_of_kind(screen, KIND_BEDROLL), -1, "...and its line gone")
		screen.call("close")
		await process_frame
	_run_state.call("use_bedroll")
	_add_gold(price)
	screen = _open()
	if screen != null:
		_expect_eq(_line_of_kind(screen, KIND_BEDROLL), -1, "That one used: the collector has no second")
		screen.call("close")
	await _teardown()
	_completed += 1

func _check_removal() -> void:
	await _load_floor_4(0)
	var removal_price: int = int(_collector.get("removal_price"))
	var screen: Node = _open()
	if screen != null:
		_add_gold(removal_price - 1)
		_expect(not bool(screen.call("is_removal_open")), "Short of its price, the removal can't be chosen")
		screen.call("activate", int(screen.call("line_focus_index", _removal_line(screen))))
		_expect(screen.call("get_picker") == null, "...its CHOOSE opens nothing")
		_add_gold(1)
		var deck_before: int = (_run_state.get("deck") as Array).size()
		screen.call("activate", int(screen.call("line_focus_index", _removal_line(screen))))
		var picker: Node = screen.call("get_picker")
		_expect(picker != null and bool(picker.get("pick_mode")), "The removal opens the deck picking")
		if picker != null:
			_expect(int((picker.get_parent() as CanvasLayer).layer) > int(screen.get("layer")), "...above the screen")
			_expect(bool(picker.get("header_voice")), "...its heading the world line")
			picker.call("close")
			await process_frame
			_expect_eq(int(_run_state.get("gold")), removal_price, "A cancel spends nothing")
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...and keeps the deck")
			_expect(bool(screen.call("is_removal_open")), "...and the removal is still on offer")
		screen.call("activate", int(screen.call("line_focus_index", _removal_line(screen))))
		picker = screen.call("get_picker")
		if picker != null:
			var views: Array = picker.call("get_card_views")
			var view: CardView = views[0] if not views.is_empty() else null
			if view == null:
				_fail("The picker shows the deck")
			else:
				view.emit_signal("clicked", view.card_data)
				await ProbePlay.wait_until(self, func() -> bool: return not bool(picker.get("_inspect_busy")), 2.0)
				var handed: CardData = picker.call("get_pending_pick")
				_expect(handed != null and (_run_state.get("deck") as Array).has(handed), "A card clicked waits for a confirm")
				_expect_eq((_run_state.get("deck") as Array).size(), deck_before, "...nothing gone yet")
				if handed != null:
					_expect(str(picker.call("get_confirm_text")).contains(handed.card_name.to_upper()), "...the confirm names it (%s)" % picker.call("get_confirm_text"))
					_expect_eq(int(picker.get("pick_confirm_price")), removal_price, "...with the removal's price")
					_expect_eq(str(picker.call("get_detail_text")), str(screen.get("removal_detail_format")) % [deck_before, deck_before - 1], "...and the deck's count to one fewer")
					picker.call("confirm_pick")
					await process_frame
					_expect_eq(int(_run_state.get("gold")), 0, "Confirmed: the removal's price spent once")
					_expect_eq((_run_state.get("deck") as Array).size(), deck_before - 1, "...one card gone")
					_expect(not (_run_state.get("deck") as Array).has(handed), "...that very card")
		_add_gold(500)
		_expect_eq(_removal_line(screen), -1, "Once used, the removal line is gone, gold or not")
		screen.call("close")
		await process_frame
		var again: Node = _open()
		if again != null:
			_expect_eq(_removal_line(again), -1, "...and still gone on reopening")
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
				await _await_reward_screen()
				_expect(not _deck_has("Samphire"), "The fight over: Samphire has left RunState.deck")
				_expect_eq((_run_state.get("deck") as Array).size(), 4, "...the deck down to the four Braces")
	await _teardown()
	_completed += 1

# --- Helpers ---

# Each finished name sheened once as the stock arrived (a Common's not).
func _check_sheens(screen: Node, cards: Array) -> void:
	var finish := load(RARITY_FINISH_PATH) as CardRarityFinish
	var views: Array = screen.get("_views")
	for slot in cards.size():
		var card: CardData = cards[slot]
		if card == null:
			continue
		var view: CardView = views[slot]
		var expected: int = 1 if finish.has_finish(card.rarity) else 0
		_expect_eq(view.get_name_sheens_started(), expected, "Slot %d (%s): its name sheened %d time(s) on arrival" % [slot, card.card_name, expected])

# The list index of the line selling `item`, or -1.
func _line_of(screen: Node, item: Resource) -> int:
	var lines: Array = screen.call("get_lines")
	for index in lines.size():
		var good: CollectorGood = (lines[index] as Dictionary)["good"]
		if good != null and good.item == item:
			return index
	return -1

# The list index of the removal line, or -1.
func _removal_line(screen: Node) -> int:
	return _line_of_kind(screen, KIND_REMOVAL)

# The list index of the first line of `kind`, or -1; and how many there are.
func _line_of_kind(screen: Node, kind: int) -> int:
	var lines: Array = screen.call("get_lines")
	for index in lines.size():
		if int((lines[index] as Dictionary)["kind"]) == kind:
			return index
	return -1

func _lines_of_kind(screen: Node, kind: int) -> int:
	var count: int = 0
	for line: Dictionary in screen.call("get_lines"):
		if int(line["kind"]) == kind:
			count += 1
	return count

# The item line `index` sells, or null.
func _item_at(screen: Node, index: int) -> Resource:
	if index < 0:
		return null
	var good: CollectorGood = ((screen.call("get_lines") as Array)[index] as Dictionary)["good"]
	return good.item if good != null else null

func _table_has(table: KeepsakeTable, trinket: TrinketData) -> bool:
	for entry in table.entries:
		if entry != null and entry.trinket == trinket:
			return true
	return false

# Whether `pool` can offer `card` at all - its own cards, folders included.
func _pool_offers(pool: RewardPool, card: CardData) -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	return pool.roll(999, rng, null, load(CHARACTER_PATH) as CharacterData).has(card)

# A plate answered: until it has eased away.
func _offer_gone(screen: Node) -> void:
	await ProbePlay.wait_until(self, func() -> bool: return screen.call("get_offer") == null, 2.0)

# A new run on floor 4 with `gold`, and a collector of our own at its
# spot, wired to the field as RegionField wires a placed one.
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
	_collector.call("set_floor_placement", SPOT, SPOT_YAW, 0.0)
	_field.add_child(_collector)
	_stock = int(_collector.get("class_card_count")) + int(_collector.get("neutral_card_count"))
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

# A fight just won: until its reward screen is up - the killing blow and
# the last death play out first - or REWARD_WAIT_SECONDS have gone.
func _await_reward_screen() -> void:
	var start: int = ProbePlay.cap_msec()
	while _child_with_script(_field, "reward_screen.gd") == null and ProbePlay.cap_msec() - start < int(REWARD_WAIT_SECONDS * 1000.0):
		await process_frame

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
