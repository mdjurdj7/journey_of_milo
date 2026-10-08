extends SceneTree

# Headless probe for floor 3's required pair, the Blackback and the
# Nipper: their loops, the Blackback's Fed from the first frame turning
# Hungry once when the Nipper dies (a Carve's kill included), Hungry's +3
# on every hit of its Attacks (Peck 2x7, Lunge 15), the Nipper's Forage
# healing the Blackback 8 up to its max and giving way to Nip once the
# Blackback is dead, and every turn's intent preview equal to what the
# turn resolves. Floor 3 keeps the Blackback first, where the Sputter
# stood, so the LINE exit measures from the same place. Its sounds: two
# contact takes, the bill clatter with each windup, and the hiss once as
# it turns Hungry - never at a fight's opening.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/blackback_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fights load the real floor 3 scene and drive BattleController's own
# end_turn() and request_play(), as keeper_keepsake_probe does. Untyped
# against anything that names the RunState autoload (RegionField,
# BattleController, FieldEnemy): a SceneTree script compiles before the
# autoloads register.

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const BLACKBACK_PATH := "res://battle/rules/enemies/blackback.tres"
const NIPPER_PATH := "res://battle/rules/enemies/nipper.tres"
const FED_PATH := "res://battle/rules/statuses/fed.tres"
const HUNGRY_PATH := "res://battle/rules/statuses/hungry.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const STORK_AUDIO := "res://assets/audio/enemies/Stork/"
const FLOOR_3 := 2
const PLAYER_HP := 999
const TURNS := 8
const SAFETY_SECONDS := 420.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_check_data()
	_check_hungry_per_attack()
	_check_floor_3()
	await _check_fight_opens()
	await _check_both_alive_turns()
	await _check_nipper_dies_first()
	await _check_blackback_dies_first()
	await _check_carve_kills_nipper()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("blackback_probe: PASSED")
		quit(0)
	else:
		print("blackback_probe: %d FAILED" % _failures)
		quit(1)

# The two as authored: HP, loops in order, Fed as the Blackback's only
# passive, both reveal lines filled.
func _check_data() -> void:
	var blackback := load(BLACKBACK_PATH) as EnemyData
	var nipper := load(NIPPER_PATH) as EnemyData
	_expect_eq(blackback.max_hp, 40, "Blackback: 40 HP")
	_expect_eq(nipper.max_hp, 16, "Nipper: 16 HP")
	_expect(not blackback.erratic_intent_selection and not nipper.erratic_intent_selection, "Both loop in order")
	var b := _enemy(blackback)
	var seen: Array[String] = []
	for turn in 5:
		seen.append(_intent_name(EnemyTurn.current_intent(b, blackback)))
		EnemyTurn._advance_intent(b, blackback)
	_expect_eq(seen, ["4x2", "12", "4x2", "12", "4x2"] as Array[String], "Blackback: Peck 4x2, Lunge 12, repeating")
	var n := _enemy(nipper)
	seen.clear()
	for turn in 7:
		seen.append(_intent_name(EnemyTurn.current_intent(n, nipper)))
		EnemyTurn._advance_intent(n, nipper)
	_expect_eq(seen, ["3", "3", "heal 8", "3", "3", "heal 8", "3"] as Array[String], "Nipper: Nip 3, Nip 3, Forage 8, repeating")
	_expect_eq(blackback.starting_statuses.size(), 1, "Blackback holds one passive")
	_expect(blackback.starting_statuses[0] == load(FED_PATH), "...Fed")
	_expect(nipper.starting_statuses.is_empty(), "Nipper holds none")
	_expect_eq(blackback.model_scene_path, "res://assets/models/enemies/Stork/Stork.glb", "Blackback is the marabou")
	_expect_eq(blackback.model_scale, 92.9, "...at 92.9 - 1.3 m standing")
	_expect_eq(blackback.attachment_scene_path, "res://field/stork_tells.tscn", "...with its tells (sac, clatter)")
	var takes: Array[String] = []
	for take in blackback.contact_sounds:
		takes.append(take.resource_path if take != null else "<none>")
	_expect_eq(takes, [STORK_AUDIO + "hit_1.mp3", STORK_AUDIO + "hit_2.mp3"] as Array[String], "...its contact takes hit_1 and hit_2")
	_expect(blackback.status_gained_sound != null and blackback.status_gained_sound.resource_path == STORK_AUDIO + "hiss_1.mp3", "...the hiss as its status sound")
	_expect(blackback.status_gained_sound_on == load(HUNGRY_PATH), "...played on Hungry")
	_expect_eq(nipper.model_scale, 0.625, "Nipper still wears the Sputter, at 0.625")
	var fed := Status.new(load(FED_PATH) as StatusData)
	_expect_eq(fed.describe(), "When the other dies, it turns Hungry: each hit of its Attacks deals 3 more.", "Fed's reveal line")
	var hungry := Status.new(load(HUNGRY_PATH) as StatusData)
	_expect_eq(hungry.describe(), "Each hit of its Attacks deals 3 more.", "Hungry's reveal line")
	_completed += 1

# Rules only: Hungry's +3 lands on every hit of its Attacks - Peck 2x7,
# Lunge 15 - previewed and resolved alike, and block is worn down hit by
# hit; Fed adds nothing (Peck 2x4, Lunge 12).
func _check_hungry_per_attack() -> void:
	var data := load(BLACKBACK_PATH) as EnemyData
	var fed_peck := _peck_against(data, FED_PATH)
	_expect_eq(fed_peck, [8, 8, [4, 4]], "Fed: Peck 2x4 = 8, previewed and resolved")
	var hungry_peck := _peck_against(data, HUNGRY_PATH)
	_expect_eq(hungry_peck, [14, 14, [7, 7]], "Hungry: Peck 2x7 = 14, previewed and resolved")
	# Against 10 block: the first 7 is all blocked, the second meets the 3
	# left and 4 gets through - previewed and resolved alike.
	var hungry_b := _enemy(data)
	Status.apply_to(hungry_b.statuses, load(HUNGRY_PATH) as StatusData)
	var guarded := Combatant.new(PLAYER_HP)
	guarded.block = 10
	var guarded_preview: Dictionary = EnemyTurn.preview_intent(hungry_b, data, guarded)
	var guarded_result: Dictionary = EnemyTurn.take_turn(hungry_b, data, guarded)
	_expect_eq(int(guarded_preview["damage_to_hp"]), 4, "Hungry Peck into 10 block: 7 blocked, then 3 of 7 - 4 through, previewed")
	_expect_eq(int(guarded_result["damage_to_hp"]), 4, "...and landed")
	_expect_eq(guarded.block, 0, "...the block worn to 0")
	_expect_eq(_lunge_against(data, FED_PATH), [12, 12], "Fed: Lunge 12, previewed and resolved")
	_expect_eq(_lunge_against(data, HUNGRY_PATH), [15, 15], "Hungry: Lunge 12 + 3 = 15, previewed and resolved")
	_completed += 1

# Floor 3: the Blackback first at (-3, -9), where the Sputter stood (the
# gate measures from the first enemy); the Wardling as it was; the Nipper
# 1.5-2 m from the Blackback in its cluster; both required.
func _check_floor_3() -> void:
	var floor_data := load(FLOOR_3_PATH) as Resource
	var enemies: Array = floor_data.get("enemies")
	_expect_eq(enemies.size(), 3, "Floor 3 has three enemies")
	var blackback: Resource = enemies[0]
	var nipper: Resource = enemies[2]
	_expect_eq((blackback.get("enemy_data") as EnemyData).enemy_name, "Blackback", "...the Blackback first")
	_expect_eq(blackback.get("position"), Vector2(-3, -9), "...at (-3, -9)")
	_expect_eq((enemies[1].get("enemy_data") as EnemyData).enemy_name, "Wardling", "...the Wardling second")
	_expect_eq((nipper.get("enemy_data") as EnemyData).enemy_name, "Nipper", "...the Nipper third")
	var gap: float = (nipper.get("position") as Vector2).distance_to(blackback.get("position") as Vector2)
	_expect(gap >= 1.5 and gap <= 2.0, "...%.2f m from the Blackback" % gap)
	_expect(blackback.get("group") != &"" and blackback.get("group") == nipper.get("group"), "...one cluster")
	_expect(bool(blackback.get("required")) and bool(nipper.get("required")), "...both required")
	_completed += 1

# One contact starts the fight with both; the Blackback opens Fed, its
# row reads it and its reveal says what it turns into.
func _check_fight_opens() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var members: Array = controller.get("enemies")
		_expect_eq(members.size(), 2, "One contact: the fight has both")
		var blackback: Node = _member(controller, "Blackback")
		var nipper: Node = _member(controller, "Nipper")
		_expect(blackback != null and nipper != null, "...the Blackback and the Nipper")
		if blackback != null:
			var labels: PackedStringArray = controller.call("get_enemy_status_labels", blackback)
			_expect_eq(labels, PackedStringArray(["Fed"]), "Turn 1: the Blackback's row reads Fed")
			_expect_eq(_intent_text(controller, blackback), "4×2", "...and its Peck reads 4×2")
			var bar: Node = blackback.get("enemy_status")
			_expect(bar != null and _shows(bar, "Fed"), "...its readout shows it")
			var tells: Node = blackback.get("_attachment")
			_expect(tells is StorkTells, "The marabou wears its tells")
			if tells is StorkTells:
				_expect(is_equal_approx(_sac_grey(tells), (tells as StorkTells).fed_desaturation), "...its sac grey while it's Fed (%.2f)" % _sac_grey(tells))
				var windup: float = (tells as StorkTells).play_windup(0.1)
				_expect(windup > 0.0 and is_equal_approx(windup, (tells as StorkTells).clatter_seconds), "...and each attack waits on its bill clatter (%.2f s)" % windup)
				var clatter: AudioStreamPlayer3D = tells.get("_clatter_player")
				_expect(clatter != null and clatter.playing and clatter.stream != null and clatter.stream.resource_path == STORK_AUDIO + "clatter_1.mp3", "...which sounds: clatter_1")
				_expect(clatter != null and clatter.bus == &"SFX", "...the clatter on the SFX bus")
			_expect(blackback.get("_status_player") == null, "...and no hiss as the fight opens Fed")
		if nipper != null:
			_expect_eq(_combatant(controller, nipper).statuses.size(), 0, "The Nipper holds nothing")
	await _teardown()
	_completed += 1

# Both alive, eight turns: every turn the previews are what lands - the
# player's loss is their damage summed, the Blackback's gain is the
# Forage's number - and the Forage heals 8, then only up to the max.
func _check_both_alive_turns() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var blackback: Node = _member(controller, "Blackback")
		var nipper: Node = _member(controller, "Nipper")
		var b: Combatant = _combatant(controller, blackback)
		var n: Combatant = _combatant(controller, nipper)
		b.hp = 20
		var heals: Array[int] = []
		for turn in TURNS:
			# The second Forage meets a Blackback 6 short of its max.
			if turn == 5:
				b.hp = 34
			var forage: bool = EnemyTurn.current_intent(n, nipper.get("enemy_data")).type == EnemyIntent.IntentType.HEAL_ALLY
			var outcome: Array = await _turn(controller, turn)
			if forage:
				heals.append(outcome[1])
		_expect_eq(heals, [8, 6] as Array[int], "Forage heals the Blackback 8, then 6 to its max of 40")
		_expect_eq(b.hp, 40, "...the Blackback at 40")
	await _teardown()
	_completed += 1

# The Nipper killed first: Fed becomes Hungry at once, once - the next
# Peck previews and lands 2x7, the Lunge 15, and nothing turns twice.
func _check_nipper_dies_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var blackback: Node = _member(controller, "Blackback")
		var b: Combatant = _combatant(controller, blackback)
		var gained: Array = []
		controller.connect("enemy_status_gained", func(member: Node, status: StatusData) -> void: gained.append([member, status]))
		_kill(controller, _member(controller, "Nipper"))
		_expect_eq(controller.call("get_enemy_status_labels", blackback), PackedStringArray(["Hungry"]), "Nipper dead: Fed is Hungry")
		_expect(gained.size() == 1 and gained[0][0] == blackback and gained[0][1] == load(HUNGRY_PATH), "...told once, to its body: it gained Hungry (%d told)" % gained.size())
		var hiss: AudioStreamPlayer3D = blackback.get("_status_player")
		_expect(hiss != null and hiss.playing and hiss.stream != null and hiss.stream.resource_path == STORK_AUDIO + "hiss_1.mp3", "...and it hisses (hiss_1)")
		_expect(hiss != null and hiss.bus == &"SFX", "...on the SFX bus")
		var tells: Node = blackback.get("_attachment")
		if tells is StorkTells:
			await create_timer((tells as StorkTells).fade_seconds + 0.2).timeout
			_expect(is_equal_approx(_sac_grey(tells), 0.0), "...and its sac's red is back (%.2f)" % _sac_grey(tells))
		var bar: Node = blackback.get("enemy_status")
		_expect(bar != null and _shows(bar, "Hungry"), "...its readout shows it")
		var preview: Dictionary = controller.call("get_intent_preview", blackback)
		_expect_eq(preview.get("hit_amounts"), [7, 7], "...the Peck is 7 and 7")
		_expect_eq(_intent_text(controller, blackback), "7×2", "...and reads 7×2 - per hit, never \"a + b\"")
		_expect_eq(int(preview["damage_to_hp"]), 14, "...14 in all")
		var landed: Array[int] = []
		for turn in TURNS:
			var outcome: Array = await _turn(controller, turn)
			landed.append(outcome[0])
			controller.call("_mark_lone_pack_members")
		_expect_eq(landed, [14, 15, 14, 15, 14, 15, 14, 15] as Array[int], "Hungry: Peck 2x7 = 14, Lunge 15, every turn")
		_expect_eq(b.statuses.size(), 1, "...one status, Hungry alone")
		_expect_eq(b.statuses[0].stack_count, 1, "...turned once")
	await _teardown()
	_completed += 1

# The Blackback killed first, with the Nipper's Forage queued: it turns
# Nip at once, in the preview, and the Nipper never forages again.
func _check_blackback_dies_first() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var nipper: Node = _member(controller, "Nipper")
		var n: Combatant = _combatant(controller, nipper)
		var data: EnemyData = nipper.get("enemy_data")
		n.current_intent_index = 2
		_expect_eq(int((controller.call("get_intent_preview", nipper) as Dictionary)["type"]), EnemyIntent.IntentType.HEAL_ALLY, "Forage queued")
		_kill(controller, _member(controller, "Blackback"))
		var preview: Dictionary = controller.call("get_intent_preview", nipper)
		_expect_eq(int(preview["type"]), EnemyIntent.IntentType.ATTACK, "Blackback dead: the Forage is a Nip at once")
		_expect_eq(int(preview["per_hit"]), 3, "...for 3")
		var landed: Array[int] = []
		var foraged: bool = false
		for turn in TURNS:
			foraged = foraged or EnemyTurn.current_intent(n, data).type == EnemyIntent.IntentType.HEAL_ALLY
			var outcome: Array = await _turn(controller, turn)
			landed.append(outcome[0])
		_expect(not foraged, "...and the Nipper never forages again")
		_expect_eq(landed, [3, 3, 3, 3, 3, 3, 3, 3] as Array[int], "...Nip 3 every turn")
	await _teardown()
	_completed += 1

# A Carve (6 to all) that kills the Nipper turns the Blackback Hungry
# exactly once.
func _check_carve_kills_nipper() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		var blackback: Node = _member(controller, "Blackback")
		var b: Combatant = _combatant(controller, blackback)
		_combatant(controller, _member(controller, "Nipper")).hp = 5
		var views: Array = controller.get("_hand_container").call("_card_views")
		controller.call("request_play", views[0])
		# Carve asks for a target like any card; its damage goes to all.
		if bool(controller.call("is_awaiting_target")):
			controller.call("confirm_target", blackback)
		await create_timer(2.0).timeout
		_expect_eq((controller.get("enemies") as Array).size(), 1, "Carve kills the Nipper")
		_expect_eq(b.hp, 34, "...and cuts the Blackback to 34")
		var hungry: int = 0
		for active: Status in b.statuses:
			_expect(active.data.id != "fed", "...no Fed left")
			if active.data.id == "hungry":
				hungry += active.stack_count
		_expect_eq(hungry, 1, "...Hungry exactly once")
	await _teardown()
	_completed += 1

# --- Helpers ---

# One enemy turn through the controller: the previews read first, then
# end_turn(). [what reached the player's HP, what the Blackback healed],
# each checked against its preview.
func _turn(controller: Node, turn: int) -> Array:
	var player: Combatant = controller.get("player")
	var expected_damage: int = 0
	var expected_heal: int = 0
	var blackback: Node = _member(controller, "Blackback")
	for member: Node in (controller.get("enemies") as Array):
		var preview: Dictionary = controller.call("get_intent_preview", member)
		if int(preview.get("type", -1)) == EnemyIntent.IntentType.HEAL_ALLY:
			expected_heal += int(preview["per_hit"])
		else:
			expected_damage += int(preview.get("damage_to_hp", 0))
	var b: Combatant = _combatant(controller, blackback) if blackback != null else null
	var hp_before: int = player.hp
	var blackback_before: int = b.hp if b != null else 0
	await controller.call("end_turn")
	var damage: int = hp_before - player.hp
	var healed: int = (b.hp - blackback_before) if b != null else 0
	_expect_eq(damage, expected_damage, "Turn %d: the damage previewed is the damage landed" % (turn + 1))
	_expect_eq(healed, expected_heal, "Turn %d: the heal previewed is the heal landed" % (turn + 1))
	return [damage, healed]

# A new run on floor 3 at PLAYER_HP, the fight started on the Blackback -
# a deck of `deck_card_path` alone when one is given. The controller, or
# null (a FAIL is recorded).
func _start_fight(deck_card_path: String = "") -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if deck_card_path != "":
		_set_deck(deck_card_path)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_3)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == BLACKBACK_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Blackback on floor 3")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(0.0, 0.0, 1.5)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 3")
		return null
	# Let the battle frame settle and the opening hand land.
	await create_timer(2.5).timeout
	var controller: Node = overlay.get("battle_controller")
	var player: Combatant = controller.get("player")
	_expect_eq(player.hp, PLAYER_HP, "The fight opens at %d HP (no turn can end it)" % PLAYER_HP)
	return controller

func _member(controller: Node, enemy_name: String) -> Node:
	for member: Node in (controller.get("enemies") as Array):
		var data: EnemyData = member.get("enemy_data")
		if data != null and data.enemy_name == enemy_name:
			return member
	return null

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

# To 0 through the controller's own damage path - kill_order_probe's
# _kill().
func _kill(controller: Node, member: Node) -> void:
	var combatant: Combatant = _combatant(controller, member)
	combatant.hp = 0
	controller.call("_report_damage", "player", combatant, 99, "card")

# What `member`'s intent readout says now (BattleIntent's number).
func _intent_text(controller: Node, member: Node) -> String:
	var intents: Dictionary = controller.get_parent().get("_enemy_intents")
	var intent: Node = intents.get(member)
	var label: Label = intent.get("_label") if intent != null else null
	return label.text if label != null else ""

# How grey the marabou's sac is now (its pass's grey_amount).
func _sac_grey(tells: Node) -> float:
	var sac: ShaderMaterial = tells.get("_sac")
	return float(sac.get_shader_parameter("grey_amount")) if sac != null else -1.0

func _shows(bar: Node, text: String) -> bool:
	var row: Variant = bar.get("_status_texts")
	if row is PackedStringArray:
		return (row as PackedStringArray).has(text)
	return str(row).contains(text)

func _set_deck(card_path: String) -> void:
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _intent_name(intent: EnemyIntent) -> String:
	if intent.type == EnemyIntent.IntentType.HEAL_ALLY:
		return "heal %d" % intent.value
	return ("%dx%d" % [intent.value, intent.hits]) if intent.hits > 1 else str(intent.value)

# A Peck from a fresh Blackback holding `status_path`, against an
# unguarded player: [previewed damage, landed damage, previewed hits].
func _peck_against(data: EnemyData, status_path: String) -> Array:
	var b := _enemy(data)
	Status.apply_to(b.statuses, load(status_path) as StatusData)
	var player := Combatant.new(PLAYER_HP)
	var preview: Dictionary = EnemyTurn.preview_intent(b, data, player)
	var result: Dictionary = EnemyTurn.take_turn(b, data, player)
	return [int(preview["damage_to_hp"]), int(result["damage_to_hp"]), preview["hit_amounts"]]

# The Lunge (the loop's second move) against a Blackback holding
# `status_path`: [what the preview said reaches HP, what landed].
func _lunge_against(data: EnemyData, status_path: String) -> Array:
	var b := _enemy(data)
	Status.apply_to(b.statuses, load(status_path) as StatusData)
	EnemyTurn._advance_intent(b, data)
	var player := Combatant.new(PLAYER_HP)
	var preview: Dictionary = EnemyTurn.preview_intent(b, data, player)
	var result: Dictionary = EnemyTurn.take_turn(b, data, player)
	return [int(preview["damage_to_hp"]), int(result["damage_to_hp"])]

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 5:
		await process_frame

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
