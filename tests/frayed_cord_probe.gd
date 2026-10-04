extends SceneTree

# Headless probe for Frayed Cord, the Wardling's keepsake: "At the end of
# your turn, you may keep 1 card in your hand." Its data and drop (the
# Wardling's table alone), Deck.discard_hand()'s keep, and the keep played
# through real fights: End Turn opens the choice (BattleController's
# choose mode with no armed card), End Turn again confirms - 1 card kept
# and in next turn's hand under the usual draw, or none - an empty hand
# just ends, a cancel goes back to the turn with nothing ended, and the
# hand limit holds.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/frayed_cord_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fight cases load the real region scene and start fights through
# RegionField's contact handler, as trinket_probe does. Untyped against
# anything that names the RunState autoload.

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const FRAYED_CORD_PATH := "res://run/keepsakes/frayed_cord.tres"
const ART_PATH := "res://assets/textures/keepsakes/frayed_cord.png"
const WARDLING_PATH := "res://battle/rules/enemies/wardling.tres"
const WARDLING_TABLE_PATH := "res://run/keepsakes/wardling_keepsakes.tres"
const BELONGINGS_TABLE_PATH := "res://run/keepsakes/belongings_keepsakes.tres"
const BELONGINGS_IDS: Array[StringName] = [&"bent_nail", &"white_shell", &"worn_page"]
const SLASH_PATH := "res://cards/data/slash.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
# Where a keepsake table or an enemy could be.
const SEARCH_ROOTS: Array[String] = ["res://run", "res://battle", "res://field", "res://floors"]
const TURN_DRAW := 5
const HAND_LIMIT := 10
const PROMPT_OPEN := "KEEP 0 / 1  ·  CLICK END TURN TO CONFIRM"
const PROMPT_MARKED := "KEEP 1 / 1  ·  CLICK END TURN TO CONFIRM"
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
	_check_signature_drop()
	_check_deck_keep()
	await _check_keep_one()
	await _check_keep_none()
	await _check_empty_hand()
	await _check_cancel()
	await _check_hand_limit()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("frayed_cord_probe: PASSED")
		quit(0)
	else:
		print("frayed_cord_probe: %d FAILED" % _failures)
		quit(1)

func _check_data() -> void:
	var cord: TrinketData = load(FRAYED_CORD_PATH)
	_expect_eq(cord.end_turn_keep, 1, "Frayed Cord keeps 1 card")
	_expect(cord.combat_start_status == null, "...with no status")
	_expect_eq(cord.describe(), "At the end of your turn, you may keep 1 card in your hand.", "...its description")
	_expect_eq(cord.describe_short(), "Keep 1 card at the end of each turn.", "...its short line")
	_expect(cord.art != null and cord.art.resource_path == ART_PATH, "...and its own art, frayed_cord.png")
	_completed += 1

# The Wardling's signature: its table holds Frayed Cord alone, and no
# other keepsake table, nor any other enemy's, holds it.
func _check_signature_drop() -> void:
	var cord: TrinketData = load(FRAYED_CORD_PATH)
	var wardling: EnemyData = load(WARDLING_PATH)
	_expect(wardling.keepsake_table != null and wardling.keepsake_table.resource_path == WARDLING_TABLE_PATH, "The Wardling drops from its own table")
	var table: KeepsakeTable = load(WARDLING_TABLE_PATH)
	_expect(table.guaranteed and table.entries.size() == 1 and table.entries[0].trinket == cord, "...which is Frayed Cord alone, guaranteed")
	var belongings: KeepsakeTable = load(BELONGINGS_TABLE_PATH)
	var ids: Array[StringName] = []
	for entry in belongings.entries:
		ids.append(entry.trinket.id)
	_expect_eq(ids, BELONGINGS_IDS, "The bedroll offers Bent Nail, White Shell and Worn Page")
	var tables: int = 0
	for path in _tres_under(SEARCH_ROOTS):
		var resource: Resource = load(path)
		if resource is KeepsakeTable:
			tables += 1
			if path == WARDLING_TABLE_PATH:
				continue
			for entry in (resource as KeepsakeTable).entries:
				_expect(entry.trinket != cord, "%s holds no Frayed Cord" % path)
		elif resource is EnemyData and path != WARDLING_PATH:
			_expect((resource as EnemyData).keepsake_table == null or (resource as EnemyData).keepsake_table.resource_path != WARDLING_TABLE_PATH, "%s doesn't drop from the Wardling's table" % path)
	_expect(tables >= 3, "The search found the keepsake tables (%d)" % tables)
	_completed += 1

# The keep at the Deck: one occurrence each - of two Slashes, keeping one
# discards the other.
func _check_deck_keep() -> void:
	var slash: CardData = load(SLASH_PATH)
	var brace: CardData = load(BRACE_PATH)
	var deck := Deck.new()
	deck.hand = [slash, slash, brace] as Array[CardData]
	deck.discard_hand([slash] as Array[CardData])
	_expect_eq(deck.hand, [slash] as Array[CardData], "Deck.discard_hand([Slash]) keeps one Slash")
	_expect_eq(deck.discard_pile, [slash, brace] as Array[CardData], "...and discards the other and Brace")
	deck.discard_hand()
	_expect(deck.hand.is_empty(), "With no keep, the whole hand goes")
	_completed += 1

func _check_keep_one() -> void:
	var controller: Node = await _fight_with_cord()
	if controller != null:
		var deck: Object = controller.get("deck")
		controller.call("end_turn")
		_expect(bool(controller.get("_keep_choice_open")), "End Turn with a hand opens the keep")
		_expect_eq(_prompt_text(), PROMPT_OPEN, "...prompting '%s'" % PROMPT_OPEN)
		var view: Object = _views(controller)[2]
		var kept: CardData = view.get("card_data")
		controller.call("toggle_choice", view)
		_expect(bool(view.call("is_marked")), "...a click marks a card")
		_expect_eq(_prompt_text(), PROMPT_MARKED, "...the prompt counts it")
		controller.call("toggle_choice", _views(controller)[0])
		_expect_eq(_marked_count(controller), 1, "...and a second mark past the cap does nothing")
		var discarded_copies: int = _count(deck.get("hand"), kept) - 1
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(hand.size(), 1 + TURN_DRAW, "Next turn: the kept card and the usual %d drawn" % TURN_DRAW)
		_expect(hand.has(kept), "...the kept card (%s) among them" % kept.card_name)
		_expect(_count(deck.get("discard_pile"), kept) >= discarded_copies, "...its other copies, if any, discarded")
		_expect_eq((deck.get("discard_pile") as Array).size(), TURN_DRAW - 1, "...and the other %d in the discard" % (TURN_DRAW - 1))
		_expect(not bool(controller.get("_keep_choice_open")), "...the choice closed")
	await _teardown()
	_completed += 1

func _check_keep_none() -> void:
	var controller: Node = await _fight_with_cord()
	if controller != null:
		var deck: Object = controller.get("deck")
		var before: Array = (deck.get("hand") as Array).duplicate()
		controller.call("end_turn")
		_expect(bool(controller.get("_keep_choice_open")), "Keep none: the choice opens")
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(hand.size(), TURN_DRAW, "...confirmed with none marked, next turn holds just the %d drawn" % TURN_DRAW)
		var discard: Array = deck.get("discard_pile")
		for card in before:
			_expect(discard.has(card), "...%s went to the discard" % (card as CardData).card_name)
	await _teardown()
	_completed += 1

func _check_empty_hand() -> void:
	var controller: Node = await _fight_with_cord()
	if controller != null:
		var deck: Object = controller.get("deck")
		controller.get("_hand_container").call("discard_hand")
		var turns: Array[bool] = []
		controller.connect("turn_phase_changed", func(player_turn: bool) -> void: turns.append(player_turn))
		controller.call("end_turn")
		_expect(not bool(controller.get("_keep_choice_open")), "An empty hand: no choice opens")
		_expect(turns.has(false), "...the turn ends at once")
		await _wait_unlocked(controller)
		_expect_eq((deck.get("hand") as Array).size(), TURN_DRAW, "...and the next turn draws %d" % TURN_DRAW)
	await _teardown()
	_completed += 1

func _check_cancel() -> void:
	var controller: Node = await _fight_with_cord()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var hand_before: Array = (deck.get("hand") as Array).duplicate()
		var energy: int = player.energy
		var turns: Array[bool] = []
		controller.connect("turn_phase_changed", func(player_turn: bool) -> void: turns.append(player_turn))
		controller.call("end_turn")
		controller.call("toggle_choice", _views(controller)[0])
		controller.call("cancel_choice")
		_expect(not bool(controller.get("_keep_choice_open")), "Cancel closes the keep")
		_expect(not bool(controller.get("_input_locked")) and turns.is_empty(), "...nothing of the turn ended")
		_expect_eq(deck.get("hand"), hand_before, "...the hand as it was")
		_expect_eq(_marked_count(controller), 0, "...no card left marked")
		_expect_eq(player.energy, energy, "...Energy as it was")
		_expect(not _prompt_visible(), "...and the prompt gone")
		_expect(not bool(controller.call("_choice_open")), "...so cards play again")
		controller.call("end_turn")
		_expect(bool(controller.get("_keep_choice_open")), "End Turn again opens the keep again")
		_expect_eq(_prompt_text(), PROMPT_OPEN, "...from 0 marked")
	await _teardown()
	_completed += 1

# A big draw onto a kept card stops at the hand limit, the kept card in.
func _check_hand_limit() -> void:
	var controller: Node = await _fight_with_cord()
	if controller != null:
		var deck: Object = controller.get("deck")
		var slash: CardData = load(SLASH_PATH)
		var pile: Array = deck.get("draw_pile")
		for i in 15:
			pile.append(slash)
		controller.set("turn_draw_amount", 15)
		controller.call("end_turn")
		var view: Object = _views(controller)[0]
		var kept: CardData = view.get("card_data")
		controller.call("toggle_choice", view)
		await _end_turn(controller)
		var hand: Array = deck.get("hand")
		_expect_eq(hand.size(), HAND_LIMIT, "A kept card and a draw of 15: the hand stops at %d" % HAND_LIMIT)
		_expect(hand.has(kept), "...the kept card still in it")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _fight_with_cord() -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.call("equip_keepsake", load(FRAYED_CORD_PATH))
	_run_state.set("current_floor_index", 0)
	# No zone intro: it holds the field frozen for its length.
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
	if layer.get_child_count() == 0:
		_fail("no fight started")
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	# Nobody dies of a probe's turns.
	var combatants: Dictionary = controller.get("_combatants")
	for enemy in combatants:
		combatants[enemy].set("max_hp", 999)
		combatants[enemy].set("hp", 999)
	var player: Combatant = controller.get("player")
	player.max_hp = 999
	player.hp = 999
	_expect_eq(((controller.get("deck") as Object).get("hand") as Array).size(), TURN_DRAW, "The fight opens on %d cards" % TURN_DRAW)
	return controller

# End Turn - opening or confirming the keep - and the enemy turn after it,
# until the next player turn.
func _end_turn(controller: Node) -> void:
	controller.call("end_turn")
	await _wait_unlocked(controller)

func _wait_unlocked(controller: Node) -> void:
	for i in 3000:
		await process_frame
		if not bool(controller.get("_input_locked")):
			return
	_fail("the enemy turn never handed the turn back")

func _views(controller: Node) -> Array:
	return controller.get("_hand_container").call("_card_views")

func _marked_count(controller: Node) -> int:
	var marked: int = 0
	for view in _views(controller):
		if bool(view.call("is_marked")):
			marked += 1
	return marked

func _count(cards: Array, card: CardData) -> int:
	var n: int = 0
	for c in cards:
		if c == card:
			n += 1
	return n

func _prompt() -> Label:
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0).find_child("ChoicePrompt", true, false) as Label

func _prompt_text() -> String:
	var label: Label = _prompt()
	return label.text if label != null and label.visible else ""

func _prompt_visible() -> bool:
	var label: Label = _prompt()
	return label != null and label.visible

func _tres_under(roots: Array[String]) -> Array[String]:
	var found: Array[String] = []
	var pending: Array[String] = roots.duplicate()
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			pending.append(dir_path.path_join(sub))
		for file in dir.get_files():
			if file.ends_with(".tres"):
				found.append(dir_path.path_join(file))
	return found

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
