extends CanvasLayer
class_name TitleMenu

# The title's type and menu, on the world: the game's title in Spectral
# Light and three items in the HUD's tracked caps (InkType.tracked(), like
# every caps label), the utility grey when unfocused, full ink with a
# short hairline to its left when focused. No background - the world
# behind is the zone intro's frame zero (ZoneIntro's TITLE_HOLD: the
# field loaded, the camera in the opening pose, the fog closed so only
# the tower shows), which is what makes Start immediate and the colour
# behind the type the rendered fog itself, never a flat rect.
#
# Focus is the items' own index, not Godot's Control focus, kept by an
# InkMenu (the item drawing and input every menu in this style shares):
# ui_up/ui_down move it (wrapping), ui_accept activates, the mouse moves
# it by hovering and activates by clicking. Start has it on load. Start
# and Exit end the menu: the first of them wins - every input path returns
# early after it - and what it asks for goes out as a signal:
# start_requested (ZoneIntro then calls lock() and fade_out(), and runs
# the intro) or exit_requested (Exit is hidden where quitting means
# nothing, on the web). Cards doesn't end it and doesn't lock: it opens a
# CardCompendium as this node's child with the column hidden, input here
# held off while it is open, and its close shows the column again with
# focus still on Cards. The press that activated is consumed here; its
# release is all that reaches the field.
#
# Every size is authored for a 1080-high viewport and scaled by the
# viewport height; the layout is redone on every resize.

signal start_requested
signal exit_requested

const TITLE_FONT_PATH := "res://assets/fonts/Spectral-Light.ttf"
const REFERENCE_VIEWPORT_HEIGHT := 1080.0

# In menu order - each value is its item's index in the InkMenu.
enum Item { START, CARDS, EXIT }

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
# What Cards opens (a CardCompendium), loaded at each open.
@export var compendium_scene_path: String = "res://ui/card_compendium.tscn"

@onready var column: Control = $Column
@onready var title_label: Label = $Column/TitleLabel
@onready var start_item: Control = $Column/StartItem
@onready var cards_item: Control = $Column/CardsItem
@onready var exit_item: Control = $Column/ExitItem

# The items in menu order; an item hidden for the platform (Exit on web)
# is left out of the wrap.
var _menu: InkMenu = null
# The open card compendium, or null - input here waits while it is set.
var _compendium: CardCompendium = null
# The running column fade, in or out - one at a time.
var _fade_tween: Tween = null

func _ready() -> void:
	if OS.has_feature("web"):
		exit_item.visible = false
	var items: Array[Control] = [start_item, cards_item, exit_item]
	_menu = InkMenu.new(items, Item.START)
	_menu.activated.connect(_activate)
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
	_menu.ink = ink
	_menu.unfocused_color = unfocused_color
	_menu.lay_out(left, title_label.position.y + title_label.size.y + title_to_items_gap_px * scale,
			InkType.tracked(item_font, item_size, item_tracking_em), item_size,
			hairline_length_px * scale, hairline_gap_px * scale, hairline_thickness_px, item_gap_px * scale)

# --- the owner's side ---------------------------------------------------

# No input from here on, whatever the device - called by the owner on
# start_requested (and by _activate() itself first).
func lock() -> void:
	_menu.lock()

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

func _unhandled_input(event: InputEvent) -> void:
	if _menu.handle_input(event):
		get_viewport().set_input_as_handled()

# The one gate: the first activation of Start or Exit wins and everything
# after it is ignored, whichever device it came from. Cards passes
# through without locking - the menu comes back when the compendium
# closes.
func _activate(index: int) -> void:
	if _menu.locked or _compendium != null:
		return
	if index == Item.CARDS:
		_open_compendium()
		return
	lock()
	match index:
		Item.START:
			start_requested.emit()
		Item.EXIT:
			exit_requested.emit()

# --- the card compendium ------------------------------------------------

# The compendium over the held frame, the column hidden under it. A
# child, so it runs through ZoneIntro's freeze as this node does.
func _open_compendium() -> void:
	var scene := load(compendium_scene_path) as PackedScene
	if scene == null:
		push_warning("TitleMenu: could not load %s; Cards does nothing." % compendium_scene_path)
		return
	var compendium := scene.instantiate() as CardCompendium
	if compendium == null:
		push_warning("TitleMenu: %s is not a CardCompendium; Cards does nothing." % compendium_scene_path)
		return
	_compendium = compendium
	_menu.held = true
	compendium.closed.connect(_on_compendium_closed)
	column.visible = false
	add_child(compendium)

# Back to the menu as it was left: the column shown, focus on Cards.
func _on_compendium_closed() -> void:
	_compendium = null
	_menu.held = false
	column.visible = true
	_menu.apply_focus()
