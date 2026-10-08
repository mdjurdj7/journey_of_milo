extends SceneTree

# Headless probe for Garnish - 1 Energy, Uncommon Skill, one enemy: lose
# 1 HP up front (the face's HP badge, Down Payment's SELF_DAMAGE_TOLL) and
# gain 5 Toll in total, and the target is Garnished 5 - its next ATTACK
# deals 5 less in all, the hits soaking it in order, each down to 0 at
# most, after Braced's 50% and before block (EnemyTurn.reduce_hit()).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/garnish_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Rules cases play the real card through EffectResolver against the real
# enemies' data - the Sputter's Scissor, the Underfoot's Sting and Rebury,
# the Greyshelf's Tail Lash - and work each expected hit out of that data
# (the intent's value, Braced's percentage where it applies, less the
# Garnish total), never a written-in number, so a retuned enemy keeps the
# probe true. Every case checks that what preview_intent() shows is what
# take_turn() lands. The fight case loads the real region scene and plays
# the card through BattleController.request_play()/confirm_target(), as
# deny_probe does: the face, the HP and Toll (and the run log's source),
# its own sound, and the intent display's number. Untyped against
# anything that names the RunState autoload.

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_PATH := "res://cards/data/garnish.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const STATUS_PATH := "res://battle/rules/statuses/garnished.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const OFF_THE_ROCK_PATH := "res://battle/rules/statuses/off_the_rock.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const UNDERFOOT_PATH := "res://battle/rules/enemies/underfoot.tres"
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const WANDERER_POOL_PATH := "res://cards/pools/wanderer_pool.tres"
const COLLECTOR_POOL_PATH := "res://cards/pools/collector_pool.tres"
const ART_PATH := "res://cards/art/Wanderer/Garnish.png"
const SOUND_PATH := "res://assets/audio/cards/Garnish/Garnish.mp3"
const HP_LOSS := 1
const TOLL_TOTAL := 5
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _overlay: Node = null
var _failures: int = 0
var _completed: int = 0
var _resolver := EffectResolver.new()
var _garnish_total: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_garnish_total = (load(STATUS_PATH) as StatusData).default_magnitude

	_check_data()
	_check_scissor()
	_check_sting_braced()
	_check_tail_lash()
	_check_waits()
	_check_stacking()
	_check_hp_and_toll()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("garnish_probe: PASSED")
		quit(0)
	else:
		print("garnish_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var card: CardData = load(CARD_PATH)
	_expect_eq(card.card_name, "Garnish", "The card loads")
	_expect_eq(card.cost, 1, "...costs 1 Energy")
	_expect_eq(card.card_type, CardData.CardType.SKILL, "...is a Skill")
	_expect_eq(card.rarity, CardData.CardRarity.UNCOMMON, "...Uncommon")
	_expect_eq(card.target_type, CardData.TargetType.ENEMY, "...targets one enemy")
	_expect_eq(card.description, "Target enemy's next Attack deals 5 less.\nGain 5 Toll.", "...its text")
	_expect_eq(CardView._derive_keyline_type(card), CardView.KeylineType.TOLL, "...and reads TOLL")
	_expect_eq(card.effects.size(), 2, "...two effects")
	if card.effects.size() == 2:
		var cost: CardEffect = card.effects[0]
		_expect_eq([cost.effect_type, cost.value, cost.toll_gain], [CardEffect.EffectType.SELF_DAMAGE_TOLL, HP_LOSS, TOLL_TOTAL], "...first 1 HP for 5 Toll in total (Down Payment's shape)")
		var garnish: CardEffect = card.effects[1]
		_expect_eq(garnish.effect_type, CardEffect.EffectType.APPLY_STATUS_TO_TARGET, "...then a status on the target")
		_expect(garnish.status_data != null and garnish.status_data.resource_path == STATUS_PATH, "...Garnished")
	var status: StatusData = load(STATUS_PATH)
	_expect_eq(status.display_name, "Garnished", "Garnished: one word")
	_expect_eq(status.default_magnitude, 5, "...worth 5")
	_expect(status.reduces_attack_total and status.consumed_by_own_attack, "...a total off the next Attack, spent when it resolves")
	_expect_eq(status.category, StatusData.Category.INFORMATIONAL, "...not a per-hit modifier")
	_expect_eq(status.stack_rule, StatusData.StackRule.ADD_MAGNITUDE, "...copies adding up")
	_expect_eq(status.default_duration_turns, StatusData.DURATION_UNTIL_TRIGGERED, "...no turn counter")
	_expect_eq(Status.new(status).describe(), "Its next Attack deals 5 less.", "...its hover text")
	_expect(card.art != null and card.art.resource_path == ART_PATH, "The card has its art")
	_expect(card.art != null and card.art.get_image().has_mipmaps(), "...mipmapped")
	_expect_eq(card.play_sound_path, SOUND_PATH, "...and its play sound")
	_expect(load(card.play_sound_path) is AudioStream, "...which loads")
	_expect((load(WANDERER_POOL_PATH) as RewardPool).entries.has(card), "...in the Wanderer pool")
	_expect((load(COLLECTOR_POOL_PATH) as RewardPool).entries.has(card), "...and the collector pool")
	_completed += 1

# --- Rules ---

# The Sputter's Scissor, Garnished: one hit, 5 less.
func _check_scissor() -> void:
	var data: EnemyData = load(SPUTTER_PATH)
	var intent: EnemyIntent = _queue(data, "Scissor")
	var enemy: Combatant = _enemy(data, "Scissor")
	var player: Combatant = _player(60)
	_garnish(player, enemy)
	_expect_attack(enemy, data, player, _absorb([intent.value], _garnish_total), "Scissor %d, Garnished" % intent.value)
	_expect(_garnished(enemy) == null, "...and Garnished is spent")
	_completed += 1

# The Underfoot's Sting under Brace and Garnish: Braced's 50% first, then
# the 5 - so a 10 lands 0, not 2.5.
func _check_sting_braced() -> void:
	var data: EnemyData = load(UNDERFOOT_PATH)
	var intent: EnemyIntent = _queue(data, "Sting")
	var enemy: Combatant = _enemy(data, "Sting")
	var player: Combatant = _player(60)
	_brace(player, enemy)
	_garnish(player, enemy)
	var braced: int = _braced(intent.value)
	_expect_attack(enemy, data, player, _absorb([braced], _garnish_total), "Sting %d, Braced to %d, Garnished" % [intent.value, braced])
	_expect(_garnished(enemy) == null, "...Garnished spent")
	_expect(Status.find_in(enemy.statuses, load(BRACED_PATH)) == null, "...Braced too")
	# The order holds whichever went on first.
	enemy = _enemy(data, "Sting")
	_garnish(player, enemy)
	_brace(player, enemy)
	_expect_attack(enemy, data, player, _absorb([braced], _garnish_total), "Garnished before Braced lands the same")
	_completed += 1

# Tail Lash soaks the 5 hit by hit: the first gives all it has, the next
# the rest - and off the rock, its fourth hit lands in full.
func _check_tail_lash() -> void:
	var data: EnemyData = load(GREYSHELF_PATH)
	var intent: EnemyIntent = _queue(data, "Tail Lash")
	var hits: Array[int] = []
	for i in intent.hits:
		hits.append(intent.value)
	var enemy: Combatant = _enemy(data, "Tail Lash")
	var player: Combatant = _player(60)
	_garnish(player, enemy)
	_expect_attack(enemy, data, player, _absorb(hits, _garnish_total), "Tail Lash %d×%d, Garnished" % [intent.value, intent.hits])
	_expect(_garnished(enemy) == null, "...spent by the whole attack")

	var off_the_rock: StatusData = load(OFF_THE_ROCK_PATH)
	var more: Array[int] = hits.duplicate()
	for i in off_the_rock.bonus_hits:
		more.append(intent.value)
	enemy = _enemy(data, "Tail Lash")
	Status.apply_to(enemy.statuses, off_the_rock)
	_garnish(player, enemy)
	_expect_attack(enemy, data, player, _absorb(more, _garnish_total), "Off the rock, Tail Lash ×%d, Garnished" % more.size())
	_completed += 1

# Only an Attack that resolves spends it: Rebury, the Sputter's Block, a
# Denied Sting leave it standing - and the next Attack takes it.
func _check_waits() -> void:
	var underfoot: EnemyData = load(UNDERFOOT_PATH)
	var sting: EnemyIntent = _queue(underfoot, "Sting")
	var enemy: Combatant = _enemy(underfoot, "Rebury")
	var player: Combatant = _player(60)
	_garnish(player, enemy)
	var hp_before: int = player.hp
	EnemyTurn.take_turn(enemy, underfoot, player)
	_expect_eq(player.hp, hp_before, "Rebury deals nothing")
	var waiting: Status = _garnished(enemy)
	_expect(waiting != null and waiting.magnitude == _garnish_total, "...and leaves Garnished %d standing" % _garnish_total)
	_expect_eq(EnemyTurn.current_intent(enemy, underfoot), sting, "The Sting comes next")
	_expect_attack(enemy, underfoot, player, _absorb([sting.value], _garnish_total), "...and takes it")
	_expect(_garnished(enemy) == null, "...spending it")

	var sputter: EnemyData = load(SPUTTER_PATH)
	enemy = _enemy(sputter, "Block")
	_garnish(player, enemy)
	EnemyTurn.take_turn(enemy, sputter, player)
	_expect(_garnished(enemy) != null, "The Sputter's Block leaves it standing")

	enemy = _enemy(underfoot, "Sting")
	_garnish(player, enemy)
	Status.apply_to(enemy.statuses, load(DENIED_PATH))
	hp_before = player.hp
	EnemyTurn.take_turn(enemy, underfoot, player)
	_expect_eq(player.hp, hp_before, "A Denied Sting lands nothing")
	_expect(_garnished(enemy) != null, "...and leaves it standing")
	_completed += 1

# Two Garnishes add up: 10 off the next Attack, one status.
func _check_stacking() -> void:
	var data: EnemyData = load(SPUTTER_PATH)
	var intent: EnemyIntent = _queue(data, "Scissor")
	var enemy: Combatant = _enemy(data, "Scissor")
	var player: Combatant = _player(60)
	_garnish(player, enemy)
	_garnish(player, enemy)
	var count: int = 0
	for active: Status in enemy.statuses:
		if active.data.reduces_attack_total:
			count += 1
	_expect_eq(count, 1, "Two Garnishes: one status")
	var garnished: Status = _garnished(enemy)
	_expect(garnished != null and garnished.magnitude == _garnish_total * 2, "...worth %d" % (_garnish_total * 2))
	if garnished != null:
		_expect_eq(garnished.describe(), "Its next Attack deals %d less." % (_garnish_total * 2), "...its hover says so")
	_expect_attack(enemy, data, player, _absorb([intent.value], _garnish_total * 2), "Scissor %d, Garnished twice" % intent.value)

	var greyshelf: EnemyData = load(GREYSHELF_PATH)
	var lash: EnemyIntent = _queue(greyshelf, "Tail Lash")
	var hits: Array[int] = []
	for i in lash.hits:
		hits.append(lash.value)
	enemy = _enemy(greyshelf, "Tail Lash")
	_garnish(player, enemy)
	_garnish(player, enemy)
	_expect_attack(enemy, greyshelf, player, _absorb(hits, _garnish_total * 2), "Tail Lash, Garnished twice")
	_completed += 1

# The price: 1 HP, and 5 Toll in total - the HP's own 1 topped up by 4.
func _check_hp_and_toll() -> void:
	var data: EnemyData = load(SPUTTER_PATH)
	var enemy: Combatant = _enemy(data, "Scissor")
	var player: Combatant = _player(50)
	player.toll = 0
	_garnish(player, enemy)
	_expect_eq(player.hp, 50 - HP_LOSS, "Garnish costs 1 HP")
	_expect_eq(player.toll, TOLL_TOTAL, "...and leaves 5 Toll")
	_completed += 1

# --- Fight ---

# The real play: the face (1 Energy, −1 HP, TOLL, the text fitting at
# hand size), 1 Energy, 1 HP and 5 Toll - put down to card:Garnish in the
# run log - its own sound, Garnished on the target, and the intent
# display's number the rules' own.
func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var target: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var combatant: Combatant = (controller.get("_combatants") as Dictionary)[target]
		var data: EnemyData = target.get("enemy_data")
		# An Attack queued, whatever the floor's enemy opened with.
		for i in data.intents.size():
			if data.intents[i].type == EnemyIntent.IntentType.ATTACK:
				combatant.current_intent_index = i
				break
		controller.call("_emit_intent_previews")
		var before: Dictionary = controller.call("get_intent_preview", target)
		var expected: Array[int] = _absorb(_ints(before.get("hit_amounts", [])), _garnish_total)
		var card: CardData = await _deal(controller)
		var view: CardView = _view(controller, card)
		if view != null:
			_expect_eq(view.cost_label.text, "1", "The face: 1 Energy")
			_expect_eq(view.hp_cost_label.text if view.hp_cost_label.visible else "", "−1 HP", "...−1 HP in the cost badge")
			_expect_eq(view.type_label.text, "TOLL", "...labelled TOLL")
			_expect_eq(view.rules_text.get_parsed_text(), card.description, "...its text as written")
			_expect(view.rules_font_sizes.has(view.rules_text.get_theme_font_size("normal_font_size")), "...at a rules size")
			_expect_eq(view.size, view.card_size, "...fitting the face at hand size")
			var type_baseline: float = view.type_label.position.y + view.type_label.get_theme_font("font").get_ascent(view.type_label_font_size_px)
			_expect(view.rules_text.position.y + view.rules_text.size.y <= type_baseline, "...its text ending above the type label")
		var energy_before: int = player.energy
		var hp_before: int = player.hp
		var toll_before: int = player.toll
		var logged_before: int = int(RunLogger._toll_gained_by.get("card:Garnish", 0))
		await _play(controller, card, target)
		_expect_eq(energy_before - player.energy, 1, "Playing it costs 1 Energy")
		_expect_eq(hp_before - player.hp, HP_LOSS, "...loses 1 HP")
		_expect_eq(player.toll - toll_before, TOLL_TOTAL, "...gains 5 Toll (%d -> %d)" % [toll_before, player.toll])
		_expect_eq(int(RunLogger._toll_gained_by.get("card:Garnish", 0)) - logged_before, TOLL_TOTAL, "...logged as Toll from card:Garnish")
		var sound: AudioStreamPlayer = _overlay.get("_card_override_player")
		_expect(sound != null and sound.stream != null and sound.stream.resource_path == SOUND_PATH, "...playing its own sound")
		_expect(sound != null and sound.bus == &"SFX" and is_equal_approx(sound.volume_db, float(_overlay.get("card_override_volume_db"))), "...on the SFX bus at the card-play override level")
		_expect(_garnished(combatant) != null, "...and Garnishes the target")
		var after: Dictionary = controller.call("get_intent_preview", target)
		_expect_eq(_ints(after.get("hit_amounts", [])), expected, "%s's preview drops by the Garnish" % data.enemy_name)
		var intent_view: Node = (_overlay.get("_enemy_intents") as Dictionary).get(target)
		if intent_view != null:
			var label: Label = intent_view.get("_label") as Label
			_expect_eq(label.text, _intent_text(expected), "...and so does the number over it")
		else:
			_fail("no intent display over the target")
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

# One hit under Braced, as Status.apply_modifiers() takes its percentage.
func _braced(amount: int) -> int:
	var magnitude: int = (load(BRACED_PATH) as StatusData).default_magnitude
	return maxi(amount + roundi(amount * magnitude / 100.0), 0)

# The preview first, then the turn: both must say `expected`, hit by hit,
# with nothing on the player to block it.
func _expect_attack(enemy: Combatant, data: EnemyData, player: Combatant, expected: Array[int], label: String) -> void:
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(_ints(preview.get("hit_amounts", [])), expected, "%s previews %s" % [label, str(expected)])
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	var landed: Array[int] = []
	for hit: Dictionary in result["hits"]:
		landed.append(int(hit["damage"]))
	_expect_eq(landed, expected, "%s lands %s" % [label, str(expected)])
	_expect_eq(int(result["damage_to_hp"]), int(preview["damage_to_hp"]), "%s lands what it previewed" % label)

# The intent display's text for these hits (BattleIntent.show_intent()).
func _intent_text(hits: Array[int]) -> String:
	if hits.size() <= 1:
		return str(hits[0]) if hits.size() == 1 else ""
	if hits.count(hits[0]) == hits.size():
		return "%d×%d" % [hits[0], hits.size()]
	var parts := PackedStringArray()
	for hit in hits:
		parts.append(str(hit))
	return " + ".join(parts)

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
	EnemyTurn.pick_initial_intent(enemy, data)
	enemy.current_intent_index = data.intents.find(_queue(data, intent_name))
	EnemyTurn._sync_queued(enemy, data)
	return enemy

func _player(hp: int) -> Combatant:
	var player := Combatant.new(80)
	player.hp = hp
	return player

func _garnish(player: Combatant, enemy: Combatant) -> void:
	_play_on(load(CARD_PATH), player, enemy)

func _brace(player: Combatant, enemy: Combatant) -> void:
	_play_on(load(BRACE_PATH), player, enemy)

func _play_on(card: CardData, player: Combatant, enemy: Combatant) -> void:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy] as Array[Combatant]
	_resolver.resolve_card(card, ctx)

func _garnished(enemy: Combatant) -> Status:
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
