extends RefCounted
class_name InkMenu

# The title's menu items, shared by every menu in that style: TitleMenu
# and RunEnd (the won end and both deaths). Each item is a Control with a
# Label and a Hairline (ColorRect) child, stacked on one left edge: tracked
# caps, the utility grey when unfocused, full ink with a short hairline in
# the margin to its left when focused. Nothing else changes with focus.
#
# Input as the title has it: ui_up/ui_down move focus through the visible
# items (wrapping), ui_accept activates, the mouse focuses by hovering and
# activates by clicking - the press consumed. Activation goes out as
# activated(index); the owner decides what it does, and calls lock() for
# an item that ends the menu - from then on nothing responds, whatever
# the device. `held` keeps the menu where it is but deaf (TitleMenu while
# its card compendium is open).
#
# A helper the owner holds, not a node: the owner's scene keeps its own
# item nodes and its own _unhandled_input(), handing events to
# handle_input().

signal activated(index: int)

var items: Array[Control] = []
var focused: int = 0
var locked: bool = false
var held: bool = false
var ink: Color = Color(0.165, 0.165, 0.18, 1.0)
var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0)

func _init(menu_items: Array[Control], first_focus: int = 0) -> void:
	items = menu_items
	focused = first_focus
	for index in items.size():
		var item: Control = items[index]
		item.mouse_entered.connect(_on_item_mouse_entered.bind(index))
		item.gui_input.connect(_on_item_gui_input.bind(index))

# Stacks the visible items from `top` on the left edge `left`: each label
# in `font` at size_px, its hairline hairline_length long, hairline_gap
# clear of the text, hairline_thickness thick (never scaled), item_gap
# between items. Returns the y just past the last item's gap. Applies
# focus.
func lay_out(left: float, top: float, font: Font, size_px: int, hairline_length: float, hairline_gap: float, hairline_thickness: float, item_gap: float) -> float:
	var y: float = top
	for item in items:
		if not item.visible:
			continue
		var label := item.get_node(^"Label") as Label
		var hairline := item.get_node(^"Hairline") as ColorRect
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", size_px)
		label.size = label.get_combined_minimum_size()
		label.position = Vector2(hairline_length + hairline_gap, 0.0)
		item.position = Vector2(left - hairline_length - hairline_gap, y)
		item.size = Vector2(label.position.x + label.size.x, label.size.y)
		hairline.size = Vector2(hairline_length, hairline_thickness)
		hairline.position = Vector2(0.0, (label.size.y - hairline_thickness) * 0.5)
		hairline.color = ink
		y += label.size.y + item_gap
	apply_focus()
	return y

func apply_focus() -> void:
	for index in items.size():
		var item: Control = items[index]
		var is_focused: bool = index == focused
		(item.get_node(^"Label") as Label).add_theme_color_override("font_color", ink if is_focused else unfocused_color)
		(item.get_node(^"Hairline") as ColorRect).visible = is_focused

func lock() -> void:
	locked = true

func set_focus(index: int) -> void:
	if locked or held or index == focused or not items[index].visible:
		return
	focused = index
	apply_focus()

# Up/down through the visible items, wrapping at both ends.
func move_focus(step: int) -> void:
	var visible_indices: Array[int] = []
	for index in items.size():
		if items[index].visible:
			visible_indices.append(index)
	if visible_indices.is_empty():
		return
	var at: int = maxi(visible_indices.find(focused), 0)
	set_focus(visible_indices[posmod(at + step, visible_indices.size())])

# The owner's _unhandled_input() hands its events here; true when one was
# the menu's (the owner then marks it handled).
func handle_input(event: InputEvent) -> bool:
	if locked or held:
		return false
	if event.is_action_pressed("ui_down"):
		move_focus(1)
	elif event.is_action_pressed("ui_up"):
		move_focus(-1)
	elif event.is_action_pressed("ui_accept"):
		activated.emit(focused)
	else:
		return false
	return true

func _on_item_mouse_entered(index: int) -> void:
	set_focus(index)

func _on_item_gui_input(event: InputEvent, index: int) -> void:
	if locked or held:
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	set_focus(index)
	items[index].get_viewport().set_input_as_handled()
	activated.emit(index)
