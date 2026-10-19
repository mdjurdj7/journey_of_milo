extends SceneTree

# Headless probe for Second Swing: Deal 6; holding 5 Toll, spend it and
# the hit lands again - a second hit of the same card, not a second play.
# Under 5 Toll one hit and nothing spent, and the card is never blocked;
# 5 or more, two hits and exactly 5 spent; a first hit that kills skips
# the repeat and spends nothing. Under Self-Eater both hits take its +3
# (its HP paid once); Keen's one-shot +3 goes to the first hit only, and
# Come Due's mark to each hit, a charge apiece - a mark with one charge
# left pays the first hit and the repeat lands bare. Played into the Greyshelf's Gape, one Goaded stack, not
# two. Its art loads mipmapped, its face reads its live number and its
# text fits at the first rules size. Played for real, the repeat is a
# blow of its own: two damage events second_swing_delay apart, the HP bar
# dropping twice, two numbers - the second at repeat_number_offset - the
# Toll readout dropping between them, and input locked until the second
# lands. Rules cases on the real .tres; the Gape and two-blow cases load
# floor 5 and play the card through BattleController.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/second_swing_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 11
const CARD_PATH := "res://cards/data/second_swing.tres"
const ART_PATH := "res://cards/art/Wanderer/Second Swing.png"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const COME_DUE_PATH := "res://cards/data/come_due.tres"
const KEEN_PATH := "res://battle/rules/statuses/keen.tres"
const POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const GOADED_PATH := "res://battle/rules/statuses/goaded.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const FLOOR_5 := 4
const PLAYER_HP := 999
const ENEMY_HP := 100
const HIT := 6
const REPEAT_TOLL := 5
const SELF_EATER_BONUS := 3
const SELF_EATER_PRICE := 2
const KEEN_BONUS := 3
const MARK_BONUS := 4
const FIRST_RULES_SIZE := 15
const NUMBER_SLACK_PX := 1.5

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	_check_card_data()
	_check_under_toll()
	_check_at_toll()
	_check_kill_skips_repeat()
	_check_self_eater()
	_check_one_shots_first_hit_only()
	_check_pools()
	await _check_face()
	await _check_art()
	await _check_gape_goaded_once()
	await _check_two_blows()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("second_swing_probe: PASSED")
		quit(0)
	else:
		print("second_swing_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var card: CardData = _card()
	_expect_eq(card.card_name, "Second Swing", "The card is named Second Swing")
	_expect_eq(card.rarity, CardData.CardRarity.COMMON, "...is Common")
	_expect_eq(card.cost, 1, "...costs 1")
	_expect_eq(card.card_type, CardData.CardType.ATTACK, "...is an Attack")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect_eq(card.description, "Deal {damage} damage.\nSpend 5 Toll to repeat.", "...its text")
	_expect_eq(card.effects.size(), 1, "...one effect")
	if card.effects.size() == 1:
		var effect: CardEffect = card.effects[0]
		_expect(effect.effect_type == CardEffect.EffectType.DAMAGE and effect.value == HIT and effect.repeat_toll_cost == REPEAT_TOLL, "...DAMAGE 6, repeated for 5 Toll")
		_expect_eq(effect.condition, CardEffect.Condition.NONE, "...unconditional: the first hit always lands")
	_expect_eq(card.battle_animation, &"Slash", "...swings Slash's clip")
	_expect_eq(card.impact_time, 0.55, "...at Slash's impact time")
	_completed += 1

# 4 Toll: one hit of 6, nothing spent - and 0 Toll never blocks the play.
func _check_under_toll() -> void:
	var player: Combatant = _player()
	_expect(not EffectResolver.card_blocked(_card(), player), "Playable on 0 Toll")
	player.toll = REPEAT_TOLL - 1
	_expect(not EffectResolver.card_blocked(_card(), player), "...and on 4")
	var enemy := Combatant.new(ENEMY_HP)
	var ctx: EffectContext = _play(player, [enemy])
	_expect_eq(ENEMY_HP - enemy.hp, HIT, "4 Toll: one hit of 6")
	_expect_eq(player.toll, REPEAT_TOLL - 1, "...no Toll spent")
	_expect(not ctx.toll_spent_this_card, "...the card spent no Toll")
	_completed += 1

# 5 Toll: two hits of 6, 5 spent; 9: the same, 4 left. Each hit meets
# block on its own.
func _check_at_toll() -> void:
	for held in [REPEAT_TOLL, 9]:
		var player: Combatant = _player()
		player.toll = held
		var enemy := Combatant.new(ENEMY_HP)
		var hits: Array[int] = []
		var ctx: EffectContext = _ctx(player, [enemy])
		ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
			if target == enemy and kind == "card":
				hits.append(amount)
		_resolver.resolve_card(_card(), ctx)
		_expect_eq(hits, [HIT, HIT] as Array[int], "%d Toll: two hits of 6" % held)
		_expect_eq(player.toll, held - REPEAT_TOLL, "...5 Toll spent")
		_expect(ctx.toll_spent_this_card, "...the card spent Toll")
	var player: Combatant = _player()
	player.toll = REPEAT_TOLL
	var blocker := Combatant.new(ENEMY_HP)
	blocker.block = 8
	_play(player, [blocker])
	_expect_eq(ENEMY_HP - blocker.hp, 4, "8 Block: the first hit spends it (6), the second takes 2 of its 6, 4 to HP")
	_completed += 1

# A first hit that kills skips the repeat: nothing spent.
func _check_kill_skips_repeat() -> void:
	var player: Combatant = _player()
	player.toll = 10
	var enemy := Combatant.new(5)
	var ctx: EffectContext = _play(player, [enemy])
	_expect(enemy.hp <= 0, "A 5 HP enemy dies to the first hit")
	_expect_eq(player.toll, 10, "...no repeat, no Toll spent")
	_expect(not ctx.toll_spent_this_card, "...the card spent no Toll")
	_completed += 1

# Self-Eater: both hits get +3; its 2 HP is paid once - and the Toll that
# price accrues counts, being paid before the first hit.
func _check_self_eater() -> void:
	var player: Combatant = _player()
	_resolver.resolve_card(load(SELF_EATER_PATH) as CardData, _ctx(player, []))
	_expect(player.stance != null, "Self-Eater taken")
	player.toll = REPEAT_TOLL
	var enemy := Combatant.new(ENEMY_HP)
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		if target == enemy and kind == "card":
			hits.append(amount)
	var hp_before: int = player.hp
	_resolver.resolve_card(_card(), ctx)
	_expect_eq(hits, [HIT + SELF_EATER_BONUS, HIT + SELF_EATER_BONUS] as Array[int], "Under Self-Eater: two hits of 9")
	_expect_eq(hp_before - player.hp, SELF_EATER_PRICE, "...its 2 HP paid once")
	_expect_eq(player.toll, REPEAT_TOLL + SELF_EATER_PRICE - REPEAT_TOLL, "...5 spent of the 7 held after the price")
	var short: Combatant = _player()
	_resolver.resolve_card(load(SELF_EATER_PATH) as CardData, _ctx(short, []))
	short.toll = REPEAT_TOLL - SELF_EATER_PRICE
	var other := Combatant.new(ENEMY_HP)
	_play(short, [other])
	_expect_eq(ENEMY_HP - other.hp, 2 * (HIT + SELF_EATER_BONUS), "3 Toll and Self-Eater's 2: 5 at the first hit - it repeats")
	_expect_eq(short.toll, 0, "...and spends all 5")
	_completed += 1

# Keen's charge (+3 on the next Attack) goes to the first hit; Come Due's
# mark (+4) to both, a charge each - 13, then 10, one charge left. A mark
# down to its last charge: 10, then the bare 6, and the mark gone.
func _check_one_shots_first_hit_only() -> void:
	var player: Combatant = _player()
	Status.apply_to(player.statuses, load(KEEN_PATH) as StatusData)
	var enemy := Combatant.new(ENEMY_HP)
	player.toll = 5
	_resolver.resolve_card(load(COME_DUE_PATH) as CardData, _ctx(player, [enemy]))
	_expect_eq(player.toll, 0, "Come Due spent its 5")
	player.toll = REPEAT_TOLL
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		if target == enemy and kind == "card":
			hits.append(amount)
	_resolver.resolve_card(_card(), ctx)
	_expect_eq(hits, [HIT + KEEN_BONUS + MARK_BONUS, HIT + MARK_BONUS] as Array[int], "Keen and the mark: 13 on the first hit, 10 on the second")
	_expect(Status.find_in(player.statuses, load(KEEN_PATH) as StatusData) == null, "...Keen's one charge spent")
	_expect_eq(_mark_charges(enemy), 1, "...two charges of the mark spent, one a hit")

	# The mark's last charge: the first hit takes it, the repeat lands bare.
	hits.clear()
	player.toll = REPEAT_TOLL
	ctx = _ctx(player, [enemy])
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		if target == enemy and kind == "card":
			hits.append(amount)
	_resolver.resolve_card(_card(), ctx)
	_expect_eq(hits, [HIT + MARK_BONUS, HIT] as Array[int], "One charge left: 10 on the first hit, the bare 6 on the second")
	_expect_eq(_mark_charges(enemy), 0, "...and the mark gone")
	_completed += 1

func _check_pools() -> void:
	for path in [POOL_PATH, COLLECTOR_POOL_PATH]:
		var pool: RewardPool = load(path) as RewardPool
		var found: bool = false
		for entry in pool.entries:
			if entry != null and entry.resource_path == CARD_PATH:
				found = true
		_expect(found, "In %s" % path.get_file())
	_completed += 1

# Out of a fight the face reads its rule, and its text sits at the first
# rules size - it fits without stepping down. In a battle hand under
# Self-Eater the number is the hit's, 9.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(_card())
	_expect_eq(view.rules_text.get_parsed_text(), "Deal 6 damage.\nSpend 5 Toll to repeat.", "The face reads its rule")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), FIRST_RULES_SIZE, "...at the first rules size, 15")
	_expect_eq(view.size, view.card_size, "...the card keeps its size")
	_expect_eq(view.rules_text.get_line_count(), 2, "...on two lines")
	view.free()
	var player: Combatant = _player()
	_resolver.resolve_card(load(SELF_EATER_PATH) as CardData, _ctx(player, []))
	var hand: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(hand)
	await process_frame
	hand.set_stance(player.stance)
	hand.set_toll(player.toll)
	hand.set_bonus_context(_ctx(player, [Combatant.new(ENEMY_HP)]))
	hand.set_card_data(_card())
	_expect(hand.rules_text.get_parsed_text().begins_with("Deal 9 damage."), "Under Self-Eater the hand reads Deal 9 (%s)" % hand.rules_text.get_parsed_text())
	hand.free()
	_completed += 1

func _check_art() -> void:
	var card: CardData = _card()
	_expect(card.art != null and card.art.resource_path == ART_PATH, "Carries %s" % ART_PATH)
	if card.art != null:
		_expect(card.art.get_image().has_mipmaps(), "...mipmapped")
		var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(view)
		await process_frame
		view.set_card_data(card)
		_expect(view.art_rect.visible and view.art_rect.texture == card.art, "...shown on the face")
		_expect(not view.glyph.visible, "...in place of the glyph")
		view.free()
	_completed += 1

# The Gape queued, Second Swing on 12 Toll at the Greyshelf: two hits, 5
# spent, and one Goaded stack - one Attack card.
func _check_gape_goaded_once() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).get(greyshelf)
		await controller.call("end_turn")
		await create_timer(0.5).timeout
		_expect_eq(EnemyTurn.current_intent(combatant, greyshelf.get("enemy_data")).intent_name, "Gape", "The Gape is queued")
		var player: Combatant = controller.get("player")
		player.toll = 12
		var before: int = combatant.damage_taken_this_turn
		await _play_first(controller, greyshelf)
		_expect_eq(combatant.damage_taken_this_turn - before, 2 * HIT, "...Second Swing on 12 Toll lands two hits into it (12)")
		_expect_eq(player.toll, 12 - REPEAT_TOLL, "...5 Toll spent")
		_expect_eq(_goaded(combatant), 1, "...and one Goaded stack, not two")
	await _teardown()
	_completed += 1

# Within NUMBER_SLACK_PX of `expected` - a number's rise may have stepped
# once by the time it's read.
func _near(actual: Vector2, expected: Vector2) -> bool:
	return absf(actual.x - expected.x) <= NUMBER_SLACK_PX and absf(actual.y - expected.y) <= NUMBER_SLACK_PX

# Second Swing on 12 Toll at the Greyshelf, played for real: the repeat
# lands second_swing_delay after the first hit as its own blow - its own
# damage event, HP drop and number (offset), the Toll readout dropping
# by 5 at its swing, before it lands, and input still locked until it has.
func _check_two_blows() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).get(greyshelf)
		var overlay: Node = _field.get_node("BattleLayer").get_child(0)
		var player: Combatant = controller.get("player")
		player.toll = 12
		var hp_before: int = combatant.hp
		var hits: Array = []
		var hp_steps: Array[int] = []
		var tolls: Array = []
		var numbers: Array[Vector2] = []
		# Whether each was held down at the screen's top so its whole rise
		# shows (BattleOverlay._spawn_floating_number()).
		var held_down: Array[bool] = []
		var spawn_bases: Dictionary = {}
		controller.connect("damage_dealt", func(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
			if target == greyshelf:
				hits.append([ProbePlay.game_msec(), amount, bool(controller.get("_input_locked"))]))
		controller.connect("enemy_hp_changed", func(enemy: Node, current: int, _max_hp: int) -> void:
			if enemy == greyshelf:
				hp_steps.append(current))
		controller.connect("toll_changed", func(new_toll: int) -> void:
			tolls.append([ProbePlay.game_msec(), new_toll]))
		# Where this enemy's number would go as a number is spawned, against
		# where it was put - read at that frame's end, placed by its bottom
		# centre, less the sideways jitter it drew (FloatingNumber.jitter).
		# It holds still
		# through its pop and hold, so it hasn't risen yet. Damage numbers
		# only - the Wanderer's own (a heal, Toll) aren't this enemy's.
		overlay.connect("child_entered_tree", func(node: Node) -> void:
			if node is FloatingNumber:
				spawn_bases[node] = overlay.call("_screen_pos_for_damage_target", greyshelf) as Vector2)
		overlay.connect("child_entered_tree", func(node: Node) -> void:
			if node is FloatingNumber and spawn_bases.has(node):
				var number := node as FloatingNumber
				if number.kind == FloatingNumber.KIND_DAMAGE:
					var bottom_centre: Vector2 = number.position - number.jitter + Vector2(number.size.x / 2.0, number.size.y)
					numbers.append(bottom_centre - (spawn_bases[node] as Vector2))
					held_down.append(number.position.y <= number.rise_px + float(overlay.get("number_clearance_px")) + 0.5), CONNECT_DEFERRED)
		await _play_first(controller, greyshelf)
		_expect_eq(hits.size(), 2, "Two damage events, one per hit")
		if hits.size() == 2:
			_expect_eq([hits[0][1], hits[1][1]], [HIT, HIT], "...of 6 each")
			var gap_ms: int = int(hits[1][0]) - int(hits[0][0])
			var delay_ms: int = roundi(float(controller.get("second_swing_delay")) * 1000.0)
			_expect(gap_ms >= delay_ms - 20, "...the second %d ms after the first (second_swing_delay %d ms)" % [gap_ms, delay_ms])
			_expect(bool(hits[1][2]), "...input still locked as the second lands")
			var drop_at: int = -1
			for entry: Array in tolls:
				if int(entry[1]) == 12 - REPEAT_TOLL:
					drop_at = int(entry[0])
					break
			_expect(drop_at >= int(hits[0][0]) and drop_at <= int(hits[1][0]), "The Toll readout drops to 7 between the hits (%d, hits at %d and %d)" % [drop_at, hits[0][0], hits[1][0]])
		_expect_eq(hp_steps, [hp_before - HIT, hp_before - 2 * HIT] as Array[int], "The HP bar drops twice")
		_expect_eq(numbers.size(), 2, "Two damage numbers")
		if numbers.size() == 2:
			# The repeat's offset, and one step of the stack - the first still
			# shows as it lands. Held down at the screen's top, it can only
			# have moved down from there.
			var offset: Vector2 = Vector2(overlay.get("repeat_number_offset")) + Vector2(overlay.get("number_stack_step"))
			var expected: Vector2 = numbers[0] + offset
			_expect(_near(numbers[0], Vector2.ZERO), "...the first where a hit's goes (%s)" % str(numbers[0]))
			if held_down[1]:
				_expect(absf(numbers[1].x - expected.x) <= NUMBER_SLACK_PX and numbers[1].y >= expected.y - NUMBER_SLACK_PX, "...the second offset by %s across, held down at the screen's top (%s)" % [str(offset), str(numbers[1] - numbers[0])])
			else:
				_expect(_near(numbers[1], expected), "...the second offset by %s (%s)" % [str(offset), str(numbers[1] - numbers[0])])
		_expect_eq(player.toll, 12 - REPEAT_TOLL, "...5 Toll spent, as before")
		_expect(not bool(controller.get("_input_locked")), "Input unlocks once it has landed")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _card() -> CardData:
	return load(CARD_PATH) as CardData

func _player() -> Combatant:
	return Combatant.new(PLAYER_HP)

func _ctx(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[0] if not enemies.is_empty() else null
	return ctx

func _play(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx: EffectContext = _ctx(player, enemies)
	_resolver.resolve_card(_card(), ctx)
	return ctx

func _mark_charges(enemy: Combatant) -> int:
	for active in enemy.statuses:
		if active.data != null and active.data.id == "come_due":
			return active.charges
	return 0

func _goaded(combatant: Combatant) -> int:
	for active: Status in combatant.statuses:
		if active.data.resource_path == GOADED_PATH:
			return active.stack_count
	return 0

func _find_greyshelf() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == GREYSHELF_PATH:
			return node as Node3D
	return null

# A new run on floor 5 with a deck of Second Swing alone, the fight
# started on the Greyshelf. The controller, or null (a FAIL is recorded).
func _start_fight() -> Node:
	if _run_state == null:
		_fail("no RunState autoload")
		return null
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append(_card().duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_5)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = _find_greyshelf()
	if target == null:
		_fail("no Greyshelf on floor 5")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 5")
		return null
	await ProbePlay.settle_fight(self, _field, overlay.get("battle_controller"))
	return overlay.get("battle_controller")

func _play_first(controller: Node, greyshelf: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")):
		controller.call("confirm_target", greyshelf)
	# Until the play has resolved - a repeat's second hit included - by the
	# clock, not frames, which run unthrottled headless.
	var deadline: int = ProbePlay.cap_msec() + 5000
	while bool(controller.get("_input_locked")) and ProbePlay.cap_msec() < deadline:
		await process_frame
	await create_timer(0.6).timeout

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
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
