extends SceneTree

# Headless probe for the Underfoot, floor 2's required fight beside the
# Sputter: its Sting -> Rebury loop, Covered (takes 50% less) while the
# Sting is queued and Exposed (takes 50% more) while the Rebury is -
# starting Covered, and still alternating after a Denied or Stunned
# Sting; the Sting one unbreakable blow of 10 that Block and Brace
# soften; the Rebury nothing. Floor 2's required cluster is the Sputter
# and the Underfoot, no dragonfly, the island's Dragonfly x3 as they
# were. The Wanderer's stance on the dune's rise east of the crab stands
# on the drawn surface, and an escape leaves him there with no lift.
# The body: in the field Covered with its barb down; in the fight
# the barb raised exactly while the Sting is queued - its height on a
# 1080p screen printed - lifted and tilted Exposed after the Sting; after
# an escape reburied, barb down. The run log's state lines (queued_
# state): Covered then Exposed, each with what a Slash took off it. And
# the encounter's rule (FloorEnemy.excluded_intent): across many seeded
# turns the Sputter never has its Scissor queued while the Underfoot's
# Sting is, and still draws it on the other turns; in the fight the
# controller redraws a Scissor queued against a Sting and keeps one
# against a Rebury; and a move the player is shown never switches - the
# Sputter's redraw lands before its display shows again. The rules cases
# drive EnemyTurn on the real .tres; the field and fight cases load
# floor 2.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/underfoot_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 13
const UNDERFOOT_PATH := "res://battle/rules/enemies/underfoot.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const DRAGONFLY_PATH := "res://battle/rules/enemies/dragonfly.tres"
const COVERED_PATH := "res://battle/rules/statuses/covered.tres"
const EXPOSED_PATH := "res://battle/rules/statuses/exposed.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const STUNNED_PATH := "res://battle/rules/statuses/stunned.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const FLOOR_2_PATH := "res://floors/region1_floor2.tres"
const MODEL_PATH := "res://assets/models/enemies/Underfoot/Underfoot.glb"
const POSE_SCENE_PATH := "res://field/underfoot_pose.tscn"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
# Where the fight case logs its run, when run_probes.sh hands over no
# folder of this process's own (RunLogger.dir_override()).
const LOG_DIR := "user://underfoot_probe"
const FLOOR_2 := 1
const MAX_HP := 34
const STING := 10
const PLAYER_HP := 999
# The barb raised should stand at least this tall on a 1080p screen.
const BARB_MIN_PX := 40.0
# Nothing in the fight's line nearer anything else than this, metres.
const LINE_CLEARANCE_M := 0.4
const SAFETY_SECONDS := 300.0
# The rule's seeded runs: this many fights of this many turns.
const SEEDS := 40
const TURNS := 30
# The fight the display check plays out: this many enemy turns.
const VISIBLE_TURNS := 6

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
	_check_multipliers()
	_check_loop()
	_check_lost_sting()
	_check_sting_defence()
	_check_floor_data()
	_check_scissor_rule()
	await _check_field_body()
	await _check_fight_body()
	await _check_fight_line()
	await _check_escape()
	await _check_fight_scissor_rule()
	await _check_no_visible_switch()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("underfoot_probe: PASSED")
		quit(0)
	else:
		print("underfoot_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _underfoot()
	_expect_eq(data.enemy_name, "Underfoot", "The Underfoot")
	_expect_eq(data.max_hp, MAX_HP, "...34 HP")
	_expect(not data.erratic_intent_selection and data.intents.size() == 2, "...a fixed loop of two moves")
	_expect(not data.mechanic_summary.is_empty(), "...with its mechanic summary")
	if data.intents.size() == 2:
		var sting: EnemyIntent = data.intents[0]
		var rebury: EnemyIntent = data.intents[1]
		_expect(sting.intent_name == "Sting" and sting.type == EnemyIntent.IntentType.ATTACK and sting.value == STING and sting.hits == 1, "Sting first, one blow of 10")
		_expect(sting.interrupt_threshold == 0 and sting.on_interrupt == null, "...unbreakable: no threshold")
		_expect(sting.rear_while_queued, "...its barb raised while queued")
		_expect(sting.status_while_queued != null and sting.status_while_queued.resource_path == COVERED_PATH, "...Covered while queued")
		_expect(rebury.intent_name == "Rebury" and rebury.type == EnemyIntent.IntentType.SETTLE, "Rebury second, a SETTLE")
		_expect(rebury.status_while_queued != null and rebury.status_while_queued.resource_path == EXPOSED_PATH, "...Exposed while queued")
		_expect(not rebury.rear_while_queued, "...the barb down")
	var covered: StatusData = load(COVERED_PATH) as StatusData
	var exposed: StatusData = load(EXPOSED_PATH) as StatusData
	_expect_eq("%s: %s" % [covered.display_name, Status.new(covered).describe()], "Covered: It takes 50% less damage.", "Covered's readout line")
	_expect_eq("%s: %s" % [exposed.display_name, Status.new(exposed).describe()], "Exposed: It takes 50% more damage.", "Exposed's readout line")
	_expect_eq(data.model_scene_path, MODEL_PATH, "Its body the Underfoot glb")
	_expect(is_equal_approx(data.model_scale, 0.744) and is_equal_approx(data.model_yaw_offset_degrees, 180.0), "...at 0.744, turned 180")
	_expect_eq(data.attachment_scene_path, POSE_SCENE_PATH, "...UnderfootPose")
	_expect(data.sink_m > 0.0 and data.rest_height_m == 0.0, "...sunk, not buried")
	_expect(data.cluster_gap_m > 0.0, "...its own gap in the line")
	_completed += 1

# Covered: 7 -> 3, 10 -> 5; Exposed: 7 -> 11, 10 -> 15 - the enemy's
# incoming modifiers, as every card's damage meets them.
func _check_multipliers() -> void:
	var data: EnemyData = _underfoot()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var covered: Array[int] = [_taken(enemy, 7), _taken(enemy, 10)]
	_expect_eq(covered, [3, 5] as Array[int], "Covered: 7 and 10 land 3 and 5")
	EnemyTurn.take_turn(enemy, data, player)
	var exposed: Array[int] = [_taken(enemy, 7), _taken(enemy, 10)]
	_expect_eq(exposed, [11, 15] as Array[int], "Exposed: 7 and 10 land 11 and 15")
	_completed += 1

# Nothing played, twice round: Covered with the Sting queued - it lands
# 10 - then Exposed with the Rebury queued - nothing - and Covered again.
func _check_loop() -> void:
	var data: EnemyData = _underfoot()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var seen: Array[String] = []
	for turn in 4:
		var intent: EnemyIntent = EnemyTurn.current_intent(enemy, data)
		var state: String = _state(enemy)
		var before: int = player.hp
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		seen.append("%s %s %d%s" % [state, intent.intent_name.to_lower(), before - player.hp, "" if bool(result["attacked"]) else " (no attack)"])
	_expect_eq(seen, ["covered sting 10", "exposed rebury 0 (no attack)", "covered sting 10", "exposed rebury 0 (no attack)"] as Array[String], "Covered Sting 10 -> Exposed Rebury, looping")
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	EnemyTurn.take_turn(enemy, data, player)
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect(int(preview["type"]) == EnemyIntent.IntentType.SETTLE and int(preview["damage_to_hp"]) == 0, "The Rebury previews no damage")
	_completed += 1

# A Denied Sting and a Stunned one: nothing lands, and the loop still
# hands over - Exposed with the Rebury queued, then Covered again.
func _check_lost_sting() -> void:
	for path: String in [DENIED_PATH, STUNNED_PATH]:
		var data: EnemyData = _underfoot()
		var enemy: Combatant = _enemy(data)
		var player: Combatant = _player()
		Status.apply_to(enemy.statuses, load(path) as StatusData)
		var name: String = path.get_file().get_basename()
		var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
		_expect(bool(result["denied"]) and not bool(result["attacked"]) and player.hp == PLAYER_HP, "%s Sting: nothing lands" % name)
		_expect_eq("%s %s" % [_state(enemy), EnemyTurn.current_intent(enemy, data).intent_name], "exposed Rebury", "...Exposed, the Rebury queued")
		EnemyTurn.take_turn(enemy, data, player)
		_expect_eq("%s %s" % [_state(enemy), EnemyTurn.current_intent(enemy, data).intent_name], "covered Sting", "...then Covered, the Sting queued")
	_completed += 1

# 99 dealt on the Sting's turn: it lands all the same. Block 5 takes 5 of
# it; Braced halves it; both: 0.
func _check_sting_defence() -> void:
	var data: EnemyData = _underfoot()
	var lost: Array[int] = []
	for case in ["dealt", "block", "brace", "both"]:
		var enemy: Combatant = _enemy(data)
		var player: Combatant = _player()
		if case == "dealt":
			enemy.damage_taken_this_turn = 99
			_expect(not EnemyTurn.is_interrupted(enemy, EnemyTurn.current_intent(enemy, data)), "99 dealt: the Sting isn't broken")
		if case == "block" or case == "both":
			player.block = 5
		if case == "brace" or case == "both":
			Status.apply_to(enemy.statuses, load(BRACED_PATH) as StatusData)
		var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		lost.append(before - player.hp)
		_expect_eq(before - player.hp, int(preview["damage_to_hp"]), "%s: the Sting lands its preview" % case)
	_expect_eq(lost, [STING, 5, 5, 0] as Array[int], "The Sting: 10 through anything dealt, 5 through Block 5, 5 Braced, 0 both")
	_completed += 1

# --- Floor 2 ---

# The required cluster is the Sputter (anchor) and the Underfoot - no
# dragonfly in it; the island's three Dragonflies optional, as they were.
func _check_floor_data() -> void:
	var floor_data: Resource = load(FLOOR_2_PATH)
	var crab: Array[String] = []
	var island: int = 0
	for entry: Resource in floor_data.get("enemies"):
		var data: EnemyData = entry.get("enemy_data")
		if entry.get("group") == &"crab":
			crab.append("%s%s%s" % [data.resource_path.get_file().get_basename(), " anchor" if bool(entry.get("anchor")) else "", " required" if bool(entry.get("required")) else ""])
		elif entry.get("group") == &"island":
			if data.resource_path == DRAGONFLY_PATH and not bool(entry.get("required")):
				island += 1
	_expect_eq(crab, ["sputter anchor required", "underfoot required"] as Array[String], "Floor 2's required fight: the Sputter and the Underfoot")
	_expect_eq(island, 3, "...the island's Dragonfly x3 unchanged")
	_completed += 1

# Floor 2's rule, over SEEDS x TURNS seeded turns in the controller's
# order - the Sputter (the anchor, first in line) acts and redraws
# against nothing yet settled, then the Underfoot acts and the Sputter
# redraws against its newly queued move, as BattleController.
# _apply_intent_exclusions() runs them. Every turn the player faces: no
# Scissor beside a Sting; Scissors beside the Rebury still. Without the
# rule the two do meet - it is what keeps them apart.
func _check_scissor_rule() -> void:
	var floor_data: Resource = load(FLOOR_2_PATH)
	var rule: Array[String] = []
	for entry: Resource in floor_data.get("enemies"):
		var data: EnemyData = entry.get("enemy_data")
		if entry.get("group") == &"crab" and data.resource_path == SPUTTER_PATH:
			rule = [String(entry.get("excluded_intent")), String(entry.get("excluded_while_packmate_intent"))]
	_expect_eq(rule, ["Scissor", "Sting"] as Array[String], "Floor 2's Sputter: no Scissor while a Sting is queued")
	var with_rule: Array[int] = _scissor_turns(rule)
	_expect_eq(with_rule[0], 0, "Over %d seeded turns, Scissor never faces the player beside a Sting" % (SEEDS * TURNS))
	_expect(with_rule[1] > 0, "...and still does beside the Rebury (%d turns)" % with_rule[1])
	var without: Array[int] = _scissor_turns(["", ""] as Array[String])
	_expect(without[0] > 0, "Without the rule they meet (%d turns)" % without[0])
	_completed += 1

# [turns with Scissor beside a Sting, turns with Scissor beside a Rebury]
# over SEEDS x TURNS turns of the Sputter and the Underfoot, `rule` the
# Sputter's [excluded, trigger].
func _scissor_turns(rule: Array[String]) -> Array[int]:
	var sputter_data := load(SPUTTER_PATH) as EnemyData
	var underfoot_data: EnemyData = _underfoot()
	var counts: Array[int] = [0, 0]
	for run in SEEDS:
		seed(run)
		var sputter := Combatant.new(PLAYER_HP)
		var underfoot := Combatant.new(PLAYER_HP)
		EnemyTurn.pick_initial_intent(sputter, sputter_data)
		EnemyTurn.pick_initial_intent(underfoot, underfoot_data)
		var player: Combatant = _player()
		EnemyTurn.exclude_queued(sputter, sputter_data, rule[0], rule[1], [EnemyTurn.current_intent(underfoot, underfoot_data)] as Array[EnemyIntent])
		for turn in TURNS:
			if EnemyTurn.current_intent(sputter, sputter_data).intent_name == "Scissor":
				counts[0 if EnemyTurn.current_intent(underfoot, underfoot_data).intent_name == "Sting" else 1] += 1
			player.hp = PLAYER_HP
			player.block = 0
			EnemyTurn.take_turn(sputter, sputter_data, player)
			EnemyTurn.exclude_queued(sputter, sputter_data, rule[0], rule[1], [] as Array[EnemyIntent])
			EnemyTurn.take_turn(underfoot, underfoot_data, player)
			EnemyTurn.exclude_queued(sputter, sputter_data, rule[0], rule[1], [EnemyTurn.current_intent(underfoot, underfoot_data)] as Array[EnemyIntent])
	return counts

# In the field: Covered - sunk, the cover on - and the barb down.
func _check_field_body() -> void:
	_new_run()
	await _load_field()
	var underfoot: Node = _find(UNDERFOOT_PATH)
	var pose: Node = _pose(underfoot)
	_expect(pose != null, "The field's Underfoot wears UnderfootPose")
	if pose != null:
		_expect(is_zero_approx(float(pose.call("get_barb_raise"))), "In the field: the barb down")
		_expect(is_zero_approx(float(pose.call("get_exposed"))) and float(pose.call("get_cover")) > 0.5, "...Covered, the cover on")
		_expect(is_equal_approx(float(underfoot.get("sink")), _underfoot().sink_m), "...sunk to its sink_m")
		var tip: Vector3 = pose.call("get_barb_tip")
		var sand: float = (underfoot as Node3D).global_position.y
		print("Field: barb tip %.3f m off the sand" % (tip.y - sand))
		_expect(tip.y < sand + 0.02, "...the barb's tip at or under the sand (%.3f m)" % (tip.y - sand))
	await _teardown()
	_completed += 1

# The fight: the barb up once the frame settles, the Sting's turn; it
# lands, and the barb is down, the body Exposed - lifted, tilted toward
# the camera, the cover off; the Rebury, and it is Covered with the barb
# up again. The barb's height on a 1080p screen, raised. A Slash into it
# each turn, and the run log's state lines say Covered then Exposed, each
# with the HP that Slash took.
func _check_fight_body() -> void:
	var log_dir: String = _open_log()
	var controller: Node = await _start_fight()
	if controller != null:
		var underfoot: Node = _find(UNDERFOOT_PATH)
		var pose: Node = _pose(underfoot)
		var combatant: Combatant = _combatant(controller, underfoot)
		_expect(combatant != null and _state(combatant) == "covered", "The fight opens Covered")
		_expect(is_equal_approx(float(pose.call("get_barb_raise")), 1.0), "...the barb raised as the frame settles")
		_expect(_intent_text(controller, underfoot) == "10", "...the Sting telegraphed: 10")
		var px: float = _barb_px(underfoot, pose)
		print("Fight: the raised barb stands %.1f px tall at 1080p" % px)
		_expect(px >= BARB_MIN_PX, "...clearly above the sand line: %.1f px (at least %d)" % [px, int(BARB_MIN_PX)])
		var sink_covered: float = float(underfoot.get("sink"))
		var taken: Array[int] = [await _slash(controller, underfoot, combatant)]
		await _end_turn(controller)
		_expect_eq(_state(combatant), "exposed", "The Sting lands: Exposed")
		_expect(is_zero_approx(float(pose.call("get_barb_raise"))), "...the barb down")
		_expect(is_equal_approx(float(pose.call("get_exposed")), 1.0) and is_zero_approx(float(pose.call("get_cover"))), "...lifted and tilted, the cover off")
		_expect(float(underfoot.get("sink")) < sink_covered, "...clear of the sand (sink %.3f)" % float(underfoot.get("sink")))
		_expect_eq(_intent_text(controller, underfoot), "", "...the Rebury shows no number")
		_expect(_shows(controller, underfoot, "Exposed"), "...Exposed in its readout")
		taken.append(await _slash(controller, underfoot, combatant))
		await _end_turn(controller)
		_expect_eq(_state(combatant), "covered", "The Rebury: Covered again")
		_expect(is_zero_approx(float(pose.call("get_exposed"))) and is_equal_approx(float(underfoot.get("sink")), sink_covered), "...settled back, the cover on")
		_expect(is_equal_approx(float(pose.call("get_barb_raise")), 1.0), "...the barb raised for the next Sting")
		_expect(taken[0] > 0 and taken[0] < taken[1], "A Slash takes less Covered than Exposed: %d, %d" % [taken[0], taken[1]])
		var states: Array[String] = []
		for line: Dictionary in _state_lines(log_dir):
			states.append("%s %s %d" % [str(line.get("state")), str(line.get("intent")), int(line.get("taken", -1))])
		print("Run log: ", states)
		_expect_eq(states.slice(0, 2), ["covered Sting %d" % taken[0], "exposed Rebury %d" % taken[1]] as Array[String], "The run log: Covered then Exposed, each with the damage it took")
	RunLogger.set_output_dir("")
	await _teardown()
	_completed += 1

# The line: the Sputter heads it, the Underfoot behind it at its own gap,
# with at least 0.4 m between the Underfoot's nose and the Sputter's back.
# The Wanderer's stance - on the dune east of the crab - is on the drawn
# surface (Ground.get_walk_height_at()), not inside it.
func _check_fight_line() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var members: Array = controller.get("enemies")
		_expect(members.size() == 2, "The fight is two")
		if members.size() == 2:
			var sputter: Node3D = members[0]
			var underfoot: Node3D = members[1]
			_expect((sputter.get("enemy_data") as EnemyData).resource_path == SPUTTER_PATH and (underfoot.get("enemy_data") as EnemyData).resource_path == UNDERFOOT_PATH, "...the Sputter heads the line, the Underfoot behind")
			var apart: Vector3 = underfoot.global_position - sputter.global_position
			apart.y = 0.0
			_expect(absf(apart.length() - _underfoot().cluster_gap_m) < 0.05, "...%.2f m apart (its gap %.2f)" % [apart.length(), _underfoot().cluster_gap_m])
			var along: Vector3 = -apart.normalized()
			var sputter_back: float = _extent(sputter, -along)
			var underfoot_nose: float = _extent(underfoot, along)
			var gap: float = apart.length() - sputter_back - underfoot_nose
			print("Line: Sputter back %.3f m, Underfoot nose %.3f m, clear %.3f m" % [sputter_back, underfoot_nose, gap])
			_expect(gap >= LINE_CLEARANCE_M - 0.02, "...%.2f m clear between them" % gap)
		var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
		var drawn: float = _walk_height(wanderer.global_position) - float(wanderer.get("model_ground_offset"))
		print("Stance: (%.2f, %.2f) at y %.3f, the drawn surface %.3f" % [wanderer.global_position.x, wanderer.global_position.z, wanderer.global_position.y, drawn])
		_expect(absf(wanderer.global_position.y - drawn) < 0.01, "The Wanderer's stance on the drawn surface: %.3f m off it" % (wanderer.global_position.y - drawn))
	await _teardown()
	_completed += 1

# Escape on the Exposed turn: reburied - Covered, sunk, the barb down -
# and the Wanderer pushed clear onto the surface, no lift warning.
func _check_escape() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var underfoot: Node = _find(UNDERFOOT_PATH)
		var pose: Node = _pose(underfoot)
		var sink_covered: float = float(underfoot.get("sink"))
		await _end_turn(controller)
		_expect(is_equal_approx(float(pose.call("get_exposed")), 1.0), "Exposed before the escape")
		_overlay().call("_finish_battle", 2) # ESCAPE
		await create_timer(1.5).timeout
		_expect(is_zero_approx(float(pose.call("get_exposed"))) and float(pose.call("get_cover")) > 0.5, "After the escape: Covered, the cover on")
		_expect(is_equal_approx(float(underfoot.get("sink")), sink_covered), "...sunk again")
		_expect(is_zero_approx(float(pose.call("get_barb_raise"))), "...the barb down")
		var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
		_expect(not bool(wanderer.get("_ground_hold_warned")), "...the Wanderer clear of it on the surface - no lift warning")
		_expect(absf(wanderer.global_position.y - (_walk_height(wanderer.global_position) - float(wanderer.get("model_ground_offset")))) < 0.03, "...standing on it")
	await _teardown()
	_completed += 1

# --- Helpers ---

# The rule in the fight: the Sputter carries it from the floor
# (FieldEnemy), and BattleController redraws its Scissor - set queued by
# hand, past its first turn - against the Underfoot's queued Sting, and
# leaves one queued against the Rebury.
func _check_fight_scissor_rule() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var sputter: Node = _find(SPUTTER_PATH)
		var underfoot: Node = _find(UNDERFOOT_PATH)
		_expect(sputter.get("excluded_intent") == "Scissor" and sputter.get("excluded_while_packmate_intent") == "Sting", "The Sputter's body carries the floor's rule")
		var sputter_data: EnemyData = sputter.get("enemy_data")
		var scissor: int = -1
		var strike: int = -1
		for i in sputter_data.intents.size():
			if sputter_data.intents[i].intent_name == "Scissor":
				scissor = i
			elif sputter_data.intents[i].intent_name == "Strike":
				strike = i
		var sputter_combatant: Combatant = _combatant(controller, sputter)
		var underfoot_combatant: Combatant = _combatant(controller, underfoot)
		var underfoot_data: EnemyData = underfoot.get("enemy_data")
		for queued in ["Sting", "Rebury"]:
			for i in underfoot_data.intents.size():
				if underfoot_data.intents[i].intent_name == queued:
					underfoot_combatant.current_intent_index = i
			sputter_combatant.turns_taken = 1
			sputter_combatant.previous_intent_index = strike
			sputter_combatant.current_intent_index = scissor
			controller.call("_apply_intent_exclusions", controller.get("enemies"))
			var now: String = EnemyTurn.current_intent(sputter_combatant, sputter_data).intent_name
			if queued == "Sting":
				_expect(now != "Scissor", "A Scissor queued against the Sting is drawn again (%s)" % now)
				_expect(_intent_text(controller, sputter) != str(sputter_data.intents[scissor].value), "...and the readout shows the new move (%s)" % _intent_text(controller, sputter))
			else:
				_expect_eq(now, "Scissor", "A Scissor queued against the Rebury stays")
	await _teardown()
	_completed += 1

# A fight of VISIBLE_TURNS enemy turns with the Sputter all but certain
# to draw Scissor (its Strike and Block weighted to almost nothing, on a
# copy of its data), so the redraw against the Sting comes round: every
# frame, no shown display's move (its type and number) changes from the
# frame before while it stays shown. The redraws did happen (the
# Sputter's intent changed twice in one enemy turn), and the Scissor
# still showed beside the Rebury.
func _check_no_visible_switch() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var sputter: Node = _find(SPUTTER_PATH)
		var underfoot: Node = _find(UNDERFOOT_PATH)
		var biased: EnemyData = (sputter.get("enemy_data") as EnemyData).duplicate(true)
		for intent in biased.intents:
			if intent.intent_name != "Scissor":
				intent.erratic_weight = 0.001
		sputter.set("enemy_data", biased)
		var displays: Dictionary = controller.get_parent().get("_enemy_intents")
		var last: Dictionary = {}
		var switches: Array[String] = []
		var watch := func() -> void:
			for member: Node in displays.keys():
				var display: Control = displays[member]
				if not is_instance_valid(display):
					continue
				var label: Label = display.get("_label")
				var key: String = "%d %s" % [int(display.get("_type")), label.text if label != null else ""]
				if display.visible and last.get(member, "") != "" and last[member] != key:
					switches.append("%s: %s -> %s" % [(member.get("enemy_data") as EnemyData).enemy_name, last[member], key])
				last[member] = key if display.visible else ""
		process_frame.connect(watch)
		var redraws: int = 0
		var scissor_by_rebury: int = 0
		var changes: Array[int] = [0]
		var count := func(member: Node, _preview: Dictionary) -> void:
			if member == sputter:
				changes[0] += 1
		controller.connect("enemy_intent_changed", count)
		for turn in VISIBLE_TURNS:
			changes[0] = 0
			await controller.call("end_turn")
			for i in 600:
				if not bool(controller.get("_input_locked")):
					break
				await process_frame
			await create_timer(0.5).timeout
			if changes[0] >= 2:
				redraws += 1
			var sputter_now: EnemyIntent = EnemyTurn.current_intent(_combatant(controller, sputter), biased)
			var underfoot_now: EnemyIntent = EnemyTurn.current_intent(_combatant(controller, underfoot), underfoot.get("enemy_data"))
			_expect(not (sputter_now.intent_name == "Scissor" and underfoot_now.intent_name == "Sting"), "Turn %d: no Scissor beside the Sting" % (turn + 2))
			if sputter_now.intent_name == "Scissor" and underfoot_now.intent_name == "Rebury":
				scissor_by_rebury += 1
		process_frame.disconnect(watch)
		controller.disconnect("enemy_intent_changed", count)
		_expect(switches.is_empty(), "No shown move ever switched (%s)" % ", ".join(switches))
		_expect(redraws > 0, "...across %d redraw(s) in %d enemy turns" % [redraws, VISIBLE_TURNS])
		_expect(scissor_by_rebury > 0, "...and the Scissor still shown beside the Rebury (%d turns)" % scissor_by_rebury)
	await _teardown()
	_completed += 1

func _underfoot() -> EnemyData:
	return load(UNDERFOOT_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _player() -> Combatant:
	var player := Combatant.new(PLAYER_HP)
	player.hp = PLAYER_HP
	return player

func _taken(enemy: Combatant, amount: int) -> int:
	return Status.apply_modifiers(amount, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE)

# "covered", "exposed", both or neither, from the statuses it holds.
func _state(enemy: Combatant) -> String:
	var held: Array[String] = []
	for active: Status in enemy.statuses:
		if active.data.resource_path == COVERED_PATH:
			held.append("covered")
		elif active.data.resource_path == EXPOSED_PATH:
			held.append("exposed")
	return "+".join(held) if not held.is_empty() else "neither"

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(SLASH_PATH) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_2)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)

func _load_field() -> void:
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

# A new run on floor 2 and the crab's fight started at the Underfoot,
# waited through the camera's swing until the frame settles. The
# controller, or null (a FAIL is recorded).
func _start_fight() -> Node:
	_new_run()
	await _load_field()
	var target: Node3D = _find(UNDERFOOT_PATH) as Node3D
	if target == null:
		_fail("no Underfoot on floor 2")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(-1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	if _overlay() == null:
		_fail("no fight started on floor 2")
		return null
	await create_timer(3.0).timeout
	return _overlay().get("battle_controller")

func _find(path: String) -> Node:
	for node in get_nodes_in_group("enemies"):
		var data: EnemyData = node.get("enemy_data")
		if data != null and data.resource_path == path:
			return node
	return null

func _pose(enemy: Node) -> Node:
	if enemy == null:
		return null
	var poses: Array[Node] = enemy.find_children("*", "UnderfootPose", true, false)
	return poses[0] if poses.size() == 1 else null

func _overlay() -> Node:
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

# A Slash from the hand into `member`, Energy enough; the HP it took.
func _slash(controller: Node, member: Node, combatant: Combatant) -> int:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return 0
	var before: int = combatant.hp
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")):
		controller.call("confirm_target", member)
	for i in 120:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.6).timeout
	return before - combatant.hp

# The run log into this process's folder - run_probes.sh's, else
# LOG_DIR - cleared first, so the next run's file is the only one.
func _open_log() -> String:
	var dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	RunLogger.set_output_dir(dir)
	RunLogger.enabled = true
	return dir

# Every queued_state mechanic line in the folder's run logs, in order.
func _state_lines(dir: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for file_name in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".jsonl"):
			continue
		for raw in FileAccess.get_file_as_string(dir.path_join(file_name)).split("\n", false):
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary and str((parsed as Dictionary).get("ev")) == "mechanic" and str((parsed as Dictionary).get("kind")) == "queued_state":
				found.append(parsed as Dictionary)
	if found.is_empty():
		_fail("no queued_state line in the run log at %s" % ProjectSettings.globalize_path(dir))
	return found

func _end_turn(controller: Node) -> void:
	await controller.call("end_turn")
	await create_timer(1.0).timeout

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _intent_text(controller: Node, member: Node) -> String:
	var intents: Dictionary = controller.get_parent().get("_enemy_intents")
	var intent: Node = intents.get(member)
	var label: Label = intent.get("_label") if intent != null else null
	return label.text if label != null else "<none>"

func _shows(controller: Node, member: Node, prefix: String) -> bool:
	for text: String in controller.call("get_enemy_status_labels", member):
		if text.begins_with(prefix):
			return true
	return false

# The raised barb's height on screen, scaled to 1080 rows: its tip and
# the sand under it, unprojected through the battle camera.
func _barb_px(underfoot: Node, pose: Node) -> float:
	var camera: Camera3D = root.get_viewport().get_camera_3d()
	if camera == null:
		_fail("no camera to measure the barb with")
		return 0.0
	var tip: Vector3 = pose.call("get_barb_tip")
	var sand := Vector3(tip.x, (underfoot as Node3D).global_position.y, tip.z)
	var rows: float = root.get_viewport().get_visible_rect().size.y
	return absf(camera.unproject_position(sand).y - camera.unproject_position(tip).y) * 1080.0 / maxf(rows, 1.0)

# The drawn surface at a world point's XZ (Ground.get_walk_height_at(),
# in Ground's own frame).
func _walk_height(world: Vector3) -> float:
	var ground: Node3D = _field.get_node("Ground") as Node3D
	var local: Vector3 = ground.to_local(Vector3(world.x, 0.0, world.z))
	return float(ground.call("get_walk_height_at", Vector2(local.x, local.z)))

# How far `body`'s model reaches from its origin along `direction`
# (horizontal), metres - the most of its mesh AABB corners.
func _extent(body: Node3D, direction: Vector3) -> float:
	var reach: float = 0.0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.get_aabb()
		for corner in 8:
			var world: Vector3 = mi.global_transform * box.get_endpoint(corner)
			var offset: Vector3 = world - body.global_position
			offset.y = 0.0
			reach = maxf(reach, offset.dot(direction))
	return reach

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
