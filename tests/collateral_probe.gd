extends SceneTree

# Headless probe for Collateral - 0 Energy, Uncommon Skill, Spent: "This
# turn, pay 3 HP for each Energy you lack." (StatusData.hp_per_missing_
# energy, ends_at_turn_end). A card costing more Energy than is held -
# after Leverage's discount - takes all the Energy there is and 3 HP for
# each short, paid before its effects through the self-loss path (past
# Block, 1 Toll a point, no Grace); Energy enough, nothing changes. A card
# whose HP would leave 0 can't be played. The faces carry the live "-N HP"
# and the shared HP-paid helper counts it (a Critical face goes live on
# it). Collateral+ charges 2.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/collateral_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases read the data; fight cases load the real region scene and
# start fights through RegionField's contact handler, then play real
# cards through BattleController.request_play() / confirm_target() - so
# the commit, the payment and the faces are the game's own. Each case
# discards the hand and deals itself fresh copies of the cards it needs.
# Untyped against anything that names the RunState autoload.

const CASES := 9
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const COLLATERAL_PATH := "res://cards/data/collateral.tres"
const TEMPERED_PATH := "res://cards/tempered/collateral_tempered.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const LEVERAGE_PATH := "res://cards/data/leverage.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const LAST_WAGER_PATH := "res://cards/data/last_wager.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _lost: bool = false
var _rate: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_rate = (load(COLLATERAL_STATUS_PATH) as StatusData).hp_per_missing_energy

	_check_data()
	_check_rules()
	await _check_enough_energy()
	await _check_shortfall()
	await _check_leverage_first()
	await _check_turn_long()
	await _check_last_hp_refused()
	await _check_critical_entry()
	await _check_faces()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("collateral_probe: PASSED")
		quit(0)
	else:
		print("collateral_probe: %d FAILED" % _failures)
		quit(1)

# --- Data and rules ---

func _check_data() -> void:
	var card: CardData = load(COLLATERAL_PATH)
	var status: StatusData = load(COLLATERAL_STATUS_PATH)
	_expect_eq([card.cost, card.card_type, card.rarity, card.removal_scope], [0, CardData.CardType.SKILL, CardData.CardRarity.UNCOMMON, CardData.RemovalScope.SPENT], "Collateral: 0 Energy, a Skill, Uncommon, Spent")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...with mipmapped art")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect_eq(card.description, "This turn, pay {hp_per_energy} HP for each Energy you lack.\nSpent.", "The card's text, its number from data")
	_expect_eq([status.hp_per_missing_energy, status.default_charges, status.ends_at_turn_end, status.default_duration_turns], [3, 0, true, StatusData.DURATION_UNTIL_REMOVED], "The status: 3 HP an Energy, no charges, for the turn")
	var statuses: Array[Status] = []
	Status.apply_to(statuses, status)
	_expect_eq(statuses[0].label(), "Collateral", "Its line reads Collateral")
	_expect_eq(statuses[0].describe(), "This turn, pay 3 HP for each Energy you lack.", "...and the reveal")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Collateral+")
	_expect_eq([tempered.cost, tempered.removal_scope, tempered.description, tempered.effects[0].status_data.hp_per_missing_energy], [0, CardData.RemovalScope.SPENT, card.description, 2], "Collateral+: the same card at 2 HP an Energy")
	_completed += 1

# On bare fighters: 2 short of Reckoning's 2 at 0 Energy is 6 HP, at 1
# Energy 3; enough Energy, none. Collateral+ at 2 an Energy; both up, the
# cheaper. Can't pay what would leave 0 HP.
func _check_rules() -> void:
	var reckoning: CardData = load(RECKONING_PATH)
	var player := Combatant.new(70)
	player.energy = 0
	_expect(not player.can_pay(reckoning), "No Collateral, 0 Energy: Reckoning can't be paid")
	Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
	_expect_eq([player.energy_cost(reckoning), player.replaced_cost_hp(reckoning)], [0, 2 * _rate], "Collateral, 0 Energy: Reckoning is 0 Energy and 6 HP")
	player.energy = 1
	_expect_eq([player.energy_cost(reckoning), player.replaced_cost_hp(reckoning)], [1, _rate], "...1 Energy: 1 and 3 HP")
	player.energy = 3
	_expect_eq([player.energy_cost(reckoning), player.replaced_cost_hp(reckoning)], [2, 0], "...3 Energy: its 2, no HP")
	player.energy = 0
	Status.apply_to(player.statuses, (load(TEMPERED_PATH) as CardData).effects[0].status_data)
	_expect_eq(player.replaced_cost_hp(reckoning), 4, "Collateral and Collateral+ both up: the cheaper, 2 an Energy")
	var low := Combatant.new(70)
	low.energy = 0
	Status.apply_to(low.statuses, load(COLLATERAL_STATUS_PATH))
	low.hp = 6
	_expect(not low.can_pay(reckoning), "6 HP, 6 to pay: can't - it would leave 0")
	low.hp = 7
	_expect(low.can_pay(reckoning), "7 HP: it leaves 1, so it can")
	_completed += 1

# --- Fights ---

# Collateral on 3 Energy, then Reckoning: its 2 Energy, no HP.
func _check_enough_energy() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var collateral: CardData = await _deal(controller, COLLATERAL_PATH)
		await _play(controller, collateral)
		_expect_eq(player.energy, 3, "Collateral costs no Energy")
		_expect((controller.get("deck").get("exhaust_pile") as Array).has(collateral), "...and is Spent")
		_expect_eq(_status_label(player), "Collateral", "...leaving Collateral")
		var hp: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq([player.energy, hp - player.hp], [1, 0], "Energy enough: Reckoning takes its 2, no HP")
	await _teardown()
	_completed += 1

# On 1 Energy, 5 Block and Toll 0: Reckoning takes the 1 and 3 HP - past
# the Block, 3 Toll made, no Grace - and keeps that Toll: it spends none.
func _check_shortfall() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		player.energy = 1
		player.block = 5
		player.toll = 0
		var hp: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 0, "1 Energy short: Reckoning takes the 1")
		_expect_eq(hp - player.hp, _rate, "...and 3 HP")
		_expect_eq(player.block, 5, "...past the Block")
		_expect_eq(player.grace, 0, "...opening no Grace")
		_expect_eq(player.toll, _rate, "...its 3 Toll made and kept: Reckoning spends none")
	await _teardown()
	_completed += 1

# Leverage's discount comes off first: at 0 Energy a Reckoning under
# Leverage costs nothing at all; a 3-cost card under it is 1 short, 3 HP.
func _check_leverage_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		player.toll = 5
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		player.energy = 0
		var hp: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(hp - player.hp, 0, "Leverage takes Reckoning to 0: no HP")
		player.toll = 5
		await _play(controller, await _deal(controller, LEVERAGE_PATH))
		hp = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH, 3), _field_enemy(controller))
		_expect_eq(hp - player.hp, _rate, "A 3-cost under Leverage at 0 Energy: 1 short, 3 HP")
	await _teardown()
	_completed += 1

# Every short card this turn pays: two Slashes at 0 Energy, 3 HP each.
# The turn ends, Collateral with it: the next turn's Slash takes Energy.
func _check_turn_long() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		player.energy = 0
		var hp: int = player.hp
		await _play(controller, await _deal(controller, SLASH_PATH), _field_enemy(controller))
		await _play(controller, await _deal(controller, SLASH_PATH), _field_enemy(controller))
		_expect_eq(hp - player.hp, 2 * _rate, "Two Slashes at 0 Energy: 3 HP each")
		_expect_eq(_status_label(player), "Collateral", "...Collateral still up")
		player.hp = player.max_hp
		await controller.call("end_turn")
		_expect_eq(_status_label(player), "", "The turn ends, and Collateral with it")
		controller.get("deck").call("discard_hand")
		player.energy = 0
		await process_frame
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_expect(not player.can_pay(slash), "...the next turn a Slash at 0 Energy can't be paid")
	await _teardown()
	_completed += 1

# 3 HP and 0 Energy: a Slash would take the 3 and leave 0 - not
# playable, faded, and a play request does nothing. At 4 it can.
func _check_last_hp_refused() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		player.energy = 0
		player.hp = _rate
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_expect(not bool(controller.call("_is_playable", slash)), "At 3 HP a short Slash costing 3 can't be played")
		_expect(not controller.get("_hand_container").call("_can_play", slash, player.energy), "...the hand fades it")
		controller.call("request_play", _view(controller, slash))
		await process_frame
		_expect(not bool(controller.call("is_awaiting_target")) and player.hp == _rate, "...and a play request does nothing")
		player.hp = _rate + 1
		_expect(bool(controller.call("_is_playable", slash)), "At 4 it can: it leaves 1")
	await _teardown()
	_completed += 1

# The shortfall's HP is self-loss like any: at 30 of 80, two short of
# Reckoning is 6 HP - into Critical (24), and the Critical-entry Block
# fires.
func _critical_entry_trinket() -> TrinketData:
	var trinket := TrinketData.new()
	trinket.id = &"probe_critical_entry"
	trinket.display_name = "Probe Critical Entry"
	trinket.critical_entry_block = 6
	return trinket

func _check_critical_entry() -> void:
	var controller: Node = await _start_fight(-1, "", _critical_entry_trinket())
	if controller != null:
		var player: Combatant = controller.get("player")
		player.hp = int(player.max_hp * player.critical_fraction()) + 2 * _rate
		_expect(not player.is_critical(), "At %d of %d HP the Wanderer is out of Critical" % [player.hp, player.max_hp])
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		player.energy = 0
		var block_before: int = player.block
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect(player.is_critical(), "The 6 HP takes him into Critical")
		_expect_eq(player.block - block_before, 6, "...and the Critical-entry hook's 6 Block fires")
	await _teardown()
	_completed += 1

# Faces: on 3 Energy under Collateral Reckoning reads 2, no HP line; on 1,
# "1" and "-3 HP", Blood Arc (made to cost 2) its own loss plus 3, Slash
# untouched. Last Wager 1 short just above the Critical line reads its
# Critical half live - the shared HP-paid helper counts the 3 - and the
# play sound's check counts what the play pays.
func _check_faces() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var blood_arc: CardData = await _deal(controller, BLOOD_ARC_PATH, 2)
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var own_loss: int = _self_damage(blood_arc)
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		_expect_eq(_face(controller, reckoning), ["2", ""], "On 3 Energy under Collateral, Reckoning reads 2, no HP line")
		player.energy = 1
		controller.emit_signal("energy_changed", 1)
		await process_frame
		_expect_eq(_face(controller, reckoning), ["1", "−%d HP" % _rate], "...on 1 Energy, 1 and −3 HP")
		_expect_eq(_face(controller, blood_arc), ["1", "−%d HP" % (own_loss + _rate)], "...Blood Arc 1 and its own loss plus 3")
		_expect_eq(_face(controller, slash), ["1", ""], "...Slash untouched")
		player.energy = 0
		player.hp = int(player.max_hp * player.critical_fraction()) + _rate
		controller.emit_signal("energy_changed", 0)
		controller.emit_signal("hp_changed", player.hp, player.max_hp)
		await process_frame
		var wager: CardData = await _deal(controller, LAST_WAGER_PATH)
		var view: CardView = _view(controller, wager)
		_expect(view != null and view.get("_bonus_state") == CardBonus.State.LIVE, "Last Wager 1 short at %d HP: its Critical half live, the 3 counted" % player.hp)
		controller.set("play_hp_cost", _rate)
		var overlay: Node = _field.get_node("BattleLayer").get_child(0)
		var ctx: EffectContext = controller.call("preview_context")
		_expect(CardBonus.state(wager, ctx.for_card_preview(CardBonus.upfront_hp_cost(wager, player.stance, int(controller.get("play_hp_cost"))))) == CardBonus.State.LIVE, "...and the play sound's reading counts the HP the play pays")
		_expect(overlay != null, "...(the overlay is up)")
	await _teardown()
	_completed += 1

# --- Helpers ---

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, with an empty hand and 3 Energy: at `hp` when given,
# holding the keepsake at `keepsake_path` when given.
func _start_fight(hp: int = -1, keepsake_path: String = "", keepsake: TrinketData = null) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if not keepsake_path.is_empty():
		_run_state.call("equip_keepsake", load(keepsake_path))
	if keepsake != null:
		_run_state.call("equip_keepsake", keepsake)
	if hp > 0:
		_run_state.set("player_hp", hp)
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

# A fresh copy of the card at `path`, drawn into the hand - at `cost`
# when one is given.
func _deal(controller: Node, path: String, cost: int = -1) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	if cost >= 0:
		card.cost = cost
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
	await ProbePlay.settle(self, controller, func() -> bool: return _lost)

func _face(controller: Node, card: CardData) -> Array:
	var view: CardView = _view(controller, card)
	if view == null:
		return ["missing", "missing"]
	return [view.cost_label.text, view.hp_cost_label.text if view.hp_cost_label.visible else ""]

func _rules_text(controller: Node, card: CardData) -> String:
	var view: CardView = _view(controller, card)
	return view.rules_text.get_parsed_text() if view != null else ""

func _self_damage(card: CardData) -> int:
	var total: int = 0
	for effect in card.effects:
		if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
			total += effect.value
	return total

func _status_label(player: Combatant) -> String:
	for active in player.statuses:
		if active.data != null and active.data.id == "collateral":
			return active.label()
	return ""

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
