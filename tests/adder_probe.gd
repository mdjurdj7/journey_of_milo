extends SceneTree

# Headless probe for the Adder, floor 4's faint-side elite: its Coil ->
# Bite -> Strike loop; Coiled, brought by the Coil resolving - a Denied
# Coil brings none - and held until its next move, striking back for 5
# at each Attack card played against it - an enemy hit in every way (Block, Garnished and Unbroken taken off and spent,
# its attack bonuses, Grace) - Skills never, an all-enemies Attack once;
# the Bite's Venom, landing whatever Block took and adding up; Venom's
# tick at the turn's start - its stacks in HP, falling by 1, gone at 0,
# no Toll, no Grace, caught by Refuse the End; the run log's split; the
# Coiled mark beside its HP and Venom's drop in the player's row; and its
# elite rewards. The rules cases drive EnemyTurn on the real .tres; the
# fight cases load floor 4 and play real cards through BattleController.
# request_play().
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/adder_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 13
const ADDER_PATH := "res://battle/rules/enemies/adder.tres"
const COILED_PATH := "res://battle/rules/statuses/coiled.tres"
const VENOM_PATH := "res://battle/rules/statuses/venom.tres"
const GARNISHED_PATH := "res://battle/rules/statuses/garnished.tres"
const UNBROKEN_PATH := "res://battle/rules/statuses/unbroken.tres"
const HUNGRY_PATH := "res://battle/rules/statuses/hungry.tres"
const REFUSE_PATH := "res://battle/rules/statuses/refuse_the_end.tres"
const KEEPSAKE_PATH := "res://run/keepsakes/keeper/blue_fastener.tres"
const MODEL_PATH := "res://assets/models/enemies/Adder/Adder.glb"
const SOUND_PATHS: Array[String] = ["res://assets/audio/enemies/Stork/hit_1.mp3", "res://assets/audio/enemies/Stork/hit_2.mp3"]
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const RUN_LOGGER_PATH := "res://run/run_logger.gd"
const FLOOR_4 := 3
const HP := 60
const COUNTER := 5
const BITE := 6
const VENOM := 3
const STRIKE := 11
const SLASH := 6
const PLAYER_HP := 999
const SAFETY_SECONDS := 400.0
# How long a won fight may take to open its reward screen: the killing
# blow, the last death, the camera's return.
const REWARD_WAIT_SECONDS := 5.0

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
	_check_cycle()
	_check_counter_rules()
	_check_bite_venom()
	_check_venom_tick_rules()
	await _check_fight_counter()
	await _check_fight_denied()
	await _check_fight_skill()
	await _check_fight_aoe()
	await _check_fight_venom()
	await _check_fight_refuse()
	await _check_floor_entry()
	await _check_elite()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("adder_probe: PASSED")
		quit(0)
	else:
		print("adder_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _adder()
	_expect_eq(data.enemy_name, "Adder", "The Adder")
	_expect_eq(data.max_hp, HP, "...60 HP")
	_expect(data.is_elite, "...an elite")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 3, "...of three moves")
	if data.intents.size() == 3:
		var coil: EnemyIntent = data.intents[0]
		var bite: EnemyIntent = data.intents[1]
		var strike: EnemyIntent = data.intents[2]
		_expect(coil.intent_name == "Coil" and coil.type == EnemyIntent.IntentType.COIL, "...Coil, a COIL")
		_expect(bite.intent_name == "Bite" and bite.type == EnemyIntent.IntentType.ATTACK and bite.value == BITE, "...Bite, an Attack of 6")
		_expect(bite.applies_to_player != null and bite.applies_to_player.resource_path == VENOM_PATH and bite.applied_amount == VENOM, "...that puts 3 Venom on the player")
		_expect(coil.status_on_resolve != null and coil.status_on_resolve.resource_path == COILED_PATH, "...the Coil bringing Coiled when it resolves")
		_expect(coil.status_while_queued == null and bite.status_while_queued == null, "...and nothing held while queued")
		_expect(strike.intent_name == "Strike" and strike.type == EnemyIntent.IntentType.ATTACK and strike.value == STRIKE and strike.applies_to_player == null, "...Strike, an Attack of 11")
	var coiled: StatusData = load(COILED_PATH)
	_expect(coiled.strikes_back_on_attack_card and coiled.default_magnitude == COUNTER, "Coiled strikes back for 5")
	_expect(coiled.shows_beside_hp and coiled.mark == StatusData.Mark.COIL, "...shown beside the HP as a coil")
	_expect_eq(Status.new(coiled).label(), "Coiled 5", "...reading Coiled 5")
	var venom: StatusData = load(VENOM_PATH)
	_expect(venom.category == StatusData.Category.TICK and venom.tick_decay == 1 and not venom.tick_is_self_loss, "Venom: a TICK, falling by 1, not the holder's own loss")
	_expect(venom.mark == StatusData.Mark.DROP, "...marked with a drop")
	_expect(data.keepsake_table != null and data.keepsake_table.guaranteed and data.keepsake_table.entries.size() == 1 and data.keepsake_table.entries[0].trinket.resource_path == KEEPSAKE_PATH, "Its keepsake table: Blue Fastener, guaranteed")
	_expect_eq(data.glassbone_reward, 1, "...and Glassbone 1")
	_expect_eq(data.model_scene_path, MODEL_PATH, "Its own body, the adder model")
	_expect_eq(data.attachment_scene_path, "", "...without its pose")
	var sounds: Array[String] = []
	for stream in data.contact_sounds:
		sounds.append(stream.resource_path)
	_expect_eq(sounds, SOUND_PATHS, "...and the Stork's hits for its contact")
	_completed += 1

# Coil (nothing) -> Bite 6 -> Strike 11 -> Coil; Coiled from the Coil's
# end until the Bite lands.
func _check_cycle() -> void:
	var data: EnemyData = _adder()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = Combatant.new(PLAYER_HP)
	_expect(not _has(enemy, COILED_PATH), "At the start, Coil queued: not Coiled")
	var seen: Array[String] = []
	var coiled_after: Array[bool] = []
	for turn in 4:
		var name: String = EnemyTurn.current_intent(enemy, data).intent_name
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		seen.append("%s %d" % [name.to_lower(), before - player.hp])
		coiled_after.append(_has(enemy, COILED_PATH))
	_expect_eq(seen, ["coil 0", "bite 6", "strike 11", "coil 0"] as Array[String], "Coil -> Bite 6 -> Strike 11 -> Coil")
	_expect_eq(coiled_after, [true, false, false, true] as Array[bool], "...Coiled after the Coil, gone once the Bite lands, back after the next Coil")
	_completed += 1

# The strike back on its own: an enemy hit in every way.
func _check_counter_rules() -> void:
	var data: EnemyData = _adder()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _grace_player()
	_expect(EnemyTurn.counter_strike(enemy, data, player).is_empty(), "Not Coiled: no strike back")
	Status.apply_to(enemy.statuses, load(COILED_PATH))
	var result: Dictionary = EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq(PLAYER_HP - player.hp, COUNTER, "Coiled: the strike back takes 5")
	_expect_eq(str(result.get("intent", "")), "Coiled", "...logged as its Coiled")
	_expect(int(result.get("grace_opened", 0)) > 0 and player.grace > 0, "...and opens Grace (%d)" % player.grace)
	_expect(_has(enemy, COILED_PATH), "...and Coiled stays")
	# Block takes it.
	player = _grace_player()
	player.block = 3
	EnemyTurn.counter_strike(enemy, data, player)
	_expect(PLAYER_HP - player.hp == 2 and player.block == 0, "Block 3: it takes 2, the Block gone")
	# Garnished on the adder: off it, and spent.
	player = _grace_player()
	Status.apply_to(enemy.statuses, load(GARNISHED_PATH))
	EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq(PLAYER_HP - player.hp, 0, "Garnished 5 on it: the strike back lands 0")
	_expect(not _has(enemy, GARNISHED_PATH), "...and spends Garnished")
	# Unbroken on the player: off it, and spent.
	player = _grace_player()
	Status.apply_to(player.statuses, load(UNBROKEN_PATH))
	EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq(PLAYER_HP - player.hp, 1, "Unbroken 4: it lands 1")
	_expect(not _has(player, UNBROKEN_PATH), "...and spends Unbroken")
	# Its attack bonuses count.
	player = _grace_player()
	Status.apply_to(enemy.statuses, load(HUNGRY_PATH))
	EnemyTurn.counter_strike(enemy, data, player)
	_expect_eq(PLAYER_HP - player.hp, COUNTER + 3, "Hungry (+3) on it: the strike back takes 8")
	_completed += 1

# The Bite's Venom lands even when Block takes all of it, and adds up.
func _check_bite_venom() -> void:
	var data: EnemyData = _adder()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = Combatant.new(PLAYER_HP)
	enemy.current_intent_index = 1
	player.block = 50
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(player.hp, PLAYER_HP, "A Bite into Block 50 takes nothing")
	_expect_eq(_magnitude(player, VENOM_PATH), VENOM, "...and still puts Venom 3 on")
	enemy.current_intent_index = 1
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(_magnitude(player, VENOM_PATH), VENOM * 2, "A second Bite: Venom 6 - the stacks add")
	_expect_eq(_label(player, VENOM_PATH), "Venom 6", "...reading Venom 6")
	_completed += 1

# The tick itself: its stacks dealt, then 1 fewer, gone at 0.
func _check_venom_tick_rules() -> void:
	var player: Combatant = Combatant.new(PLAYER_HP)
	Status.apply_amount(player.statuses, load(VENOM_PATH), 2)
	var dealt: Array[int] = []
	var deal := func(amount: int, _ticking: Status) -> void: dealt.append(amount)
	Status.tick_all(player.statuses, deal)
	_expect_eq(_magnitude(player, VENOM_PATH), 1, "Venom 2 ticks: 1 left")
	Status.tick_all(player.statuses, deal)
	_expect(not _has(player, VENOM_PATH), "...ticks again: gone")
	_expect_eq(dealt, [2, 1] as Array[int], "...having dealt 2, then 1")
	_completed += 1

# --- Fights ---

# Slash: none back on the Coil; once Coiled, the card first, then the
# strike back - and the readout's mark.
func _check_fight_counter() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var adder: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, adder)
		var player: Combatant = controller.get("player")
		_expect_eq(int(controller.call("get_intent_preview", adder)["type"]), EnemyIntent.IntentType.COIL, "The fight opens on Coil")
		_expect_eq(_intent_text(controller, adder), "", "...shown as its glyph alone")
		_expect_eq(_hp_mark(controller, adder), {"glyph": &"", "value": 0}, "...nothing beside its HP")
		var before: int = player.hp
		await _play_first(controller, adder)
		_expect(combatant.hp == HP - SLASH and player.hp == before, "Slash on the Coil: it takes 6, nothing back")
		await _end_turn(controller)
		_expect_eq(_intent_text(controller, adder), str(BITE), "Coiled, the Bite queued: the intent reads 6")
		_expect_eq(_hp_mark(controller, adder), {"glyph": &"coil", "value": COUNTER}, "...the coil and 5 beside its HP")
		_expect(not _row_has(controller, adder, "Coiled"), "...and not in the status row")
		var events: Array = []
		controller.connect("damage_dealt", func(source: Variant, _target: Variant, amount: int, _kind: String) -> void:
			events.append([Time.get_ticks_msec(), source is String, amount])
		)
		var adder_hp: int = combatant.hp
		before = player.hp
		var grace_before: int = player.grace
		await _play_first(controller, adder)
		_expect_eq(adder_hp - combatant.hp, SLASH, "Slash into Coiled: it takes 6")
		_expect_eq(before - player.hp, COUNTER, "...and strikes back for 5")
		_expect(player.grace > grace_before, "...which opens Grace")
		_expect(events.size() == 2 and bool(events[0][1]) and not bool(events[1][1]), "...the card's hit shown first, then the strike back's (%s)" % str(events))
		if events.size() == 2:
			var gap: int = int(events[1][0]) - int(events[0][0])
			var delay_ms: int = int(float(controller.get("counter_strike_delay")) * 1000.0)
			_expect(gap >= delay_ms - 20, "...at least counter_strike_delay after it (%d ms)" % gap)
		var by_intent: Dictionary = (load(RUN_LOGGER_PATH) as Script).get("_taken_by_intent")
		_expect_eq(int(by_intent.get("adder:Coiled", 0)), COUNTER, "The run log keys it adder:Coiled")
		# The Bite lands (Block takes it): Coiled goes, and its mark.
		player.block = 99
		await _end_turn(controller)
		_expect(not _has(combatant, COILED_PATH), "The Bite landed: no longer Coiled")
		_expect_eq(_hp_mark(controller, adder), {"glyph": &"", "value": 0}, "...nothing beside its HP")
		before = player.hp
		await _play_first(controller, adder)
		_expect_eq(before - player.hp, 0, "...and a Slash now draws nothing back")
	await _teardown()
	_completed += 1

# Denied on its Coil turn, it never coils: the Bite comes up with no
# Coiled, and an Attack into it draws nothing back - until it next coils.
func _check_fight_denied() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var adder: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, adder)
		var player: Combatant = controller.get("player")
		Status.apply_to(combatant.statuses, load(DENIED_PATH))
		await _end_turn(controller)
		_expect_eq(EnemyTurn.current_intent(combatant, adder.get("enemy_data")).intent_name, "Bite", "Denied on the Coil: the Bite comes up")
		_expect(not _has(combatant, COILED_PATH), "...with no Coiled")
		_expect_eq(_hp_mark(controller, adder), {"glyph": &"", "value": 0}, "...nothing beside its HP")
		var before: int = player.hp
		await _play_first(controller, adder)
		_expect_eq(before - player.hp, 0, "...and a Slash into it draws nothing back")
		# Bite, Strike, then the next Coil resolves: Coiled again.
		player.block = 99
		await _end_turn(controller)
		player.block = 99
		await _end_turn(controller)
		player.block = 99
		await _end_turn(controller)
		_expect(_has(combatant, COILED_PATH), "Its next Coil resolves: Coiled")
		before = player.hp
		await _play_first(controller, adder)
		_expect_eq(before - player.hp, COUNTER, "...and a Slash draws the strike back")
	await _teardown()
	_completed += 1

# A Skill into Coiled draws nothing back.
func _check_fight_skill() -> void:
	var controller: Node = await _start_fight(BRACE_PATH)
	if controller != null:
		var adder: Node = (controller.get("enemies") as Array)[0]
		var player: Combatant = controller.get("player")
		await _end_turn(controller)
		_expect(_has(_combatant(controller, adder), COILED_PATH), "Coiled")
		var before: int = player.hp
		await _play_first(controller, adder)
		await _play_first(controller, adder)
		_expect_eq(before - player.hp, 0, "Two Braces - Skills - into Coiled: nothing back")
	await _teardown()
	_completed += 1

# Carve, an all-enemies Attack, draws one strike back.
func _check_fight_aoe() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		var adder: Node = (controller.get("enemies") as Array)[0]
		var player: Combatant = controller.get("player")
		await _end_turn(controller)
		var hits_back: Array[int] = [0]
		controller.connect("damage_dealt", func(source: Variant, _target: Variant, _amount: int, _kind: String) -> void:
			if not (source is String):
				hits_back[0] += 1
		)
		var before: int = player.hp
		await _play_first(controller, adder)
		_expect(before - player.hp == COUNTER and hits_back[0] == 1, "Carve into Coiled: one strike back, 5 (took %d in %d)" % [before - player.hp, hits_back[0]])
	await _teardown()
	_completed += 1

# Venom from the Bite: its stacks at each turn's start, falling by 1 -
# no Toll, no Grace - in the row with its drop, gone at 0.
func _check_fight_venom() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		var overlay: Node = controller.get_parent()
		var taken_by: Dictionary = {}
		player.block = 99
		await _end_turn(controller)
		player.block = 99
		var toll: int = player.toll
		var grace: int = player.grace
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, VENOM, "The Bite blocked, its Venom 3 ticks at the turn's start: 3 HP")
		_expect_eq(_magnitude(player, VENOM_PATH), VENOM - 1, "...then Venom 2")
		_expect_eq(player.toll, toll, "...no Toll")
		_expect_eq(player.grace, grace, "...no Grace")
		_expect(_row_line(overlay, "Venom 2") != null and _row_line(overlay, "Venom 2").get("glyph", &"") == &"drop", "...the row reads Venom 2 beside its drop")
		player.block = 99
		before = player.hp
		await _end_turn(controller)
		_expect(before - player.hp == 2 and _magnitude(player, VENOM_PATH) == 1, "Next turn: 2 HP, Venom 1")
		player.block = 99
		before = player.hp
		await _end_turn(controller)
		_expect(before - player.hp == 1 and not _has(player, VENOM_PATH), "Then 1 HP, and it's gone")
		_expect(_row_line(overlay, "Venom") == null, "...from the row too")
		taken_by = (load(RUN_LOGGER_PATH) as Script).get("_taken_by")
		_expect_eq(int(taken_by.get("venom", 0)), VENOM + 2 + 1, "The run log puts 6 HP to venom")
		_expect_eq(int(taken_by.get("status", 0)), 0, "...none to a status of their own")
	await _teardown()
	_completed += 1

# A Venom tick that would kill them Critical, Refuse the End armed: it
# leaves them at its survive HP, as a killing hit would, and is spent.
func _check_fight_refuse() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var player: Combatant = controller.get("player")
		player.hp = 2
		_run_state.set("player_hp", 2)
		var refuse: StatusData = load(REFUSE_PATH)
		Status.apply_to(player.statuses, refuse)
		Status.apply_amount(player.statuses, load(VENOM_PATH), 9)
		await _end_turn(controller)
		var survive: int = refuse.survive_hp(player.max_hp, player.critical_hp_fraction)
		_expect_eq(player.hp, survive, "Venom 9 at 2 HP, Critical, Refuse the End armed: left at %d" % survive)
		_expect(Status.find_in(player.statuses, refuse) == null, "...and Refuse the End is spent")
		_expect_eq(int(_run_state.get("player_hp")), player.hp, "...the run's HP following")
		_expect(_field.get_node("BattleLayer").get_child_count() > 0, "...and the fight goes on")
	await _teardown()
	_completed += 1

# Floor 4's faint-side slot: the adder, an optional elite, facing east.
func _check_floor_entry() -> void:
	var data: Resource = load("res://floors/region1_floor4.tres")
	var entry: Resource = (data.get("enemies") as Array)[1]
	_expect((entry.get("enemy_data") as Resource).resource_path == ADDER_PATH, "Floor 4's second entry is the adder")
	_expect(not bool(entry.get("required")) and entry.get("position") == Vector2(11, -22.5) and is_equal_approx(float(entry.get("yaw_degrees")), -90.0), "...optional, at (11, -22.5), yaw -90")
	_completed += 1

# Won: elite rates, Glassbone 1, and Blue Fastener offered, from the Adder.
func _check_elite() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		_kill_all(controller)
		await _await_reward_screen()
		var reward: Node = _child_with_script(_field, "reward_screen.gd")
		_expect(reward != null, "Won: the reward screen")
		if reward != null:
			_expect(bool(reward.get("_elite_rates")), "...its card at the elite rates")
			_expect_eq(int(reward.get("_glassbone")), 1, "...Glassbone 1")
		var keepsake: Resource = _field.get("_pending_keepsake")
		_expect(keepsake != null and keepsake.resource_path == KEEPSAKE_PATH, "...and Blue Fastener waiting to be offered")
		_expect_eq(str(_field.get("_pending_keepsake_source")), "Adder", "...from the Adder")
		if reward != null:
			reward.call("close")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _adder() -> EnemyData:
	return load(ADDER_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

func _grace_player() -> Combatant:
	var player := Combatant.new(PLAYER_HP)
	player.has_grace = true
	return player

func _has(combatant: Combatant, path: String) -> bool:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.resource_path == path:
			return true
	return false

func _magnitude(combatant: Combatant, path: String) -> int:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.resource_path == path:
			return active.magnitude
	return 0

func _label(combatant: Combatant, path: String) -> String:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.resource_path == path:
			return active.label()
	return ""

# A new run on floor 4, the fight started on the adder with a deck of
# `card_path` alone and HP and Energy enough for anything. The
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
		if data != null and data.resource_path == ADDER_PATH:
			target = node as Node3D
	if target == null:
		_fail("no adder on floor 4")
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
	_expect(members.size() == 1 and members[0] == target, "The fight is the adder alone")
	return controller

# The first card in hand, at the adder, with Energy topped up first - and
# waited out, a strike back's beat and lunge included.
func _play_first(controller: Node, adder: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	if bool(controller.call("is_awaiting_target")):
		controller.call("confirm_target", adder)
	var start: int = Time.get_ticks_msec()
	while bool(controller.get("_input_locked")) and Time.get_ticks_msec() - start < 5000:
		await process_frame
	await create_timer(0.4).timeout

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

# What `member`'s readout shows beside its HP (EnemyStatus.get_hp_mark()).
func _hp_mark(controller: Node, member: Node) -> Dictionary:
	var statuses: Dictionary = controller.get_parent().get("_enemy_statuses")
	var status: Node = statuses.get(member)
	return status.call("get_hp_mark") if status != null else {}

func _row_has(controller: Node, member: Node, prefix: String) -> bool:
	for text: String in controller.call("get_enemy_status_labels", member):
		if text.begins_with(prefix):
			return true
	return false

# The player's standing-row line beginning with `prefix`, or null.
func _row_line(overlay: Node, prefix: String) -> Variant:
	var bar: Node = overlay.get("_field_hp_bar")
	for item: Dictionary in bar.get("_row_items"):
		if String(item.get("text", "")).begins_with(prefix):
			return item
	return null

func _kill_all(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: RefCounted = combatants.get(member)
		if combatant == null:
			continue
		combatant.set("hp", 0)
		controller.call("_report_damage", "player", combatant, 99, "card")
	controller.call("_check_battle_end")

# A fight just won: until its reward screen is up - the killing blow and
# the last death play out first - or REWARD_WAIT_SECONDS have gone.
func _await_reward_screen() -> void:
	var start: int = Time.get_ticks_msec()
	while _child_with_script(_field, "reward_screen.gd") == null and Time.get_ticks_msec() - start < int(REWARD_WAIT_SECONDS * 1000.0):
		await process_frame

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

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
