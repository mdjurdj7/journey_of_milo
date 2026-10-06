extends SceneTree

# Headless probe for the Dunecur, floor 4's required fight: its Snarl ->
# Rush loop (6, then 10), and Roused - each Attack card played against it
# while the Rush is queued adds 2 to that Rush, once per card, up to +8
# (Rush 10 to 18); played while Snarl is queued, nothing; the Rush that
# lands spends it, even fully blocked; a Denied Rush keeps it, the Snarl
# after neither takes nor spends it, and the next Rush carries it. The
# intent preview climbs with it and always equals what lands. The rules cases drive EnemyTurn on the
# real .tres; the fight cases load floor 4 and play real cards through
# BattleController.request_play(), so Skills and multi-target Attacks
# are counted the way a player's are.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/dunecur_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 11
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
const SNARL := 6
const RUSH := 10
const ROUSED_BONUS := 2
const ROUSED_CAP := 4
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
	await _check_crest()
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
	_expect_eq(data.max_hp, 55, "...55 HP")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 2, "...of two moves")
	if data.intents.size() == 2:
		var snarl: EnemyIntent = data.intents[0]
		var rush: EnemyIntent = data.intents[1]
		_expect_eq(snarl.intent_name, "Snarl", "Snarl first")
		_expect_eq(snarl.type, EnemyIntent.IntentType.ATTACK, "...an Attack")
		_expect(snarl.value == SNARL and snarl.hits == 1, "...for 6")
		_expect(not snarl.counts_attack_cards, "...that counts no Attack cards")
		_expect_eq(rush.intent_name, "Rush", "Rush second")
		_expect_eq(rush.type, EnemyIntent.IntentType.ATTACK, "...an Attack")
		_expect(rush.value == RUSH and rush.hits == 1, "...for 10")
		_expect(rush.counts_attack_cards, "...that counts Attack cards")
	var roused: StatusData = data.attack_card_status
	_expect(roused != null and roused.resource_path == ROUSED_PATH, "It gains Roused")
	if roused != null:
		_expect_eq(roused.display_name, "Roused", "...named Roused")
		_expect_eq(roused.attack_damage_bonus, ROUSED_BONUS, "...+2 a stack")
		_expect_eq(roused.max_stacks, ROUSED_CAP, "...up to 4 stacks (+8)")
		_expect(roused.consumed_by_own_attack, "...spent by its own attack")
		_expect_eq(roused.default_duration_turns, StatusData.DURATION_UNTIL_REMOVED, "...and never by a turn")
		# Per card and the cap, whatever the stacks: ×3 still reads +2 / +8.
		var hover := "Each Attack card played against it adds 2 damage to its next Rush, up to 8."
		var status := Status.new(roused)
		_expect_eq(status.describe(), hover, "...its hover")
		status.apply_stack()
		status.apply_stack()
		_expect_eq(status.describe(), hover, "...the same at Roused ×3")
	_expect_eq(data.contact_radius_m, 3.0, "Its contact area is 3 m")
	_expect_eq(data.model_scene_path, MODEL_PATH, "...its body the Dunecur glb")
	_expect(is_equal_approx(data.model_scale, 1.34) and is_equal_approx(data.model_yaw_offset_degrees, 180.0), "...at 1.34, turned 180")
	_expect(data.contact_sounds.size() == 1 and data.contact_sounds[0].resource_path == CONTACT_SOUND_PATH, "...the placeholder contact sound")
	_completed += 1

# Nothing played: Snarl lands 6, Rush lands 10 - twice round, in that
# order, and no Block either way.
func _check_loop() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var seen: Array[String] = []
	for turn in 4:
		var name: String = EnemyTurn.current_intent(enemy, data).intent_name
		var before: int = player.hp
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		seen.append("%s %d%s" % [name.to_lower(), before - player.hp, "" if bool(result["attacked"]) else " (no attack)"])
	_expect_eq(seen, ["snarl 6", "rush 10", "snarl 6", "rush 10"] as Array[String], "Snarl 6 -> Rush 10, looping")
	_expect_eq(enemy.block, 0, "...and it never Blocks")
	_completed += 1

# Only the turn the Rush is queued counts: Snarl takes nothing.
func _check_window() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Snarl queued: an Attack card adds nothing")
	_expect_eq(_roused(enemy), 0, "...no Roused")
	EnemyTurn.take_turn(enemy, data, player)
	_expect(EnemyTurn.take_attack_card(enemy, data), "Rush queued: an Attack card counts")
	_expect_eq(_roused(enemy), 1, "...Roused 1")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_roused(enemy), 0, "The Rush landed: Roused spent")
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Snarl queued again: an Attack card adds nothing")
	_expect_eq(_roused(enemy), 0, "...no Roused")
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), SNARL, "...and the Snarl shows 6")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), RUSH, "The next Rush starts at 10")
	_completed += 1

# On the Rush: 10, 12, 14, 16, 18, and a fifth Attack card still 18 - the
# preview each time; the Rush lands what the preview said and spends
# Roused; the next Rush is back to 10.
func _check_climb_and_cap() -> void:
	var data: EnemyData = _dunecur()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	var shown: Array[int] = [int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"])]
	for card in 5:
		EnemyTurn.take_attack_card(enemy, data)
		shown.append(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]))
	_expect_eq(shown, [10, 12, 14, 16, 18, 18] as Array[int], "The intent climbs 10, 12, 14, 16, 18 and holds at 18")
	_expect_eq(_roused(enemy), ROUSED_CAP, "...Roused capped at 4")
	var expected: int = int(EnemyTurn.preview_intent(enemy, data, player)["damage_to_hp"])
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, expected, "The Rush lands what the preview said (%d)" % expected)
	_expect_eq(before - player.hp, 18, "...18")
	_expect_eq(_roused(enemy), 0, "...and Roused is spent")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), RUSH, "The next Rush is 10 again")
	_completed += 1

# A Denied Rush lands nothing and keeps Roused. The Snarl that follows
# neither takes it nor spends it - Attack cards on it add nothing, and it
# lands 6 - so the next Rush carries the kept 2 stacks: 14, then spent.
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
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Snarl queued: an Attack card adds nothing")
	_expect_eq(_roused(enemy), 2, "...Roused still 2")
	var shown: int = int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"])
	_expect_eq(shown, SNARL, "The Snarl shows 6, Roused 2 or not")
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, SNARL, "...and lands 6")
	_expect_eq(_roused(enemy), 2, "...leaving Roused 2 for the Rush")
	var rush: int = RUSH + 2 * ROUSED_BONUS
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), rush, "The next Rush shows 14")
	before = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, rush, "...and lands 14")
	_expect_eq(_roused(enemy), 0, "...spending Roused")
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), RUSH, "The Rush after is back to 10")
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
	_expect_eq(player.block, 50 - 16, "...16 off the Block")
	_expect_eq(_roused(enemy), 0, "...and Roused is spent")
	_completed += 1

# --- Fights ---

# Slash on Snarl counts nothing; once the Rush is queued, each Slash puts
# the readout up 2 - 10, 12, 14, 16 - and the Rush lands its preview.
func _check_fight_slash() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var dunecur: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, dunecur)
		_expect_eq(EnemyTurn.current_intent(combatant, dunecur.get("enemy_data")).intent_name, "Snarl", "The fight opens on Snarl")
		_expect_eq(_intent_text(controller, dunecur), "6", "...its intent 6")
		await _play_first(controller, dunecur)
		_expect_eq(_roused(combatant), 0, "Slash on Snarl: no Roused")
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, dunecur), "10", "Rush queued: the intent reads 10")
		var read: Array[String] = []
		for card in 3:
			await _play_first(controller, dunecur)
			read.append(_intent_text(controller, dunecur))
		_expect_eq(read, ["12", "14", "16"] as Array[String], "...each Slash puts it up 2: 12, 14, 16")
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
		_expect_eq(_intent_text(controller, dunecur), "12", "...the intent 12")
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

# The crest and the head (DunecurPose): in the field the head is down
# feeding and the crest flat; the fight lifts the head; set_roused() puts
# the crest at its step per stack - 70, 52.5, 35, 17.5, 0 degrees of fold -
# and so do Slashes on the Rush through the controller, the landed Rush
# folding it flat again.
func _check_crest() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_4)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	await create_timer(1.5).timeout
	var dunecur: Node = null
	for node in get_nodes_in_group("enemies"):
		if (node.get("enemy_data") as Resource).resource_path == DUNECUR_PATH:
			dunecur = node
	var poses: Array[Node] = dunecur.find_children("*", "DunecurPose", true, false) if dunecur != null else []
	if poses.size() != 1:
		_fail("the Dunecur has no DunecurPose")
		await _teardown()
		_completed += 1
		return
	var pose: Node = poses[0]
	var flat: float = float(pose.get("flat_fold_degrees"))
	var step: float = float(pose.get("rise_per_stack_degrees"))
	_expect(is_equal_approx(flat, 70.0) and is_equal_approx(step, 17.5), "Flat is a 70 degree fold, 17.5 a stack")
	_expect(is_equal_approx(float(pose.call("get_head_dip_degrees")), float(pose.get("feed_dip_degrees"))), "In the field his head is down, feeding (%.1f)" % float(pose.call("get_head_dip_degrees")))
	_expect(is_equal_approx(float(pose.call("get_crest_fold_degrees")), flat), "...and his crest flat")
	dunecur.call("set_roused", 4)
	await create_timer(0.6).timeout
	_expect(is_equal_approx(float(pose.call("get_crest_fold_degrees")), flat), "Roused out of a fight: the crest stays flat")
	dunecur.call("set_roused", 0)
	_field.call_deferred("_on_enemy_contacted", dunecur)
	await create_timer(2.5).timeout
	var layer: Node = _field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		_fail("no fight started on floor 4")
	else:
		var controller: Node = layer.get_child(0).get("battle_controller")
		_expect(is_equal_approx(float(pose.call("get_head_dip_degrees")), 0.0), "The fight lifts his head (%.1f)" % float(pose.call("get_head_dip_degrees")))
		var folds: Array[float] = []
		for stacks in 5:
			dunecur.call("set_roused", stacks)
			await create_timer(float(pose.get("crest_ease_seconds")) + 0.15).timeout
			folds.append(snappedf(float(pose.call("get_crest_fold_degrees")), 0.01))
		_expect_eq(folds, [70.0, 52.5, 35.0, 17.5, 0.0] as Array[float], "set_roused() puts the crest at its step per stack")
		dunecur.call("set_roused", 0)
		await _end_turn(controller)
		var targets: Array[float] = [float(pose.call("get_crest_target_degrees"))]
		for card in 4:
			await _play_first(controller, dunecur)
			targets.append(float(pose.call("get_crest_target_degrees")))
		_expect_eq(targets, [70.0, 52.5, 35.0, 17.5, 0.0] as Array[float], "Slashes on the Rush raise it a step a card")
		await _end_turn(controller)
		await create_timer(float(pose.get("crest_ease_seconds")) + 0.15).timeout
		_expect(is_equal_approx(float(pose.call("get_crest_fold_degrees")), flat), "The Rush landed: it settles flat")
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
