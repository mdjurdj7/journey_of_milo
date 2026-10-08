extends SceneTree

# Headless probe for Deny - CONSUME and the Denied status behind it:
# playing it takes the most expensive other card in the hand by printed
# cost (CardData.cost) to the Spent pile - a tie is the player's pick,
# exactly one, through the hand choice - and the target enemy's next move
# is skipped: lost, not delayed, the pattern moving on and the turn still
# counted. Denied doesn't stack, so an enemy holding it can't be targeted
# by another Deny. The intent keeps its number, struck through.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/deny_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases drive EnemyTurn on the real enemy data; fight cases load the
# real region scene and fight floor 1's Sputter through RegionField's
# contact handler, as collateral_probe does, playing real cards through
# BattleController.request_play() / toggle_choice() / confirm_choice() /
# confirm_target() / end_turn(). Untyped against anything that names the
# RunState autoload.

const CASES := 21
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const DENY_PATH := "res://cards/data/deny.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const RANSOM_PATH := "res://cards/data/ransom.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Deny.png"
const SOUND_PATH := "res://assets/audio/cards/Deny/Deny.mp3"
const NIPPER_PATH := "res://battle/rules/enemies/nipper.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const ENEMY_HP := 999
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

	_check_data()
	_check_candidates_printed_cost()
	_check_skip_attack()
	_check_skip_defend()
	_check_skip_forage_advances()
	_check_escalation_counts()
	_check_sentence_still_ticks()
	_check_pain_turn_spends_it()
	_check_charge_not_interrupted()
	_check_preview()
	_check_no_stack()
	await _check_auto_consume()
	await _check_tie_choice()
	await _check_tie_cancel()
	await _check_alone()
	await _check_discounts_dont_reorder()
	await _check_second_deny_refused()
	await _check_faded_without_target()
	await _check_intent_struck()
	await _check_turn_skipped_in_fight()
	await _check_target_dies_first()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("deny_probe: PASSED")
		quit(0)
	else:
		print("deny_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var deny := load(DENY_PATH) as CardData
	_expect_eq(deny.card_name, "Deny", "The card is named Deny")
	_expect_eq(deny.cost, 2, "...costs 2")
	_expect_eq(deny.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(deny.rarity, CardData.CardRarity.UNCOMMON, "...is Uncommon")
	_expect_eq(deny.target_type, CardData.TargetType.ENEMY, "...targets an enemy")
	_expect_eq(deny.removal_scope, CardData.RemovalScope.SPENT, "...is Spent")
	_expect_eq(deny.description, "Consume your costliest card.\nTarget enemy skips its next move.\nSpent.", "...and says so")
	_expect_eq(deny.effects[0].effect_type, CardEffect.EffectType.CONSUME, "...CONSUME first")
	_expect_eq(deny.effects[1].effect_type, CardEffect.EffectType.APPLY_STATUS_TO_TARGET, "...then Denied on the target")
	_expect(deny.effects[1].status_data == load(DENIED_PATH), "...the Denied status")
	_expect(deny.art != null and deny.art.resource_path == ART_PATH, "...its art")
	_expect_eq(deny.play_sound_path, SOUND_PATH, "...and its play sound")
	var denied := load(DENIED_PATH) as StatusData
	_expect(denied.skips_next_turn, "Denied skips its holder's next turn")
	_expect_eq(denied.default_duration_turns, StatusData.DURATION_UNTIL_TRIGGERED, "...until that turn")
	_expect_eq(Status.new(denied).describe(), "It skips its next move.", "...and says so")
	var in_pool: bool = false
	for card: CardData in (load(POOL_PATH) as RewardPool).entries:
		if card == deny:
			in_pool = true
	_expect(in_pool, "Deny is in the Wanderer reward pool")
	_completed += 1

# Most expensive by printed cost; a tie is every card at it.
func _check_candidates_printed_cost() -> void:
	var slash := load(SLASH_PATH) as CardData
	var reckoning := load(RECKONING_PATH) as CardData
	var arc := load(BLOOD_ARC_PATH) as CardData
	_expect_eq(ConsumeEffect.candidates([slash, reckoning] as Array[CardData]), [1] as Array[int], "Slash 1, Reckoning 2: Reckoning")
	_expect_eq(ConsumeEffect.candidates([reckoning, slash, arc] as Array[CardData]), [0, 2] as Array[int], "Reckoning 2, Blood Arc 2: a tie")
	_expect_eq(ConsumeEffect.candidates([] as Array[CardData]), [] as Array[int], "No other card: nothing")
	_completed += 1

func _check_skip_attack() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 1
	_deny(enemy)
	var player := Combatant.new(70)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["denied"]) and not bool(result["attacked"]), "Denied Strike: no attack")
	_expect_eq(player.hp, 70, "...no damage")
	_expect_eq(enemy.turns_taken, 1, "...the turn still counts")
	_expect(not EnemyTurn.is_denied(enemy), "...and Denied is spent")
	_completed += 1

func _check_skip_defend() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 0
	_deny(enemy)
	EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect_eq(enemy.block, 0, "Denied Block: no block gained")
	_completed += 1

# Nip, Nip, Forage: a Denied Forage heals nothing and the loop goes on to
# Nip, as if it had foraged.
func _check_skip_forage_advances() -> void:
	var data := load(NIPPER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 2
	_deny(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect_eq(int(result["heal_allies"]), 0, "Denied Forage: no heal")
	_expect_eq(enemy.current_intent_index, 0, "...the loop moves on to Nip")
	_completed += 1

# The Wardling's escalation keeps its clock through a skipped turn.
func _check_escalation_counts() -> void:
	var data := load(WARDLING_PATH) as EnemyData
	var denied := _enemy(data)
	var plain := _enemy(data)
	for turn in 2:
		if turn == 0:
			_deny(denied)
		EnemyTurn.take_turn(denied, data, Combatant.new(999))
		EnemyTurn.take_turn(plain, data, Combatant.new(999))
	_expect_eq(EnemyTurn.escalation_stage(denied, data), EnemyTurn.escalation_stage(plain, data), "A skipped turn counts toward escalation (stage %d)" % EnemyTurn.escalation_stage(plain, data))
	_completed += 1

# Statuses still tick on a skipped turn: a Sentence at its last turn goes off.
func _check_sentence_still_ticks() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	Status.apply_to(enemy.statuses, load(SENTENCE_STATUS_PATH))
	Status.find_in(enemy.statuses, load(SENTENCE_STATUS_PATH)).turns_remaining = 1
	_deny(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect_eq(int(result["countdown_damage"]), 40, "A Sentence still goes off on a Denied turn")
	_completed += 1

# A pain turn and Denied on the same turn: both spent by it; the next
# turn acts.
func _check_pain_turn_spends_it() -> void:
	var data := load(WARDLING_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.pain_turn_pending = true
	enemy.pain_turn_used = true
	_deny(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	_expect(bool(result["pain_turn"]) and bool(result["denied"]), "Pain turn and Denied land on one turn")
	_expect(not EnemyTurn.is_denied(enemy), "...Denied doesn't carry over")
	var next: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(999))
	_expect(not bool(next["denied"]) and not bool(next["pain_turn"]), "...and the turn after acts")
	_completed += 1

# A Denied charge is lost, not interrupted: no burrow is queued.
func _check_charge_not_interrupted() -> void:
	var data := load(SILTJAW_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 1
	enemy.damage_taken_this_turn = 99
	_deny(enemy)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, Combatant.new(70))
	_expect(not bool(result["interrupted"]), "A Denied charge isn't interrupted")
	_expect(enemy.interjected_intent == null, "...so no burrow is queued")
	_completed += 1

func _check_preview() -> void:
	var data := load(SPUTTER_PATH) as EnemyData
	var enemy := _enemy(data)
	enemy.current_intent_index = 2
	var player := Combatant.new(5)
	_expect(bool(EnemyTurn.preview_intent(enemy, data, player)["lethal"]), "Scissor 9 into 5 HP reads lethal")
	_deny(enemy)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview.get("denied", false)), "Denied: the preview says so")
	_expect_eq(int(preview["per_hit"]), 9, "...keeps its number")
	_expect_eq(int(preview["damage_to_hp"]), 0, "...reaches nothing")
	_expect(not bool(preview["lethal"]), "...and is never lethal")
	_completed += 1

func _check_no_stack() -> void:
	var enemy := _enemy(load(SPUTTER_PATH) as EnemyData)
	_deny(enemy)
	_deny(enemy)
	var count: int = 0
	for active in enemy.statuses:
		if active.data != null and active.data.skips_next_turn:
			count += 1
	_expect_eq(count, 1, "Denied doesn't stack")
	_completed += 1

# --- Fights ---

# One most expensive card: taken outright, marked while the target is
# chosen, then Spent; the enemy is Denied; Deny is Spent too.
func _check_auto_consume() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		_expect(not bool(controller.call("is_choosing")), "One most expensive card: no choice")
		_expect(bool(controller.call("is_awaiting_target")), "...straight to the target")
		_expect(_view(controller, reckoning).is_marked(), "...Reckoning marked as the one it takes")
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(reckoning), "Reckoning is Spent")
		_expect((deck.get("hand") as Array).has(slash), "...Slash stays")
		_expect((deck.get("exhaust_pile") as Array).has(deny), "...and Deny is Spent")
		_expect(EnemyTurn.is_denied(_enemy_combatant(controller)), "The Sputter is Denied")
		_expect_eq((controller.get("player") as Combatant).energy, 1, "...for 2 Energy")
	await _teardown()
	_completed += 1

# A tie: the choice opens over the tied cards only, exactly one must be
# chosen, then the target; the chosen one is Spent.
func _check_tie_choice() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var arc: CardData = await _deal(controller, BLOOD_ARC_PATH)
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		_expect(bool(controller.call("is_choosing")), "Reckoning and Blood Arc tie at 2: the choice opens")
		_expect_eq(int(controller.get("_choice_cap")), 1, "...for exactly one")
		controller.call("toggle_choice", _view(controller, slash))
		_expect(not _view(controller, slash).is_marked(), "...Slash, not tied, can't be chosen")
		controller.call("confirm_choice")
		_expect(bool(controller.call("is_choosing")), "...nor can it confirm with none")
		controller.call("toggle_choice", _view(controller, arc))
		controller.call("confirm_choice")
		_expect(not bool(controller.call("is_choosing")) and bool(controller.call("is_awaiting_target")), "Blood Arc chosen: on to the target")
		_expect(_view(controller, arc).is_marked(), "...Blood Arc stays marked")
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var spent: Array = deck.get("exhaust_pile")
		_expect(spent.has(arc) and not spent.has(reckoning), "Blood Arc is Spent, Reckoning stays")
	await _teardown()
	_completed += 1

# Cancelled at the choice or at the target: nothing consumed or spent.
func _check_tie_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		await _deal(controller, BLOOD_ARC_PATH)
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		controller.call("cancel_choice")
		await create_timer(0.8).timeout
		_expect(not bool(controller.call("is_choosing")), "Cancelled at the choice: it closes")
		controller.call("request_play", _view(controller, deny))
		controller.call("toggle_choice", _view(controller, reckoning))
		controller.call("confirm_choice")
		controller.call("cancel_target")
		await create_timer(0.8).timeout
		_expect(not bool(controller.call("is_awaiting_target")), "Cancelled at the target: it disarms")
		_expect(not _view(controller, reckoning).is_marked(), "...the pick unmarked")
		_expect_eq((deck.get("exhaust_pile") as Array).size(), 0, "...nothing Spent")
		_expect_eq((deck.get("hand") as Array).size(), 3, "...the hand whole")
		_expect_eq((controller.get("player") as Combatant).energy, 3, "...no Energy spent")
		_expect(not EnemyTurn.is_denied(_enemy_combatant(controller)), "...and no one Denied")
	await _teardown()
	_completed += 1

# Deny alone: nothing to consume, the skip still lands.
func _check_alone() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		_expect(bool(controller.call("is_awaiting_target")), "Deny alone still plays")
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect_eq((deck.get("exhaust_pile") as Array), [deny], "...consuming nothing but itself")
		_expect(EnemyTurn.is_denied(_enemy_combatant(controller)), "...and the Sputter is Denied")
	await _teardown()
	_completed += 1

# Leverage and Collateral change faces, not which card is most expensive.
func _check_discounts_dont_reorder() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
		Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var deny: CardData = await _deal(controller, DENY_PATH)
		_expect_eq([player.energy_cost(slash), player.energy_cost(reckoning)], [0, 0], "Under Leverage both read 0")
		controller.call("request_play", _view(controller, deny))
		_expect(not bool(controller.call("is_choosing")), "...no tie on printed cost")
		_expect(_view(controller, reckoning).is_marked(), "...Reckoning, printed 2, is the one")
		controller.call("cancel_target")
		await create_timer(0.8).timeout
	await _teardown()
	_completed += 1

# Denied doesn't stack: a second Deny has no target in the Denied Sputter.
func _check_second_deny_refused() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var first: CardData = await _deal(controller, DENY_PATH)
		var second: CardData = await _deal(controller, DENY_PATH)
		(controller.get("player") as Combatant).energy = 4
		controller.call("request_play", _view(controller, first))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect(EnemyTurn.is_denied(_enemy_combatant(controller)), "The first Deny lands")
		var hand_before: int = (deck.get("hand") as Array).size()
		if _view(controller, second) != null:
			controller.call("request_play", _view(controller, second))
		_expect(not bool(controller.call("is_awaiting_target")), "A second Deny can't target the Denied Sputter")
		_expect_eq((deck.get("hand") as Array).size(), hand_before, "...and stays in hand")
		var combatant: Combatant = _enemy_combatant(controller)
		_expect(not bool(controller.call("_can_target", load(DENY_PATH), combatant)), "...the target test refuses it")
	await _teardown()
	_completed += 1

# No enemy it may land on - the only one already Denied - and Deny's face
# fades like any unplayable card; the turn after, it's back.
func _check_faded_without_target() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		# Ransom, at 3, is what the first Deny takes - not the second Deny.
		await _deal(controller, RANSOM_PATH)
		var first: CardData = await _deal(controller, DENY_PATH)
		var second: CardData = await _deal(controller, DENY_PATH)
		(controller.get("player") as Combatant).energy = 4
		_expect(_view(controller, second).modulate.a >= 1.0, "With a target to land on, Deny reads playable")
		controller.call("request_play", _view(controller, first))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var view: CardView = _view(controller, second)
		_expect(view != null and view.modulate.a < 1.0, "Its only enemy Denied: a second Deny fades (alpha %.2f)" % (view.modulate.a if view != null else -1.0))
		_expect(view != null and is_equal_approx(view.modulate.a, view.unplayable_alpha), "...to the unplayable alpha")
	await _teardown()
	_completed += 1

# The intent keeps its number, dimmed and struck through, from the play.
func _check_intent_struck() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var intent: Node = (controller.get_parent().get("_enemy_intents") as Dictionary).get(_field_enemy(controller))
		_expect(intent != null and bool(intent.get("_denied")), "The intent reads Denied at once")
		var label: Label = intent.get("_label") if intent != null else null
		_expect(label != null and not label.text.is_empty(), "...keeping its number (%s)" % (label.text if label != null else "?"))
		_expect(label != null and label.modulate.a < 1.0, "...dimmed to the hairline ink")
	await _teardown()
	_completed += 1

# The enemy turn: no move lands, Denied leaves the readout, the turn holds
# its beat, and the next intent comes up.
func _check_turn_skipped_in_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var combatant: Combatant = _enemy_combatant(controller)
		combatant.current_intent_index = 2
		controller.call("_emit_intent_previews")
		var player: Combatant = controller.get("player")
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var hp_before: int = player.hp
		var block_before: int = combatant.block
		var started: int = Time.get_ticks_msec()
		await _end_turn(controller)
		_expect_eq(player.hp, hp_before, "The skipped turn deals nothing")
		_expect_eq(combatant.block, block_before, "...gains nothing")
		_expect(not EnemyTurn.is_denied(combatant), "...Denied is gone")
		_expect_eq(combatant.turns_taken, 1, "...and the turn counted")
		_expect(Time.get_ticks_msec() - started >= int(float(controller.get("denied_beat_sec")) * 1000.0), "...holding its beat")
	await _teardown()
	_completed += 1

# The target dies first: Denied goes with it, nothing left over.
func _check_target_dies_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deny: CardData = await _deal(controller, DENY_PATH)
		controller.call("request_play", _view(controller, deny))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		var combatant: Combatant = _enemy_combatant(controller)
		combatant.hp = 0
		controller.call("_check_battle_end")
		await create_timer(0.3).timeout
		_expect_eq(combatant.hp, 0, "The Denied Sputter dies before its turn")
		_expect(_overlay() == null or not bool(controller.call("is_awaiting_target")), "...the fight ends with nothing waiting on it")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _enemy(data: EnemyData) -> Combatant:
	var combatant := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(combatant, data)
	return combatant

func _deny(combatant: Combatant) -> void:
	Status.apply_to(combatant.statuses, load(DENIED_PATH))

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

# Until the play has resolved - the played card reaches the Spent pile at
# its fade's end (Deck.settle_play()), before then - and a margin after.
func _settle(controller: Node) -> void:
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.8).timeout

func _end_turn(controller: Node) -> void:
	controller.call("end_turn")
	for i in 3000:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
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
