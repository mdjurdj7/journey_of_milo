extends SceneTree

# Headless probe for the heavy-hit tier and the hit-stop (BattleFeedback):
# a 30-damage card hit is in the tier and a 5 isn't; the impact layer is
# silent at the light end and heavy_impact_max_volume_db at the full one,
# and deals its two takes in turn; a Toll blow (Reckoning) counts as at
# least heavy_min_damage. The stop: 70 ms for a normal hit, 110 for one
# of 15 or more or a kill, 40 for each hit of a multi-hit (a kill still
# 110) and for a hit a block takes whole, none with hitstop_enabled off.
# And presentation only: a real Reckoning on 30 Toll, played through
# BattleController with the tier and the stop on and again with both
# off, leaves the fight in the same state - on, it held the two fighters
# (FieldEnemy.is_held(), Wanderer.is_animation_held()) and sounded the
# layer, off it did neither; Engine.time_scale never moves; and the Toll
# readout, drained, reads what is left.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/heavy_hit_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# BattleFeedback names Wanderer, so it is reached through load()/call()
# only - untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 4
const FEEDBACK_PATH := "res://battle/battle_feedback.gd"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const TAKE_PATHS: Array[String] = ["res://assets/audio/sfx/heavy_impact_01.mp3", "res://assets/audio/sfx/heavy_impact_02.mp3"]
const TOLL := 30
const PLAYER_HP := 40
const ENEMY_HP := 999
# Slack for frame timing, in milliseconds.
const SLACK_MS := 20
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

	_check_tier()
	_check_takes_alternate()
	_check_toll_blow_floor()
	await _check_rules_unchanged()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("heavy_hit_probe: PASSED")
		quit(0)
	else:
		print("heavy_hit_probe: %d FAILED" % _failures)
		quit(1)

# 30 in the tier, 5 not; the layer at either end; the recoil and number
# multipliers; the camera jolt from 30 and its toggle; the tier off. The
# stop's lengths, and none with it off.
func _check_tier() -> void:
	var feedback: Node = _feedback()
	var level_30: float = feedback.call("heavy_level", 30)
	var level_5: float = feedback.call("heavy_level", 5)
	_expect(level_30 >= 0.0, "A 30-damage hit is heavy (level %.2f)" % level_30)
	_expect(level_5 < 0.0, "A 5-damage hit isn't")
	_expect_eq(roundi(float(feedback.call("stop_ms", 5))), 70, "A 5-damage hit stops 70 ms")
	_expect_eq(roundi(float(feedback.call("stop_ms", 14))), 70, "...a 14 too")
	_expect_eq(roundi(float(feedback.call("stop_ms", 15))), 110, "A 15 stops 110 ms")
	_expect_eq(roundi(float(feedback.call("stop_ms", 3, true))), 110, "A kill for 3 stops 110 ms")
	_expect_eq(roundi(float(feedback.call("stop_ms", 20, false, true))), 40, "One hit of a multi-hit, 40 ms - for 20 as well")
	_expect_eq(roundi(float(feedback.call("stop_ms", 4, true, true))), 110, "...the one that kills, 110")
	_expect_eq(roundi(float(feedback.call("blocked_stop_ms"))), 40, "A hit a block takes whole, 40 ms")
	_expect(float(feedback.call("heavy_impact_volume_db", feedback.call("heavy_level", 10))) <= -80.0, "The layer is silent at 10")
	_expect(is_equal_approx(float(feedback.call("heavy_impact_volume_db", feedback.call("heavy_level", 35))), -14.0), "...and -14 dB at 35")
	_expect(is_equal_approx(float(feedback.call("recoil_multiplier", level_5)), 1.0) and is_equal_approx(float(feedback.call("recoil_multiplier", 1.0)), 1.6), "Recoil x1 below the tier, x1.6 at its top")
	_expect(is_equal_approx(float(feedback.call("number_multiplier", level_5)), 1.0) and is_equal_approx(float(feedback.call("number_multiplier", 1.0)), 1.4), "The number x1 below the tier, x1.4 at its top")
	_expect(bool(feedback.call("jolts_camera", 30)) and not bool(feedback.call("jolts_camera", 29)), "30 jolts the camera, 29 doesn't")
	feedback.set("camera_shake_enabled", false)
	_expect(not bool(feedback.call("jolts_camera", 30)), "...and with the toggle off, nothing does")
	feedback.set("heavy_hit_enabled", false)
	_expect(float(feedback.call("heavy_level", 30)) < 0.0, "The tier off: 30 is an ordinary hit")
	feedback.set("hitstop_enabled", false)
	_expect(is_zero_approx(float(feedback.call("stop_ms", 30, true))) and is_zero_approx(float(feedback.call("blocked_stop_ms"))), "The stop off: no stop at all")
	feedback.free()
	_completed += 1

# The two takes, in turn: never the same one twice running.
func _check_takes_alternate() -> void:
	var feedback: Node = _feedback()
	var dealt: Array[String] = []
	for i in 4:
		var take: AudioStream = feedback.call("next_heavy_take")
		dealt.append(take.resource_path if take != null else "")
	_expect_eq(dealt.slice(0, 2).duplicate(), TAKE_PATHS, "The impact layer's two takes")
	for i in range(1, dealt.size()):
		_expect(dealt[i] != dealt[i - 1], "Take %d differs from the one before it" % (i + 1))
	feedback.free()
	_completed += 1

# Reckoning's blow counts as at least heavy_min_damage; a Slash's is its
# own.
func _check_toll_blow_floor() -> void:
	var feedback: Node = _feedback()
	feedback.call("set_impact_card", load(RECKONING_PATH))
	_expect_eq(int(feedback.call("heavy_damage", 3)), 10, "A Reckoning for 3 counts as 10")
	_expect_eq(int(feedback.call("heavy_damage", 27)), 27, "...one for 27 as 27")
	feedback.call("set_impact_card", load(SLASH_PATH))
	_expect_eq(int(feedback.call("heavy_damage", 3)), 3, "A Slash for 3 is 3")
	feedback.free()
	_completed += 1

# The same Reckoning on 30 Toll, tier and stop on, then both off: the
# same enemy HP, Toll, HP and Energy after. On: the enemy and the
# Wanderer held, and the layer sounded; off: none of it. The world's
# time scale untouched throughout.
func _check_rules_unchanged() -> void:
	var on: Dictionary = await _reckoning_fight(true)
	var off: Dictionary = await _reckoning_fight(false)
	_expect_eq(on.get("state"), off.get("state"), "Reckoning's outcome is the same with the tier on and off")
	_expect(int((on.get("state", [0]) as Array)[0]) == ENEMY_HP - TOLL, "...30 dealt (%s)" % str(on.get("state")))
	_expect(bool(on.get("enemy_held", false)) and bool(on.get("wanderer_held", false)), "On: the enemy and the Wanderer held (%s / %s)" % [str(on.get("enemy_held")), str(on.get("wanderer_held"))])
	_expect(int(on.get("held_ms", 0)) >= 110 - SLACK_MS, "...for the big hit's stop (%d ms)" % int(on.get("held_ms", 0)))
	_expect(bool(on.get("layer", false)), "...and the impact layer sounded")
	_expect(not bool(off.get("enemy_held", true)) and not bool(off.get("wanderer_held", true)), "Off: no hold")
	_expect(not bool(off.get("layer", true)), "...and no layer")
	_expect(is_equal_approx(float(on.get("slowest", 0.0)), 1.0) and is_equal_approx(float(off.get("slowest", 0.0)), 1.0), "The world's time scale never moves (%.2f / %.2f)" % [float(on.get("slowest", 0.0)), float(off.get("slowest", 0.0))])
	_expect(int(on.get("toll_shown", -1)) == 0 and int(off.get("toll_shown", -1)) == 0, "The Toll readout has drained to 0 (%s / %s)" % [str(on.get("toll_shown")), str(off.get("toll_shown"))])
	_completed += 1

# One fight: Reckoning on TOLL at the first enemy, the tier and the stop
# `enabled`. Returns {state: [enemy HP, Toll, HP, Energy], toll_shown: the
# Toll readout's numeral after, slowest: the lowest time_scale seen while
# it resolved, enemy_held / wanderer_held: whether each was ever held,
# held_ms: the enemy's longest hold (game ms), layer: whether
# HeavyImpactAudio played a take}.
func _reckoning_fight(enabled: bool) -> Dictionary:
	var out: Dictionary = {}
	var controller: Node = await _start_fight()
	if controller != null:
		var feedback: Node = controller.get_parent().get("_battle_feedback")
		feedback.set("heavy_hit_enabled", enabled)
		feedback.set("hitstop_enabled", enabled)
		var wanderer: Node = _field.get_node("Wanderer")
		var player: Combatant = controller.get("player")
		player.toll = TOLL
		var card: CardData = (load(RECKONING_PATH) as CardData).duplicate()
		var deck: Object = controller.get("deck")
		(deck.get("draw_pile") as Array).append(card)
		deck.call("draw", 1)
		await process_frame
		var view: CardView = null
		for candidate: CardView in controller.get("_hand_container").call("_card_views"):
			if candidate.card_data == card:
				view = candidate
		var enemy: Node = (controller.get("_combatants") as Dictionary).keys()[0]
		var slowest: float = 1.0
		var enemy_held: bool = false
		var wanderer_held: bool = false
		var held_from: int = -1
		var held_ms: int = 0
		if view == null:
			_fail("Reckoning is not in the hand")
		else:
			controller.call("request_play", view)
			controller.call("confirm_target", enemy)
			for i in 900:
				await process_frame
				slowest = minf(slowest, Engine.time_scale)
				var held_now: bool = bool(enemy.call("is_held"))
				enemy_held = enemy_held or held_now
				wanderer_held = wanderer_held or bool(wanderer.call("is_animation_held"))
				if held_now and held_from < 0:
					held_from = ProbePlay.game_msec()
				elif not held_now and held_from >= 0:
					held_ms = maxi(held_ms, ProbePlay.game_msec() - held_from)
					held_from = -1
				if not bool(controller.get("_input_locked")) and not held_now:
					break
			# The Toll readout's drain runs on real time; let it finish.
			await create_timer(0.5, true, false, true).timeout
		var layer: Node = enemy.get_node_or_null("HeavyImpactAudio")
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
		var bar: Object = controller.get_parent().get("_field_hp_bar")
		out = {
			"state": [combatant.hp, player.toll, player.hp, player.energy],
			"toll_shown": int(bar.get("_toll")) if bar != null else -1,
			"slowest": slowest,
			"enemy_held": enemy_held,
			"wanderer_held": wanderer_held,
			"held_ms": held_ms,
			"layer": layer != null and (layer as AudioStreamPlayer3D).stream != null and TAKE_PATHS.has((layer as AudioStreamPlayer3D).stream.resource_path),
		}
	await _teardown()
	return out

func _feedback() -> Node:
	return (load(FEEDBACK_PATH) as GDScript).new()

# A fresh run and a fresh fight on floor 1 against its first enemy, made
# unkillable here, at PLAYER_HP, with an empty hand and 3 Energy - as
# ransom_probe.gd starts its own.
func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("player_hp", PLAYER_HP)
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
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
		enemy.block = 0
	controller.get("deck").call("discard_hand")
	(controller.get("player") as Combatant).energy = 3
	await process_frame
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
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
