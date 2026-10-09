extends SceneTree

# Headless probe for the Keeper's keepsake: her own table and its one
# roll per run, the in-world plaque's take / replace / keep, the offer
# claimed for good, and each of her six keepsakes' effects - in the one
# keepsake slot, never a stack.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/keeper_keepsake_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases build Combatants; field cases load the real region scene
# and start fights through RegionField's contact handler, as trinket_
# probe does. Untyped against anything that names the RunState autoload
# (Keeper, WorldKeepsake, RegionField, BattleController): a SceneTree
# script compiles before the autoloads register.

const CASES := 18
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const KEEPER_SCENE_PATH := "res://field/keeper.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const KEEPER_TABLE_PATH := "res://run/keepsakes/keeper/keeper_keepsakes.tres"
const WARDLING_TABLE_PATH := "res://run/keepsakes/wardling_keepsakes.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const WRAPPED_SWEET_PATH := "res://run/keepsakes/keeper/wrapped_sweet.tres"
const BLUE_FASTENER_PATH := "res://run/keepsakes/keeper/blue_fastener.tres"
const DEPARTURE_STUB_PATH := "res://run/keepsakes/keeper/departure_stub.tres"
const SIGNAL_GLASS_PATH := "res://run/keepsakes/keeper/signal_glass.tres"
const PRESSED_FLOWER_PATH := "res://run/keepsakes/keeper/pressed_flower.tres"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const DOWN_PAYMENT_PATH := "res://cards/data/down_payment.tres"
const KEEPER_IDS: Array[StringName] = [&"house_key", &"wrapped_sweet", &"blue_fastener", &"departure_stub", &"signal_glass", &"pressed_flower"]
const SAFETY_SECONDS := 400.0

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
	_new_run()

	_check_table()
	_check_roll_uses_run_rng()
	_check_exhausted_pool()
	_check_descriptions()
	_check_art()
	await _check_approach_grants_nothing()
	await _check_take_into_empty_slot()
	await _check_replace()
	await _check_keep_current()
	_check_critical_entry_rules()
	_check_critical_entry_enemy_hit()
	await _check_house_key()
	await _check_house_key_resets_and_zero_cost()
	await _check_departure_stub()
	await _check_signal_glass()
	await _check_blue_fastener_self_damage()
	await _check_wrapped_sweet()
	await _check_pressed_flower()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("keeper_keepsake_probe: PASSED")
		quit(0)
	else:
		print("keeper_keepsake_probe: %d FAILED" % _failures)
		quit(1)

# --- Her table ---

# Each of her six has its object art: the 1024 square the drops' PNGs
# are, imported from SVG with mipmaps (the plaque's KeepsakeTile draws it
# in a 104 px window).
func _check_art() -> void:
	for path in [HOUSE_KEY_PATH, WRAPPED_SWEET_PATH, BLUE_FASTENER_PATH, DEPARTURE_STUB_PATH, SIGNAL_GLASS_PATH, PRESSED_FLOWER_PATH]:
		var trinket: TrinketData = load(path)
		_expect(trinket.art != null, "%s has art" % trinket.display_name)
		if trinket.art == null:
			continue
		_expect_eq(trinket.art.resource_path, "res://assets/textures/keepsakes/%s.svg" % trinket.id, "...its own SVG")
		_expect_eq([trinket.art.get_width(), trinket.art.get_height()], [1024, 1024], "...1024 square")
		_expect(trinket.art.get_image().has_mipmaps(), "...with mipmaps")
	_completed += 1

func _check_table() -> void:
	var table: KeepsakeTable = load(KEEPER_TABLE_PATH)
	_expect(table != null, "The Keeper's table loads")
	if table == null:
		_completed += 1
		return
	var ids: Array[StringName] = []
	for entry in table.entries:
		ids.append(entry.trinket.id)
	_expect_eq(ids, KEEPER_IDS, "...holds exactly her six keepsakes")
	var wardling: KeepsakeTable = load(WARDLING_TABLE_PATH)
	for entry in wardling.entries:
		_expect(not ids.has(entry.trinket.id), "...none shared with the Wardling's table (%s)" % entry.trinket.display_name)
	var keeper: Node = (load(KEEPER_SCENE_PATH) as PackedScene).instantiate()
	_expect(keeper.get("keeper_pool") == table, "keeper.tscn draws from that table")
	_expect(keeper.get("offered_keepsake") == null, "...with no forced keepsake")
	keeper.free()
	_completed += 1

func _check_roll_uses_run_rng() -> void:
	_new_run()
	var rng: RandomNumberGenerator = _run_state.get("rng")
	rng.seed = 12345
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 12345
	expected_rng.state = rng.state
	var none: Array[StringName] = []
	var expected: TrinketData = (load(KEEPER_TABLE_PATH) as KeepsakeTable).roll(expected_rng, null, none)
	var keeper: Node = (load(KEEPER_SCENE_PATH) as PackedScene).instantiate()
	var picked: TrinketData = keeper.call("_pick_keepsake")
	_expect(picked != null and picked == expected, "One roll, from RunState.rng: the pick matches the run's own sequence (%s)" % (picked.display_name if picked != null else "null"))
	_expect(KEEPER_IDS.has(picked.id if picked != null else &""), "...and it's one of hers")
	var state_after: int = rng.state
	_expect(keeper.call("_pick_keepsake") == picked, "Asked again: the same keepsake, not a reroll")
	_expect_eq(rng.state, state_after, "...and the run's rng isn't drawn again")
	keeper.free()
	var again: Node = (load(KEEPER_SCENE_PATH) as PackedScene).instantiate()
	_expect(again.call("_pick_keepsake") == picked, "A second Keeper instance (a floor reload) holds the same one")
	again.free()
	_completed += 1

# Nothing left to offer: no WorldKeepsake, a warning, never a duplicate.
func _check_exhausted_pool() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	_run_state.call("equip_keepsake", nail)
	var only_nail := KeepsakeTable.new()
	var entry := KeepsakeEntry.new()
	entry.trinket = nail
	var entries: Array[KeepsakeEntry] = [entry]
	only_nail.entries = entries
	var keeper: Node = (load(KEEPER_SCENE_PATH) as PackedScene).instantiate()
	keeper.set("keeper_pool", only_nail)
	keeper.set("offer_id", "probe:exhausted")
	print("   (a 'nothing to hold out' warning is expected next)")
	keeper.call("_spawn_world_keepsake")
	_expect(keeper.call("_pick_keepsake") == null, "An exhausted table rolls nothing - never the one already held")
	_expect_eq(keeper.get_child_count(), 0, "...and she holds nothing out")
	_expect(not bool(keeper.call("is_offering")), "...so she isn't offering")
	_expect(_keepsake() == nail, "...and the slot is untouched")
	keeper.free()
	_completed += 1

func _check_descriptions() -> void:
	var expected := {
		HOUSE_KEY_PATH: ["Someone meant to need it again.", "The first card you play each combat costs 0 Energy."],
		WRAPPED_SWEET_PATH: ["Saved for later.", "After each combat you win, if you lost HP during it, heal 2 HP."],
		BLUE_FASTENER_PATH: ["Too small for you.", "The first time you enter Critical each combat, gain 6 Block."],
		DEPARTURE_STUB_PATH: ["The number is still legible.", "Draw 1 extra card on your first turn of each combat."],
		SIGNAL_GLASS_PATH: ["It still catches something.", "At the start of each combat, gain 3 Block."],
		PRESSED_FLOWER_PATH: ["It grew here.", "After each combat you win, heal 1 HP."],
	}
	for path: String in expected:
		var trinket: TrinketData = load(path)
		_expect_eq(trinket.flavor_text, expected[path][0], "%s's flavour" % trinket.display_name)
		_expect_eq(trinket.describe(), expected[path][1], "%s's rule" % trinket.display_name)
		_expect(not trinket.describe_short().is_empty() and not trinket.describe_short().contains("{"), "...and a filled short line")
	_completed += 1

# --- The offer, in the field ---

func _check_approach_grants_nothing() -> void:
	_new_run()
	await _load_field(0)
	var keeper: Node = _keeper()
	var held_out: Node = _world_keepsake(keeper)
	_expect(held_out != null, "On floor 1 the Keeper holds a WorldKeepsake out")
	if held_out != null:
		_expect(KEEPER_IDS.has((held_out.get("keepsake") as TrinketData).id), "...one of her own")
		_expect(bool(keeper.call("is_offering")), "...and is offering")
		var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
		wanderer.global_position = (held_out.call("anchor_position") as Vector3) + Vector3(0.8, 0.0, 0.0)
		for i in 20:
			await physics_frame
		_expect(bool(held_out.get("_near")), "Walking into range lifts the plaque")
		var tile: Control = held_out.call("get_tile")
		_expect(tile != null and tile.call("get_keepsake") == held_out.get("keepsake"), "...its KeepsakeTile shows the keepsake held out")
		_expect(tile != null and bool(tile.call("fits")), "...and fits it")
		_expect(_keepsake() == null, "...and grants nothing: the slot is still empty")
		_expect(bool(keeper.call("is_offering")), "...the offer still stands")
	await _teardown()
	_completed += 1

func _check_take_into_empty_slot() -> void:
	_new_run()
	await _load_field(0)
	var keeper: Node = _keeper()
	var held_out: Node = _world_keepsake(keeper)
	if held_out == null:
		_fail("no WorldKeepsake to take")
		await _teardown()
		_completed += 1
		return
	var offered: TrinketData = held_out.get("keepsake")
	_expect_eq(int(held_out.call("choice_count")), 1, "An empty slot: one action")
	_expect_eq(str(held_out.call("_choice_label", 0)), "TAKE", "...TAKE")
	held_out.call("_activate", 0)
	_expect(_keepsake() == offered, "TAKE equips it (%s)" % offered.display_name)
	_expect(not bool(keeper.call("is_offering")), "...and her offer is claimed")
	_expect((_run_state.get("keepsakes_offered") as Array).has(offered.id), "...noted offered for the run")
	var line: Node = _field.get_node("FieldHUD/KeepsakeLine")
	_expect_eq(str(line.get("_value_text")), offered.display_name, "...and the KEEPSAKE line names it")
	await create_timer(0.8).timeout
	_expect(not is_instance_valid(held_out), "...the plaque fades and goes")
	# A second click after the first can't grant twice.
	await _teardown()
	# The floor again, as a floor exit's reload or the region's wrap does.
	await _load_field(0)
	keeper = _keeper()
	_expect(_world_keepsake(keeper) == null, "Back on floor 1: nothing held out again")
	_expect(not bool(keeper.call("is_offering")), "...her offer stays claimed")
	_expect(_keepsake() == offered, "...and the keepsake is still held")
	await _teardown()
	_completed += 1

func _check_replace() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	_run_state.call("equip_keepsake", nail)
	await _load_field(0)
	var keeper: Node = _keeper()
	var held_out: Node = _world_keepsake(keeper)
	if held_out == null:
		_fail("no WorldKeepsake to replace with")
		await _teardown()
		_completed += 1
		return
	var offered: TrinketData = held_out.get("keepsake")
	_expect_eq(int(held_out.call("choice_count")), 2, "Bent Nail held: two actions")
	_expect_eq(str(held_out.call("_choice_label", 0)), "REPLACE BENT NAIL", "...REPLACE BENT NAIL says what taking costs")
	_expect_eq(str(held_out.call("_choice_label", 1)), "KEEP BENT NAIL", "...KEEP BENT NAIL the other")
	held_out.call("_activate", 0)
	_expect(_keepsake() == offered, "REPLACE: %s held" % offered.display_name)
	_expect(_keepsake() != nail, "...Bent Nail gone - one slot, no stack")
	_expect(not bool(_run_state.call("acquire_keepsake", nail)), "...and the slot still refuses a second")
	_expect(not bool(keeper.call("is_offering")), "...her offer claimed")
	held_out.call("_activate", 1)
	_expect(_keepsake() == offered, "A second activation does nothing")
	await _teardown()
	_completed += 1

func _check_keep_current() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	_run_state.call("equip_keepsake", nail)
	await _load_field(0)
	var keeper: Node = _keeper()
	var held_out: Node = _world_keepsake(keeper)
	if held_out == null:
		_fail("no WorldKeepsake to leave")
		await _teardown()
		_completed += 1
		return
	var offered: TrinketData = held_out.get("keepsake")
	held_out.call("_activate", 1)
	_expect(_keepsake() == nail, "KEEP: Bent Nail still held")
	_expect(not bool(keeper.call("is_offering")), "...and hers is left - the offer is resolved")
	_expect((_run_state.get("keepsakes_offered") as Array).has(offered.id), "...noted offered")
	await _teardown()
	await _load_field(0)
	_expect(_world_keepsake(_keeper()) == null, "Back on floor 1: she doesn't hold it out again")
	await _teardown()
	_completed += 1

# --- Blue Fastener's edge, rules only ---

func _check_critical_entry_rules() -> void:
	# 70 max, Critical at 21 and under.
	var player := _fastened(70, 70)
	player.hp = 30
	Status.resolve_critical_triggers(player)
	_expect_eq(player.block, 0, "Above Critical: nothing")
	player.hp = 21
	Status.resolve_critical_triggers(player)
	_expect_eq(player.block, 6, "Crossing into Critical (21 of 70): +6 Block")
	player.hp = 15
	Status.resolve_critical_triggers(player)
	_expect_eq(player.block, 6, "...staying Critical and losing more: no second grant")
	player.hp = 40
	Status.resolve_critical_triggers(player)
	player.hp = 10
	Status.resolve_critical_triggers(player)
	_expect_eq(player.block, 6, "...healed out and back in: spent for this fight")

	var started_low := _fastened(70, 18)
	Status.resolve_critical_triggers(started_low)
	started_low.hp = 14
	Status.resolve_critical_triggers(started_low)
	_expect_eq(started_low.block, 0, "Opening Critical is not entering it")
	started_low.hp = 30
	Status.resolve_critical_triggers(started_low)
	started_low.hp = 20
	Status.resolve_critical_triggers(started_low)
	_expect_eq(started_low.block, 6, "...healed above the line, then back in: +6 once")
	started_low.hp = 30
	Status.resolve_critical_triggers(started_low)
	started_low.hp = 20
	Status.resolve_critical_triggers(started_low)
	_expect_eq(started_low.block, 6, "...and only once")
	_completed += 1

# An enemy's attack across the line - EnemyTurn's own resolve.
func _check_critical_entry_enemy_hit() -> void:
	var player := _fastened(70, 30)
	var data := EnemyData.new()
	data.max_hp = 20
	var hit := EnemyIntent.new()
	hit.type = EnemyIntent.IntentType.ATTACK
	hit.value = 10
	var intents: Array[EnemyIntent] = [hit]
	data.intents = intents
	var enemy := Combatant.new(20)
	EnemyTurn.pick_initial_intent(enemy, data)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 20, "An enemy's 10 takes 30 to 20")
	_expect_eq(player.block, 6, "...into Critical: +6 Block, after the hit")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 16, "The next hit: 6 blocked, 4 to HP")
	_expect_eq(player.block, 0, "...and no second grant")
	_completed += 1

# --- Effects, in real fights ---

# Targeted, cost 2 (a Bite Down re-costed for the probe): arming and
# cancelling spends nothing, the first real play is free, the second pays.
func _check_house_key() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(HOUSE_KEY_PATH))
	_set_deck(BITE_DOWN_PATH, 2)
	var controller: Node = await _start_fight(0, &"")
	if controller == null:
		await _teardown()
		_completed += 1
		return
	var player: Combatant = controller.get("player")
	_toughen_enemies(controller)
	var hand: Node = controller.get("_hand_container")
	var views: Array = hand.call("_card_views")
	var first: CardView = views[0]
	var second: CardView = views[1]
	var enemy: Node = (controller.get("enemies") as Array)[0]
	_expect(player.first_card_free, "House Key: the fight opens with the free card ready")
	_expect_eq(player.energy_cost(first.card_data), 0, "...a cost-2 card costs 0")
	_expect_eq(first.cost_label.text, "0", "...and its face says 0")
	player.energy = 0
	controller.emit_signal("energy_changed", 0)
	_expect(bool(hand.call("_can_play", first.card_data, 0)), "...playable on 0 Energy - the hand doesn't dim it")
	controller.call("request_play", first)
	_expect(bool(controller.call("is_awaiting_target")), "Armed on 0 Energy: the targeted card waits for a target")
	controller.call("cancel_target")
	_expect(player.first_card_free, "Cancelling the target spends nothing")
	_expect_eq(player.energy, 0, "...Energy untouched")
	controller.call("request_play", first)
	controller.call("confirm_target", enemy)
	_expect(not player.first_card_free, "The first real play spends it")
	_expect_eq(player.energy, 0, "...and cost nothing")
	await create_timer(1.5).timeout
	_expect_eq(second.cost_label.text, "2", "After it: the hand's faces read 2 again")
	_expect_eq(player.energy_cost(second.card_data), 2, "...and it costs 2")
	_expect(not bool(hand.call("_can_play", second.card_data, 0)), "...and on 0 Energy the hand dims it")
	# Unaffordable, it arms for Devour alone (BattleController._arm_for_
	# devour()) - never to be played: an enemy click does nothing.
	controller.call("request_play", second)
	_expect(bool(controller.call("is_armed_for_devour_only")), "The second card on 0 Energy can't be played - armed for Devour alone")
	controller.call("confirm_target", enemy)
	_expect(bool(controller.call("is_awaiting_target")) and player.energy == 0, "...an enemy click plays nothing")
	controller.call("cancel_target")
	player.energy = 3
	controller.call("request_play", second)
	controller.call("confirm_target", enemy)
	_expect_eq(player.energy, 1, "...and on 3, it pays its 2")
	await create_timer(1.5).timeout
	await _teardown()
	_completed += 1

# The next fight opens with it again - and a 0-cost first card passes it
# by: the free card waits for the first card that costs something.
func _check_house_key_resets_and_zero_cost() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(HOUSE_KEY_PATH))
	_set_deck(DOWN_PAYMENT_PATH, -1)
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		var views: Array = controller.get("_hand_container").call("_card_views")
		controller.call("request_play", views[0])
		_expect(player.first_card_free, "A 0-cost first card passes the free card by: it waits")
		_expect_eq(player.energy, 3, "...Energy 3, unchanged")
		_expect_eq(player.energy_cost(load(SLASH_PATH) as CardData), 0, "...and the next card that costs something would take it")
		await create_timer(1.0).timeout
	await _teardown()
	_set_deck(DOWN_PAYMENT_PATH, -1)
	controller = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(player.first_card_free, "The next fight opens with the free card ready again")
	await _teardown()
	_new_run()
	controller = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(not player.first_card_free, "No keepsake: no free card")
	await _teardown()
	_completed += 1

func _check_departure_stub() -> void:
	_new_run()
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		_expect_eq(_hand_size(controller), 5, "No keepsake: the opening hand is 5")
	await _teardown()
	_run_state.call("equip_keepsake", load(DEPARTURE_STUB_PATH))
	controller = await _start_fight(0, &"")
	if controller != null:
		_expect_eq(_hand_size(controller), 6, "Departure Stub: the opening hand is 6")
		controller.get("_hand_container").call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(_hand_size(controller), 5, "...and the second turn's draw is the usual 5")
	await _teardown()
	_completed += 1

func _check_signal_glass() -> void:
	_new_run()
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		_expect_eq((controller.get("player") as Combatant).block, 0, "No keepsake: the fight opens with 0 Block")
	await _teardown()
	_run_state.call("equip_keepsake", load(SIGNAL_GLASS_PATH))
	controller = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.block, 3, "Signal Glass: the fight opens with exactly 3 Block")
		controller.get("_hand_container").call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(player.block, 0, "...ordinary Block: gone at the next turn's reset")
	await _teardown()
	_completed += 1

# A real card's self-damage across the line, and a real fight opening
# Critical.
func _check_blue_fastener_self_damage() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(BLUE_FASTENER_PATH))
	# The Wanderer's 80 max HP puts Critical at 24 and under.
	_run_state.set("player_hp", 25)
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(not player.is_critical(), "25 of 80 is not Critical")
		_play_self_damage(controller)
		_expect_eq(player.hp, 24, "Down Payment's 1 HP takes it to 24")
		_expect_eq(player.block, 6, "...into Critical by self-damage: +6 Block")
		_play_self_damage(controller)
		_expect_eq(player.block, 6, "...again, still Critical: no second grant")
	await _teardown()
	_run_state.set("player_hp", 15)
	controller = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_play_self_damage(controller)
		_expect_eq(player.block, 0, "Opening the fight Critical and losing more: nothing")
	await _teardown()
	_completed += 1

func _check_wrapped_sweet() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(WRAPPED_SWEET_PATH))
	var max_hp: int = int(_run_state.get("player_max_hp"))
	# Opening hurt but losing nothing in the fight.
	_run_state.set("player_hp", max_hp - 10)
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		_expect_eq(int(_run_state.get("hp_lost_this_combat")), 0, "A fight opens with nothing lost in it")
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 10, "Wrapped Sweet: opening below max alone heals nothing")
	await _teardown()
	# An enemy's hit.
	controller = await _start_fight(0, &"")
	if controller != null:
		_enemy_hit(controller, 3)
		_expect_eq(int(_run_state.get("hp_lost_this_combat")), 3, "An enemy's hit counts what it took")
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 13 + 2, "...and the win heals 2")
	await _teardown()
	# Self-damage.
	_run_state.set("player_hp", max_hp - 10)
	controller = await _start_fight(0, &"")
	if controller != null:
		_play_self_damage(controller)
		_expect_eq(int(_run_state.get("hp_lost_this_combat")), 1, "Self-damage counts")
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 11 + 2, "...and the win heals 2")
	await _teardown()
	# A status tick.
	_run_state.set("player_hp", max_hp - 10)
	controller = await _start_fight(0, &"")
	if controller != null:
		var tick := StatusData.new()
		tick.id = "probe_tick"
		tick.category = StatusData.Category.TICK
		tick.default_magnitude = 2
		tick.default_duration_turns = 5
		Status.apply_to((controller.get("player") as Combatant).statuses, tick)
		controller.get("_hand_container").call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(int(_run_state.get("hp_lost_this_combat")), 2, "A status tick counts")
	await _teardown()
	# Hurt, then escaping.
	_run_state.set("player_hp", max_hp - 10)
	controller = await _start_fight(0, &"")
	if controller != null:
		_enemy_hit(controller, 3)
		_overlay().call("_finish_battle", 2) # ESCAPE
		await physics_frame
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 13, "...an escape heals nothing, hurt or not")
	await _teardown()
	# The cap.
	_run_state.set("player_hp", max_hp)
	controller = await _start_fight(0, &"")
	if controller != null:
		_enemy_hit(controller, 1)
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp, "...and never past max HP (1 lost, 2 healed: max)")
	await _teardown()
	_completed += 1

func _check_pressed_flower() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(PRESSED_FLOWER_PATH))
	var max_hp: int = int(_run_state.get("player_max_hp"))
	_run_state.set("player_hp", max_hp - 5)
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 4, "Pressed Flower: +1 HP after a win, hurt or not")
	await _teardown()
	controller = await _start_fight(0, &"")
	if controller != null:
		_overlay().call("_finish_battle", 2) # ESCAPE
		await physics_frame
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 4, "...nothing after an escape")
	await _teardown()
	_run_state.set("player_hp", max_hp)
	controller = await _start_fight(0, &"")
	if controller != null:
		await _win()
		_expect_eq(int(_run_state.get("player_hp")), max_hp, "...and never past max HP")
	await _teardown()
	_expect(_keepsake() == load(PRESSED_FLOWER_PATH), "The keepsake persists across every fight")
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _keepsake() -> TrinketData:
	return _run_state.get("keepsake") as TrinketData

# A bare player carrying Blue Fastener's charge the way setup() arms it.
func _fastened(max_hp: int, hp: int) -> Combatant:
	var player := Combatant.new(max_hp)
	player.hp = hp
	player.critical_hp_fraction = 0.3
	player.critical_entry_block = (load(BLUE_FASTENER_PATH) as TrinketData).critical_entry_block
	player.critical_entry_armed = not player.is_critical()
	return player

# Ten copies of one card as the run's deck; cost >= 0 re-costs each copy.
func _set_deck(card_path: String, cost: int) -> void:
	var cards: Array[CardData] = []
	for i in 10:
		var card := (load(card_path) as CardData).duplicate() as CardData
		if cost >= 0:
			card.cost = cost
		cards.append(card)
	_run_state.set("deck", cards)

# Down Payment resolved against the fight's real player, through the
# controller's own damage report - the self-damage path a played card
# takes, without the play's animation wait.
func _play_self_damage(controller: Node) -> void:
	var ctx := EffectContext.new()
	ctx.player = controller.get("player")
	var none: Array[Combatant] = []
	ctx.enemies = none
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		controller.call("_report_damage", "player", target, amount, kind)
	EffectResolver.new().resolve_card(load(DOWN_PAYMENT_PATH) as CardData, ctx)

# An enemy's hit of `amount` straight to HP, reported as the controller
# reports one.
func _enemy_hit(controller: Node, amount: int) -> void:
	var player: Combatant = controller.get("player")
	player.hp -= amount
	var enemy: Node = (controller.get("enemies") as Array)[0]
	controller.call("_report_damage", enemy, player, amount, "attack")

func _toughen_enemies(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in controller.get("enemies"):
		var combatant: Combatant = combatants.get(member)
		if combatant != null:
			combatant.max_hp = 999
			combatant.hp = 999

func _win() -> void:
	_overlay().call("_finish_battle", 0) # WIN
	await physics_frame

func _keeper() -> Node:
	for node in _field.find_children("*", "Node3D", true, false):
		var script: Script = node.get_script()
		if script != null and str(script.resource_path).ends_with("field/keeper.gd"):
			return node
	_fail("no Keeper on the floor")
	return null

func _world_keepsake(keeper: Node) -> Node:
	if keeper == null:
		return null
	for child in keeper.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("world_keepsake.gd") and not child.is_queued_for_deletion():
			return child
	return null

func _load_field(floor_index: int) -> void:
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _start_fight(floor_index: int, group: StringName) -> Node:
	await _load_field(floor_index)
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if node.get("group") == group:
			target = node as Node3D
			break
	if target == null:
		_fail("no enemy to fight on floor %d (group '%s')" % [floor_index + 1, group])
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var overlay: Node = _overlay()
	if overlay == null:
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	return overlay.get("battle_controller")

func _overlay() -> Node:
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _hand_size(controller: Node) -> int:
	return (controller.get("deck").get("hand") as Array).size()

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 2:
		await process_frame

func _expect(condition: bool, label: String) -> void:
	if condition:
		print("ok   ", label)
	else:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		print("ok   ", label, " (", actual, ")")
	else:
		_fail("%s - expected %s, got %s" % [label, str(expected), str(actual)])

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL ", label)
