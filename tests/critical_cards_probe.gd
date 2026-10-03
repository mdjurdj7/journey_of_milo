extends SceneTree

# Headless rules probe for the six Critical cards (Cornered, Unbroken,
# Dying Light, Last Wager, Refuse the End, Last Resort) and the attack
# bonus on Reckoning. The rules layer - Combatant, EffectResolver,
# EnemyTurn, the real .tres cards - plus the numbers a CardView face
# prints; no field scene, no autoload:
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/critical_cards_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const MAX_HP := 70
const CRITICAL_FRACTION := 0.3
const CASES := 12
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const SAFETY_SECONDS := 60.0

var _failures: int = 0
# Cases that ran to their end. A script error aborts a case without
# failing anything, so the total is checked too.
var _completed: int = 0
var _resolver := EffectResolver.new()

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_check_threshold()
	_check_cornered()
	_check_unbroken()
	_check_last_wager()
	_check_last_wager_bonus()
	_check_dying_light()
	_check_last_resort()
	_check_bonus_once_per_card()
	_check_refuse_the_end()
	_check_preview()
	_check_reckoning()
	await _check_faces()
	if _completed != CASES:
		_failures += 1
		print("FAIL: only %d of %d cases ran to the end" % [_completed, CASES])
	if _failures == 0:
		print("critical_cards_probe: PASSED")
		quit(0)
	else:
		print("critical_cards_probe: %d FAILED" % _failures)
		quit(1)

# --- Cases ---

func _check_threshold() -> void:
	var player: Combatant = _player(21)
	_expect(player.is_critical(), "21/70 is Critical")
	player.hp = 22
	_expect(not player.is_critical(), "22/70 is not Critical")
	_completed += 1

func _check_cornered() -> void:
	var card: CardData = _card("cornered")
	_expect_eq(_deal(card, _player(50)), 8, "Cornered above the line")
	_expect_eq(_deal(card, _player(21)), 16, "Cornered while Critical")
	_completed += 1

func _check_unbroken() -> void:
	var card: CardData = _card("unbroken")
	var player: Combatant = _player(50)
	_play(card, player, null)
	_expect_eq(player.block, 6, "Unbroken above the line")
	player = _player(10)
	_play(card, player, null)
	_expect_eq(player.block, 11, "Unbroken while Critical")
	_completed += 1

# Last Wager attacks first and pays after, like Bite Down: Critical is
# judged at the HP held when it is played, so its own 4 HP can make the
# player Critical but never upgrades the blow that paid it.
func _check_last_wager() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(30)
	_expect_eq(_deal(card, player), 16, "Last Wager above the line deals 16")
	_expect_eq(player.hp, 26, "...then loses 4 HP")
	_expect_eq(player.toll, 4, "Last Wager makes 4 Toll")

	player = _player(25)
	_expect_eq(_deal(card, player), 16, "Last Wager at 25: its 4 HP reaches Critical, the blow stays 16")
	_expect_eq(player.hp, 21, "...ends at 21")
	_expect(player.is_critical(), "...and Critical afterward")

	player = _player(21)
	_expect_eq(_deal(card, player), 26, "Last Wager already Critical deals 26")
	_expect_eq(player.hp, 17, "...then loses 4 HP")
	_expect_eq(player.toll, 4, "...and makes 4 Toll")

	# The order itself: the blow is reported before the payment.
	player = _player(30)
	var enemy := Combatant.new(100)
	var ctx: EffectContext = _ctx(player, enemy)
	var reports: Array[String] = []
	ctx.on_damage = func(who: Combatant, amount: int, kind: String) -> void:
		reports.append("%s %d %s" % ["player" if who == player else "enemy", amount, kind])
	_resolver.resolve_card(card, ctx)
	_expect_eq(reports, ["enemy 16 card", "player 4 self"] as Array[String], "Last Wager: damage first, HP second")

	# The payment can still kill - after the blow has landed.
	player = _player(3)
	enemy = Combatant.new(16)
	_play(card, player, enemy)
	_expect_eq(enemy.hp, 0, "Last Wager at 3 HP still lands its 16")
	_expect_eq(player.hp, 0, "...then the 4 HP kills, like Bite Down")
	_completed += 1

# Last Wager's attack bonus goes through the normal pipeline, read in the
# same state as its Critical clause: before the payment.
func _check_last_wager_bonus() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(50)
	_play(_card("self_eater"), player, null)
	_expect_eq(_deal(card, player), 19, "Last Wager under Self-Eater: 16 + 3")
	_expect_eq(player.hp, 44, "...Self-Eater's 2 and Last Wager's 4 paid")
	_expect_eq(player.toll, 6, "...and made into 6 Toll")

	player = _player(25)
	_play(_card("last_resort"), player, null)
	_play(_card("dying_light"), player, null)
	_expect_eq(_deal(card, player), 16, "Last Wager at 25 under Last Resort + Dying Light: no Critical bonus yet")
	_expect_eq(player.hp, 21, "...Critical only after")
	_expect_eq(_deal(card, player), 35, "Last Wager at 21 under both: 26 + 6 + 3")
	_expect_eq(player.hp, 17, "...then loses 4 HP")
	_completed += 1

func _check_dying_light() -> void:
	var power: CardData = _card("dying_light")
	var cornered: CardData = _card("cornered")
	var player: Combatant = _player(50)
	_play(power, player, null)
	_expect_eq(_deal(cornered, player), 8, "Dying Light off above the line")
	player.hp = 20
	_expect_eq(_deal(cornered, player), 19, "Dying Light +3 while Critical")
	_play(power, player, null)
	_expect_eq(_deal(cornered, player), 22, "Two Dying Lights +6")
	player.hp = 40
	_expect_eq(_deal(cornered, player), 8, "Dying Light off again once HP climbs back")
	_completed += 1

func _check_last_resort() -> void:
	var stance_card: CardData = _card("last_resort")
	var cornered: CardData = _card("cornered")
	var player: Combatant = _player(50)
	player.block = 5
	_play(stance_card, player, null)
	_expect_eq(player.block, 5, "Last Resort keeps Block already up")
	_expect_eq(_deal(cornered, player), 8, "Last Resort off above the line")
	player.hp = 20
	_expect_eq(_deal(cornered, player), 22, "Last Resort +6 while Critical")
	_play(stance_card, player, null)
	_expect_eq(player.stance.stacks, 2, "A second Last Resort stacks")
	_expect_eq(_deal(cornered, player), 28, "Last Resort ×2: +12 while Critical")
	_play(_card("unbroken"), player, null)
	_expect_eq(player.block, 5, "No Block gained under Last Resort")
	_play(_card("dying_light"), player, null)
	_expect_eq(_deal(cornered, player), 31, "Last Resort ×2 and Dying Light together")
	_play(_card("self_eater"), player, null)
	_expect_eq(player.stance.data.id, "self_eater", "Self-Eater replaces Last Resort")
	_expect_eq(player.stance.stacks, 1, "...every stack of it gone, Self-Eater at 1")
	_play(stance_card, player, null)
	_expect_eq(player.stance.data.id, "last_resort", "Last Resort replaces Self-Eater")
	_expect_eq(player.stance.stacks, 1, "...and starts at 1")

	# Self-Eater stacks too: ×2 is lose 4, deal 6 more.
	player = _player(50)
	_play(_card("self_eater"), player, null)
	_play(_card("self_eater"), player, null)
	_expect_eq(player.stance.stacks, 2, "A second Self-Eater stacks")
	_expect_eq(_deal(cornered, player), 14, "Self-Eater ×2: 8 + 6")
	_expect_eq(player.hp, 46, "Self-Eater ×2 costs 4 HP")
	_expect_eq(player.toll, 4, "...and makes 4 Toll")
	_completed += 1

# A two-hit Attack under Last Resort + Dying Light at Critical takes the
# bonus once, on its first damage effect.
func _check_bonus_once_per_card() -> void:
	var player: Combatant = _player(20)
	_play(_card("last_resort"), player, null)
	_play(_card("dying_light"), player, null)
	var card := CardData.new()
	card.card_type = CardData.CardType.ATTACK
	for i in 2:
		var hit := CardEffect.new()
		hit.effect_type = CardEffect.EffectType.DAMAGE
		hit.value = 5
		card.effects.append(hit)
	_expect_eq(_deal(card, player), 19, "Two-hit Attack: 5 + 9 bonus + 5")
	_completed += 1

func _check_refuse_the_end() -> void:
	var power: CardData = _card("refuse_the_end")
	var player: Combatant = _player(10)
	_play(power, player, null)
	_expect(EffectResolver.card_blocked(power, player), "A second copy can't be played while armed")
	var data: EnemyData = _attacker(30)
	var enemy: Combatant = _enemy(data)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(not bool(preview["lethal"]), "Intent isn't lethal while the guard would hold")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 1, "Refuse the End leaves 1 HP")
	_expect_eq(int(result["damage_to_hp"]), 9, "Reported loss is what was actually lost")
	_expect(Status.find_in(player.statuses, power.effects[0].status_data) == null, "Refuse the End is gone once spent")
	_expect(EffectResolver.card_blocked(power, player), "Spent: another copy can't re-arm it")
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview["lethal"]), "Intent lethal again once spent")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 0, "Second lethal hit kills")

	# Not Critical before the hit: no save.
	player = _player(50)
	_play(power, player, null)
	var big: EnemyData = _attacker(60)
	EnemyTurn.take_turn(_enemy(big), big, player)
	_expect_eq(player.hp, 0, "No save when the hit lands from above the line")

	# Self-inflicted loss never triggers it.
	player = _player(3)
	_play(power, player, null)
	_deal(_card("last_wager"), player)
	_expect_eq(player.hp, 0, "Self-damage isn't saved")
	_expect(Status.find_in(player.statuses, power.effects[0].status_data) != null, "Guard untouched by self-damage")
	_completed += 1

# The face's reading: Last Wager's 4 HP is paid after its blow, so it
# goes LIVE only when the player is Critical already - not when its own
# payment would get them there.
func _check_preview() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(25)
	var ctx: EffectContext = _ctx(player, null).for_card_preview(0)
	_expect_eq(CardBonus.state(card, ctx), CardBonus.State.DORMANT, "Last Wager previews DORMANT at 25")
	player.hp = 21
	_expect_eq(CardBonus.state(card, ctx), CardBonus.State.LIVE, "Last Wager previews LIVE at 21")
	player.hp = 30
	_expect_eq(AttackBonus.for_player(player, 21), 0, "No bonus with nothing held")
	_completed += 1

# Reckoning is an Attack: the attack bonus lands on it once, and Self-
# Eater's HP is paid - and made into Toll - before the Toll is spent.
func _check_reckoning() -> void:
	var card: CardData = _card("reckoning")
	var player: Combatant = _player(50)
	_play(_card("self_eater"), player, null)
	player.toll = 5
	_expect_eq(_deal(card, player), 10, "Reckoning under Self-Eater: 5 Toll + 2 made + 3")
	_expect_eq(player.hp, 48, "Self-Eater's price paid")
	_expect_eq(player.toll, 0, "Reckoning spends all of it")
	_expect_eq(_deal(card, player), 5, "Reckoning at 0 Toll: 2 made + 3")

	player = _player(20)
	_play(_card("last_resort"), player, null)
	_play(_card("dying_light"), player, null)
	player.toll = 4
	_expect_eq(_deal(card, player), 13, "Reckoning at Critical: 4 + 6 + 3")
	player.toll = 4
	player.hp = 40
	_expect_eq(_deal(card, player), 4, "Reckoning above the line: Toll only")
	_completed += 1

# What the faces print. Each half of a Critical card is read in its own
# state: the {else} half without the Critical-only bonuses, the {if}
# half with them. Reckoning prints the blow it will land.
func _check_faces() -> void:
	var player: Combatant = _player(20)
	_play(_card("last_resort"), player, null)
	_play(_card("dying_light"), player, null)
	var face: String = await _face("cornered", player)
	_expect(face.contains("Deal 8 damage"), "Cornered's {else} half without Critical bonuses: " + face)
	_expect(face.contains("deal 25"), "Cornered's {if} half with them (16 + 6 + 3): " + face)

	player.hp = 25
	face = await _face("last_wager", player)
	_expect(face.begins_with("Deal 16 damage"), "Last Wager's {else} half, first: " + face)
	_expect(face.contains("deal 35"), "Last Wager's {if} half (26 + 6 + 3): " + face)
	_expect(face.ends_with("Lose 4 HP."), "Last Wager's HP line, last: " + face)
	_expect_eq(await _face_state("last_wager", player), CardBonus.State.DORMANT, "Last Wager's face DORMANT at 25")
	player.hp = 21
	_expect_eq(await _face_state("last_wager", player), CardBonus.State.LIVE, "Last Wager's face LIVE at 21")

	face = await _face("unbroken", player)
	_expect(face.contains("Gain 0 block") and face.contains("gain 0"), "Unbroken under Last Resort: " + face)

	player = _player(50)
	_play(_card("self_eater"), player, null)
	player.toll = 5
	face = await _face("reckoning", player)
	_expect(face.contains("Deal 10 damage"), "Reckoning's face under Self-Eater: " + face)

	player.hp = 21
	face = await _face("cornered", player)
	_expect(face.contains("Deal 11 damage") and face.contains("deal 19"), "Self-Eater's bonus is in both halves: " + face)
	_completed += 1

# --- Helpers ---

# The rules text a battle-hand face shows for `card_name` against
# `player`, colour tags stripped.
func _face(card_name: String, player: Combatant) -> String:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_stance(player.stance)
	view.set_toll(player.toll)
	view.set_bonus_context(_ctx(player, null))
	view.set_card_data(_card(card_name))
	var regex := RegEx.new()
	regex.compile("\\[/?[a-z]+(=[^\\]]*)?\\]")
	var text: String = regex.sub(view.rules_text.text, "", true)
	view.queue_free()
	return text

# The LIVE/DORMANT reading a battle-hand face shows for `card_name`.
func _face_state(card_name: String, player: Combatant) -> CardBonus.State:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_stance(player.stance)
	view.set_toll(player.toll)
	view.set_bonus_context(_ctx(player, null))
	view.set_card_data(_card(card_name))
	var state: CardBonus.State = view._bonus_state
	view.queue_free()
	return state

func _player(hp: int) -> Combatant:
	var player := Combatant.new(MAX_HP)
	player.hp = hp
	player.critical_hp_fraction = CRITICAL_FRACTION
	return player

func _card(card_name: String) -> CardData:
	return load("res://cards/data/%s.tres" % card_name) as CardData

func _attacker(damage: int) -> EnemyData:
	var intent := EnemyIntent.new()
	intent.type = EnemyIntent.IntentType.ATTACK
	intent.value = damage
	var data := EnemyData.new()
	data.max_hp = 50
	data.intents = [intent]
	return data

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _ctx(player: Combatant, target: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	if target != null:
		ctx.enemies = [target]
	else:
		ctx.enemies = [Combatant.new(100)]
	return ctx

func _play(card: CardData, player: Combatant, target: Combatant) -> void:
	_resolver.resolve_card(card, _ctx(player, target))

# Plays `card` into a fresh 100 HP enemy; returns the damage it took.
func _deal(card: CardData, player: Combatant) -> int:
	var enemy := Combatant.new(100)
	_play(card, player, enemy)
	return 100 - enemy.hp

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_failures += 1
		print("FAIL: ", label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_failures += 1
		print("FAIL: %s (got %s, expected %s)" % [label, str(actual), str(expected)])
