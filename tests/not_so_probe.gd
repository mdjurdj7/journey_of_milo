extends SceneTree

# Headless probe for Not So - 1 Energy, Rare Skill, Spent, TOLL: "Spend 10
# Toll. Undo the last attack; return it." The player's record of enemy
# attacks this fight (Combatant.hits_taken, written by EnemyTurn.land_
# attack()): an attack that cost HP past Block, every hit of it; a fully
# blocked one isn't on it. Not So undoes the newest not yet undone - once
# - restoring its HP (a heal, never past max), closing its share of the
# Grace window still open, and dealing as much to its attacker: not an
# Attack (no Self-Eater), through its Block; a dead attacker takes
# nothing, the HP comes back all the same. Blocked under 10 Toll or with
# nothing to undo. The spend hurries a Sentence. The face reads the live
# undo in a battle hand ("Undo 6 (Scissor); return it."), the rule
# elsewhere or with nothing to undo, and its rules text answers the hover
# with the card's note. Not So+ spends 7.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/not_so_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases drive EnemyTurn and the real cards on bare Combatants; the
# face case reads a CardView; the fight case plays it through
# BattleController on floor 1. Untyped against anything that names the
# RunState autoload.

const CASES := 12
const MAX_HP := 70
const CARD_PATH := "res://cards/data/not_so.tres"
const TEMPERED_PATH := "res://cards/tempered/not_so_tempered.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const SENTENCE_PATH := "res://cards/data/sentence.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ENEMY_HP := 100
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _toll: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_toll = (load(CARD_PATH) as CardData).effects[0].toll_cost

	_check_data()
	_check_record()
	_check_undo_and_send_back()
	_check_multi_hit_whole()
	_check_not_an_attack()
	_check_grace()
	_check_dead_attacker()
	_check_once_each()
	_check_blocked()
	_check_sentence_and_critical()
	await _check_face()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("not_so_probe: PASSED")
		quit(0)
	else:
		print("not_so_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.removal_scope, card.offer, card.card_class], ["Not So", 1, CardData.CardType.SKILL, CardData.CardRarity.RARE, CardData.RemovalScope.SPENT, CardData.OfferScope.REWARDABLE, &"wanderer"], "Not So: 1 Energy, a Rare Skill, Spent, rewardable, the Wanderer's")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[0].toll_cost == 10 and card.effects[1].effect_type == CardEffect.EffectType.UNDO_LAST_ATTACK, "...SPEND_TOLL 10, then UNDO_LAST_ATTACK")
	_expect_eq(card.description, "Spend {toll_cost} Toll.\n{battle}Undo {undo_hp} ({undo_attack}); return it.{/battle}{outside}Undo the last attack; return it.{/outside}\nSpent.", "...its text")
	_expect(card.hover_note.contains("deal that much to its attacker"), "...its hover note spells out 'return it'")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art == null, "...its glyph for art, for now")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Not So+")
	_expect_eq([tempered.card_name, tempered.effects[0].toll_cost, tempered.description], ["Not So+", 7, card.description], "Not So+: spends 7, the same text")
	_completed += 1

# An attack of 9 through 3 Block: on the record, 6, the Scissor, its
# attacker. One the Block takes whole: not on it.
func _check_record() -> void:
	var player: Combatant = _player()
	player.block = 3
	var enemy: Combatant = _sputter(2)
	EnemyTurn.take_turn(enemy, enemy.enemy_data, player)
	_expect_eq(player.hits_taken.size(), 1, "An attack past Block: on the record")
	if player.hits_taken.size() == 1:
		var entry: Dictionary = player.hits_taken[0]
		_expect_eq([entry["hp"], entry["intent"], entry["attacker"] == enemy, entry["undone"]], [6, "Scissor", true, false], "...6 HP, the Scissor, its attacker, not undone")
	var blocked: Combatant = _player()
	blocked.block = 20
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), blocked)
	_expect(blocked.hits_taken.is_empty(), "One the Block takes whole: not on it")
	_completed += 1

# The Scissor took 9 (61 of 70); Not So on 10 Toll: 70 again, 10 spent;
# 9 back at the Sputter through its 4 Block - 5 to its HP.
func _check_undo_and_send_back() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _sputter(2)
	EnemyTurn.take_turn(enemy, enemy.enemy_data, player)
	_expect_eq(player.hp, MAX_HP - 9, "The Scissor takes 9")
	enemy.block = 4
	player.toll = _toll
	_play(load(CARD_PATH), player, [enemy])
	_expect_eq(player.hp, MAX_HP, "Not So: the 9 restored")
	_expect_eq(player.toll, 0, "...10 Toll spent")
	_expect_eq([ENEMY_HP - enemy.hp, enemy.block], [5, 0], "...9 back at the Sputter: its 4 Block, then 5")
	_expect(bool(player.hits_taken[0]["undone"]), "...and the attack marked undone")
	_completed += 1

# Three hits of 4: one attack of 12 - restored whole.
func _check_multi_hit_whole() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	var data: EnemyData = _attacker(4, 3)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hits_taken.size(), 1, "Three hits: one attack on the record")
	_expect_eq(int(player.hits_taken[0]["hp"]), 12, "...of 12")
	player.toll = _toll
	_play(load(CARD_PATH), player, [enemy])
	_expect_eq(player.hp, MAX_HP, "...restored whole")
	_completed += 1

# Under Self-Eater an Attack gets 3 more; the 9 sent back stays 9.
func _check_not_an_attack() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _sputter(2)
	_play(load(SELF_EATER_PATH), player, [enemy])
	EnemyTurn.take_turn(enemy, enemy.enemy_data, player)
	var hp: int = enemy.hp
	player.toll = _toll
	_play(load(CARD_PATH), player, [enemy])
	_expect_eq(hp - enemy.hp, 9, "Under Self-Eater the 9 sent back is 9: no attack bonus")
	_completed += 1

# Grace (half the largest hit): a 9 opens 4, a 6 then 3 - the pool 4.
# Undo the 6: the 9's 4 still stands. Undo the 9: closed. And the other
# way: the 9 undone first leaves the 6's 3. A window gone: nothing to
# close.
func _check_grace() -> void:
	var player: Combatant = _graced()
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), player)
	var c6_player: Combatant = _custom(6)
	EnemyTurn.take_turn(c6_player, c6_player.enemy_data, player)
	_expect_eq(player.grace, 4, "A 9 and a 6: Grace 4")
	player.toll = 2 * _toll
	_play(load(CARD_PATH), player, [Combatant.new(ENEMY_HP)])
	_expect_eq(player.grace, 4, "The 6 undone: the 9's 4 stands")
	_play(load(CARD_PATH), player, [Combatant.new(ENEMY_HP)])
	_expect_eq(player.grace, 0, "...the 9 undone too: Grace closed")
	var other: Combatant = _graced()
	var c6_other: Combatant = _custom(6)
	EnemyTurn.take_turn(c6_other, c6_other.enemy_data, other)
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), other)
	other.toll = _toll
	_play(load(CARD_PATH), other, [Combatant.new(ENEMY_HP)])
	_expect_eq(other.grace, 3, "The 9 undone first: down to the 6's 3")
	var shut: Combatant = _graced()
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), shut)
	shut.grace = 2
	shut.grace_window_hits.clear()
	shut.toll = _toll
	_play(load(CARD_PATH), shut, [Combatant.new(ENEMY_HP)])
	_expect_eq(shut.grace, 2, "Its window gone: Grace untouched")
	_completed += 1

func _check_dead_attacker() -> void:
	var player: Combatant = _player()
	var enemy: Combatant = _sputter(2)
	EnemyTurn.take_turn(enemy, enemy.enemy_data, player)
	enemy.hp = 0
	player.toll = _toll
	_play(load(CARD_PATH), player, [Combatant.new(ENEMY_HP)])
	_expect_eq(player.hp, MAX_HP, "Its attacker dead: the HP still restored")
	_expect_eq(enemy.hp, 0, "...nothing dealt")
	_completed += 1

# Two attacks, two Not Sos: the newest, then the one before; then none.
func _check_once_each() -> void:
	var player: Combatant = _player()
	var first: Combatant = _sputter(2)
	EnemyTurn.take_turn(first, first.enemy_data, player)
	var second: Combatant = _custom(5)
	EnemyTurn.take_turn(second, second.enemy_data, player)
	_expect_eq(player.hp, MAX_HP - 14, "9 and 5 taken")
	player.toll = _toll
	_play(load(CARD_PATH), player, [first, second])
	_expect_eq([player.hp, ENEMY_HP - second.hp], [MAX_HP - 9, 5], "The first Not So undoes the newest, the 5")
	player.toll = _toll
	_play(load(CARD_PATH), player, [first, second])
	_expect_eq([player.hp, ENEMY_HP - first.hp], [MAX_HP, 9], "...the second the one before, the 9 - never the 5 again")
	player.toll = _toll
	_expect(EffectResolver.card_blocked(load(CARD_PATH), player), "...and with both undone, nothing to undo")
	_completed += 1

func _check_blocked() -> void:
	var player: Combatant = _player()
	player.toll = _toll
	_expect(EffectResolver.card_blocked(load(CARD_PATH), player), "No attack on the record: blocked")
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), player)
	_expect(not EffectResolver.card_blocked(load(CARD_PATH), player), "An attack to undo, 10 Toll: playable")
	player.toll = _toll - 1
	_expect(EffectResolver.card_blocked(load(CARD_PATH), player), "...on 9 Toll: blocked")
	_completed += 1

# The spend hurries a Sentence; restoring lifts the player out of Critical.
func _check_sentence_and_critical() -> void:
	var player: Combatant = _player()
	player.hp = 25
	var enemy: Combatant = _sputter(2)
	EnemyTurn.take_turn(enemy, enemy.enemy_data, player)
	_expect(player.is_critical(), "At 16 of 70, Critical")
	_play(load(SENTENCE_PATH), player, [enemy])
	_expect_eq(_label_of(enemy, "sentence"), "Sentence 3", "Sentence on the Sputter: 3")
	player.toll = _toll
	_play(load(CARD_PATH), player, [enemy])
	_expect(not player.is_critical(), "Not So's 9 back: out of Critical (%d)" % player.hp)
	_expect_eq(_label_of(enemy, "sentence"), "Sentence 2", "...and its spend hurries the Sentence")
	_completed += 1

# Outside a fight, the rule; in a battle hand with the Scissor's 6 on the
# record, the live undo; with nothing to undo, the rule again. The rules
# text answers the hover with the card's note.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	var rule: String = "Spend 10 Toll.\nUndo the last attack; return it.\nSpent."
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), rule, "Outside a fight: the rule")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	var player: Combatant = _player()
	view.set_bonus_context(_ctx(player))
	_expect_eq(view.rules_text.get_parsed_text(), rule, "A battle hand, nothing to undo: the rule")
	player.block = 3
	EnemyTurn.take_turn(_sputter(2), load(SPUTTER_PATH), player)
	view.set_bonus_context(_ctx(player))
	_expect_eq(view.rules_text.get_parsed_text(), "Spend 10 Toll.\nUndo 6 (Scissor); return it.\nSpent.", "...the Scissor's 6 on the record: the live undo")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	var centre: Vector2 = view.rules_text.position + view.rules_text.size / 2.0
	_expect_eq(view.keyword_at(centre), "Not So", "Hovering the rules text: the card's note")
	view.free()
	_completed += 1

# The real fight: an attack forced on floor 1's first enemy lands on the
# enemy turn; Not So on 10 Toll restores the newest attack on the record,
# strikes its attacker, and is Spent.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var enemy: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
		var strike := EnemyIntent.new()
		strike.type = EnemyIntent.IntentType.ATTACK
		strike.intent_name = "Probe Hit"
		strike.value = 6
		enemy.interjected_intent = strike
		player.block = 0
		var hp: int = player.hp
		await _end_turn(controller)
		_expect(hp - player.hp > 0 and not player.hits_taken.is_empty(), "The forced attack lands: %d lost, on the record" % (hp - player.hp))
		var entry: Dictionary = player.last_undoable_hit()
		if not entry.is_empty():
			var attacker: Combatant = entry["attacker"]
			attacker.block = 0
			var attacker_hp: int = attacker.hp
			var before: int = player.hp
			player.toll = _toll
			player.energy = 3
			var deck: Object = controller.get("deck")
			deck.call("discard_hand")
			var card: CardData = (load(CARD_PATH) as CardData).duplicate()
			(deck.get("draw_pile") as Array).append(card)
			deck.call("draw", 1)
			await process_frame
			var view: CardView = null
			for candidate: CardView in controller.get("_hand_container").call("_card_views"):
				if candidate.card_data == card:
					view = candidate
			_expect(view != null, "Not So dealt into the hand")
			if view != null:
				controller.call("request_play", view)
				await ProbePlay.settle(self, controller)
			_expect_eq(player.hp - before, int(entry["hp"]), "Not So: the %s's %d back" % [entry["intent"], int(entry["hp"])])
			_expect_eq(attacker_hp - attacker.hp, int(entry["hp"]), "...as much to its attacker")
			_expect((deck.get("exhaust_pile") as Array).has(card), "...and Not So Spent")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	return player

func _graced() -> Combatant:
	var player: Combatant = _player()
	player.has_grace = true
	player.grace_open_fraction = 0.5
	player.grace_cap_mode = CharacterData.GraceCapMode.LARGEST_HIT
	return player

# A Sputter at intent `index` (2: its Scissor, 9).
func _sputter(index: int) -> Combatant:
	var data: EnemyData = load(SPUTTER_PATH)
	var enemy := Combatant.new(ENEMY_HP)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	enemy.current_intent_index = index
	return enemy

func _custom(damage: int) -> Combatant:
	var data: EnemyData = _attacker(damage, 1)
	var enemy := Combatant.new(ENEMY_HP)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _attacker(damage: int, hits: int) -> EnemyData:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.ATTACK
	intent.intent_name = "Probe Hit"
	intent.value = damage
	intent.hits = hits
	var data := EnemyData.new()
	data.max_hp = ENEMY_HP
	data.intents = [intent]
	return data

func _ctx(player: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	return ctx

func _play(card: CardData, player: Combatant, enemies: Array) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	var list: Array[Combatant] = []
	for enemy: Combatant in enemies:
		list.append(enemy)
	ctx.enemies = list
	ctx.target = list[0] if not list.is_empty() else null
	_resolver.resolve_card(card, ctx)

func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
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
	var entry_layer: Node = _field.get_node("BattleLayer")
	while entry_layer.get_child_count() > 0 and bool((entry_layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	var player: Combatant = controller.get("player")
	player.max_hp = 999
	player.hp = 900
	player.energy = 3
	controller.get("deck").call("discard_hand")
	await process_frame
	return controller

func _end_turn(controller: Node) -> void:
	var turn: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)

func _label_of(combatant: Combatant, id: String) -> String:
	for active in combatant.statuses:
		if active.data != null and active.data.id == id:
			return active.label()
	return ""

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
