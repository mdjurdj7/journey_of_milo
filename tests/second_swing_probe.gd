extends SceneTree

# Headless probe for Second Swing - 1 Energy, Uncommon Skill, TOLL:
# "Spend 5 Toll. Play the last Attack you played this turn again." No
# damage of its own; blocked under 5 Toll or with no Attack played this
# turn. The replay resolves that Attack's effects in full as if played -
# its own HP and Toll (Bite Down), the stance's price and bonus (Self-
# Eater) - but isn't a play: no Energy, no pile moved, no played-card or
# tag count, no Bent Nail, and a one-shot Keen the Attack already spent
# stays spent. At the enemy it was played at while that one stands, at
# every enemy for an all-enemies Attack (Carve). Second Swing+ costs 0.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/second_swing_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Rules cases play the real cards through EffectResolver on bare
# Combatants. The fight cases load floor 5 and play through
# BattleController at the Greyshelf: Slash then Second Swing lands two
# blows, two Goaded stacks into a queued Gape, Slash's card staying in
# the discard; a Spent Claw Back replays from the Spent pile; with the
# Attack's enemy no longer standing, Second Swing asks for a target.
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 11
const CARD_PATH := "res://cards/data/second_swing.tres"
const TEMPERED_PATH := "res://cards/tempered/second_swing_tempered.tres"
const ART_PATH := "res://cards/art/Wanderer/Second Swing.png"
const SLASH_PATH := "res://cards/data/slash.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const CLAW_BACK_PATH := "res://cards/data/claw_back.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const KEEN_PATH := "res://battle/rules/statuses/keen.tres"
const BENT_NAIL_PATH := "res://battle/rules/statuses/bent_nail.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const GOADED_PATH := "res://battle/rules/statuses/goaded.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const FLOOR_5 := 4
const PLAYER_HP := 999
const ENEMY_HP := 100
const HIT := 6
const SELF_EATER_BONUS := 3
const SELF_EATER_PRICE := 2

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _toll: int = 0

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	_toll = _card().effects[0].toll_cost
	_check_card_data()
	_check_blocked()
	_check_replays_slash()
	_check_own_costs()
	_check_stance()
	_check_one_shots()
	_check_targets()
	await _check_face()
	await _check_fight_gape()
	await _check_fight_spent()
	await _check_fight_needs_target()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("second_swing_probe: PASSED")
		quit(0)
	else:
		print("second_swing_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card()
	_expect_eq(card.card_name, "Second Swing", "The card is named Second Swing")
	_expect_eq([card.card_type, card.rarity, card.card_class], [CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON, &"wanderer"], "...a Skill, Uncommon, the Wanderer's")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...no target of its own")
	_expect_eq(card.removal_scope, CardData.RemovalScope.NONE, "...not Spent")
	_expect_eq(card.description, "Spend {toll_cost} Toll.\nPlay the last Attack you played this turn again.", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[1].effect_type == CardEffect.EffectType.REPLAY_LAST_ATTACK, "...SPEND_TOLL, then REPLAY_LAST_ATTACK")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...its art kept")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Second Swing+")
	_expect_eq([tempered.card_name, tempered.card_type, tempered.rarity], ["Second Swing+", CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON], "Second Swing+: the same Skill")
	_expect_eq(tempered.description, card.description, "...the same text")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "In the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector's")
	_completed += 1

# Blocked with no Attack played this turn, whatever the Toll; then by
# Toll under 5; playable on 5.
func _check_blocked() -> void:
	var player: Combatant = _player()
	player.toll = 9
	_expect(EffectResolver.card_blocked(_card(), player), "No Attack played this turn: blocked on 9 Toll")
	player.record_attack(load(SLASH_PATH), null, false)
	player.toll = _toll - 1
	_expect(EffectResolver.card_blocked(_card(), player), "An Attack played, %d Toll: blocked" % (_toll - 1))
	player.toll = _toll
	_expect(not EffectResolver.card_blocked(_card(), player), "...%d: playable" % _toll)
	player.clear_last_attack()
	_expect(EffectResolver.card_blocked(_card(), player), "The turn's record cleared: blocked again")
	player.record_attack(load(SELF_EATER_PATH), null, false)
	_expect(player.last_attack == null, "A Stance played is no Attack to replay")
	_completed += 1

# Slash at an enemy, then Second Swing on 7 Toll: 6 again, 5 spent, no
# Energy, no tag or play counted.
func _check_replays_slash() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	player.energy = 3
	_play_attack(load(SLASH_PATH), player, enemy, [enemy])
	_expect_eq(ENEMY_HP - enemy.hp, HIT, "Slash: 6")
	player.toll = 7
	var tags: Dictionary = player.tagged_plays_this_turn.duplicate()
	_play(_card(), player, null, [enemy])
	_expect_eq(ENEMY_HP - enemy.hp, 2 * HIT, "Second Swing replays it: 6 again")
	_expect_eq(player.toll, 7 - _toll, "...%d Toll spent" % _toll)
	_expect_eq(player.energy, 3, "...no Energy taken by the replay")
	_expect_eq(player.tagged_plays_this_turn, tags, "...no tag counted")
	_expect_eq(player.last_attack, load(SLASH_PATH), "...and Slash still the last Attack")
	_completed += 1

# Bite Down: deal 8, then lose 2 HP and make 2 Toll - the replay pays and
# makes them again.
func _check_own_costs() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	_play_attack(load(BITE_DOWN_PATH), player, enemy, [enemy])
	var hp: int = player.hp
	player.toll = _toll
	_play(_card(), player, null, [enemy])
	_expect_eq(ENEMY_HP - enemy.hp, 16, "Bite Down replayed: 8 again")
	_expect_eq(hp - player.hp, 2, "...its 2 HP paid again")
	_expect_eq(player.toll, 2, "...and its 2 Toll made again, after the 5 spent")
	_completed += 1

# Under Self-Eater the replay is an Attack like any: its price and its +3.
func _check_stance() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	_play(load(SELF_EATER_PATH), player, null, [enemy])
	_play_attack(load(SLASH_PATH), player, enemy, [enemy])
	var hp: int = player.hp
	player.toll += _toll
	var dealt: int = ENEMY_HP - enemy.hp
	_play(_card(), player, null, [enemy])
	_expect_eq(ENEMY_HP - enemy.hp - dealt, HIT + SELF_EATER_BONUS, "Under Self-Eater the replay deals 6 + 3")
	_expect_eq(hp - player.hp, SELF_EATER_PRICE, "...and pays its 2 HP")
	_completed += 1

# Keen's one charge went with Slash; Bent Nail, still up, neither doubles
# the replay nor is spent by it.
func _check_one_shots() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	Status.apply_to(player.statuses, load(KEEN_PATH))
	_play_attack(load(SLASH_PATH), player, enemy, [enemy])
	_expect(not _holds(player, KEEN_PATH), "Slash spends Keen")
	player.toll = _toll
	var before: int = enemy.hp
	_play(_card(), player, null, [enemy])
	_expect_eq(before - enemy.hp, HIT, "...the replay lands 6, no Keen")
	var nailed: Combatant = _player()
	var other := Combatant.new(ENEMY_HP)
	nailed.record_attack(load(SLASH_PATH), other, false)
	Status.apply_to(nailed.statuses, load(BENT_NAIL_PATH))
	nailed.toll = _toll
	_play(_card(), nailed, null, [other])
	_expect_eq(ENEMY_HP - other.hp, HIT, "Bent Nail up: the replay isn't doubled")
	_expect(_holds(nailed, BENT_NAIL_PATH), "...nor does it spend Bent Nail")
	_completed += 1

# Slash's enemy dead: the replay goes to the card's own target; Carve (all
# enemies) hits every one.
func _check_targets() -> void:
	var player: Combatant = _player()
	var first := Combatant.new(ENEMY_HP)
	var second := Combatant.new(ENEMY_HP)
	_play_attack(load(SLASH_PATH), player, first, [first, second])
	first.hp = 0
	player.toll = _toll
	_play(_card(), player, second, [second])
	_expect_eq(ENEMY_HP - second.hp, HIT, "Slash's enemy dead: the replay lands on the other")
	var all: Combatant = _player()
	var a := Combatant.new(ENEMY_HP)
	var b := Combatant.new(ENEMY_HP)
	_play_attack(load(CARVE_PATH), all, null, [a, b], true)
	all.toll = _toll
	_play(_card(), all, null, [a, b])
	_expect_eq([ENEMY_HP - a.hp, ENEMY_HP - b.hp], [2 * HIT, 2 * HIT], "Carve replayed: 6 more to each")
	_completed += 1

func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(_card())
	_expect_eq(view.rules_text.get_parsed_text(), "Spend 5 Toll.\nPlay the last Attack you played this turn again.", "The face reads its rule")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view.type_label.text, "TOLL", "...labelled TOLL")
	_expect(not view.hp_cost_label.visible, "...no HP badge")
	view.free()
	_completed += 1

# The Gape queued at the Greyshelf: Slash at it, then Second Swing on 12
# Toll - two blows (the replay a swing of its own), two Goaded stacks, 5
# Toll spent, 2 Energy in all, Slash's card in the discard once.
func _check_fight_gape() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).get(greyshelf)
		await _end_turn(controller)
		_expect_eq(EnemyTurn.current_intent(combatant, greyshelf.get("enemy_data")).intent_name, "Gape", "The Gape is queued")
		var player: Combatant = controller.get("player")
		player.toll = 12
		player.energy = 3
		var replayed: Array = []
		controller.connect("card_replayed", func(card: CardData, target: Variant) -> void:
			replayed.append([card.card_name, target]))
		var hits: Array[int] = []
		controller.connect("damage_dealt", func(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
			if target == greyshelf:
				hits.append(amount))
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await _play_view(controller, slash, greyshelf)
		var swing: CardData = await _deal(controller, CARD_PATH)
		await _play_view(controller, swing, null)
		_expect_eq(hits, [HIT, HIT] as Array[int], "Slash, then its replay: two blows of 6")
		_expect_eq(replayed.size(), 1, "...the replay swung as Slash (card_replayed once)")
		if replayed.size() == 1:
			_expect(replayed[0][0] == "Slash" and replayed[0][1] == greyshelf, "...at the Greyshelf")
		_expect_eq(_goaded(combatant), 2, "...two Goaded stacks - an Attack each time")
		_expect_eq(player.toll, 12 - _toll, "...5 Toll spent")
		_expect_eq(player.energy, 1, "...2 Energy in all: Slash's and Second Swing's")
		_expect_eq((deck.get("discard_pile") as Array).count(slash), 1, "...Slash's card in the discard once")
		_expect(not bool(controller.get("_input_locked")), "Input unlocks after the replay")
	await _teardown()
	_completed += 1

# Claw Back is Spent once played; Second Swing replays it from there.
func _check_fight_spent() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).get(greyshelf)
		var player: Combatant = controller.get("player")
		player.toll = _toll
		player.energy = 9
		var deck: Object = controller.get("deck")
		var claw: CardData = await _deal(controller, CLAW_BACK_PATH)
		await _play_view(controller, claw, greyshelf)
		var hp: int = combatant.hp
		_expect((deck.get("exhaust_pile") as Array).has(claw), "Claw Back is Spent")
		await _play_view(controller, await _deal(controller, CARD_PATH), null)
		_expect(combatant.hp < hp, "Second Swing replays the Spent Claw Back (%d to %d)" % [hp, combatant.hp])
		_expect_eq((deck.get("exhaust_pile") as Array).count(claw), 1, "...which stays where it was")
	await _teardown()
	_completed += 1

# The Attack's enemy no longer stands where it was played (the record's
# enemy gone): Second Swing asks for a target, and replays at the one
# chosen.
func _check_fight_needs_target() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var player: Combatant = controller.get("player")
		player.toll = _toll
		player.energy = 9
		await _play_view(controller, await _deal(controller, SLASH_PATH), greyshelf)
		controller.set("_last_attack_enemy", null)
		var hits: Array[int] = []
		controller.connect("damage_dealt", func(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
			if target == greyshelf:
				hits.append(amount))
		var view: CardView = _view(controller, await _deal(controller, CARD_PATH))
		controller.call("request_play", view)
		_expect(bool(controller.call("is_awaiting_target")), "Its enemy gone: Second Swing asks for a target")
		controller.call("confirm_target", greyshelf)
		await ProbePlay.settle(self, controller)
		_expect_eq(hits, [HIT] as Array[int], "...and replays Slash at the one chosen")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _card() -> CardData:
	return load(CARD_PATH) as CardData

func _player() -> Combatant:
	return Combatant.new(PLAYER_HP)

func _holds(player: Combatant, path: String) -> bool:
	for active in player.statuses:
		if active.data != null and active.data.resource_path == path:
			return true
	return false

# `card` resolved as BattleController would play it, recorded as the
# last Attack.
func _play_attack(card: CardData, player: Combatant, target: Combatant, enemies: Array[Combatant], all_enemies: bool = false) -> void:
	player.record_attack(card, target, all_enemies)
	player.count_play(card)
	_play(card, player, target, enemies)

func _play(card: CardData, player: Combatant, target: Combatant, enemies: Array[Combatant]) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	ctx.enemies = enemies
	_resolver.resolve_card(card, ctx)

func _goaded(combatant: Combatant) -> int:
	for active: Status in combatant.statuses:
		if active.data.resource_path == GOADED_PATH:
			return active.stack_count
	return 0

func _find_greyshelf() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == GREYSHELF_PATH:
			return node as Node3D
	return null

# A new run on floor 5, the fight started on the Greyshelf, the hand
# emptied. The controller, or null (a FAIL is recorded).
func _start_fight() -> Node:
	if _run_state == null:
		_fail("no RunState autoload")
		return null
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_5)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = _find_greyshelf()
	if target == null:
		_fail("no Greyshelf on floor 5")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 5")
		return null
	var controller: Node = overlay.get("battle_controller")
	await ProbePlay.settle_fight(self, _field, controller)
	controller.get("deck").call("discard_hand")
	return controller

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

func _play_view(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if target != null:
		if not bool(controller.call("is_awaiting_target")):
			_fail("'%s' didn't ask for a target" % card.card_name)
			return
		controller.call("confirm_target", target)
	await ProbePlay.settle(self, controller)

# End Turn, and back once the player's next turn is open.
func _end_turn(controller: Node) -> void:
	var turn: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)
	controller.get("deck").call("discard_hand")

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
