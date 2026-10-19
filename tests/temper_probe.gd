extends SceneTree

# Headless probe for tempering at floor 3's wagon: every card's tempered
# version as data (CardData.tempered, cards/tempered/), kept out
# of every pool, list and folder scan; RunState.temper_card() - exactly
# the cost spent, exactly one card swapped at its own deck position, once
# per card, logged; the workbench on floor 3 - grounded on walkable
# ground inside the walls, reached from spawn, and the handcart, where
# there is one, grounded and tipped onto its shafts; its screen - no grid while the Glassbone is short, the grid and
# the preview's hairlines while it isn't, TEMPER, the hold and the field
# lock; a tempered Consumed card still removed after its fight; and the
# Cards screen's TEMPERED toggle.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/temper_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload (RegionField,
# Wagon, WagonScreen): a SceneTree script compiles before the autoloads
# register.

const CASES := 9
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const WAGON_SCENE_PATH := "res://field/wagon.tscn"
const COMPENDIUM_SCENE_PATH := "res://ui/card_compendium.tscn"
const TEMPERED_DIR := "res://cards/tempered/"
const CARD_DIRS: Array[String] = ["res://cards/data/", "res://cards/neutral/"]
const STARTERS: Array[String] = ["slash", "bite_down", "brace", "settled_account", "down_payment"]
# The smallest rules size a tempered face may shrink to and still read.
const MIN_RULES_SIZE := 13
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
# How far into the sand a wheel or a shaft tip may sit: the cart's sink
# plus its roll's dip at the wheels, and a margin.
const CART_SUNK_MAX := 0.09
# The handcart glb's own points (model frame): a wheel's lowest point
# either side of the axle, and the shaft tips - Handcart's defaults.
const CART_WHEEL_LOW: Array[Vector3] = [Vector3(-0.636, 0.001, -0.69), Vector3(-0.636, 0.001, 0.69)]
const CART_TIPS: Array[Vector3] = [Vector3(1.495, 0.401, -0.341), Vector3(1.495, 0.401, 0.341)]
const LEAVE_INDEX := 100002
const BACK_INDEX := 100001
const TEMPER_INDEX := 100000
const SAFETY_SECONDS := 300.0

# This process's log folder: run_probes.sh's per-process --runlog-dir
# (RunLogger.dir_override()) when it hands one over, so a second copy of
# this probe running at once never sees this one's files - else LOG_DIR.
var _log_dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
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
	await _check_compendium()
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

# Every card that names a tempered version: <id>_tempered.tres, its name
# plus "+", its rarity, type, removal scope and art the original's, its
# own tempered null - its target may differ, and it may drop Spent (never
# gain it, or move to another scope). Each starter has one; and the
# provisional numbers.
func _check_data() -> void:
	for id in STARTERS:
		_expect(_tempered(id) != null, "%s has a tempered version" % id)
	for card in _tempered_originals():
		var id: String = card.resource_path.get_file().get_basename()
		var tempered: CardData = card.tempered
		_expect_eq(tempered.resource_path, TEMPERED_DIR + "%s_tempered.tres" % id, "...at %s_tempered.tres" % id)
		_expect_eq(tempered.card_name, card.card_name + "+", "...named %s+" % card.card_name)
		_expect_eq(tempered.rarity, card.rarity, "...its rarity")
		_expect_eq(tempered.card_type, card.card_type, "...its type")
		# A temper may drop Spent (Leverage+), never gain it or move to
		# another scope.
		var drops_spent: bool = card.removal_scope == CardData.RemovalScope.SPENT and tempered.removal_scope == CardData.RemovalScope.NONE
		_expect(tempered.removal_scope == card.removal_scope or drops_spent, "...its removal scope, or Spent dropped (%d from %d)" % [tempered.removal_scope, card.removal_scope])
		_expect(tempered.tempered == null, "...and can't be tempered again")
		_expect_eq(tempered.art, card.art, "...its art")
	var slash: CardData = _tempered("slash")
	_expect_eq(_values(slash, CardEffect.EffectType.DAMAGE), [9], "Slash+ deals 9")
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
	for file in DirAccess.get_files_at(TEMPERED_DIR):
		if file.ends_with(".tres"):
			var named: bool = false
			for card in _tempered_originals():
				named = named or card.tempered.resource_path == TEMPERED_DIR + file
			_expect(named, "cards/tempered/%s is some card's tempered version" % file)
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
			# The original may live in any card folder (cards/data/, cards/neutral/).
			var original_file: String = named.get_file().get_basename().trim_suffix("_tempered") + ".tres"
			_expect(CARD_DIRS.has(path.get_base_dir() + "/") and path.get_file() == original_file, "%s is named only by its original (named by %s)" % [named, path])
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
	RunLogger.set_output_dir(_log_dir)
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

# Each tempered face fits: the name on one line beside the cost, the
# rules text at MIN_RULES_SIZE or above, the card unchanged in size.
func _check_faces() -> void:
	var view: CardView = (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(view)
	await process_frame
	for card in _tempered_originals():
		var tempered: CardData = card.tempered
		view.set_card_data(tempered)
		var lines: int = view.call("_wrapped_line_count", view.name_label, view.name_font_size(), view.name_label.size.x)
		_expect_eq(lines, 1, "%s's name fits on one line beside its cost" % tempered.card_name)
		var rules_size: int = view.rules_text.get_theme_font_size("normal_font_size")
		_expect(rules_size >= MIN_RULES_SIZE, "%s's rules size %d, at least %d (else its text is too long)" % [tempered.card_name, rules_size, MIN_RULES_SIZE])
		_expect_eq(view.size, view.card_size, "%s keeps the card's size" % tempered.card_name)
	view.free()
	_completed += 1

# The Cards screen's TEMPERED: off on open, no "+" face in the grid; Tab
# turns it on - Slash shows Slash+ and Carve Carve+, their numbers
# underlined, Reckoning+ its cost, a card with none as it was when one
# is left (the first such in the grid, so the check never names one that
# later gets a tempered version), no entry added; kept through a rebuild;
# a click turns it off again, marks and all; the scroll kept across a
# toggle; a lifted card put away by one.
func _check_compendium() -> void:
	var compendium: Node = (load(COMPENDIUM_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(compendium)
	await process_frame
	var count: int = _compendium_views(compendium).size()
	_expect(count > 0, "The compendium shows cards (%d)" % count)
	_expect(not bool(compendium.call("is_showing_tempered")), "TEMPERED is off on open")
	_expect_no_tempered_faces(compendium, "Off on open")
	# The first card with no tempered version, or "" once every card has one.
	var untouched: String = _untempered_name(compendium)
	var label := compendium.get_node("Page/TemperedItem/Label") as Label
	var hairline := compendium.get_node("Page/TemperedItem/Hairline") as ColorRect
	_expect_eq(label.text, "TEMPERED", "TEMPERED sits beside BACK")
	_expect_eq(label.get_theme_color("font_color"), compendium.get("grey"), "...grey while off")
	_expect(not hairline.visible, "...without its hairline")

	await _press("ui_focus_next")
	_expect(bool(compendium.call("is_showing_tempered")), "Tab turns TEMPERED on")
	label = compendium.get_node("Page/TemperedItem/Label") as Label
	hairline = compendium.get_node("Page/TemperedItem/Hairline") as ColorRect
	_expect_eq(label.get_theme_color("font_color"), compendium.get("ink"), "...full ink while on")
	_expect(hairline.visible, "...with its hairline")
	_expect_tempered_faces(compendium, count, untouched, "On")
	compendium.call("_rebuild")
	_expect(bool(compendium.call("is_showing_tempered")), "A rebuild keeps TEMPERED on")
	_expect_tempered_faces(compendium, count, untouched, "After a rebuild")

	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	compendium.call("_on_tempered_gui_input", click)
	_expect(not bool(compendium.call("is_showing_tempered")), "A click turns TEMPERED off")
	_expect_no_tempered_faces(compendium, "Off again")

	var scroll := compendium.get_node("Page/Scroll") as ScrollContainer
	# The rebuilt list's range settles over a few sorts.
	for _frame in 3:
		await process_frame
	scroll.scroll_vertical = 400
	await process_frame
	var scrolled: int = scroll.scroll_vertical
	_expect(scrolled > 0, "The list scrolls (%d of %.0f)" % [scrolled, scroll.get_v_scroll_bar().max_value])
	compendium.call("toggle_tempered")
	await process_frame
	await process_frame
	_expect_eq(scroll.scroll_vertical, scrolled, "Toggling keeps the scroll")
	compendium.call("toggle_tempered")
	await process_frame
	await process_frame
	_expect_eq(scroll.scroll_vertical, scrolled, "...both ways")

	var lift_name: String = untouched if not untouched.is_empty() else _compendium_views(compendium)[0].card_data.card_name
	var lifted: CardView = _compendium_view(compendium, lift_name)
	if lifted == null:
		_fail("%s is not in the compendium" % lift_name)
	else:
		compendium.call("_begin_inspect", lifted, lifted.get_parent())
		_expect(compendium.get("_inspected") == lifted, "%s lifted" % lift_name)
		compendium.call("toggle_tempered")
		_expect(compendium.get("_inspected") == null, "Toggling puts a lifted card away")
		var inspect_layer := compendium.get_node("Page/InspectLayer") as Control
		_expect(not inspect_layer.visible, "...its layer hidden")
		_expect_eq(scroll.modulate.a, 1.0, "...the list back at full")
		_expect(bool(compendium.call("is_showing_tempered")), "...and TEMPERED is on")
	compendium.queue_free()
	await process_frame
	_completed += 1

func _expect_tempered_faces(compendium: Node, count: int, untouched: String, label: String) -> void:
	_expect_eq(_compendium_views(compendium).size(), count, "%s: no entry added" % label)
	for name in ["Slash", "Carve"]:
		_expect(_compendium_view(compendium, name) == null, "%s: %s's face is gone" % [label, name])
		var view: CardView = _compendium_view(compendium, name + "+")
		_expect(view != null, "%s: %s+ shows" % [label, name])
	var slash: CardView = _compendium_view(compendium, "Slash+")
	if slash != null:
		_expect_eq(slash.rules_text.text, "Deal [u]9[/u] damage.", "%s: Slash+ underlines its 9" % label)
	var carve: CardView = _compendium_view(compendium, "Carve+")
	if carve != null:
		_expect(carve.rules_text.text.contains("[u]10[/u]") and carve.rules_text.text.count("[u]") == 1, "%s: Carve+ underlines its 10 alone (%s)" % [label, carve.rules_text.text])
	var reckoning: CardView = _compendium_view(compendium, "Reckoning+")
	_expect(reckoning != null and reckoning.get_node_or_null(^"CostMark") != null, "%s: Reckoning+ marks its cost" % label)
	if not untouched.is_empty():
		var plain: CardView = _compendium_view(compendium, untouched)
		_expect(plain != null and not plain.rules_text.text.contains("[u]") and plain.get_node_or_null(^"CostMark") == null, "%s: %s (no tempered version) as it was" % [label, untouched])

# The name of the first card in the grid with no tempered version, or "".
func _untempered_name(compendium: Node) -> String:
	for view in _compendium_views(compendium):
		if view.card_data.tempered == null:
			return view.card_data.card_name
	return ""

func _expect_no_tempered_faces(compendium: Node, label: String) -> void:
	for view in _compendium_views(compendium):
		_expect(not view.card_data.card_name.ends_with("+"), "%s: %s isn't a tempered face" % [label, view.card_data.card_name])
		_expect(not view.rules_text.text.contains("[u]") and view.get_node_or_null(^"CostMark") == null, "%s: %s has no marks" % [label, view.card_data.card_name])

# The grid's faces - not one queued to go with a rebuilt-away section.
func _compendium_views(compendium: Node) -> Array[CardView]:
	var views: Array[CardView] = []
	for node in compendium.find_children("*", "CardView", true, false):
		var view := node as CardView
		if view.card_data != null and not view.is_queued_for_deletion():
			views.append(view)
	return views

func _compendium_view(compendium: Node, card_name: String) -> CardView:
	for view in _compendium_views(compendium):
		if view.card_data.card_name == card_name:
			return view
	return null

# The workbench on floor 3: one, with an approach line, MAKE_STATIC, its
# bbox's four bottom corners on the drawn sand (in it no deeper than its
# sink and a margin), its footprint on walkable ground - inside the
# floor's ledge lines, never across one, and on land - and a plan from
# spawn getting him into its reach. The handcart, where there is one:
# MAKE_STATIC, tipped forward onto its shafts with both wheels and both
# shaft tips on the drawn sand (in it no deeper than CART_SUNK_MAX), its
# footprint on walkable ground as the workbench's. Where either stands is
# not this probe's to say.
func _check_wagon_placement() -> void:
	var wagons: Array[Node] = get_nodes_in_group("wagons")
	_expect_eq(wagons.size(), 1, "Floor 3 has one workbench")
	if wagons.is_empty():
		_completed += 1
		return
	var wagon := wagons[0] as Node3D
	var spawn: Vector3 = _field.call("get_spawn_position")
	var ground: Node = _field.get_node("Ground")
	_expect(not String(wagon.get("world_line")).is_empty(), "...with an approach line")
	var body := wagon.find_child("Collision", true, false) as StaticBody3D
	_expect(body != null and body.disable_mode == CollisionObject3D.DISABLE_MODE_MAKE_STATIC, "...its collision MAKE_STATIC")
	var box: AABB = wagon.call("get_body_aabb")
	var pose := wagon.get_node("Pose") as Node3D
	var deepest: float = float(wagon.get("sink_depth")) + 0.03
	for corner: Vector3 in [Vector3(box.position.x, 0, box.position.z), Vector3(box.end.x, 0, box.position.z), Vector3(box.position.x, 0, box.end.z), Vector3(box.end.x, 0, box.end.z)]:
		var point: Vector3 = pose.global_transform * corner
		var under: float = float(ground.call("get_visible_height_at", Vector2(point.x, point.z)))
		_expect(point.y <= under + 0.01, "...its foot %s on or in the sand (%.3f over it)" % [corner, point.y - under])
		_expect(point.y >= under - deepest, "...and not buried past its sink (%.3f under)" % [under - point.y])
	_expect_on_walkable_ground("The workbench", wagon, Rect2(box.position.x, box.position.z, box.size.x, box.size.z), spawn, ground)
	var cart := _field.find_child("Handcart*", true, false) as Node3D
	if cart != null:
		var cart_body := cart.find_child("Collision", true, false) as StaticBody3D
		_expect(cart_body != null and cart_body.disable_mode == CollisionObject3D.DISABLE_MODE_MAKE_STATIC, "The handcart's collision MAKE_STATIC")
		var tip: float = float(cart.call("get_tip_degrees"))
		_expect(tip > 5.0 and tip < 20.0, "...tipped forward onto its shafts (%.1f degrees)" % tip)
		var touching: Array[Vector3] = []
		for low: Vector3 in CART_WHEEL_LOW:
			# A wheel's lowest point as posed: its hub less the radius, straight
			# down in the world, not in the cart's tipped frame.
			var hub: Vector3 = cart.call("model_to_world", Vector3(low.x, float((cart.get("axle_point") as Vector3).y), low.z))
			touching.append(hub - Vector3(0.0, float(cart.get("wheel_radius")), 0.0))
		for shaft: Vector3 in CART_TIPS:
			touching.append(cart.call("model_to_world", shaft))
		for point in touching:
			var under: float = float(ground.call("get_visible_height_at", Vector2(point.x, point.z)))
			_expect(point.y <= under + 0.01, "...a wheel or shaft tip on or in the sand (%.3f over it)" % [point.y - under])
			_expect(point.y >= under - CART_SUNK_MAX, "...and not buried past %.2f m (%.3f under)" % [CART_SUNK_MAX, under - point.y])
		_expect_on_walkable_ground("The handcart", cart, Rect2(-1.5, -0.86, 3.01, 1.72), spawn, ground)
	var path: PackedVector3Array = _field.call("plan_path", spawn, wagon.global_position, null, false)
	_expect(path.size() >= 2, "A plan from spawn to the workbench")
	if path.size() >= 2:
		var end: Vector3 = path[path.size() - 1]
		var reach: float = Vector2(end.x, end.z).distance_to(Vector2(wagon.global_position.x, wagon.global_position.z))
		_expect(bool(wagon.call("can_open_from", end)), "...ending in its reach (%.2f m off)" % reach)
	_completed += 1

# A prop's footprint (`rect`, in its own XZ) on walkable ground: every
# sampled point inside the floor's ledge lines - never across one - and
# on land, not in the water.
func _expect_on_walkable_ground(label: String, node: Node3D, rect: Rect2, spawn: Vector3, ground: Node) -> void:
	var ledges: Array = (_field.call("get_floor_data") as Resource).get("ledges")
	var outside: int = 0
	var wet: int = 0
	for u in 9:
		for v in 5:
			var local := Vector3(lerpf(rect.position.x, rect.end.x, float(u) / 8.0), 0, lerpf(rect.position.y, rect.end.y, float(v) / 4.0))
			var point: Vector3 = node.global_transform * local
			var at := Vector2(point.x, point.z)
			for ledge: PackedVector2Array in ledges:
				if not Geometry2D.is_point_in_polygon(at - Vector2(spawn.x, spawn.z), ledge):
					outside += 1
			if float(ground.call("get_landmass_distance", at)) > 0.0:
				wet += 1
	_expect_eq(outside, 0, "%s's footprint inside the floor's ledge lines, across none" % label)
	_expect_eq(wet, 0, "...and on land")

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
		var cost_mark: Node = after.get_node_or_null(^"CostMark")
		match id:
			"slash":
				_expect_eq(text, "Deal [u]9[/u] damage.", "...Slash+ underlines its 9")
			"bite_down":
				_expect_eq(text, "Deal [u]11[/u] damage.\nThen lose 2 HP.", "...Bite Down+ underlines its 11 alone")
			"brace":
				_expect(text.ends_with("\n[u]Draw 1.[/u]") and text.count("[u]") == 1, "...Brace+ underlines its added line whole (%s)" % text)
			"settled_account":
				_expect_eq(text, "Gain [u]6[/u] block.
Spend up to [u]8[/u] [b]Toll[/b]: gain that much more block.", "...Settled Account+ underlines its 6 and its 8")
			"down_payment":
				_expect(text.begins_with("Gain [u]8[/u] ") and text.count("[u]") == 1, "...Down Payment+ underlines its 8 (%s)" % text)
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

# Every card in CARD_DIRS that names a tempered version.
func _tempered_originals() -> Array[CardData]:
	var originals: Array[CardData] = []
	for dir in CARD_DIRS:
		for file in DirAccess.get_files_at(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir + file) as CardData
			if card != null and card.tempered != null:
				originals.append(card)
	return originals

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

func _collect_resources(dir: String, out: Array[String]) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub.begins_with(".") or sub == "reference" or sub == "addons":
			continue
		_collect_resources(dir.path_join(sub), out)
	for file in DirAccess.get_files_at(dir):
		if file.ends_with(".tres") or file.ends_with(".tscn"):
			out.append(dir.path_join(file))

func _clear_log_dir() -> void:
	var dir := DirAccess.open(_log_dir)
	if dir == null:
		return
	for file in dir.get_files():
		dir.remove(file)

func _log_lines() -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	for file in DirAccess.get_files_at(_log_dir):
		for raw in FileAccess.get_file_as_string(_log_dir.path_join(file)).split("\n", false):
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
