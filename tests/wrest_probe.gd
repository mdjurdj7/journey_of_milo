extends SceneTree

# Headless probe for Wrest - 2 Energy, Common Skill, GUARD, aimed at one
# enemy's attack intent: it takes up to 7 off that attack (Wrest+ 11) -
# off its landing total as it stands when played, after any Brace or
# Garnish already on it - as Wrested, an intent mark soaked hit by hit as
# Garnish's is, and gives as much Block, once (TakeFromAttackEffect). The
# Block is what it took when played: a Brace played after it doesn't take
# any back. Only an attack that will land may be Wrested, once; a strike
# back neither feels it nor spends it; a stance that forbids Block gives
# none, and the attack is still cut; an intent that won't land loses the
# mark and the Block stays.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/wrest_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real cards through EffectResolver against the real
# enemies' data - the Sputter's Scissor, the Underfoot's Sting and Rebury,
# the Greyshelf's Tail Lash, the Adder's Bite and its strike back - and
# work each expected number out of that data (the intent's value, Braced's
# percentage, the take, Garnish's total), never a written-in number. Every
# attack case checks that what preview_intent() shows is what take_turn()
# lands. The face case reads both copies on a CardView; the fight case
# plays Wrest through BattleController on the real region scene. Untyped
# against anything that names the RunState autoload.

const CASES := 11
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/wrest.tres"
const TEMPERED_PATH := "res://cards/tempered/wrest_tempered.tres"
const STATUS_PATH := "res://battle/rules/statuses/wrested.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const GARNISH_PATH := "res://cards/data/garnish.tres"
const LAST_RESORT_PATH := "res://cards/data/last_resort.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const GARNISHED_PATH := "res://battle/rules/statuses/garnished.tres"
const STUNNED_PATH := "res://battle/rules/statuses/stunned.tres"
const BEREFT_PATH := "res://battle/rules/statuses/bereft.tres"
const COILED_PATH := "res://battle/rules/statuses/coiled.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const UNDERFOOT_PATH := "res://battle/rules/enemies/underfoot.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const ADDER_PATH := "res://battle/rules/enemies/adder.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _take: int = 0
var _garnish_total: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_take = (load(CARD_PATH) as CardData).effects[0].value
	_garnish_total = (load(GARNISHED_PATH) as StatusData).default_magnitude

	_check_data()
	await _check_face()
	_check_targeting()
	_check_tail_lash()
	_check_small_attack()
	_check_brace()
	_check_garnish()
	_check_strike_back()
	_check_no_block_stance()
	_check_lost_mark()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("wrest_probe: PASSED")
		quit(0)
	else:
		print("wrest_probe: %d FAILED" % _failures)
		quit(1)

# --- Data and face ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	var status: StatusData = load(STATUS_PATH)
	_expect_eq([card.card_name, card.card_type, card.rarity, card.target_type, card.card_class, card.offer], ["Wrest", CardData.CardType.SKILL, CardData.CardRarity.COMMON, CardData.TargetType.ENEMY, &"wanderer", CardData.OfferScope.REWARDABLE], "Wrest: a Common Skill at one enemy, the Wanderer's")
	_expect(card.art != null and card.art.resource_path == "res://cards/art/Wanderer/Wrest.png", "...with its art")
	_expect_eq(card.description, "Take up to {take} from an attack.\nGain that much Block.", "...its text")
	_expect(card.effects.size() == 1 and card.effects[0].effect_type == CardEffect.EffectType.TAKE_FROM_ATTACK and card.effects[0].status_data == status, "...one effect: take from an attack, as Wrested")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.GUARD, "...reading GUARD")
	_expect_eq(EffectResolver.intent_mark_status(card.effects[0]), status, "...marking an intent")
	_expect_eq([status.display_name, status.intent_mark, status.reduces_attack_total, status.consumed_by_own_attack, status.ignores_strike_backs], ["Wrested", &"wrest", true, true, true], "Wrested: a mark that cuts the attack's total, spent by it, passed by a strike back")
	var tempered: CardData = load(TEMPERED_PATH)
	_expect(card.tempered == tempered, "...tempering to Wrest+")
	_expect_eq([tempered.card_name, tempered.rarity, tempered.description], ["Wrest+", CardData.CardRarity.COMMON, card.description], "Wrest+: the same text")
	_expect(tempered.effects.size() == 1 and tempered.effects[0].status_data == status, "...as Wrested too")
	for pool_path: String in [WANDERER_POOL_PATH, COLLECTOR_POOL_PATH]:
		_expect((load(pool_path) as RewardPool).entries.has(card), "In %s" % pool_path)
	_completed += 1

# Both faces: the take from data, GUARD on the footer, 15 px.
func _check_face() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	view.set_card_data(load(CARD_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Take up to 7 from an attack.\nGain that much Block.", "Wrest's face")
	_expect_eq(view.type_label.text, "GUARD", "...its footer GUARD")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	_expect_eq(view.cost_label.text, "2", "...2 Energy")
	view.set_card_data(load(TEMPERED_PATH))
	_expect_eq(view.rules_text.get_parsed_text(), "Take up to 11 from an attack.\nGain that much Block.", "Wrest+'s face")
	_expect_eq(view.type_label.text, "GUARD", "...GUARD too")
	_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "...at 15 px")
	view.free()
	_completed += 1

# --- Rules ---

# Only an attack that will land: not the Underfoot's Rebury, not the
# Sputter's Block, not a Stunned Sting - and once an intent; a Garnish may
# still go on a Wrested one.
func _check_targeting() -> void:
	var card: CardData = load(CARD_PATH)
	var underfoot: EnemyData = load(UNDERFOOT_PATH)
	_expect(not EffectResolver.can_target(card, _enemy(underfoot, "Rebury")), "Wrest can't target the Rebury")
	_expect_eq(EnemyTurn.mark_refusal(_enemy(underfoot, "Rebury"), underfoot, load(STATUS_PATH)), EnemyTurn.MarkRefusal.NOT_ATTACK, "...not an attack")
	_expect(not EffectResolver.can_target(card, _enemy(load(SPUTTER_PATH), "Block")), "...nor the Sputter's Block")
	var stunned: Combatant = _enemy(underfoot, "Sting")
	Status.apply_to(stunned.statuses, load(STUNNED_PATH))
	_expect(not EffectResolver.can_target(card, stunned), "...nor a Stunned Sting")
	var sting: Combatant = _enemy(underfoot, "Sting")
	_expect(EffectResolver.can_target(card, sting), "The Sting it can")
	_wrest(_player(60), sting)
	_expect(not EffectResolver.can_target(card, sting), "A Wrested intent can't be Wrested again")
	_expect(not EffectResolver.can_target(load(TEMPERED_PATH), sting), "...nor by Wrest+")
	_expect_eq(EnemyTurn.mark_refusal(sting, underfoot, load(STATUS_PATH)), EnemyTurn.MarkRefusal.ALREADY, "...already wrested")
	_expect(EffectResolver.can_target(load(GARNISH_PATH), sting), "...but Garnish may still go on it")
	_completed += 1

# The Tail Lash's hits soak the take in order; the Block is the take.
func _check_tail_lash() -> void:
	var data: EnemyData = load(GREYSHELF_PATH)
	var hits: Array[int] = _hits(data, "Tail Lash")
	var enemy: Combatant = _enemy(data, "Tail Lash")
	var player: Combatant = _player(60)
	var taken: int = mini(_take, _sum(hits))
	_wrest(player, enemy)
	_expect_eq(player.block, taken, "Tail Lash %s, Wrested: %d Block" % [str(hits), taken])
	_expect(_wrested(enemy) != null and _wrested(enemy).magnitude == taken, "...Wrested %d on it" % taken)
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(hits, taken), "Tail Lash, Wrested")
	_expect(_wrested(enemy) == null, "...spent by the whole attack")
	_completed += 1

# An attack under the take gives what it has: Wrest+ (11) on the Sputter's
# Scissor takes all of it, and gives that much Block.
func _check_small_attack() -> void:
	var data: EnemyData = load(SPUTTER_PATH)
	var hits: Array[int] = _hits(data, "Scissor")
	var plus: int = (load(TEMPERED_PATH) as CardData).effects[0].value
	var enemy: Combatant = _enemy(data, "Scissor")
	var player: Combatant = _player(60)
	_play_on(load(TEMPERED_PATH), player, enemy)
	var taken: int = mini(plus, _sum(hits))
	_expect(_sum(hits) < plus, "The Scissor (%d) is under Wrest+'s %d" % [_sum(hits), plus])
	_expect_eq(player.block, taken, "Wrest+ on it: %d Block, all it has" % taken)
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(hits, taken), "Scissor, Wrested+")
	# Bereft's two Scissors: the first loses the take - the action it was
	# put on - and the second lands in full, as with Garnish; the Block is
	# given once.
	enemy = _enemy(data, "Scissor")
	Status.apply_to(enemy.statuses, load(BEREFT_PATH))
	player = _player(60)
	_wrest(player, enemy)
	var each: int = mini(_take, _sum(hits))
	_expect_eq(player.block, each, "Bereft's Scissors, Wrested: %d Block, once" % each)
	player.block = 0
	var both: Array[int] = _absorb(hits, each)
	both.append_array(hits)
	_expect_attack(enemy, data, player, both, "Bereft's two Scissors, Wrested: the first cut, the second in full")
	_expect(_wrested(enemy) == null, "...and Wrested spent")
	_completed += 1

# With Brace: Braced's 50% first, then the take - whichever went on first.
# Brace then Wrest takes off the halved attack; Wrest then Brace took off
# the whole one, and keeps the Block it took then.
func _check_brace() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var raw: Array[int] = _hits(data, "Sting")
	var braced: Array[int] = []
	for hit in raw:
		braced.append(_braced(hit))
	var enemy: Combatant = _enemy(data, "Sting")
	var player: Combatant = _player(60)
	_play_on(load(BRACE_PATH), player, enemy)
	_wrest(player, enemy)
	var taken: int = mini(_take, _sum(braced))
	_expect_eq(player.block, taken, "Brace then Wrest on the Sting %d: %d Block, off the halved %d" % [_sum(raw), taken, _sum(braced)])
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(braced, taken), "Braced then Wrested")

	enemy = _enemy(data, "Sting")
	player = _player(60)
	_wrest(player, enemy)
	var first: int = mini(_take, _sum(raw))
	_play_on(load(BRACE_PATH), player, enemy)
	_expect_eq(player.block, first, "Wrest then Brace: %d Block, off the whole %d - kept" % [first, _sum(raw)])
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(braced, first), "Wrested then Braced")
	_completed += 1

# With Garnish: both cut the total, so the attack lands the same either
# way; Wrest's take is read off what Garnish has left when it goes on
# second.
func _check_garnish() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var raw: Array[int] = _hits(data, "Sting")
	var enemy: Combatant = _enemy(data, "Sting")
	var player: Combatant = _player(60)
	_play_on(load(GARNISH_PATH), player, enemy)
	_wrest(player, enemy)
	var after_garnish: int = _sum(_absorb(raw, _garnish_total))
	var taken: int = mini(_take, after_garnish)
	_expect_eq(player.block, taken, "Garnish then Wrest: %d Block, off the %d Garnish leaves" % [taken, after_garnish])
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(raw, _garnish_total + taken), "Garnished then Wrested")

	enemy = _enemy(data, "Sting")
	player = _player(60)
	_wrest(player, enemy)
	var first: int = mini(_take, _sum(raw))
	_play_on(load(GARNISH_PATH), player, enemy)
	_expect_eq(player.block, first, "Wrest then Garnish: %d Block" % first)
	player.block = 0
	_expect_attack(enemy, data, player, _absorb(raw, first + _garnish_total), "Wrested then Garnished")
	_completed += 1

# A strike back (the Adder Coiled, struck by an Attack card) lands in full
# past a Wrested Bite and spends nothing of it; the Bite, after, takes it.
func _check_strike_back() -> void:
	var data: EnemyData = load(ADDER_PATH)
	var enemy: Combatant = _enemy(data, "Bite")
	var player: Combatant = _player(60)
	_wrest(player, enemy)
	var taken: int = player.block
	player.block = 0
	Status.apply_to(enemy.statuses, load(COILED_PATH))
	var counter: int = (load(COILED_PATH) as StatusData).default_magnitude
	var before: int = player.hp
	EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq(before - player.hp, counter, "The Coiled strike back lands in full (%d) past Wrested" % counter)
	_expect(_wrested(enemy) != null and _wrested(enemy).magnitude == taken, "...and Wrested stays for its Bite")
	_completed += 1

# Last Resort forbids Block while Critical: above the line Wrest gives its
# Block as ever; under it none - and still takes off the attack.
func _check_no_block_stance() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var raw: Array[int] = _hits(data, "Sting")
	var taken: int = mini(_take, _sum(raw))
	var player: Combatant = _player(60)
	_play_on(load(LAST_RESORT_PATH), player, null)
	_wrest(player, _enemy(data, "Sting"))
	_expect_eq(player.block, taken, "Under Last Resort above the line: %d Block" % taken)
	var enemy: Combatant = _enemy(data, "Sting")
	player = _player(20)
	_play_on(load(LAST_RESORT_PATH), player, null)
	_wrest(player, enemy)
	_expect_eq(player.block, 0, "Under Last Resort while Critical: no Block")
	_expect(_wrested(enemy) != null and _wrested(enemy).magnitude == taken, "...the Sting still Wrested %d" % taken)
	_expect_attack(enemy, data, player, _absorb(raw, taken), "Sting, Wrested under Last Resort")
	_completed += 1

# Stunned after: the mark won't hold - lost, cancelled - and the Block
# Wrest gave stays.
func _check_lost_mark() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var enemy: Combatant = _enemy(data, "Sting")
	var player: Combatant = _player(60)
	_wrest(player, enemy)
	var block: int = player.block
	Status.apply_to(enemy.statuses, load(STUNNED_PATH))
	_expect_eq(EnemyTurn.mark_loss(_wrested(enemy), enemy, data), "cancelled", "Stunned after: the Wrest won't hold")
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	var marks: Array = result.get("marks", [])
	_expect(marks.size() == 1 and str(marks[0]["outcome"]) == "lost", "...lost")
	_expect(_wrested(enemy) == null, "...and gone")
	_expect_eq(player.block, block, "...the Block it gave stays (%d)" % block)
	_completed += 1

# --- Fight ---

# The real play: 2 Energy, the Block it took, Wrested on the target, the
# intent's number down by it, its hover naming it, and a second Wrest
# refused - "Already wrested."
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		var data: EnemyData = target.get("enemy_data")
		for i in data.intents.size():
			if data.intents[i].type == EnemyIntent.IntentType.ATTACK:
				combatant.current_intent_index = i
				break
		controller.call("_emit_intent_previews")
		var before: Dictionary = controller.call("get_intent_preview", target)
		var raw: Array[int] = _ints(before.get("hit_amounts", []))
		var taken: int = mini(_take, _sum(raw))
		var card: CardData = await _deal(controller)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.type_label.text, "GUARD", "The face in hand: GUARD")
		player.energy = 3
		var block_before: int = player.block
		await _play(controller, card, target)
		_expect_eq(3 - player.energy, 2, "Playing it costs 2 Energy")
		_expect_eq(player.block - block_before, taken, "...gives %d Block" % taken)
		_expect(_wrested(combatant) != null, "...and Wrests the target")
		var after: Dictionary = controller.call("get_intent_preview", target)
		_expect_eq(_ints(after.get("hit_amounts", [])), _absorb(raw, taken), "%s's preview drops by %d" % [data.enemy_name, taken])
		var hover: String = str(_overlay.call("_mark_phrase", _wrested(combatant)))
		_expect(hover.contains("Wrested") and hover.contains(str(taken)), "...its hover names it: %s" % hover)
		var second: CardData = await _deal(controller)
		_expect(not bool(controller.call("_can_target", second, combatant)), "A second Wrest can't target it")
		_expect_eq(str(_overlay.call("_refusal_text", EnemyTurn.MarkRefusal.ALREADY, second, target)), "Already wrested.", "...\"Already wrested.\"")
	await _teardown()
	_completed += 1

# --- Helpers ---

# `hits`, with `total` soaked out of them in order, none below 0.
func _absorb(hits: Array[int], total: int) -> Array[int]:
	var left: int = total
	var landed: Array[int] = []
	for hit in hits:
		var cut: int = mini(left, hit)
		landed.append(hit - cut)
		left -= cut
	return landed

func _sum(values: Array[int]) -> int:
	var total: int = 0
	for value in values:
		total += value
	return total

# One hit under Braced, as Status.apply_modifiers() takes its percentage.
func _braced(amount: int) -> int:
	var magnitude: int = (load(BRACED_PATH) as StatusData).default_magnitude
	return maxi(amount + roundi(amount * magnitude / 100.0), 0)

# An intent's hits from its data: its value, `hits` times.
func _hits(data: EnemyData, intent_name: String) -> Array[int]:
	var intent: EnemyIntent = _queue(data, intent_name)
	var hits: Array[int] = []
	if intent != null:
		for i in maxi(intent.hits, 1):
			hits.append(intent.value)
	return hits

# The preview first, then the turn: both must say `expected`, hit by hit,
# with nothing on the player to block it.
func _expect_attack(enemy: Combatant, data: EnemyData, player: Combatant, expected: Array[int], label: String) -> void:
	player.block = 0
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(_ints(preview.get("hit_amounts", [])), expected, "%s previews %s" % [label, str(expected)])
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	var landed: Array[int] = []
	for hit: Dictionary in result["hits"]:
		landed.append(int(hit["damage"]))
	_expect_eq(landed, expected, "%s lands %s" % [label, str(expected)])

func _ints(values: Array) -> Array[int]:
	var out: Array[int] = []
	for value: Variant in values:
		out.append(int(value))
	return out

func _queue(data: EnemyData, intent_name: String) -> EnemyIntent:
	for intent in data.intents:
		if intent.intent_name == intent_name:
			return intent
	_fail("%s has no %s" % [data.enemy_name, intent_name])
	return null

# A fresh enemy with `intent_name` queued.
func _enemy(data: EnemyData, intent_name: String) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	enemy.current_intent_index = data.intents.find(_queue(data, intent_name))
	EnemyTurn._sync_queued(enemy, data)
	return enemy

func _player(hp: int) -> Combatant:
	var player := Combatant.new(80)
	player.hp = hp
	return player

func _wrest(player: Combatant, enemy: Combatant) -> void:
	_play_on(load(CARD_PATH), player, enemy)

func _play_on(card: CardData, player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy if enemy != null else Combatant.new(100)] as Array[Combatant]
	_resolver.resolve_card(card, ctx)

func _wrested(enemy: Combatant) -> Status:
	return Status.find_in(enemy.statuses, load(STATUS_PATH))

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
	# The fight's opening hold (BattleController.lock_entry_input()).
	var entry_layer: Node = _field.get_node("BattleLayer")
	while entry_layer.get_child_count() > 0 and bool((entry_layer.get_child(0).get("battle_controller") as Node).call("is_entry_locked")):
		await process_frame
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

func _play(controller: Node, card: CardData, target: Node) -> void:
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("'%s' is not in the hand" % card.card_name)
		return
	controller.call("request_play", view)
	if not bool(controller.call("is_awaiting_target")):
		_fail("'%s' didn't ask for a target" % card.card_name)
		return
	controller.call("confirm_target", target)
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
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
