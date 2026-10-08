extends SceneTree

# Headless probe for the KeepsakeTile - the one way a keepsake is shown -
# and the hosts that are only reachable from the field and the battle:
#
#   fit          every keepsake under run/keepsakes/ fits its tile with
#                the rules at the first (largest) size, at 1x, the
#                offer's 1.3x and the examine view's 2x, and the tile is
#                tile_size x tile_scale
#   placeholder  a keepsake with no art draws the placeholder and fits;
#                no lore leaves the lore out
#   no draw      a tile takes nothing from the global generator (the
#                battle shuffles a seeded run replays), and the same
#                keepsake gets the same paper
#   HUD          the field HUD's keepsake line hovers its tile above the
#                row; a left click on it opens KeepsakeExamine at
#                examine_scale, centred, with the field locked under it;
#                Escape closes it and unlocks the field
#   battle row   the battle keepsake row's hover shows the hovered
#                keepsake's tile at 1x, reveal_gap_px over its floor
#
# The offer and the belongings screen's HELD / OFFERED tiles are checked
# in trinket_probe and belongings_choice_probe, the Keeper's in
# keeper_keepsake_probe. Headless, the mouse can't be moved, so a hover
# is driven through the hosts' own steps (KeepsakeLine._place_tile(),
# KeepsakeRow._set_hovered()); a click is a pushed InputEventMouseButton.
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
const TILE_SCRIPT_PATH := "res://ui/keepsake_tile.gd"
const ROW_SCRIPT_PATH := "res://battle/keepsake_row.gd"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BENT_NAIL_PATH := "res://run/keepsakes/bent_nail.tres"
const HOUSE_KEY_PATH := "res://run/keepsakes/keeper/house_key.tres"
const SCALES := [1.0, 1.3, 2.0]
# Past KeepsakeExamine's inspect_duration_sec (0.15) either way.
const TWEEN_ROOM_SEC := 0.4

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
	await _check_placeholder_and_no_lore()
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

# --- The tile ---

func _check_fit() -> void:
	var keepsakes: Array[TrinketData] = _all_keepsakes()
	_expect(keepsakes.size() >= 10, "At least the ten keepsakes are found (got %d)" % keepsakes.size())
	for scale: float in SCALES:
		var tile: Control = _new_tile(scale)
		var largest: int = (tile.get("rules_sizes_px") as PackedInt32Array)[0]
		var expected_size: Vector2 = ((tile.get("tile_size") as Vector2) * scale).round()
		_expect_eq(tile.call("get_tile_size"), expected_size, "At %.1fx the tile is tile_size x tile_scale" % scale)
		_expect_eq(tile.size, expected_size, "...and its Control is that size")
		for keepsake in keepsakes:
			tile.call("set_keepsake", keepsake)
			_expect(bool(tile.call("fits")), "%s fits its tile at %.1fx" % [keepsake.display_name, scale])
			_expect_eq(int(tile.call("get_rules_size_px")), largest, "%s's rules at %.1fx: the largest size" % [keepsake.display_name, scale])
			_expect(not bool(tile.call("uses_placeholder")), "%s has its art" % keepsake.display_name)
		tile.queue_free()
	await process_frame
	_completed += 1

func _check_placeholder_and_no_lore() -> void:
	var bare: TrinketData = (load(BENT_NAIL_PATH) as TrinketData).duplicate()
	bare.art = null
	bare.flavor_text = ""
	var tile: Control = _new_tile(1.0)
	tile.call("set_keepsake", bare)
	_expect(bool(tile.call("uses_placeholder")), "No art: the placeholder")
	_expect(bool(tile.call("fits")), "...and it fits")
	_expect(tile.get("_lore") == null, "No lore: no lore paragraph")
	tile.call("set_keepsake", load(HOUSE_KEY_PATH))
	_expect(tile.get("_lore") != null, "With lore (House Key): the lore paragraph")
	tile.queue_free()
	await process_frame
	_completed += 1

func _check_no_global_draw() -> void:
	seed(1234)
	var expected: int = randi()
	seed(1234)
	var first: Control = _new_tile(1.0)
	first.call("set_keepsake", load(HOUSE_KEY_PATH))
	var second: Control = _new_tile(2.0)
	second.call("set_keepsake", load(HOUSE_KEY_PATH))
	_expect_eq(randi(), expected, "Making and filling tiles draws nothing from the global generator")
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
	var line := _field.get_node_or_null("FieldHUD/KeepsakeLine") as Control
	if line == null:
		_fail("The field HUD has no KeepsakeLine")
		await _teardown()
		_completed += 1
		return
	_expect(line.visible, "The HUD's keepsake line shows Bent Nail")

	# The hover: the tile, above the row.
	var tile: Control = line.call("get_tile")
	_expect(tile != null and not tile.visible, "...its hover tile hidden at rest")
	line.set("_reveal_alpha", 1.0)
	line.call("_place_tile")
	_expect(tile.visible and tile.call("get_keepsake") == load(BENT_NAIL_PATH), "Hovered: the tile shows Bent Nail")
	var style: Resource = line.get("style")
	_expect(is_equal_approx(float(tile.get("tile_scale")), float(style.get("hud_keepsake_tile_scale"))), "...at hud_keepsake_tile_scale")
	_expect(tile.global_position.y + (tile.call("get_tile_size") as Vector2).y <= line.global_position.y, "...above the row")
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
		var big: Control = examine.call("get_tile")
		_expect(is_equal_approx(float(big.get("tile_scale")), float(examine.get("examine_scale"))), "...its tile at examine_scale")
		_expect(bool(big.call("fits")), "...and Bent Nail fits it")
		var view: Vector2 = root.get_visible_rect().size
		var centre: Vector2 = big.position + (big.call("get_tile_size") as Vector2) / 2.0
		_expect(centre.distance_to(view / 2.0) <= 1.0, "...centred (tile centre %s, screen %s)" % [centre, view / 2.0])
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
	var tile: Control = row.call("get_tile")
	_expect(tile != null and not tile.visible, "The battle row's tile is hidden at rest")
	row.call("_set_hovered", 1)
	row.call("_advance_reveal", 1.0)
	_expect(tile.visible and tile.call("get_keepsake") == load(HOUSE_KEY_PATH), "Hovering the second name shows House Key's tile")
	_expect(is_equal_approx(float(tile.get("tile_scale")), 1.0), "...at 1x")
	var bottom: float = tile.global_position.y + (tile.call("get_tile_size") as Vector2).y
	_expect(is_equal_approx(bottom, floor_y - float(row.get("reveal_gap_px"))), "...reveal_gap_px over the floor (bottom %s)" % bottom)
	row.call("_set_hovered", -1)
	row.call("_advance_reveal", 1.0)
	_expect(not tile.visible, "...and hidden once the cursor leaves")
	row.queue_free()
	await process_frame
	_completed += 1

# --- Helpers ---

func _all_keepsakes() -> Array[TrinketData]:
	var found: Array[TrinketData] = []
	var pending: Array[String] = [KEEPSAKES_DIR]
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			pending.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if file.ends_with(".tres"):
				var trinket := load(dir_path.path_join(file)) as TrinketData
				if trinket != null:
					found.append(trinket)
	return found

func _new_tile(scale: float) -> Control:
	var tile: Control = (load(TILE_SCRIPT_PATH) as GDScript).new()
	tile.set("tile_scale", scale)
	root.add_child(tile)
	return tile

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
