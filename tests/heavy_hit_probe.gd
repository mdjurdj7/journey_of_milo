extends SceneTree

# Headless probe for the heavy-hit tier (BattleFeedback's heavy tier): a
# 30-damage card hit is in it and a 5 isn't; the hit-stop runs 40 ms at
# heavy_min_damage to 140 at heavy_max_damage and never past 160; the
# impact layer is silent at the light end and heavy_impact_max_volume_db
# at the full one, and deals its two takes in turn; a Toll blow
# (Reckoning) counts as at least heavy_min_damage. And presentation only:
# a real Reckoning on 30 Toll, played through BattleController with the
# tier on and again with it off, leaves the fight in the same state -
# with the tier on it held the world (Engine.time_scale) and sounded the
# layer, off it did neither, and either way the world is back at full
# speed after.
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

# 30 in the tier, 5 not; the stop and the layer at either end and the
# cap; the recoil and number multipliers; the tier off.
func _check_tier() -> void:
	var feedback: Node = _feedback()
	var level_30: float = feedback.call("heavy_level", 30)
	var level_5: float = feedback.call("heavy_level", 5)
	_expect(level_30 >= 0.0 and float(feedback.call("hitstop_ms", level_30)) > 0.0, "A 30-damage hit is heavy (level %.2f, stop %.0f ms)" % [level_30, float(feedback.call("hitstop_ms", level_30))])
	_expect(level_5 < 0.0 and is_zero_approx(float(feedback.call("hitstop_ms", level_5))), "A 5-damage hit isn't")
	_expect_eq(roundi(float(feedback.call("hitstop_ms", feedback.call("heavy_level", 10)))), 40, "At 10 the stop is 40 ms")
	_expect_eq(roundi(float(feedback.call("hitstop_ms", feedback.call("heavy_level", 35)))), 140, "At 35, 140 ms")
	_expect_eq(roundi(float(feedback.call("hitstop_ms", feedback.call("heavy_level", 90)))), 140, "...and held past it")
	_expect(float(feedback.call("heavy_impact_volume_db", feedback.call("heavy_level", 10))) <= -80.0, "The layer is silent at 10")
	_expect(is_equal_approx(float(feedback.call("heavy_impact_volume_db", feedback.call("heavy_level", 35))), -14.0), "...and -14 dB at 35")
	_expect(is_equal_approx(float(feedback.call("recoil_multiplier", level_5)), 1.0) and is_equal_approx(float(feedback.call("recoil_multiplier", 1.0)), 1.6), "Recoil x1 below the tier, x1.6 at its top")
	_expect(is_equal_approx(float(feedback.call("number_multiplier", level_5)), 1.0) and is_equal_approx(float(feedback.call("number_multiplier", 1.0)), 1.4), "The number x1 below the tier, x1.4 at its top")
	feedback.set("hitstop_max_ms", 500.0)
	_expect_eq(roundi(float(feedback.call("hitstop_ms", 1.0))), 160, "Never a stop past 160 ms")
	feedback.set("heavy_hit_enabled", false)
	_expect(float(feedback.call("heavy_level", 30)) < 0.0, "The tier off: 30 is an ordinary hit")
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

# The same Reckoning on 30 Toll, tier on and tier off: the same enemy HP,
# Toll, HP and Energy after. On: the world held and the layer sounded;
# off: neither. Full speed after both.
func _check_rules_unchanged() -> void:
	var on: Dictionary = await _reckoning_fight(true)
	var off: Dictionary = await _reckoning_fight(false)
	_expect_eq(on.get("state"), off.get("state"), "Reckoning's outcome is the same with the tier on and off")
	_expect(int((on.get("state", [0]) as Array)[0]) == ENEMY_HP - TOLL, "...30 dealt (%s)" % str(on.get("state")))
	_expect(float(on.get("slowest", 1.0)) < 1.0, "On: the world held (time_scale %.2f)" % float(on.get("slowest", 1.0)))
	_expect(bool(on.get("layer", false)), "...and the impact layer sounded")
	_expect(is_equal_approx(float(off.get("slowest", 0.0)), 1.0), "Off: no hold")
	_expect(not bool(off.get("layer", true)), "...and no layer")
	_expect(is_equal_approx(Engine.time_scale, 1.0), "Full speed after")
	_completed += 1

# One fight: Reckoning on TOLL at the first enemy, the tier `enabled`.
# Returns {state: [enemy HP, Toll, HP, Energy], slowest: the lowest
# time_scale seen while it resolved, layer: whether HeavyImpactAudio
# played a take}.
func _reckoning_fight(enabled: bool) -> Dictionary:
	var out: Dictionary = {}
	var controller: Node = await _start_fight()
	if controller != null:
		var feedback: Node = controller.get_parent().get("_battle_feedback")
		feedback.set("heavy_hit_enabled", enabled)
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
		if view == null:
			_fail("Reckoning is not in the hand")
		else:
			controller.call("request_play", view)
			controller.call("confirm_target", enemy)
			for i in 900:
				await process_frame
				slowest = minf(slowest, Engine.time_scale)
				if not bool(controller.get("_input_locked")) and is_equal_approx(Engine.time_scale, 1.0):
					break
		var layer: Node = enemy.get_node_or_null("HeavyImpactAudio")
		var combatant: Combatant = (controller.get("_combatants") as Dictionary).values()[0]
		out = {
			"state": [combatant.hp, player.toll, player.hp, player.energy],
			"slowest": slowest,
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
