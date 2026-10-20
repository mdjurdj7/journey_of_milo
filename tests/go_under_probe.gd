extends SceneTree

# Headless probe for Go Under - 1 Energy, Uncommon Power, no target: it
# applies Gone Under, and for the rest of the fight the player is Critical
# at or below 50% of max HP (StatusData.raises_critical_percent, read
# through Combatant.critical_fraction()). A second copy adds nothing and
# is never blocked. Played at or under the new line, the player enters
# Critical then and there: No Further gives way and the keepsake's entry
# Block fires, as if HP had dropped there. Go Under+ costs 0.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/go_under_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants. The face case reads Go Under's text and In the Red's live
# ink with and without the raised line; the tooltip case the Critical
# keyword's threshold. The fight case plays Go Under through
# BattleController on the real region scene: the HP bar's line easing to
# 50% and its colour, In the Red's sound lift, the tooltip - and all of it
# back to 30% when the fight is won. The turn-scoped case raises the same
# line for one turn only (On the Brink's status, StatusData.ends_at_turn_
# end), gone at the turn's end - and under Gone Under, still 50% after.
# Untyped against anything that names the RunState autoload (the HP bar
# is read by name, not as HPBar).

const CASES := 9
const MAX_HP := 80
const BASE_FRACTION := 0.3
const CARD_PATH := "res://cards/data/go_under.tres"
const TEMPERED_PATH := "res://cards/tempered/go_under_tempered.tres"
const STATUS_PATH := "res://battle/rules/statuses/gone_under.tres"
const TURN_STATUS_PATH := "res://battle/rules/statuses/on_the_brink.tres"
const NO_FURTHER_STATUS_PATH :="res://battle/rules/statuses/no_further.tres"
const CORNERED_PATH := "res://cards/data/cornered.tres"
const IN_THE_RED_PATH := "res://cards/data/in_the_red.tres"
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
var _raised: float = 0.0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_raised = (load(STATUS_PATH) as StatusData).raises_critical_percent / 100.0

	_check_data()
	_check_threshold()
	_check_turn_scoped()
	_check_entry()
	_check_cornered()
	_check_in_the_red()
	await _check_face()
	_check_tooltip()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("go_under_probe: PASSED")
		quit(0)
	else:
		print("go_under_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	_expect_eq(card.card_name, "Go Under", "The card loads")
	_expect_eq(card.cost, 1, "...costs 1 Energy")
	_expect_eq(card.card_type, CardData.CardType.POWER, "...is a Power")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.offer, CardData.OfferScope.REWARDABLE, "...rewardable")
	_expect_eq(card.card_class, &"wanderer", "...the Wanderer's")
	_expect_eq(card.target_type, CardData.TargetType.SELF, "...takes no enemy target")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.POWER, "...reading POWER")
	_expect_eq(card.description, "This fight, you're Critical at {critical_percent}% of max HP or below.", "...its text")
	_expect(card.effects.size() == 1 and card.effects[0].effect_type == CardEffect.EffectType.APPLY_STATUS and card.effects[0].status_data == status, "...one effect: it applies Gone Under")
	_expect_eq(status.raises_critical_percent, 50, "Gone Under raises the line to 50%")
	_expect_eq(status.default_duration_turns, -1, "...for the fight")
	_expect_eq(status.stack_rule, StatusData.StackRule.IGNORE, "...a second copy ignored")
	_expect(not status.blocks_reapply_while_held, "...and never blocked")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Go Under+")
	_expect_eq([tempered.card_name, tempered.cost, tempered.card_type, tempered.rarity, tempered.card_class], ["Go Under+", 0, CardData.CardType.POWER, CardData.CardRarity.UNCOMMON, &"wanderer"], "Go Under+: 0 Energy, the same Power")
	_expect_eq(tempered.description, card.description, "...the same text")
	_expect(tempered.effects.size() == 1 and tempered.effects[0].status_data == status, "...and the same status")
	_completed += 1

# --- Rules ---

# 35 of 80: above 24, so not Critical; Go Under puts the line at 40 and
# 35 is under it. A second copy: still one Gone Under, still 50%, and
# playable. Go Under+ the same.
func _check_threshold() -> void:
	var player: Combatant = _player(35)
	_expect(not player.is_critical(), "35 of 80 isn't Critical at 30%")
	_expect_eq(player.critical_fraction(), BASE_FRACTION, "...the line at 30%")
	_play(load(CARD_PATH), player)
	_expect_eq(player.critical_fraction(), _raised, "Go Under: the line at 50%")
	_expect(player.is_critical(), "...35 of 80 is Critical")
	_expect(player.is_critical_at(40) and not player.is_critical_at(41), "...at 40 and below, not 41")
	_expect(not EffectResolver.card_blocked(load(CARD_PATH), player), "A second copy can still be played")
	_play(load(CARD_PATH), player)
	_expect_eq(_held(player), 1, "...and adds nothing: one Gone Under")
	_expect_eq(player.critical_fraction(), _raised, "...the line still 50%")
	var tempered: Combatant = _player(35)
	_play(load(TEMPERED_PATH), tempered)
	_expect_eq(tempered.critical_fraction(), _raised, "Go Under+ raises it the same")
	var higher: Combatant = _player(35)
	higher.critical_hp_fraction = 0.6
	_play(load(CARD_PATH), higher)
	_expect_eq(higher.critical_fraction(), 0.6, "A line already above 50% stays where it is")
	_completed += 1

# The turn-scoped raise (On the Brink's status): 35 of 80 Critical at 50%
# while it's held; the turn's end (Status.remove_at_turn_end(), the call
# BattleController._finish_turn() makes before the enemy turn) takes it
# and the line is 30% again. Held beside Gone Under it adds nothing, and
# its end leaves Gone Under's 50%.
func _check_turn_scoped() -> void:
	var status: StatusData = load(TURN_STATUS_PATH)
	_expect_eq([status.raises_critical_percent, status.ends_at_turn_end, status.stack_rule], [50, true, StatusData.StackRule.IGNORE], "On the Brink's status: 50%, this turn only, a second copy ignored")
	var player: Combatant = _player(35)
	Status.apply_to(player.statuses, status)
	_expect_eq(player.critical_fraction(), _raised, "Held: the line at 50%")
	_expect(player.is_critical(), "...35 of 80 Critical")
	Status.remove_at_turn_end(player.statuses)
	_expect_eq(player.critical_fraction(), BASE_FRACTION, "The turn's end: the line back at 30%")
	_expect(not player.is_critical(), "...35 of 80 not Critical")
	var under: Combatant = _player(35)
	_play(load(CARD_PATH), under)
	Status.apply_to(under.statuses, status)
	_expect_eq(under.critical_fraction(), _raised, "With Gone Under: still 50%")
	Status.remove_at_turn_end(under.statuses)
	_expect_eq(under.critical_fraction(), _raised, "...and 50% after the turn's end")
	_expect_eq(_held(under), 1, "...Gone Under kept")
	_completed += 1

# Played at 35 with No Further held and the keepsake's entry Block armed:
# Critical then and there - No Further gives way to its grant, the Block
# lands. At 60, over the new line too: nothing fires.
func _check_entry() -> void:
	var no_further: StatusData = load(NO_FURTHER_STATUS_PATH)
	var player: Combatant = _player(35)
	Status.apply_to(player.statuses, no_further)
	player.critical_entry_block = 5
	player.critical_entry_armed = true
	_play(load(CARD_PATH), player)
	_expect(Status.find_in(player.statuses, no_further) == null, "Entering Critical on play: No Further gives way")
	_expect(Status.find_in(player.statuses, no_further.grants_on_critical) != null, "...to what it grants")
	_expect_eq(player.block, 5, "...and the entry Block fires")
	var calm: Combatant = _player(60)
	Status.apply_to(calm.statuses, no_further)
	calm.critical_entry_block = 5
	calm.critical_entry_armed = true
	_play(load(CARD_PATH), calm)
	_expect(Status.find_in(calm.statuses, no_further) != null, "At 60, over 40: No Further waits")
	_expect_eq(calm.block, 0, "...and no entry Block")
	_completed += 1

# Cornered at 35: 8 before Go Under, 16 after.
func _check_cornered() -> void:
	var cornered: CardData = load(CORNERED_PATH)
	var player: Combatant = _player(35)
	var enemy := Combatant.new(100)
	_play(cornered, player, enemy)
	var plain: int = 100 - enemy.hp
	_expect_eq(plain, cornered.effects[0].value, "Cornered at 35, line at 30%%: %d" % cornered.effects[0].value)
	_play(load(CARD_PATH), player)
	var after := Combatant.new(100)
	_play(cornered, player, after)
	_expect_eq(100 - after.hp, cornered.effects[0].alt_value, "...after Go Under: %d" % cornered.effects[0].alt_value)
	_completed += 1

# In the Red at 48: 40 after its 8 - not Critical at 24, Critical at 40.
func _check_in_the_red() -> void:
	var in_the_red: CardData = load(IN_THE_RED_PATH)
	var plain: Combatant = _player(48)
	var plain_deck: Deck = _deck()
	_play(in_the_red, plain, null, plain_deck)
	_expect_eq([plain.energy, plain_deck.hand.size()], [1, 0], "In the Red at 48, line at 30%: 1 Energy, nothing drawn")
	var under: Combatant = _player(48)
	_play(load(CARD_PATH), under)
	var under_deck: Deck = _deck()
	_play(in_the_red, under, null, under_deck)
	_expect_eq([under.energy, under_deck.hand.size()], [2, 2], "...after Go Under: 2 Energy, 2 drawn")
	_completed += 1

# --- Face, tooltip, HP bar, fight ---

# Go Under's face: its 50 from data. In the Red at 48 in a battle hand:
# the Critical clause grey at 30%, in ink with Gone Under.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "This fight, you're Critical at 50% of max HP or below.", "Go Under's face")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view.type_label.text, "POWER", "...labelled POWER")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.cost_label.text, "0", "Go Under+'s face: 0 Energy")
	view.set_card_data(load(IN_THE_RED_PATH))
	var player: Combatant = _player(48)
	view.set_bonus_context(_ctx(player))
	_expect_eq(view._bonus_state, CardBonus.State.DORMANT, "In the Red at 48, line at 30%: its clause grey")
	_play(load(CARD_PATH), player)
	view.set_bonus_context(_ctx(player))
	_expect_eq(view._bonus_state, CardBonus.State.LIVE, "...with Gone Under: in ink")
	view.free()
	_completed += 1

func _check_tooltip() -> void:
	var table: KeywordTable = KeywordTable.shared()
	_expect_eq(table.definition("Critical"), "At or below 30% of your max HP.", "The Critical tooltip: 30%")
	KeywordTable.fight_critical_fraction = _raised
	_expect_eq(table.definition("Critical"), "At or below 50% of your max HP.", "...50% during a fight with Go Under")
	KeywordTable.fight_critical_fraction = -1.0
	_expect_eq(table.definition("Critical"), "At or below 30% of your max HP.", "...30% again once cleared")
	_completed += 1

# The real fight on 38 of 80: In the Red's sound reads not Critical (30
# after its 8, over 24); Go Under played - the line at 50% (40), 38
# Critical, the HP bar's tick easing there (seen partway, not snapped) and
# the bar Critical, the tooltip at 50%, In the Red's sound live (30 is
# under 40). The fight won:
# the tick eased back to 30%, the tooltip at 30%.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var bar: Node = _overlay.get("_field_hp_bar")
		player.energy = 99
		player.hp = 38
		_run_state.set("player_hp", 38)
		_run_state.emit_signal("player_hp_changed", 38, player.max_hp)
		var in_the_red: CardData = await _deal(controller, IN_THE_RED_PATH)
		_expect(not bool(_overlay.call("_condition_live_at_commit", in_the_red)), "In the Red's sound on 38, line at 30%: not lifted")
		_expect(is_equal_approx(_line(bar), BASE_FRACTION), "The HP bar's line at 30%% (%s)" % _line(bar))
		_expect(not bool(bar.call("_is_critical")), "...38 of 80 not Critical on it")
		var go_under: CardData = await _deal(controller, CARD_PATH)
		var rising: Array[float] = []
		_watch_line(bar, rising, _raised)
		await _play_real(controller, go_under)
		_expect_eq(player.critical_fraction(), _raised, "Go Under played: the fight's line at 50%")
		_expect(player.is_critical(), "...38 of 80 Critical")
		_expect(bool(bar.call("_is_critical")), "...the HP bar Critical")
		var there: bool = await ProbePlay.wait_until(self, func() -> bool: return is_equal_approx(_line(bar), _raised), 3.0)
		_expect(there, "...its line at 50%% (%s)" % _line(bar))
		_expect(_eased(rising, BASE_FRACTION, _raised), "...eased there, not snapped (%s)" % [rising])
		_expect_eq(int(KeywordTable.live_values()["threshold"]), 50, "...the Critical tooltip at 50%")
		_expect(bool(_overlay.call("_condition_live_at_commit", in_the_red)), "...In the Red's sound lifted")
		var falling: Array[float] = []
		_watch_line(bar, falling, BASE_FRACTION)
		_win(controller)
		var back: bool = await ProbePlay.wait_until(self, func() -> bool: return not bool(bar.get("_in_battle")) and is_equal_approx(_line(bar), BASE_FRACTION), 30.0)
		_expect(back, "The fight won: the HP bar's line back at 30%% (%s)" % _line(bar))
		_expect(_eased(falling, _raised, BASE_FRACTION), "...eased back (%s)" % [falling])
		_expect_eq(KeywordTable.fight_critical_fraction, -1.0, "...the tooltip's fight line cleared")
		_expect_eq(int(KeywordTable.live_values()["threshold"]), 30, "...30% again")
	await _teardown()
	_completed += 1

# Where the HP bar's Critical tick draws now, as a fraction of the bar.
func _line(bar: Node) -> float:
	return float(bar.call("_critical_fraction"))

# Records the tick's place every frame, alongside whatever the caller
# awaits, until it reaches `to` (or 30 s of game time pass).
func _watch_line(bar: Node, samples: Array[float], to: float) -> void:
	var until: int = ProbePlay.game_msec() + 30000
	while ProbePlay.game_msec() < until and is_instance_valid(bar):
		var value: float = _line(bar)
		samples.append(value)
		if is_equal_approx(value, to):
			return
		await process_frame

# Whether `samples` went from `from` to `to` through a place between.
func _eased(samples: Array[float], from: float, to: float) -> bool:
	var low: float = minf(from, to)
	var high: float = maxf(from, to)
	for value in samples:
		if value > low + 0.001 and value < high - 0.001:
			return true
	return false

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = BASE_FRACTION
	return player

func _held(player: Combatant) -> int:
	var count: int = 0
	for active in player.statuses:
		if active.data == load(STATUS_PATH):
			count += 1
	return count

func _deck() -> Deck:
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(load(FILLER_PATH))
	return Deck.new(cards)

func _ctx(player: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	return ctx

func _play(card: CardData, player: Combatant, enemy: Combatant = null, deck: Deck = null) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.deck = deck if deck != null else _deck()
	var enemies: Array[Combatant] = [enemy if enemy != null else Combatant.new(100)]
	ctx.enemies = enemies
	_resolver.resolve_card(card, ctx)

# Every enemy down, as floor5_probe wins its fight.
func _win(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: Combatant = combatants.get(member)
		combatant.hp = 0
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

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
