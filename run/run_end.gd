extends CanvasLayer
class_name RunEnd

# The run's end when it is won: Region 1's last floor left by its exit
# (RegionField._on_floor_exited(), with loop_region_after_last_floor off).
# The transition's fade has already taken the frame to the fog colour and
# stays up (FloorFade, layer 128, on the tree's root); this sits just
# above it, so the screen is type on the fog - no boxes, no glow. One
# world-voice line in Spectral; under it, in the system voice, the run's
# tally - caps labels in the utility grey, values in ink; under that two
# items in the title's style (TitleMenu): NEW RUN and TITLE, the utility
# grey when unfocused, full ink with a short hairline to the left when
# focused. Keyboard and mouse as the title: ui_up/ui_down move focus
# (wrapping), ui_accept activates, hover focuses, a click activates; the
# first activation wins.
#
# NEW RUN is RunOver's restart: RunState.new_run() with the same
# character, then the field - floor 1, the zone intro. TITLE starts the
# new run the same way and then loads the boot scene (TitleScreen), so the
# title's Start finds a fresh run exactly as at launch. Either way the
# fade comes down first, as neither flow expects one up.
#
# Every size is authored for a 1080-high viewport and scaled by the
# viewport height; the layout is redone on every resize.

const REFERENCE_VIEWPORT_HEIGHT := 1080.0
const LINE_FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"
# Only for a RunEnd reached with no run on RunState at all (the scene run
# directly).
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"

enum Item { NEW_RUN, TITLE }

# The world-voice line - placeholder text, to be replaced.
@export var world_line: String = "The way goes on.":
	set(value):
		world_line = value
		_relayout_if_ready()

@export_group("Type")
@export var line_font: Font = load(LINE_FONT_PATH):
	set(value):
		line_font = value
		_relayout_if_ready()
@export var line_font_size_px: int = 44:
	set(value):
		line_font_size_px = value
		_relayout_if_ready()
# The stat labels and the items: the HUD's caps label - Alegreya Sans
# Bold at 0.16 em.
@export var caps_font: Font = load(InkType.TEXT_BOLD_FONT_PATH):
	set(value):
		caps_font = value
		_relayout_if_ready()
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_relayout_if_ready()
@export var stat_label_font_size_px: int = 16:
	set(value):
		stat_label_font_size_px = value
		_relayout_if_ready()
# The stat values: the readouts' numerals (Spectral SemiBold).
@export var value_font: Font = load(InkType.NUMERAL_FONT_PATH):
	set(value):
		value_font = value
		_relayout_if_ready()
@export var value_font_size_px: int = 24:
	set(value):
		value_font_size_px = value
		_relayout_if_ready()
@export var item_font_size_px: int = 22:
	set(value):
		item_font_size_px = value
		_relayout_if_ready()

@export_group("Colour")
# The UI ink (BattleTheme's on_pale_ink) - the line, the values, the
# focused item and its hairline.
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_relayout_if_ready()
# The utility grey (CardView's keyline_utility) - the stat labels and an
# unfocused item.
@export var utility_grey: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		utility_grey = value
		_relayout_if_ready()
# Behind the type only when no fade is up (the scene run on its own):
# TitleScreen's colour, matched to the rendered fog.
@export var background_color: Color = Color(0.86, 0.87, 0.86, 1.0):
	set(value):
		background_color = value
		_relayout_if_ready()

@export_group("Layout")
# The one left edge everything shares, as a fraction of the viewport
# width (the title's); hairlines hang into the margin to its left.
@export var left_margin_fraction: float = 0.12:
	set(value):
		left_margin_fraction = value
		_relayout_if_ready()
# The line's top, as a fraction of the viewport height.
@export var line_y_fraction: float = 0.3:
	set(value):
		line_y_fraction = value
		_relayout_if_ready()
# Pixels at 1080p: line to the first stat, stat to stat, the label column
# to the values, the last stat to the first item, item to item, and the
# hairline's length and gap (its thickness is not scaled).
@export var line_to_stats_gap_px: float = 56.0:
	set(value):
		line_to_stats_gap_px = value
		_relayout_if_ready()
@export var stat_gap_px: float = 10.0:
	set(value):
		stat_gap_px = value
		_relayout_if_ready()
@export var label_to_value_gap_px: float = 28.0:
	set(value):
		label_to_value_gap_px = value
		_relayout_if_ready()
@export var stats_to_items_gap_px: float = 64.0:
	set(value):
		stats_to_items_gap_px = value
		_relayout_if_ready()
@export var item_gap_px: float = 18.0:
	set(value):
		item_gap_px = value
		_relayout_if_ready()
@export var hairline_length_px: float = 28.0:
	set(value):
		hairline_length_px = value
		_relayout_if_ready()
@export var hairline_gap_px: float = 14.0:
	set(value):
		hairline_gap_px = value
		_relayout_if_ready()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_relayout_if_ready()

@export_group("Flow")
# The column fades in over this on arrival; input is live from the first
# frame regardless.
@export var fade_in_seconds: float = 0.6
@export var field_scene_path: String = "res://field/region_field.tscn"
@export var title_scene_path: String = "res://run/title_screen.tscn"

@onready var background: ColorRect = $Background
@onready var column: Control = $Column
@onready var line_label: Label = $Column/LineLabel
@onready var stats: Control = $Column/Stats
@onready var new_run_item: Control = $Column/NewRunItem
@onready var title_item: Control = $Column/TitleItem

var _items: Array[Control] = []
var _focused: int = Item.NEW_RUN
var _activated: bool = false
# [label, value] text pairs, read from RunState once on arrival.
var _stat_rows: Array[PackedStringArray] = []

func _ready() -> void:
	_items = [new_run_item, title_item]
	for index in _items.size():
		var item: Control = _items[index]
		item.mouse_entered.connect(_on_item_mouse_entered.bind(index))
		item.gui_input.connect(_on_item_gui_input.bind(index))
	_stat_rows = stat_rows()
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	if fade_in_seconds > 0.0:
		column.modulate.a = 0.0
		create_tween().tween_property(column, "modulate:a", 1.0, fade_in_seconds)

# The run's tally, as the screen shows it: floors crossed, fights won,
# HP of max, deck size, keepsake (a dash for none).
static func stat_rows() -> Array[PackedStringArray]:
	var keepsake: TrinketData = RunState.keepsake
	return [
		PackedStringArray(["FLOORS CROSSED", str(RunState.floors_crossed)]),
		PackedStringArray(["FIGHTS WON", str(RunState.fights_won)]),
		PackedStringArray(["HP", "%d / %d" % [RunState.player_hp, RunState.player_max_hp]]),
		PackedStringArray(["DECK", str(RunState.deck.size())]),
		PackedStringArray(["KEEPSAKE", keepsake.display_name if keepsake != null and not keepsake.display_name.is_empty() else "—"]),
	]

func _relayout_if_ready() -> void:
	if is_inside_tree() and line_label != null:
		_relayout()

func _relayout() -> void:
	var fade := FloorFade.find_existing(get_tree())
	background.visible = fade == null or not fade.is_opaque()
	background.color = background_color
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = viewport_size.y / REFERENCE_VIEWPORT_HEIGHT
	var left: float = viewport_size.x * left_margin_fraction

	var line_size: int = maxi(roundi(float(line_font_size_px) * scale), 1)
	line_label.text = world_line
	line_label.add_theme_font_override("font", line_font)
	line_label.add_theme_font_size_override("font_size", line_size)
	line_label.add_theme_color_override("font_color", ink)
	line_label.size = line_label.get_combined_minimum_size()
	line_label.position = Vector2(left, viewport_size.y * line_y_fraction)

	# The stats: one label column, the values on a shared edge after the
	# widest label, each row's label and value on one baseline.
	for child in stats.get_children():
		stats.remove_child(child)
		child.queue_free()
	var label_size: int = maxi(roundi(float(stat_label_font_size_px) * scale), 1)
	var label_font: Font = InkType.tracked(caps_font, label_size, tracking_em)
	var value_size: int = maxi(roundi(float(value_font_size_px) * scale), 1)
	var label_width: float = 0.0
	for row in _stat_rows:
		label_width = maxf(label_width, InkType.width(label_font, row[0], label_size))
	var value_x: float = label_width + label_to_value_gap_px * scale
	var row_height: float = maxf(value_font.get_height(value_size), label_font.get_height(label_size))
	var ascent: float = maxf(value_font.get_ascent(value_size), label_font.get_ascent(label_size))
	stats.position = Vector2(left, line_label.position.y + line_label.size.y + line_to_stats_gap_px * scale)
	var y: float = 0.0
	for row in _stat_rows:
		var label := _bare_label(row[0], label_font, label_size, utility_grey)
		label.position = Vector2(0.0, y + ascent - label_font.get_ascent(label_size))
		stats.add_child(label)
		var value := _bare_label(row[1], value_font, value_size, ink)
		value.position = Vector2(value_x, y + ascent - value_font.get_ascent(value_size))
		stats.add_child(value)
		y += row_height + stat_gap_px * scale
	stats.size = Vector2(value_x, y)

	var item_size: int = maxi(roundi(float(item_font_size_px) * scale), 1)
	var item_font: Font = InkType.tracked(caps_font, item_size, tracking_em)
	var hairline_length: float = hairline_length_px * scale
	var hairline_gap: float = hairline_gap_px * scale
	y = stats.position.y + stats.size.y + stats_to_items_gap_px * scale
	for item in _items:
		var label := item.get_node(^"Label") as Label
		var hairline := item.get_node(^"Hairline") as ColorRect
		label.add_theme_font_override("font", item_font)
		label.add_theme_font_size_override("font_size", item_size)
		label.size = label.get_combined_minimum_size()
		label.position = Vector2(hairline_length + hairline_gap, 0.0)
		item.position = Vector2(left - hairline_length - hairline_gap, y)
		item.size = Vector2(label.position.x + label.size.x, label.size.y)
		hairline.size = Vector2(hairline_length, hairline_thickness_px)
		hairline.position = Vector2(0.0, (label.size.y - hairline_thickness_px) * 0.5)
		hairline.color = ink
		y += label.size.y + item_gap_px * scale
	_apply_focus()

func _bare_label(text: String, font: Font, size_px: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", size_px)
	label.add_theme_color_override("font_color", color)
	label.size = label.get_combined_minimum_size()
	return label

func _apply_focus() -> void:
	for index in _items.size():
		var item: Control = _items[index]
		var focused: bool = index == _focused
		(item.get_node(^"Label") as Label).add_theme_color_override("font_color", ink if focused else utility_grey)
		(item.get_node(^"Hairline") as ColorRect).visible = focused

# --- input --------------------------------------------------------------

func _set_focus(index: int) -> void:
	if _activated or index == _focused:
		return
	_focused = index
	_apply_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _activated:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focused + 1, _items.size()))
	elif event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focused - 1, _items.size()))
	elif event.is_action_pressed("ui_accept"):
		_activate(_focused)
	else:
		return
	get_viewport().set_input_as_handled()

func _on_item_mouse_entered(index: int) -> void:
	_set_focus(index)

func _on_item_gui_input(event: InputEvent, index: int) -> void:
	if _activated:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_set_focus(index)
	_activate(index)
	get_viewport().set_input_as_handled()

# The first activation wins. Both start a fresh run - the one just won is
# already logged and closed - and take the fade down before leaving.
func _activate(index: int) -> void:
	if _activated:
		return
	_activated = true
	var character: CharacterData = RunState.character
	if character == null:
		character = load(STARTING_CHARACTER_PATH) as CharacterData
	RunState.new_run(character)
	var fade := FloorFade.find_existing(get_tree())
	if fade != null:
		fade.clear()
	match index:
		Item.NEW_RUN:
			get_tree().change_scene_to_file(field_scene_path)
		Item.TITLE:
			get_tree().change_scene_to_file(title_scene_path)
