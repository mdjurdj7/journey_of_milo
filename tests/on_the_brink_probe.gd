extends SceneTree

# Headless probe for On the Brink - 0 Energy, Common Skill, no target,
# Spent: it applies On the Brink's status (the Critical line at 50% of
# max HP, this turn only - StatusData.ends_at_turn_end, read through
# Combatant.critical_fraction()) and draws 1. On the Brink+ draws 2.
# Under Gone Under the line adds nothing, and the draw still happens.
# Played at or under the new line, the player is Critical then and
# there: No Further arms, and stays armed into the enemy's turn.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/on_the_brink_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants, and end the turn the way BattleController._finish_turn()
# does (Status.remove_at_turn_end()). The face case reads both copies'
# text and size. The fight case plays On the Brink through
# BattleController on the real region scene: the HP bar's line at 50%,
# the card Spent, one card drawn - and at End Turn the line back at 30%
# before any enemy acts. Untyped against anything that names the RunState
# autoload (the HP bar is read by name, not as HPBar).

const CASES := 7
const MAX_HP := 80
const BASE_FRACTION := 0.3
const CARD_PATH := "res://cards/data/on_the_brink.tres"
const TEMPERED_PATH := "res://cards/tempered/on_the_brink_tempered.tres"
const STATUS_PATH := "res://battle/rules/statuses/on_the_brink.tres"
const ART_PATH := "res://cards/art/Wanderer/On the Brink.png"
const GO_UNDER_PATH := "res://cards/data/go_under.tres"
const NO_FURTHER_STATUS_PATH := "res://battle/rules/statuses/no_further.tres"
const CORNERED_PATH := "res://cards/data/cornered.tres"
const IN_THE_RED_PATH := "res://cards/data/in_the_red.tres"
const FILLER_PATH := "res://cards/data/slash.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _raised: float = 0.0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_raised = (load(STATUS_PATH) as StatusData).raises_critical_percent / 100.0

	_check_data()
	await _check_face()
	_check_turn()
	_check_go_under()
	_check_critical_cards()
	_check_no_further()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("on_the_brink_probe: PASSED")
		quit(0)
	else:
		print("on_the_brink_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	_expect_eq(card.card_name, "On the Brink", "The card loads")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.COMMON, "...Common")
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.card_class, &"wanderer", "...the Wanderer's")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...Spent")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...with its art (%s)" % (card.art.resource_path if card.art != null else "none"))
	_expect_eq(card.description, "This turn, your Critical line is {critical_percent}% HP. Draw {draw}.\nSpent.", "...its text")
	_expect(card.effects.size() == 2 and card.effects[0].effect_type == CardEffect.EffectType.APPLY_STATUS and card.effects[0].status_data == status, "...first it applies On the Brink's status")
	_expect(card.effects.size() == 2 and card.effects[1].effect_type == CardEffect.EffectType.DRAW, "...then draws")
	_expect(status.ends_at_turn_end, "The status: this turn only")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to On the Brink+")
	_expect_eq([tempered.card_name, tempered.card_type, tempered.rarity, tempered.removal_scope, tempered.card_class], ["On the Brink+", CardData.CardType.SKILL, CardData.CardRarity.COMMON, CardData.RemovalScope.SPENT, &"wanderer"], "On the Brink+: the same Spent Skill")
	_expect_eq(tempered.description, card.description, "...the same text")
	_expect(tempered.effects.size() == 2 and tempered.effects[0].status_data == status and tempered.effects[1].effect_type == CardEffect.EffectType.DRAW, "...the same status, and a draw")
	for pool_path: String in [WANDERER_POOL_PATH, COLLECTOR_POOL_PATH]:
		var pool: RewardPool = load(pool_path)
		_expect(pool.entries.has(card), "In %s" % pool_path)
	_completed += 1

# --- Face ---

# Both copies' faces: the 50 and the draw from data, Critical in bold, at
# 15 px - the text fits on two lines and a third for Spent, no lone word.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "This turn, your Critical line is 50% HP. Draw 1.\nSpent.", "On the Brink's face")
	_expect(view.rules_text.text.contains("[b]Critical[/b]"), "...Critical in bold")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view.cost_label.text, "0", "...0 Energy")
	_expect_eq(view.type_label.text, "UTILITY", "...labelled UTILITY, as a Skill is")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "This turn, your Critical line is 50% HP. Draw 2.\nSpent.", "On the Brink+'s face")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	view.free()
	_completed += 1

# --- Rules ---

# 35 of 80: above 24, so not Critical. Played: the line at 50% (40), 35
# Critical, one card drawn. The turn's end: 30% again, 35 not Critical.
# On the Brink+ draws 2.
func _check_turn() -> void:
	var player: Combatant = _player(35)
	_expect(not player.is_critical(), "35 of 80 isn't Critical at 30%")
	var deck: Deck = _deck()
	_play(load(CARD_PATH), player, null, deck)
	_expect_eq(player.critical_fraction(), _raised, "Played: the line at 50%")
	_expect(player.is_critical(), "...35 of 80 Critical")
	_expect(player.is_critical_at(40) and not player.is_critical_at(41), "...at 40 and below, not 41")
	_expect_eq(deck.hand.size(), 1, "...one card drawn")
	_expect_eq([player.hp, player.max_hp], [35, MAX_HP], "...HP and max HP untouched")
	Status.remove_at_turn_end(player.statuses)
	_expect_eq(player.critical_fraction(), BASE_FRACTION, "The turn's end: the line back at 30%")
	_expect(not player.is_critical(), "...35 of 80 not Critical")
	var tempered: Combatant = _player(35)
	var tempered_deck: Deck = _deck()
	_play(load(TEMPERED_PATH), tempered, null, tempered_deck)
	_expect_eq(tempered.critical_fraction(), _raised, "On the Brink+: the line at 50%")
	_expect_eq(tempered_deck.hand.size(), 2, "...two cards drawn")
	_completed += 1

# Under Gone Under: the line already 50%, so nothing more - the draw still
# happens - and the turn's end leaves Gone Under's 50%.
func _check_go_under() -> void:
	var player: Combatant = _player(60)
	_play(load(GO_UNDER_PATH), player)
	_expect_eq(player.critical_fraction(), _raised, "Go Under: the line at 50%")
	var deck: Deck = _deck()
	_play(load(CARD_PATH), player, null, deck)
	_expect_eq(player.critical_fraction(), _raised, "On the Brink with it: still 50%")
	_expect_eq(deck.hand.size(), 1, "...and its draw happens")
	Status.remove_at_turn_end(player.statuses)
	_expect_eq(player.critical_fraction(), _raised, "The turn's end: Gone Under's 50% holds")
	_completed += 1

# This turn's Critical reads: Cornered at 35 deals its Critical damage; In
# the Red at 45 (40 after its 5) its Critical Energy and draw.
func _check_critical_cards() -> void:
	var cornered: CardData = load(CORNERED_PATH)
	var player: Combatant = _player(35)
	_play(load(CARD_PATH), player)
	var enemy := Combatant.new(100)
	_play(cornered, player, enemy)
	_expect_eq(100 - enemy.hp, cornered.effects[0].alt_value, "Cornered at 35 after On the Brink: %d" % cornered.effects[0].alt_value)
	var in_the_red: CardData = load(IN_THE_RED_PATH)
	var red: Combatant = _player(45)
	_play(load(CARD_PATH), red)
	var red_deck: Deck = _deck()
	_play(in_the_red, red, null, red_deck)
	_expect_eq([red.energy, red_deck.hand.size()], [2, 2], "In the Red at 45 after On the Brink: 2 Energy, 2 drawn")
	_completed += 1

# No Further held at 35: On the Brink makes the player Critical, No Further
# gives way to its armed grant - and the turn's end, taking the line back
# to 30%, leaves it armed for the enemy's turn. At 60, over 40: it waits.
func _check_no_further() -> void:
	var no_further: StatusData = load(NO_FURTHER_STATUS_PATH)
	var player: Combatant = _player(35)
	Status.apply_to(player.statuses, no_further)
	_play(load(CARD_PATH), player)
	_expect(Status.find_in(player.statuses, no_further) == null, "No Further at 35: gives way on On the Brink")
	_expect(Status.find_in(player.statuses, no_further.grants_on_critical) != null, "...armed")
	Status.remove_at_turn_end(player.statuses)
	_expect(not player.is_critical(), "The turn's end: not Critical")
	_expect(Status.find_in(player.statuses, no_further.grants_on_critical) != null, "...and still armed into the enemy's turn")
	var calm: Combatant = _player(60)
	Status.apply_to(calm.statuses, no_further)
	_play(load(CARD_PATH), calm)
	_expect(Status.find_in(calm.statuses, no_further) != null, "At 60, over 40: No Further waits")
	_completed += 1

# --- Fight ---

# The real fight on 38 of 80: On the Brink played - Spent, one card drawn,
# 38 Critical, the HP bar Critical and its line at 50%, the tooltip at
# 50%. End Turn: before any enemy acts, the line is 30% again and 38 is
# not Critical; the HP bar's line eases back to 30%.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var deck: Deck = controller.get("deck")
		var bar: Node = _overlay.get("_field_hp_bar")
		player.energy = 3
		player.hp = 38
		_run_state.set("player_hp", 38)
		_run_state.emit_signal("player_hp_changed", 38, player.max_hp)
		for combatant: Combatant in (controller.get("_combatants") as Dictionary).values():
			combatant.max_hp = 999
			combatant.hp = 999
		for i in 5:
			deck.draw_pile.append((load(FILLER_PATH) as CardData).duplicate())
		var brink: CardData = await _deal(controller, CARD_PATH)
		_expect(not bool(bar.call("_is_critical")), "38 of 80 not Critical on the HP bar")
		var hand_before: int = deck.hand.size()
		await _play_real(controller, brink)
		_expect(deck.exhaust_pile.has(brink), "On the Brink played: Spent")
		_expect_eq(deck.hand.size(), hand_before, "...one card drawn in its place")
		_expect_eq(player.critical_fraction(), _raised, "...the fight's line at 50%")
		_expect(player.is_critical(), "...38 of 80 Critical")
		_expect(bool(bar.call("_is_critical")), "...the HP bar Critical")
		var there: bool = await ProbePlay.wait_until(self, func() -> bool: return is_equal_approx(_line(bar), _raised), 3.0)
		_expect(there, "...its line at 50%% (%s)" % _line(bar))
		_expect_eq(int(KeywordTable.live_values()["threshold"]), 50, "...the Critical tooltip at 50%")
		controller.call("end_turn")
		_expect(bool(controller.get("_input_locked")), "End Turn: the enemy turn under way")
		_expect_eq(player.critical_fraction(), BASE_FRACTION, "...the line at 30% before any enemy acts")
		_expect(not player.is_critical(), "...38 of 80 not Critical")
		_expect_eq(int(KeywordTable.live_values()["threshold"]), 30, "...the Critical tooltip at 30%")
		var back: bool = await ProbePlay.wait_until(self, func() -> bool: return is_equal_approx(_line(bar), BASE_FRACTION), 3.0)
		_expect(back, "...the HP bar's line back at 30%% (%s)" % _line(bar))
		await ProbePlay.wait_until(self, func() -> bool: return not bool(controller.get("_input_locked")), 30.0)
	await _teardown()
	_completed += 1

# Where the HP bar's Critical tick draws now, as a fraction of the bar.
func _line(bar: Node) -> float:
	return float(bar.call("_critical_fraction"))

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = BASE_FRACTION
	return player

func _deck() -> Deck:
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(load(FILLER_PATH))
	return Deck.new(cards)

func _play(card: CardData, player: Combatant, enemy: Combatant = null, deck: Deck = null) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.deck = deck if deck != null else _deck()
	var enemies: Array[Combatant] = [enemy if enemy != null else Combatant.new(100)]
	ctx.enemies = enemies
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
