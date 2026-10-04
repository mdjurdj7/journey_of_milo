extends SceneTree

# Headless probe for the Dunecur, floor 4's required fight: its Watch ->
# Rush -> Recover loop (nothing, 7, 5 Block), and Roused - each Attack
# card played against it while the Rush is queued adds 2 to that Rush,
# once per card, up to +8 (Rush 7 to 15); played while Watch or Recover
# is queued, nothing; the Rush that lands spends it, even fully blocked;
# a Denied Rush keeps it for the next. The intent preview climbs with it
# and always equals what lands. The rules cases drive EnemyTurn on the
# real .tres; the fight cases load floor 4 and play real cards through
# BattleController.request_play(), so Skills and multi-target Attacks
# are counted the way a player's are.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/dunecur_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 10
const DUNECUR_PATH := "res://battle/rules/enemies/dunecur.tres"
const ROUSED_PATH := "res://battle/rules/statuses/roused.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const CONTACT_SOUND_PATH := "res://assets/audio/combat_old/hit.wav"
const MODEL_PATH := "res://assets/models/enemies/Dunecur/Dunecur.glb"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const FLOOR_4 := 3
const RUSH := 7
const ROUSED_BONUS := 2
const ROUSED_CAP := 4
const RECOVER := 5
const PLAYER_HP := 999
const SAFETY_SECONDS := 300.0

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
	_check_loop()
	_check_window()
	_check_climb_and_cap()
	_check_denied_keeps()
	_check_blocked_spends()
	await _check_fight_slash()
	await _check_fight_carve()
	await _check_fight_skill()
	await _check_fight_strike_hover()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("dunecur_probe: PASSED")
		quit(0)
	else:
		print("dunecur_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _dunecur()
	_expect_eq(data.enemy_name, "Dunecur", "The Dunecur")
	_expect_eq(data.max_hp, 44, "...44 HP")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 3, "...of three moves")
	if data.intents.size() == 3:
		var watch: EnemyIntent = data.intents[0]
		var rush: EnemyIntent = data.intents[1]
		var recover: EnemyIntent = data.intents[2]
		_expect_eq(watch.type, EnemyIntent.IntentType.WATCH, "Watch is a WATCH")
		_expect(not watch.counts_attack_cards, "...that counts no Attack cards")
		_expect_eq(rush.type, EnemyIntent.IntentType.ATTACK, "Rush is an Attack")
		_expect_eq(rush.value, RUSH, "...for 7")
		_expect(rush.counts_attack_cards, "...that counts Attack cards")
		_expect_eq(recover.type, EnemyIntent.IntentType.DEFEND, "Recover is a Defend")
		_expect_eq(recover.value, RECOVER, "...for 5 Block")
		_expect(not recover.counts_attack_cards, "...that counts none")
	var roused: StatusData = data.attack_card_status
	_expect(roused != null and roused.resource_path == ROUSED_PATH, "It gains Roused")
	if roused != null:
		_expect_eq(roused.display_name, "Roused", "...named Roused")
		_expect_eq(roused.attack_damage_bonus, ROUSED_BONUS, "...+2 a stack")
		_expect_eq(roused.max_stacks, ROUSED_CAP, "...up to 4 stacks (+8)")
		_expect(roused.consumed_by_own_attack, "...spent by its own attack")
		_expect_eq(roused.default_duration_turns, StatusData.DURATION_UNTIL_REMOVED, "...and never by a turn")
		_expect_eq(roused.description, "Each Attack card played against it adds 2 damage to its next Rush.", "...its hover")
	_expect_eq(data.contact_radius_m, 3.0, "Its contact area is 3 m")
	_expect_eq(data.model_scene_path, MODEL_PATH, "...its body the Dunecur glb")
	_expect(is_equal_approx(data.model_scale, 1.34) and is_equal_approx(data.model_yaw_offset_degrees, 180.0), "...at 1.34, turned 180")
	_expect(data.contact_sounds.size() == 1 and data.contact_sounds[0].resource_path == CONTACT_SOUND_PATH, "...the placeholder contact sound")
	_completed += 1

# Nothing played: Watch does nothing, Rush lands 7, Recover gains 5
# Block - twice round, in that order.
func _check_loop() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var seen: Array[String] = []
	for turn in 6:
		var before: int = player.hp
		var block_before: int = enemy.block
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		if bool(result["attacked"]):
			seen.append("rush %d" % (before - player.hp))
		elif bool(result["defended"]):
			seen.append("recover %d" % (enemy.block - block_before))
		elif player.hp == before and enemy.block == block_before:
			seen.append("watch")
		else:
			seen.append("?")
	_expect_eq(seen, ["watch", "rush 7", "recover 5", "watch", "rush 7", "recover 5"] as Array[String], "Watch -> Rush 7 -> Recover 5, looping")
	_completed += 1

# Only the turn the Rush is queued counts: Watch and Recover take nothing.
func _check_window() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Watch queued: an Attack card adds nothing")
	_expect_eq(_roused(enemy), 0, "...no Roused")
	EnemyTurn.take_turn(enemy, data, player)
	_expect(EnemyTurn.take_attack_card(enemy, data), "Rush queued: an Attack card counts")
	_expect_eq(_roused(enemy), 1, "...Roused 1")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_roused(enemy), 0, "The Rush landed: Roused spent")
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Recover queued: an Attack card adds nothing")
	_expect_eq(_roused(enemy), 0, "...no Roused")
	EnemyTurn.take_turn(enemy, data, player)
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Watch queued again: nothing")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), RUSH, "The next Rush starts at 7")
	_completed += 1

# On the Rush: 7, 9, 11, 13, 15, and a fifth Attack card still 15 - the
# preview each time; the Rush lands what the preview said and spends
# Roused; the next Rush is back to 7.
func _check_climb_and_cap() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	var shown: Array[int] = [int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"])]
	for card in 5:
		EnemyTurn.take_attack_card(enemy, data)
		shown.append(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]))
	_expect_eq(shown, [7, 9, 11, 13, 15, 15] as Array[int], "The intent climbs 7, 9, 11, 13, 15 and holds at 15")
	_expect_eq(_roused(enemy), ROUSED_CAP, "...Roused capped at 4")
	var expected: int = int(EnemyTurn.preview_intent(enemy, data, player)["damage_to_hp"])
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, expected, "The Rush lands what the preview said (%d)" % expected)
	_expect_eq(before - player.hp, 15, "...15")
	_expect_eq(_roused(enemy), 0, "...and Roused is spent")
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), RUSH, "The next Rush is 7 again")
	_completed += 1

# A Denied Rush lands nothing and keeps Roused through Recover and Watch
# (which add nothing), for the next Rush to land.
func _check_denied_keeps() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_attack_card(enemy, data)
	EnemyTurn.take_attack_card(enemy, data)
	Status.apply_to(enemy.statuses, load(DENIED_PATH) as StatusData)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview.get("denied", false)), "Denied on the Rush: the preview says so")
	_expect_eq(int(preview["damage_to_hp"]), 0, "...and that nothing reaches")
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["denied"]) and not bool(result["attacked"]), "The Denied Rush doesn't land")
	_expect_eq(player.hp, before, "...nothing lost")
	_expect_eq(_roused(enemy), 2, "...and Roused 2 stays")
	EnemyTurn.take_attack_card(enemy, data)
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_attack_card(enemy, data)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_roused(enemy), 2, "Recover and Watch add nothing to it")
	var shown: int = int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"])
	_expect_eq(shown, 11, "The next Rush shows 11")
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, 11, "...and lands 11")
	_expect_eq(_roused(enemy), 0, "...spending Roused")
	_completed += 1

# A Rush the player's Block takes all of still lands, and still spends
# Roused.
func _check_blocked_spends() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	for card in 3:
		EnemyTurn.take_attack_card(enemy, data)
	player.block = 50
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["attacked"]), "A fully blocked Rush still lands")
	_expect_eq(player.hp, before, "...nothing through")
	_expect_eq(player.block, 50 - 13, "...13 off the Block")
	_expect_eq(_roused(enemy), 0, "...and Roused is spent")
	_completed += 1

# --- Fights ---

# Slash on Watch counts nothing; once the Rush is queued, each Slash puts
# the readout up 2 - 7, 9, 11, 13 - and the Rush lands its preview.
func _check_fight_slash() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var dunecur: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, dunecur)
		_expect_eq(EnemyTurn.current_intent(combatant, dunecur.get("enemy_data")).type, EnemyIntent.IntentType.WATCH, "The fight opens on Watch")
		_expect_eq(_intent_text(controller, dunecur), "", "...its intent the eye alone, no number")
		await _play_first(controller, dunecur)
		_expect_eq(_roused(combatant), 0, "Slash on Watch: no Roused")
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, dunecur), "7", "Rush queued: the intent reads 7")
		var read: Array[String] = []
		for card in 3:
			await _play_first(controller, dunecur)
			read.append(_intent_text(controller, dunecur))
		_expect_eq(read, ["9", "11", "13"] as Array[String], "...each Slash puts it up 2: 9, 11, 13")
		_expect_eq(_roused(combatant), 3, "...Roused 3")
		var player: Combatant = controller.get("player")
		var preview: Dictionary = controller.call("get_intent_preview", dunecur)
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, int(preview["damage_to_hp"]), "The Rush lands its preview (%d)" % int(preview["damage_to_hp"]))
		_expect_eq(_roused(combatant), 0, "...and Roused is spent")
		_expect_eq(_shows_roused(controller, dunecur), false, "...gone from the readout")
	await _teardown()
	_completed += 1

# Carve, an all-enemies Attack, counts once a card.
func _check_fight_carve() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		var dunecur: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, dunecur)
		await _end_turn(controller)
		await _play_first(controller, dunecur)
		_expect_eq(_roused(combatant), 1, "Carve on the Rush: Roused 1, once for the card")
		_expect_eq(_intent_text(controller, dunecur), "9", "...the intent 9")
		_expect(_shows_roused(controller, dunecur), "...and the readout shows Roused")
		await _play_first(controller, dunecur)
		_expect_eq(_roused(combatant), 2, "A second Carve: Roused 2")
	await _teardown()
	_completed += 1

# A Skill on the Rush counts nothing, even one played at it (Brace).
func _check_fight_skill() -> void:
	var controller: Node = await _start_fight(BRACE_PATH)
	if controller != null:
		var dunecur: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, dunecur)
		await _end_turn(controller)
		await _play_first(controller, dunecur)
		await _play_first(controller, dunecur)
		_expect_eq(_roused(combatant), 0, "Brace - a Skill, played at it - on the Rush: no Roused")
		_expect(not _shows_roused(controller, dunecur), "...none in the readout")
	await _teardown()
	_completed += 1

# The hand's Slash answers its STRIKE label with "An Attack card."
func _check_fight_strike_hover() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var views: Array = controller.get("_hand_container").call("_card_views")
		if views.is_empty():
			_fail("no hand to hover")
		else:
			var view: Node = views[0]
			var rect: Rect2 = view.call("strike_label_rect")
			_expect_eq(view.call("keyword_at", rect.get_center()), "STRIKE", "A Slash in hand answers STRIKE over its type label")
			_expect_eq(view.get("strike_label_definition"), "An Attack card.", "...defined as \"An Attack card.\"")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _dunecur() -> EnemyData:
	return load(DUNECUR_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	return Combatant.new(PLAYER_HP)

func _roused(combatant: Combatant) -> int:
	for active: Status in combatant.statuses:
		if active.data.id == "roused":
			return active.stack_count
	return 0

# A new run on floor 4, the fight started on the Dunecur with a deck of
# `card_path` alone and Energy enough for any number of plays. The
# controller, or null (a FAIL is recorded).
func _start_fight(card_path: String) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == DUNECUR_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Dunecur on floor 4")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 4")
		return null
	await create_timer(2.5).timeout
	var controller: Node = overlay.get("battle_controller")
	var members: Array = controller.get("enemies")
	_expect(members.size() == 1 and members[0] == target, "The fight is the Dunecur alone")
	return controller

# The first card in hand, at the Dunecur, with Energy topped up first.
func _play_first(controller: Node, dunecur: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")):
		controller.call("confirm_target", dunecur)
	for i in 120:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.6).timeout

func _end_turn(controller: Node) -> void:
	await controller.call("end_turn")
	await create_timer(0.5).timeout

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

# What `member`'s intent readout says now (BattleIntent's number).
func _intent_text(controller: Node, member: Node) -> String:
	var intents: Dictionary = controller.get_parent().get("_enemy_intents")
	var intent: Node = intents.get(member)
	var label: Label = intent.get("_label") if intent != null else null
	return label.text if label != null else "<none>"

func _shows_roused(controller: Node, member: Node) -> bool:
	for text: String in controller.call("get_enemy_status_labels", member):
		if text.begins_with("Roused"):
			return true
	return false

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
