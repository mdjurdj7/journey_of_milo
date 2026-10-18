extends CanvasLayer
class_name CharacterSelect

# The class a title-started run plays as, picked between the title's
# START GAME and the zone intro. No background of its own: it stands over
# the held title frame (ZoneIntro's TITLE_HOLD - fog closed, the tower
# faint) in the title column's place, once that column has faded - a
# small prompt line and one item per class, in the title's type language
# (InkType.tracked() caps, InkMenu's focus): the focused item in the
# title's ink with its hairline in the margin, the rest the utility grey.
#
# The items are built from `characters` (CharacterData, each shown as its
# character_name in caps), so a third class is one more entry in the
# scene's list. Focus starts on default_index.
#
# Where the column stands is the title's: the owner hands in anchor_
# source, a Callable returning the title column's left edge and its first
# item's top (TitleMenu.item_anchor()), read on every layout - this
# column's first item sits there, the prompt above it. Without one, the
# fallback margin and height below place it.
#
# Input is InkMenu's - ui_up/ui_down move focus (wrapping), ui_accept
# picks, the mouse focuses by hovering and picks by clicking - plus
# move_forward/move_back as up/down (W/S) and ui_cancel back to the title.
# The first pick or cancel wins and locks the menu.
#
# The owner (ZoneIntro, whose child this is - so it runs through the
# title's freeze) drives the beats: open() fades the column in; a pick
# goes out as picked(character), after which fade_to_reload() fades the
# column out for the owner's capture of the held frame (ZoneIntro, its
# FreezeFrame) and the field reload; a cancel fades the column out, goes
# out as cancelled, and this node frees itself.
#
# Every size is authored for a 1080-high viewport and scaled by the
# viewport height; the layout is redone on every resize.

signal picked(character: CharacterData)
signal cancelled

const REFERENCE_VIEWPORT_HEIGHT := 1080.0

@export var characters: Array[CharacterData] = []:
	set(value):
		characters = value
		if is_inside_tree():
			_build_items()
# The item focused when the screen opens.
@export var default_index: int = 0
@export var prompt_text: String = "WHO WALKS":
	set(value):
		prompt_text = value
		_relayout_if_ready()

@export_group("Type")
# The items and the prompt: the HUD's caps label - Alegreya Sans Bold,
# tracked 0.16 em, as the title's items.
@export var item_font: Font = load(InkType.TEXT_BOLD_FONT_PATH):
	set(value):
		item_font = value
		_relayout_if_ready()
@export var item_font_size_px: int = 22:
	set(value):
		item_font_size_px = value
		_relayout_if_ready()
@export var prompt_font_size_px: int = 14:
	set(value):
		prompt_font_size_px = value
		_relayout_if_ready()
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_relayout_if_ready()

@export_group("Colour")
# The title's UI ink (TitleMenu.ink) - the prompt, the focused item and
# its hairline.
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_relayout_if_ready()
# The utility grey - the unfocused items.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_relayout_if_ready()

@export_group("Layout")
# Fallbacks, used only with no anchor_source: the left edge as a
# fraction of the viewport width, and the first item's top as a fraction
# of its height.
@export var left_margin_fraction: float = 0.12:
	set(value):
		left_margin_fraction = value
		_relayout_if_ready()
@export var items_y_fraction: float = 0.45:
	set(value):
		items_y_fraction = value
		_relayout_if_ready()
# Pixels at 1080p: the prompt's bottom to the first item, item to item,
# and the hairline's length, gap and thickness (the thickness never
# scaled) - the title's item values.
@export var prompt_to_items_gap_px: float = 36.0:
	set(value):
		prompt_to_items_gap_px = value
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
# The column in on open and out on a cancel.
@export var items_fade_seconds: float = 0.3

# Returns Vector2(left edge, first item's top) in viewport pixels; set by
# the owner before open(). Empty: the fallback exports.
var anchor_source: Callable = Callable()

var _column: Control = null
var _prompt: Label = null
var _menu: InkMenu = null
# Parallel to _menu.items.
var _item_characters: Array[CharacterData] = []
var _tween: Tween = null

func _ready() -> void:
	_column = Control.new()
	_column.name = "Column"
	_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_column)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_column.add_child(_prompt)
	_column.modulate.a = 0.0
	_build_items()
	_menu.lock()
	get_viewport().size_changed.connect(_relayout)

# --- the owner's side ---------------------------------------------------

# The column in; input is live once it is. Awaitable.
func open() -> void:
	_relayout()
	await _fade(_column, 1.0, items_fade_seconds)
	if _menu != null:
		_menu.unlock()

# After picked: the column out, leaving the held title frame alone for
# the owner to capture. Awaitable; the owner reloads the field after.
func fade_to_reload() -> void:
	await _fade(_column, 0.0, items_fade_seconds)

# --- input --------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _menu == null or _menu.locked:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_cancel()
	elif event.is_action_pressed("move_forward"):
		get_viewport().set_input_as_handled()
		_menu.move_focus(-1)
	elif event.is_action_pressed("move_back"):
		get_viewport().set_input_as_handled()
		_menu.move_focus(1)
	elif _menu.handle_input(event):
		get_viewport().set_input_as_handled()

func _activate(index: int) -> void:
	if _menu.locked or index < 0 or index >= _item_characters.size():
		return
	_menu.lock()
	picked.emit(_item_characters[index])

func _cancel() -> void:
	_menu.lock()
	await _fade(_column, 0.0, items_fade_seconds)
	cancelled.emit()
	queue_free()

# --- items and layout ---------------------------------------------------

# One item per class (a Control holding a Hairline and a Label, as the
# title's items are), in list order; null entries left out.
func _build_items() -> void:
	if _column == null:
		return
	var was_locked: bool = _menu == null or _menu.locked
	if _menu != null:
		for item in _menu.items:
			item.queue_free()
	_item_characters.clear()
	var items: Array[Control] = []
	for character in characters:
		if character == null:
			continue
		var item := Control.new()
		item.name = "Item%d" % items.size()
		var hairline := ColorRect.new()
		hairline.name = "Hairline"
		hairline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		item.add_child(hairline)
		var label := Label.new()
		label.name = "Label"
		label.text = character.character_name.to_upper()
		item.add_child(label)
		_column.add_child(item)
		items.append(item)
		_item_characters.append(character)
	_menu = InkMenu.new(items, clampi(default_index, 0, maxi(items.size() - 1, 0)))
	_menu.activated.connect(_activate)
	if was_locked:
		_menu.lock()
	_relayout()

func _relayout_if_ready() -> void:
	if is_inside_tree() and _prompt != null:
		_relayout()

# The first item on the anchor (the title's first item), the prompt
# above it on the same left edge, the rest stacked below.
func _relayout() -> void:
	if _menu == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = viewport_size.y / REFERENCE_VIEWPORT_HEIGHT
	var anchor: Vector2 = Vector2(viewport_size.x * left_margin_fraction, viewport_size.y * items_y_fraction)
	if anchor_source.is_valid():
		anchor = anchor_source.call() as Vector2

	var prompt_size: int = maxi(roundi(float(prompt_font_size_px) * scale), 1)
	_prompt.text = prompt_text
	_prompt.add_theme_font_override("font", InkType.tracked(item_font, prompt_size, tracking_em))
	_prompt.add_theme_font_size_override("font_size", prompt_size)
	_prompt.add_theme_color_override("font_color", ink)
	_prompt.size = _prompt.get_combined_minimum_size()
	_prompt.position = Vector2(anchor.x, anchor.y - prompt_to_items_gap_px * scale - _prompt.size.y)

	var item_size: int = maxi(roundi(float(item_font_size_px) * scale), 1)
	_menu.ink = ink
	_menu.unfocused_color = unfocused_color
	_menu.lay_out(anchor.x, anchor.y,
			InkType.tracked(item_font, item_size, tracking_em), item_size,
			hairline_length_px * scale, hairline_gap_px * scale, hairline_thickness_px, item_gap_px * scale)

# `node`'s `property` to `to` over `seconds`; awaitable. One fade at a
# time.
func _fade(node: CanvasItem, to: float, seconds: float, property: NodePath = ^"modulate:a") -> void:
	_kill_tween()
	if seconds <= 0.0:
		node.set_indexed(property, to)
		return
	_tween = create_tween()
	_tween.tween_property(node, property, to, seconds)
	await _tween.finished

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
