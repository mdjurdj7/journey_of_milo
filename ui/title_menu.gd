extends CanvasLayer
class_name TitleMenu

# The title's type and menu, on the world: the game's title in Spectral
# Light and two items in the HUD's tracked caps (InkType.tracked(), like
# every caps label), the utility grey when unfocused, full ink with a
# short hairline to its left when focused. No background - the world
# behind is the zone intro's frame zero (ZoneIntro's TITLE_HOLD: the
# field loaded, the camera in the opening pose, the fog closed so only
# the tower shows), which is what makes Start immediate and the colour
# behind the type the rendered fog itself, never a flat rect.
#
# Focus is this script's own index, not Godot's Control focus: ui_up/
# ui_down move it (wrapping), ui_accept activates, the mouse moves it by
# hovering and activates by clicking. Start has it on load. The first
# activation wins - every input path returns early after it - and what
# it asks for goes out as a signal: start_requested (ZoneIntro then calls
# lock() and fade_out(), and runs the intro) or exit_requested (Exit is
# hidden where quitting means nothing, on the web). The press that
# activated is consumed here; its release is all that reaches the field.
#
# Every size is authored for a 1080-high viewport and scaled by the
# viewport height; the layout is redone on every resize.

signal start_requested
signal exit_requested

const TITLE_FONT_PATH := "res://assets/fonts/Spectral-Light.ttf"
const REFERENCE_VIEWPORT_HEIGHT := 1080.0

enum Item { START, EXIT }

@export var game_title: String = "The Journey of Milo":
	set(value):
		game_title = value
		_relayout_if_ready()

@export_group("Type")
# The title: Spectral Light, tracked a touch tight (Spectral runs loose
# at this size).
@export var title_font: Font = load(TITLE_FONT_PATH):
	set(value):
		title_font = value
		_relayout_if_ready()
@export var title_font_size_px: int = 96:
	set(value):
		title_font_size_px = value
		_relayout_if_ready()
@export var title_tracking_em: float = -0.02:
	set(value):
		title_tracking_em = value
		_relayout_if_ready()
# The items: the HUD's caps label - Alegreya Sans Bold at 0.16 em.
@export var item_font: Font = load(InkType.TEXT_BOLD_FONT_PATH):
	set(value):
		item_font = value
		_relayout_if_ready()
@export var item_font_size_px: int = 22:
	set(value):
		item_font_size_px = value
		_relayout_if_ready()
@export var item_tracking_em: float = 0.16:
	set(value):
		item_tracking_em = value
		_relayout_if_ready()

@export_group("Colour")
# The UI ink (BattleTheme's on_pale_ink) - the title, and the focused
# item and its hairline.
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_relayout_if_ready()
# The utility grey (CardView's keyline_utility) for an unfocused item.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_relayout_if_ready()

@export_group("Layout")
# The one left edge the title and both items share, as a fraction of
# the viewport width; the hairline hangs into the margin to its left.
@export var left_margin_fraction: float = 0.12:
	set(value):
		left_margin_fraction = value
		_relayout_if_ready()
# The title's top, as a fraction of the viewport height.
@export var title_y_fraction: float = 0.3:
	set(value):
		title_y_fraction = value
		_relayout_if_ready()
# Pixels at 1080p, below: title bottom to the first item, item to item,
# and the hairline's length, its gap to the text, and its thickness (the
# one thing not scaled - a hairline is a hairline).
@export var title_to_items_gap_px: float = 72.0:
	set(value):
		title_to_items_gap_px = value
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
# The column fades in over this on arrival - input is live from the
# first frame regardless, so focus and Start never wait on it.
@export var title_fade_in_seconds: float = 0.4
# How long the column takes to fade once Start is taken (fade_out()'s
# default).
@export var start_delay_seconds: float = 0.3

@onready var column: Control = $Column
@onready var title_label: Label = $Column/TitleLabel
@onready var start_item: Control = $Column/StartItem
@onready var exit_item: Control = $Column/ExitItem

# In menu order; an item hidden for the platform (Exit on web) is left
# out of _focusable() and so out of the wrap.
var _items: Array[Control] = []
var _focused: int = Item.START
var _activated: bool = false
# The running column fade, in or out - one at a time.
var _fade_tween: Tween = null

func _ready() -> void:
	_items = [start_item, exit_item]
	if OS.has_feature("web"):
		exit_item.visible = false
	for index in _items.size():
		var item: Control = _items[index]
		item.mouse_entered.connect(_on_item_mouse_entered.bind(index))
		item.gui_input.connect(_on_item_gui_input.bind(index))
	get_viewport().size_changed.connect(_relayout)
	_relayout()
	_fade_in()

func _relayout_if_ready() -> void:
	if is_inside_tree() and title_label != null:
		_relayout()

# Everything from the exports and the viewport: fonts rebuilt tracked at
# the scaled size, the title at the left edge and title_y_fraction, the
# items stacked under it on the same left edge, each item's hairline
# sitting in the margin to its left, and the focus colours applied.
func _relayout() -> void:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var scale: float = viewport_size.y / REFERENCE_VIEWPORT_HEIGHT
	var left: float = viewport_size.x * left_margin_fraction

	var title_size: int = maxi(roundi(float(title_font_size_px) * scale), 1)
	title_label.text = game_title
	title_label.add_theme_font_override("font", InkType.tracked(title_font, title_size, title_tracking_em))
	title_label.add_theme_font_size_override("font_size", title_size)
	title_label.add_theme_color_override("font_color", ink)
	title_label.size = title_label.get_combined_minimum_size()
	title_label.position = Vector2(left, viewport_size.y * title_y_fraction)

	var item_size: int = maxi(roundi(float(item_font_size_px) * scale), 1)
	var item_font_tracked: Font = InkType.tracked(item_font, item_size, item_tracking_em)
	var hairline_length: float = hairline_length_px * scale
	var hairline_gap: float = hairline_gap_px * scale
	var y: float = title_label.position.y + title_label.size.y + title_to_items_gap_px * scale
	for index in _items.size():
		var item: Control = _items[index]
		if not item.visible:
			continue
		var label := item.get_node(^"Label") as Label
		var hairline := item.get_node(^"Hairline") as ColorRect
		label.add_theme_font_override("font", item_font_tracked)
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

# The focused item in ink with its hairline shown; every other in the
# utility grey with none. Nothing else changes with focus.
func _apply_focus() -> void:
	for index in _items.size():
		var item: Control = _items[index]
		var label := item.get_node(^"Label") as Label
		var hairline := item.get_node(^"Hairline") as ColorRect
		var focused: bool = index == _focused
		label.add_theme_color_override("font_color", ink if focused else unfocused_color)
		hairline.visible = focused

# --- the owner's side ---------------------------------------------------

# No input from here on, whatever the device - called by the owner on
# start_requested (and by _activate() itself first).
func lock() -> void:
	_activated = true

# The column from nothing to full over title_fade_in_seconds, on
# arrival. Only the look - nothing waits on it.
func _fade_in() -> void:
	_kill_fade()
	if title_fade_in_seconds <= 0.0:
		column.modulate.a = 1.0
		return
	column.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(column, "modulate:a", 1.0, title_fade_in_seconds)

# The column to nothing over `seconds` (start_delay_seconds when not
# given); awaitable. What the owner runs before its own beat begins. A
# fade-in still running is cut, so the two never fight over the alpha.
func fade_out(seconds: float = -1.0) -> void:
	_kill_fade()
	var duration: float = start_delay_seconds if seconds < 0.0 else seconds
	if duration <= 0.0:
		column.modulate.a = 0.0
		return
	_fade_tween = create_tween()
	_fade_tween.tween_property(column, "modulate:a", 0.0, duration)
	await _fade_tween.finished

func _kill_fade() -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = null

# --- input --------------------------------------------------------------

func _focusable() -> Array[int]:
	var indices: Array[int] = []
	for index in _items.size():
		if _items[index].visible:
			indices.append(index)
	return indices

func _set_focus(index: int) -> void:
	if _activated or index == _focused or not _items[index].visible:
		return
	_focused = index
	_apply_focus()

# Up/down through the visible items, wrapping at both ends.
func _move_focus(step: int) -> void:
	var indices: Array[int] = _focusable()
	if indices.is_empty():
		return
	var at: int = maxi(indices.find(_focused), 0)
	_set_focus(indices[posmod(at + step, indices.size())])

func _unhandled_input(event: InputEvent) -> void:
	if _activated:
		return
	if event.is_action_pressed("ui_down"):
		_move_focus(1)
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)
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

# The one gate: the first activation wins and everything after it is
# ignored, whichever device it came from.
func _activate(index: int) -> void:
	if _activated:
		return
	lock()
	match index:
		Item.START:
			start_requested.emit()
		Item.EXIT:
			exit_requested.emit()
