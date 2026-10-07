extends SceneTree

# Headless probe for tempering at floor 3's wagon: the five starters'
# tempered versions as data (CardData.tempered, cards/tempered/), kept out
# of every pool, list and folder scan; RunState.temper_card() - exactly
# the cost spent, exactly one card swapped at its own deck position, once
# per card, logged; the wagon on floor 3, grounded and clear of the worn
# band; its screen - no grid while the Glassbone is short, the grid and
# the preview's hairlines while it isn't, TEMPER, the hold and the field
# lock; and a tempered Consumed card still removed after its fight.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/temper_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# Wagon, WagonScreen): a SceneTree script compiles before the autoloads
# register.

const CASES := 8
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const WAGON_SCENE_PATH := "res://field/wagon.tscn"
const TEMPERED_DIR := "res://cards/tempered/"
const CARD_DIRS: Array[String] = ["res://cards/data/", "res://cards/neutral/"]
const STARTERS: Array[String] = ["slash", "bite_down", "brace", "reckoning", "down_payment"]
# Scripts whose folder lists must leave cards/tempered/ out: the
# compendium's card_folders, both debug pickers' debug_card_dirs.
const SCANS: Dictionary = {
	"res://ui/card_compendium.gd": "card_folders",
	"res://field/region_field.gd": "debug_card_dirs",
	"res://battle/battle_overlay.gd": "debug_card_dirs",
}
const LOG_DIR := "user://temper_probe"
# Floor 3 (index 2) holds the wagon.
const WAGON_FLOOR := 2
# In the north-west pocket off the stem, set back from its mouth, its
# long axis along the pocket's curve.
const WAGON_OFFSET := Vector2(-7.3, -28.1)
const WAGON_YAW := 153.0
# Room the Wanderer has round it: footprint to the floor's ledge lines,
# and the ground this far round it is the floor, not a ridge face.
const WAGON_EDGE_CLEARANCE := 1.5
const LEAVE_INDEX := 100002
const BACK_INDEX := 100001
const TEMPER_INDEX := 100000
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
	_check_out_of_pools_and_scans()
	_check_temper_card()
	await _check_faces()
	await _load_floor_3()
	_check_wagon_placement()
	await _check_screen_short()
	await _check_screen_temper()
	await _check_consumed()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("temper_probe: PASSED")
		quit(0)
	else:
		print("temper_probe: %d FAILED" % _failures)
		quit(1)

# Each starter names its tempered version: <id>_tempered.tres, its name
# plus "+", its rarity, type, target and removal scope the original's,
# its own tempered null; and the provisional numbers. No other card has
# one.
func _check_data() -> void:
	for id in STARTERS:
		var card := load("res://cards/data/%s.tres" % id) as CardData
		var tempered: CardData = card.tempered
		_expect(tempered != null, "%s has a tempered version" % card.card_name)
		if tempered == null:
			continue
		_expect_eq(tempered.resource_path, TEMPERED_DIR + "%s_tempered.tres" % id, "...at %s_tempered.tres" % id)
		_expect_eq(tempered.card_name, card.card_name + "+", "...named %s+" % card.card_name)
		_expect_eq(tempered.rarity, card.rarity, "...its rarity")
		_expect_eq(tempered.card_type, card.card_type, "...its type")
		_expect_eq(tempered.target_type, card.target_type, "...its target")
		_expect_eq(tempered.removal_scope, card.removal_scope, "...its removal scope")
		_expect(tempered.tempered == null, "...and can't be tempered again")
		_expect_eq(tempered.art, card.art, "...its art")
	var slash: CardData = _tempered("slash")
	_expect_eq(_values(slash, CardEffect.EffectType.DAMAGE), [8], "Slash+ deals 8")
	var bite: CardData = _tempered("bite_down")
	_expect_eq(_values(bite, CardEffect.EffectType.DAMAGE), [11], "Bite Down+ deals 11")
	_expect_eq(_values(bite, CardEffect.EffectType.SELF_DAMAGE), [2], "...and loses 2 HP")
	var brace: CardData = _tempered("brace")
	_expect_eq(brace.effects.size(), 2, "Brace+ has two effects")
	_expect_eq(brace.effects[0].effect_type, CardEffect.EffectType.APPLY_STATUS_TO_TARGET, "...the Brace first")
	_expect_eq(brace.effects[0].status_data, (load("res://cards/data/brace.tres") as CardData).effects[0].status_data, "...the same status")
	_expect_eq(_values(brace, CardEffect.EffectType.DRAW), [1], "...then draw 1")
	var reckoning: CardData = _tempered("reckoning")
	var original_reckoning := load("res://cards/data/reckoning.tres") as CardData
	_expect_eq(reckoning.cost, 1, "Reckoning+ costs 1")
	_expect_eq(original_reckoning.cost, 2, "...Reckoning 2")
	_expect_eq(reckoning.description, original_reckoning.description, "...otherwise unchanged in text")
	_expect_eq(_values(reckoning, CardEffect.EffectType.TOLL_DAMAGE), _values(original_reckoning, CardEffect.EffectType.TOLL_DAMAGE), "...and in effect")
	var down: CardData = _tempered("down_payment")
	_expect_eq(_values(down, CardEffect.EffectType.SELF_DAMAGE_TOLL), [1], "Down Payment+ loses 1 HP")
	_expect_eq(down.effects[0].toll_gain, 8, "...and gains 8 Toll")
	for dir in CARD_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres") or STARTERS.has(file.get_basename()) and dir == "res://cards/data/":
				continue
			var card := load(dir + file) as CardData
			_expect(card.tempered == null, "%s has no tempered version (only the five starters do)" % card.card_name)
	for file in DirAccess.get_files_at(TEMPERED_DIR):
		if file.ends_with(".tres"):
			_expect(STARTERS.has(file.get_basename().trim_suffix("_tempered")), "cards/tempered/%s is a starter's" % file)
	_completed += 1

# No .tres or .tscn names a tempered card but its own original - so no
# pool, offer or list can hold one. No folder list the compendium or a
# debug picker scans includes cards/tempered/, and none of the cards they
# find is a tempered one.
func _check_out_of_pools_and_scans() -> void:
	var files: Array[String] = []
	_collect_resources("res://", files)
	_expect(files.size() > 50, "The resource sweep saw the project (%d files)" % files.size())
	for path in files:
		var text: String = FileAccess.get_file_as_string(path)
		var at: int = text.find(TEMPERED_DIR)
		while at >= 0:
			var end: int = text.find("\"", at)
			var named: String = text.substr(at, end - at)
			var original: String = "res://cards/data/%s.tres" % named.get_file().get_basename().trim_suffix("_tempered")
			_expect_eq(path, original, "%s is named only by its original" % named)
			at = text.find(TEMPERED_DIR, at + 1)
	for script_path: String in SCANS:
		var node: Object = (load(script_path) as GDScript).new()
		var folders: Variant = node.get(SCANS[script_path])
		var list: Array = (folders as Dictionary).keys() if folders is Dictionary else Array(folders)
		_expect(not list.is_empty(), "%s lists folders" % script_path.get_file())
		for folder: String in list:
			_expect(not folder.begins_with(TEMPERED_DIR.trim_suffix("/")), "%s's %s leaves cards/tempered/ out (%s)" % [script_path.get_file(), SCANS[script_path], folder])
			for file in ResourceLoader.list_directory(folder):
				if not file.ends_with(".tres"):
					continue
				var card := load(folder.path_join(file)) as CardData
				if card != null:
					_expect(not card.card_name.ends_with("+"), "%s finds no tempered card (%s)" % [script_path.get_file(), card.card_name])
		(node as Node).free()
	_completed += 1

# temper_card(): exactly the cost spent and exactly one card swapped, at
# its own deck position, for a fresh copy of its tempered version; all or
# nothing when it can't; never a second time; logged as "temper".
func _check_temper_card() -> void:
	RunLogger.set_output_dir(LOG_DIR)
	RunLogger.enabled = true
	_clear_log_dir()
	_new_run()
	var deck: Array = _deck()
	var before: Array = deck.duplicate()
	var index: int = _index_of(deck, "Bite Down")
	var picked: CardData = deck[index]
	_expect(_run_state.call("temper_card", picked, 1) == null, "With no Glassbone nothing is tempered")
	_expect_eq(_deck(), before, "...and the deck is untouched")
	_run_state.call("add_glassbone", 3)
	_expect(_run_state.call("temper_card", picked, 4) == null, "Short of the cost (3 of 4) nothing is tempered")
	_expect_eq(_glassbone(), 3, "...and nothing is spent")
	var tempered: CardData = _run_state.call("temper_card", picked, 2)
	_expect(tempered != null and tempered.card_name == "Bite Down+", "Tempering Bite Down gives Bite Down+")
	_expect_eq(_glassbone(), 1, "...for exactly the cost (3 - 2)")
	deck = _deck()
	_expect_eq(deck.size(), before.size(), "...the deck the same size")
	_expect(deck[index] == tempered, "...Bite Down+ where Bite Down was (%d)" % index)
	_expect(not deck.has(picked), "...Bite Down gone")
	_expect(tempered != picked.tempered, "...a copy of its own, not the shared resource")
	var others_same: bool = true
	for i in deck.size():
		if i != index and deck[i] != before[i]:
			others_same = false
	_expect(others_same, "...every other card the same object in the same place")
	_expect(_run_state.call("temper_card", tempered, 1) == null, "Bite Down+ can't be tempered again")
	_expect_eq(_glassbone(), 1, "...and nothing is spent trying")
	_expect(_run_state.call("temper_card", load("res://cards/data/slash.tres"), 1) == null, "A card not in the deck isn't tempered")
	_expect(_run_state.call("temper_card", deck[_index_of(deck, "Slash")], 0) == null, "A cost under 1 is refused")
	_expect_eq(_glassbone(), 1, "...and nothing is spent")
	var slash_a: CardData = _run_state.call("temper_card", deck[_index_of(deck, "Slash")], 1)
	_run_state.call("add_glassbone", 1)
	var slash_b: CardData = _run_state.call("temper_card", _deck()[_index_of(_deck(), "Slash")], 1)
	_expect(slash_a != null and slash_b != null and slash_a != slash_b, "Two Slashes tempered are two cards")
	_run_state.call("log_run_end", "abandoned")
	var temper_lines: Array[Dictionary] = []
	for line in _log_lines():
		if str(line.get("ev")) == "temper":
			temper_lines.append(line)
	_expect_eq(temper_lines.size(), 3, "Each temper is logged once")
	if not temper_lines.is_empty():
		var first: Dictionary = temper_lines[0]
		_expect_eq([first.get("card"), first.get("tempered"), int(first.get("glassbone_after", -1))], ["Bite Down", "Bite Down+", 1], "...with the card, its tempered name and the Glassbone after")
	RunLogger.set_output_dir("")
	_completed += 1

# Each tempered face fits as its original does: the name on one line
# beside the cost, the rules text at the first size, the card unchanged
# in size.
func _check_faces() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	for id in STARTERS:
		var tempered: CardData = _tempered(id)
		view.set_card_data(tempered)
		var lines: int = view.call("_wrapped_line_count", view.name_label, view.name_font_size_px, view.name_label.size.x)
		_expect_eq(lines, 1, "%s's name fits on one line beside its cost" % tempered.card_name)
		_expect_eq(view.rules_text.get_theme_font_size("normal_font_size"), 15, "%s's rules size" % tempered.card_name)
		_expect_eq(view.size, view.card_size, "%s keeps the card's size" % tempered.card_name)
	view.free()
	_completed += 1

# The wagon: floor 3's second prop at (-7.3, -28.1) from spawn, yaw 153,
# grounded by its footprint on the floor, WAGON_EDGE_CLEARANCE from every
# ledge line and on flat floor that far round, MAKE_STATIC, its footprint
# clear of the worn band's visible edge.
func _check_wagon_placement() -> void:
	var wagons: Array[Node] = get_nodes_in_group("wagons")
	_expect_eq(wagons.size(), 1, "Floor 3 has one wagon")
	if wagons.is_empty():
		_completed += 1
		return
	var wagon := wagons[0] as Node3D
	var spawn: Vector3 = _field.call("get_spawn_position")
	var offset := Vector2(wagon.global_position.x - spawn.x, wagon.global_position.z - spawn.z)
	_expect(offset.distance_to(WAGON_OFFSET) < 0.01, "...at %s from spawn (got %s)" % [WAGON_OFFSET, offset])
	_expect(is_equal_approx(float(wagon.get("yaw_degrees")), WAGON_YAW), "...yaw %.0f along the pocket's curve" % WAGON_YAW)
	_expect_eq(wagon.get("world_line"), "A wagon, unhitched. The tools are still on it.", "...with its approach line")
	var body := wagon.find_child("Collision", true, false) as StaticBody3D
	_expect(body != null and body.disable_mode == CollisionObject3D.DISABLE_MODE_MAKE_STATIC, "...its collision MAKE_STATIC")
	var ground: Node = _field.get_node("Ground")
	# Grounded by its footprint: no bottom corner above the sand, none
	# buried past the sink plus the roll's dip.
	var half := Vector2(float(wagon.get("body_width")) * 0.5, float(wagon.get("body_length")) * 0.5)
	var pose := wagon.get_node("Pose") as Node3D
	var deepest: float = float(wagon.get("sink_depth")) + half.x * sin(deg_to_rad(float(wagon.get("roll_degrees")))) + 0.03
	for corner: Vector3 in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y)]:
		var point: Vector3 = pose.global_transform * corner
		var under: float = float(ground.call("get_height_at", Vector2(point.x, point.z)))
		_expect(point.y <= under + 0.01, "...its corner %s on or in the sand (%.3f over it)" % [corner, point.y - under])
		_expect(point.y >= under - deepest, "...and not buried past its sink and roll (%.3f under)" % [under - point.y])
	# Room to walk round it: every point of its footprint at least
	# WAGON_EDGE_CLEARANCE from the floor's ledge lines, and the ground that
	# far round it within 0.3 m of its base - floor, not a ridge face.
	var footprint: Array[Vector2] = []
	for u in 5:
		for v in 9:
			var local := Vector3(lerpf(-half.x, half.x, float(u) / 4.0), 0, lerpf(-half.y, half.y, float(v) / 8.0))
			var point: Vector3 = wagon.global_transform * local
			footprint.append(Vector2(point.x - spawn.x, point.z - spawn.z))
	var to_ledge: float = INF
	var ledges: Array = (_field.call("get_floor_data") as Resource).get("ledges")
	_expect(not ledges.is_empty(), "...floor 3 has its ledge lines")
	for ledge: PackedVector2Array in ledges:
		for i in ledge.size() - 1:
			for p in footprint:
				to_ledge = minf(to_ledge, _segment_distance(p, ledge[i], ledge[i + 1]))
	_expect(to_ledge >= WAGON_EDGE_CLEARANCE, "...%.1f m or more from the floor's edge (%.2f m)" % [WAGON_EDGE_CLEARANCE, to_ledge])
	var flat: bool = true
	var ring: float = WAGON_EDGE_CLEARANCE
	# That far from the footprint: off each side's middle, and off each
	# corner along its diagonal.
	var diagonal: float = ring / sqrt(2.0)
	for corner: Vector3 in [Vector3(-half.x - diagonal, 0, -half.y - diagonal), Vector3(half.x + diagonal, 0, -half.y - diagonal), Vector3(-half.x - diagonal, 0, half.y + diagonal), Vector3(half.x + diagonal, 0, half.y + diagonal), Vector3(-half.x - ring, 0, 0), Vector3(half.x + ring, 0, 0), Vector3(0, 0, -half.y - ring), Vector3(0, 0, half.y + ring)]:
		var point: Vector3 = wagon.global_transform * corner
		if absf(float(ground.call("get_height_at", Vector2(point.x, point.z))) - wagon.global_position.y) > 0.3:
			flat = false
	_expect(flat, "...on flat floor %.1f m round it, off the ridge faces" % ring)
	var floor_data: Resource = _field.call("get_floor_data")
	var band: PackedVector2Array = floor_data.get("wear_path_override")
	var clearance: float = float(ground.get("wear_half_width")) + float(ground.get("wear_edge_noise_amplitude"))
	var nearest: float = INF
	for corner: Vector3 in [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y), Vector3(-half.x, 0, half.y), Vector3(half.x, 0, half.y)]:
		var point: Vector3 = wagon.global_transform * corner
		nearest = minf(nearest, _band_distance(band, Vector2(point.x - spawn.x, point.z - spawn.z)))
	_expect(nearest > clearance, "...its footprint off the worn band (%.2f m from its centre line, band edge %.2f)" % [nearest, clearance])
	_completed += 1

# Glassbone short: EMPTY - the count, the empty line, no grid built. The
# field locks while it's open; ui_cancel closes it and unlocks.
func _check_screen_short() -> void:
	_run_state.set("glassbone", 0)
	var screen: Node = await _open_screen()
	if screen == null:
		_completed += 1
		return
	_expect_eq(screen.get("layer"), 100, "The screen is on layer 100")
	_expect_eq(_field.process_mode, Node.PROCESS_MODE_DISABLED, "...the field locked under it")
	_expect_eq(screen.call("get_mode"), "EMPTY", "With no Glassbone it shows no grid")
	_expect_eq(screen.call("get_world_line"), "The tools are laid out. There is nothing here to work.", "...the no-Glassbone line")
	_expect_eq(_card_views(screen).size(), 0, "...and builds no card")
	await _press("ui_cancel")
	_expect(not is_instance_valid(screen) or screen.is_queued_for_deletion(), "Escape closes it")
	_expect_eq(_field.process_mode, Node.PROCESS_MODE_INHERIT, "...and the field unlocks")
	_completed += 1

# One Glassbone: the grid by name, only the untempered starters pickable;
# a pick previews with the hairlines; BACK spends nothing; TEMPER spends
# exactly one and swaps exactly the picked card at its place, holds
# (LEAVE refused), then EMPTY. The tempered card is dimmed next time.
func _check_screen_temper() -> void:
	_new_run_on_field()
	_run_state.call("add_glassbone", 1)
	var screen: Node = await _open_screen()
	if screen == null:
		_completed += 1
		return
	_expect_eq(screen.call("get_mode"), "GRID", "With 1 Glassbone it shows the grid")
	_expect_eq(screen.call("get_world_line"), "Someone worked it here. The tools still fit the hand.", "...the working line")
	var grid: Array = screen.call("get_grid_cards")
	var names: Array[String] = []
	for card: CardData in grid:
		names.append(card.card_name)
	var sorted: Array[String] = names.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)
	_expect_eq(names, sorted, "...sorted by name")
	_expect_eq(grid.size(), _deck().size(), "...every card in the deck")
	var views: Array = screen.get("_views")
	for i in grid.size():
		var card: CardData = grid[i]
		_expect_eq(views[i].modulate.a < 1.0, card.tempered == null, "%s is %s" % [card.card_name, "dimmed" if card.tempered == null else "pickable"])
	for id in STARTERS:
		var name: String = (load("res://cards/data/%s.tres" % id) as CardData).card_name
		await _preview(screen, name)
		_expect_eq(screen.call("get_mode"), "PREVIEW", "Picking %s previews it" % name)
		var after: CardView = screen.get("_after_view")
		var text: String = after.rules_text.text
		var cost_mark: Variant = screen.get("_cost_mark")
		match id:
			"slash":
				_expect_eq(text, "Deal [u]8[/u] damage.", "...Slash+ underlines its 8")
			"bite_down":
				_expect_eq(text, "Deal [u]11[/u] damage.\nThen lose 2 HP.", "...Bite Down+ underlines its 11 alone")
			"brace":
				_expect(text.ends_with("\n[u]Draw 1.[/u]") and text.count("[u]") == 1, "...Brace+ underlines its added line whole (%s)" % text)
			"reckoning":
				_expect(not text.contains("[u]"), "...Reckoning+ underlines no rules text")
				_expect(cost_mark != null, "...but its cost")
			"down_payment":
				_expect(text.begins_with("Gain [u]8[/u] ") and text.count("[u]") == 1, "...Down Payment+ underlines its 8 (%s)" % text)
		if id != "reckoning":
			_expect(cost_mark == null, "...and no cost (it's the same)")
		screen.call("_activate", BACK_INDEX)
		await process_frame
		_expect_eq(screen.call("get_mode"), "GRID", "...BACK returns to the grid")
	_expect_eq(_glassbone(), 1, "Previewing spent nothing")
	var deck_before: Array = _deck().duplicate()
	await _preview(screen, "Bite Down")
	var picked: CardData = screen.call("get_picked")
	var position: int = deck_before.find(picked)
	screen.call("_activate", TEMPER_INDEX)
	await process_frame
	_expect_eq(screen.call("get_mode"), "HELD", "TEMPER holds the tempered card")
	_expect_eq(screen.call("get_world_line"), "It holds.", "...under its line")
	_expect_eq(_glassbone(), 0, "...spending exactly 1")
	var deck: Array = _deck()
	var changed: Array[int] = []
	for i in deck.size():
		if deck[i] != deck_before[i]:
			changed.append(i)
	_expect_eq(changed, [position] as Array[int], "...swapping exactly the picked card, in its place")
	_expect_eq((deck[position] as CardData).card_name, "Bite Down+", "...for Bite Down+")
	screen.call("close")
	await _press("ui_cancel")
	_expect(is_instance_valid(screen) and not screen.is_queued_for_deletion(), "Neither LEAVE nor Escape closes it mid-temper")
	await create_timer(float(_wagon().get("held_seconds")) + 0.3).timeout
	_expect_eq(screen.call("get_mode"), "EMPTY", "After the hold, short of Glassbone: the no-Glassbone line")
	_run_state.call("add_glassbone", 1)
	screen.call("_enter_rest_mode")
	grid = screen.call("get_grid_cards")
	views = screen.get("_views")
	var tempered_index: int = -1
	for i in grid.size():
		if (grid[i] as CardData).card_name == "Bite Down+":
			tempered_index = i
	_expect(tempered_index >= 0 and views[tempered_index].modulate.a < 1.0, "Bite Down+ shows dimmed in the grid")
	screen.call("_activate", tempered_index)
	await process_frame
	_expect_eq(screen.call("get_mode"), "GRID", "...and can't be picked")
	screen.call("_activate", LEAVE_INDEX)
	await process_frame
	_expect_eq(_field.process_mode, Node.PROCESS_MODE_INHERIT, "LEAVE closes it and unlocks the field")
	_completed += 1

# A Consumed card, tempered, is the deck's own object: played into a
# fight's exhaust pile, the fight's end removes exactly it.
func _check_consumed() -> void:
	_new_run_on_field()
	var tempered := CardData.new()
	tempered.card_name = "Probe Ember+"
	tempered.rarity = CardData.CardRarity.COMMON
	tempered.removal_scope = CardData.RemovalScope.CONSUMED
	var original := CardData.new()
	original.card_name = "Probe Ember"
	original.rarity = CardData.CardRarity.COMMON
	original.removal_scope = CardData.RemovalScope.CONSUMED
	original.tempered = tempered
	var copy: CardData = _run_state.call("add_card", original)
	_run_state.call("add_glassbone", 1)
	var swapped: CardData = _run_state.call("temper_card", copy, 1)
	_expect(swapped != null and swapped.removal_scope == CardData.RemovalScope.CONSUMED, "A Consumed card tempers into a Consumed card")
	var size_before: int = _deck().size()
	var fight := Deck.new(_deck() as Array[CardData])
	_expect(fight.draw_pile.has(swapped), "The next fight's piles hold the tempered card itself")
	fight.draw_pile.erase(swapped)
	fight.hand.append(swapped)
	fight.exhaust(swapped)
	_field.call("_apply_consumed_removals", fight)
	_expect(not _deck().has(swapped), "Its fight's end removes it from the deck")
	_expect(not _deck().has(copy), "...the original long gone")
	_expect_eq(_deck().size(), size_before - 1, "...and nothing else")
	_completed += 1

# --- Helpers ---

func _new_run() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", WAGON_FLOOR)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)

# A new run under the loaded field (the floor stays as it is).
func _new_run_on_field() -> void:
	_new_run()

func _load_floor_3() -> void:
	_new_run()
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 30:
		await physics_frame

func _wagon() -> Node:
	var wagons: Array[Node] = get_nodes_in_group("wagons")
	return wagons[0] if not wagons.is_empty() else null

func _open_screen() -> Node:
	var wagon: Node = _wagon()
	if wagon == null:
		_fail("no wagon to open")
		return null
	_expect(_field.call("open_wagon_screen", wagon), "The wagon's screen opens")
	await process_frame
	var screen: Node = _field.get_node_or_null("WagonScreen")
	if screen == null:
		_fail("no WagonScreen under the field")
	return screen

func _preview(screen: Node, card_name: String) -> void:
	var grid: Array = screen.call("get_grid_cards")
	for i in grid.size():
		if (grid[i] as CardData).card_name == card_name:
			screen.call("_activate", i)
			break
	await process_frame

func _card_views(screen: Node) -> Array[Node]:
	return screen.find_children("*", "CardView", true, false)

func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	await process_frame
	await process_frame

func _tempered(id: String) -> CardData:
	return (load("res://cards/data/%s.tres" % id) as CardData).tempered

func _values(card: CardData, type: CardEffect.EffectType) -> Array[int]:
	var values: Array[int] = []
	for effect in card.effects:
		if effect.effect_type == type:
			values.append(effect.value)
	return values

func _deck() -> Array:
	return _run_state.get("deck")

func _glassbone() -> int:
	return int(_run_state.get("glassbone"))

func _index_of(deck: Array, card_name: String) -> int:
	for i in deck.size():
		if (deck[i] as CardData).card_name == card_name:
			return i
	return -1

func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var t: float = clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.000001), 0.0, 1.0)
	return p.distance_to(a + ab * t)

# Distance to the floor's three-point worn band (Ground's quadratic
# through its middle point - ground.gdshader's wear_curve_point()).
func _band_distance(points: PackedVector2Array, p: Vector2) -> float:
	var start: Vector2 = points[0]
	var end: Vector2 = points[2]
	var control: Vector2 = 2.0 * points[1] - 0.5 * (start + end)
	var best: float = INF
	for i in 401:
		var t: float = float(i) / 400.0
		var u: float = 1.0 - t
		best = minf(best, p.distance_to(u * u * start + 2.0 * u * t * control + t * t * end))
	return best

func _collect_resources(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "reference" or sub == "addons":
			continue
		_collect_resources(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres") or file.ends_with(".tscn"):
			out.append(dir.path_join(file))

func _clear_log_dir() -> void:
	var dir := DirAccess.open(LOG_DIR)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)

func _log_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for file in DirAccess.get_files_at(LOG_DIR):
		for raw in FileAccess.get_file_as_string(LOG_DIR.path_join(file)).split("\n", false):
			var parsed: Variant = JSON.parse_string(raw)
			if parsed is Dictionary:
				lines.append(parsed)
	return lines

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s - got %s, expected %s" % [message, str(actual), str(expected)])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
