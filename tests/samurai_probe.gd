extends SceneTree

# Headless probe for the Samurai's shell (run/data/samurai.tres): the
# class seam a run started as her goes through, not her content.
#
#   class  - a run started with samurai.tres is hers: no weapon, no Toll,
#            no Grace, shows_critical off, every starter a class-neutral
#            card (cards/neutral/); the Wanderer's own flags stay on
#   toll   - her self-inflicted HP loss accrues no Toll (Combatant.has_
#            toll, copied from the character as BattleController.setup()
#            does); the same loss as the Wanderer still does
#   hud    - the HP bar draws no Critical for her, even at 1 HP
#   pool   - RegionField.run_reward_pool() hands a floor's fights her
#            pool; it rolls by rarity, top tier first and flat, without
#            error, every card from her folder or cards/neutral/; a pool
#            naming only a missing folder rolls nothing, quietly
#   devour - a fight as her offers no Devour (CharacterData.has_devour
#            off): no DevourButton, never available, devour() changes
#            nothing, an unplayable card doesn't arm for it; the Wanderer
#            keeps has_devour
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/samurai_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).

const CASES := 5
const SAMURAI_PATH := "res://run/data/samurai.tres"
const WANDERER_PATH := "res://run/data/wanderer.tres"
const HP_BAR_SCENE_PATH := "res://ui/hp_bar.tscn"
# Loaded at run time, not named: a -s script compiles before the autoloads
# exist, and RegionField names RunState.
const REGION_FIELD_SCRIPT_PATH := "res://field/region_field.gd"
const FLOOR_PATH := "res://floors/region1_floor1.tres"
# A card whose only effect is HP off its player - the self-inflicted loss
# Toll is made of. The Wanderer's, used here as nothing more than that.
const SELF_DAMAGE_CARD_PATH := "res://cards/data/bite_down.tres"
const NEUTRAL_DIR := "res://cards/neutral/"
const SAMURAI_DIR := "res://cards/samurai/"
const MISSING_DIR := "res://cards/no_such_folder/"
const ROLL_COUNT := 3
const SEED_COUNT := 50
const REGION_SCENE_PATH := "res://field/region_field.tscn"
# A Samurai starter, dealt at UNPLAYABLE_COST so it can't be played on
# the fight's 3 Energy.
const UNPLAYABLE_CARD_PATH := "res://cards/neutral/left_hand.tres"
const UNPLAYABLE_COST := 9
const SAFETY_SECONDS := 120.0

var _failures: int = 0
var _completed: int = 0
var _run_state: Node = null
var _field: Node = null

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_run_state.call("new_run", load(SAMURAI_PATH))
	_check_class()
	_check_no_toll()
	_check_no_critical()
	_check_pool()
	await _check_no_devour()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("samurai_probe: PASSED")
		quit(0)
	else:
		print("samurai_probe: %d FAILED" % _failures)
		quit(1)

func _check_class() -> void:
	var samurai := load(SAMURAI_PATH) as CharacterData
	var character := _run_state.get(&"character") as CharacterData
	_expect(character == samurai, "The run is the Samurai's")
	_expect(_run_state.get(&"weapon") == null, "...with no weapon")
	_expect(not samurai.has_toll, "...no Toll")
	_expect(not samurai.has_grace, "...no Grace")
	_expect(not samurai.shows_critical, "...and shows_critical off")
	_expect(samurai.reward_pool != null, "...and a reward pool of her own")
	_expect(load(samurai.field_model_path) is PackedScene, "Her field model loads (%s)" % samurai.field_model_path)
	var deck: Array[CardData] = _run_state.get(&"deck")
	_expect(not deck.is_empty(), "She starts with a deck")
	for card_data: CardData in samurai.starting_deck_counts:
		_expect(card_data.resource_path.begins_with(NEUTRAL_DIR), "Starter %s is class-neutral (%s)" % [card_data.card_name, card_data.resource_path])
	var wanderer := load(WANDERER_PATH) as CharacterData
	_expect(wanderer.has_toll and wanderer.has_grace and wanderer.shows_critical, "The Wanderer keeps Toll, Grace and Critical")
	_expect(not samurai.has_devour, "...no Devour")
	_expect(wanderer.has_devour, "The Wanderer keeps Devour")
	_completed += 1

# The same self-inflicted loss, through the run's Toll, for each class.
func _check_no_toll() -> void:
	var samurai_toll: int = _self_loss_toll(load(SAMURAI_PATH) as CharacterData)
	_expect_eq(samurai_toll, 0, "Her self-damage accrues no Toll")
	var wanderer_toll: int = _self_loss_toll(load(WANDERER_PATH) as CharacterData)
	_expect(wanderer_toll > 0, "The Wanderer's same loss does (%d)" % wanderer_toll)
	_run_state.call("new_run", load(SAMURAI_PATH))
	_completed += 1

func _check_no_critical() -> void:
	var bar: Node = (load(HP_BAR_SCENE_PATH) as PackedScene).instantiate()
	_run_state.call("lose_hp", int(_run_state.get(&"player_hp")) - 1)
	_expect_eq(int(_run_state.get(&"player_hp")), 1, "She stands at 1 HP")
	_expect(not bool(bar.call("_shows_critical")), "Her HP bar draws no Critical line")
	_expect(not bool(bar.call("_is_critical")), "...and doesn't turn Critical at 1 HP")
	bar.free()
	_run_state.call("new_run", load(SAMURAI_PATH))
	_completed += 1

func _check_pool() -> void:
	var samurai := load(SAMURAI_PATH) as CharacterData
	var field: Node = (load(REGION_FIELD_SCRIPT_PATH) as GDScript).new() as Node
	var pool := field.call(&"run_reward_pool", load(FLOOR_PATH) as FloorData) as RewardPool
	field.free()
	_expect(pool == samurai.reward_pool, "A floor's fights roll her pool")
	if pool == null:
		_completed += 1
		return
	var rng := RandomNumberGenerator.new()
	for seed_index in SEED_COUNT:
		rng.seed = seed_index
		for rolled: Array[CardData] in [pool.roll_by_rarity(ROLL_COUNT, rng, null, false, samurai), pool.roll_by_rarity(ROLL_COUNT, rng, null, true, samurai), pool.roll_top_tier(ROLL_COUNT, rng, null, samurai), pool.roll(ROLL_COUNT, rng, null, samurai)]:
			_expect_eq(rolled.size(), ROLL_COUNT, "Seed %d: her pool rolls %d cards" % [seed_index, ROLL_COUNT])
			for card in rolled:
				_expect(card.resource_path.begins_with(SAMURAI_DIR) or card.resource_path.begins_with(NEUTRAL_DIR), "Seed %d: %s is hers or neutral (%s)" % [seed_index, card.card_name, card.resource_path])
				_expect_eq(rolled.count(card), 1, "Seed %d: %s once per roll" % [seed_index, card.card_name])
	var empty := RewardPool.new()
	empty.source_folders = PackedStringArray([MISSING_DIR])
	rng.seed = 0
	_expect(empty.roll_by_rarity(ROLL_COUNT, rng).is_empty(), "A pool naming only a missing folder rolls nothing")
	_expect(empty.roll(ROLL_COUNT, rng).is_empty(), "...flat as well")
	_completed += 1

# A fight as her, through RegionField's contact handler as devour_probe
# fights: no Devour anywhere in it.
func _check_no_devour() -> void:
	_run_state.call("new_run", load(SAMURAI_PATH))
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
		await _teardown()
		return
	var body: Node3D = _field.get_node("Wanderer") as Node3D
	body.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("no fight started")
		await _teardown()
		return
	var overlay: Node = layer.get_child(0)
	var controller: Node = overlay.get("battle_controller")
	# The fight's opening hold (BattleController.lock_entry_input()).
	while bool(controller.call("is_entry_locked")):
		await process_frame
	await process_frame

	_expect(not bool(controller.get("has_devour")), "Her fight has no Devour")
	_expect(overlay.get_node_or_null("DevourButton") == null, "...and no Devour button")
	var player: Combatant = controller.get("player")
	player.energy = 3
	controller.emit_signal("energy_changed", 3)
	player.hp = maxi(player.max_hp - 20, 1)
	_expect(not bool(controller.call("is_devour_available")), "...never available, with Energy and a card in hand")

	var devoured: Array[CardData] = []
	controller.connect("card_devoured", func(card: CardData) -> void: devoured.append(card))
	var deck: Object = controller.get("deck")
	var hp_before: int = player.hp
	var energy_before: int = player.energy
	var hand_before: int = (deck.get("hand") as Array).size()
	controller.call("devour")
	for i in 5:
		await process_frame
	_expect(not bool(controller.call("is_devour_picking")), "devour() opens no pick")
	controller.call("devour")
	for i in 5:
		await process_frame
	_expect(devoured.is_empty(), "...and eats nothing")
	_expect_eq(player.hp, hp_before, "...heals nothing")
	_expect_eq(player.energy, energy_before, "...spends no Energy")
	_expect_eq((deck.get("hand") as Array).size(), hand_before, "...and the hand keeps its cards")

	# A card she can't play arms for nothing.
	var card: CardData = (load(UNPLAYABLE_CARD_PATH) as CardData).duplicate()
	card.cost = UNPLAYABLE_COST
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	var view: CardView = null
	for candidate: CardView in controller.get("_hand_container").call("_card_views"):
		if candidate.card_data == card:
			view = candidate
	_expect(view != null, "The unplayable card is in her hand")
	if view != null:
		controller.call("request_play", view)
		await process_frame
		_expect(not bool(controller.call("is_awaiting_target")), "An unplayable card doesn't arm for Devour")
		_expect(not bool(controller.call("is_armed_for_devour_only")), "...not even for Devour alone")
	_expect(devoured.is_empty(), "Nothing was devoured in her fight")
	await _teardown()
	_completed += 1

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# --- Helpers ---

# A fresh run as `character`, its player built the way BattleController.
# setup() builds it, and the self-damage card resolved: the run's Toll
# after.
func _self_loss_toll(character: CharacterData) -> int:
	_run_state.call("new_run", character)
	var player := Combatant.new(int(_run_state.get(&"player_hp")))
	player.run_toll_owner = _run_state
	player.has_toll = character.has_toll
	var enemy := Combatant.new(50)
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = enemy
	ctx.enemies = [enemy] as Array[Combatant]
	EffectResolver.new().resolve_card(load(SELF_DAMAGE_CARD_PATH) as CardData, ctx)
	_expect(player.hp < int(_run_state.get(&"player_hp")), "%s's self-damage costs HP" % character.character_name)
	return int(_run_state.get(&"toll"))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
