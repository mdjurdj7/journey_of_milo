extends SceneTree

# Headless probe for In the Red - 0 Energy, Uncommon Skill, TOLL, no
# target, Spent: lose 5 HP (SELF_DAMAGE_TOLL, no top-up: past Block, 1
# Toll for each HP lost, never below 1 HP, no Grace), gain 1 Energy, and
# if that leaves the player Critical - judged after the loss, against the
# fighter's own threshold as it stands - 1 more Energy and draw 2.
# Energy may stand above the maximum (GainEnergyEffect). In the Red+ draws
# 3.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/in_the_red_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants and a bare Deck. The face case reads a CardView in and out
# of a battle hand: only the Critical clause goes grey when the loss
# won't reach Critical. The fight case loads the real region scene and
# plays through BattleController: the face at hand size, the play sound's
# reading of Critical after the loss, a play over the Energy maximum with
# the extra pips shown, the card Spent, and the next turn's Energy back
# at the refill.

const CASES := 9
const MAX_HP := 70
# Combatant's default: Critical at or below 21 of 70.
const CRITICAL_FRACTION := 0.3
const CARD_PATH := "res://cards/data/in_the_red.tres"
const TEMPERED_PATH := "res://cards/tempered/in_the_red_tempered.tres"
const ART_PATH := "res://cards/art/Wanderer/In the Red.png"
const FILLER_PATH := "res://cards/data/slash.tres"
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
var _loss: int = 0
var _energy: int = 0
var _bonus_energy: int = 0
var _draw: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var card: CardData = load(CARD_PATH)
	_loss = card.effects[0].value
	_energy = card.effects[1].value
	_bonus_energy = card.effects[2].value
	_draw = card.effects[3].value

	_check_data()
	_check_loss()
	_check_floor()
	_check_critical_after_loss()
	_check_live_threshold()
	_check_over_max()
	_check_tempered()
	await _check_face()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("in_the_red_probe: PASSED")
		quit(0)
	else:
		print("in_the_red_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "In the Red", "The card loads")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.card_class, &"wanderer", "...the Wanderer's")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...Spent")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...with its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.description, "Gain {energy} Energy.\n{if}Critical: {bonus_energy} more, and draw {draw}.{/if}\nSpent.", "...its text - the 5 HP on the badge alone")
	_expect_eq(_shape(card), [CardEffect.EffectType.SELF_DAMAGE_TOLL, CardEffect.Condition.NONE,
		CardEffect.EffectType.GAIN_ENERGY, CardEffect.Condition.NONE,
		CardEffect.EffectType.GAIN_ENERGY, CardEffect.Condition.CRITICAL,
		CardEffect.EffectType.DRAW, CardEffect.Condition.CRITICAL], "...lose HP, gain Energy, then more Energy and a draw when Critical")
	_expect_eq(CardBonus.mode(card.effects[2]), CardBonus.Mode.GATE, "...the Critical Energy a gate")
	_expect_eq(CardBonus.mode(card.effects[3]), CardBonus.Mode.GATE, "...and the draw")
	_expect_eq(CardBonus.upfront_hp_cost(card, null, 0), 5, "...its 5 paid before Critical is read")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to In the Red+")
	_expect_eq(tempered.card_name, "In the Red+", "In the Red+ loads")
	_expect_eq(tempered.description, card.description, "...reads the same text")
	_expect_eq([tempered.rarity, tempered.card_class, tempered.removal_scope], [CardData.CardRarity.UNCOMMON, &"wanderer", CardData.RemovalScope.SPENT], "...Uncommon, the Wanderer's, Spent")
	_expect(tempered.art == card.art, "...the same art")
	_expect_eq(_shape(tempered), _shape(card), "...the same effects")
	_completed += 1

# Each effect's type and condition.
func _shape(card: CardData) -> Array:
	var shape: Array = []
	for effect in card.effects:
		shape.append(effect.effect_type)
		shape.append(effect.condition)
	return shape

# --- Rules ---

# 50 HP and 5 Block: 45 after, the Block untouched, 5 Toll, no Grace. Not
# Critical: 1 Energy, nothing drawn.
func _check_loss() -> void:
	var player: Combatant = _player(50)
	player.block = 5
	var deck: Deck = _deck()
	_play(load(CARD_PATH), player, deck)
	_expect_eq(player.hp, 50 - _loss, "Lose %d: 50 to %d" % [_loss, 50 - _loss])
	_expect_eq(player.block, 5, "...past Block, which stays")
	_expect_eq(player.toll, _loss, "...%d Toll, one for each HP" % _loss)
	_expect_eq(player.grace, 0, "...no Grace opened")
	_expect(player.took_damage_this_turn, "...and it counts as damage taken this turn")
	_expect_eq(player.energy, _energy, "Not Critical at %d: %d Energy" % [player.hp, _energy])
	_expect_eq(deck.hand.size(), 0, "...and nothing drawn")
	_completed += 1

# 5 HP: down to 1, never 0 - 4 lost, 4 Toll. At 1 HP, Critical: 2 Energy
# and 2 cards.
func _check_floor() -> void:
	var player: Combatant = _player(5)
	var deck: Deck = _deck()
	_play(load(CARD_PATH), player, deck)
	_expect_eq(player.hp, 1, "On 5 HP: down to 1, not below")
	_expect_eq(player.toll, 4, "...4 Toll, for the 4 lost")
	_expect_eq(player.energy, _energy + _bonus_energy, "...Critical: %d Energy" % (_energy + _bonus_energy))
	_expect_eq(deck.hand.size(), _draw, "...and %d drawn" % _draw)
	var spent: Combatant = _player(1)
	_play(load(CARD_PATH), spent, _deck())
	_expect_eq([spent.hp, spent.toll], [1, 0], "On 1 HP: nothing lost, no Toll")
	_completed += 1

# 26 HP isn't Critical, 21 is: the check reads the HP after the loss. 27
# goes to 22, still above 21: 1 Energy only.
func _check_critical_after_loss() -> void:
	var player: Combatant = _player(26)
	_expect(not player.is_critical(), "26 of 70 isn't Critical")
	var deck: Deck = _deck()
	_play(load(CARD_PATH), player, deck)
	_expect_eq(player.hp, 21, "...down to 21")
	_expect_eq(player.energy, _energy + _bonus_energy, "...Critical after the loss: %d Energy" % (_energy + _bonus_energy))
	_expect_eq(deck.hand.size(), _draw, "...and %d drawn" % _draw)
	var short: Combatant = _player(27)
	var short_deck: Deck = _deck()
	_play(load(CARD_PATH), short, short_deck)
	_expect_eq(short.hp, 22, "27 HP: down to 22")
	_expect_eq(short.energy, _energy, "...not Critical: %d Energy" % _energy)
	_expect_eq(short_deck.hand.size(), 0, "...nothing drawn")
	_completed += 1

# The threshold is the fighter's own, read at play: at half (35 of 70),
# 40 to 35 is Critical; at a tenth (7), 20 to 15 isn't.
func _check_live_threshold() -> void:
	var raised: Combatant = _player(40)
	raised.critical_hp_fraction = 0.5
	var deck: Deck = _deck()
	_play(load(CARD_PATH), raised, deck)
	_expect_eq(raised.energy, _energy + _bonus_energy, "Critical at 35: 40 to 35 pays %d Energy" % (_energy + _bonus_energy))
	_expect_eq(deck.hand.size(), _draw, "...and draws %d" % _draw)
	var lowered: Combatant = _player(20)
	lowered.critical_hp_fraction = 0.1
	var lowered_deck: Deck = _deck()
	_play(load(CARD_PATH), lowered, lowered_deck)
	_expect_eq(lowered.energy, _energy, "Critical at 7: 20 to 15 pays %d" % _energy)
	_expect_eq(lowered_deck.hand.size(), 0, "...and draws nothing")
	_completed += 1

# On a full 3 of 3: 4 not Critical, 5 Critical - above the maximum.
func _check_over_max() -> void:
	var calm: Combatant = _player(50)
	calm.energy = calm.max_energy
	_play(load(CARD_PATH), calm, _deck())
	_expect_eq(calm.energy, calm.max_energy + _energy, "Full Energy, not Critical: %d, past the maximum" % (calm.max_energy + _energy))
	var critical: Combatant = _player(25)
	critical.energy = critical.max_energy
	_play(load(CARD_PATH), critical, _deck())
	_expect_eq(critical.energy, critical.max_energy + _energy + _bonus_energy, "...Critical: %d" % (critical.max_energy + _energy + _bonus_energy))
	_expect_eq(critical.turn_start_energy(), critical.max_energy, "...and a turn starts back at %d" % critical.max_energy)
	_completed += 1

func _check_tempered() -> void:
	var player: Combatant = _player(25)
	var deck: Deck = _deck()
	_play(load(TEMPERED_PATH), player, deck)
	_expect_eq([player.hp, player.toll, player.energy, deck.hand.size()], [20, 5, 2, 3], "In the Red+ on 25: 20 HP, 5 Toll, 2 Energy, 3 drawn")
	var calm: Combatant = _player(50)
	var calm_deck: Deck = _deck()
	_play(load(TEMPERED_PATH), calm, calm_deck)
	_expect_eq([calm.energy, calm_deck.hand.size()], [1, 0], "...on 50: 1 Energy, nothing drawn")
	_completed += 1

# --- Face and fight ---

# Outside a fight: the rule, no ink state. In a battle hand: the Critical
# clause grey when the loss won't reach Critical, in ink when it will -
# judged at the HP after the 5 - and "Gain 1 Energy." always in ink. The
# 5 HP is the badge's alone.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	var rule: String = "Gain 1 Energy.\nCritical: 1 more, and draw 2.\nSpent."
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), rule, "The face outside a fight says its rule")
	_expect_eq(view._bonus_state, CardBonus.State.NONE, "...with no clause to light")
	_expect_eq(view.hp_cost_label.text, "−5 HP", "...and its −5 HP line")
	_expect(not view.rules_text.text.contains("[color="), "...all of it in ink")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), rule.replace("draw 2", "draw 3"), "In the Red+ outside a fight")
	view.set_card_data(load(CARD_PATH))
	var dormant: String = "[color=#%s]" % Color(view.bonus_dormant_ink, view.rules_alpha).to_html(true)
	var calm: Combatant = _player(30)
	view.set_bonus_context(_ctx(calm))
	_expect_eq(view._bonus_state, CardBonus.State.DORMANT, "On 30 HP (25 after): the clause dormant")
	var text: String = view.rules_text.text
	var clause: int = text.find(dormant + "[b]Critical[/b]")
	_expect(clause >= 0, "...the Critical clause in grey (%s)" % text)
	_expect(clause >= 0 and not text.substr(0, clause).contains("[color="), "...Gain 1 Energy still in ink")
	_expect_eq(view.rules_text.get_parsed_text(), rule, "...the words the same")
	var near: Combatant = _player(26)
	view.set_bonus_context(_ctx(near))
	_expect_eq(view._bonus_state, CardBonus.State.LIVE, "On 26 HP (21 after): the clause live")
	_expect(not view.rules_text.text.contains("[color="), "...everything in ink")
	view.free()
	_completed += 1

# The real fight - the Wanderer's 80 HP, Critical at 24 - on 29 HP and a
# full 3 Energy: the face at hand size, live; the play sound reads it as
# Critical (29 isn't - 24 is), and at 50 wouldn't. Played: 24 HP, 5 Toll,
# 5 Energy with two pips past the row, 2 more in hand, the card Spent.
# The next turn starts on 3 again.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.hp = 29
		player.toll = 0
		player.energy = player.max_energy
		controller.emit_signal("toll_changed", 0)
		controller.emit_signal("energy_changed", player.energy)
		var card: CardData = await _deal(controller, CARD_PATH)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.cost_label.text, "0", "The face: 0 Energy")
			_expect_eq(view.type_label.text, "TOLL", "...labelled TOLL")
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...its text at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
		_expect(bool(_overlay.call("_condition_live_at_commit", card)), "The play sound reads Critical on 29 HP: the 5 counted")
		player.hp = 50
		_expect(not bool(_overlay.call("_condition_live_at_commit", card)), "...and not on 50")
		player.hp = 29
		var deck: Deck = controller.get("deck")
		var in_hand: int = deck.hand.size()
		await _play_real(controller, card)
		_expect_eq(player.hp, 24, "Played on 29: 24 HP")
		_expect_eq(player.toll, _loss, "...%d Toll" % _loss)
		_expect_eq(player.energy, player.max_energy + _energy + _bonus_energy, "...%d Energy, past the maximum" % (player.max_energy + _energy + _bonus_energy))
		_expect_eq(deck.hand.size(), in_hand - 1 + _draw, "...%d drawn" % _draw)
		_expect(deck.exhaust_pile.has(card), "...and the card Spent")
		_expect(not deck.discard_pile.has(card) and not deck.draw_pile.has(card), "...out of the piles")
		var resources: Node = _overlay.get("_resources")
		_expect_eq(int(resources.call("_over_max")), _energy + _bonus_energy, "The readout shows %d pips past the row" % (_energy + _bonus_energy))
		player.hp = player.max_hp
		var turn: int = int(controller.get("_player_turn"))
		controller.call("end_turn")
		var back: bool = await ProbePlay.wait_until(self, func() -> bool:
			return int(controller.get("_player_turn")) > turn and not bool(controller.get("_enemy_phase")) and ProbePlay.is_settled(controller), 20.0)
		_expect(back, "The next turn comes round")
		if back:
			_expect_eq(player.energy, player.turn_start_energy(), "...on the refill, %d" % player.turn_start_energy())
			_expect_eq(int(resources.call("_over_max")), 0, "...no pips past the row")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	player.energy = 0
	return player

# Ten cards to draw from, an empty hand.
func _deck() -> Deck:
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(load(FILLER_PATH))
	return Deck.new(cards)

func _ctx(player: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	return ctx

func _play(card: CardData, player: Combatant, deck: Deck) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.deck = deck
	var enemies: Array[Combatant] = [Combatant.new(100)]
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
