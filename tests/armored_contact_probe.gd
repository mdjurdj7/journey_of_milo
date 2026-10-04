extends SceneTree

# Headless probe for the armored contact sound (EnemyData.armored_contact_
# sounds): a card hit that meets an enemy's block draws its contact take
# from the armored pool, judged as the hit lands, before the block is
# spent - whether the block takes it whole or it breaks through - and a
# hit on no block from contact_sounds. A hit the block takes whole has
# its own reaction (BattleFeedback.on_enemy_hit_blocked()): the sound and
# a reduced recoil, with no damage report (so no number, hit-stop or
# shake) and no flash.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/armored_contact_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fight cases load the real region scene and start a fight with floor 1's
# Sputter through RegionField's contact handler, as collateral_probe does,
# then play real Slashes (5 damage) through BattleController.request_play()
# / confirm_target() with the Sputter's block set by hand. Untyped against
# anything that names the RunState autoload.

const CASES := 5
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const NIPPER_PATH := "res://battle/rules/enemies/nipper.tres"
const DRAGONFLY_PATHS: Array[String] = ["res://battle/rules/enemies/dragonfly.tres", "res://battle/rules/enemies/dragonfly_lone.tres"]
const HIT_ARMOR_PATH := "res://assets/audio/enemies/Sputter/hit_armor.mp3"
const SHELL_PATHS: Array[String] = [
	"res://assets/audio/enemies/Sputter/hit_shell_1.mp3",
	"res://assets/audio/enemies/Sputter/hit_shell_2.mp3",
	"res://assets/audio/enemies/Sputter/hit_shell_3.mp3",
]
# The crack's ID from when it was hit_shell_1.mp3 - the dragonflies were
# authored against it and must still find the same sound.
const HIT_ARMOR_UID := "uid://co5jagvmbnmkr"
const SLASH_DAMAGE := 5
const ENEMY_HP := 999
# Seconds sampled after the impact: past the recoil's out leg and flash.
const WATCH_SECONDS := 0.45
const SAFETY_SECONDS := 300.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
# Spies on the controller, reset per play.
var _dealt: Array = []
var _blocked: Array = []
var _impact: bool = false

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	_check_data()
	await _check_fight()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("armored_contact_probe: PASSED")
		quit(0)
	else:
		print("armored_contact_probe: %d FAILED" % _failures)
		quit(1)

# --- Data ---

func _check_data() -> void:
	var sputter := load(SPUTTER_PATH) as EnemyData
	_expect_eq(_paths(sputter.contact_sounds), SHELL_PATHS, "Sputter's contact_sounds are the three shell takes")
	_expect_eq(_paths(sputter.armored_contact_sounds), [HIT_ARMOR_PATH] as Array[String], "...and its armored_contact_sounds the crack")
	_expect_eq(_paths((load(NIPPER_PATH) as EnemyData).contact_sounds), SHELL_PATHS, "The Nipper's contact_sounds are the Sputter's shell takes")
	_expect_eq((load(NIPPER_PATH) as EnemyData).armored_contact_sounds.size(), 0, "...with no armored takes")
	for path in DRAGONFLY_PATHS:
		var data := load(path) as EnemyData
		_expect_eq(_paths(data.contact_sounds), [HIT_ARMOR_PATH] as Array[String], "%s still cracks (hit_armor)" % path.get_file())
		_expect_eq(data.armored_contact_sounds.size(), 0, "...with no armored takes")
	_expect_eq(ResourceUID.id_to_text(ResourceLoader.get_resource_uid(HIT_ARMOR_PATH)), HIT_ARMOR_UID, "hit_armor.mp3 keeps the old hit_shell_1 ID")
	_expect(not SHELL_PATHS.has(HIT_ARMOR_PATH), "The crack is not among the shell takes")
	_completed += 1

# --- The fight ---

func _check_fight() -> void:
	var controller: Node = await _start_fight()
	if controller == null:
		return
	var enemy: Node3D = _field_enemy(controller)
	var combatant: Combatant = _enemy(controller)
	_expect_eq((enemy.get("enemy_data") as EnemyData).resource_path, SPUTTER_PATH, "Floor 1's fight is the Sputter")
	controller.connect("damage_dealt", func(_source: Variant, target: Variant, amount: int, _kind: String) -> void:
		if target is Node3D:
			_dealt.append(amount)
	)
	controller.connect("enemy_hit_blocked", func(_enemy: Node3D, absorbed: bool) -> void:
		_blocked.append(absorbed)
	)
	controller.connect("card_impact", func(_card: CardData) -> void:
		_impact = true
	)

	# A hit on no block: a shell take, the full reaction.
	combatant.block = 0
	var normal: Dictionary = await _slash(controller, enemy)
	_expect(_in(normal["stream"], SHELL_PATHS), "A hit on no block plays a shell take (got %s)" % _path_of(normal["stream"]))
	_expect_eq(_dealt, [SLASH_DAMAGE], "...reports its damage (the number)")
	_expect_eq(_blocked, [], "...and meets no block")
	_expect(normal["flashed"], "...and flashes")
	var full_recoil: float = normal["recoil"]
	_expect(full_recoil > 0.05, "...and recoils (%.3f m)" % full_recoil)
	_completed += 1

	# A hit that breaks through block: the crack, the full reaction.
	combatant.block = 3
	var through: Dictionary = await _slash(controller, enemy)
	_expect(_path_of(through["stream"]) == HIT_ARMOR_PATH, "A hit breaking through 3 block plays the crack (got %s)" % _path_of(through["stream"]))
	_expect_eq(_blocked, [false], "...met block, not absorbed")
	_expect_eq(_dealt, [SLASH_DAMAGE - 3], "...reports what got through")
	_expect_eq(combatant.block, 0, "...and spends the block")
	_expect(through["flashed"], "...and flashes")
	_expect(absf(float(through["recoil"]) - full_recoil) < full_recoil * 0.15, "...and recoils in full (%.3f m of %.3f)" % [through["recoil"], full_recoil])
	_completed += 1

	# A hit the block takes whole: the crack, a half recoil, nothing else.
	combatant.block = 8
	var hp_before: int = combatant.hp
	var absorbed: Dictionary = await _slash(controller, enemy)
	_expect(_path_of(absorbed["stream"]) == HIT_ARMOR_PATH, "A hit 8 block takes whole plays the crack (got %s)" % _path_of(absorbed["stream"]))
	_expect_eq(_blocked, [true], "...met block, absorbed")
	_expect_eq(_dealt, [], "...reports no damage: no number, hit-stop or shake")
	_expect_eq(combatant.hp, hp_before, "...takes no HP")
	_expect_eq(combatant.block, 8 - SLASH_DAMAGE, "...and wears the block down")
	_expect(not absorbed["flashed"], "...and does not flash")
	var fraction: float = float(_field.get_node("BattleLayer").get_child(0).get("_battle_feedback").get("absorbed_recoil_fraction"))
	var want: float = full_recoil * fraction
	_expect(absf(float(absorbed["recoil"]) - want) < full_recoil * 0.1, "...and recoils %.2f of a full hit (%.3f m, want %.3f)" % [fraction, absorbed["recoil"], want])
	_completed += 1

	# An enemy with no armored takes plays its usual ones on a blocked hit.
	var empty: Array[AudioStream] = []
	(enemy.get("_armored_contact_pool") as SoundPool).set_clips(empty)
	combatant.block = 8
	var plain: Dictionary = await _slash(controller, enemy)
	_expect(_in(plain["stream"], SHELL_PATHS), "With no armored takes, a blocked hit plays a shell take (got %s)" % _path_of(plain["stream"]))
	_completed += 1
	await _teardown()

# Plays a fresh Slash at `enemy` and watches it land: the contact take it
# played, whether its body flashed and how far it recoiled, sampled every
# frame from the impact for WATCH_SECONDS.
func _slash(controller: Node, enemy: Node3D) -> Dictionary:
	_dealt.clear()
	_blocked.clear()
	_impact = false
	(controller.get("player") as Combatant).energy = 3
	var player: AudioStreamPlayer3D = enemy.get("_contact_player")
	player.stream = null
	var card: CardData = await _deal(controller, SLASH_PATH)
	var view: CardView = _view(controller, card)
	if view == null:
		_fail("Slash is not in the hand")
		return {"stream": null, "flashed": false, "recoil": 0.0}
	var materials: Array[BaseMaterial3D] = enemy.get("_tint_materials")
	var base_colors: Array[Color] = enemy.get("_tint_base_colors")
	var base_position: Vector3 = enemy.global_position
	controller.call("request_play", view)
	controller.call("confirm_target", enemy)
	for i in 600:
		await process_frame
		if _impact:
			break
	var flashed: bool = false
	var recoil: float = 0.0
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < int(WATCH_SECONDS * 1000.0):
		recoil = maxf(recoil, enemy.global_position.distance_to(base_position))
		for index in materials.size():
			if not materials[index].albedo_color.is_equal_approx(base_colors[index]):
				flashed = true
		await process_frame
	for i in 600:
		if not bool(controller.get("_input_locked")):
			break
		await process_frame
	# Back at rest before the next play.
	await create_timer(0.4).timeout
	if materials.is_empty():
		_fail("The Sputter has no tint materials - the flash can't be watched")
	return {"stream": player.stream, "flashed": flashed, "recoil": recoil}

func _start_fight() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data := node.get("enemy_data") as EnemyData
		if data != null and data.resource_path == SPUTTER_PATH:
			target = node as Node3D
			break
	if target == null:
		_fail("no Sputter on floor 1")
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
	controller.get("deck").call("discard_hand")
	# The fight's opening settles (camera, poses) before anything is
	# measured.
	await create_timer(1.5).timeout
	return controller

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand.
func _deal(controller: Node, path: String) -> CardData:
	var card: CardData = (load(path) as CardData).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _enemy(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

func _field_enemy(controller: Node) -> Node3D:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _paths(streams: Array[AudioStream]) -> Array[String]:
	var out: Array[String] = []
	for stream in streams:
		out.append(_path_of(stream))
	return out

func _path_of(stream: Variant) -> String:
	var resource := stream as Resource
	return resource.resource_path if resource != null else "<none>"

func _in(stream: Variant, paths: Array[String]) -> bool:
	return paths.has(_path_of(stream))

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
