extends SceneTree

# Headless probe for Thick Skin - 2 Energy, Common Skill, TOLL: gain 6
# Block, and until the player's next turn, enemy damage that gets past
# Block takes their Toll first, 1 for 1, and only the rest reaches HP
# (StatusData.toll_pays_damage, DamagePipeline.resolve()). Thick Skin+
# gains 9. Their own HP loss - self-damage, a stance's price, a tick -
# never touches Toll. Toll paid this way is spent (Reckoning counts it,
# Gnaw's "spent this turn" sees it) but hurries no Sentence. HP Toll paid
# opens no Grace; a lethal guard only fires on what's left past Toll; the
# intent preview's HP and lethal flag read the Toll too.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/thick_skin_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver and land the real
# enemies' attacks (the Sputter's Scissor, the Underfoot's Sting, the
# Adder's strike back) on bare Combatants, every number worked out of the
# data. The fight case plays Thick Skin through BattleController on the
# real region scene and lets the enemy turn run: the Toll it pays, put
# down to status:thick_skin in the run log, and the status gone when the
# next turn starts. Untyped against anything that names the RunState
# autoload.

const CASES := 12
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/thick_skin.tres"
const TEMPERED_PATH := "res://cards/tempered/thick_skin_tempered.tres"
const STATUS_PATH := "res://battle/rules/statuses/thick_skin.tres"
const SMALL_PRICE_PATH := "res://cards/data/small_price.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const GNAW_PATH := "res://cards/data/gnaw.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const GARNISH_PATH := "res://cards/data/garnish.tres"
const WREST_PATH := "res://cards/data/wrest.tres"
const NO_FURTHER_ARMED_PATH := "res://battle/rules/statuses/no_further_armed.tres"
const REFUSE_PATH := "res://battle/rules/statuses/refuse_the_end.tres"
const SENTENCE_PATH := "res://battle/rules/statuses/sentence.tres"
const COILED_PATH := "res://battle/rules/statuses/coiled.tres"
const VENOM_PATH := "res://battle/rules/statuses/venom.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const UNDERFOOT_PATH := "res://battle/rules/enemies/underfoot.tres"
const ADDER_PATH := "res://battle/rules/enemies/adder.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const MAX_HP := 80
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	await _check_face()
	_check_pays_first()
	_check_rest_to_hp()
	_check_no_toll()
	_check_own_loss()
	_check_strike_back_and_spent()
	_check_no_sentence()
	_check_marks_first()
	_check_lethal_guard()
	_check_preview()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("thick_skin_probe: PASSED")
		quit(0)
	else:
		print("thick_skin_probe: %d FAILED" % _failures)
		quit(1)

# --- Data and face ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	_expect_eq([card.card_name, card.cost, card.card_type, card.rarity, card.target_type, card.card_class, card.offer], ["Thick Skin", 2, CardData.CardType.SKILL, CardData.CardRarity.COMMON, CardData.TargetType.SELF, &"wanderer", CardData.OfferScope.REWARDABLE], "Thick Skin: 2 Energy, a Common Skill, no target, the Wanderer's")
	_expect(card.art != null and card.art.resource_path == "res://cards/art/Wanderer/Thick Skin.png", "...with its art")
	_expect_eq(card.description, "Gain {block} block.\nUntil your next turn, damage past Block costs Toll first.", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.BLOCK and card.effects[0].value == 6, "...6 Block")
	_expect(card.effects.size() == 2 and card.effects[1].effect_type == CardEffect.EffectType.APPLY_STATUS and card.effects[1].status_data == status, "...then Thick Skin")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect_eq([status.toll_pays_damage, status.default_duration_turns, status.ignores_strike_backs], [true, 1, false], "The status: Toll pays, until the next turn, strike backs too")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Thick Skin+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.rarity, tempered.description], ["Thick Skin+", 2, CardData.CardRarity.COMMON, card.description], "Thick Skin+: the same card")
	_expect(tempered.effects.size() == 2 and tempered.effects[0].value == 9 and tempered.effects[1].status_data == status, "...9 Block")
	for pool_path: String in [WANDERER_POOL_PATH, COLLECTOR_POOL_PATH]:
		_expect((load(pool_path) as RewardPool).entries.has(card), "In %s" % pool_path)
	_completed += 1

func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 6 block.\nUntil your next turn, damage past Block costs Toll first.", "Thick Skin's face")
	_expect_eq(view.type_label.text, "TOLL", "...its footer TOLL")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 9 block.\nUntil your next turn, damage past Block costs Toll first.", "Thick Skin+'s face")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	view.free()
	_completed += 1

# --- Rules ---

# Played on 20 Toll: 6 Block; the Scissor's hit past it is paid in Toll,
# no HP lost, no Grace opened, counted as spent.
func _check_pays_first() -> void:
	var data: EnemyData = load(SPUTTER_PATH)
	var hit: int = _queue(data, "Scissor").value
	var player: Combatant = _player(60, 20)
	_play(load(CARD_PATH), player)
	_expect_eq(player.block, 6, "Thick Skin: 6 Block")
	var past: int = maxi(hit - 6, 0)
	var result: Dictionary = EnemyTurn.take_turn(_enemy(data, "Scissor"), data, player)
	_expect_eq([player.hp, player.toll], [60, 20 - past], "The Scissor %d past 6 Block: %d Toll paid, no HP" % [hit, past])
	_expect_eq(int(result["tolled"]), past, "...the turn's \"tolled\" %d" % past)
	_expect_eq([player.grace, int(result["grace_opened"])], [0, 0], "...no Grace")
	_expect_eq(player.toll_spent_this_fight, past, "...spent: %d this fight" % past)
	_completed += 1

# More than the Toll: it all goes, the rest reaches HP and opens Grace on
# that rest alone.
func _check_rest_to_hp() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var hit: int = _queue(data, "Sting").value
	var player: Combatant = _player(60, 3)
	_apply_skin(player)
	EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect_eq([player.toll, player.hp], [0, 60 - (hit - 3)], "The Sting %d on 3 Toll: the 3 paid, %d to HP" % [hit, hit - 3])
	_expect(player.grace > 0, "...Grace opened on what reached HP (%d)" % player.grace)
	_completed += 1

# No Toll: as it always was.
func _check_no_toll() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var hit: int = _queue(data, "Sting").value
	var player: Combatant = _player(60, 0)
	_apply_skin(player)
	EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect_eq(player.hp, 60 - hit, "On 0 Toll the Sting takes its %d from HP" % hit)
	_completed += 1

# Their own HP loss never touches Toll: Small Price's 1, Self-Eater's 2 on
# an Attack, a Venom tick - Toll only rises (a self-loss makes Toll).
func _check_own_loss() -> void:
	var player: Combatant = _player(60, 10)
	_apply_skin(player)
	_play(load(SMALL_PRICE_PATH), player)
	_expect_eq([player.hp, player.toll], [59, 11], "Small Price under Thick Skin: 1 HP, Toll up, not down")
	_play(load(SELF_EATER_PATH), player)
	_play_on(load(SLASH_PATH), player, Combatant.new(500))
	_expect_eq(player.hp, 57, "...Self-Eater's 2 on a Slash: from HP")
	_expect(player.toll >= 11, "...Toll untouched by it (%d)" % player.toll)
	var lost: int = DamagePipeline.apply_bypass(3, player)
	_expect_eq([lost, player.hp], [3, 54], "...a tick (apply_bypass): from HP")
	_completed += 1

# A strike back in the player's own turn (the Adder Coiled) is paid in
# Toll too - and Gnaw sees Toll spent this turn; Reckoning counts it.
func _check_strike_back_and_spent() -> void:
	var data: EnemyData = load(ADDER_PATH)
	var enemy: Combatant = _enemy(data, "Bite")
	Status.apply_to(enemy.statuses, load(COILED_PATH))
	var counter: int = (load(COILED_PATH) as StatusData).default_magnitude
	var player: Combatant = _player(60, 10)
	_apply_skin(player)
	EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq([player.hp, player.toll], [60, 10 - counter], "The Coiled strike back %d: paid in Toll" % counter)
	var gnaw: CardData = load(GNAW_PATH)
	_expect(EffectResolver.condition_met(gnaw.effects[0], _ctx(player, null)), "...Gnaw sees Toll spent this turn")
	var target := Combatant.new(500)
	_play_on(load(RECKONING_PATH), player, target)
	_expect_eq(500 - target.hp, counter, "...Reckoning deals the %d spent" % counter)
	_completed += 1

# Toll paid this way hurries no Sentence: one on another enemy keeps its
# count through an attack Thick Skin paid for.
func _check_no_sentence() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var watcher: Combatant = _enemy(load(SPUTTER_PATH), "Scissor")
	var sentence: StatusData = load(SENTENCE_PATH)
	Status.apply_to(watcher.statuses, sentence)
	var before: int = Status.find_in(watcher.statuses, sentence).turns_remaining
	var player: Combatant = _player(60, 30)
	_apply_skin(player)
	var result: Dictionary = EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect(int(result["tolled"]) > 0, "The Sting paid in Toll (%d)" % int(result["tolled"]))
	_expect_eq(Status.find_in(watcher.statuses, sentence).turns_remaining, before, "...and a Sentence elsewhere not hurried (%d)" % before)
	_completed += 1

# Brace, Garnish and Wrest cut the attack before Block, so less reaches
# Toll; No Further's armed takes it all and Toll is untouched.
func _check_marks_first() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var hit: int = _queue(data, "Sting").value
	var braced: int = maxi(hit + roundi(hit * (load("res://battle/rules/statuses/braced.tres") as StatusData).default_magnitude / 100.0), 0)
	for case: Array in [[BRACE_PATH, braced, "Brace"], [GARNISH_PATH, -1, "Garnish"], [WREST_PATH, -1, "Wrest"]]:
		var enemy: Combatant = _enemy(data, "Sting")
		var player: Combatant = _player(60, 40)
		_play_on(load(case[0]), player, enemy)
		var landing: int = _sum(_ints(EnemyTurn.preview_intent(enemy, data, player).get("hit_amounts", [])))
		# Measured after the card: Garnish's own HP and Toll, Wrest's Block.
		var block: int = player.block
		var toll: int = player.toll
		var hp: int = player.hp
		_apply_skin(player)
		EnemyTurn.take_turn(enemy, data, player)
		_expect_eq([player.hp, toll - player.toll], [hp, maxi(landing - block, 0)], "%s first: the Sting lands %d, past %d Block, paid in Toll" % [case[2], landing, block])
	var player: Combatant = _player(60, 40)
	_apply_skin(player)
	Status.apply_to(player.statuses, load(NO_FURTHER_ARMED_PATH))
	EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect_eq([player.hp, player.toll], [60, 40], "No Further armed: the Sting deals 0, Toll untouched")
	_completed += 1

# Refuse the End fires only when what's past Toll would kill: on 5 HP,
# Critical, with 20 Toll the Sting is paid and the save waits; with 2 Toll
# the rest kills, and the save fires.
func _check_lethal_guard() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var refuse: StatusData = load(REFUSE_PATH)
	var player: Combatant = _player(5, 20)
	_apply_skin(player)
	Status.apply_to(player.statuses, refuse)
	EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect_eq(player.hp, 5, "On 5 HP and 20 Toll: no HP lost")
	_expect(Status.find_in(player.statuses, refuse) != null, "...Refuse the End still armed")
	player = _player(5, 2)
	_apply_skin(player)
	Status.apply_to(player.statuses, refuse)
	EnemyTurn.take_turn(_enemy(data, "Sting"), data, player)
	_expect(player.hp > 0, "On 2 Toll the rest would kill: saved (%d HP)" % player.hp)
	_expect(Status.find_in(player.statuses, refuse) == null, "...the save spent")
	_completed += 1

# The intent preview reads the Toll: on 5 HP and 20 Toll the Sting reaches
# no HP and isn't lethal; without Thick Skin it is.
func _check_preview() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var plain: Combatant = _player(5, 20)
	var preview: Dictionary = EnemyTurn.preview_intent(_enemy(data, "Sting"), data, plain)
	_expect(bool(preview["lethal"]), "On 5 HP without Thick Skin the Sting previews lethal")
	var skinned: Combatant = _player(5, 20)
	_apply_skin(skinned)
	preview = EnemyTurn.preview_intent(_enemy(data, "Sting"), data, skinned)
	_expect_eq([int(preview["damage_to_hp"]), bool(preview["lethal"])], [0, false], "...with it and 20 Toll: 0 to HP, not lethal")
	_expect(not bool(EnemyTurn.simulate_hits(skinned, [20] as Array[int])["lethal"]), "simulate_hits reads the Toll too")
	_completed += 1

# --- Fight ---

# The real play on 20 Toll: TOLL on the face, 2 Energy, 6 Block, the
# status up; End Turn - the enemy's attack past Block paid in Toll, put
# down to status:thick_skin in the run log - and at the next turn's start
# the status gone.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		var data: EnemyData = target.get("enemy_data")
		# Its biggest attack queued, so something gets past the 6 Block.
		var biggest: int = -1
		for i in data.intents.size():
			if data.intents[i].type == EnemyIntent.IntentType.ATTACK and (biggest < 0 or data.intents[i].value * maxi(data.intents[i].hits, 1) > data.intents[biggest].value * maxi(data.intents[biggest].hits, 1)):
				biggest = i
		if biggest >= 0:
			combatant.current_intent_index = biggest
		combatant.max_hp = 999
		combatant.hp = 999
		controller.call("_emit_intent_previews")
		player.toll = 20
		player.energy = 3
		var card: CardData = await _deal(controller)
		var view: CardView = _view(controller, card)
		_expect(view != null and view.type_label.text == "TOLL", "The face in hand: TOLL")
		var block_before: int = player.block
		await _play_real(controller, card)
		_expect_eq(3 - player.energy, 2, "Playing it costs 2 Energy")
		_expect_eq(player.block - block_before, 6, "...gives 6 Block")
		_expect(Status.toll_payer(player.statuses) != null, "...and Thick Skin is up")
		var landing: int = _sum(_ints((controller.call("get_intent_preview", target) as Dictionary).get("hit_amounts", [])))
		var expected: int = mini(maxi(landing - player.block, 0), player.toll)
		var logged_before: int = int(RunLogger._toll_spent_by.get("status:thick_skin", 0))
		var hp_before: int = player.hp
		var turn: int = int(controller.get("_player_turn"))
		controller.call("end_turn")
		await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and not bool(controller.get("_input_locked")), 30.0)
		_expect_eq(20 - player.toll, expected, "The enemy's %d past Block: %d paid in Toll" % [landing, expected])
		_expect_eq(int(RunLogger._toll_spent_by.get("status:thick_skin", 0)) - logged_before, expected, "...logged against status:thick_skin")
		_expect_eq(player.hp, hp_before - maxi(landing - 6 - expected, 0), "...the rest, if any, from HP")
		_expect(Status.toll_payer(player.statuses) == null, "The next turn: Thick Skin gone")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _sum(values: Array[int]) -> int:
	var total: int = 0
	for value in values:
		total += value
	return total

func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out

func _queue(data: EnemyData, intent_name: String) -> EnemyIntent:
	for intent in data.intents:
		if intent.intent_name == intent_name:
			return intent
	_fail("%s has no %s" % [data.enemy_name, intent_name])
	return null

# A fresh enemy with `intent_name` queued.
func _enemy(data: EnemyData, intent_name: String) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	enemy.current_intent_index = data.intents.find(_queue(data, intent_name))
	EnemyTurn._sync_queued(enemy, data)
	return enemy

func _player(hp: int, toll: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.toll = toll
	player.critical_hp_fraction = 0.3
	# The Wanderer's Grace, so "no Grace" is a real test (BattleController
	# copies CharacterData's; a bare Combatant has none).
	player.has_grace = true
	return player

# Thick Skin's status alone, no Block.
func _apply_skin(player: Combatant) -> void:
	Status.apply_to(player.statuses, load(STATUS_PATH))

func _ctx(player: Combatant, enemy: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy if enemy != null else Combatant.new(500)] as Array[Combatant]
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(load(SLASH_PATH))
	ctx.deck = Deck.new(cards)
	return ctx

func _play(card: CardData, player: Combatant) -> void:
	_resolver.resolve_card(card, _ctx(player, null))

func _play_on(card: CardData, player: Combatant, enemy: Combatant) -> void:
	_resolver.resolve_card(card, _ctx(player, enemy))

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
	var layer: Node = _field.get_node("BattleLayer")
	_overlay = layer.get_child(0) if layer.get_child_count() > 0 else null
	if _overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = _overlay.get("battle_controller")
	controller.get("deck").call("discard_hand")
	return controller

func _deal(controller: Node) -> CardData:
	var card: CardData = (load(CARD_PATH) as CardData).duplicate()
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

func _play_real(controller: Node, card: CardData) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	await ProbePlay.settle(self, controller)

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	_overlay = null
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
