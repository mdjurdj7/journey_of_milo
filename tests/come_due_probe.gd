extends SceneTree

# Headless probe for Come Due - 0 Energy, Common Skill, TOLL, no target:
# "Spend 5 Toll. Gain 2 Energy. Next turn, gain 2 less." Blocked under 5
# Toll. The debt is Owed on the Wanderer, its amount in its row ("Owed
# 2"), adding up over plays; the next turn's refill is that much less,
# never below 0, and then it clears. Come Due+ owes 1. Rules layer, a
# CardView, the real .tres cards, status and pool; the fight case plays it
# through BattleController on floor 1 and ends the turn.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/come_due_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const CASES := 9
const MAX_HP := 70
const CARD_PATH := "res://cards/data/come_due.tres"
const TEMPERED_PATH := "res://cards/tempered/come_due_tempered.tres"
const OWED_PATH := "res://battle/rules/statuses/owed.tres"
const DYING_LIGHT_PATH := "res://battle/rules/statuses/dying_light.tres"
const ART_PATH := "res://cards/art/Wanderer/Come Due.png"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _toll: int = 0
var _gain: int = 0
var _debt: int = 0

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	var card: CardData = load(CARD_PATH)
	_toll = card.effects[0].toll_cost
	_gain = card.effects[1].value
	_debt = card.effects[2].value
	_check_card_data()
	_check_toll_gate()
	_check_play()
	_check_stacks()
	_check_next_turn()
	_check_floor()
	_check_tempered()
	await _check_face()
	await _check_fight()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("come_due_probe: PASSED")
		quit(0)
	else:
		print("come_due_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = load(CARD_PATH)
	var owed: StatusData = load(OWED_PATH)
	_expect_eq(card.card_name, "Come Due", "The card loads")
	_expect_eq([card.card_type, card.rarity, card.target_type, card.card_class], [CardData.CardType.SKILL, CardData.CardRarity.COMMON, CardData.TargetType.SELF, &"wanderer"], "...a Skill, Common, no target, the Wanderer's")
	_expect_eq(card.description, "Gain {energy} Energy.\nNext turn, gain {debt} less.", "...its text")
	_expect(card.effects.size() == 3 and card.effects[0].effect_type == CardEffect.EffectType.SPEND_TOLL and card.effects[1].effect_type == CardEffect.EffectType.GAIN_ENERGY and card.effects[2].effect_type == CardEffect.EffectType.APPLY_STATUS and card.effects[2].status_data == owed, "...SPEND_TOLL, GAIN_ENERGY, then Owed")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...reading TOLL")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "...its art kept")
	_expect(owed.energy_debt and owed.default_duration_turns == 1, "Owed: an Energy debt, for one turn")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "In the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector's")
	_completed += 1

func _check_toll_gate() -> void:
	var player: Combatant = _player()
	player.toll = _toll - 1
	_expect(EffectResolver.card_blocked(load(CARD_PATH), player), "%d Toll: blocked" % (_toll - 1))
	player.toll = _toll
	_expect(not EffectResolver.card_blocked(load(CARD_PATH), player), "%d: playable" % _toll)
	_completed += 1

# On 7 Toll and 1 Energy: 2 Toll left, 3 Energy, Owed 2.
func _check_play() -> void:
	var player: Combatant = _player()
	player.toll = 7
	player.energy = 1
	_play(load(CARD_PATH), player)
	_expect_eq(player.toll, 7 - _toll, "Come Due spends 5")
	_expect_eq(player.energy, 1 + _gain, "...gains 2 Energy")
	_expect_eq(_owed_label(player), "Owed 2", "...and owes 2: 'Owed 2'")
	_expect(player.toll_spent_this_turn, "...Toll spent this turn")
	_completed += 1

func _check_stacks() -> void:
	var player: Combatant = _player()
	player.toll = 2 * _toll
	_play(load(CARD_PATH), player)
	_play(load(CARD_PATH), player)
	_expect_eq(player.energy, 2 * _gain, "Twice: 4 Energy")
	_expect_eq(_owed_label(player), "Owed 4", "...one Owed, 4")
	_expect_eq(Status.energy_debt(player.statuses), 4, "...4 owed")
	_completed += 1

# The refill reads the debt, then the turn's tick ends it - as
# BattleController._start_player_turn() runs them: 3 - 2, then 3 again.
func _check_next_turn() -> void:
	var player: Combatant = _player()
	player.toll = _toll
	_play(load(CARD_PATH), player)
	_expect_eq(player.turn_start_energy(), player.max_energy - _debt, "Next turn's refill: 3 - 2 = 1")
	_start_turn(player)
	_expect_eq(player.energy, player.max_energy - _debt, "...the turn starts on 1")
	_expect_eq(_owed_label(player), "", "...and Owed is gone")
	_start_turn(player)
	_expect_eq(player.energy, player.max_energy, "The turn after: 3 again")
	_completed += 1

# Owed 4 against a refill of 3: 0, never below; Dying Light's 1 at
# Critical comes off the same debt.
func _check_floor() -> void:
	var player: Combatant = _player()
	player.toll = 2 * _toll
	_play(load(CARD_PATH), player)
	_play(load(CARD_PATH), player)
	_expect_eq(player.turn_start_energy(), 0, "Owed 4, refill 3: 0, not -1")
	var lit: Combatant = _player()
	lit.hp = 10
	Status.apply_to(lit.statuses, load(DYING_LIGHT_PATH))
	lit.toll = 2 * _toll
	_play(load(CARD_PATH), lit)
	_play(load(CARD_PATH), lit)
	_expect_eq(lit.turn_start_energy(), 0, "...with Dying Light at Critical: 3 + 1 - 4 = 0")
	_completed += 1

func _check_tempered() -> void:
	var card: CardData = load(CARD_PATH)
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "Come Due tempers to Come Due+")
	_expect_eq([tempered.card_name, tempered.rarity, tempered.card_type], ["Come Due+", CardData.CardRarity.COMMON, CardData.CardType.SKILL], "...Common, a Skill")
	_expect_eq(tempered.description, card.description, "...the same text")
	var player: Combatant = _player()
	player.toll = _toll
	_play(tempered, player)
	_expect_eq([player.energy, _owed_label(player)], [_gain, "Owed 1"], "Come Due+: 2 Energy, owes 1")
	_completed += 1

func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 2 Energy.\nNext turn, gain 2 less.", "The face reads its rule")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view.type_label.text, "TOLL", "...labelled TOLL")
	_expect_eq(view.cost_label.text, "0", "...0 Energy")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Gain 2 Energy.\nNext turn, gain 1 less.", "Come Due+'s face")
	view.free()
	_completed += 1

# The real fight: Come Due on 5 Toll and 3 Energy - 5 Energy, "Owed 2" in
# the Wanderer's row; the next turn starts on 1, the row without it.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var overlay: Node = _field.get_node("BattleLayer").get_child(0)
		var bar: Node = overlay.get("_field_hp_bar")
		player.toll = _toll
		player.energy = player.max_energy
		var card: CardData = await _deal(controller, CARD_PATH)
		var view: CardView = _view(controller, card)
		if view != null:
			controller.call("request_play", view)
			await ProbePlay.settle(self, controller)
		_expect_eq(player.energy, player.max_energy + _gain, "Played: 5 Energy")
		_expect(_row_has(bar, "Owed 2"), "...'Owed 2' in the Wanderer's row")
		var turn: int = int(controller.get("_player_turn"))
		player.hp = player.max_hp
		controller.call("end_turn")
		var back: bool = await ProbePlay.wait_until(self, func() -> bool: return int(controller.get("_player_turn")) > turn and ProbePlay.is_settled(controller), 20.0)
		_expect(back, "The next turn comes round")
		if back:
			_expect_eq(player.energy, player.max_energy - _debt, "...on 1 Energy")
			_expect(not _row_has(bar, "Owed"), "...Owed gone from the row")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player() -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.energy = 0
	return player

func _play(card: CardData, player: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	var enemies: Array[Combatant] = [Combatant.new(100)]
	ctx.enemies = enemies
	_resolver.resolve_card(card, ctx)

# The turn-start steps that touch Energy and the debt, in
# BattleController._start_player_turn()'s order.
func _start_turn(player: Combatant) -> void:
	player.energy = player.turn_start_energy()
	Status.tick_all(player.statuses, func(_amount: int, _ticking: Status) -> void: pass)
	Status.remove_expired(player.statuses)

func _owed_label(player: Combatant) -> String:
	for active in player.statuses:
		if active.data != null and active.data.resource_path == OWED_PATH:
			return active.label()
	return ""

func _row_has(bar: Node, prefix: String) -> bool:
	for item: Dictionary in bar.get("_row_items"):
		if str(item.get("text", "")).begins_with(prefix):
			return true
	return false

func _start_fight() -> Node:
	if _run_state == null:
		_fail("no RunState autoload")
		return null
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
	var layer: Node = _field.get_node("BattleLayer")
	while layer.get_child_count() > 0 and bool((layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
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

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 3:
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
