extends SceneTree

# Headless probe for the keepsake prototype (one trinket slot): the slot
# rules, each prototype trinket's effect, where they may and may not come
# from, and that the slot lives exactly as long as the run.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/trinket_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases build Combatants and resolve real cards; field cases load
# the real region scene and start fights through RegionField's contact
# handler, the way kill_order_probe does (a teleport doesn't move a body
# through the physics server, so the Area never fires headless). Death
# comes last: Restart changes the scene. Untyped against anything that names
# the RunState autoload (RegionField, BattleController, KeepsakeOffer):
# a SceneTree script compiles before the autoloads register.

const CASES := 22
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
const KEEPSAKE_OFFER_SCENE_PATH := "res://battle/keepsake_offer.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const WHITE_SHELL_PATH := "res://run/keepsakes/white_shell.tres"
const FRAYED_CORD_PATH := "res://run/keepsakes/frayed_cord.tres"
const WORN_PAGE_PATH := "res://run/keepsakes/worn_page.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const DYING_LIGHT_PATH := "res://battle/rules/statuses/dying_light.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const DOWN_PAYMENT_PATH := "res://cards/data/down_payment.tres"
# Where a card reward could ever be drawn from.
const REWARD_SEARCH_ROOTS: Array[String] = ["res://cards", "res://floors", "res://run", "res://battle"]
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
	_new_run()

	_check_empty_slot_equips()
	_check_second_does_not_stack()
	await _check_offer_take_replaces()
	await _check_offer_keep_leaves_new()
	_check_new_run_clears()
	_check_bent_nail()
	_check_bent_nail_spent_while_buried()
	_check_dying_light_unchanged()
	_check_frayed_cord_self_loss()
	_check_frayed_cord_not_enemy_damage()
	_check_descriptions()
	_check_art()
	_check_never_in_card_rewards()
	_check_wardling_table_guaranteed()
	await _check_combat_start_and_worn_page()
	await _check_white_shell_win_not_escape()
	await _check_frayed_cord_tick()
	await _check_persists_across_floors()
	await _check_wardling_drop_offered()
	await _check_debug_row()
	await _check_hud_line()
	await _check_restart_clears()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("trinket_probe: PASSED")
		quit(0)
	else:
		print("trinket_probe: %d FAILED" % _failures)
		quit(1)

# --- The slot ---

func _check_empty_slot_equips() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	_expect(_keepsake() == null, "A new run's slot is empty")
	_expect(bool(_run_state.call("acquire_keepsake", nail)), "Acquiring into an empty slot equips at once")
	_expect(_keepsake() == nail, "...Bent Nail is held")
	_completed += 1

func _check_second_does_not_stack() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	var shell: TrinketData = load(WHITE_SHELL_PATH)
	_run_state.call("acquire_keepsake", nail)
	_expect(not bool(_run_state.call("acquire_keepsake", shell)), "A second acquisition into a full slot is refused - it's a choice, not a stack")
	_expect(_keepsake() == nail, "...the first is still the one held")
	_completed += 1

func _check_offer_take_replaces() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	var shell: TrinketData = load(WHITE_SHELL_PATH)
	_run_state.call("equip_keepsake", nail)
	var offer: Node = await _open_offer(shell, nail)
	_expect_eq(_choice_label(offer, 1), "KEEP CURRENT", "A full slot offers TAKE / KEEP CURRENT")
	offer.call("_activate", 0)
	await process_frame
	_expect(_keepsake() == shell, "TAKE replaces: White Shell held, Bent Nail left behind")
	_expect(not is_instance_valid(offer), "...and the offer is gone")
	_completed += 1

func _check_offer_keep_leaves_new() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	var shell: TrinketData = load(WHITE_SHELL_PATH)
	_run_state.call("equip_keepsake", nail)
	var offer: Node = await _open_offer(shell, nail)
	offer.call("_activate", 1)
	await process_frame
	_expect(_keepsake() == nail, "KEEP CURRENT leaves the new one behind: Bent Nail still held")
	# An empty slot's offer is TAKE / LEAVE, and LEAVE leaves it empty.
	_run_state.call("equip_keepsake", null)
	offer = await _open_offer(shell, null)
	_expect_eq(_choice_label(offer, 1), "LEAVE", "An empty slot offers TAKE / LEAVE")
	offer.call("_activate", 1)
	await process_frame
	_expect(_keepsake() == null, "...and LEAVE leaves the slot empty")
	_completed += 1

func _check_new_run_clears() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	_run_state.call("note_keepsake_offered", load(WHITE_SHELL_PATH))
	_run_state.call("set_toll", 4)
	_new_run()
	_expect(_keepsake() == null, "new_run() empties the slot")
	_expect((_run_state.get("keepsakes_offered") as Array).is_empty(), "...and forgets what was offered")
	_expect_eq(int(_run_state.get("toll")), 0, "...and Toll starts at 0")
	_completed += 1

# --- Effects, on the rules layer ---

func _check_bent_nail() -> void:
	var nail: TrinketData = load(BENT_NAIL_PATH)
	var player := _player(50)
	var enemy := Combatant.new(100)
	nail.apply_combat_start(player.statuses)
	_expect_eq(player.statuses.size(), 1, "Bent Nail opens the fight with one status")
	_expect_eq(player.statuses[0].label(), "Keen ×1", "...shown as Keen ×1")
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(enemy.hp, 100 - 11, "The first Attack deals 8 + 3")
	_expect(player.statuses.is_empty(), "...and spends the status")
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(enemy.hp, 100 - 11 - 8, "The second Attack deals the card's own 8")
	_completed += 1

# Current behaviour, documented: an Attack played with every enemy buried
# (ctx.enemies holds only the hittable - none) still takes, and spends,
# the charge - Blood Arc needs no target, so it can be played then.
func _check_bent_nail_spent_while_buried() -> void:
	var nail: TrinketData = load(BENT_NAIL_PATH)
	var player := _player(50)
	var buried := Combatant.new(100)
	buried.buried = true
	nail.apply_combat_start(player.statuses)
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = []
	EffectResolver.new().resolve_card(load(BLOOD_ARC_PATH) as CardData, ctx)
	_expect(player.statuses.is_empty(), "An Attack with every enemy buried still spends Bent Nail's charge")
	_expect_eq(buried.hp, 100, "...while dealing nothing")
	_completed += 1

func _check_dying_light_unchanged() -> void:
	var dying_light: StatusData = load(DYING_LIGHT_PATH)
	var player := _player(50)
	player.hp = 10
	var enemy := Combatant.new(100)
	Status.apply_to(player.statuses, dying_light)
	_play(BITE_DOWN_PATH, player, enemy)
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(enemy.hp, 100 - 11 - 11, "Dying Light pays +3 on every Attack while Critical, as before")
	_expect(Status.find_in(player.statuses, dying_light) != null, "...and is never spent - it has no charges")
	# With Bent Nail's status beside it: both on the first, Dying Light alone after.
	var nail: TrinketData = load(BENT_NAIL_PATH)
	nail.apply_combat_start(player.statuses)
	enemy.hp = 100
	_play(BITE_DOWN_PATH, player, enemy)
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(enemy.hp, 100 - 14 - 11, "Beside Keen: 8 + 3 + 3, then 8 + 3")
	_expect(Status.find_in(player.statuses, dying_light) != null, "...Dying Light still up")
	_completed += 1

func _check_frayed_cord_self_loss() -> void:
	var cord: TrinketData = load(FRAYED_CORD_PATH)
	var player := _player(50)
	var enemy := Combatant.new(100)
	cord.apply_combat_start(player.statuses)
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(player.toll, 4, "The first Bite Down: 2 Toll + 2 extra")
	_expect(player.statuses.is_empty(), "...and Frayed is spent")
	_play(BITE_DOWN_PATH, player, enemy)
	_expect_eq(player.toll, 6, "The second Bite Down: the normal 2")
	# SELF_DAMAGE_TOLL's fixed total gets the bonus on top.
	var paying := _player(50)
	cord.apply_combat_start(paying.statuses)
	_play(DOWN_PAYMENT_PATH, paying, null)
	_expect_eq(paying.toll, 7, "Down Payment with Frayed: its 5 Toll + 2 extra")
	_completed += 1

func _check_frayed_cord_not_enemy_damage() -> void:
	var cord: TrinketData = load(FRAYED_CORD_PATH)
	var data: EnemyData = load(SPUTTER_PATH)
	var player := _player(50)
	cord.apply_combat_start(player.statuses)
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	var hit: bool = false
	for turn in 6:
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		if int(result.get("damage_to_hp", 0)) > 0:
			hit = true
	_expect(hit, "The Sputter's turns land at least one hit (the check means something)")
	_expect_eq(player.toll, 0, "Enemy hits give no Toll with Frayed Cord")
	_expect_eq(player.statuses.size(), 1, "...and Frayed is still waiting")
	_completed += 1

func _check_descriptions() -> void:
	var keen := Status.new((load(BENT_NAIL_PATH) as TrinketData).combat_start_status)
	var frayed := Status.new((load(FRAYED_CORD_PATH) as TrinketData).combat_start_status)
	print("   Keen: ", keen.describe())
	print("   Frayed: ", frayed.describe())
	_expect_eq(keen.describe(), "+3 damage on your next Attack.", "Keen's live description")
	_expect_eq(frayed.describe(), "The next time you lose HP to your own effect, gain 2 extra Toll.", "Frayed's live description")
	for path in [BENT_NAIL_PATH, WHITE_SHELL_PATH, FRAYED_CORD_PATH, WORN_PAGE_PATH]:
		var trinket: TrinketData = load(path)
		print("   ", trinket.display_name, ": ", trinket.describe())
		_expect(not trinket.describe().contains("{"), "%s's description has no unfilled token" % trinket.display_name)
	_completed += 1

# Every prototype keepsake has its object art: a square texture, for the
# offer's large view and its small held strip alike.
func _check_art() -> void:
	for path in [BENT_NAIL_PATH, WHITE_SHELL_PATH, FRAYED_CORD_PATH, WORN_PAGE_PATH]:
		var trinket: TrinketData = load(path)
		_expect(trinket.art != null, "%s has art" % trinket.display_name)
		if trinket.art != null:
			_expect_eq(trinket.art.get_width(), trinket.art.get_height(), "...square")
		_expect(not trinket.describe_short().is_empty() and not trinket.describe_short().contains("{"), "%s has a filled short line" % trinket.display_name)
	_completed += 1

# Card rewards draw from RewardPools, and a pool holds CardData. No
# pool anywhere holds a trinket, and a trinket isn't a card.
func _check_never_in_card_rewards() -> void:
	var nail: Resource = load(BENT_NAIL_PATH)
	_expect(not (nail is CardData), "A trinket is not a CardData")
	var pools: int = 0
	for path in _tres_under(REWARD_SEARCH_ROOTS):
		var resource: Resource = load(path)
		var pool := resource as RewardPool
		if pool == null:
			continue
		pools += 1
		for entry in pool.entries:
			_expect(not ((entry as Resource) is TrinketData), "%s holds no trinket" % path)
	_expect(pools > 0, "The search found the reward pools (%d)" % pools)
	_completed += 1

func _check_wardling_table_guaranteed() -> void:
	var data: EnemyData = load(WARDLING_PATH)
	var table: KeepsakeTable = data.keepsake_table
	_expect(table != null, "The Wardling has a keepsake table")
	if table == null:
		_completed += 1
		return
	_expect(table.guaranteed, "...its drop is guaranteed")
	_expect_eq(table.entries.size(), 4, "...the four prototype trinkets")
	for entry in table.entries:
		_expect_eq(entry.weight, 1.0, "...%s weighted equally" % entry.trinket.display_name)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var none: Array[StringName] = []
	var seen: Dictionary = {}
	for i in 400:
		var drop: TrinketData = table.roll(rng, null, none)
		_expect(drop != null, "Roll %d with an empty slot drops something" % i)
		if drop != null:
			seen[drop.id] = true
	_expect_eq(seen.size(), 4, "All four come up")
	for entry in table.entries:
		for i in 50:
			var drop: TrinketData = table.roll(rng, entry.trinket, none)
			_expect(drop != null and drop != entry.trinket, "Holding %s: a drop, never %s" % [entry.trinket.display_name, entry.trinket.display_name])
	_expect(load(SPUTTER_PATH).get("keepsake_table") == null, "The Sputter has no table")
	_completed += 1

# --- Effects, in real fights ---

func _check_combat_start_and_worn_page() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.statuses.size(), 1, "In a real fight, Bent Nail's status is on the Wanderer from setup()")
		_expect_eq(_hand_size(controller), 5, "...and the opening hand is the usual 5")
	await _teardown()
	_run_state.call("equip_keepsake", load(WORN_PAGE_PATH))
	controller = await _start_fight(0, &"")
	if controller != null:
		_expect_eq(_hand_size(controller), 6, "Worn Page: the opening hand is 6")
		controller.get("_hand_container").call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(_hand_size(controller), 5, "...and the second turn's draw is the usual 5")
	await _teardown()
	_completed += 1

func _check_white_shell_win_not_escape() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(WHITE_SHELL_PATH))
	var max_hp: int = int(_run_state.get("player_max_hp"))
	_run_state.set("player_hp", max_hp - 10)
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		_overlay().call("_finish_battle", 0) # WIN
		await physics_frame
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 8, "White Shell: +2 HP after a win")
	await _teardown()
	_run_state.set("player_hp", max_hp - 10)
	controller = await _start_fight(0, &"")
	if controller != null:
		_overlay().call("_finish_battle", 2) # ESCAPE
		await physics_frame
		_expect_eq(int(_run_state.get("player_hp")), max_hp - 10, "...and nothing after an escape")
	await _teardown()
	_expect(_keepsake() == load(WHITE_SHELL_PATH), "The keepsake persists across both fights")
	_completed += 1

func _check_frayed_cord_tick() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(FRAYED_CORD_PATH))
	var tick := StatusData.new()
	tick.id = "probe_tick"
	tick.category = StatusData.Category.TICK
	tick.default_magnitude = 1
	tick.default_duration_turns = 5
	var controller: Node = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, tick)
		var hand: Node = controller.get("_hand_container")
		var before: int = int(_run_state.get("toll"))
		hand.call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(int(_run_state.get("toll")) - before, 1 + 2, "A status tick is self-inflicted: its 1 Toll + Frayed's 2, the first time")
		before = int(_run_state.get("toll"))
		hand.call("discard_hand")
		controller.call("_start_player_turn")
		_expect_eq(int(_run_state.get("toll")) - before, 1, "...the next tick: 1, the bonus spent for this combat")
	await _teardown()
	# A new fight opens with Frayed again.
	controller = await _start_fight(0, &"")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.statuses.size(), 1, "The next fight opens with Frayed again")
	await _teardown()
	_completed += 1

func _check_persists_across_floors() -> void:
	_new_run()
	var nail: TrinketData = load(BENT_NAIL_PATH)
	_run_state.call("equip_keepsake", nail)
	# What a floor advance does to RunState (RegionField._on_floor_exited()),
	# then the next floor's fresh scene.
	_run_state.call("carry_toll")
	_run_state.set("current_floor_index", 1)
	var controller: Node = await _start_fight(1, &"crab")
	_expect(_keepsake() == nail, "Across a floor: Bent Nail still held")
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.statuses.size(), 1, "...and applied in the next floor's fight")
	await _teardown()
	_completed += 1

func _check_wardling_drop_offered() -> void:
	_new_run()
	var controller: Node = await _start_fight(2, &"", WARDLING_PATH)
	if controller == null:
		await _teardown()
		_completed += 1
		return
	_kill_all(controller)
	await create_timer(1.6).timeout
	var reward: Node = _child_with_script(_field, "reward_screen.gd")
	_expect(reward != null, "Killing the Wardling opens its normal reward first")
	_expect(_child_with_script(_field, "keepsake_offer.gd") == null, "...with the keepsake offer not yet up")
	var offered: Array = _run_state.get("keepsakes_offered")
	_expect_eq(offered.size(), 1, "...and one keepsake already rolled (the guarantee)")
	if reward != null:
		reward.call("close")
	await process_frame
	var offer: Node = _child_with_script(_field, "keepsake_offer.gd")
	_expect(offer != null, "The keepsake offer follows the reward")
	if offer != null:
		_expect_eq(_choice_label(offer, 1), "LEAVE", "...TAKE / LEAVE with an empty slot")
		_expect_eq(str(offer.get("_source")), "Wardling", "...its source line names the Wardling")
		_expect(not _field.can_process(), "...over a frozen field")
		offer.call("_activate", 0)
		await process_frame
		_expect(_keepsake() != null and StringName(_keepsake().id) == StringName(offered[0]), "TAKE equips the offered keepsake")
		_expect(_field.can_process(), "...and the field is live again once it closes")
	await _teardown()
	# A Sputter leaves none.
	controller = await _start_fight(0, &"")
	if controller != null:
		_kill_all(controller)
		await create_timer(1.6).timeout
		var sputter_reward: Node = _child_with_script(_field, "reward_screen.gd")
		if sputter_reward != null:
			sputter_reward.call("close")
		await process_frame
		_expect(_child_with_script(_field, "keepsake_offer.gd") == null, "A Sputter leaves no keepsake")
	await _teardown()
	_completed += 1

func _check_debug_row() -> void:
	_new_run()
	await _load_field(0)
	var row: Node = _field.get_node_or_null("FieldHUD/DebugRow")
	_expect(row != null, "A debug build has the field's debug row")
	if row != null:
		_expect(not (row as Control).visible, "...hidden until F1")
		var button: Button = row.get_node("KeepsakeButton")
		_expect_eq(button.text, "Keepsake: Bent Nail", "...its button grants Bent Nail first")
		button.pressed.emit()
		_expect(_keepsake() == load(BENT_NAIL_PATH), "The debug grant equips straight into an empty slot")
		_expect(_child_with_script(_field, "keepsake_offer.gd") == null, "...with no offer")
		button.pressed.emit()
		var offer: Node = _child_with_script(_field, "keepsake_offer.gd")
		_expect(offer != null, "A second grant into a full slot opens the replace-or-keep offer")
		if offer != null:
			_expect_eq(str(offer.get("_source")), "", "...with no source line - the grant has no named source")
			offer.call("_activate", 0)
			await process_frame
			var line: Node = _field.get_node("FieldHUD/KeepsakeLine")
			_expect_eq(str(line.get("_value_text")), "White Shell", "After TAKE replaces it, the KEEPSAKE line names the new one")
	await _teardown()
	_completed += 1

func _check_hud_line() -> void:
	_new_run()
	await _load_field(0)
	var line: Control = _field.get_node("FieldHUD/KeepsakeLine")
	var toll_line: Control = _field.get_node("FieldHUD/TollLine")
	var gold_line: Control = _field.get_node("FieldHUD/GoldLine")
	_expect(not line.visible, "KEEPSAKE is hidden with an empty slot")
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	_expect(line.visible, "...shown once one is held")
	_expect_eq(str(line.get("_value_text")), "Bent Nail", "...naming it")
	_expect(line.position.x > gold_line.position.x + gold_line.size.x, "...beside GOLD")
	_expect_eq(str(toll_line.get("_value_text")), "0", "TOLL still reads its count")
	await _teardown()
	_completed += 1

# Last: Restart changes the scene. Death leaves a keepsake and Toll; the
# RunOver screen's Restart starts a new run.
func _check_restart_clears() -> void:
	_new_run()
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	_run_state.call("set_toll", 3)
	var run_over: Node = (load(RUN_OVER_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(run_over)
	await process_frame
	(run_over.get_node("RestartButton") as Button).pressed.emit()
	_expect(_keepsake() == null, "Death -> Restart leaves the slot empty")
	_expect_eq(int(_run_state.get("toll")), 0, "...and Toll at 0")
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _keepsake() -> TrinketData:
	return _run_state.get("keepsake") as TrinketData

func _player(hp: int) -> Combatant:
	var player := Combatant.new(hp)
	player.critical_hp_fraction = 0.3
	return player

func _play(card_path: String, player: Combatant, target: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	var enemies: Array[Combatant] = []
	if target != null:
		enemies.append(target)
	ctx.enemies = enemies
	EffectResolver.new().resolve_card(load(card_path) as CardData, ctx)

func _open_offer(offered: TrinketData, held: TrinketData) -> Node:
	var offer: Node = (load(KEEPSAKE_OFFER_SCENE_PATH) as PackedScene).instantiate()
	offer.call("setup", offered, held)
	root.add_child(offer)
	await process_frame
	return offer

func _choice_label(offer: Node, index: int) -> String:
	return str(offer.call("_choice_label", index))

func _load_field(floor_index: int) -> void:
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

# Loads the floor and starts a fight with the first enemy of `group` (or
# of `enemy_path`'s data, when given). The fight's BattleController, or
# null (a FAIL is recorded).
func _start_fight(floor_index: int, group: StringName, enemy_path: String = "") -> Node:
	await _load_field(floor_index)
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if enemy_path != "":
			var data: Resource = node.get("enemy_data")
			if data != null and data.resource_path == enemy_path:
				target = node as Node3D
				break
		elif node.get("group") == group:
			target = node as Node3D
			break
	if target == null:
		_fail("no enemy to fight on floor %d (group '%s', data '%s')" % [floor_index + 1, group, enemy_path])
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

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

func _tres_under(roots: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = roots.duplicate()
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			pending.append(dir_path.path_join(sub))
		for file in dir.get_files():
			if file.ends_with(".tres"):
				found.append(dir_path.path_join(file))
	return found

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
	print("FAIL: ", message)
