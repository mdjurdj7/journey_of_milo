extends SceneTree

# Headless probe for Deny - 1 Energy, Uncommon Skill, TOLL, aimed at an
# enemy, not Spent: "Spend 6 Toll. Delay target enemy's next action by a
# turn." Blocked under 6 Toll; not on an enemy already Delayed. On its
# coming turn the enemy does nothing - its move held where it is, the
# marks on it still bound, its turn count (escalation) not moving, its
# statuses still ticking, a pain turn due then spent on it - and on the
# turn after it performs the held move, its loop going on from there.
# The coming turn's preview leaves the move out: it reaches nothing and is
# never lethal; a Delayed packmate answers no Signal. Deny+ spends 4.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/deny_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases drive EnemyTurn on the real enemy data; fight cases load the
# real region scene and fight floor 1's Sputter through RegionField's
# contact handler, playing real cards through BattleController. Untyped
# against anything that names the RunState autoload.

const CASES := 12
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const DENY_PATH := "res://cards/data/deny.tres"
const TEMPERED_PATH := "res://cards/tempered/deny_tempered.tres"
const DELAYED_PATH := "res://battle/rules/statuses/delayed.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const GARNISHED_PATH := "res://battle/rules/statuses/garnished.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Deny.png"
const SOUND_PATH := "res://assets/audio/cards/Deny/Deny.mp3"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const STRIKE := 1
const SCISSOR := 2
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _toll: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_toll = (load(DENY_PATH) as CardData).effects[0].toll_cost

	_check_data()
	_check_gate()
	_check_held_then_acts()
	_check_escalation_paused()
	_check_ticks_run()
	_check_pain_turn()
	_check_marks_held()
	_check_preview()
	_check_gape_held()
	await _check_fight()
	await _check_second_refused()
	await _check_target_dies_first()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("deny_probe: PASSED")
		quit(0)
	else:
		print("deny_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(DENY_PATH)
	var delayed: StatusData = load(DELAYED_PATH)
	_expect_eq(card.card_name, "Deny", "The card loads")
	_expect_eq([card.cost, card.card_type, card.rarity, card.target_type, card.removal_scope, card.card_class], [1, CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON, CardData.TargetType.ENEMY, CardData.RemovalScope.NONE, &"wanderer"], "...1 Energy, a Skill, Uncommon, at an enemy, not Spent, the Wanderer's")
	_expect_eq(card.description, "Spend {toll_cost} Toll.\nDelay target enemy's next action by a turn.", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[1].effect_type == CardEffect.EffectType.APPLY_STATUS_TO_TARGET and card.effects[1].status_data == delayed, "...SPEND_TOLL, then Delayed on the target - no hand card taken")
	_expect_eq(_toll, 6, "...6 Toll")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...its art kept")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its sound")
	_expect(delayed.delays_next_action and not delayed.skips_next_turn, "Delayed holds the next action - no skip")
	_expect_eq([delayed.default_duration_turns, delayed.stack_rule], [StatusData.DURATION_UNTIL_TRIGGERED, StatusData.StackRule.IGNORE], "...until its turn, one at a time")
	_expect(not ResourceLoader.exists(DENIED_PATH), "Denied is gone")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Deny+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.effects[0].toll_cost, tempered.description], ["Deny+", 1, 4, card.description], "Deny+: 1 Energy, spends 4, the same text")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "In the Wanderer pool")
	_completed += 1

func _check_gate() -> void:
	var card: CardData = load(DENY_PATH)
	var player := Combatant.new(70)
	player.toll = _toll - 1
	_expect(EffectResolver.card_blocked(card, player), "%d Toll: blocked" % (_toll - 1))
	player.toll = _toll
	_expect(not EffectResolver.card_blocked(card, player), "%d: playable" % _toll)
	var enemy := _enemy(load(SPUTTER_PATH) as EnemyData)
	_expect(EffectResolver.can_target(card, enemy), "A Sputter can be Delayed")
	_play_deny(player, enemy)
	_expect_eq(player.toll, 0, "Deny spends 6")
	_expect(EnemyTurn.is_delayed(enemy), "...and Delays it")
	_expect(not EffectResolver.can_target(card, enemy), "...not again while it's Delayed")
	_completed += 1

# --- The enemy's turns ---

# Strike queued, Delayed: the coming turn does nothing - no hit, the
# Strike still queued, the turn count unmoved, Delayed gone; the turn
# after, the Strike lands and counts.
func _check_held_then_acts() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = STRIKE
	_delay(enemy)
	var player := Combatant.new(70)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["delayed"]) and not bool(result["attacked"]), "Delayed: the coming turn does nothing")
	_expect_eq(player.hp, 70, "...no damage")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Strike", "...the Strike still queued")
	_expect_eq(enemy.turns_taken, 0, "...the turn count unmoved")
	_expect(not EnemyTurn.is_delayed(enemy), "...and Delayed gone")
	result = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["attacked"]) and player.hp < 70, "The turn after: the held Strike lands")
	_expect_eq(enemy.turns_taken, 1, "...its turn counted, the loop going on from there")
	_completed += 1

# The Wardling's escalation waits with it: the stage after the do-nothing
# turn is the stage before it.
func _check_escalation_paused() -> void:
	var data := load(WARDLING_PATH) as EnemyData
	var enemy := _enemy(data)
	EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	var stage: int = EnemyTurn.escalation_stage(enemy, data)
	var taken: int = enemy.turns_taken
	_delay(enemy)
	EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	_expect_eq([enemy.turns_taken, EnemyTurn.escalation_stage(enemy, data)], [taken, stage], "A Delayed turn moves neither the turn count nor the escalation stage")
	_completed += 1

# Statuses still tick on the do-nothing turn: a Sentence at its last turn
# goes off.
func _check_ticks_run() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	Status.apply_to(enemy.statuses, load(SENTENCE_STATUS_PATH))
	Status.find_in(enemy.statuses, load(SENTENCE_STATUS_PATH)).turns_remaining = 1
	_delay(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect_eq(int(result["countdown_damage"]), (load(SENTENCE_STATUS_PATH) as StatusData).countdown_damage, "A Sentence still goes off on a Delayed turn")
	_completed += 1

# A pain turn due on the do-nothing turn is spent on it; the turn after
# performs the held move.
func _check_pain_turn() -> void:
	var data := load(WARDLING_PATH) as EnemyData
	var enemy := _enemy(data)
	var held: String = EnemyTurn.current_intent(enemy, data).intent_name
	enemy.pain_turn_pending = true
	enemy.pain_turn_used = true
	_delay(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	_expect(bool(result["pain_turn"]) and bool(result["delayed"]), "A pain turn due falls on the Delayed turn")
	_expect(not enemy.pain_turn_pending, "...and is spent")
	var next: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	_expect(not bool(next["pain_turn"]) and not bool(next["delayed"]), "The turn after acts")
	_expect_eq(str(next["intent"]), held, "...its held %s" % held)
	_completed += 1

# Braced on the queued Strike, then Delayed: the mark stays bound through
# the do-nothing turn - and a Garnish can still go on it - then the Strike
# lands Braced and the mark is spent.
func _check_marks_held() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = STRIKE
	var strike: EnemyIntent = EnemyTurn.current_intent(enemy, data)
	var braced := Status.new(load(BRACED_PATH) as StatusData)
	braced.bound_intent = strike
	enemy.statuses.append(braced)
	_delay(enemy)
	_expect_eq(EnemyTurn.mark_refusal(enemy, data, load(GARNISHED_PATH) as StatusData), EnemyTurn.MarkRefusal.NONE, "A Delayed Strike can still be Garnished - it lands later")
	_expect_eq(EnemyTurn.mark_loss(braced, enemy, data), "", "...and Braced holds")
	var player := Combatant.new(70)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(enemy.statuses.has(braced) and braced.bound_intent == strike, "Through the do-nothing turn, Braced stays on the Strike")
	_expect((result.get("marks", []) as Array).is_empty(), "...no mark settled")
	result = EnemyTurn.take_turn(enemy, data, player)
	_expect(70 - player.hp < strike.value, "The Strike lands Braced: %d, not %d" % [70 - player.hp, strike.value])
	var marks: Array = result.get("marks", [])
	_expect(marks.size() == 1 and str(marks[0]["outcome"]) == "spent", "...and Braced is spent (%s)" % [marks])
	_completed += 1

# The coming turn's preview leaves a Delayed move out: its number kept,
# reaching nothing, never lethal. A Delayed packmate answers no Signal.
func _check_preview() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = SCISSOR
	var player := Combatant.new(5)
	_expect(bool(EnemyTurn.preview_intent(enemy, data, player)["lethal"]), "Scissor 9 into 5 HP reads lethal")
	_delay(enemy)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview.get("delayed", false)) and not bool(preview.get("denied", false)), "Delayed: the preview says so")
	_expect_eq(int(preview["per_hit"]), 9, "...keeps its number")
	_expect_eq(int(preview["damage_to_hp"]), 0, "...reaches nothing this turn")
	_expect(not bool(preview["lethal"]), "...and isn't lethal")
	_expect(EnemyTurn.signal_answer_intent(enemy, data) == null, "A Delayed packmate answers no Signal")
	_completed += 1

# A Delayed Gape, its threshold met: not interrupted on the do-nothing
# turn, and still the Gape after it.
func _check_gape_held() -> void:
	var data := load(GREYSHELF_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 1
	var gape: String = EnemyTurn.current_intent(enemy, data).intent_name
	enemy.damage_taken_this_turn = 99
	_delay(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect(not bool(result["interrupted"]), "A Delayed %s isn't interrupted on its do-nothing turn" % gape)
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, gape, "...and is still queued after it")
	_completed += 1

# --- Fights ---

# Deny on 6 Toll at the Sputter's Scissor: 0 Toll, 1 Energy spent, Deny to
# the discard, the rest of the hand untouched; the intent dimmed, not
# struck, its hover saying delayed. The enemy turn: nothing lands, the
# turn holds its beat, the Scissor still queued; the turn after, it lands.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var combatant: Combatant = _enemy_combatant(controller)
		combatant.current_intent_index = SCISSOR
		controller.call("_emit_intent_previews")
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		_expect(bool(controller.call("is_awaiting_target")), "Deny asks for its target")
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect_eq([player.toll, player.energy], [0, 2], "Played: 6 Toll and 1 Energy spent")
		_expect((deck.get("discard_pile") as Array).has(deny) and not (deck.get("exhaust_pile") as Array).has(deny), "...Deny to the discard, not Spent")
		_expect((deck.get("hand") as Array).has(slash), "...no hand card taken")
		var intent: Node = (controller.get_parent().get("_enemy_intents") as Dictionary).get(_field_enemy(controller))
		_expect(intent != null and bool(intent.get("_delayed")) and not bool(intent.get("_denied")), "The intent reads Delayed - dimmed, not struck")
		var label: Label = intent.get("_label") if intent != null else null
		_expect(label != null and label.text == "9" and label.modulate.a < 1.0, "...keeping its 9, dimmed (%s)" % (label.text if label != null else "?"))
		var hover: String = str(controller.get_parent().call("_intent_hover_text", _field_enemy(controller)))
		_expect(hover.contains("delayed"), "...its hover saying delayed (%s)" % hover)
		var hp: int = player.hp
		var taken: int = combatant.turns_taken
		var started: int = ProbePlay.game_msec()
		await _end_turn(controller)
		_expect_eq(player.hp, hp, "The Delayed turn deals nothing")
		_expect_eq(combatant.turns_taken, taken, "...its turn count unmoved")
		_expect(not EnemyTurn.is_delayed(combatant), "...Delayed gone")
		_expect_eq(EnemyTurn.current_intent(combatant, _field_enemy(controller).get("enemy_data")).intent_name, "Scissor", "...the Scissor still queued")
		_expect(ProbePlay.game_msec() - started >= int(float(controller.get("denied_beat_sec")) * 1000.0), "...holding its beat")
		await _end_turn(controller)
		_expect(player.hp < hp, "The turn after: the Scissor lands (%d to %d)" % [hp, player.hp])
	await _teardown()
	_completed += 1

# A second Deny can't land on the Delayed Sputter: it fades with no other
# enemy to take it.
func _check_second_refused() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 2 * _toll
		var first: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, first))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var second: CardData = await _deal(controller, DENY_PATH)
		_expect(not bool(controller.call("_can_target", second, _enemy_combatant(controller))), "A second Deny can't target the Delayed Sputter")
		_expect(not bool(controller.call("_is_playable", second)), "...and with no one else, it isn't playable")
	await _teardown()
	_completed += 1

# The target dies first: Delayed goes with it.
func _check_target_dies_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = _toll
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var combatant: Combatant = _enemy_combatant(controller)
		combatant.hp = 0
		controller.call("_check_battle_end")
		await ProbePlay.wait_until(self, func() -> bool: return _overlay() == null or not bool(controller.call("is_awaiting_target")), 3.0)
		_expect_eq(combatant.hp, 0, "The Delayed Sputter dies before its turn")
		_expect(_overlay() == null or not bool(controller.call("is_awaiting_target")), "...the fight ends with nothing waiting on it")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _enemy(data: EnemyData) -> Combatant:
	var combatant := Combatant.new(data.max_hp)
	combatant.enemy_data = data
	EnemyTurn.pick_initial_intent(combatant, data)
	return combatant

func _delay(combatant: Combatant) -> void:
	Status.apply_to(combatant.statuses, load(DELAYED_PATH))

func _play_deny(player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	var enemies: Array[Combatant] = [enemy]
	ctx.enemies = enemies
	EffectResolver.new().resolve_card(load(DENY_PATH), ctx)

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
	# The fight's opening hold (BattleController.lock_entry_input()).
	var entry_layer: Node = _field.get_node("BattleLayer")
	while entry_layer.get_child_count() > 0 and bool((entry_layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	var overlay: Node = _overlay()
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	var player: Combatant = controller.get("player")
	player.max_hp = 999
	player.hp = 999
	player.energy = 3
	await process_frame
	return controller

func _overlay() -> Node:
	if _field == null or not is_instance_valid(_field):
		return null
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand - the first
# call of a case discards the opening hand.
func _deal(controller: Node, path: String) -> CardData:
	var deck: Object = controller.get("deck")
	if not bool(controller.get_meta("probe_dealt", false)):
		controller.set_meta("probe_dealt", true)
		deck.call("discard_hand")
		await process_frame
	var card: CardData = (load(path) as CardData).duplicate()
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _enemy_combatant(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

func _settle(controller: Node) -> void:
	await ProbePlay.settle(self, controller)

# End Turn, and back once the player's next turn is open.
func _end_turn(controller: Node) -> void:
	var turn: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
