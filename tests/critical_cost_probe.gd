extends SceneTree

# Headless probe for a cost that drops while Critical (CardData.critical_
# cost, Combatant.base_cost()): judged at the HP held now, it replaces the
# printed cost before House Key's free card, a cost reduction (Leverage)
# and a cost replacement (Collateral), never below 0. A card whose base
# is 0 while Critical takes no "next card" discount and leaves it waiting.
# Unset (-1), a card costs as it always has. In a fight the face's numeral
# and the hand's fade follow HP across the Critical line with no Energy
# change.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/critical_cost_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# No card uses critical_cost yet: every case gives an in-memory copy of a
# real card one. Rules cases read bare Combatants (max HP 80, Critical at
# 24 and under); fight cases load the real region scene and start fights
# as leverage_probe does, then play through BattleController.request_
# play() - so the commit-time spend and the faces are the game's own.
# Untyped against anything that names the RunState autoload.

const CASES := 5
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const LEVERAGE_STATUS_PATH := "res://battle/rules/statuses/leverage.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const MAX_HP := 80
# Above the Critical line, and on it (80 x 0.3 = 24).
const SAFE_HP := 50
const CRITICAL_HP := 24
const ENEMY_HP := 999
const SAFETY_SECONDS := 300.0

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

	_check_rules()
	_check_modifiers()
	await _check_commit_leaves_discounts()
	await _check_house_key()
	await _check_face_and_fade()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("critical_cost_probe: PASSED")
		quit(0)
	else:
		print("critical_cost_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

# Cost 1, Critical cost 0: 1 above the line, 0 on it - and no "next card"
# discount at 0. Unset: 1 either side. Every real card leaves it unset.
func _check_rules() -> void:
	var card: CardData = _card(1, 0)
	var plain: CardData = _card(1, -1)
	var player: Combatant = _player(SAFE_HP)
	_expect_eq([player.base_cost(card), player.energy_cost(card)], [1, 1], "Above the line: base 1, costs 1")
	_expect(player.takes_next_card_discount(card), "...and takes a next-card discount")
	player.hp = CRITICAL_HP
	_expect(player.is_critical(), "%d of %d is Critical" % [CRITICAL_HP, MAX_HP])
	_expect_eq([player.base_cost(card), player.energy_cost(card)], [0, 0], "Critical: base 0, costs 0")
	_expect(not player.takes_next_card_discount(card), "...and takes no next-card discount")
	_expect_eq([player.energy_cost(plain), player.energy_cost(_card(1, -1))], [1, 1], "Unset: 1 while Critical too")
	_expect(player.takes_next_card_discount(plain), "...and still takes a discount")
	player.hp = SAFE_HP
	_expect_eq(player.energy_cost(plain), 1, "...and 1 above the line")
	for dir in ["res://cards/data/", "res://cards/neutral/", "res://cards/tempered/"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tres"):
				var real := load(dir + file) as CardData
				if real.critical_cost >= 0:
					_expect(real.description.contains("Critical: costs %d." % real.critical_cost), "%s names its Critical cost" % real.card_name)
				else:
					_expect_eq(player.base_cost(real), real.cost, "%s: unset, its printed cost" % real.card_name)
	_completed += 1

# Leverage: 0 and left waiting while Critical; 1 - 2, floored at 0, above.
# Collateral (2 or more) judges the base: a cost-2 card with Critical cost
# 0 is covered above the line (0 Energy, 5 HP) and passes it by while
# Critical (0 Energy, no HP).
func _check_modifiers() -> void:
	var card: CardData = _card(1, 0)
	var player: Combatant = _player(SAFE_HP)
	Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
	_expect_eq(player.energy_cost(card), 0, "Leverage above the line: 1 - 2, never below 0")
	player.hp = CRITICAL_HP
	_expect_eq(player.energy_cost(card), 0, "Leverage while Critical: 0")
	_expect(not player.takes_next_card_discount(card), "...the card passing Leverage by")

	var heavy: CardData = _card(2, 0)
	var other: Combatant = _player(SAFE_HP)
	Status.apply_to(other.statuses, load(COLLATERAL_STATUS_PATH))
	_expect(other.cost_replacement_for(heavy) != null, "Collateral above the line covers a 2-cost card")
	_expect_eq([other.energy_cost(heavy), other.replaced_cost_hp(heavy)], [0, 5], "...0 Energy and 5 HP")
	other.hp = CRITICAL_HP
	_expect(other.cost_replacement_for(heavy) == null, "While Critical its base is 0: Collateral passes it by")
	_expect_eq([other.energy_cost(heavy), other.replaced_cost_hp(heavy)], [0, 0], "...0 Energy and no HP")
	_completed += 1

# --- Fight ---

# Played while Critical at 0 Energy: it plays, spends nothing, and
# Leverage and Collateral both wait. Above the line it pays 1 and spends
# Leverage.
func _check_commit_leaves_discounts() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		_set_hp(controller, CRITICAL_HP)
		Status.apply_to(player.statuses, load(LEVERAGE_STATUS_PATH))
		Status.apply_to(player.statuses, load(COLLATERAL_STATUS_PATH))
		player.energy = 0
		var card: CardData = await _deal(controller, SLASH_PATH, 1, 0)
		_expect(bool(controller.call("_is_playable", card)), "Critical at 0 Energy: playable")
		await _play(controller, card, _field_enemy(controller))
		_expect_eq(player.energy, 0, "...played for 0 Energy")
		_expect_eq(_label_of(player, "leverage"), "Leverage", "...Leverage still waiting")
		_expect(_label_of(player, "collateral") != "", "...Collateral still waiting")
		_expect_eq(player.hp, CRITICAL_HP, "...and no HP paid")
		_set_hp(controller, SAFE_HP)
		player.energy = 3
		var again: CardData = await _deal(controller, SLASH_PATH, 1, 0)
		await _play(controller, again, _field_enemy(controller))
		_expect_eq(player.energy, 3, "Above the line Leverage takes its 1: 0 Energy paid")
		_expect_eq(_label_of(player, "leverage"), "", "...and is spent")
	await _teardown()
	_completed += 1

# House Key's free card waits through a card played at 0 while Critical,
# and is spent by the next one above the line.
func _check_house_key() -> void:
	var controller: Node = await _start_fight(HOUSE_KEY_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect(player.first_card_free, "House Key: the free card ready")
		_set_hp(controller, CRITICAL_HP)
		await _play(controller, await _deal(controller, SLASH_PATH, 1, 0), _field_enemy(controller))
		_expect(player.first_card_free, "Played at 0 while Critical: the free card still waits")
		_set_hp(controller, SAFE_HP)
		await _play(controller, await _deal(controller, SLASH_PATH, 1, 0), _field_enemy(controller))
		_expect(not player.first_card_free, "...and the next one, above the line, spends it")
		_expect_eq(player.energy, 3, "...for no Energy either time")
	await _teardown()
	_completed += 1

# At 0 Energy, HP crossing the line both ways with no Energy change: the
# numeral reads 1, then 0, then 1, and the fade follows - in reach only
# while Critical.
func _check_face_and_fade() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		player.energy = 0
		controller.emit_signal("energy_changed", 0)
		var card: CardData = await _deal(controller, SLASH_PATH, 1, 0)
		var view: CardView = _view(controller, card)
		_expect_eq(_face(controller, card), "1", "Above the line the face reads 1")
		_expect(view != null and not bool(view.get("_playable")), "...faded on 0 Energy")
		_set_hp(controller, CRITICAL_HP)
		_expect_eq(_face(controller, card), "0", "Into Critical: 0")
		_expect(view != null and bool(view.get("_playable")), "...in reach, no Energy change")
		_set_hp(controller, SAFE_HP)
		_expect_eq(_face(controller, card), "1", "Healed out of it: 1 again")
		_expect(view != null and not bool(view.get("_playable")), "...faded again")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _card(cost: int, critical_cost: int) -> CardData:
	var card: CardData = (load(SLASH_PATH) as CardData).duplicate()
	card.cost = cost
	card.critical_cost = critical_cost
	return card

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	return player

# HP set and the fight told, the way any HP change tells it.
func _set_hp(controller: Node, hp: int) -> void:
	var player: Combatant = controller.get("player")
	player.hp = hp
	controller.emit_signal("hp_changed", player.hp, player.max_hp)

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, with an empty hand and 3 Energy: holding the keepsake
# at `keepsake_path` when given.
func _start_fight(keepsake_path: String = "") -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if not keepsake_path.is_empty():
		_run_state.call("equip_keepsake", load(keepsake_path))
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
	var player: Combatant = controller.get("player")
	player.max_hp = MAX_HP
	player.energy = 3
	await process_frame
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand, at `cost` and
# `critical_cost`.
func _deal(controller: Node, path: String, cost: int, critical_cost: int) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	card.cost = cost
	card.critical_cost = critical_cost
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
	await ProbePlay.settle(self, controller)

func _face(controller: Node, card: CardData) -> String:
	var view: CardView = _view(controller, card)
	return view.cost_label.text if view != null else "missing"

func _label_of(combatant: Combatant, id: String) -> String:
	for active in combatant.statuses:
		if active.data != null and active.data.id == id:
			return active.label()
	return ""

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
	print("FAIL: " + message)
