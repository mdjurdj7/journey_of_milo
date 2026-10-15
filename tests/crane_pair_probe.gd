extends SceneTree

# Headless probe for floor 3's required pair, the crowned cranes
# Strawcrown and Chalkcrown: as authored (32 HP each, the shared loop Bow
# 4 Block, Step 6, Leap 10, every step simultaneous and named for its
# move; Paired from the start, which turns Bereft - twice each turn, its
# line said - when the other falls); where floor 3 stands them (in the
# stream at the top of its pool, the gate line still at x 23.3, the worn
# band through the anchor); and the fight: one contact for both, Paired
# and on the same Bow; one killed first and the other Bereft at once,
# its Step 6x2 landing 12 and its Bow 8 Block; both killed by one Carve
# and neither turning - their line said and Leg Band offered after. And
# the fight's staging from the hub side: the Wanderer at least his
# minimum spacing from the anchor (he may stand in the ford's shallows),
# and no one standing on a face.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/crane_pair_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Fights load the real floor 3 scene and drive BattleController's own
# end_turn() and request_play(), as blackback_probe does. Untyped against
# anything that names the RunState autoload.

const CASES := 8
# A combatant stands on a face when the ground under its feet slopes past
# FACE_SLOPE_MAX_DEG (read over half a metre) or rises or falls more than
# FACE_JUMP_MAX_M within half a metre - a ridge's inner face (43 degrees,
# 0.48 m) fails both, a ford or a bank's foot (under 25, 0.25) neither.
const FACE_SLOPE_MAX_DEG := 30.0
const FACE_JUMP_MAX_M := 0.35
# Where he comes from for the staging case: from the hub, south-west.
const HUB_SIDE := Vector3(-0.6, 0.0, 0.8)
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FLOOR_3_PATH := "res://floors/region1_floor3.tres"
const STRAWCROWN_PATH := "res://battle/rules/enemies/strawcrown.tres"
const CHALKCROWN_PATH := "res://battle/rules/enemies/chalkcrown.tres"
const PAIRED_PATH := "res://battle/rules/statuses/paired.tres"
const BEREFT_PATH := "res://battle/rules/statuses/bereft.tres"
const LEG_BAND_PATH := "res://run/keepsakes/leg_band.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const STORK_AUDIO := "res://assets/audio/enemies/Stork/"
const ANCHOR := Vector2(8.67, -33.4)
const GATE_X := 23.3
const FLOOR_3 := 2
const PLAYER_HP := 999
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
	_check_floor_3()
	await _check_standing()
	await _check_fight_opens()
	await _check_one_falls_first()
	await _check_bereft_bow()
	await _check_felled_together()
	await _check_staging()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("crane_pair_probe: PASSED")
		quit(0)
	else:
		print("crane_pair_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var paired := load(PAIRED_PATH) as StatusData
	var bereft := load(BEREFT_PATH) as StatusData
	for path: String in [STRAWCROWN_PATH, CHALKCROWN_PATH]:
		var data := load(path) as EnemyData
		var label: String = data.enemy_name
		_expect_eq(data.max_hp, 32, "%s: 32 HP" % label)
		_expect(not data.erratic_intent_selection, "%s: a fixed loop" % label)
		var seen: Array = []
		for intent in data.intents:
			seen.append([intent.intent_name, intent.type, intent.value, intent.simultaneous, intent.motion])
		_expect_eq(seen, [["Bow", EnemyIntent.IntentType.DEFEND, 4, true, &"bow"], ["Step", EnemyIntent.IntentType.ATTACK, 6, true, &"step"], ["Leap", EnemyIntent.IntentType.ATTACK, 10, true, &"leap"]], "%s: Bow 4 Block, Step 6, Leap 10, all together, each its move" % label)
		_expect(data.starting_statuses.size() == 1 and data.starting_statuses[0] == paired, "%s: Paired from the start" % label)
		var takes: Array[String] = []
		for take in data.contact_sounds:
			takes.append(take.resource_path if take != null else "<none>")
		_expect_eq(takes, [STORK_AUDIO + "hit_1.mp3", STORK_AUDIO + "hit_2.mp3"] as Array[String], "%s: the Stork's hits as its contact sound" % label)
		_expect_eq(data.attachment_scene_path, "res://field/crane_motion.tscn", "%s: moves by CraneMotion" % label)
		_expect(data.painted_albedo_path.ends_with("/crane_0.jpg") and ResourceLoader.exists(data.painted_albedo_path), "%s: painted on its own colour map" % label)
		_expect(data.defeat_line.is_empty(), "%s: no defeat line to talk over the pair's" % label)
	_expect_eq((load(STRAWCROWN_PATH) as EnemyData).model_scale, 1.0, "Strawcrown at 1.0")
	_expect_eq((load(CHALKCROWN_PATH) as EnemyData).model_scale, 1.075, "Chalkcrown at 1.075 - its body matched to Strawcrown's")
	_expect(paired.grants_when_alone == bereft, "Paired turns Bereft when alone")
	_expect_eq(Status.new(paired).describe(), "If its partner falls, it becomes Bereft.", "Paired's hover line")
	_expect_eq(Status.new(bereft).describe(), "Acts twice each turn.", "Bereft's hover line")
	_expect_eq(bereft.repeats_intent, 2, "Bereft: each step twice")
	_expect_eq(bereft.gained_line, "The other keeps dancing.", "...and its line")
	_completed += 1

func _check_floor_3() -> void:
	var floor_data := load(FLOOR_3_PATH) as FloorData
	var slot: EncounterSlot = floor_data.slots[0]
	_expect_eq(slot.slot_id, &"cranes", "Floor 3's first slot: the cranes - the gate measures from it")
	_expect(slot.required, "...required")
	_expect_eq(slot.position, ANCHOR, "...anchored at (8.67, -33.4), the top of the pool")
	var option: EncounterOption = slot.options[0]
	_expect_eq(option.option_id, &"crane_pair", "...standing the crane pair")
	_expect_eq(option.members.size(), 2, "...two, one cluster")
	_expect_eq(option.members[0].enemy_data.resource_path, STRAWCROWN_PATH, "...Strawcrown first")
	_expect(option.members[0].anchor, "...the anchor")
	_expect_eq(option.members[1].enemy_data.resource_path, CHALKCROWN_PATH, "...Chalkcrown beside it")
	var gap: float = slot.to_floor(option.members[1].position).distance_to(ANCHOR)
	_expect(absf(gap - 1.3) < 0.01, "...1.3 m off (%.3f)" % gap)
	for member in option.members:
		_expect_eq(member.yaw_degrees + slot.yaw_degrees, 10.0, "...%s at yaw 10" % member.enemy_data.enemy_name)
	_expect(option.felled_together_keepsake == load(LEG_BAND_PATH), "Felled together: the Leg Band")
	_expect_eq(option.felled_together_line, "They fell in step.", "...and their line")
	var gate_x: float = slot.position.x + floor_data.exit_direction.x * floor_data.gate_distance_beyond_enemy
	_expect(is_equal_approx(gate_x, GATE_X) and floor_data.exit_direction == Vector2(1, 0), "The gate line stays at x %.1f (got %.2f)" % [GATE_X, gate_x])
	_expect(floor_data.wear_path_override.has(ANCHOR), "The worn band runs through the anchor")
	_expect(not floor_data.wear_path_override.has(Vector2(-3, -9)), "...not the old pair's spot")
	_completed += 1

# Loaded: both stand in the water on the bed, at their real heights, and
# the exit gate sits on x 23.3.
func _check_standing() -> void:
	await _load_floor_3()
	var ground: Node = _field.get_node("Ground")
	var sea_level: float = float(_field.get_node("Sea").get("sea_level"))
	var heights: Array[float] = []
	for path: String in [STRAWCROWN_PATH, CHALKCROWN_PATH]:
		var body: Node3D = _body(path)
		if body == null:
			_fail("no %s on floor 3" % path.get_file())
			continue
		var at := Vector2(body.global_position.x, body.global_position.z)
		var bed: float = float(ground.call("get_height_at", at))
		_expect(sea_level - bed > 0.1, "%s stands in water %.2f m deep" % [path.get_file(), sea_level - bed])
		_expect(absf(body.global_position.y - bed) < 0.05, "...its feet on the bed, not the surface (%.2f vs %.2f)" % [body.global_position.y, bed])
		heights.append(float(body.call("get_head_height")))
		_expect(body.get("_attachment") is CraneMotion, "...wearing CraneMotion")
	if heights.size() == 2:
		_expect(absf(heights[0] - 1.5) < 0.08 and absf(heights[1] - 1.5) < 0.08, "Both about 1.5 m tall (%.2f, %.2f)" % [heights[0], heights[1]])
	var gate: Node3D = _field.get_node("ExitGate")
	_expect(absf(gate.global_position.x - GATE_X) < 0.01, "The gate at x %.2f" % gate.global_position.x)
	await _teardown()
	_completed += 1

# One contact: the fight has both, each Paired, both on Bow - and the
# shared Bow lands 4 Block on each.
func _check_fight_opens() -> void:
	var controller: Node = await _start_fight("")
	if controller != null:
		var straw: Node = _member(controller, "Strawcrown")
		var chalk: Node = _member(controller, "Chalkcrown")
		_expect(straw != null and chalk != null and (controller.get("enemies") as Array).size() == 2, "One contact: the fight has both cranes")
		for member: Node in [straw, chalk]:
			if member == null:
				continue
			_expect_eq(controller.call("get_enemy_status_labels", member), PackedStringArray(["Paired"]), "%s opens Paired" % member.get("enemy_data").enemy_name)
			_expect_eq(_intent_text(controller, member), "4", "...on Bow, 4")
		if straw != null and chalk != null:
			_expect(bool(controller.call("_all_living_simultaneous")), "...and the pair moves together")
			await controller.call("end_turn")
			_expect_eq([_combatant(controller, straw).block, _combatant(controller, chalk).block], [4, 4], "The Bow: 4 Block each")
	await _teardown()
	_completed += 1

# Chalkcrown killed first: Strawcrown turns Bereft at once - told once,
# its line said - and its Step reads 6x2 and lands 12.
func _check_one_falls_first() -> void:
	var controller: Node = await _start_fight("")
	if controller != null:
		var straw: Node = _member(controller, "Strawcrown")
		var c: Combatant = _combatant(controller, straw)
		c.current_intent_index = 1
		var gained: Array = []
		controller.connect("enemy_status_gained", func(member: Node, status: StatusData) -> void: gained.append([member, status]))
		_kill(controller, _member(controller, "Chalkcrown"))
		_expect_eq(controller.call("get_enemy_status_labels", straw), PackedStringArray(["Bereft"]), "Chalkcrown dead: Strawcrown is Bereft")
		_expect(gained.size() == 1 and gained[0][1] == load(BEREFT_PATH), "...told once (%d told)" % gained.size())
		_expect_eq(_line_text(), "The other keeps dancing.", "...its line said over it")
		_expect_eq(_intent_text(controller, straw), "6×2", "...its Step reads 6×2")
		var player: Combatant = controller.get("player")
		var hp_before: int = player.hp
		await controller.call("end_turn")
		_expect_eq(hp_before - player.hp, 12, "...and lands 6 and 6")
		_expect(not bool(controller.call("felled_together")), "One at a time is not felled together")
	await _teardown()
	_completed += 1

# Bereft on Bow: 8 Block in its one turn.
func _check_bereft_bow() -> void:
	var controller: Node = await _start_fight("")
	if controller != null:
		var chalk: Node = _member(controller, "Chalkcrown")
		_kill(controller, _member(controller, "Strawcrown"))
		var c: Combatant = _combatant(controller, chalk)
		c.current_intent_index = 0
		controller.call("_emit_intent_previews")
		_expect_eq(_intent_text(controller, chalk), "8", "Bereft Chalkcrown's Bow reads 8")
		var before: int = c.block
		await controller.call("end_turn")
		_expect_eq(c.block - before, 8, "...and gains 8 Block")
	await _teardown()
	_completed += 1

# One Carve kills both: neither turns Bereft, they fell together, their
# line is said, and the win offers the Leg Band.
func _check_felled_together() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		for member: Node in (controller.get("enemies") as Array):
			_combatant(controller, member).hp = 5
		var gained: Array = []
		controller.connect("enemy_status_gained", func(member: Node, status: StatusData) -> void: gained.append(status))
		var player: Combatant = controller.get("player")
		player.energy = 3
		var views: Array = controller.get("_hand_container").call("_card_views")
		controller.call("request_play", views[0])
		if bool(controller.call("is_awaiting_target")):
			controller.call("confirm_target", (controller.get("enemies") as Array)[0])
		await create_timer(2.0).timeout
		_expect_eq((controller.get("enemies") as Array).size(), 0, "One Carve kills both")
		_expect_eq(gained.size(), 0, "...neither turns Bereft on the way down")
		_expect(bool(controller.call("felled_together")), "...felled together")
		_expect_eq(_line_text(), "They fell in step.", "...their line said")
		await create_timer(4.0).timeout
		_expect(_field.get("_pending_keepsake") == load(LEG_BAND_PATH), "...and the win offers the Leg Band")
	await _teardown()
	_completed += 1

# Contacted from the hub side, the fight stages with the Wanderer at
# least his minimum spacing from Strawcrown (the anchor) - in the ford's
# shallows, not on top of it - and no one on a face.
func _check_staging() -> void:
	await _load_floor_3()
	var target: Node3D = _body(STRAWCROWN_PATH)
	if target == null:
		_fail("no Strawcrown on floor 3")
		_completed += 1
		return
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + HUB_SIDE.normalized() * 2.3
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	await create_timer(3.0).timeout
	var ground: Node = _field.get_node("Ground")
	var gap: float = _flat(wanderer.global_position).distance_to(_flat(target.global_position))
	var minimum: float = float(_field.call("stance_distance_min", target))
	_expect(gap >= minimum - 0.01, "From the hub: the Wanderer %.2f m from Strawcrown, at least his minimum %.2f" % [gap, minimum])
	var members: Array = _field.get("_battle_members")
	for body: Node3D in [wanderer] + members:
		var label: String = "The Wanderer" if body == wanderer else (body.get("enemy_data") as EnemyData).enemy_name
		var face: Vector2 = _face_at(ground, _flat(body.global_position))
		_expect(face.x <= FACE_SLOPE_MAX_DEG and face.y <= FACE_JUMP_MAX_M, "...%s off any face (%.1f degrees, %.2f m within half a metre)" % [label, face.x, face.y])
	await _teardown()
	_completed += 1

# --- Helpers ---

func _flat(at: Vector3) -> Vector2:
	return Vector2(at.x, at.z)

# The ground under `at`: [its slope in degrees over half a metre, the most
# it rises or falls within half a metre].
func _face_at(ground: Node, at: Vector2) -> Vector2:
	var e: float = 0.25
	var gx: float = (float(ground.call("get_height_at", at + Vector2(e, 0.0))) - float(ground.call("get_height_at", at - Vector2(e, 0.0)))) / (2.0 * e)
	var gz: float = (float(ground.call("get_height_at", at + Vector2(0.0, e))) - float(ground.call("get_height_at", at - Vector2(0.0, e)))) / (2.0 * e)
	var here: float = float(ground.call("get_height_at", at))
	var jump: float = 0.0
	for k in 8:
		var angle: float = TAU * float(k) / 8.0
		jump = maxf(jump, absf(float(ground.call("get_height_at", at + Vector2(cos(angle), sin(angle)) * 0.5)) - here))
	return Vector2(rad_to_deg(atan(Vector2(gx, gz).length())), jump)

func _load_floor_3(deck_card_path: String = "") -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	if deck_card_path != "":
		var cards: Array[CardData] = []
		for i in 10:
			cards.append((load(deck_card_path) as CardData).duplicate() as CardData)
		_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_3)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _start_fight(deck_card_path: String) -> Node:
	await _load_floor_3(deck_card_path)
	var target: Node3D = _body(STRAWCROWN_PATH)
	if target == null:
		_fail("no Strawcrown on floor 3")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(0.0, 0.0, 2.5)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 3")
		return null
	await create_timer(2.5).timeout
	return overlay.get("battle_controller")

func _body(path: String) -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == path:
			return node as Node3D
	return null

func _member(controller: Node, enemy_name: String) -> Node:
	for member: Node in (controller.get("enemies") as Array):
		var data: EnemyData = member.get("enemy_data")
		if data != null and data.enemy_name == enemy_name:
			return member
	return null

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _kill(controller: Node, member: Node) -> void:
	var combatant: Combatant = _combatant(controller, member)
	combatant.hp = 0
	controller.call("_report_damage", "player", combatant, 99, "card")

func _intent_text(controller: Node, member: Node) -> String:
	var intents: Dictionary = controller.get_parent().get("_enemy_intents")
	var intent: Node = intents.get(member)
	var label: Label = intent.get("_label") if intent != null else null
	return label.text if label != null else ""

func _line_text() -> String:
	var hud: Node = _field.get_node_or_null(^"FieldHUD")
	if hud == null:
		return ""
	for child in hud.find_children("*", "Label", true, false):
		if child is WorldVoiceLine:
			return (child as Label).text
	return ""

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
