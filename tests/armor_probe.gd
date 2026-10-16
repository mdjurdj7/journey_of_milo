extends SceneTree

# Headless probe for armor - the WORN slot beside the keepsake (RunState.
# worn, TrinketData.slot WORN) and its rules: max HP while worn (no heal
# on equip, current HP clamped when it comes off), the first hit that gets
# past Block scaled once a fight (Grace opening on what then reaches HP,
# the intent preview agreeing), Block as a fight opens, damage back once
# per attack through the enemy's Block - a kill by it included - and an
# elite's table rolling by rarity, never the piece already worn. On the
# sand (WorldArmor): its line once he walks up, the plate's TAKE / LEAVE
# and "Replaces ...", a swap setting the old piece down where he stands to
# be taken again, a won fight's piece lying where the enemy fell, the
# name's rarity finish, and the HUD's WORN line.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/armor_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Pieces are built here, not loaded: the rules are under test, not the
# four pieces' numbers - every expectation is read off the piece's own
# fields. Rules cases build Combatants; field cases load the real region
# scene and start fights through RegionField's contact handler, as
# trinket_probe does. Untyped against anything that names the RunState
# autoload: a SceneTree script compiles before the autoloads register.

const CASES := 14
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const SAFETY_SECONDS := 240.0

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
	_new_run()

	_check_max_hp_while_worn()
	_check_new_run_empties_slot()
	_check_roll_by_rarity()
	_check_first_hit_scaled_once()
	_check_first_hit_preview()
	_check_hit_back_once_per_attack()
	await _check_fight_opening()
	await _check_hit_back_kill_in_fight()
	await _check_drop_line()
	await _check_examine_leave()
	await _check_swap_sets_old_down()
	_check_plate_finish()
	await _check_worn_line()
	await _check_elite_drop()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("armor_probe: PASSED")
		quit(0)
	else:
		print("armor_probe: %d FAILED" % _failures)
		quit(1)

# --- The slot ---

# Max HP rises by the piece's bonus without healing, falls when it comes
# off with current HP clamped, and a swap trades one bonus for the other.
func _check_max_hp_while_worn() -> void:
	_new_run()
	var base_max: int = int(_run_state.get("player_max_hp"))
	var harness: TrinketData = _piece(&"probe_harness", CardData.CardRarity.COMMON)
	harness.max_hp_bonus = 6
	var plain: TrinketData = _piece(&"probe_plain", CardData.CardRarity.COMMON)
	_run_state.set("player_hp", base_max - 2)
	_run_state.call("equip_worn", harness)
	_expect(_run_state.get("worn") == harness, "equip_worn() puts the piece in the WORN slot")
	_expect(_run_state.get("keepsake") == null, "...and leaves the keepsake slot alone")
	_expect_eq(int(_run_state.get("player_max_hp")), base_max + harness.max_hp_bonus, "Max HP rises by the piece's max_hp_bonus")
	_expect_eq(int(_run_state.get("player_hp")), base_max - 2, "...without healing")
	_run_state.call("heal", 999)
	_expect_eq(int(_run_state.get("player_hp")), base_max + harness.max_hp_bonus, "Healed to the new max")
	_run_state.call("equip_worn", plain)
	_expect_eq(int(_run_state.get("player_max_hp")), base_max, "Swapping it off takes the bonus away")
	_expect_eq(int(_run_state.get("player_hp")), base_max, "...and current HP clamps to the new max")
	_run_state.call("equip_worn", harness)
	_run_state.call("equip_worn", null)
	_expect_eq(int(_run_state.get("player_max_hp")), base_max, "Emptying the slot takes it away too")
	_expect(_run_state.get("worn") == null, "...and the slot is empty")
	_completed += 1

func _check_new_run_empties_slot() -> void:
	_new_run()
	var harness: TrinketData = _piece(&"probe_harness", CardData.CardRarity.COMMON)
	harness.max_hp_bonus = 6
	_run_state.call("equip_worn", harness)
	_new_run()
	_expect(_run_state.get("worn") == null, "A new run's WORN slot is empty")
	var character: CharacterData = load(CHARACTER_PATH)
	_expect_eq(int(_run_state.get("player_max_hp")), character.max_hp, "...and max HP is the character's own")
	_completed += 1

# RARE with the chance, COMMON without; never the worn piece - a tier left
# empty by that falls back to the other.
func _check_roll_by_rarity() -> void:
	var common: TrinketData = _piece(&"probe_common", CardData.CardRarity.COMMON)
	var rare: TrinketData = _piece(&"probe_rare", CardData.CardRarity.RARE)
	var table := KeepsakeTable.new()
	for trinket in [common, rare]:
		var entry := KeepsakeEntry.new()
		entry.trinket = trinket
		table.entries.append(entry)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var all_rare: bool = true
	var all_common: bool = true
	var rares: int = 0
	for i in 40:
		all_rare = all_rare and table.roll_by_rarity(rng, 1.0, null) == rare
		all_common = all_common and table.roll_by_rarity(rng, 0.0, null) == common
		if table.roll_by_rarity(rng, 0.5, null) == rare:
			rares += 1
	_expect(all_rare, "A rare chance of 1 always rolls the RARE piece")
	_expect(all_common, "A rare chance of 0 always rolls a COMMON piece")
	_expect(rares > 0 and rares < 40, "A chance between rolls both (%d of 40 rare at 0.5)" % rares)
	var never_worn: bool = true
	for i in 20:
		never_worn = never_worn and table.roll_by_rarity(rng, 1.0, rare) == common and table.roll_by_rarity(rng, 0.0, common) == rare
	_expect(never_worn, "Never the piece already worn - the other tier instead")
	var lone := KeepsakeTable.new()
	var lone_entry := KeepsakeEntry.new()
	lone_entry.trinket = common
	lone.entries.append(lone_entry)
	_expect(lone.roll_by_rarity(rng, 0.0, common) == null, "...and nothing when the worn piece is all there is")
	_completed += 1

# --- The first hit ---

# A fully blocked hit leaves it armed; the first to get past Block is
# scaled before Block takes its share, Grace opening on what reaches HP;
# the next hit lands whole.
func _check_first_hit_scaled_once() -> void:
	var scale: float = 0.5
	var player: Combatant = _player(60)
	player.first_hit_scale = scale
	var enemy := Combatant.new(40)
	var data: EnemyData = _enemy_data(11, 1)
	var intent: EnemyIntent = data.intents[0]
	player.block = 20
	var blocked: Dictionary = _attack(enemy, data, intent, player)
	_expect(not player.first_hit_spent, "A hit Block takes whole leaves the first-hit scale armed")
	_expect_eq(int(blocked["damage_to_hp"]), 0, "...nothing reached HP")
	player.block = 2
	var hp_before: int = player.hp
	var first: Dictionary = _attack(enemy, data, intent, player)
	var scaled: int = floori(float(intent.value) * scale)
	_expect(player.first_hit_spent, "The first hit past Block spends it")
	_expect_eq(int(first["damage_to_hp"]), scaled - 2, "...scaled before Block: (%d x %.2f) - 2 Block" % [intent.value, scale])
	_expect_eq(hp_before - player.hp, scaled - 2, "...and that is what HP lost")
	_expect_eq(player.grace, int(first["damage_to_hp"]), "Grace opens on the hit as actually taken")
	var second: Dictionary = _attack(enemy, data, intent, player)
	_expect_eq(int(second["damage_to_hp"]), intent.value, "The next hit lands whole - once per fight")
	_completed += 1

# The intent display shows the scaled hit while it's armed, and the whole
# one once it's spent - the same rule the attack lands.
func _check_first_hit_preview() -> void:
	var player: Combatant = _player(60)
	player.first_hit_scale = 0.5
	var enemy := Combatant.new(40)
	var data: EnemyData = _enemy_data(9, 2)
	EnemyTurn.pick_initial_intent(enemy, data)
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	var scaled: int = floori(9.0 * player.first_hit_scale)
	_expect_eq(str(preview["hit_amounts"]), str([scaled, 9]), "The preview scales only the first hit of a two-hit attack")
	_expect_eq(int(preview["damage_to_hp"]), scaled + 9, "...and its total to HP agrees")
	var landed: Dictionary = _attack(enemy, data, data.intents[0], player)
	_expect_eq(int(landed["damage_to_hp"]), int(preview["damage_to_hp"]), "...with what the attack then lands")
	_expect(player.first_hit_spent, "...spending it")
	var after: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq(str(after["hit_amounts"]), str([9, 9]), "Spent, the preview shows whole hits")
	_completed += 1

# --- Damage back ---

# Once per attack however many hits, Block taking it all included; through
# the enemy's own Block; and a kill by it ends the enemy's repeats.
func _check_hit_back_once_per_attack() -> void:
	var back: int = 2
	var player: Combatant = _player(60)
	player.hit_back_damage = back
	var enemy := Combatant.new(40)
	var data: EnemyData = _enemy_data(4, 3)
	player.block = 99
	_attack(enemy, data, data.intents[0], player)
	_expect_eq(enemy.hp, 40 - back, "A three-hit attack Block took whole: hit_back_damage back, once")
	enemy.block = 1
	var result: Dictionary = _attack(enemy, data, data.intents[0], player)
	_expect_eq(enemy.block, 0, "...through the enemy's own Block")
	_expect_eq(int(result.get("hit_back", 0)), back - 1, "...\"hit_back\" is what reached its HP")
	var plain: Combatant = _player(60)
	var untouched := Combatant.new(40)
	_attack(untouched, data, data.intents[0], plain)
	_expect_eq(untouched.hp, 40, "Nothing comes back without the piece")
	# A kill by it: the turn's remaining attacks don't land.
	var twice := StatusData.new()
	twice.id = &"probe_twice"
	twice.repeats_intent = 2
	var dying := Combatant.new(40)
	dying.hp = back
	EnemyTurn.pick_initial_intent(dying, data)
	Status.apply_to(dying.statuses, twice)
	var shield: Combatant = _player(60)
	shield.hit_back_damage = back
	shield.block = 99
	var turn: Dictionary = EnemyTurn.take_turn(dying, data, shield)
	_expect_eq(dying.hp, 0, "Damage back can kill on the enemy's own turn")
	_expect_eq((turn["actions"] as Array).size(), 1, "...and a repeated attack stops at the one that killed it")
	_completed += 1

# --- In a fight ---

# The opening: the worn piece's Block on the Wanderer, beside the
# keepsake's own part; its first-hit scale and damage back armed.
func _check_fight_opening() -> void:
	_new_run()
	var skin: TrinketData = _piece(&"probe_skin", CardData.CardRarity.COMMON)
	skin.combat_start_block = 5
	skin.first_hit_scale = 0.5
	skin.hit_back_damage = 2
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	_run_state.call("equip_worn", skin)
	var controller: Node = await _start_fight(0)
	if controller != null:
		var player: Combatant = controller.get("player")
		_expect_eq(player.block, skin.combat_start_block, "A fight opens with the worn piece's Block")
		_expect_eq(player.statuses.size(), 1, "...beside the keepsake's own status")
		_expect(is_equal_approx(player.first_hit_scale, skin.first_hit_scale) and not player.first_hit_spent, "...its first-hit scale armed")
		_expect_eq(player.hit_back_damage, skin.hit_back_damage, "...and its damage back")
	await _teardown()
	_completed += 1

# A kill by damage back, as the controller hears it: the enemy dropped,
# its death held, and the fight won once it has played.
func _check_hit_back_kill_in_fight() -> void:
	_new_run()
	var controller: Node = await _start_fight(0)
	if controller != null:
		var enemies: Array = (controller.get("enemies") as Array).duplicate()
		var combatants: Dictionary = controller.get("_combatants")
		var won: Array[bool] = [false]
		controller.connect("battle_won", func() -> void: won[0] = true)
		for member in enemies:
			var combatant: Combatant = combatants.get(member)
			var left: int = combatant.hp
			combatant.hp = 0
			controller.call("_report_enemy_attack", member, {"intent": "probe", "hits": [], "blocked": 0, "absorbed": 0, "damage_to_hp": 0, "saved_heal": 0, "grace_opened": 0, "hit_back": left})
		_expect((controller.get("enemies") as Array).is_empty(), "Damage back's kill drops the enemy from the fight")
		_expect(bool(controller.call("has_held_deaths")) or bool(controller.call("is_dying", enemies[0])), "...its death held for the blow")
		controller.call("_check_battle_end")
		var start: int = Time.get_ticks_msec()
		while not won[0] and Time.get_ticks_msec() - start < 5000:
			await process_frame
		_expect(won[0], "...and the fight is won once it has played")
	await _teardown()
	_completed += 1

# --- On the sand ---

# A piece lying near him says its line once he walks up; a piece set down
# under him waits until he has stepped away and back.
func _check_drop_line() -> void:
	_new_run()
	await _load_field(0)
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var away: Vector3 = wanderer.global_position
	var piece: TrinketData = _piece(&"probe_common", CardData.CardRarity.COMMON)
	piece.drop_line = "Probe line."
	var drop: Node3D = _field.call("spawn_world_armor", piece, away + Vector3(6.0, 0.0, 0.0), false)
	await _physics(5)
	_expect(not bool(drop.call("has_spoken")), "A piece out of reach says nothing")
	_expect(drop.get_node_or_null("Body") != null, "...and has a body on the sand")
	wanderer.global_position = drop.global_position + Vector3(0.5, 0.0, 0.0)
	await _physics(5)
	_expect(bool(drop.call("has_spoken")), "Walking up to it says its line")
	var set_down: Node3D = _field.call("spawn_world_armor", piece, wanderer.global_position, true)
	await _physics(5)
	_expect(not bool(set_down.call("has_spoken")), "A piece set down under him waits")
	wanderer.global_position = away
	await _physics(5)
	wanderer.global_position = set_down.global_position + Vector3(0.5, 0.0, 0.0)
	await _physics(5)
	_expect(bool(set_down.call("has_spoken")), "...until he steps away and back")
	await _teardown()
	_completed += 1

# The plate from the sand: TAKE and LEAVE, "Replaces ..." with one worn;
# LEAVE leaves it lying and the slot as it was; the field frozen under it
# and live again after.
func _check_examine_leave() -> void:
	_new_run()
	await _load_field(0)
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var worn: TrinketData = _piece(&"probe_worn", CardData.CardRarity.COMMON)
	var offered: TrinketData = _piece(&"probe_offered", CardData.CardRarity.COMMON)
	_run_state.call("equip_worn", worn)
	var drop: Node3D = _field.call("spawn_world_armor", offered, wanderer.global_position + Vector3(0.5, 0.0, 0.0), false)
	await _physics(2)
	_expect(bool(_field.call("open_armor_examine", drop)), "A piece within reach opens its plate")
	await process_frame
	var examine: Node = _field.get_node_or_null("ArmorExamine")
	_expect(examine != null, "...ArmorExamine is up")
	_expect(not _field.can_process(), "...over a frozen field")
	if examine != null:
		var plate: Node = examine.call("get_plate")
		_expect(str(plate.call("replaces_text")).begins_with("Replaces " + worn.display_name), "...naming the piece it replaces")
		plate.call("activate", 1) # LEAVE
		await _seconds(0.5)
	_expect(_field.can_process(), "LEAVE: the field is live again")
	_expect(_run_state.get("worn") == worn, "...the worn piece still worn")
	_expect(is_instance_valid(drop) and not bool(drop.call("is_taken")), "...and the piece still lying there")
	await _teardown()
	_completed += 1

# TAKE: worn, gone from the sand; the old one set down where he stands,
# to be taken again - and the swap goes back the other way.
func _check_swap_sets_old_down() -> void:
	_new_run()
	await _load_field(0)
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	var first: TrinketData = _piece(&"probe_first", CardData.CardRarity.COMMON)
	first.max_hp_bonus = 6
	var second: TrinketData = _piece(&"probe_second", CardData.CardRarity.RARE)
	var base_max: int = int(_run_state.get("player_max_hp"))
	var drop_first: Node3D = _field.call("spawn_world_armor", first, wanderer.global_position + Vector3(0.5, 0.0, 0.0), false)
	await _physics(2)
	_field.call("take_worn_piece", drop_first)
	_expect(_run_state.get("worn") == first, "TAKE wears the piece")
	_expect(bool(drop_first.call("is_taken")), "...and it leaves the sand")
	_expect_eq(_lying().size(), 0, "...with nothing set down from an empty slot")
	var drop_second: Node3D = _field.call("spawn_world_armor", second, wanderer.global_position + Vector3(0.5, 0.0, 0.0), false)
	await _physics(2)
	_field.call("take_worn_piece", drop_second)
	_expect(_run_state.get("worn") == second, "Taking another wears it")
	_expect_eq(int(_run_state.get("player_max_hp")), base_max, "...the first's max HP gone with it")
	var lying: Array[Node] = _lying()
	_expect(lying.size() == 1 and lying[0].get("piece") == first, "...and the first lies on the sand")
	if lying.size() == 1:
		var at: Vector3 = (lying[0] as Node3D).global_position
		_expect(Vector2(at.x - wanderer.global_position.x, at.z - wanderer.global_position.z).length() < 0.01, "...where he stands")
		_field.call("take_worn_piece", lying[0])
		_expect(_run_state.get("worn") == first, "It can be taken again")
		var back: Array[Node] = _lying()
		_expect(back.size() == 1 and back[0].get("piece") == second, "...setting the second down in turn")
	await _teardown()
	_completed += 1

# The name's finish: the cards' own for RARE, none for COMMON.
func _check_plate_finish() -> void:
	var plate := ArmorPlate.new()
	root.add_child(plate)
	plate.set_piece(_piece(&"probe_rare", CardData.CardRarity.RARE))
	_expect(plate.get_name_finish() != null, "A RARE piece's name wears the rarity finish")
	plate.set_piece(_piece(&"probe_common", CardData.CardRarity.COMMON))
	_expect(plate.get_name_finish() == null, "A COMMON piece's name is plain ink")
	_expect_eq(plate.replaces_text(), "", "...and with nothing worn there is no Replaces line")
	plate.queue_free()
	_completed += 1

# The HUD's WORN line: hidden while nothing is worn, the piece's name
# while one is; its click opens the plate with no choice.
func _check_worn_line() -> void:
	_new_run()
	await _load_field(0)
	var line: Control = _field.get_node_or_null("FieldHUD/WornLine") as Control
	_expect(line != null, "The field HUD has a WORN line")
	if line != null:
		_expect(not line.is_visible_in_tree(), "...hidden while nothing is worn")
		var piece: TrinketData = _piece(&"probe_worn", CardData.CardRarity.COMMON)
		_run_state.call("equip_worn", piece)
		await process_frame
		_expect(line.call("get_keepsake") == piece, "...showing the piece once worn")
		_expect(bool(_field.call("open_worn_examine", piece, Rect2())), "Its examine opens")
		await process_frame
		var examine: Node = _field.get_node_or_null("WornExamine")
		_expect(examine != null and (examine.call("get_plate") as ArmorPlate).get_piece() == piece, "...the plate, with the piece")
		if examine != null:
			examine.call("close", false)
			await _seconds(0.5)
		_expect(_field.can_process(), "...and the field is live once it closes")
	await _teardown()
	_completed += 1

# A won fight against an enemy with an armor table leaves one piece on the
# sand, where it fell. The table is set here, not read from the data - the
# rule under test is the drop.
func _check_elite_drop() -> void:
	_new_run()
	var data: EnemyData = load(WARDLING_PATH)
	var saved: KeepsakeTable = data.armor_table
	var table := KeepsakeTable.new()
	var entry := KeepsakeEntry.new()
	entry.trinket = _piece(&"probe_drop", CardData.CardRarity.COMMON)
	table.entries.append(entry)
	data.armor_table = table
	var controller: Node = await _start_fight(2, WARDLING_PATH)
	if controller != null:
		var fell_at: Vector3 = Vector3.ZERO
		for member in (controller.get("enemies") as Array):
			fell_at = (member as Node3D).global_position
		_kill_all(controller)
		var start: int = Time.get_ticks_msec()
		while _lying().is_empty() and Time.get_ticks_msec() - start < 6000:
			await process_frame
		var lying: Array[Node] = _lying()
		_expect_eq(lying.size(), 1, "A win against it leaves one worn piece on the sand")
		if lying.size() == 1:
			_expect(lying[0].get("piece") == entry.trinket, "...the piece its table gave")
			var at: Vector3 = (lying[0] as Node3D).global_position
			_expect(Vector2(at.x - fell_at.x, at.z - fell_at.z).length() < 0.01, "...where it fell")
	data.armor_table = saved
	await _teardown()
	_completed += 1

func _lying() -> Array[Node]:
	var lying: Array[Node] = []
	for node in get_nodes_in_group(&"worn_drops"):
		if not bool(node.call("is_taken")):
			lying.append(node)
	return lying

func _physics(frames: int) -> void:
	for i in frames:
		await physics_frame

func _seconds(seconds: float) -> void:
	await create_timer(seconds).timeout

# Every member to 0 through the controller's own damage path, then the
# end check - kill_order_probe's _kill().
func _kill_all(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: RefCounted = combatants.get(member)
		if combatant == null:
			continue
		combatant.set("hp", 0)
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

# --- Helpers ---

func _piece(id: StringName, rarity: CardData.CardRarity) -> TrinketData:
	var piece := TrinketData.new()
	piece.id = id
	piece.display_name = String(id)
	piece.slot = TrinketData.Slot.WORN
	piece.rarity = rarity
	return piece

func _player(hp: int) -> Combatant:
	var player := Combatant.new(hp)
	player.critical_hp_fraction = 0.3
	player.has_grace = true
	player.grace_cap_mode = CharacterData.GraceCapMode.LARGEST_HIT
	player.grace_open_fraction = 1.0
	return player

func _enemy_data(value: int, hits: int) -> EnemyData:
	var intent := EnemyIntent.new()
	intent.intent_name = "Probe"
	intent.value = value
	intent.hits = hits
	var data := EnemyData.new()
	data.enemy_name = "Probe"
	data.max_hp = 40
	data.intents.append(intent)
	return data

func _attack(enemy: Combatant, data: EnemyData, intent: EnemyIntent, player: Combatant) -> Dictionary:
	var result: Dictionary = {"intent": intent.intent_name, "hits": [], "attacked": false, "damage_to_hp": 0, "grace_opened": 0, "saved_heal": 0, "blocked": 0, "absorbed": 0}
	EnemyTurn.land_attack(enemy, data, intent, player, result)
	return result

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))

func _load_field(floor_index: int) -> void:
	_run_state.set("current_floor_index", floor_index)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame

# Loads the floor and starts a fight with its first enemy (or the first
# of `enemy_path`'s data, when given). The fight's BattleController, or
# null (a FAIL is recorded).
func _start_fight(floor_index: int, enemy_path: String = "") -> Node:
	await _load_field(floor_index)
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if enemy_path == "" or (data != null and data.resource_path == enemy_path):
			target = node as Node3D
			break
	if target == null:
		_fail("no enemy to fight on floor %d (%s)" % [floor_index + 1, enemy_path])
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
		_fail("no fight started on floor %d" % (floor_index + 1))
		return null
	return overlay.get("battle_controller")

func _teardown() -> void:
	if _field != null:
		_field.queue_free()
		_field = null
	for i in 2:
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
