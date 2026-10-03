extends SceneTree

# Headless probe for Collateral - the card, its status and the cost
# replacement behind them (StatusData.replaces_cost_at_least): while a
# charge waits, the next card whose Energy cost (after House Key's free
# card) is 2 or more costs 0 Energy and 5 HP instead, paid before its
# effects through the self-loss path, and spends the charge.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/collateral_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases read the data; fight cases load the real region scene and
# start fights through RegionField's contact handler, as trinket_probe
# does, then play real cards through BattleController.request_play() /
# confirm_target() - so the commit-time charge spend, the payment and the
# faces are the game's own. Each case discards the hand and deals itself
# fresh copies of the cards it needs. Death comes last: a defeat changes
# the scene. Untyped against anything that names the RunState autoload.

const CASES := 9
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const COLLATERAL_PATH := "res://cards/data/collateral.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const BLUE_FASTENER_PATH := "res://run/keepsakes/keeper/blue_fastener.tres"
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _lost: bool = false

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	await _check_reckoning()
	await _check_cheap_cards_pass()
	await _check_persists_then_ends()
	await _check_two_charges()
	await _check_house_key_first()
	await _check_critical_entry()
	await _check_faces()
	await _check_payment_kills()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("collateral_probe: PASSED")
		quit(0)
	else:
		print("collateral_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(COLLATERAL_PATH)
	var status: StatusData = load(COLLATERAL_STATUS_PATH)
	_expect_eq(card.cost, 0, "Collateral costs 0")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...and Spent")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...with mipmapped art")
	_expect((load(POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect_eq(card.description, "The next card you play costing %d or more costs %d HP instead of Energy.\nSpent." % [status.replaces_cost_at_least, status.replacement_hp_cost], "The card's text carries the status's own numbers")
	_expect_eq([status.replaces_cost_at_least, status.replacement_hp_cost, status.default_charges], [2, 5, 1], "The status: 2 or more, 5 HP, 1 charge")
	var statuses: Array[Status] = []
	Status.apply_to(statuses, status)
	_expect_eq(statuses[0].label(), "Collateral ×1", "One play: the line reads Collateral ×1")
	_expect_eq(statuses[0].describe(), "Pay 5 HP instead of Energy for your next 1 card costing 2 or more.", "...and the reveal, singular")
	Status.apply_to(statuses, status)
	_expect_eq(statuses.size(), 1, "A second play adds to the same status")
	_expect_eq(statuses[0].label(), "Collateral ×2", "...Collateral ×2")
	_expect_eq(statuses[0].describe(), "Pay 5 HP instead of Energy for your next 2 cards costing 2 or more.", "...and the reveal, plural")
	_completed += 1

# --- Fights ---

# Collateral, then Reckoning: 0 Energy for both, 5 HP and 5 Toll from the
# payment, and Reckoning spends that Toll with the rest.
func _check_reckoning() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.toll = 3
		var collateral: CardData = await _deal(controller, COLLATERAL_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		await _play(controller, collateral)
		_expect_eq(player.energy, 3, "Collateral costs no Energy")
		# Spent once its fly-out lands (BattleController._on_play_animation_
		# finished()).
		var exhaust: Array = controller.get("deck").get("exhaust_pile")
		for i in 180:
			if exhaust.has(collateral):
				break
			await process_frame
		_expect(exhaust.has(collateral), "...and is Spent")
		_expect_eq(_status_label(player), "Collateral ×1", "...leaving Collateral ×1")
		var enemy: Combatant = _enemy(controller)
		var hp_before: int = player.hp
		var enemy_before: int = enemy.hp + enemy.block
		await _play(controller, reckoning, _field_enemy(controller))
		_expect_eq(player.energy, 3, "Reckoning under Collateral costs 0 Energy")
		_expect_eq(hp_before - player.hp, 5, "...and 5 HP")
		_expect_eq(enemy_before - (enemy.hp + enemy.block), 3 + 5, "...and deals the 3 Toll held plus the 5 its payment made")
		_expect_eq(player.toll, 0, "...spending all of it")
		_expect_eq(_status_label(player), "", "The charge is spent")
	await _teardown()
	_completed += 1

# A card costing 0 or 1 passes the charge by: its own Energy, no HP.
func _check_cheap_cards_pass() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var hp_before: int = player.hp
		await _play(controller, slash, _field_enemy(controller))
		_expect_eq(player.energy, 2, "A 1-cost card costs its 1 Energy")
		_expect_eq(player.hp, hp_before, "...and no HP")
		_expect_eq(_status_label(player), "Collateral ×1", "...and leaves the charge waiting")
	await _teardown()
	_completed += 1

# The charge waits through a whole enemy turn, and the next fight starts
# without it.
func _check_persists_then_ends() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		await controller.call("end_turn")
		_expect_eq(_status_label(player), "Collateral ×1", "The charge is still there next turn")
	await _teardown()
	controller = await _start_fight()
	if controller != null:
		_expect_eq(_status_label(controller.get("player")), "", "...and the next fight starts without it")
	await _teardown()
	_completed += 1

# Two plays, two charges: two covered cards, then the usual cost again.
func _check_two_charges() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		_expect_eq(_status_label(player), "Collateral ×2", "Two Collaterals: two charges")
		var hp_before: int = player.hp
		for i in 2:
			await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 3, "Two covered Reckonings cost no Energy")
		_expect_eq(hp_before - player.hp, 10, "...and 5 HP each")
		_expect_eq(_status_label(player), "", "...spending both charges")
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 1, "The third costs its 2 Energy again")
	await _teardown()
	_completed += 1

# House Key's free first card costs 0 before Collateral is asked, so it
# isn't covered and keeps the charge; the next one uses it. (In play the
# Collateral card would itself be the free first card - the status is
# applied directly here to reach the ordering.)
func _check_house_key_first() -> void:
	var controller: Node = await _start_fight(-1, HOUSE_KEY_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
		var hp_before: int = player.hp
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.energy, 3, "House Key's free Reckoning costs 0 Energy")
		_expect_eq(player.hp, hp_before, "...and no HP")
		_expect_eq(_status_label(player), "Collateral ×1", "...and keeps the charge")
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(hp_before - player.hp, 5, "The next Reckoning takes the charge: 5 HP")
		_expect_eq(player.energy, 3, "...and 0 Energy")
	await _teardown()
	_completed += 1

# Blue Fastener: the payment that crosses into Critical fires the entry
# Block, as any self-inflicted loss does.
func _check_critical_entry() -> void:
	var controller: Node = await _start_fight(25, BLUE_FASTENER_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(not player.is_critical(), "At 25 of 70 HP the Wanderer is out of Critical")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		var block_before: int = player.block
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect(player.is_critical(), "The 5 HP takes him into Critical")
		_expect_eq(player.block - block_before, 6, "...and Blue Fastener's 6 Block fires")
	await _teardown()
	_completed += 1

# Faces while the charge waits, and after it's spent: a covered card
# reads 0 and the payment on its "-N HP" line. Blood Arc's own loss is
# upfront, so it's the badge's alone - its text never names it.
func _check_faces() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		var blood_arc: CardData = await _deal(controller, BLOOD_ARC_PATH)
		var slash: CardData = await _deal(controller, SLASH_PATH)
		var own_loss: int = _self_damage(blood_arc)
		_expect_eq(_face(controller, reckoning), ["2", ""], "Before Collateral, Reckoning reads 2 and no HP line")
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		_expect_eq(_face(controller, reckoning), ["0", "−5 HP"], "With a charge waiting, Reckoning reads 0 and −5 HP")
		_expect_eq(_face(controller, blood_arc), ["0", "−%d HP" % (own_loss + 5)], "...Blood Arc 0 and its own loss plus 5")
		_expect(not _rules_text(controller, blood_arc).contains("HP"), "...while its text names no HP: the badge carries it all")
		_expect_eq(_face(controller, slash), ["1", ""], "...and Slash is untouched")
		await _play(controller, reckoning, _field_enemy(controller))
		_expect_eq(_face(controller, blood_arc), ["2", "−%d HP" % own_loss], "Once spent, Blood Arc reads 2 and its own loss again")
	await _teardown()
	_completed += 1

# At 4 HP a covered Reckoning's payment kills: 0 HP, its effects skipped
# (no blow, no Toll spent), and the fight ends as a defeat. Last - the
# defeat changes the scene.
func _check_payment_kills() -> void:
	var controller: Node = await _start_fight(4)
	if controller != null:
		var player: Combatant = controller.get("player")
		controller.connect("battle_lost", func() -> void: _lost = true)
		await _play(controller, await _deal(controller, COLLATERAL_PATH))
		var enemy: Combatant = _enemy(controller)
		var enemy_before: int = enemy.hp + enemy.block
		await _play(controller, await _deal(controller, RECKONING_PATH), _field_enemy(controller))
		_expect_eq(player.hp, 0, "At 4 HP, Collateral's 5 leaves 0")
		_expect_eq(enemy.hp + enemy.block, enemy_before, "...and Reckoning's blow never lands")
		_expect_eq(player.toll, 4, "...nor does it spend the 4 Toll the loss made")
		_expect(_lost, "...and the fight ends as a defeat")
	_completed += 1

# --- Helpers ---

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, with an empty hand and 3 Energy: at `hp` when given,
# holding the keepsake at `keepsake_path` when given.
func _start_fight(hp: int = -1, keepsake_path: String = "") -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if not keepsake_path.is_empty():
		_run_state.call("equip_keepsake", load(keepsake_path))
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

# A fresh copy of the card at `path`, drawn into the hand.
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
	for i in 600:
		await process_frame
		if _lost or not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

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
