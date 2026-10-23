extends SceneTree

# Core probe: what the run earns and spends, through the game's own
# screens, on the floor whose FloorData places a collector:
#
#   reward   - a won fight's reward screen: its gold taken is the run's,
#              its card taken joins the deck
#   cards    - the collector's first card bought: its price spent, the
#              deck one up
#   replace  - with a worn piece and a keepsake already held (any not on
#              the shop's tables), the shop's worn piece, keepsake and
#              weapon bought: each price spent, each one now the run's -
#              the old ones replaced, max HP following the worn pieces'
#              bonuses
#   bedroll  - the Bedroll bought: carried, its price spent
#   removal  - a card removed: its price spent, exactly that card gone
#   temper   - a deck card with a tempered version tempered at the
#              wagon's cost: the Glassbone spent, the card swapped in place
#
# Every price and number read from the collector, the items and the cards
# - none pinned. A script error fails it too (tools/run_probes.sh).
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/economy_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# Collector, CollectorScreen).

const REGION_PATH := "res://floors/region1.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const COLLECTOR_SCENE_PATH := "res://field/collector.tscn"
const WAGON_SCENE_PATH := "res://field/wagon.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const ARMOR_DIR := "res://run/armor/"
const KEEPSAKES_DIR := "res://run/keepsakes/"
# CollectorScreen.Kind, read off its lines untyped.
const KIND_WORN := 0
const KIND_KEEPSAKE := 1
const KIND_WEAPON := 2
const KIND_REMOVAL := 3
const KIND_BEDROLL := 4
const PURSE := 5000
const REWARD_WAIT_SECONDS := 8.0
const SAFETY_SECONDS := 180.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _cases: int = 0
# The run's gold as the last good's TAKE was pressed (_buy_line()).
var _gold_before: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var floor_index: int = _collector_floor()
	_expect(floor_index >= 0, "A floor places a collector")
	if floor_index >= 0:
		await _load(floor_index)
		await _check_reward()
		await _check_collector()
		await _teardown()
	_check_temper()
	if _cases != 6:
		_fail("%d of 6 cases ran to their end" % _cases)
	if _failures == 0:
		print("economy_probe: PASSED")
		quit(0)
	else:
		print("economy_probe: %d FAILED" % _failures)
		quit(1)

# --- reward ---

func _check_reward() -> void:
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		if _field.is_ancestor_of(node) and bool(node.get("required")):
			target = node as Node3D
			break
	var controller: Node = await ProbePlay.start_fight(self, _field, target) if target != null else null
	if controller == null:
		_fail("reward: no fight opened")
		return
	var combatants: Dictionary = controller.get("_combatants")
	for member in (controller.get("enemies") as Array).duplicate():
		var combatant: Combatant = combatants.get(member)
		combatant.hp = 0
		controller.call("_report_damage", "player", combatant, combatant.max_hp, "card")
	controller.call("_check_battle_end")
	var reward: Node = await _await_child("reward_screen.gd", REWARD_WAIT_SECONDS)
	_expect(reward != null, "reward: the win opens the reward screen")
	if reward == null:
		return
	var gold_before: int = int(_run_state.get("gold"))
	var deck_before: int = (_run_state.get("deck") as Array).size()
	var gold: int = int(reward.get("_gold"))
	var lines: Array = reward.get("_lines")
	for index in lines.size():
		var id: String = str((lines[index] as RefCounted).get("id"))
		if id == "gold":
			reward.call("_take_line", index)
			_expect_eq(int(_run_state.get("gold")), gold_before + gold, "reward: the gold taken is the run's")
		elif id == "card":
			reward.call("_take_line", index)
			var views: Array = reward.get("_card_views")
			if not views.is_empty():
				var first: CardView = views[0]
				reward.call("_on_choice_clicked", first.card_data, first)
				await ProbePlay.wait_until(self, func() -> bool: return (_run_state.get("deck") as Array).size() > deck_before, 3.0)
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before + 1, "reward: the card taken joins the deck")
	var reward_ref: WeakRef = weakref(reward)
	await ProbePlay.wait_until(self, func() -> bool:
		var live: Node = reward_ref.get_ref() as Node
		return live == null or live.is_queued_for_deletion(), 5.0)
	var offer: Node = _child_with_script(_field, "keepsake_offer.gd")
	if offer != null:
		offer.call("_activate", 1)
	await ProbePlay.wait_until(self, func() -> bool: return not bool(_field.get("_battle_open")), 5.0)
	for i in 10:
		await physics_frame
	_cases += 1

# --- the collector ---

func _check_collector() -> void:
	var collector: Node = _find_collector(_field)
	if collector == null:
		_fail("collector: none on its floor")
		return
	collector.set("weapon_chance", 1.0)
	var old_worn: TrinketData = _held_elsewhere(ARMOR_DIR, TrinketData.Slot.WORN, str(collector.get("worn_table_path")))
	var old_keepsake: TrinketData = _held_elsewhere(KEEPSAKES_DIR, TrinketData.Slot.KEEPSAKE, str(collector.get("keepsake_table_path")))
	if old_worn != null:
		_run_state.call("equip_worn", old_worn)
	if old_keepsake != null:
		_run_state.call("equip_keepsake", old_keepsake)
	var old_weapon: WeaponData = _run_state.get("weapon")
	var base_max_hp: int = int(_run_state.get("player_max_hp")) - (old_worn.max_hp_bonus if old_worn != null else 0)
	_run_state.call("add_gold", PURSE)
	# The stock rolled as the floor loaded: again, at this chance and with
	# these pieces held.
	collector.call("reroll_stock")
	var screen: Node = _open(collector)
	if screen == null:
		return

	# --- cards ---
	var cards: Array = screen.call("get_slot_cards")
	if not cards.is_empty() and cards[0] != null:
		var price: int = int(screen.call("price_at", 0))
		var gold: int = int(_run_state.get("gold"))
		var deck: int = (_run_state.get("deck") as Array).size()
		screen.call("activate", 0)
		screen.call("take_open_card")
		_expect_eq(int(_run_state.get("gold")), gold - price, "cards: its price spent")
		_expect_eq((_run_state.get("deck") as Array).size(), deck + 1, "cards: the deck one up")
	else:
		_fail("cards: none on offer")
	_cases += 1

	# --- replace ---
	for kind in [KIND_WORN, KIND_KEEPSAKE, KIND_WEAPON]:
		var line: int = _line_of_kind(screen, kind)
		if line < 0:
			_fail("replace: no good of kind %d on offer" % kind)
			continue
		var item: Resource = ((screen.call("get_lines") as Array)[line] as Dictionary)["good"].item
		var price: int = int(screen.call("line_price", line))
		await _buy_line(screen, line)
		_expect_eq(int(_run_state.get("gold")), _gold_before - price, "replace: %s for its price" % str(item.get("display_name")))
		match kind:
			KIND_WORN:
				_expect(_run_state.get("worn") == item and item != old_worn, "replace: the worn piece bought replaces the one worn")
				_expect_eq(int(_run_state.get("player_max_hp")), base_max_hp + maxi((item as TrinketData).max_hp_bonus, 0), "replace: max HP follows the worn pieces' bonuses")
			KIND_KEEPSAKE:
				_expect(_run_state.get("keepsake") == item and item != old_keepsake, "replace: the keepsake bought replaces the one held")
			KIND_WEAPON:
				_expect(_run_state.get("weapon") == item and item != old_weapon, "replace: the weapon bought replaces the one carried")
	_cases += 1

	# --- bedroll ---
	var bedroll_line: int = _line_of_kind(screen, KIND_BEDROLL)
	if bedroll_line < 0:
		_fail("bedroll: not on offer")
	else:
		var price: int = int(screen.call("line_price", bedroll_line))
		await _buy_line(screen, bedroll_line)
		_expect(bool(_run_state.get("has_bedroll")), "bedroll: carried")
		_expect_eq(int(_run_state.get("gold")), _gold_before - price, "bedroll: its price spent")
	_cases += 1

	# --- removal ---
	var removal_line: int = _line_of_kind(screen, KIND_REMOVAL)
	if removal_line < 0:
		_fail("removal: not on offer")
	else:
		var price: int = int(screen.call("line_price", removal_line))
		var gold: int = int(_run_state.get("gold"))
		var deck_before: Array = (_run_state.get("deck") as Array).duplicate()
		screen.call("activate", int(screen.call("line_focus_index", removal_line)))
		var picker: Node = screen.call("get_picker")
		var views: Array = picker.call("get_card_views") if picker != null else []
		if views.is_empty():
			_fail("removal: the picker shows no deck")
		else:
			await ProbePlay.wait_until(self, func() -> bool: return not bool(picker.get("_inspect_busy")), 3.0)
			var view: CardView = views[0]
			view.emit_signal("clicked", view.card_data)
			await ProbePlay.wait_until(self, func() -> bool: return not bool(picker.get("_inspect_busy")) and picker.call("get_pending_pick") != null, 3.0)
			var handed: CardData = picker.call("get_pending_pick")
			_expect(handed != null, "removal: a card clicked waits for its confirm")
			picker.call("confirm_pick")
			await process_frame
			_expect_eq(int(_run_state.get("gold")), gold - price, "removal: its price spent")
			_expect_eq((_run_state.get("deck") as Array).size(), deck_before.size() - 1, "removal: one card gone")
			_expect(handed != null and not (_run_state.get("deck") as Array).has(handed), "removal: that very card")
	_cases += 1
	screen.call("close")
	await process_frame

# --- temper ---

func _check_temper() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var wagon: Node = (load(WAGON_SCENE_PATH) as PackedScene).instantiate()
	var cost: int = int(wagon.get("temper_cost"))
	wagon.free()
	var deck: Array = _run_state.get("deck")
	var index: int = -1
	for i in deck.size():
		if (deck[i] as CardData).tempered != null:
			index = i
			break
	if index < 0:
		_fail("temper: no card in the starting deck tempers")
		_cases += 1
		return
	var card: CardData = deck[index]
	_run_state.call("add_glassbone", cost)
	var before: int = int(_run_state.get("glassbone"))
	var tempered: CardData = _run_state.call("temper_card", card, cost)
	_expect(tempered != null and tempered != card.tempered and tempered.card_name == card.tempered.card_name, "temper: %s becomes a copy of its tempered version" % card.card_name)
	_expect_eq(int(_run_state.get("glassbone")), before - cost, "temper: the wagon's cost in Glassbone spent")
	_expect((_run_state.get("deck") as Array)[index] == tempered, "temper: in the card's own place")
	_cases += 1

# --- Helpers ---

# A good's line chosen, its plate's TAKE pressed, the plate gone.
func _buy_line(screen: Node, line: int) -> void:
	_gold_before = int(_run_state.get("gold"))
	screen.call("activate", int(screen.call("line_focus_index", line)))
	var offer: Node = screen.call("get_offer")
	if offer == null:
		_fail("a good's line opened no plate")
		return
	(offer.call("get_plate") as Node).call("activate", 0)
	await ProbePlay.wait_until(self, func() -> bool: return screen.call("get_offer") == null, 3.0)

func _line_of_kind(screen: Node, kind: int) -> int:
	var lines: Array = screen.call("get_lines")
	for index in lines.size():
		if int((lines[index] as Dictionary)["kind"]) == kind:
			return index
	return -1

# The first floor whose FloorData places a collector, by index; -1.
func _collector_floor() -> int:
	var floors: Array = (load(REGION_PATH) as Resource).get("floors")
	for index in floors.size():
		for prop in (floors[index] as Resource).get("props"):
			var scene: PackedScene = prop.get("scene") if prop != null else null
			if scene != null and scene.resource_path == COLLECTOR_SCENE_PATH:
				return index
	return -1

func _find_collector(parent: Node) -> Node:
	var stack: Array[Node] = [parent]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		var script: Script = node.get_script()
		if script != null and str(script.resource_path).ends_with("field/collector.gd"):
			return node
		stack.append_array(node.get_children())
	return null

# A trinket of `slot` under `dir` that the table at `table_path` doesn't
# hold - something to be holding when the shop's is bought.
func _held_elsewhere(dir: String, slot: TrinketData.Slot, table_path: String) -> TrinketData:
	var table := load(table_path) as KeepsakeTable
	var stack: Array[String] = [dir]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		for sub in DirAccess.get_directories_at(current):
			stack.append(current.path_join(sub))
		for file in DirAccess.get_files_at(current):
			if not file.ends_with(".tres"):
				continue
			var trinket := load(current.path_join(file)) as TrinketData
			if trinket == null or trinket.slot != slot:
				continue
			var listed: bool = false
			if table != null:
				for entry in table.entries:
					if entry != null and entry.trinket == trinket:
						listed = true
			if not listed:
				return trinket
	return null

func _open(collector: Node) -> Node:
	if not bool(_field.call("open_collector_screen", collector)):
		_fail("collector: open_collector_screen refused")
		return null
	var screen: Node = _child_with_script(_field, "collector_screen.gd")
	if screen == null:
		_fail("collector: no screen opened")
	return screen

func _load(floor_index: int) -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", floor_index)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	await ProbePlay.wait_until(self, func() -> bool: return not bool(_field.call("is_arrival_held")), 10.0)

func _await_child(suffix: String, timeout_sec: float) -> Node:
	var found: Array[Node] = [null]
	await ProbePlay.wait_until(self, func() -> bool:
		found[0] = _child_with_script(_field, suffix)
		return found[0] != null, timeout_sec)
	return found[0]

func _child_with_script(parent: Node, suffix: String) -> Node:
	for child in parent.get_children():
		var script: Script = child.get_script()
		if script != null and str(script.resource_path).ends_with(suffix) and not child.is_queued_for_deletion():
			return child
	return null

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
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
