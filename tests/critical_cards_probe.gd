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
const CASES := 14
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
	_check_refuse_the_end_copies()
	_check_preview()
	_check_reckoning()
	await _check_faces()
	await _check_refuse_the_end_face()
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
	_expect_eq(_deal(card, _player(21)), 14, "Cornered while Critical")
	_completed += 1

# 6 block either way; at Critical, the Unbroken status too: until the
# player's next turn, each enemy Attack against them deals 4 less in all
# (Unbroken+ 6), soaked hit by hit like Garnish (4×3 lands 0, 4, 4),
# after other modifiers and before block. An attack doesn't spend it -
# the next one is cut as well - and it goes as the player's turn starts.
# Two stack; with Garnish on the attacker, they add.
func _check_unbroken() -> void:
	var card: CardData = _card("unbroken")
	var player: Combatant = _player(50)
	_play(card, player, null)
	_expect_eq(player.block, 6, "Unbroken above the line: 6 block")
	_expect(_unbroken(player) == null, "...and no guard")
	player = _player(10)
	_play(card, player, null)
	_expect_eq(player.block, 6, "Unbroken while Critical: 6 block")
	var guard: Status = _unbroken(player)
	_expect(guard != null and guard.magnitude == 4, "...and Unbroken 4")
	if guard != null:
		_expect_eq(guard.describe(), "Until your next turn, take 4 less from each attack.", "...its hover")
	player.block = 0
	var defender := EnemyData.new()
	var defend := EnemyIntent.new()
	defend.type = EnemyIntent.IntentType.DEFEND
	defend.value = 5
	defender.max_hp = 50
	defender.intents = [defend]
	EnemyTurn.take_turn(_enemy(defender), defender, player)
	_expect(_unbroken(player) != null, "A Defend leaves it")
	var lash: EnemyData = _attacker_hits(4, 3)
	var enemy: Combatant = _enemy(lash)
	_expect_eq(EnemyTurn.preview_intent(enemy, lash, player)["hit_amounts"], [0, 4, 4] as Array[int], "4×3 previews 0, 4, 4")
	var result: Dictionary = EnemyTurn.take_turn(enemy, lash, player)
	_expect_eq(int(result["damage_to_hp"]), 8, "...and lands 8")
	_expect(_unbroken(player) != null, "...leaving it up")
	player.hp = 10
	enemy = _enemy(lash)
	_expect_eq(EnemyTurn.preview_intent(enemy, lash, player)["hit_amounts"], [0, 4, 4] as Array[int], "A second 4×3 previews 0, 4, 4 too")
	result = EnemyTurn.take_turn(enemy, lash, player)
	_expect_eq(int(result["damage_to_hp"]), 8, "...and lands 8")
	# The player's turn starts: its tick and expiry, as BattleController's.
	Status.tick_all(player.statuses, func(_amount: int, _ticking: Status) -> void: pass)
	Status.remove_expired(player.statuses)
	_expect(_unbroken(player) == null, "Gone as the player's next turn starts")
	player = _player(10)
	_play(load("res://cards/tempered/unbroken_tempered.tres"), player, null)
	var tempered_guard: Status = Status.find_in(player.statuses, load("res://battle/rules/statuses/unbroken_tempered.tres"))
	_expect(tempered_guard != null and tempered_guard.magnitude == 6, "Unbroken+ while Critical: Unbroken 6")
	if tempered_guard != null:
		_expect_eq(tempered_guard.describe(), "Until your next turn, take 6 less from each attack.", "...its hover")
	player.block = 0
	enemy = _enemy(lash)
	_expect_eq(EnemyTurn.preview_intent(enemy, lash, player)["hit_amounts"], [0, 0, 4] as Array[int], "4×3 against Unbroken+ previews 0, 0, 4")
	player = _player(10)
	_play(card, player, null)
	_play(card, player, null)
	guard = _unbroken(player)
	_expect(guard != null and guard.magnitude == 8, "Two at Critical stack to 8")
	player.block = 0
	var hit: EnemyData = _attacker(10)
	enemy = _enemy(hit)
	var ctx: EffectContext = _ctx(player, enemy)
	_resolver.resolve_card(load("res://cards/data/garnish.tres"), ctx)
	_expect_eq(int(EnemyTurn.take_turn(enemy, hit, player)["damage_to_hp"]), 0, "With Garnish's 5 on the attacker, a 10 lands 0 (10 - 8 - 5)")
	_completed += 1

func _unbroken(player: Combatant) -> Status:
	return Status.find_in(player.statuses, load("res://battle/rules/statuses/unbroken.tres"))

# Last Wager pays first and attacks after: its 8 HP, then 12 - or 32 when
# that 8 took the player from above the line (21 of 70) to at or under
# it. Already Critical: 12. The loss makes Toll; at 8 HP it still kills,
# like any self-damage, with the blow landing first. last_wager_probe
# has the other lines, the Toll and the fight.
func _check_last_wager() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(35)
	_expect_eq(_deal(card, player), 12, "Last Wager at 35 (27 after): 12")
	_expect_eq(player.hp, 27, "...having lost 8 HP")
	_expect_eq(player.toll, 8, "Last Wager makes 8 Toll")

	player = _player(29)
	_expect_eq(_deal(card, player), 32, "Last Wager at 29: its 8 HP takes it to 21, into Critical - 32")
	_expect(player.is_critical(), "...Critical afterward")

	player = _player(21)
	_expect_eq(_deal(card, player), 12, "Last Wager already Critical at 21: 12")
	_expect_eq(player.hp, 13, "...having lost 8 HP")

	# The order itself: the payment is reported before the blow.
	player = _player(35)
	var enemy := Combatant.new(100)
	var ctx: EffectContext = _ctx(player, enemy)
	var reports: Array[String] = []
	ctx.on_damage = func(who: Combatant, amount: int, kind: String) -> void:
		reports.append("%s %d %s" % ["player" if who == player else "enemy", amount, kind])
	_resolver.resolve_card(card, ctx)
	_expect_eq(reports, ["player 8 self", "enemy 12 card"] as Array[String], "Last Wager: HP first, damage second")

	# The payment can kill - the blow still lands after it.
	player = _player(8)
	enemy = Combatant.new(12)
	_play(card, player, enemy)
	_expect_eq(player.hp, 0, "Last Wager at 8 HP: its 8 kills, like Bite Down")
	_expect_eq(enemy.hp, 0, "...and its 12 still lands")
	_completed += 1

# Last Wager's attack bonus goes through the normal pipeline, read after
# every HP the card costs. Self-Eater's 2 is one of them, so it counts
# toward the crossing too.
func _check_last_wager_bonus() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(50)
	_play(_card("self_eater"), player, null)
	_expect_eq(_deal(card, player), 15, "Last Wager under Self-Eater at 50: 12 + 3")
	_expect_eq(player.hp, 40, "...Self-Eater's 2 and Last Wager's 8 paid")
	_expect_eq(player.toll, 10, "...and made into 10 Toll")
	player = _player(31)
	_play(_card("self_eater"), player, null)
	_expect_eq(_deal(card, player), 35, "...at 31: 2 + 8 take it to 21, into Critical - 32 + 3")

	player = _player(29)
	_play(_card("last_resort"), player, null)
	_expect_eq(_deal(card, player), 38, "Last Wager at 29 under Last Resort: into Critical, 32 + 6")
	_expect_eq(_deal(card, player), 18, "...again at 21, already Critical: 12 + 6")
	_expect_eq(_deal(card, _player(35)), 12, "Above the line after (35 to 27), no Last Resort: 12")
	_completed += 1

# Dying Light is Energy now, not damage: Critical at a turn's start gives
# 1 more (Combatant.turn_start_energy()), nothing above the line; it adds
# no attack bonus; and a second copy can't be played while it's held.
# The fight itself (the refill, entering Critical mid-turn, the faded
# face) is dying_light_probe's.
func _check_dying_light() -> void:
	var power: CardData = _card("dying_light")
	var cornered: CardData = _card("cornered")
	var player: Combatant = _player(50)
	_expect_eq(player.turn_start_energy(), 3, "No Dying Light: a turn starts on 3")
	_play(power, player, null)
	_expect_eq(player.turn_start_energy(), 3, "Dying Light above the line: still 3")
	player.hp = 20
	_expect_eq(player.turn_start_energy(), 4, "Dying Light while Critical: 4")
	_expect_eq(_deal(cornered, player), 14, "...and no attack bonus: Cornered's Critical 14, nothing added")
	_expect(EffectResolver.card_blocked(power, player), "A second Dying Light can't be played while one is held")
	_expect_eq(Status.new(load("res://battle/rules/statuses/dying_light.tres") as StatusData).describe(), "While Critical, gain 1 Energy at the start of your turn.", "Its readout line matches the card")
	_expect_eq(power.description, "While Critical, gain 1 Energy at the start of your turn.", "...and the card says so")
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
	_expect_eq(_deal(cornered, player), 28, "Dying Light beside Last Resort ×2 adds no damage")
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

# A two-hit Attack under Last Resort at Critical takes the bonus once, on
# its first damage effect.
func _check_bonus_once_per_card() -> void:
	var player: Combatant = _player(20)
	_play(_card("last_resort"), player, null)
	var card := CardData.new()
	card.card_type = CardData.CardType.ATTACK
	for i in 2:
		var hit := CardEffect.new()
		hit.effect_type = CardEffect.EffectType.DAMAGE
		hit.value = 5
		card.effects.append(hit)
	_expect_eq(_deal(card, player), 16, "Two-hit Attack: 5 + 6 bonus + 5")
	_completed += 1

# Refuse the End: an enemy's lethal hit on a player who was Critical
# before it leaves them at 15% of max HP - 10 of 70 - raised to it from
# below, and spends one save. Never from above the line, never for
# self-inflicted loss.
func _check_refuse_the_end() -> void:
	var power: CardData = _card("refuse_the_end")
	var guard: StatusData = power.effects[0].status_data
	_expect_eq(power.removal_scope, CardData.RemovalScope.SPENT, "Refuse the End is Spent")
	_expect_eq(guard.survive_hp(70, CRITICAL_FRACTION), 10, "It survives at 10 at 70 max HP")
	_expect_eq(guard.survive_hp(100, CRITICAL_FRACTION), 15, "...15 at 100")
	_expect_eq(guard.survive_hp(4, CRITICAL_FRACTION), 1, "...at least 1 (4 max HP)")
	# Never above the Critical line: a fraction past it clamps to its top.
	var greedy: StatusData = guard.duplicate()
	greedy.survive_fraction = 0.5
	_expect_eq(greedy.survive_hp(70, CRITICAL_FRACTION), 21, "A fraction past the line clamps to the highest Critical HP: 21 at 70")
	_expect_eq(greedy.survive_hp(40, CRITICAL_FRACTION), 12, "...12 at 40")
	for max_hp: int in [10, 37, 70, 101]:
		var top: int = greedy.survive_hp(max_hp, CRITICAL_FRACTION)
		_expect(Combatant.critical_at(top, max_hp, CRITICAL_FRACTION) and not Combatant.critical_at(top + 1, max_hp, CRITICAL_FRACTION), "...at %d max HP: %d, the top of the line" % [max_hp, top])

	# Saved from below its survive HP: raised to it, nothing lost.
	var player: Combatant = _player(5)
	_play(power, player, null)
	var data: EnemyData = _attacker(30)
	var enemy: Combatant = _enemy(data)
	_expect(not bool(EnemyTurn.preview_intent(enemy, data, player)["lethal"]), "Intent isn't lethal while a save is armed")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 10, "Saved from 5: raised to 10")
	_expect_eq(int(result["damage_to_hp"]), 0, "...nothing lost")
	_expect_eq(int(result["saved_heal"]), 5, "...the 5 it rose reported as a heal, for the run's HP")
	_expect(Status.find_in(player.statuses, guard) == null, "Its one save spent, it's gone")
	_expect(player.spent_statuses.has(guard), "...and reads as spent")
	_expect(bool(EnemyTurn.preview_intent(enemy, data, player)["lethal"]), "Intent lethal again once spent")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 0, "The next lethal hit kills")

	# Saved from above it: the hit takes them down to it.
	player = _player(18)
	_play(power, player, null)
	result = EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, 10, "Saved from 18: left at 10")
	_expect_eq(int(result["damage_to_hp"]), 8, "...the 8 it lost reported")
	_expect_eq(int(result["saved_heal"]), 0, "...and no heal")

	# The preview knows where a save leaves them - 10, not 1: from 5, two
	# hits of 9 are saved then survived; two of 10 are saved then lethal.
	player = _player(5)
	_play(power, player, null)
	var nines: EnemyData = _attacker_hits(9, 2)
	_expect(not bool(EnemyTurn.preview_intent(_enemy(nines), nines, player)["lethal"]), "Saved at 10, a second hit of 9 isn't lethal")
	var tens: EnemyData = _attacker_hits(10, 2)
	_expect(bool(EnemyTurn.preview_intent(_enemy(tens), tens, player)["lethal"]), "...a second hit of 10 is")

	# Not Critical before the hit: no save.
	player = _player(50)
	_play(power, player, null)
	var big: EnemyData = _attacker(60)
	EnemyTurn.take_turn(_enemy(big), big, player)
	_expect_eq(player.hp, 0, "No save when the hit lands from above the line")

	# Self-inflicted loss never triggers it.
	player = _player(8)
	_play(power, player, null)
	_deal(_card("last_wager"), player)
	_expect_eq(player.hp, 0, "Self-damage isn't saved")
	_expect(Status.find_in(player.statuses, guard) != null, "Guard untouched by self-damage")
	_completed += 1

# Each copy arms one save: two played give two in one fight - both spent
# by one two-hit attack, a lethal hit each - and a copy played after they
# fired arms another. The standing row counts them.
func _check_refuse_the_end_copies() -> void:
	var power: CardData = _card("refuse_the_end")
	var guard: StatusData = power.effects[0].status_data
	var player: Combatant = _player(5)
	_play(power, player, null)
	_expect(not EffectResolver.card_blocked(power, player), "A second copy can be played while one is armed")
	_play(power, player, null)
	var armed: Status = Status.find_in(player.statuses, guard)
	_expect(armed != null and armed.charges == 2, "Two copies: two saves armed")
	if armed != null:
		_expect_eq(armed.label(), "Refuse the End ×2", "...read as \"Refuse the End ×2\"")
	var twice: EnemyData = _attacker_hits(30, 2)
	var enemy: Combatant = _enemy(twice)
	_expect(not bool(EnemyTurn.preview_intent(enemy, twice, player)["lethal"]), "Two lethal hits preview as survived with two saves")
	EnemyTurn.take_turn(enemy, twice, player)
	_expect_eq(player.hp, 10, "...and are: both saved, at 10")
	_expect(Status.find_in(player.statuses, guard) == null, "Both saves spent")
	_expect_eq(player.spent_statuses.count(guard), 1, "...one spent line, however many fired")
	_play(power, player, null)
	armed = Status.find_in(player.statuses, guard)
	_expect(armed != null and armed.charges == 1, "A copy played after they fired arms one more")
	if armed != null:
		_expect_eq(armed.label(), "Refuse the End ×1", "...read as \"Refuse the End ×1\"")
	_expect(bool(EnemyTurn.preview_intent(enemy, twice, player)["lethal"]), "One save against two lethal hits: lethal")
	var once: EnemyData = _attacker(30)
	enemy = _enemy(once)
	EnemyTurn.take_turn(enemy, once, player)
	_expect_eq(player.hp, 10, "The third save holds, at 10")
	EnemyTurn.take_turn(enemy, once, player)
	_expect_eq(player.hp, 0, "...and with none left the next lethal hit kills")
	_completed += 1

# The face and the readout print the live survive HP: the fight's player
# in a battle hand, the run's max HP anywhere else - and the readout says
# what the card says.
func _check_refuse_the_end_face() -> void:
	var power: CardData = _card("refuse_the_end")
	var guard: StatusData = power.effects[0].status_data
	var player: Combatant = _player(5)
	var face: String = await _face("refuse_the_end", player)
	_expect_eq(face, "The next time an enemy would kill you while Critical, survive at 10 HP.\nSpent.", "The face in battle, at 70 max HP")
	var small := Combatant.new(40)
	small.hp = 5
	small.critical_hp_fraction = CRITICAL_FRACTION
	face = await _face("refuse_the_end", small)
	_expect(face.contains("survive at 6 HP"), "...at 40 max HP: 6 - " + face)
	var run_state: Node = root.get_node_or_null(^"RunState")
	var run_max: int = int(run_state.get(&"player_max_hp")) if run_state != null else 0
	if run_state != null:
		run_state.set(&"player_max_hp", 100)
	face = await _face_out_of_battle("refuse_the_end")
	_expect(face.contains("survive at 15 HP"), "Out of battle, for the run's 100 max HP: 15 - " + face)
	if run_state != null:
		run_state.set(&"player_max_hp", run_max)
	_play(power, small, null)
	var armed: Status = Status.find_in(small.statuses, guard)
	_expect(armed != null and armed.describe(small) == "The next time an enemy would kill you while Critical, survive at 6 HP.", "The readout says what the card says, its number the holder's")
	_completed += 1

# The face's reading: Last Wager's 8 HP is paid before its blow, so it
# goes LIVE only when that payment would take the player into Critical -
# not above the line after it, and not when they're Critical already.
func _check_preview() -> void:
	var card: CardData = _card("last_wager")
	var player: Combatant = _player(29)
	var ctx: EffectContext = _ctx(player, null).for_card_preview(8)
	_expect_eq(CardBonus.state(card, ctx), CardBonus.State.LIVE, "Last Wager previews LIVE at 29 (21 after its 8)")
	player.hp = 35
	_expect_eq(CardBonus.state(card, ctx), CardBonus.State.DORMANT, "...DORMANT at 35 (27 after)")
	player.hp = 21
	_expect_eq(CardBonus.state(card, ctx), CardBonus.State.DORMANT, "...DORMANT at 21, already Critical")
	player.hp = 30
	_expect_eq(AttackBonus.for_player(player, 21), 0, "No bonus with nothing held")
	_completed += 1

# Reckoning is an Attack: the attack bonus lands on it once, on top of
# the Toll spent this fight. Self-Eater's HP price makes Toll but spends
# none, so it adds nothing to the tally.
func _check_reckoning() -> void:
	var card: CardData = _card("reckoning")
	var player: Combatant = _player(50)
	_play(_card("self_eater"), player, null)
	player.toll_spent_this_fight = 5
	_expect_eq(_deal(card, player), 8, "Reckoning under Self-Eater: 5 spent + 3")
	_expect_eq(player.hp, 48, "Self-Eater's price paid")
	_expect_eq(player.toll_spent_this_fight, 5, "...the tally untouched: the price made Toll, spent none")
	player.toll_spent_this_fight = 0
	_expect_eq(_deal(card, player), 3, "Reckoning with nothing spent: the 3 alone")

	player = _player(20)
	_play(_card("last_resort"), player, null)
	player.toll_spent_this_fight = 4
	_expect_eq(_deal(card, player), 10, "Reckoning at Critical: 4 + 6")
	player.hp = 40
	_expect_eq(_deal(card, player), 4, "Reckoning above the line: the tally only")
	_completed += 1

# What the faces print. Each half of a Critical card is read in its own
# state: the {else} half without the Critical-only bonuses, the {if}
# half with them. Reckoning prints the blow it will land.
func _check_faces() -> void:
	var player: Combatant = _player(20)
	_play(_card("last_resort"), player, null)
	var face: String = await _face("cornered", player)
	_expect(face.contains("Deal 8 damage"), "Cornered's {else} half without Critical bonuses: " + face)
	_expect(face.contains("deal 22"), "Cornered's {if} half with them (16 + 6): " + face)

	# Last Wager under Last Resort: its {if} half lands Critical (32 + 6);
	# its {else} half prints the bonus as the 8 HP would leave it - at 25
	# that's Critical too (12 + 6), at 40 it isn't (12).
	player.hp = 25
	face = await _face("last_wager", player)
	_expect(face.begins_with("Deal 18 damage"), "Last Wager's {else} half at 25, Critical after its 8 (12 + 6): " + face)
	_expect(face.contains("deal 38"), "Last Wager's {if} half (32 + 6): " + face)
	_expect_eq(await _face_state("last_wager", player), CardBonus.State.LIVE, "Last Wager's face LIVE at 25 (17 after)")
	player.hp = 40
	face = await _face("last_wager", player)
	_expect(face.begins_with("Deal 12 damage"), "Last Wager's {else} half at 40: " + face)
	_expect_eq(await _face_state("last_wager", player), CardBonus.State.DORMANT, "...DORMANT at 40 (32 after)")
	player.hp = 21
	_expect_eq(await _face_state("last_wager", player), CardBonus.State.DORMANT, "...DORMANT at 21, already Critical")

	face = await _face("unbroken", player)
	_expect(face == "Gain 0 block.\nCritical: until your next turn, take 4 less from each attack.", "Unbroken under Last Resort: no block, the guard still there: " + face)
	_expect_eq(await _face_state("unbroken", player), CardBonus.State.LIVE, "...its Critical line LIVE at 21")
	player.hp = 50
	_expect_eq(await _face_state("unbroken", player), CardBonus.State.DORMANT, "...and DORMANT at 50")
	player.hp = 21

	player = _player(50)
	_play(_card("self_eater"), player, null)
	player.toll_spent_this_fight = 5
	face = await _face("reckoning", player)
	_expect(face.contains("Deal 8 damage"), "Reckoning's face under Self-Eater: 5 spent + 3: " + face)

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

# The rules text a face shows for `card_name` outside a battle hand (the
# deck view, the compendium) - no fight to read, colour tags stripped.
func _face_out_of_battle(card_name: String) -> String:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
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

# One ATTACK intent of `hits` hits, `damage` each.
func _attacker_hits(damage: int, hits: int) -> EnemyData:
	var data: EnemyData = _attacker(damage)
	data.intents[0].hits = hits
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
