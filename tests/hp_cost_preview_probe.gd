extends SceneTree

# Headless probe for the HP-cost preview: while a card is hovered or armed
# in a fight, the HP bar shows every HP playing it will cost
# (CardBonus.predicted_self_loss()) - a pale stretch cut from the fill's
# right end, and the numeral's result after an arrow. Cases: a plain
# HP-badge card (Small Price), self-loss after the hit (Bite Down),
# Collateral paying for missing Energy, Self-Eater's price on an Attack,
# a play that crosses the Critical line, a lethal play, and a play's
# preview holding until the card has resolved and its HP has dropped.
# Every number is read from the cards' and statuses' data.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/hp_cost_preview_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const CASES := 7
const MAX_HP := 70
const SMALL_PRICE_PATH := "res://cards/data/small_price.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const HOLD_FAST_PATH := "res://cards/data/hold_fast.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const COLLATERAL_STATUS_PATH := "res://battle/rules/statuses/collateral.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"

var _run_state: Node = null
var _field: Node = null
var _controller: Node = null
var _bar: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	_run_state = root.get_node("RunState")
	_controller = await _start_fight()
	if _controller != null:
		_bar = _overlay().get("_field_hp_bar")
		await _check_plain_badge()
		await _check_bite_down()
		await _check_collateral()
		await _check_self_eater()
		await _check_crossing_critical()
		await _check_lethal()
		await _check_holds_until_hp_drops()
	if _field != null:
		_field.queue_free()
		for i in 5:
			await process_frame
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("hp_cost_preview_probe: PASSED")
		quit(0)
	else:
		print("hp_cost_preview_probe: %d FAILED" % _failures)
		quit(1)

# Small Price: its own self-loss, cut from the fill; the numeral's result.
func _check_plain_badge() -> void:
	var loss: int = _self_loss(SMALL_PRICE_PATH)
	await _set_hp(50)
	var card: CardData = await _deal(SMALL_PRICE_PATH)
	await _hover(card)
	_expect_preview(loss, 50 - loss, "Small Price at 50 HP")
	await _unhover(card)
	_expect(not bool(_bar.call("shows_cost_preview")), "...off the card: no preview")
	_completed += 1

# Bite Down: the HP it loses after its hit counts too.
func _check_bite_down() -> void:
	var loss: int = _self_loss(BITE_DOWN_PATH)
	await _set_hp(50)
	var card: CardData = await _deal(BITE_DOWN_PATH)
	await _hover(card)
	_expect_preview(loss, 50 - loss, "Bite Down at 50 HP")
	await _unhover(card)
	_completed += 1

# Collateral: no Energy, a 1-cost Slash - its Energy paid in HP.
func _check_collateral() -> void:
	var player: Combatant = _controller.get("player")
	var collateral: StatusData = load(COLLATERAL_STATUS_PATH)
	Status.apply_to(player.statuses, collateral)
	player.energy = 0
	await _set_hp(50)
	var card: CardData = await _deal(SLASH_PATH)
	var loss: int = card.cost * collateral.hp_per_missing_energy
	await _hover(card)
	_expect_preview(loss, 50 - loss, "Collateral, no Energy, Slash (%d Energy at %d HP each)" % [card.cost, collateral.hp_per_missing_energy])
	await _unhover(card)
	for status in player.statuses.duplicate():
		if (status as Status).data == collateral:
			player.statuses.erase(status)
	player.energy = 3
	_completed += 1

# Self-Eater up: an Attack pays the stance's price; a Skill doesn't.
func _check_self_eater() -> void:
	var player: Combatant = _controller.get("player")
	var ctx := EffectContext.new()
	ctx.player = player
	EffectResolver.new().resolve_card(load(SELF_EATER_PATH), ctx)
	_expect(player.stance != null, "Self-Eater's stance is up")
	var price: int = Stance.attack_hp_loss(player.stance)
	_expect(price > 0, "...with a price on Attacks (%d)" % price)
	await _set_hp(50)
	var slash: CardData = await _deal(SLASH_PATH)
	await _hover(slash)
	_expect_preview(price, 50 - price, "Self-Eater, Slash")
	await _unhover(slash)
	var small: CardData = await _deal(SMALL_PRICE_PATH)
	await _hover(small)
	_expect_preview(_self_loss(SMALL_PRICE_PATH), 50 - _self_loss(SMALL_PRICE_PATH), "Self-Eater, Small Price (a Skill: no price)")
	await _unhover(small)
	player.stance = null
	_controller.emit_signal("status_changed")
	_completed += 1

# Reaching the Critical line marks it; stopping one HP short doesn't.
func _check_crossing_critical() -> void:
	var loss: int = _self_loss(SMALL_PRICE_PATH)
	var line_hp: int = floori(MAX_HP * float(_bar.call("_target_critical_fraction")))
	var card: CardData = await _deal(SMALL_PRICE_PATH)
	await _set_hp(line_hp + loss)
	await _hover(card)
	_expect(bool(_bar.call("cost_preview_crosses_critical")), "Small Price from %d HP to %d: crosses the Critical line (%d)" % [line_hp + loss, line_hp, line_hp])
	await _unhover(card)
	await _set_hp(line_hp + loss + 1)
	await _hover(card)
	_expect(bool(_bar.call("shows_cost_preview")) and not bool(_bar.call("cost_preview_crosses_critical")), "...from %d to %d: above it, no mark" % [line_hp + loss + 1, line_hp + 1])
	await _unhover(card)
	await _set_hp(line_hp - 1 + loss)
	await _hover(card)
	_expect(not bool(_bar.call("cost_preview_crosses_critical")), "...already Critical: no crossing")
	await _unhover(card)
	_completed += 1

# Bite Down at its own self-loss in HP: the result is 0, the whole fill
# previewed.
func _check_lethal() -> void:
	var loss: int = _self_loss(BITE_DOWN_PATH)
	await _set_hp(loss)
	var card: CardData = await _deal(BITE_DOWN_PATH)
	await _hover(card)
	_expect_preview(loss, 0, "Bite Down at %d HP: lethal" % loss)
	await _set_hp(maxi(loss - 1, 1))
	_expect_eq(int(_bar.call("get_cost_preview_result")), 0, "...at less HP than it costs: still 0, the loss clamped to the HP held")
	_expect_eq(int(_bar.call("get_cost_preview")), maxi(loss - 1, 1), "...the preview the HP held")
	await _unhover(card)
	_completed += 1

# Hold Fast played: the preview holds its result while the card resolves
# and its HP lands - never re-read off the lower HP - and goes once the
# play has resolved.
func _check_holds_until_hp_drops() -> void:
	var loss: int = _self_loss(HOLD_FAST_PATH)
	await _set_hp(50)
	var card: CardData = await _deal(HOLD_FAST_PATH)
	await _hover(card)
	_expect_preview(loss, 50 - loss, "Hold Fast at 50 HP")
	var at_impact: Array[int] = []
	var at_drop: Array[int] = []
	var at_resolved: Array[int] = []
	var on_impact := func(_c: CardData) -> void: at_impact.append(int(_bar.call("get_cost_preview_result")))
	var on_drop := func(_hp: int, _max: int) -> void: at_drop.append(int(_bar.call("get_cost_preview_result")))
	var on_resolved := func(_c: CardData) -> void: at_resolved.append(int(_bar.call("get_cost_preview")))
	_controller.connect("card_impact", on_impact)
	_controller.connect("hp_changed", on_drop)
	_controller.connect("play_resolved", on_resolved)
	_controller.call("request_play", _view(card))
	await ProbePlay.settle(self, _controller)
	_controller.disconnect("card_impact", on_impact)
	_controller.disconnect("hp_changed", on_drop)
	_controller.disconnect("play_resolved", on_resolved)
	var player: Combatant = _controller.get("player")
	_expect_eq(player.hp, 50 - loss, "Hold Fast played: %d HP lost" % loss)
	_expect_eq(at_impact, [50 - loss] as Array[int], "...at its impact, the preview still leads to %d" % (50 - loss))
	_expect(not at_drop.is_empty() and at_drop.all(func(r: int) -> bool: return r == 50 - loss), "...as its HP drops, still %d - not re-read off the lower HP (%s)" % [50 - loss, str(at_drop)])
	_expect_eq(at_resolved, [0] as Array[int], "...once it has resolved, gone")
	_expect(not bool(_bar.call("shows_cost_preview")), "...and nothing previewed after")
	_completed += 1

# --- Helpers ---

func _expect_preview(loss: int, result: int, label: String) -> void:
	var card: CardData = _overlay().get("_cost_focus")
	var ctx: EffectContext = _controller.call("preview_context")
	_expect_eq(CardBonus.predicted_self_loss(card, ctx), loss, "%s: predicted_self_loss" % label)
	_expect_eq(int(_bar.call("get_cost_preview")), loss, "...the bar previews %d HP" % loss)
	_expect_eq(int(_bar.call("get_cost_preview_result")), result, "...the numeral reads → %d" % result)
	_expect(bool(_bar.call("shows_cost_preview")), "...and the preview shows")

# The card's own SELF_DAMAGE / SELF_DAMAGE_TOLL values, from its data.
func _self_loss(path: String) -> int:
	var total: int = 0
	for effect in (load(path) as CardData).effects:
		if effect != null and (effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL):
			total += effect.value
	return total

func _set_hp(hp: int) -> void:
	var player: Combatant = _controller.get("player")
	player.max_hp = MAX_HP
	player.hp = hp
	_run_state.set("player_max_hp", MAX_HP)
	_run_state.set("player_hp", hp)
	_run_state.emit_signal("player_hp_changed", hp, MAX_HP)
	_controller.emit_signal("hp_changed", hp, MAX_HP)
	await process_frame

func _hover(card: CardData) -> void:
	_view(card).set_hovered(true)
	for i in 10:
		await process_frame

func _unhover(card: CardData) -> void:
	var view: CardView = _view(card)
	if view != null:
		view.set_hovered(false)
	for i in 10:
		await process_frame

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
	var layer: Node = _field.get_node("BattleLayer")
	while layer.get_child_count() > 0 and bool((layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = 999
		enemy.hp = 999
	var player: Combatant = controller.get("player")
	player.energy = 3
	controller.get("deck").call("discard_hand")
	await process_frame
	return controller

func _overlay() -> Node:
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _deal(path: String) -> CardData:
	var deck: Object = _controller.get("deck")
	deck.call("discard_hand")
	var card: CardData = (load(path) as CardData).duplicate()
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	for i in 5:
		await process_frame
	return card

func _view(card: CardData) -> CardView:
	for view: CardView in _controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
