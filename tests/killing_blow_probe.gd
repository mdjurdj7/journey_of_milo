extends SceneTree

# Headless probe for killing blows and the death after them: a killing
# hit shows in full - its damage number, its hit-stop (at least
# kill_hitstop_min, a 9-damage Blood Arc's too) and its recoil - before
# the death begins (BattleController.enemy_defeated); Blood Arc killing a
# whole pack reacts on every one of them, and runs its stroke out, before
# any dies; the death plays (FieldEnemy.death_finished) and only then is
# the fight won; a non-final kill hands input back once its blow has
# shown, the death still running; and a click skips a running death to
# its end, but never the blow before it. Real cards through
# BattleController.request_play(), on floor 1's lone crab and floor 2's
# island pack.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/killing_blow_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 4
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const PLAYER_HP := 999
# Floor 1's lone crab (ungrouped), floor 2's island pack.
const FLOOR_1 := 0
const FLOOR_2 := 1
const ISLAND := &"island"
# Slack for frame timing, in milliseconds.
const SLACK_MS := 20
# How long a case may watch for its fight to be won.
const WATCH_SECONDS := 8.0
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
	await _check_single_kill()
	await _check_blood_arc_pack()
	await _check_non_final_unlock()
	await _check_skip()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("killing_blow_probe: PASSED")
		quit(0)
	else:
		print("killing_blow_probe: %d FAILED" % _failures)
		quit(1)

# A Slash (6 - under the heavy tier) kills floor 1's crab: its number, a
# hit-stop of at least kill_hitstop_min and its recoil all show before the
# death begins; the death plays out; then, and only then, the win.
func _check_single_kill() -> void:
	var controller: Node = await _start_fight(FLOOR_1, &"", SLASH_PATH)
	if controller != null:
		var crab: Node3D = (controller.get("enemies") as Array)[0]
		_combatant(controller, crab).set("hp", 5)
		var log: Dictionary = _watch_setup(controller, [crab])
		_play_first(controller, crab)
		await _watch(controller, log)
		var hit: int = _first(log, "hit")
		var defeated: int = _first(log, "defeated")
		_expect(hit > 0 and defeated > 0, "The Slash hits and kills the crab (hit %d, death %d)" % [hit, defeated])
		if hit > 0 and defeated > 0:
			_expect(_first(log, "number") > 0 and _first(log, "number") <= defeated, "...its damage number shows before the death begins")
			_expect(_recoiled_before(log, crab, defeated), "...and its recoil")
			var stop_ms: int = _stop_ms_before(log, defeated)
			var minimum: int = int(log["kill_min_ms"])
			_expect(stop_ms >= minimum - SLACK_MS, "...and a hit-stop of at least kill_hitstop_min (%d ms, got %d)" % [minimum, stop_ms])
			_expect(defeated - hit >= 300, "...the death waits for the blow (%d ms after the hit)" % (defeated - hit))
		_check_win_after_deaths(log, "The crab")
	await _teardown()
	_completed += 1

# Blood Arc (9 to each) kills the whole island pack: every member's
# number, recoil and the 9-damage kill's minimum hit-stop before any
# death; the stroke runs out first; the win after the last death.
func _check_blood_arc_pack() -> void:
	var controller: Node = await _start_fight(FLOOR_2, ISLAND, BLOOD_ARC_PATH)
	if controller != null:
		var members: Array = (controller.get("enemies") as Array).duplicate()
		_expect(members.size() >= 2, "Floor 2's island pack is a fight of several (%d)" % members.size())
		for member in members:
			_combatant(controller, member).set("hp", 5)
		var log: Dictionary = _watch_setup(controller, members)
		_play_first(controller, null)
		await _watch(controller, log)
		var first_death: int = _first(log, "defeated")
		_expect(first_death > 0, "Blood Arc kills the pack")
		if first_death > 0:
			_expect_eq((log["defeated_by"] as Dictionary).size(), members.size(), "...every member dies")
			for member in members:
				var number_at: int = int((log["number_by"] as Dictionary).get(member, 0))
				_expect(number_at > 0 and number_at <= first_death, "...'%s' shows its number before any death" % (log["names"] as Dictionary).get(member, "?"))
				_expect(_recoiled_before(log, member, first_death), "...'%s' recoils before any death" % (log["names"] as Dictionary).get(member, "?"))
			var stop_ms: int = _stop_ms_before(log, first_death)
			var minimum: int = int(log["kill_min_ms"])
			_expect(stop_ms >= minimum - SLACK_MS, "...a 9-damage kill holds at least kill_hitstop_min (%d ms, got %d)" % [minimum, stop_ms])
			var stroke_ms: int = int(log.get("stroke_ms", 0))
			_expect(first_death - _first(log, "hit") >= stroke_ms - SLACK_MS, "...and the stroke runs out first (%d ms, deaths at %d)" % [stroke_ms, first_death - _first(log, "hit")])
		_check_win_after_deaths(log, "The pack")
	await _teardown()
	_completed += 1

# One of the pack killed by a Slash: once its blow has shown, input is
# back while its death is still running, and the fight goes on.
func _check_non_final_unlock() -> void:
	var controller: Node = await _start_fight(FLOOR_2, ISLAND, SLASH_PATH)
	if controller != null:
		var members: Array = (controller.get("enemies") as Array).duplicate()
		var target: Node3D = members[0]
		_combatant(controller, target).set("hp", 5)
		var dying_unlocked: Array[bool] = [false]
		var finished: Array[bool] = [false]
		target.connect("death_finished", func() -> void: finished[0] = true)
		_play_first(controller, target)
		var start: int = Time.get_ticks_msec()
		while not finished[0] and Time.get_ticks_msec() - start < int(WATCH_SECONDS * 1000.0):
			await process_frame
			if not finished[0] and bool(target.call("is_dying")) and not bool(controller.get("_input_locked")):
				dying_unlocked[0] = true
		_expect(dying_unlocked[0], "A non-final kill: input is back while its death is still running")
		_expect(finished[0], "...and the death plays out")
		_expect_eq((controller.get("enemies") as Array).size(), members.size() - 1, "...the fight going on without it")
		_expect(bool(_field.get("_battle_open")), "...still open")
	await _teardown()
	_completed += 1

# A click during the blow cuts nothing; a click during the death skips it
# to its end, and the win follows at once.
func _check_skip() -> void:
	var controller: Node = await _start_fight(FLOOR_1, &"", SLASH_PATH)
	if controller != null:
		var crab: Node3D = (controller.get("enemies") as Array)[0]
		_combatant(controller, crab).set("hp", 5)
		var log: Dictionary = _watch_setup(controller, [crab])
		_play_first(controller, crab)
		# Clicked while the blow is still showing.
		var start: int = Time.get_ticks_msec()
		while _first(log, "hit") == 0 and Time.get_ticks_msec() - start < 3000:
			await process_frame
		for i in 3:
			await process_frame
		_click()
		while _first(log, "defeated") == 0 and Time.get_ticks_msec() - start < 5000:
			await process_frame
			_record_frame(log)
		var hit: int = _first(log, "hit")
		var defeated: int = _first(log, "defeated")
		_expect(defeated > 0 and defeated - hit >= 300, "A click during the blow: the death still waits for it (%d ms)" % (defeated - hit))
		_expect(_first(log, "number") > 0, "...its number still shows")
		# Clicked once the death runs.
		for i in 3:
			await process_frame
		var clicked: int = Time.get_ticks_msec()
		_click()
		await _watch(controller, log)
		var won: int = int(log.get("won", 0))
		var fade_ms: int = int(float(crab.get("death_fade_time")) * 1000.0) if is_instance_valid(crab) else 800
		_expect(won > 0, "A click during the death: the fight is won")
		if won > 0:
			_expect(won - clicked < fade_ms / 2, "...at once, the death skipped to its end (%d ms after the click)" % (won - clicked))
	await _teardown()
	_completed += 1

# --- Watching ---

# What a case records, keyed by event: the first time each happened (real
# ms), per enemy where it matters, the time scale's stops, recoil.
func _watch_setup(controller: Node, members: Array) -> Dictionary:
	var log: Dictionary = {"hit": 0, "number": 0, "defeated": 0, "won": 0, "number_by": {}, "defeated_by": {}, "finished_by": {}, "stops": [], "stop_from": 0, "rest": {}, "moved": {}, "numbers_seen": 0, "stroke_ms": 0, "names": {}, "kill_min_ms": 0}
	for member in members:
		(log["rest"] as Dictionary)[member] = (member as Node3D).global_position
		(log["names"] as Dictionary)[member] = str(member.name)
	# Read now: the fight, and the feedback with it, is gone by the checks.
	var feedback_now: Node = _feedback(controller)
	if feedback_now != null:
		log["kill_min_ms"] = int(float(feedback_now.get("kill_hitstop_min")) * 1000.0)
	controller.connect("damage_dealt", func(source: Variant, target: Variant, _amount: int, _kind: String) -> void:
		if source is String and target is Node and log["hit"] == 0:
			log["hit"] = Time.get_ticks_msec()
			var feedback: Node = _feedback(controller)
			if feedback != null:
				log["stroke_ms"] = int(float(feedback.call("effect_remaining_time")) * 1000.0)
	)
	controller.connect("enemy_defeated", func(enemy: Node) -> void:
		var now: int = Time.get_ticks_msec()
		if log["defeated"] == 0:
			log["defeated"] = now
		(log["defeated_by"] as Dictionary)[enemy] = now
		enemy.connect("death_finished", func() -> void: (log["finished_by"] as Dictionary)[enemy] = Time.get_ticks_msec())
	)
	controller.connect("battle_won", func() -> void: log["won"] = Time.get_ticks_msec())
	return log

# Frame by frame until the fight is won, or WATCH_SECONDS.
func _watch(_controller: Node, log: Dictionary) -> void:
	var start: int = Time.get_ticks_msec()
	while int(log["won"]) == 0 and Time.get_ticks_msec() - start < int(WATCH_SECONDS * 1000.0):
		await process_frame
		_record_frame(log)
	if int(log["stop_from"]) != 0:
		(log["stops"] as Array).append([int(log["stop_from"]), Time.get_ticks_msec()])
		log["stop_from"] = 0

# One frame's look: new damage numbers (whose target is the nearest
# member on screen - by order here: one card's numbers land in its
# targets' order), the time scale, and how far each member stands from
# its rest.
func _record_frame(log: Dictionary) -> void:
	var now: int = Time.get_ticks_msec()
	var numbers: int = _numbers_now()
	if numbers > int(log["numbers_seen"]):
		if int(log["number"]) == 0:
			log["number"] = now
		for member in (log["rest"] as Dictionary).keys():
			if not (log["number_by"] as Dictionary).has(member):
				(log["number_by"] as Dictionary)[member] = now
				numbers -= 1
				if numbers <= int(log["numbers_seen"]):
					break
	log["numbers_seen"] = maxi(int(log["numbers_seen"]), _numbers_now())
	if Engine.time_scale < 1.0 and int(log["stop_from"]) == 0:
		log["stop_from"] = now
	elif Engine.time_scale >= 1.0 and int(log["stop_from"]) != 0:
		(log["stops"] as Array).append([int(log["stop_from"]), now])
		log["stop_from"] = 0
	# The recoil: a push along the ground, away from the Wanderer - read
	# flat, after the hit, from where it stood at the hit (a hovering body
	# bobs up and down the whole time).
	for member in (log["rest"] as Dictionary).keys():
		if not is_instance_valid(member) or (log["moved"] as Dictionary).has(member):
			continue
		var at: Vector3 = (member as Node3D).global_position
		if int(log["hit"]) == 0:
			(log["rest"] as Dictionary)[member] = at
			continue
		var rest: Vector3 = (log["rest"] as Dictionary)[member]
		if Vector2(at.x - rest.x, at.z - rest.z).length() > 0.01:
			(log["moved"] as Dictionary)[member] = now

func _first(log: Dictionary, key: String) -> int:
	return int(log.get(key, 0))

func _recoiled_before(log: Dictionary, member: Variant, at: int) -> bool:
	var moved: int = int((log["moved"] as Dictionary).get(member, 0))
	return moved > 0 and moved <= at

# How long the world held, in all, before `at`.
func _stop_ms_before(log: Dictionary, at: int) -> int:
	var total: int = 0
	for span: Array in log["stops"]:
		if int(span[0]) < at:
			total += mini(int(span[1]), at) - int(span[0])
	return total

# Every death begun has finished, and only then the win.
func _check_win_after_deaths(log: Dictionary, label: String) -> void:
	var won: int = int(log["won"])
	_expect(won > 0, "%s: the fight is won" % label)
	var last_finished: int = 0
	for at in (log["finished_by"] as Dictionary).values():
		last_finished = maxi(last_finished, int(at))
	_expect_eq((log["finished_by"] as Dictionary).size(), (log["defeated_by"] as Dictionary).size(), "%s: every death begun plays out" % label)
	if won > 0 and last_finished > 0:
		_expect(won >= last_finished, "%s: the win comes after the last death (%d ms after)" % [label, won - last_finished])
		var fade_ms: int = 800
		_expect(last_finished - int(log["defeated"]) >= fade_ms - 100, "%s: the death runs its fade (%d ms)" % [label, last_finished - int(log["defeated"])])

func _numbers_now() -> int:
	var layer: Node = _field.get_node_or_null("BattleLayer")
	if layer == null or layer.get_child_count() == 0:
		return 0
	var count: int = 0
	for child in layer.get_child(0).get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with("floating_number.gd"):
			count += 1
	return count

# A left click, pressed, through the viewport's input.
func _click() -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(4, 4)
	root.push_input(press)

# --- Fights ---

# A new run on `floor_index`, a deck of `card_path` alone, the fight
# started on the pack `group` (&"" = the floor's first ungrouped enemy).
# The controller, or null (a FAIL is recorded).
func _start_fight(floor_index: int, group: StringName, card_path: String) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if node.get("group") == group:
			target = node as Node3D
			break
	if target == null:
		_fail("no enemy of group '%s' on floor %d" % [group, floor_index + 1])
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	await create_timer(2.5).timeout
	return overlay.get("battle_controller")

# The first card in hand, at `target` (or none, for a card that takes
# none), Energy topped up first. Not waited on - the case watches.
func _play_first(controller: Node, target: Variant) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")) and target != null:
		controller.call("confirm_target", target)

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _feedback(controller: Node) -> Node:
	return controller.get_parent().get("_battle_feedback")

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	Engine.time_scale = 1.0
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
