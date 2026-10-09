extends SceneTree

# Headless probe for Claw Back - 2 Energy, Rare Attack, one enemy, Spent:
# a hit of 5 - 12 when the player is Critical as it resolves - that
# Drains (CardEffect.drains): the player heals the HP it took, after
# block, less what Grace reclaims, no further than max HP. The hit is the
# card's own blow, so the Attack bonuses are in it and in its heal, and
# Ransom's half comes on top.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/claw_back_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver on bare
# Combatants (max HP 70, Critical at 21 and below), working each number
# out of the card's own data. The fight cases load the real region scene
# and play the card through BattleController.request_play()/confirm_
# target(), as garnish_probe does: the face at hand size, Spent after the
# play, and its own sound - at the card's Critical pitch and lift when
# the player is Critical as it plays, 1.0 and the usual level otherwise.
# Untyped against anything that names the RunState autoload.

const CASES := 12
const MAX_HP := 70
const CRITICAL_FRACTION := 0.3
const CRITICAL_HP := 21
const ENEMY_HP := 100
const CARD_PATH := "res://cards/data/claw_back.tres"
const SELF_EATER_PATH := "res://cards/data/self_eater.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const RANSOM_ACTIVE_PATH := "res://battle/rules/statuses/ransom_active.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Claw Back.png"
const SOUND_PATH := "res://assets/audio/cards/Claw Back/Claw Back.mp3"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SAFETY_SECONDS := 240.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _hit: int = 0
var _critical_hit: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var effect: CardEffect = (load(CARD_PATH) as CardData).effects[0]
	_hit = effect.value
	_critical_hit = effect.alt_value

	_check_data()
	_check_above_critical()
	_check_at_critical()
	_check_into_block()
	_check_capped_at_max_hp()
	_check_grace()
	_check_self_eater()
	_check_last_resort()
	_check_ransom()
	await _check_face()
	await _check_play(false)
	await _check_play(true)

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("claw_back_probe: PASSED")
		quit(0)
	else:
		print("claw_back_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Claw Back", "The card loads")
	_expect_eq(card.cost, 2, "...costs 2 Energy")
	_expect_eq(card.card_type, CardData.CardType.ATTACK, "...is an Attack")
	_expect_eq(card.rarity, CardData.CardRarity.RARE, "...Rare")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect_eq(card.removal_scope, CardData.RemovalScope.SPENT, "...and is Spent")
	_expect_eq(card.description, "{else}Drain {damage}.{/else} {if}Critical: drain {alt_damage}.{/if}\nSpent.", "...its text, in Cornered's voice")
	_expect_eq(card.effects.size(), 1, "...one effect")
	var effect: CardEffect = card.effects[0]
	_expect_eq(effect.effect_type, CardEffect.EffectType.DAMAGE, "...an ordinary hit, the card's own blow")
	_expect(effect.drains, "...that Drains")
	_expect_eq([effect.value, effect.condition, effect.alt_value], [5, CardEffect.Condition.CRITICAL, 12], "...5, or 12 at Critical")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.STRIKE, "...reading STRIKE")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect_eq([card.critical_sound_pitch, card.critical_sound_volume_db], [0.85, 2.0], "...deeper and louder at Critical (0.85, +2 dB)")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	var slash: CardData = load("res://cards/data/slash.tres")
	_expect_eq([slash.critical_sound_pitch, slash.critical_sound_volume_db], [1.0, 0.0], "Any other card's sound is unchanged at Critical")
	# Drain's hover still holds for it: what the hit takes, up to the number
	# the face prints (the live one, bonuses in).
	_expect(CardView.KEYWORDS.has("Drain"), "Drain is a bold rules keyword on its face")
	_expect_eq(KeywordTable.shared().definition("Drain"), "Heal for the HP the damage takes from enemies, up to the Drain's number if it has one.", "The Drain keyword's hover is unchanged")
	_completed += 1

# --- Rules ---

func _check_above_critical() -> void:
	var player: Combatant = _player(50)
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, _hit, "Above Critical: deals %d" % _hit)
	_expect_eq(player.hp, 50 + _hit, "...and heals %d" % _hit)
	_completed += 1

func _check_at_critical() -> void:
	var player: Combatant = _player(CRITICAL_HP)
	_expect(player.is_critical(), "21 of 70 HP is Critical")
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, _critical_hit, "At Critical: deals %d" % _critical_hit)
	_expect_eq(player.hp, CRITICAL_HP + _critical_hit, "...and heals %d" % _critical_hit)
	_completed += 1

func _check_into_block() -> void:
	var player: Combatant = _player(40)
	var enemy: Combatant = _enemy()
	enemy.block = 3
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, _hit - 3, "Into 3 Block: %d gets through" % (_hit - 3))
	_expect_eq(player.hp, 40 + _hit - 3, "...and it heals only that")
	var walled: Combatant = _enemy()
	walled.block = 50
	_play(player, walled)
	_expect_eq(player.hp, 40 + _hit - 3, "All of it blocked: no heal")
	_completed += 1

func _check_capped_at_max_hp() -> void:
	var player: Combatant = _player(MAX_HP - 2)
	_play(player, _enemy())
	_expect_eq(player.hp, MAX_HP, "The heal stops at max HP (%d + 2, not + %d)" % [MAX_HP - 2, _hit])
	_completed += 1

# Grace open: what Grace reclaims from the hit is its heal; the Drain
# heals the rest, as Ransom's does - never the same HP twice.
func _check_grace() -> void:
	var player: Combatant = _player(40)
	player.has_grace = true
	player.grace = 3
	player.grace_turns_left = 1
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, _hit, "With 3 Grace open: deals %d" % _hit)
	_expect_eq(player.hp, 40 + _hit, "...Grace reclaims 3 and the Drain heals the other %d - %d in all, not %d" % [_hit - 3, _hit, _hit + 3])
	_completed += 1

# Self-Eater: its +3 is in the hit and in the heal - and its 2 HP, paid
# as the card resolves, before the hit, is what Critical is judged after:
# from 23 it pays to 21, Critical, and the hit is 12 + 3.
func _check_self_eater() -> void:
	var player: Combatant = _player(CRITICAL_HP + 2)
	_play_card(load(SELF_EATER_PATH), player, _enemy())
	_expect(not player.is_critical(), "Self-Eater up, 23 HP: not Critical yet")
	var bonus: int = AttackBonus.ongoing_for_player(player, player.hp)
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	var dealt: int = ENEMY_HP - enemy.hp
	_expect_eq(dealt, _critical_hit + bonus, "Self-Eater's 2 HP tips it into Critical first: deals %d + %d" % [_critical_hit, bonus])
	_expect_eq(player.hp, CRITICAL_HP + dealt, "...and heals all %d (23 - 2 + %d)" % [dealt, dealt])
	_completed += 1

# Last Resort: at Critical its +6 is in the hit and the heal.
func _check_last_resort() -> void:
	var player: Combatant = _player(15)
	_play_card(load(LAST_RESORT_PATH), player, _enemy())
	var bonus: int = AttackBonus.ongoing_for_player(player, player.hp)
	_expect(bonus > 0, "Last Resort at Critical: an Attack bonus is up (%d)" % bonus)
	var enemy: Combatant = _enemy()
	var hp_before: int = player.hp
	_play(player, enemy)
	_expect_eq(ENEMY_HP - enemy.hp, _critical_hit + bonus, "...Claw Back deals %d + %d" % [_critical_hit, bonus])
	_expect_eq(player.hp - hp_before, _critical_hit + bonus, "...and heals it all")
	_completed += 1

# Ransom: Claw Back's own Drain, then Ransom's half of the damage dealt on
# top - floor(5 x 0.5) = 2, 7 in all.
func _check_ransom() -> void:
	var player: Combatant = _player(40)
	var ransom: StatusData = load(RANSOM_ACTIVE_PATH)
	Status.apply_to(player.statuses, ransom)
	var enemy: Combatant = _enemy()
	_play(player, enemy)
	var half: int = floori(float(_hit) * ransom.ransom_heal_fraction)
	_expect_eq(ENEMY_HP - enemy.hp, _hit, "Under Ransom: deals %d" % _hit)
	_expect_eq(player.hp, 40 + _hit + half, "...heals its own %d and Ransom's %d on top" % [_hit, half])
	_completed += 1

# --- Face and fight ---

# Outside a fight, both halves of the face, and the text at the first
# rules size, on the card's own size.
func _check_face() -> void:
	var view: CardView = (load("res://battle/card_view.tscn") as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Drain 5. Critical: drain 12.\nSpent.", "The face reads Drain 5. Critical: drain 12. / Spent.")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), view.rules_font_sizes[0], "...at the first rules size")
	_expect_eq(view.size, view.card_size, "...on the card's own size")
	view.free()
	_completed += 1

# The real play, at `critical` or not: the face at hand size, 2 Energy, its
# sound at the card's Critical pitch and lift (or 1.0 and the usual
# level), the hit and its heal, and Spent after.
func _check_play(critical: bool) -> void:
	var controller: Node = await _start_fight(10 if critical else 50)
	if controller != null:
		var player: Combatant = controller.get("player")
		var label: String = "At Critical" if critical else "Above Critical"
		_expect_eq(player.is_critical(), critical, "%s as it's played" % label)
		var card: CardData = await _deal(controller)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.cost_label.text, "2", "%s, the face: 2 Energy" % label)
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...its text at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		var enemy_before: int = combatant.hp
		var hp_before: int = player.hp
		await _play_real(controller, card, target)
		var sound: AudioStreamPlayer = _overlay.get("_card_override_player")
		_expect(sound != null and sound.stream != null and sound.stream.resource_path == SOUND_PATH, "%s: its own sound plays" % label)
		if sound != null:
			var level: float = float(_overlay.get("card_override_volume_db"))
			_expect(is_equal_approx(sound.pitch_scale, card.critical_sound_pitch if critical else 1.0), "...at pitch %s (%s)" % ["0.85" if critical else "1.0", sound.pitch_scale])
			_expect(is_equal_approx(sound.volume_db, level + (card.critical_sound_volume_db if critical else 0.0)), "...at %s dB (%s)" % [level + (card.critical_sound_volume_db if critical else 0.0), sound.volume_db])
		var dealt: int = enemy_before - combatant.hp
		_expect(dealt > 0, "...the hit lands (%d)" % dealt)
		_expect_eq(player.hp - hp_before, mini(dealt, player.max_hp - hp_before), "...and heals what it took")
		var deck: Object = controller.get("deck")
		_expect((deck.get("exhaust_pile") as Array).has(card), "...and Claw Back is Spent")
		_expect(not (deck.get("discard_pile") as Array).has(card), "...not discarded")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	return player

func _enemy() -> Combatant:
	return Combatant.new(ENEMY_HP)

func _play(player: Combatant, enemy: Combatant) -> void:
	_play_card(load(CARD_PATH), player, enemy)

func _play_card(card: CardData, player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy] as Array[Combatant]
	_resolver.resolve_card(card, ctx)

func _start_fight(hp: int) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
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
	_overlay = layer.get_child(0) if layer.get_child_count() > 0 else null
	if _overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = _overlay.get("battle_controller")
	controller.get("deck").call("discard_hand")
	return controller

func _deal(controller: Node) -> CardData:
	var card: CardData = (load(CARD_PATH) as CardData).duplicate()
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

func _play_real(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if not bool(controller.call("is_awaiting_target")):
		_fail("'%s' didn't ask for a target" % card.card_name)
		return
	controller.call("confirm_target", target)
	# By the clock, not frames, which run unthrottled headless.
	var deadline: int = Time.get_ticks_msec() + 5000
	while bool(controller.get("_input_locked")) and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 3:
		await process_frame

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
