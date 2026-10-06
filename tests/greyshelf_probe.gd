extends SceneTree

# Headless probe for the Greyshelf, floor 5's region-end fight: its Flick
# -> Gape -> Tail Lash loop (nothing, 20, 4 x 3); the Gape breaking at 16
# damage dealt that turn, which stuns it (Stunned) so the Tail Lash after
# is skipped; Goaded - each Attack card played against it while the Gape
# is queued adds 2, up to +6, the preview always what lands, a Skill
# nothing, and a broken Gape's stacks cleared so the next starts at 20;
# off its rock below half HP (Off the rock), once - the Tail Lash strikes
# 4 times, the Gape still one blow. The rules cases drive EnemyTurn on the
# real .tres; the fight cases load floor 5 and play real cards through
# BattleController.request_play(); the body case reads GreyshelfPose and
# the measured size on the crest.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/greyshelf_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 11
const GREYSHELF_PATH := "res://battle/rules/enemies/greyshelf.tres"
const GOADED_PATH := "res://battle/rules/statuses/goaded.tres"
const STUNNED_PATH := "res://battle/rules/statuses/stunned.tres"
const OFF_THE_ROCK_PATH := "res://battle/rules/statuses/off_the_rock.tres"
const CONTACT_SOUND_PATH := "res://assets/audio/combat_old/hit.wav"
const MODEL_PATH := "res://assets/models/enemies/Greyshelf/Greyshelf.glb"
const POSE_SCENE_PATH := "res://field/greyshelf_pose.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const FLOOR_5 := 4
const MAX_HP := 120
const GAPE := 20
const BREAK := 16
const GOADED_BONUS := 2
const GOADED_CAP := 3
const LASH := 4
const LASH_HITS := 3
const PLAYER_HP := 999
# The body: 5 m long; the top of its back, belly sunk on the rock, about
# the Wanderer's waist-to-chest (measured and printed).
const LENGTH_M := 5.0
const LENGTH_TOLERANCE_M := 0.05
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
	_check_break_stuns()
	_check_goaded_climb()
	_check_break_clears_goaded()
	_check_phase()
	await _check_fight_gape()
	await _check_fight_skill()
	await _check_fight_break()
	await _check_fight_phase()
	await _check_body()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("greyshelf_probe: PASSED")
		quit(0)
	else:
		print("greyshelf_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _greyshelf()
	_expect_eq(data.enemy_name, "Greyshelf", "The Greyshelf")
	_expect_eq(data.max_hp, MAX_HP, "...120 HP")
	_expect(not data.is_elite, "...not elite: the region-end fight")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect(not data.mechanic_summary.is_empty(), "...with its mechanic summary")
	_expect_eq(data.intents.size(), 3, "...of three moves")
	if data.intents.size() == 3:
		var flick: EnemyIntent = data.intents[0]
		var gape: EnemyIntent = data.intents[1]
		var lash: EnemyIntent = data.intents[2]
		_expect(flick.intent_name == "Flick" and flick.type == EnemyIntent.IntentType.WATCH, "Flick first, a Watch")
		_expect(gape.intent_name == "Gape" and gape.type == EnemyIntent.IntentType.ATTACK and gape.value == GAPE and gape.hits == 1, "Gape second, 20 in one blow")
		_expect_eq(gape.interrupt_threshold, BREAK, "...broken by 16")
		_expect(gape.counts_attack_cards and gape.deny_next_on_interrupt and gape.rear_while_queued, "...counting Attack cards, stunning when broken, reared")
		_expect(gape.on_interrupt == null, "...nothing interjected: the stun takes the next move")
		_expect(lash.intent_name == "Tail Lash" and lash.value == LASH and lash.hits == LASH_HITS, "Tail Lash third, 4 x 3")
	var goaded: StatusData = data.attack_card_status
	_expect(goaded != null and goaded.resource_path == GOADED_PATH, "It gains Goaded")
	if goaded != null:
		_expect(goaded.display_name == "Goaded" and goaded.attack_damage_bonus == GOADED_BONUS and goaded.max_stacks == GOADED_CAP and goaded.consumed_by_own_attack, "...+2 a stack, up to 3 (+6), spent by its own attack")
		_expect_eq(Status.new(goaded).describe(), "Each Attack card played against it adds 2 damage to its next Gape, up to 6.", "...its hover")
	var stunned: StatusData = data.stun_status
	_expect(stunned != null and stunned.resource_path == STUNNED_PATH and stunned.skips_next_turn and stunned.display_name == "Stunned", "Broken, it is Stunned: its next move skipped")
	var off: StatusData = data.phase_status
	_expect(off != null and off.resource_path == OFF_THE_ROCK_PATH and off.bonus_hits == 1, "Below half: Off the rock, one more hit")
	if off != null:
		_expect_eq("%s: %s" % [off.display_name, Status.new(off).describe()], "Off the rock: Tail Lash strikes 4 times.", "...its readout line")
	_expect(is_equal_approx(data.phase_hp_threshold, 0.5), "...at half HP")
	_expect_eq(data.glassbone_reward, 1, "It leaves Glassbone x1")
	_expect_eq(data.model_scene_path, MODEL_PATH, "Its body the Greyshelf glb")
	_expect(is_equal_approx(data.model_scale, 1.36) and is_equal_approx(data.model_yaw_offset_degrees, 180.0), "...at 1.36, turned 180")
	_expect(is_equal_approx(data.sink_m, 0.3) and is_equal_approx(data.rest_height_m, 0.0), "...sunk 0.3 m, not buried")
	_expect_eq(data.attachment_scene_path, POSE_SCENE_PATH, "...GreyshelfPose")
	_expect(is_equal_approx(data.contact_radius_m, 3.2), "...a 3.2 m contact area")
	_expect(data.contact_sounds.size() == 1 and data.contact_sounds[0].resource_path == CONTACT_SOUND_PATH, "...the placeholder contact sound")
	_completed += 1

# Nothing played: Flick nothing, Gape 20, Tail Lash 4 x 3 - twice round.
func _check_loop() -> void:
	var data: EnemyData = _greyshelf()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var seen: Array[String] = []
	for turn in 6:
		var intent: EnemyIntent = EnemyTurn.current_intent(enemy, data)
		var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
		var before: int = player.hp
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		seen.append("%s %d%s" % [intent.intent_name.to_lower(), before - player.hp, (" x%d" % int(preview["hits"])) if bool(result["attacked"]) else " (no attack)"])
	_expect_eq(seen, ["flick 0 (no attack)", "gape 20 x1", "tail lash 12 x3", "flick 0 (no attack)", "gape 20 x1", "tail lash 12 x3"] as Array[String], "Flick -> Gape 20 -> Tail Lash 4 x 3, looping")
	_completed += 1

# 15 dealt on the Gape: it lands. 16: broken - nothing lands, Stunned; the
# Tail Lash shows struck (denied) and is skipped; then the Flick.
func _check_break_stuns() -> void:
	var data: EnemyData = _greyshelf()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	enemy.damage_taken_this_turn = BREAK - 1
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(preview["threshold"]), int(preview["threshold_left"])], [BREAK, 1], "15 dealt: the ring says 1 to go")
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, GAPE, "...and the Gape lands 20")
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	enemy.damage_taken_this_turn = BREAK
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview["interrupted"]) and int(preview["threshold_left"]) == 0 and not bool(preview["lethal"]), "16 dealt: broken, the ring closed")
	before = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["interrupted"]) and bool(result["stunned"]) and not bool(result["attacked"]), "The broken Gape doesn't land, and stuns")
	_expect_eq(player.hp, before, "...nothing lost")
	_expect(_has(enemy, STUNNED_PATH), "...Stunned")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Tail Lash", "...the Tail Lash queued")
	enemy.damage_taken_this_turn = 0
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect(bool(preview.get("denied", false)) and int(preview["damage_to_hp"]) == 0, "...shown struck through: it won't land")
	result = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["denied"]) and not bool(result["attacked"]), "The Tail Lash is skipped")
	_expect_eq(player.hp, before, "...nothing lost")
	_expect(not _has(enemy, STUNNED_PATH), "...Stunned spent")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Flick", "...and the Flick is next")
	_completed += 1

# On the Gape: 20, 22, 24, 26 and a fourth Attack card still 26 - the
# preview each time; it lands what the preview said and spends Goaded.
# Flick and Tail Lash queued: an Attack card adds nothing.
func _check_goaded_climb() -> void:
	var data: EnemyData = _greyshelf()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Flick queued: an Attack card adds nothing")
	EnemyTurn.take_turn(enemy, data, player)
	var shown: Array[int] = [int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"])]
	for card in 4:
		EnemyTurn.take_attack_card(enemy, data)
		shown.append(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]))
	_expect_eq(shown, [20, 22, 24, 26, 26] as Array[int], "The Gape climbs 20, 22, 24, 26 and holds at 26")
	_expect_eq(_goaded(enemy), GOADED_CAP, "...Goaded capped at 3")
	var expected: int = int(EnemyTurn.preview_intent(enemy, data, player)["damage_to_hp"])
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, expected, "The Gape lands what the preview said (%d)" % expected)
	_expect_eq(_goaded(enemy), 0, "...Goaded spent")
	_expect(not EnemyTurn.take_attack_card(enemy, data), "Tail Lash queued: an Attack card adds nothing")
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), LASH, "...the Tail Lash still 4 a hit")
	_completed += 1

# Goaded 2 on a Gape that breaks: cleared with it, Stunned; the skip and
# the Flick, and the next Gape is 20.
func _check_break_clears_goaded() -> void:
	var data: EnemyData = _greyshelf()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_attack_card(enemy, data)
	EnemyTurn.take_attack_card(enemy, data)
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), 24, "Goaded 2: the Gape shows 24")
	enemy.damage_taken_this_turn = BREAK
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_goaded(enemy), 0, "Broken: Goaded cleared")
	enemy.damage_taken_this_turn = 0
	EnemyTurn.take_turn(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Gape", "The next Gape")
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), GAPE, "...starts at 20")
	_completed += 1

# Down to 60 (half): nothing. 59: Off the rock, once - the Tail Lash
# previews and lands 4 x 4, the Gape still one blow of 20.
func _check_phase() -> void:
	var data: EnemyData = _greyshelf()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	enemy.hp = MAX_HP / 2
	_expect(not EnemyTurn.check_phase(enemy, data), "At 60 of 120: still on its rock")
	enemy.hp = MAX_HP / 2 - 1
	_expect(EnemyTurn.check_phase(enemy, data), "At 59: off the rock")
	_expect(_has(enemy, OFF_THE_ROCK_PATH), "...Off the rock")
	_expect(not EnemyTurn.check_phase(enemy, data), "...once")
	EnemyTurn.take_turn(enemy, data, player)
	var gape: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(gape["hits"]), int(gape["per_hit"])], [1, GAPE], "The Gape is still one blow of 20")
	EnemyTurn.take_turn(enemy, data, player)
	var lash: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(lash["hits"]), int(lash["per_hit"])], [LASH_HITS + 1, LASH], "The Tail Lash previews 4 x 4")
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, LASH * (LASH_HITS + 1), "...and lands 16")
	# Reached by a turn's own start (a countdown): take_turn() checks it too.
	var other: Combatant = _enemy(data)
	other.hp = 10
	var result: Dictionary = EnemyTurn.take_turn(other, data, player)
	_expect(bool(result["phase_triggered"]) and _has(other, OFF_THE_ROCK_PATH), "Below half at its turn's start: off the rock then")
	_completed += 1

# --- Fights ---

# The fight opens on the Flick; the Gape reads 20 with its ring at 16;
# each Slash puts the Gape up 2 and the ring down by the damage; the Gape
# lands its preview.
func _check_fight_gape() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, greyshelf)
		_expect_eq(EnemyTurn.current_intent(combatant, greyshelf.get("enemy_data")).intent_name, "Flick", "The fight opens on the Flick")
		_expect_eq(_intent_text(controller, greyshelf), "", "...its intent the eye alone, no number")
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, greyshelf), "20", "Gape queued: the intent reads 20")
		_expect_eq(_ring_text(controller, greyshelf), "16", "...its ring 16")
		var read: Array[String] = []
		for card in 2:
			await _play_first(controller, greyshelf)
			read.append("%s/%s" % [_intent_text(controller, greyshelf), _ring_text(controller, greyshelf)])
		var dealt: int = combatant.damage_taken_this_turn
		_expect_eq(read[1], "24/%d" % (BREAK - dealt), "...two Slashes: 24, the ring at %d" % (BREAK - dealt))
		_expect(_shows(controller, greyshelf, "Goaded"), "...Goaded in the readout")
		var player: Combatant = controller.get("player")
		var preview: Dictionary = controller.call("get_intent_preview", greyshelf)
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, int(preview["damage_to_hp"]), "The Gape lands its preview (%d)" % int(preview["damage_to_hp"]))
		_expect(not _shows(controller, greyshelf, "Goaded"), "...Goaded gone from the readout")
	await _teardown()
	_completed += 1

# A Skill played at the Gape (Brace) adds no Goaded: the intent is the
# Gape's own 20 through Brace's softening, never more.
func _check_fight_skill() -> void:
	var controller: Node = await _start_fight(BRACE_PATH)
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, greyshelf)
		await _end_turn(controller)
		await _play_first(controller, greyshelf)
		await _play_first(controller, greyshelf)
		_expect_eq(_goaded(combatant), 0, "Brace - a Skill - played on the Gape: no Goaded")
		_expect(not _shows(controller, greyshelf, "Goaded"), "...none in the readout")
		var preview: Dictionary = controller.call("get_intent_preview", greyshelf)
		_expect_eq(_intent_text(controller, greyshelf), str(int(preview["per_hit"])), "...the intent its preview (%s)" % _intent_text(controller, greyshelf))
		_expect(int(preview["per_hit"]) <= GAPE, "...never above 20")
	await _teardown()
	_completed += 1

# Slashes until 16 is dealt: the ring closes and the rear drops on that
# card; its turn - Stunned in the readout, the Tail Lash struck; its next
# turn takes nothing; then the Flick, and a Gape at 20 again. The tell
# (GreyshelfPose) holds while the Gape is queued and Goaded deepens it.
func _check_fight_break() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, greyshelf)
		var pose: Node = _pose(greyshelf)
		await _end_turn(controller)
		await create_timer(0.8).timeout
		if pose != null:
			_expect(is_equal_approx(float(pose.get("_rear")), float(pose.get("rear_degrees"))) and float(pose.call("get_rear_lift")) > 0.0, "Gape queued: the forequarters rear (%.1f deg, top up %.2f m)" % [float(pose.get("_rear")), float(pose.call("get_rear_lift"))])
			_expect(is_equal_approx(float(pose.call("get_throat_deepen")), float(pose.get("tell_deepen"))), "...the throat deepened (%.2f)" % float(pose.call("get_throat_deepen")))
		await _play_first(controller, greyshelf)
		if pose != null:
			_expect(float(pose.call("get_throat_deepen")) > float(pose.get("tell_deepen")), "...deeper with Goaded (%.2f)" % float(pose.call("get_throat_deepen")))
			_expect(float(pose.call("get_throat_deepen")) <= 1.0, "...never past its full")
		for card in 6:
			if combatant.damage_taken_this_turn >= BREAK:
				break
			await _play_first(controller, greyshelf)
		_expect(combatant.damage_taken_this_turn >= BREAK, "16 dealt (%d)" % combatant.damage_taken_this_turn)
		_expect_eq(_ring_text(controller, greyshelf), "0", "...the ring closed")
		await create_timer(0.6).timeout
		if pose != null:
			_expect(is_equal_approx(float(pose.get("_rear")), 0.0) and is_equal_approx(float(pose.call("get_throat_deepen")), 0.0), "...and the rear and the throat down on that card")
		var player: Combatant = controller.get("player")
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(player.hp, before, "The broken Gape lands nothing")
		_expect(_shows(controller, greyshelf, "Stunned"), "...Stunned in the readout")
		_expect(not _shows(controller, greyshelf, "Goaded"), "...Goaded cleared")
		var preview: Dictionary = controller.call("get_intent_preview", greyshelf)
		_expect(bool(preview.get("denied", false)), "...the Tail Lash shown struck")
		before = player.hp
		await _end_turn(controller)
		_expect_eq(player.hp, before, "The Tail Lash is skipped")
		_expect(not _shows(controller, greyshelf, "Stunned"), "...Stunned spent")
		_expect_eq(EnemyTurn.current_intent(combatant, greyshelf.get("enemy_data")).intent_name, "Flick", "...the Flick next")
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, greyshelf), "20", "The next Gape reads 20")
	await _teardown()
	_completed += 1

# The Tail Lash queued and the Greyshelf taken below half by the player's
# damage: Off the rock in the readout at once, the intent from 3×4 (hits
# × damage, BattleIntent's way) to 4×4.
func _check_fight_phase() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var greyshelf: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, greyshelf)
		await _end_turn(controller)
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, greyshelf), "3×4", "Tail Lash queued: 3×4")
		_expect(not _shows(controller, greyshelf, "Off the rock"), "...on its rock")
		combatant.hp = MAX_HP / 2 + 3
		await _play_first(controller, greyshelf)
		_expect(combatant.hp < MAX_HP / 2, "Slashed below half (%d)" % combatant.hp)
		_expect(_shows(controller, greyshelf, "Off the rock"), "...Off the rock in the readout at once")
		_expect_eq(_intent_text(controller, greyshelf), "4×4", "...the Tail Lash reads 4×4")
		var player: Combatant = controller.get("player")
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, LASH * (LASH_HITS + 1), "...and lands 16")
	await _teardown()
	_completed += 1

# --- The body ---

# On the crest: 5 m long, lying broadside (head east), sunk 0.3 m; the
# head turns and lifts toward the Wanderer within its look range and
# eases back beyond it; the fight's freeze eases it back too.
func _check_body() -> void:
	_new_run()
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	await create_timer(1.5).timeout
	var greyshelf: Node3D = _find_greyshelf()
	var pose: Node = _pose(greyshelf)
	if greyshelf == null or pose == null:
		_fail("no Greyshelf with its GreyshelfPose on floor 5")
		await _teardown()
		_completed += 1
		return
	var aabb: AABB = greyshelf.call("get_model_aabb")
	var length: float = maxf(aabb.size.x, aabb.size.z)
	var top: float = aabb.position.y + aabb.size.y
	print("greyshelf_probe: body %.2f m long, %.2f m wide, its back's top %.2f m above the rock (sunk %.2f), head height %.2f" % [length, minf(aabb.size.x, aabb.size.z), top, float(greyshelf.get("sink")), float(greyshelf.call("get_head_height"))])
	_expect(absf(length - LENGTH_M) < LENGTH_TOLERANCE_M, "It is 5 m long (%.2f)" % length)
	_expect(is_equal_approx(float(greyshelf.get("sink")), 0.3) and is_equal_approx(aabb.position.y, -0.3), "...set 0.3 m into the rock")
	var forward: Vector3 = -greyshelf.global_transform.basis.z
	_expect(forward.x > 0.99, "...its head east (%s)" % forward)
	_expect((greyshelf.get_node("SandMound") if greyshelf.has_node("SandMound") else null) == null, "...no mound: sunk, not buried")
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var head: Vector3 = greyshelf.global_position + forward * 2.0
	wanderer.global_position = head + Vector3(0.0, 0.0, 6.0)
	await create_timer(3.0).timeout
	var angle: float = float(pose.call("get_head_angle"))
	var lift: float = float(pose.get("_lift"))
	_expect(absf(angle) > 20.0, "The Wanderer 6 m off: the head turns to him (%.1f)" % angle)
	_expect(lift > 0.5 * float(pose.get("lift_degrees")), "...and lifts (%.1f)" % lift)
	_expect(is_equal_approx(float(pose.call("get_rear_lift")), 0.0), "...the body still lying")
	wanderer.global_position = head + Vector3(0.0, 0.0, 20.0)
	await create_timer(4.0).timeout
	_expect(absf(float(pose.call("get_head_angle"))) < 1.0 and float(pose.get("_lift")) < 0.5, "20 m off: the head eases back to the front")
	wanderer.global_position = head + Vector3(0.0, 0.0, 6.0)
	await create_timer(3.0).timeout
	_field.call_deferred("_on_enemy_contacted", greyshelf)
	await create_timer(4.0).timeout
	_expect(absf(float(pose.call("get_head_angle"))) < 1.0 and float(pose.get("_lift")) < 0.5, "The fight's freeze eases the head back (%.1f, %.1f)" % [float(pose.call("get_head_angle")), float(pose.get("_lift"))])
	await _teardown()
	_completed += 1

# --- Helpers ---

func _greyshelf() -> EnemyData:
	return load(GREYSHELF_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	return Combatant.new(PLAYER_HP)

func _has(combatant: Combatant, path: String) -> bool:
	for active: Status in combatant.statuses:
		if active.data.resource_path == path:
			return true
	return false

func _goaded(combatant: Combatant) -> int:
	for active: Status in combatant.statuses:
		if active.data.resource_path == GOADED_PATH:
			return active.stack_count
	return 0

func _new_run(card_path: String = SLASH_PATH) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_5)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)

func _find_greyshelf() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == GREYSHELF_PATH:
			return node as Node3D
	return null

func _pose(greyshelf: Node) -> Node:
	if greyshelf == null:
		return null
	var poses: Array[Node] = greyshelf.find_children("*", "GreyshelfPose", true, false)
	return poses[0] if poses.size() == 1 else null

# A new run on floor 5, the fight started on the Greyshelf with a deck of
# `card_path` alone and Energy enough for any number of plays. The
# controller, or null (a FAIL is recorded).
func _start_fight(card_path: String) -> Node:
	_new_run(card_path)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = _find_greyshelf()
	if target == null:
		_fail("no Greyshelf on floor 5")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 5")
		return null
	await create_timer(2.5).timeout
	var controller: Node = overlay.get("battle_controller")
	var members: Array = controller.get("enemies")
	_expect(members.size() == 1 and members[0] == target, "The fight is the Greyshelf alone")
	return controller

# The first card in hand, at the Greyshelf, with Energy topped up first.
func _play_first(controller: Node, greyshelf: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")):
		controller.call("confirm_target", greyshelf)
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

func _intent_node(controller: Node, member: Node) -> Node:
	var intents: Dictionary = controller.get_parent().get("_enemy_intents")
	return intents.get(member)

# What `member`'s intent readout says now (BattleIntent's number), and its
# ring's.
func _intent_text(controller: Node, member: Node) -> String:
	var intent: Node = _intent_node(controller, member)
	var label: Label = intent.get("_label") if intent != null else null
	return label.text if label != null else "<none>"

func _ring_text(controller: Node, member: Node) -> String:
	var intent: Node = _intent_node(controller, member)
	var label: Label = intent.get("_threshold_label") if intent != null else null
	return label.text if label != null and label.visible else "<none>"

func _shows(controller: Node, member: Node, prefix: String) -> bool:
	for text: String in controller.call("get_enemy_status_labels", member):
		if text.begins_with(prefix):
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
