extends SceneTree

# Headless probe for Lash, Greyshelf's Tail's basic attack: Deal 5, and
# once more for each Lash played earlier this turn - 5, then 5 x 2, then
# 5 x 3, each a hit of its own. Under Self-Eater every hit takes its +3
# and its 2 HP is paid once for the card; Keen's one-shot +3 goes to the
# first hit only; an
# enemy's Block meets each hit on its own; a kill ends the chain; a
# Siltjaw's own mound broken mid-chain hands the rest of the hits to the
# Siltjaw. The face reads "Deal 5 damage." once and "Deal 5 ×N" from
# twice. The weapon: Slash plays as Lash (Slash+ as Lash+), a copy of the
# fight's own, the run's deck untouched. Played for real at the Greyshelf
# under the Tail: the hand holds Lash, the third Lash's three hits land
# card_hit_interval apart with input locked until the last, the faces
# count up - and with the Rusted Blade back the next fight's hand is
# Slash again. The weapon offer closes on TAKE or LEAVE alone - a click
# off the plate and Escape do nothing - while a piece on the sand still
# closes on either. A deck view shows the deck as the weapon carried
# makes it (Lash under the Tail, Slash under the Blade), and a pick hands
# back the deck's own card. Rules cases on the real .tres; the fight cases
# load floor 5 and play the cards through BattleController.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/lash_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 12
const LASH_PATH := "res://cards/weapon/lash.tres"
const LASH_PLUS_PATH := "res://cards/weapon/lash_tempered.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const SLASH_PLUS_PATH := "res://cards/tempered/slash_tempered.tres"
const TAIL_PATH := "res://run/weapons/greyshelfs_tail.tres"
const BLADE_PATH := "res://run/weapons/rusted_blade.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const KEEN_PATH := "res://battle/rules/statuses/keen.tres"
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const ARMOR_PATH := "res://run/armor/harness.tres"
const LASH_TAG := &"lash"
const FLOOR_5 := 4
const PLAYER_HP := 999
const ENEMY_HP := 100
const HIT := 5
const HIT_PLUS := 7
const SELF_EATER_BONUS := 3
const SELF_EATER_PRICE := 2
const KEEN_BONUS := 3

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	_run_state = root.get_node_or_null("RunState")
	_check_card_data()
	_check_counts_up()
	_check_self_eater()
	_check_keen_and_mark()
	_check_block_per_hit()
	_check_kill_ends_chain()
	_check_mound_break_carries()
	await _check_face()
	_check_weapon_mapping()
	await _check_offer_needs_a_choice()
	await _check_deck_view()
	await _check_fight()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("lash_probe: PASSED")
		quit(0)
	else:
		print("lash_probe: %d FAILED" % _failures)
		quit(1)

func _check_card_data() -> void:
	var lash: CardData = _lash()
	_expect_eq(lash.card_name, "Lash", "The card is named Lash")
	_expect_eq(lash.cost, 1, "...costs 1")
	_expect_eq(lash.card_type, CardData.CardType.ATTACK, "...is an Attack")
	_expect_eq(lash.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect(lash.rarity != CardData.CardRarity.UNSET, "...has a rarity")
	_expect(lash.has_tag(LASH_TAG) and not lash.has_tag(&"basic_attack"), "...tagged lash, not basic_attack")
	_expect(lash.effects.size() == 1 and lash.effects[0].value == HIT and lash.effects[0].repeat_per_earlier_play_tag == LASH_TAG, "...one DAMAGE 5, repeating per earlier lash")
	var plus: CardData = lash.tempered
	_expect(plus != null and plus.resource_path == LASH_PLUS_PATH, "...tempered into Lash+")
	if plus != null:
		_expect_eq(plus.card_name, "Lash+", "Lash+ is named so")
		_expect(plus.effects.size() == 1 and plus.effects[0].value == HIT_PLUS and plus.effects[0].repeat_per_earlier_play_tag == LASH_TAG, "...DAMAGE 7, repeating the same way")
		_expect(plus.has_tag(LASH_TAG), "...tagged lash")
		_expect(plus.tempered == null, "...and tempered no further")
	_completed += 1

# Three Lashes in a turn, counted as the controller counts them: 5, then
# 5 x 2, then 5 x 3. A new turn starts the count again.
func _check_counts_up() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	for played in [1, 2, 3]:
		var expected: Array[int] = []
		for i in played:
			expected.append(HIT)
		var hits: Array[int] = _play_counted(player, [enemy], _lash())
		_expect_eq(hits, expected, "Lash %d this turn: %s" % [played, str(expected)])
	player.tagged_plays_this_turn.clear()
	_expect_eq(_play_counted(player, [enemy], _lash()), [HIT] as Array[int], "A new turn: one hit again")
	_completed += 1

# Self-Eater: +3 on every hit, its 2 HP paid once for the card.
func _check_self_eater() -> void:
	var player: Combatant = _player()
	_resolver.resolve_card(load(SELF_EATER_PATH) as CardData, _ctx(player, []))
	_expect(player.stance != null, "Self-Eater taken")
	var enemy := Combatant.new(ENEMY_HP)
	var hp_before: int = player.hp
	var hits: Array[int] = _play(player, [enemy], _lash(), 2)
	var hit: int = HIT + SELF_EATER_BONUS
	_expect_eq(hits, [hit, hit, hit] as Array[int], "Under Self-Eater the third Lash: three hits of 8")
	_expect_eq(hp_before - player.hp, SELF_EATER_PRICE, "...its 2 HP paid once for the card")
	_completed += 1

# Keen (+3 on the next Attack) to the first hit only: 8 then 5, and the
# next Lash bare.
func _check_keen_and_mark() -> void:
	var player: Combatant = _player()
	Status.apply_to(player.statuses, load(KEEN_PATH) as StatusData)
	var enemy := Combatant.new(ENEMY_HP)
	var hits: Array[int] = _play(player, [enemy], _lash(), 1)
	_expect_eq(hits, [HIT + KEEN_BONUS, HIT] as Array[int], "Keen: 8 on the first hit, 5 on the second")
	_expect(Status.find_in(player.statuses, load(KEEN_PATH) as StatusData) == null, "...Keen's one charge spent")
	hits = _play(player, [enemy], _lash(), 2)
	_expect_eq(hits, [HIT, HIT, HIT] as Array[int], "...then 5, 5 and 5")
	_completed += 1

# 8 Block against three hits of 5: the first all blocked, the second 3
# blocked and 2 through, the third 5 - 7 to HP, Block met twice.
func _check_block_per_hit() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	enemy.block = 8
	var blocked: Array[int] = []
	var ctx: EffectContext = _ctx(player, [enemy])
	ctx.tagged_plays_before_this = {LASH_TAG: 2}
	ctx.on_block = func(_target: Combatant, amount: int, _to_hp: int) -> void:
		blocked.append(amount)
	_resolver.resolve_card(_lash(), ctx)
	_expect_eq(blocked, [HIT, 3] as Array[int], "8 Block meets the hits one at a time: 5, then 3")
	_expect_eq(ENEMY_HP - enemy.hp, 2 + HIT, "...7 to HP")
	_completed += 1

# An 8 HP enemy and a third Lash: the second hit kills, the third never
# lands.
func _check_kill_ends_chain() -> void:
	var player: Combatant = _player()
	var enemy := Combatant.new(8)
	var hits: Array[int] = _play(player, [enemy], _lash(), 2)
	_expect(enemy.hp <= 0, "The second hit kills an 8 HP enemy")
	_expect_eq(hits.size(), 2, "...and the chain ends there: two hits, not three (%s)" % str(hits))
	_completed += 1

# At a dug-in Siltjaw's own mound: the hits that break it, then the rest
# on the Siltjaw itself (after the break's overkill), each as it lands
# there - Exposed and all.
func _check_mound_break_carries() -> void:
	var data: EnemyData = load(SILTJAW_PATH) as EnemyData
	var enemy := Combatant.new(data.max_hp)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	if not enemy.dug_in or enemy.true_mound < 0:
		_fail("The Siltjaw opens dug in")
		_completed += 1
		return
	var guard: Combatant = enemy.mound_guards[enemy.true_mound]
	var to_break: int = ceili(float(guard.hp) / float(HIT))
	var player: Combatant = _player()
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = guard
	for each in enemy.mound_guards:
		ctx.enemies.append(each)
	ctx.mound_data[enemy] = data
	# Two hits more than the mound takes.
	ctx.tagged_plays_before_this = {LASH_TAG: to_break + 1}
	var on_guard: Array[int] = []
	var on_siltjaw: Array[int] = []
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		if kind != "card":
			return
		if target == guard:
			on_guard.append(amount)
		elif target == enemy:
			on_siltjaw.append(amount)
	_resolver.resolve_card(_lash(), ctx)
	_expect(not enemy.dug_in, "%d hits break its own mound - it is up" % to_break)
	_expect_eq(on_guard.size(), to_break, "...those hits on the mound (%s)" % str(on_guard))
	# The overkill the breaking hit carried in, then the two hits after.
	_expect_eq(on_siltjaw.size(), 3, "...the break's overkill and the two hits after it on the Siltjaw (%s)" % str(on_siltjaw))
	if on_siltjaw.size() == 3:
		var after: int = DamageEffect.landed(HIT, player, enemy)
		_expect_eq([on_siltjaw[1], on_siltjaw[2]], [after, after], "...each as a hit lands on it now (%d)" % after)
	_completed += 1

# Out of a fight: "Deal 5 damage." and its rule. In a battle hand: the
# same with no Lash played, "Deal 5 ×2." after one, "Deal 8 ×3." after
# two under Self-Eater. The card keeps its size.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(_lash())
	_expect_eq(view.rules_text.get_parsed_text(), "Deal 5 damage.\nRepeat once for each Lash played earlier this turn.", "The face reads its rule")
	_expect_eq(view.size, view.card_size, "...the card keeps its size")
	print("lash_probe: rules size %d, %d lines" % [view.rules_text.get_theme_font_size("normal_font_size"), view.rules_text.get_line_count()])
	view.free()
	var player: Combatant = _player()
	var enemy := Combatant.new(ENEMY_HP)
	for case: Array in [[0, "Deal 5 damage."], [1, "Deal 5 ×2."], [2, "Deal 5 ×3."]]:
		var hand: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
		root.add_child(hand)
		await process_frame
		var ctx: EffectContext = _ctx(player, [enemy])
		ctx.tagged_plays_before_this = {LASH_TAG: int(case[0])}
		hand.set_bonus_context(ctx)
		hand.set_card_data(_lash())
		var text: String = hand.rules_text.get_parsed_text()
		_expect(text.begins_with(String(case[1]) + "\n"), "%d Lash played: the hand reads %s (%s)" % [int(case[0]), case[1], text])
		hand.free()
	_resolver.resolve_card(load(SELF_EATER_PATH) as CardData, _ctx(player, []))
	var stance_hand: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(stance_hand)
	await process_frame
	var stance_ctx: EffectContext = _ctx(player, [enemy])
	stance_ctx.tagged_plays_before_this = {LASH_TAG: 2}
	stance_hand.set_stance(player.stance)
	stance_hand.set_bonus_context(stance_ctx)
	stance_hand.set_card_data(_lash())
	_expect(stance_hand.rules_text.get_parsed_text().begins_with("Deal 8 ×3."), "Under Self-Eater, two played: Deal 8 ×3. (%s)" % stance_hand.rules_text.get_parsed_text())
	stance_hand.free()
	_completed += 1

# The Tail plays Slash as Lash and Slash+ as Lash+, each a fresh copy;
# anything else as itself. The Rusted Blade plays Slash as Slash.
func _check_weapon_mapping() -> void:
	var tail: WeaponData = load(TAIL_PATH) as WeaponData
	var blade: WeaponData = load(BLADE_PATH) as WeaponData
	var slash: CardData = (load(SLASH_PATH) as CardData).duplicate() as CardData
	var slash_plus: CardData = (load(SLASH_PLUS_PATH) as CardData).duplicate() as CardData
	var lash: CardData = tail.modify_basic_attack(slash)
	_expect(lash != null and lash.card_name == "Lash" and lash != _lash(), "The Tail plays Slash as a Lash of its own")
	var lash_plus: CardData = tail.modify_basic_attack(slash_plus)
	_expect(lash_plus != null and lash_plus.card_name == "Lash+", "...Slash+ as Lash+")
	_expect(tail.modify_basic_attack(slash) != lash, "...a fresh copy each time")
	var self_eater: CardData = load(SELF_EATER_PATH) as CardData
	_expect(tail.modify_basic_attack(self_eater) == self_eater, "...anything else as itself")
	_expect(blade.modify_basic_attack(slash) == slash, "The Rusted Blade plays Slash as Slash")
	_expect_eq(slash.card_name, "Slash", "...and the Slash itself is untouched")
	_completed += 1

# The Tail's offer: a click off the plate and Escape leave it open; LEAVE
# closes it, not taken. A piece on the sand (ArmorExamine with_choice)
# still closes on a click off it.
func _check_offer_needs_a_choice() -> void:
	var offer := ArmorExamine.new()
	offer.setup_weapon(load(TAIL_PATH) as WeaponData, Rect2(), load(BLADE_PATH) as WeaponData, true)
	var results: Array = []
	offer.closed.connect(func(taken: bool) -> void: results.append(taken))
	root.add_child(offer)
	await process_frame
	offer.call("_on_scrim_gui_input", _click(MOUSE_BUTTON_LEFT))
	offer.call("_on_scrim_gui_input", _click(MOUSE_BUTTON_RIGHT))
	var escape := InputEventAction.new()
	escape.action = &"ui_cancel"
	escape.pressed = true
	offer.call("_unhandled_input", escape)
	await create_timer(0.4).timeout
	_expect(results.is_empty() and is_instance_valid(offer) and offer.is_inside_tree(), "The weapon offer stays open through a click off it, a right click and Escape")
	if is_instance_valid(offer):
		offer.get_plate().activate(ItemPlate.Choice.LEAVE)
		await create_timer(0.4).timeout
	_expect_eq(results, [false], "...LEAVE closes it, not taken")
	var armor := ArmorExamine.new()
	armor.setup(load(ARMOR_PATH) as TrinketData, null, true)
	var armor_results: Array = []
	armor.closed.connect(func(taken: bool) -> void: armor_results.append(taken))
	root.add_child(armor)
	await process_frame
	armor.call("_on_scrim_gui_input", _click(MOUSE_BUTTON_LEFT))
	await create_timer(0.4).timeout
	_expect_eq(armor_results, [false], "A piece on the sand still closes on a click off it")
	_completed += 1

# A deck view of one Slash: Lash under the Tail - its pick the Slash
# itself - and Slash again under the Rusted Blade.
func _check_deck_view() -> void:
	if _run_state == null:
		_fail("no RunState autoload")
		_completed += 1
		return
	_run_state.call("new_run", load(CHARACTER_PATH))
	var slash: CardData = (load(SLASH_PATH) as CardData).duplicate() as CardData
	var cards: Array[CardData] = [slash]
	_run_state.call("equip_weapon", load(TAIL_PATH))
	var picked: Array = []
	var view: DeckView = DeckPanel.open_picker(self, cards, "PICK", 100)
	view.card_picked.connect(func(card: CardData) -> void: picked.append(card))
	await process_frame
	var faces: Array[CardView] = _deck_view_faces(view)
	_expect(faces.size() == 1 and faces[0].card_data.card_name == "Lash", "Under the Tail the deck view shows Lash")
	if faces.size() == 1:
		faces[0].clicked.emit(faces[0].card_data)
	await process_frame
	_expect(picked.size() == 1 and picked[0] == slash, "...and a pick hands back the deck's own Slash")
	_expect_eq(slash.card_name, "Slash", "...the Slash untouched")
	_run_state.call("equip_weapon", load(BLADE_PATH))
	var again: DeckView = DeckPanel.open_view(self, cards, "DECK")
	await process_frame
	faces = _deck_view_faces(again)
	_expect(faces.size() == 1 and faces[0].card_data.card_name == "Slash", "The Rusted Blade back on: the deck view shows Slash")
	again.close()
	await process_frame
	_completed += 1

func _deck_view_faces(view: DeckView) -> Array[CardView]:
	var faces: Array[CardView] = []
	var grid: Node = view.get("_grid")
	if grid == null:
		return faces
	for slot in grid.get_children():
		for child in slot.get_children():
			if child is CardView and not child.is_queued_for_deletion():
				faces.append(child as CardView)
	return faces

func _click(button_index: MouseButton) -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = button_index
	click.pressed = true
	return click

# A run of Slashes under the Tail at the Greyshelf: the hand is Lash; the
# third Lash lands three hits card_hit_interval apart, input locked until
# the last; a Lash still in hand reads x2 after one. The run's deck is
# still its Slashes. The Rusted Blade back on and a new fight: the hand
# is Slash.
func _check_fight() -> void:
	if _run_state == null:
		_fail("no RunState autoload")
		_completed += 1
		return
	_run_state.call("new_run", load(CHARACTER_PATH))
	var run_cards: Array[CardData] = []
	for i in 10:
		run_cards.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
	_run_state.set("deck", run_cards)
	_run_state.call("equip_weapon", load(TAIL_PATH))
	var controller: Node = await _start_fight()
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var names: Array[String] = _hand_names(controller)
		_expect(not names.is_empty() and names.count("Lash") == names.size(), "Under the Tail the hand is Lash (%s)" % str(names))
		var hits: Array = []
		controller.connect("damage_dealt", func(_source: Variant, target: Variant, amount: int, kind: String) -> void:
			if target == greyshelf and kind == "card":
				hits.append([ProbePlay.game_msec(), amount, bool(controller.get("_input_locked"))]))
		await _play_first(controller, greyshelf)
		_expect_eq(hits.size(), 1, "The first Lash: one hit")
		var faces: Array = controller.get("_hand_container").call("_card_views")
		if not faces.is_empty():
			var text: String = (faces[0] as CardView).rules_text.get_parsed_text()
			_expect(text.contains("×2"), "...a Lash in hand now reads x2 (%s)" % text)
		await _play_first(controller, greyshelf)
		_expect_eq(hits.size(), 3, "The second: two more")
		hits.clear()
		await _play_first(controller, greyshelf)
		_expect_eq(hits.size(), 3, "The third: three hits, each a damage event")
		if hits.size() == 3:
			var interval_ms: int = roundi(float(controller.get("card_hit_interval")) * 1000.0)
			for i in [1, 2]:
				var gap: int = int(hits[i][0]) - int(hits[i - 1][0])
				_expect(gap >= interval_ms - 20, "...hit %d lands %d ms after the one before (card_hit_interval %d ms)" % [i + 1, gap, interval_ms])
			_expect(bool(hits[2][2]), "...input still locked as the last lands")
		_expect(not bool(controller.get("_input_locked")), "Input unlocks once the last has landed")
		var deck: Array = _run_state.get("deck")
		var all_slash: bool = deck.size() == run_cards.size()
		for i in deck.size():
			all_slash = all_slash and deck[i] == run_cards[i] and (deck[i] as CardData).card_name == "Slash"
		_expect(all_slash, "The run's deck is still its own Slashes")
	await _teardown()
	_run_state.call("equip_weapon", load(BLADE_PATH))
	controller = await _start_fight()
	if controller != null:
		var names: Array[String] = _hand_names(controller)
		_expect(not names.is_empty() and names.count("Slash") == names.size(), "The Rusted Blade back on: the next fight's hand is Slash (%s)" % str(names))
	await _teardown()
	_completed += 1

# --- Helpers ---

func _lash() -> CardData:
	return load(LASH_PATH) as CardData

func _player() -> Combatant:
	return Combatant.new(PLAYER_HP)

func _ctx(player: Combatant, enemies: Array[Combatant]) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = enemies
	ctx.target = enemies[0] if not enemies.is_empty() else null
	return ctx

# `card` resolved with `earlier` Lashes before it this turn; its card
# hits on enemies[0], in order.
func _play(player: Combatant, enemies: Array[Combatant], card: CardData, earlier: int) -> Array[int]:
	var hits: Array[int] = []
	var ctx: EffectContext = _ctx(player, enemies)
	ctx.tagged_plays_before_this = {LASH_TAG: earlier}
	var struck: Combatant = enemies[0]
	ctx.on_damage = func(target: Combatant, amount: int, kind: String) -> void:
		if target == struck and kind == "card":
			hits.append(amount)
	_resolver.resolve_card(card, ctx)
	return hits

# `card` played as the controller plays it: counted at commit, the
# context carrying the count from before it.
func _play_counted(player: Combatant, enemies: Array[Combatant], card: CardData) -> Array[int]:
	var earlier: int = int(player.tagged_plays_this_turn.get(LASH_TAG, 0))
	player.count_play(card)
	return _play(player, enemies, card, earlier)

func _hand_names(controller: Node) -> Array[String]:
	var names: Array[String] = []
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		names.append(view.card_data.card_name)
	return names

func _find_greyshelf() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == GREYSHELF_PATH:
			return node as Node3D
	return null

# Floor 5 with the run as it stands, the fight started on the Greyshelf.
# The controller, or null (a FAIL is recorded).
func _start_fight() -> Node:
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
	# Until the play has resolved - its last hit included - by the clock,
	# not frames, which run unthrottled headless.
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
