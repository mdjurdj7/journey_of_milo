extends SceneTree

# Headless probe for Ransom - the card, its two statuses and the rules
# behind them: the waiting status takes hold at the start of the next
# turn (StatusData.grants_on_turn_start), its live half makes every
# Attack Drain (StatusData.attacks_drain) and ends with that turn
# (StatusData.ends_at_turn_end). An Attack that Drains heals, after its
# last effect, half the HP its hits took, rounded down (StatusData.
# ransom_heal_fraction) - no overkill, net of what Grace reclaimed from
# each hit (EffectContext.record_hit()).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/ransom_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases resolve the real cards through EffectResolver.resolve_card()
# against bare Combatants - block, the cap, all enemies, the bonuses and
# Grace, with nothing else moving the numbers. Fight cases load the real
# region scene and start fights through RegionField's contact handler, as
# collateral_probe does, then play real cards through BattleController.
# request_play() / confirm_target() and end_turn() - so the turn-start
# swap, the turn-end removal, Spent and the readout are the game's own.
# Untyped against anything that names the RunState autoload.

const CASES := 14
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const RANSOM_PATH := "res://cards/data/ransom.tres"
const RANSOM_STATUS_PATH := "res://battle/rules/statuses/ransom.tres"
const RANSOM_ACTIVE_PATH := "res://battle/rules/statuses/ransom_active.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const COLLATERAL_PATH := "res://cards/data/collateral.tres"
const COME_DUE_STATUS_PATH := "res://battle/rules/statuses/come_due.tres"
const SELF_EATER_STANCE_PATH := "res://battle/rules/stances/self_eater.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const WAITING_TEXT := "Next turn, your Attacks heal half the damage dealt."
const ACTIVE_TEXT := "This turn, your Attacks heal half the damage dealt."
const PLAYER_MAX_HP := 70
const PLAYER_HP := 40
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
# What the last rules resolution healed, split by source.
var _healed: int = 0
var _reclaimed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	_check_heal_and_block()
	_check_cap_and_overkill()
	_check_all_enemies()
	_check_bonuses()
	_check_grace()
	_check_reckoning_and_skills()
	await _check_turn_played()
	await _check_next_turn_then_ends()
	await _check_no_stack()
	await _check_played_while_active()
	await _check_spent()
	await _check_collateral()
	await _check_fight_ends_first()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("ransom_probe: PASSED")
		quit(0)
	else:
		print("ransom_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(RANSOM_PATH)
	var waiting: StatusData = load(RANSOM_STATUS_PATH)
	var active: StatusData = load(RANSOM_ACTIVE_PATH)
	_expect_eq(card.cost, 3, "Ransom costs 3")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.RARE, "...Rare")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...and Spent")
	_expect_eq(card.description, WAITING_TEXT + "\nSpent.", "The card's text")
	_expect(card.art != null and card.art.resource_path == "res://cards/art/Wanderer/Ransom.png", "...shows its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect(card.effects.size() == 1 and card.effects[0].status_data == waiting, "It applies the waiting status")
	_expect_eq(waiting.grants_on_turn_start, active, "The waiting status gives way to the live one at turn start")
	_expect(not waiting.attacks_drain and not waiting.ends_at_turn_end, "...and does nothing itself")
	_expect(active.attacks_drain and active.ends_at_turn_end, "The live one Drains and ends with the turn")
	_expect(is_equal_approx(active.ransom_heal_fraction, 0.5), "...healing half")
	_expect_eq([waiting.default_duration_turns, active.default_duration_turns], [StatusData.DURATION_UNTIL_REMOVED, StatusData.DURATION_UNTIL_REMOVED], "Neither is aged by the turn counter")
	var statuses: Array[Status] = []
	Status.apply_to(statuses, waiting)
	_expect_eq([statuses[0].label(), statuses[0].describe()], ["Ransom", WAITING_TEXT], "Waiting: Ransom / " + WAITING_TEXT)
	Status.resolve_turn_start_triggers(statuses)
	_expect_eq([statuses.size(), statuses[0].data], [1, active], "Turn start swaps it for the live one")
	_expect_eq([statuses[0].label(), statuses[0].describe()], ["Ransom", ACTIVE_TEXT], "Active: Ransom / " + ACTIVE_TEXT)
	Status.remove_at_turn_end(statuses)
	_expect(statuses.is_empty(), "Turn end removes it")
	_completed += 1

# --- Rules ---

# Slash with no block heals half what it dealt, rounded down; block
# reduces the heal by what it stopped, to 0 when it stops it all. Without
# the live status, nothing.
func _check_heal_and_block() -> void:
	var player: Combatant = _player(false)
	var enemy := Combatant.new(ENEMY_HP)
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq([ENEMY_HP - enemy.hp, _healed], [6, 0], "Without Ransom, Slash deals 6 and heals nothing")
	player = _player()
	enemy = Combatant.new(ENEMY_HP)
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq(_healed, 3, "Draining, Slash heals half the 6 it dealt: 3")
	_expect_eq(player.hp, PLAYER_HP + 3, "...onto the player's HP")
	enemy.block = 3
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq(_healed, 1, "3 Block: Slash heals half the 2 that got through: 1")
	enemy.block = 10
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq(_healed, 0, "Block covering it all: no heal")
	_completed += 1

# The heal stops at max HP; a killing blow heals half the HP that was
# left, not the overkill.
func _check_cap_and_overkill() -> void:
	var player: Combatant = _player()
	player.hp = PLAYER_MAX_HP - 1
	var enemy := Combatant.new(ENEMY_HP)
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq(player.hp, PLAYER_MAX_HP, "1 below max, a 5's heal of 2 stops at max HP")
	player = _player()
	enemy = Combatant.new(ENEMY_HP)
	enemy.hp = 3
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq([enemy.hp, _healed], [0, 1], "A 5 that kills a 3-HP enemy heals half the 3: 1")
	_completed += 1

# Carve against two enemies, one with 2 Block: one heal, the total.
func _check_all_enemies() -> void:
	var player: Combatant = _player()
	var first := Combatant.new(ENEMY_HP)
	var second := Combatant.new(ENEMY_HP)
	second.block = 2
	_resolve(CARVE_PATH, player, [first, second], null)
	_expect_eq([ENEMY_HP - first.hp, ENEMY_HP - second.hp], [6, 4], "Carve deals 6 and 4 through 2 Block")
	_expect_eq(_healed, 5, "...and heals half the 10, once: 5")
	_completed += 1

# Come Due's mark and the Self-Eater stance's bonus are part of the blow,
# so they are part of the heal; the stance's own HP price is still paid.
func _check_bonuses() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	var come_due: StatusData = load(COME_DUE_STATUS_PATH)
	Status.apply_to(enemy.statuses, come_due)
	_resolve(SLASH_PATH, player, [enemy], enemy)
	var marked: int = 6 + come_due.attack_bonus_against_holder
	_expect_eq([ENEMY_HP - enemy.hp, _healed], [marked, marked / 2], "Come Due's +%d: Slash deals %d and heals %d" % [come_due.attack_bonus_against_holder, marked, marked / 2])
	player = _player()
	enemy = Combatant.new(ENEMY_HP)
	Stance.apply_to(player, load(SELF_EATER_STANCE_PATH))
	var price: int = Stance.attack_hp_loss(player.stance)
	var bonus: int = AttackBonus.for_player(player, player.hp - price)
	_expect(bonus > 0 and price > 0, "Self-Eater charges HP and adds damage")
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq([ENEMY_HP - enemy.hp, _healed], [6 + bonus, (6 + bonus) / 2], "Self-Eater's +%d: Slash deals %d and heals %d" % [bonus, 6 + bonus, (6 + bonus) / 2])
	_expect_eq(player.hp, PLAYER_HP - price + (6 + bonus) / 2, "...after its %d HP price" % price)
	_completed += 1

# With Grace open, a hit's damage reclaims Grace first; Drain heals half
# of only what Grace didn't take back from that hit. Grace itself is
# unchanged.
func _check_grace() -> void:
	var player: Combatant = _player()
	player.grace = 6
	var enemy := Combatant.new(ENEMY_HP)
	Status.apply_to(enemy.statuses, load(COME_DUE_STATUS_PATH))
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq(ENEMY_HP - enemy.hp, 10, "Slash with Come Due deals 10")
	_expect_eq([_reclaimed, _healed], [6, 2], "...Grace +6, Drain half the 4 left: +2")
	_expect_eq([player.hp, player.grace], [PLAYER_HP + 8, 0], "...8 HP back in all, Grace spent")
	player = _player()
	player.grace = 20
	enemy = Combatant.new(ENEMY_HP)
	_resolve(SLASH_PATH, player, [enemy], enemy)
	_expect_eq([_reclaimed, _healed, player.grace], [6, 0, 14], "Grace bigger than the hit: Grace +6, Drain nothing")
	_completed += 1

# Reckoning, an Attack through its own resolver, Drains too - half, no
# cap: 27 heals 13; a Skill under the same status heals nothing.
func _check_reckoning_and_skills() -> void:
	var player: Combatant = _player()
	player.toll = 7
	var enemy := Combatant.new(ENEMY_HP)
	_resolve(RECKONING_PATH, player, [enemy], enemy)
	_expect_eq([ENEMY_HP - enemy.hp, _healed], [7, 3], "Reckoning on 7 Toll deals 7 and heals 3")
	player = _player()
	player.hp = PLAYER_HP - 20
	player.toll = 27
	enemy = Combatant.new(40)
	_resolve(RECKONING_PATH, player, [enemy], enemy)
	_expect_eq([40 - enemy.hp, _healed], [27, 13], "Reckoning on 27 Toll deals 27 and heals 13")
	player = _player()
	enemy = Combatant.new(ENEMY_HP)
	_resolve(BRACE_PATH, player, [enemy], null)
	_expect_eq(_healed, 0, "Brace, a Skill, heals nothing")
	_completed += 1

# --- Fights ---

# The turn it's played: 3 Energy, the waiting line, and an Attack after it
# heals nothing.
func _check_turn_played() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, RANSOM_PATH))
		_expect_eq(player.energy, 0, "Ransom costs 3 Energy")
		_expect_eq(_ransom_lines(controller), [WAITING_TEXT], "The readout: Ransom / " + WAITING_TEXT)
		player.energy = 3
		var hp_before: int = player.hp
		await _play(controller, await _deal(controller, SLASH_PATH), _field_enemy(controller))
		_expect_eq(player.hp, hp_before, "Slash the same turn heals nothing")
	await _teardown()
	_completed += 1

# Next turn the live line shows and an Attack heals exactly what it took;
# the turn after, it's gone and heals nothing.
func _check_next_turn_then_ends() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, RANSOM_PATH))
		await _next_turn(controller)
		_expect_eq(_ransom_lines(controller), [ACTIVE_TEXT], "Next turn the readout: Ransom / " + ACTIVE_TEXT)
		_expect_eq(_slash_heal(await _slash(controller)), true, "...and Slash heals half what it dealt")
		await _next_turn(controller)
		_expect_eq(_ransom_lines(controller), [], "The turn after, no Ransom line")
		var hit: Array = await _slash(controller)
		_expect(hit[0] > 0 and hit[1] == 0, "...and Slash heals nothing (dealt %d, healed %d)" % hit)
	await _teardown()
	_completed += 1

# Two Ransoms while one waits: one status, one stack, one Drain.
func _check_no_stack() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, RANSOM_PATH))
		player.energy = 3
		await _play(controller, await _deal(controller, RANSOM_PATH))
		_expect_eq(_ransom_lines(controller), [WAITING_TEXT], "Two Ransoms: one waiting line")
		var waiting: Status = Status.find_in(player.statuses, load(RANSOM_STATUS_PATH))
		_expect_eq(player.statuses.filter(func(active: Status) -> bool: return active.data.id == "ransom").size(), 1, "...one status")
		_expect_eq(waiting.stack_count if waiting != null else 0, 1, "...one stack")
		await _next_turn(controller)
		_expect_eq(_ransom_lines(controller), [ACTIVE_TEXT], "Next turn: one live line")
		_expect_eq(_slash_heal(await _slash(controller)), true, "...and Slash heals once, half what it dealt")
	await _teardown()
	_completed += 1

# A Ransom played during the live turn sets up the turn after as usual.
func _check_played_while_active() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		await _play(controller, await _deal(controller, RANSOM_PATH))
		await _next_turn(controller)
		await _play(controller, await _deal(controller, RANSOM_PATH))
		_expect_eq(_ransom_lines(controller), [ACTIVE_TEXT, WAITING_TEXT], "Played while live: both lines")
		_expect_eq(_slash_heal(await _slash(controller)), true, "...Slash still Drains this turn")
		await _next_turn(controller)
		_expect_eq(_ransom_lines(controller), [ACTIVE_TEXT], "The turn after: live again")
		_expect_eq(_slash_heal(await _slash(controller)), true, "...and Slash Drains again")
		await _next_turn(controller)
		_expect_eq(_ransom_lines(controller), [], "...then it ends")
	await _teardown()
	_completed += 1

# Spent: out of the rotation for the rest of the fight.
func _check_spent() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var ransom: CardData = await _deal(controller, RANSOM_PATH)
		await _play(controller, ransom)
		var deck: Object = controller.get("deck")
		var exhaust: Array = deck.get("exhaust_pile")
		for i in 180:
			if exhaust.has(ransom):
				break
			await process_frame
		_expect(exhaust.has(ransom), "Ransom is Spent")
		await _next_turn(controller)
		await _next_turn(controller)
		_expect(exhaust.has(ransom), "...and stays Spent two turns on")
		for pile: String in ["draw_pile", "hand", "discard_pile"]:
			_expect(not (deck.get(pile) as Array).has(ransom), "...not in %s" % pile)
	await _teardown()
	_completed += 1

# Collateral pays for it: 3 ≥ 2, so 0 Energy and 5 HP.
func _check_collateral() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		var hp_before: int = player.hp
		await _play(controller, await _deal(controller, RANSOM_PATH))
		_expect_eq(player.energy, 3, "Under Collateral, Ransom costs 0 Energy")
		_expect_eq(hp_before - player.hp, 5, "...and 5 HP")
		_expect_eq(_ransom_lines(controller), [WAITING_TEXT], "...and still waits for next turn")
	await _teardown()
	_completed += 1

# A fight that ends before the next turn takes the waiting Ransom with it.
func _check_fight_ends_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		await _play(controller, await _deal(controller, RANSOM_PATH))
	await _teardown()
	controller = await _start_fight()
	if controller != null:
		_expect_eq(_ransom_lines(controller), [], "The next fight starts without Ransom")
	await _teardown()
	_completed += 1

# --- Helpers ---

# A player at PLAYER_HP of PLAYER_MAX_HP, with Ransom's live status when
# `draining`.
func _player(draining: bool = true) -> Combatant:
	var player := Combatant.new(PLAYER_MAX_HP)
	player.hp = PLAYER_HP
	if draining:
		Status.apply_to(player.statuses, load(RANSOM_ACTIVE_PATH))
	return player

# Resolves the card at `path` through the real resolver, recording what
# it healed (_healed) and what Grace reclaimed (_reclaimed).
func _resolve(path: String, player: Combatant, enemies: Array[Combatant], target: Combatant) -> void:
	_healed = 0
	_reclaimed = 0
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	ctx.enemies = enemies
	ctx.on_heal = func(amount: int) -> void: _healed += amount
	ctx.on_grace_reclaimed = func(amount: int) -> void: _reclaimed += amount
	_resolver.resolve_card(load(path), ctx)

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, at PLAYER_HP, with an empty hand and 3 Energy.
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
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
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	controller.get("deck").call("discard_hand")
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# Ends the turn and waits out the enemy's, then empties the new hand and
# clears what the enemy's hit opened (Grace) and left (Block on it), so
# the next Slash's heal is its Drain alone.
func _next_turn(controller: Node) -> void:
	await controller.call("end_turn")
	for i in 600:
		if not bool(controller.get("_input_locked")):
			break
		await process_frame
	var player: Combatant = controller.get("player")
	player.grace = 0
	_enemy(controller).block = 0
	controller.get("deck").call("discard_hand")
	await process_frame

# Plays a fresh Slash at the enemy; returns [HP it took, HP the player
# gained].
func _slash(controller: Node) -> Array:
	var player: Combatant = controller.get("player")
	player.energy = 3
	var enemy: Combatant = _enemy(controller)
	var enemy_before: int = enemy.hp
	var hp_before: int = player.hp
	await _play(controller, await _deal(controller, SLASH_PATH), _field_enemy(controller))
	return [enemy_before - enemy.hp, player.hp - hp_before]

func _slash_heal(hit: Array) -> bool:
	if hit[0] <= 0 or hit[1] != int(hit[0]) / 2:
		_fail("Slash dealt %d and healed %d" % hit)
		return false
	return true

# A fresh copy of the card at `path`, drawn into the hand.
func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

# Plays `card` from the hand through the controller's own path, and waits
# for the play to resolve.
func _play(controller: Node, card: CardData, target: Node = null) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if target != null:
		controller.call("confirm_target", target)
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

# The Wanderer readout's Ransom lines, as their reveals read, top to
# bottom - the rows BattleOverlay actually hands the HP bar.
func _ransom_lines(controller: Node) -> Array:
	var bar: Object = controller.get_parent().get("_field_hp_bar")
	var lines: Array = []
	if bar == null:
		_fail("no HP bar readout")
		return lines
	for item: Dictionary in bar.get("_row_items"):
		if String(item.get("name", "")) == "Ransom":
			lines.append(String(item.get("rules", "")))
	return lines

func _enemy(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
