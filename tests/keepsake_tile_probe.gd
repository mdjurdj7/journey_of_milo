extends SceneTree

# Headless probe for the ItemPlate - the one way equipment is shown: the
# weapon, a worn piece and a keepsake alike - and the hosts that are only
# reachable from the field and the battle:
#
#   fit          every keepsake under run/keepsakes/, every worn piece
#                under run/armor/ and every weapon under run/weapons/ fits
#                its plate - the effect in its two-line block, the lore in
#                its two, the name on one line - at the one plate scale
#                every host shows them at (the hovers, the examine views,
#                the offers); every plate is the same size, and at
#                1920x1080 and 2560x1440 no taller than a third of the
#                screen (MAX_HEIGHT_FRACTION, the offer strip left out);
#                each says its own kind (WEAPON, WORN, KEEPSAKE)
#   blank        a piece with no art draws the placeholder; one with no
#                effect, or no lore, leaves that block blank, the plate
#                the same size; the stat row takes no room while empty
#   no draw      a plate takes nothing from the global generator (the
#                battle shuffles a seeded run replays), and the same
#                piece gets the same paper
#   HUD          the field HUD's KEEPSAKE slot hovers its plate above the
#                slot; a left click on it opens KeepsakeExamine at
#                examine_scale, centred, with the field locked under it;
#                Escape closes it and unlocks the field
#   battle row   the battle keepsake row's hover shows the hovered
#                keepsake's plate at the plate scale, reveal_gap_px over
#                its floor
#
# The offer and the belongings screen's HELD / OFFERED plates are checked
# in trinket_probe and belongings_choice_probe, the Keeper's in
# keeper_keepsake_probe, a worn piece's offer in armor_probe. Headless,
# the mouse can't be moved, so a hover is driven through the hosts' own
# steps (KeepsakeLine._place_tile(), KeepsakeRow._set_hovered()); a click
# is a pushed InputEventMouseButton.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/keepsake_tile_probe.gd
#
# Exit code 0 = passed, 1 = a failure (each printed as FAIL).
#
# Untyped against classes that name the RunState autoload (RegionField,
# KeepsakeLine): a SceneTree script compiles before the autoloads
# register.

const CASES := 5
const SAFETY_SECONDS := 120.0
const KEEPSAKES_DIR := "res://run/keepsakes/"
const ARMOR_DIR := "res://run/armor/"
const WEAPONS_DIR := "res://run/weapons/"
const PLATE_SCRIPT_PATH := "res://ui/item_plate.gd"
# The one plate scale, each host's own export: the hovers, the examine
# views, the offers.
const PLATE_SCALES := [["res://ui/hud_row_style.gd", "hud_plate_scale"], ["res://battle/keepsake_row.gd", "reveal_plate_scale"], ["res://ui/armor_examine.gd", "examine_scale"], ["res://ui/keepsake_examine.gd", "examine_scale"], ["res://battle/keepsake_offer.gd", "tile_scale"], ["res://battle/belongings_screen.gd", "keepsake_tile_scale"], ["res://field/world_keepsake.gd", "plate_scale"]]
# The screens a plate must stay within a third of the height of, through
# the window's stretch (display/window/stretch/mode).
const SCREENS := [Vector2(1920.0, 1080.0), Vector2(2560.0, 1440.0)]
const MAX_HEIGHT_FRACTION := 0.33
const ROW_SCRIPT_PATH := "res://battle/keepsake_row.gd"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const RUSTED_BLADE_PATH := "res://run/weapons/rusted_blade.tres"
# Past KeepsakeExamine's inspect_duration_sec (0.15) either way.
const TWEEN_ROOM_SEC := 0.4
# The collector's shop pieces, on the plate's placeholder until their art
# is made: each still has to fit its plate and say its kind. Remove each
# id here when its art lands.
const PLACEHOLDER_ART_IDS: Array[StringName] = [&"salt_collar", &"reed_cape", &"counting_stone", &"knotted_cord", &"gaff_hook"]

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
	await _check_fit()
	await _check_blank()
	await _check_no_global_draw()
	await _check_hud()
	await _check_battle_row()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("keepsake_tile_probe: PASSED")
		quit(0)
	else:
		print("keepsake_tile_probe: %d FAILED" % _failures)
		quit(1)

# --- The plate ---

func _check_fit() -> void:
	var keepsakes: Array[Resource] = _all_in(KEEPSAKES_DIR)
	var worn: Array[Resource] = _all_in(ARMOR_DIR)
	var weapons: Array[Resource] = _all_in(WEAPONS_DIR)
	_expect(keepsakes.size() >= 10, "At least the ten keepsakes are found (got %d)" % keepsakes.size())
	_expect(worn.size() >= 4, "...the four worn pieces (got %d)" % worn.size())
	_expect(weapons.size() >= 1, "...and the weapon (got %d)" % weapons.size())
	var one: float = _default(PLATE_SCALES[0])
	for pair: Array in PLATE_SCALES:
		_expect(is_equal_approx(_default(pair), one), "%s's %s is the one plate scale (%.2f)" % [pair[0].get_file(), pair[1], one])
	for scale: float in [one]:
		var plate: Control = _new_plate(scale)
		var card_size: Vector2 = Vector2.ZERO
		for group: Array in [[keepsakes, "KEEPSAKE"], [worn, "WORN"], [weapons, "WEAPON"]]:
			for item: Resource in group[0]:
				var item_name: String = str(item.get("display_name"))
				_show(plate, item)
				_expect(bool(plate.call("fits")), "%s fits its plate at %.1fx (effect %d lines, lore %d)" % [item_name, scale, int(plate.call("get_rules_line_count")), int(plate.call("get_lore_line_count"))])
				_expect(int(plate.call("get_rules_line_count")) <= 2 and int(plate.call("get_lore_line_count")) <= 2, "...two lines at most each")
				_expect_eq(plate.call("get_type_label"), group[1], "...and says %s" % group[1])
				if not PLACEHOLDER_ART_IDS.has(StringName(str(item.get("id")))):
					_expect(not bool(plate.call("uses_placeholder")), "%s has its art" % item_name)
				if card_size == Vector2.ZERO:
					card_size = plate.call("get_card_size")
				_expect_eq(plate.call("get_card_size"), card_size, "%s's plate at %.1fx is the same size as every other" % [item_name, scale])
				_expect_eq(plate.call("get_plate_size"), card_size, "...with no offer strip under it")
		for screen: Vector2 in SCREENS:
			var on_screen: float = card_size.y * _stretch(screen)
			_expect(on_screen <= screen.y * MAX_HEIGHT_FRACTION, "At %dx%d the plate is %.0f px tall: no more than %.0f%% of the screen (%.1f%%)" % [int(screen.x), int(screen.y), on_screen, MAX_HEIGHT_FRACTION * 100.0, on_screen / screen.y * 100.0])
		plate.queue_free()
	await process_frame
	_completed += 1

func _check_blank() -> void:
	var plate: Control = _new_plate(1.0)
	plate.call("set_keepsake", load(BENT_NAIL_PATH))
	var card_size: Vector2 = plate.call("get_card_size")
	var bare: TrinketData = (load(BENT_NAIL_PATH) as TrinketData).duplicate()
	bare.art = null
	bare.flavor_text = ""
	plate.call("set_keepsake", bare)
	_expect(bool(plate.call("uses_placeholder")), "No art: the placeholder")
	_expect(bool(plate.call("fits")), "...and it fits")
	_expect_eq(int(plate.call("get_lore_line_count")), 0, "No lore: the lore block blank")
	_expect_eq(plate.call("get_card_size"), card_size, "...the plate the same size")
	# The baseline weapon, which does nothing to the attack.
	var blade: Resource = load(RUSTED_BLADE_PATH)
	plate.call("set_weapon", blade)
	_expect(not bool(plate.call("shows_rules")), "No effect (%s): the effect block blank" % blade.get("display_name"))
	_expect_eq(plate.call("get_card_size"), card_size, "...the plate the same size")
	plate.call("set_stat_row", "")
	_expect_eq(plate.call("get_card_size"), card_size, "An empty stat row takes no room")
	plate.call("set_keepsake", load(HOUSE_KEY_PATH))
	_expect(int(plate.call("get_lore_line_count")) > 0, "With lore (House Key): the lore paragraph")
	plate.queue_free()
	await process_frame
	_completed += 1

func _check_no_global_draw() -> void:
	seed(1234)
	var expected: int = randi()
	seed(1234)
	var first: Control = _new_plate(1.0)
	first.call("set_keepsake", load(HOUSE_KEY_PATH))
	var second: Control = _new_plate(1.3)
	second.call("set_keepsake", load(HOUSE_KEY_PATH))
	_expect_eq(randi(), expected, "Making and filling plates draws nothing from the global generator")
	_expect_eq(first.get("_paper_seed"), second.get("_paper_seed"), "...and the same keepsake gets the same paper")
	first.queue_free()
	second.queue_free()
	await process_frame
	_completed += 1

# --- The field HUD ---

func _check_hud() -> void:
	_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	# No zone intro: it holds the field frozen for its length.
	_run_state.set("run_opening_pending", false)
	_run_state.call("equip_keepsake", load(BENT_NAIL_PATH))
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 3:
		await process_frame
	# The arrival hold swallows presses at first (FloorData.
	# arrival_hold_seconds).
	while bool(_field.call("is_arrival_held")):
		await process_frame
	var line := _field.get_node_or_null("FieldHUD/KeepsakeLine") as Control
	if line == null:
		_fail("The field HUD has no KeepsakeLine")
		await _teardown()
		_completed += 1
		return
	_expect(line.visible, "The HUD's keepsake line shows Bent Nail")

	# The hover: the plate, above the slot.
	var tile: Control = line.call("get_plate")
	_expect(tile != null and not tile.visible, "...its hover plate hidden at rest")
	line.set("_reveal_alpha", 1.0)
	line.call("_place_tile")
	_expect(tile.visible and tile.call("get_keepsake") == load(BENT_NAIL_PATH), "Hovered: the plate shows Bent Nail")
	var style: Resource = line.get("style")
	_expect(is_equal_approx(float(tile.get("plate_scale")), float(style.get("hud_plate_scale"))), "...at hud_plate_scale")
	_expect(tile.global_position.y + (tile.call("get_plate_size") as Vector2).y <= line.global_position.y, "...above the slot")
	line.set("_reveal_alpha", 0.0)
	line.call("_place_tile")

	# The click: examine, the field locked.
	_click(line.get_global_rect().get_center())
	await process_frame
	var examine: Node = _child_with_script(_field, "keepsake_examine.gd")
	_expect(examine != null, "A left click on the keepsake opens KeepsakeExamine")
	if examine != null:
		_expect_eq(_field.process_mode, Node.PROCESS_MODE_DISABLED, "...with the field locked under it")
		await create_timer(TWEEN_ROOM_SEC).timeout
		var big: Control = examine.call("get_plate")
		_expect(is_equal_approx(float(big.get("plate_scale")), float(examine.get("examine_scale"))), "...its plate at examine_scale")
		_expect(bool(big.call("fits")), "...and Bent Nail fits it")
		var view: Vector2 = root.get_visible_rect().size
		var centre: Vector2 = big.position + (big.call("get_plate_size") as Vector2) / 2.0
		_expect(centre.distance_to(view / 2.0) <= 1.0, "...centred (plate centre %s, screen %s)" % [centre, view / 2.0])
		var escape := InputEventAction.new()
		escape.action = &"ui_cancel"
		escape.pressed = true
		root.push_input(escape)
		await create_timer(TWEEN_ROOM_SEC).timeout
		_expect(not is_instance_valid(examine) or examine.is_queued_for_deletion(), "Escape closes it")
		_expect_eq(_field.process_mode, Node.PROCESS_MODE_INHERIT, "...and unlocks the field")
	await _teardown()
	_completed += 1

# --- The battle keepsake row ---

func _check_battle_row() -> void:
	var row: Control = (load(ROW_SCRIPT_PATH) as GDScript).new()
	root.add_child(row)
	row.position = Vector2(40.0, 1000.0)
	var keepsakes: Array[TrinketData] = [load(BENT_NAIL_PATH), load(HOUSE_KEY_PATH)]
	row.call("set_keepsakes", keepsakes)
	var floor_y: float = 960.0
	row.call("set_reveal_floor_y", floor_y)
	await process_frame
	var tile: Control = row.call("get_plate")
	_expect(tile != null and not tile.visible, "The battle row's plate is hidden at rest")
	row.call("_set_hovered", 1)
	row.call("_advance_reveal", 1.0)
	_expect(tile.visible and tile.call("get_keepsake") == load(HOUSE_KEY_PATH), "Hovering the second name shows House Key's plate")
	_expect(is_equal_approx(float(tile.get("plate_scale")), float(row.get("reveal_plate_scale"))), "...at reveal_plate_scale")
	var bottom: float = tile.global_position.y + (tile.call("get_plate_size") as Vector2).y
	_expect(is_equal_approx(bottom, floor_y - float(row.get("reveal_gap_px"))), "...reveal_gap_px over the floor (bottom %s)" % bottom)
	row.call("_set_hovered", -1)
	row.call("_advance_reveal", 1.0)
	_expect(not tile.visible, "...and hidden once the cursor leaves")
	row.queue_free()
	await process_frame
	_completed += 1

# --- Helpers ---

# Every TrinketData or WeaponData under `root_dir`, its subfolders too.
func _all_in(root_dir: String) -> Array[Resource]:
	var found: Array[Resource] = []
	var pending: Array[String] = [root_dir]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".tres"):
				var item: Resource = load(dir_path.path_join(file))
				if item is TrinketData or item is WeaponData:
					found.append(item)
	return found

func _new_plate(scale: float) -> Control:
	var plate: Control = (load(PLATE_SCRIPT_PATH) as GDScript).new()
	plate.set("plate_scale", scale)
	root.add_child(plate)
	return plate

func _show(plate: Control, item: Resource) -> void:
	if item is WeaponData:
		plate.call("set_weapon", item)
	else:
		plate.call("set_piece", item)

# How much the window's stretch scales the UI on `screen`: canvas_items
# or viewport stretch keep the base size's aspect (the lesser ratio);
# with none, 1.
func _stretch(screen: Vector2) -> float:
	if str(ProjectSettings.get_setting("display/window/stretch/mode", "disabled")) == "disabled":
		return 1.0
	var base := Vector2(float(ProjectSettings.get_setting("display/window/size/viewport_width")), float(ProjectSettings.get_setting("display/window/size/viewport_height")))
	return minf(screen.x / base.x, screen.y / base.y)

# A host's scale export, as authored: [script path, property].
func _default(pair: Array) -> float:
	return float((load(pair[0]) as Script).get_property_default_value(pair[1]))

func _click(position: Vector2) -> void:
	for pressed in [true, false]:
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_LEFT
		button.pressed = pressed
		button.position = position
		button.global_position = position
		root.push_input(button, true)

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
