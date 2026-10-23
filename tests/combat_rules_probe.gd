extends SceneTree

# Core probe: the fight's rules, on the rules layer alone (Combatant,
# EnemyTurn, EffectResolver, Status, Deck) - no scene. Every number is read
# from the data or made here; none is pinned, so a retune never breaks it.
#
#   enemies  - every enemy under battle/rules/enemies/, its loop run for
#              two rounds: each turn what preview_intent() shows is what
#              take_turn() lands, hit by hit, with no Block and again with
#              some - the HP the preview says reaches him is what does
#   energy   - a turn starts on the refill; a card costs its cost and is
#              payable on exactly that; a gain adds its number
#   statuses - a ticking status deals its magnitude each tick, ages, and is
#              gone when it runs out; one that decays loses its decay a
#              tick and is gone at 0
#   marks    - the intent marks (Brace, Garnish, Wrest - every card whose
#              status has an intent_mark), on the largest attack in the
#              data: each lands no more than unmarked, preview equal to
#              landing; two marks land the same whichever went on first;
#              Wrest's Block is what it took off the preview; each mark is
#              spent by the attack
#   deny     - Delay (a status that delays_next_action): the turn lands
#              nothing, the turn after performs the held move
#   keep     - a kept card stays in the hand through the end of the turn
#   copy     - a fight-only copy is gone at the end of the turn, in no pile
#   turn     - an extra turn (grants_extra_turn) is taken once a charge
#   toll     - a status that has Toll pay damage takes the Toll first, the
#              rest to HP
#   critical - Critical at or under the line, not above; a status that
#              raises the line moves it
#
# Any SCRIPT ERROR or engine ERROR fails it (tools/run_probes.sh).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/combat_rules_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const ENEMIES_DIR := "res://battle/rules/enemies/"
const STATUSES_DIR := "res://battle/rules/statuses/"
const POOLS_DIR := "res://cards/pools/"
const CHARACTERS: Array[String] = ["res://run/data/wanderer.tres", "res://run/data/samurai.tres"]
const LOOP_ROUNDS := 2
const PLAYER_HP := 9999
const SAFETY_SECONDS := 120.0

var _failures: int = 0
var _cases: int = 0
var _resolver := EffectResolver.new()
var _cards: Array[CardData] = []
var _enemies: Array[EnemyData] = []

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_cards = _all_cards()
	_enemies = _all_enemies()
	_expect(not _cards.is_empty() and not _enemies.is_empty(), "The data: %d cards, %d enemies" % [_cards.size(), _enemies.size()])
	_check_enemy_loops()
	_check_energy()
	_check_statuses()
	_check_marks()
	_check_deny()
	_check_keep_and_copy()
	_check_extra_turn()
	_check_toll_pays()
	_check_critical()
	if _cases != 9:
		_fail("%d of 9 cases ran to their end" % _cases)
	if _failures == 0:
		print("combat_rules_probe: PASSED")
		quit(0)
	else:
		print("combat_rules_probe: %d FAILED" % _failures)
		quit(1)

# --- enemies ---

func _check_enemy_loops() -> void:
	var compared: int = 0
	for data in _enemies:
		var enemy: Combatant = _fresh_enemy(data)
		var turns: int = maxi(data.intents.size(), 1) * LOOP_ROUNDS
		for turn in turns:
			var player := Combatant.new(PLAYER_HP)
			var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
			# A Signal's answers land through its packmates' own turns, not
			# this one's.
			if preview.has("answers"):
				EnemyTurn.take_turn(enemy, data, player)
				continue
			var hits: Array[int] = _ints(preview.get("hit_amounts", []))
			var block: int = _sum(hits) / 2
			# Twin of the enemy at this turn, for the pass with Block.
			var twin: Combatant = _twin(enemy, data)
			var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
			var landed: Array[int] = []
			for hit: Dictionary in result["hits"]:
				landed.append(int(hit["damage"]))
			var label: String = "%s turn %d (%s)" % [data.enemy_name, turn + 1, str(result.get("intent", ""))]
			_expect_eq(landed, hits, "%s: lands what it previews" % label)
			compared += 1
			if block > 0 and twin != null:
				var guarded := Combatant.new(PLAYER_HP)
				guarded.block = block
				var guarded_preview: Dictionary = EnemyTurn.preview_intent(twin, data, guarded)
				var hp_before: int = guarded.hp
				EnemyTurn.take_turn(twin, data, guarded)
				_expect_eq(hp_before - guarded.hp, int(guarded_preview.get("damage_to_hp", -1)), "%s: behind %d Block, the HP previewed is the HP lost" % [label, block])
	print("enemies: %d enemies, %d turns compared" % [_enemies.size(), compared])
	_cases += 1

# --- energy ---

func _check_energy() -> void:
	var player := Combatant.new(PLAYER_HP)
	_expect_eq(player.turn_start_energy(), player.max_energy, "A turn starts on the refill")
	var priced: CardData = null
	for card in _cards:
		if card.cost >= 1 and card.critical_cost < 0:
			priced = card
			break
	if priced != null:
		player.energy = priced.cost
		_expect_eq(player.energy_cost(priced), priced.cost, "%s costs its %d" % [priced.card_name, priced.cost])
		_expect(player.can_pay(priced), "...payable on exactly that")
		player.energy = priced.cost - 1
		_expect(not player.can_pay(priced), "...and not on one less")
	var gain: CardEffect = _first_effect(CardEffect.EffectType.GAIN_ENERGY)
	if gain != null:
		player.energy = 0
		_resolve_effect(gain, player, null)
		_expect_eq(player.energy, gain.value, "A gain of Energy adds its %d" % gain.value)
	_cases += 1

# --- statuses ---

func _check_statuses() -> void:
	var tick := StatusData.new()
	tick.id = "probe_tick"
	tick.category = StatusData.Category.TICK
	tick.default_magnitude = 2
	tick.default_duration_turns = 2
	var player := Combatant.new(PLAYER_HP)
	Status.apply_to(player.statuses, tick)
	for turn in 2:
		var dealt: Array[int] = [0]
		Status.tick_all(player.statuses, func(amount: int, _ticking: Status) -> void: dealt[0] += amount)
		Status.remove_expired(player.statuses)
		_expect_eq(dealt[0], tick.default_magnitude, "A ticking status deals its magnitude (tick %d)" % (turn + 1))
	_expect(Status.find_in(player.statuses, tick) == null, "...and is gone when its turns run out")
	var decaying: StatusData = null
	for status in _all_statuses():
		if status.category == StatusData.Category.TICK and status.tick_decay > 0:
			decaying = status
			break
	if decaying != null:
		var held := Combatant.new(PLAYER_HP)
		Status.apply_to(held.statuses, decaying)
		var active: Status = Status.find_in(held.statuses, decaying)
		var start: int = active.magnitude
		Status.tick_all(held.statuses, func(_amount: int, _ticking: Status) -> void: pass)
		if start > decaying.tick_decay:
			_expect_eq(active.magnitude, start - decaying.tick_decay, "%s decays by %d a tick" % [decaying.display_name, decaying.tick_decay])
		for i in start:
			Status.tick_all(held.statuses, func(_amount: int, _ticking: Status) -> void: pass)
			Status.remove_expired(held.statuses)
		_expect(Status.find_in(held.statuses, decaying) == null, "...and is gone at 0")
	_cases += 1

# --- marks ---

func _check_marks() -> void:
	var marks: Array[CardData] = []
	for card in _cards:
		for effect in card.effects:
			var status: StatusData = EffectResolver.intent_mark_status(effect)
			if status != null and not _has_mark(marks, status.intent_mark):
				marks.append(card)
				break
	_expect(marks.size() >= 2, "The intent marks found (%d)" % marks.size())
	var attack: Array = _largest_attack()
	if attack.is_empty():
		_fail("No attack in the enemy data to mark")
		_cases += 1
		return
	var data: EnemyData = attack[0]
	var index: int = attack[1]
	print("marks: %s on %s's %s" % [str(marks.map(func(c: CardData) -> String: return c.card_name)), data.enemy_name, data.intents[index].intent_name])
	var unmarked: int = _sum(_ints(EnemyTurn.preview_intent(_queued(data, index), data, Combatant.new(PLAYER_HP)).get("hit_amounts", [])))
	for card in marks:
		var enemy: Combatant = _queued(data, index)
		var player := Combatant.new(PLAYER_HP)
		player.toll = 99
		var before: int = _sum(_ints(EnemyTurn.preview_intent(enemy, data, player).get("hit_amounts", [])))
		_resolve(card, player, enemy)
		var gained: int = player.block
		player.block = 0
		var after: int = _expect_attack(enemy, data, player, "%s on %s" % [card.card_name, data.enemy_name])
		_expect(after <= unmarked, "...landing no more than unmarked (%d of %d)" % [after, unmarked])
		if _effect_of(card, CardEffect.EffectType.TAKE_FROM_ATTACK) != null:
			_expect_eq(gained, before - after, "...its Block what it took off")
		_expect(_marks_on(enemy) == 0, "...and the mark spent by the attack")
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			var a: CardData = marks[i]
			var b: CardData = marks[j]
			var first: int = _land_marked(data, index, [a, b])
			var second: int = _land_marked(data, index, [b, a])
			if _effect_of(a, CardEffect.EffectType.TAKE_FROM_ATTACK) == null and _effect_of(b, CardEffect.EffectType.TAKE_FROM_ATTACK) == null:
				_expect_eq(first, second, "%s and %s land the same in either order" % [a.card_name, b.card_name])
	_cases += 1

func _land_marked(data: EnemyData, index: int, cards: Array) -> int:
	var enemy: Combatant = _queued(data, index)
	var player := Combatant.new(PLAYER_HP)
	player.toll = 99
	for card: CardData in cards:
		_resolve(card, player, enemy)
	player.block = 0
	return _expect_attack(enemy, data, player, "%s on %s" % [" then ".join(cards.map(func(c: CardData) -> String: return c.card_name)), data.enemy_name])

# --- deny ---

func _check_deny() -> void:
	var deny: CardData = null
	for card in _cards:
		for effect in card.effects:
			if effect.status_data != null and effect.status_data.delays_next_action:
				deny = card
		if deny != null:
			break
	if deny == null:
		_fail("No card delays an enemy")
		_cases += 1
		return
	var attack: Array = _largest_attack()
	var data: EnemyData = attack[0]
	var enemy: Combatant = _queued(data, attack[1])
	var held: String = EnemyTurn.current_intent(enemy, data).intent_name
	var player := Combatant.new(PLAYER_HP)
	player.toll = 99
	_resolve(deny, player, enemy)
	var hp_before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result.get("delayed", false)) and (result["hits"] as Array).is_empty() and player.hp == hp_before, "%s: the delayed turn lands nothing" % deny.card_name)
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, held, "...and the move is still held")
	_expect_attack(enemy, data, player, "...performed the turn after")
	_cases += 1

# --- keep, copy ---

func _check_keep_and_copy() -> void:
	var cards: Array[CardData] = []
	for i in 3:
		cards.append(_cards[i % _cards.size()].duplicate())
	var deck := Deck.new(cards)
	deck.draw(3)
	var kept: CardData = deck.hand[0]
	deck.grant_keep(kept)
	var copy: CardData = deck.add_copy(deck.hand[1])
	_expect(copy != null and copy.battle_copy and deck.hand.has(copy), "A copy joins the hand")
	deck.discard_hand()
	_expect(deck.hand.has(kept), "A kept card stays in the hand through the turn's end")
	_expect(not deck.hand.has(copy) and not deck.discard_pile.has(copy) and not deck.draw_pile.has(copy) and not deck.exhaust_pile.has(copy), "...the copy is gone, in no pile")
	_cases += 1

# --- extra turn ---

func _check_extra_turn() -> void:
	var owed: StatusData = null
	for status in _all_statuses():
		if status.grants_extra_turn:
			owed = status
			break
	if owed == null:
		_fail("No status grants an extra turn")
	else:
		var player := Combatant.new(PLAYER_HP)
		Status.apply_to(player.statuses, owed)
		var charges: int = Status.find_in(player.statuses, owed).charges
		for i in charges:
			_expect(Status.take_extra_turn(player.statuses), "%s: an extra turn for charge %d" % [owed.display_name, i + 1])
		_expect(not Status.take_extra_turn(player.statuses), "...and none once they're spent")
	_cases += 1

# --- toll pays damage ---

func _check_toll_pays() -> void:
	var payer: StatusData = null
	for status in _all_statuses():
		if status.toll_pays_damage:
			payer = status
			break
	var attack: Array = _largest_attack()
	if payer == null or attack.is_empty():
		_fail("No status has Toll pay damage")
	else:
		var data: EnemyData = attack[0]
		var enemy: Combatant = _queued(data, attack[1])
		var player := Combatant.new(PLAYER_HP)
		Status.apply_to(player.statuses, payer)
		var total: int = _sum(_ints(EnemyTurn.preview_intent(enemy, data, Combatant.new(PLAYER_HP)).get("hit_amounts", [])))
		var toll: int = maxi(total / 2, 1)
		player.toll = toll
		var hp_before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		_expect_eq(player.toll, maxi(toll - total, 0), "%s: the Toll pays first" % payer.display_name)
		_expect_eq(hp_before - player.hp, maxi(total - toll, 0), "...the rest reaches HP")
	# The weapon's self-loss bonus (Gaff Hook): each self-inflicted loss -
	# the one Toll counts - stores one more; the next Slash takes them all.
	var wielder := Combatant.new(PLAYER_HP)
	wielder.self_loss_attack_bonus = 3
	wielder.self_loss_attack_tag = &"basic_attack"
	wielder.gain_self_loss_toll(1)
	wielder.gain_self_loss_toll(5)
	var slash: CardData = load("res://cards/data/slash.tres")
	_expect_eq([wielder.take_self_loss_attack_bonus(slash), wielder.take_self_loss_attack_bonus(slash)], [6, 0], "Two self-losses: the next Slash takes both, the one after none")
	_cases += 1

# --- critical ---

func _check_critical() -> void:
	var player := Combatant.new(100)
	var line: int = int(floor(player.max_hp * player.critical_fraction()))
	player.hp = line
	_expect(player.is_critical(), "Critical at the line (%d of %d)" % [line, player.max_hp])
	player.hp = line + 1
	_expect(not player.is_critical(), "...not above it")
	var raiser: StatusData = null
	for status in _all_statuses():
		if status.raises_critical_percent > 0:
			raiser = status
			break
	if raiser != null:
		Status.apply_to(player.statuses, raiser)
		var raised: int = int(floor(player.max_hp * raiser.raises_critical_percent / 100.0))
		if raised > line + 1:
			player.hp = raised
			_expect(player.is_critical(), "%s raises the line to %d" % [raiser.display_name, raised])
	_cases += 1

# --- Helpers ---

# Every card the game can deal: every pool's, every class's starters, and
# each one's tempered copy - once each.
func _all_cards() -> Array[CardData]:
	var found: Array[CardData] = []
	for file in DirAccess.get_files_at(POOLS_DIR):
		var pool := load(POOLS_DIR.path_join(file)) as RewardPool
		if pool != null:
			for card: CardData in pool.call("_cards"):
				_add_card(found, card)
	for path in CHARACTERS:
		var character := load(path) as CharacterData
		for card: CardData in character.starting_deck_counts:
			_add_card(found, card)
	for card in found.duplicate():
		_add_card(found, card.tempered)
	return found

func _add_card(found: Array[CardData], card: CardData) -> void:
	if card != null and not found.has(card):
		found.append(card)

func _all_enemies() -> Array[EnemyData]:
	var found: Array[EnemyData] = []
	for file in DirAccess.get_files_at(ENEMIES_DIR):
		if file.ends_with(".tres"):
			var data := load(ENEMIES_DIR.path_join(file)) as EnemyData
			if data != null and not data.intents.is_empty():
				found.append(data)
	return found

func _all_statuses() -> Array[StatusData]:
	var found: Array[StatusData] = []
	for file in DirAccess.get_files_at(STATUSES_DIR):
		if file.ends_with(".tres"):
			var status := load(STATUSES_DIR.path_join(file)) as StatusData
			if status != null:
				found.append(status)
	return found

func _fresh_enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	for status in data.starting_statuses:
		if status != null:
			Status.apply_to(enemy.statuses, status)
	return enemy

# An enemy of `data` with its intent `index` queued.
func _queued(data: EnemyData, index: int) -> Combatant:
	var enemy: Combatant = _fresh_enemy(data)
	enemy.current_intent_index = index
	EnemyTurn._sync_queued(enemy, data)
	return enemy

# A copy of `enemy` as it stands - its queued intent and statuses - for a
# second pass at the same turn; null when it can't be matched.
func _twin(enemy: Combatant, data: EnemyData) -> Combatant:
	var twin: Combatant = _queued(data, enemy.current_intent_index)
	twin.hp = enemy.hp
	twin.turns_taken = enemy.turns_taken
	twin.statuses.clear()
	for active in enemy.statuses:
		Status.apply_to(twin.statuses, active.data)
		var copied: Status = Status.find_in(twin.statuses, active.data)
		if copied != null:
			copied.magnitude = active.magnitude
	return twin

# The enemy intent in the data whose hits total the most, with no
# answers or special state - [data, intent index], or [].
func _largest_attack() -> Array:
	var best: Array = []
	var best_total: int = 0
	for data in _enemies:
		if data.opens_dug_in or data.starts_dormant:
			continue
		for index in data.intents.size():
			var enemy: Combatant = _queued(data, index)
			var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, Combatant.new(PLAYER_HP))
			if preview.has("answers"):
				continue
			var total: int = _sum(_ints(preview.get("hit_amounts", [])))
			if total > best_total:
				best_total = total
				best = [data, index]
	return best

# The preview, then the turn: both the same, hit by hit. What landed.
func _expect_attack(enemy: Combatant, data: EnemyData, player: Combatant, label: String) -> int:
	var preview: Array[int] = _ints(EnemyTurn.preview_intent(enemy, data, player).get("hit_amounts", []))
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	var landed: Array[int] = []
	for hit: Dictionary in result["hits"]:
		landed.append(int(hit["damage"]))
	_expect_eq(landed, preview, "%s: lands what it previews" % label)
	return _sum(landed)

func _marks_on(enemy: Combatant) -> int:
	var count: int = 0
	for active in enemy.statuses:
		if active.data != null and active.data.intent_mark != &"":
			count += 1
	return count

func _has_mark(cards: Array[CardData], mark: StringName) -> bool:
	for card in cards:
		for effect in card.effects:
			var status: StatusData = EffectResolver.intent_mark_status(effect)
			if status != null and status.intent_mark == mark:
				return true
	return false

func _first_effect(type: CardEffect.EffectType) -> CardEffect:
	for card in _cards:
		var effect: CardEffect = _effect_of(card, type)
		if effect != null:
			return effect
	return null

func _effect_of(card: CardData, type: CardEffect.EffectType) -> CardEffect:
	for effect in card.effects:
		if effect != null and effect.effect_type == type:
			return effect
	return null

func _resolve(card: CardData, player: Combatant, target: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = target
	ctx.enemies = [target if target != null else Combatant.new(100)] as Array[Combatant]
	_resolver.resolve_card(card, ctx)

func _resolve_effect(effect: CardEffect, player: Combatant, target: Combatant) -> void:
	var card := CardData.new()
	card.card_name = "Probe"
	card.effects = [effect] as Array[CardEffect]
	_resolve(card, player, target)

func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out

func _sum(values: Array[int]) -> int:
	var total: int = 0
	for value in values:
		total += value
	return total

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
