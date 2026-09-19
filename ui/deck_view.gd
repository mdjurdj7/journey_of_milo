extends Control
class_name DeckView

# Emitted right before queue_free(), regardless of which of the three
# close paths fired (DeckPanel's own toggle-close, a scrim click, or
# Escape) - DeckPanel connects to this to clear its own "a view from me
# is currently open" reference (see its _on_deck_view_closed()), so that
# stays accurate no matter how this instance actually closed.
signal closed()

# Full-screen dark scrim behind a scrollable grid of CardView instances,
# sorted by name - browsing only (hover_enabled is turned off on every
# card, so nothing lifts/fights the grid layout). Escape or a click
# outside the content panel closes it. Dumb about where its cards/header
# came from - DeckPanel decides that (whole deck vs. a battle pile) and
# calls open() with a plain card list and a pre-formatted header string.
#
# Layout is containers all the way down, no manually-computed position
# anywhere: Scrim (full-rect) -> CenterContainer (full-rect) ->
# ContentPanel, sized only via custom_minimum_size (a fraction of the
# viewport) and placed by CenterContainer itself -> MarginContainer ->
# VBoxContainer -> HeaderLabel + a filling ScrollContainer -> a second
# CenterContainer (GridCenterContainer, EXPAND_FILL - see _ready()'s own
# doc on why a real CenterContainer is needed here rather than a size
# flag on GridContainer itself) -> GridContainer, which ends up centered
# with equal left/right margins whenever it's narrower than the available
# width (fewer cards than fit, or the column cap itself - see _compute_
# column_count()).
#
# Opened via DeckPanel._open_deck_view(), added directly under the
# SceneTree's own root so it renders full-screen over both the field and
# any battle overlay regardless of which one is currently active - not a
# child of either, and not otherwise part of any other scene's tree.

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

@export var scrim_color: Color = Color(0.0, 0.0, 0.0, 0.6)
@export_range(0.1, 1.0) var content_width_fraction: float = 0.75
@export_range(0.1, 1.0) var content_height_fraction: float = 0.8
@export var content_margin_px: int = 24
@export var header_grid_gap_px: int = 24
@export var grid_h_separation: float = 20.0
@export var grid_v_separation: float = 20.0
@export var header_font_size_px: int = 28
# Applied to every CardView in the grid (both .scale and the slot
# reserving only its scaled footprint) so a whole pile reads at a glance
# instead of needing to scroll through full hand-sized cards.
@export_range(0.1, 1.0) var deck_view_card_scale: float = 0.75

# Inspect: clicking a card in the grid lifts THAT SAME CardView out of
# its slot, over a dim, at reading size. The same instance rather than a
# second one so the card can't drift from the grid's - one layout, one
# set of colours, text simply larger. Lifting it out of the tree is also
# what makes it possible at all: in the grid it lives inside a
# ScrollContainer, which clips, so a card scaled up in place would be cut
# off at the panel's edge.
@export_group("Inspect")
@export var inspect_scale: float = 2.2
@export var inspect_duration_sec: float = 0.15
# CardView's own ink at 35% - the same dark the cards are drawn with, so
# the dim reads as the deck receding rather than as a new surface.
@export var inspect_scrim_color: Color = Color(0.165, 0.165, 0.18, 0.35)
@export_group("")
# Hard cap regardless of how much width is actually available - past a
# point, more columns just means smaller reading distance between eye and
# card, not a more useful browse. GridCenterContainer keeps the grid
# centered whenever fewer than this many columns end up fitting anyway.
@export var max_columns: int = 7

@export_group("Panel/Card Contrast")
# Two ways to make cards read as objects sitting ON this view rather than
# blending into it - both computed from the theme's own panel_color ->
# panel_light_color delta (one "step"), extrapolated by the given step
# count rather than a separately-tuned color, so they track the theme
# automatically. Both are real, independent toggles (not mutually
# exclusive) but this feature's own spec calls for shipping with the
# lighter panel active and the card edge off.
@export var use_lighter_content_panel: bool = true
@export var content_panel_steps: int = 2
@export var use_card_edge: bool = false
@export var card_edge_steps: int = 1
# How far each step moves the edge from the card's bone toward its ink.
@export_range(0.0, 1.0) var card_edge_step_fraction: float = 0.15
@export var card_edge_width_px: float = 1.0

@onready var _scrim: ColorRect = $Scrim
@onready var _center_container: CenterContainer = $Scrim/CenterContainer
@onready var _content_panel: PanelContainer = $Scrim/CenterContainer/ContentPanel
@onready var _margin: MarginContainer = $Scrim/CenterContainer/ContentPanel/Margin
@onready var _vbox: VBoxContainer = $Scrim/CenterContainer/ContentPanel/Margin/VBox
@onready var _header_label: Label = $Scrim/CenterContainer/ContentPanel/Margin/VBox/HeaderLabel
@onready var _scroll_container: ScrollContainer = $Scrim/CenterContainer/ContentPanel/Margin/VBox/ScrollContainer
@onready var _grid_center: CenterContainer = $Scrim/CenterContainer/ContentPanel/Margin/VBox/ScrollContainer/GridCenterContainer
@onready var _grid: GridContainer = $Scrim/CenterContainer/ContentPanel/Margin/VBox/ScrollContainer/GridCenterContainer/GridContainer
@onready var _inspect_layer: Control = $InspectLayer
@onready var _inspect_scrim: ColorRect = $InspectLayer/InspectScrim

# The width _grid actually has to lay columns out in, derived arithmetically
# from content_width_fraction/content_margin_px rather than read back off
# the live container tree - VBox/ScrollContainer/GridCenterContainer all
# stretch to fill Margin's content width, so this is exactly that width
# without needing to wait for a layout pass to settle before open() can
# use it.
var _available_grid_width: float = 0.0
# The card currently lifted out for inspection, and the slot it came
# from - the slot stays in the grid holding its footprint, so nothing
# reflows while a card is out and it has somewhere exact to go back to.
var _inspected: CardView = null
var _inspect_slot: Control = null
var _inspect_tween: Tween = null
# True for the length of a lift or a return - see _on_card_clicked().
var _inspect_busy: bool = false

# One "step" in the theme's own value set - the delta between panel_color
# and panel_light_color, extrapolated by content_panel_steps/
# card_edge_steps below rather than picked as an arbitrary lighten
# amount, so both stay in the theme's own voice.
var _card_edge_color: Color = Color.WHITE

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_scrim.color = scrim_color
	_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)

	# mouse_filter IGNORE, not the Control default STOP - CenterContainer
	# has no visual footprint of its own and spans the full screen, so
	# leaving it at STOP would swallow every click outside ContentPanel
	# (anywhere in that full-rect area) before it could ever reach this
	# node's own _gui_input() below, breaking "click outside closes."
	_center_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_center_container.set_anchors_preset(Control.PRESET_FULL_RECT)

	# No position/anchor math for ContentPanel itself - custom_minimum_size
	# is the only input CenterContainer needs to size and center it.
	var viewport_size: Vector2 = get_viewport_rect().size
	var content_size := Vector2(viewport_size.x * content_width_fraction, viewport_size.y * content_height_fraction)
	_content_panel.custom_minimum_size = content_size
	_content_panel.mouse_filter = Control.MOUSE_FILTER_STOP

	_available_grid_width = content_size.x - float(content_margin_px) * 2.0

	# Above Scrim in the scene, so the lifted card and its dim cover the
	# grid and the panel alike. IGNORE on the layer itself and STOP on the
	# scrim inside it: while a card is out, the scrim is what catches
	# "click anywhere", and it has to catch it BEFORE this node's own
	# _gui_input() closes the whole view.
	_inspect_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inspect_layer.visible = false
	_inspect_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_inspect_scrim.color = inspect_scrim_color
	_inspect_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	_inspect_scrim.gui_input.connect(_on_inspect_scrim_gui_input)
	# Starts fully transparent and is faded in by the lift; the colour's
	# own 0.35 is the target, modulate is what animates to it.
	_inspect_scrim.modulate.a = 0.0

	var panel_color: Color = get_theme_color("panel_color", "CardFace")
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var step: Color = Color(
		panel_light_color.r - panel_color.r,
		panel_light_color.g - panel_color.g,
		panel_light_color.b - panel_color.b,
		0.0
	)

	var content_bg_color: Color = panel_color
	if use_lighter_content_panel:
		content_bg_color = panel_color + step * float(content_panel_steps)
	var style := StyleBoxFlat.new()
	style.bg_color = content_bg_color
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_right = 12
	style.corner_radius_bottom_left = 12
	_content_panel.add_theme_stylebox_override("panel", style)

	# Cards are always ink-on-bone (they don't take the theme's value set -
	# see CardView), so their browsing edge steps the card's own bone
	# toward its ink rather than following panel_color.
	var reference_card := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	_card_edge_color = reference_card.field_color.lerp(reference_card.ink_color, card_edge_step_fraction * float(card_edge_steps))
	reference_card.free()

	_margin.add_theme_constant_override("margin_left", content_margin_px)
	_margin.add_theme_constant_override("margin_top", content_margin_px)
	_margin.add_theme_constant_override("margin_right", content_margin_px)
	_margin.add_theme_constant_override("margin_bottom", content_margin_px)

	_vbox.add_theme_constant_override("separation", header_grid_gap_px)

	_header_label.add_theme_color_override("font_color", text_color)
	_header_label.add_theme_font_size_override("font_size", header_font_size_px)

	# Horizontal scroll is never actually wanted (columns are already capped
	# to fit _available_grid_width - see _compute_column_count()) - left at
	# ScrollContainer's own default (AUTO), it sizes its DIRECT child to
	# exactly that child's own minimum width on this axis regardless of
	# whether scrolling is actually needed, leaving GridCenterContainer no
	# extra room to center into. DISABLED makes ScrollContainer treat this
	# axis like a normal stretch container instead, handing GridCenter
	# Container the full available width. Vertical scrolling (a tall pile)
	# is untouched.
	_scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	# ScrollContainer does not honor a direct child's own size_flags for
	# centering purposes (confirmed: GridContainer's own SHRINK_CENTER,
	# even with scrolling disabled above, still left it flush left) - the
	# working fix is structural, not a flag on the grid itself:
	# GridCenterContainer sits between ScrollContainer and GridContainer
	# specifically so a real CenterContainer (which always centers its own
	# child, regardless of that child's flags) does the centering.
	# EXPAND_FILL is what makes ScrollContainer stretch THIS node to the
	# full available width in the first place, giving it room to center
	# GridContainer into whenever the grid is narrower than that.
	_grid_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_grid.add_theme_constant_override("h_separation", int(grid_h_separation))
	_grid.add_theme_constant_override("v_separation", int(grid_v_separation))

func open(cards: Array[CardData], header_text: String) -> void:
	_header_label.text = header_text

	var sorted_cards := cards.duplicate()
	sorted_cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name < b.card_name)

	for child in _grid.get_children():
		child.queue_free()

	# A throwaway instance purely to read CardView's own card_size (never
	# added to the tree, so free() - not queue_free() - is safe) - avoids
	# hardcoding a second copy of that size here just to size the grid.
	var reference_card := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	var scaled_card_size: Vector2 = reference_card.card_size * deck_view_card_scale
	reference_card.free()

	_grid.columns = _compute_column_count(scaled_card_size.x, sorted_cards.size())

	for card in sorted_cards:
		var slot := Control.new()
		var card_view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
		card_view.hover_enabled = false
		# Set before add_child(), same as hover_enabled above - scale
		# shrinks the rendered card toward its own top-left corner
		# (pivot_offset's default), which is exactly the corner slot's
		# custom_minimum_size below reserves the footprint from.
		card_view.pivot_offset = Vector2.ZERO
		card_view.scale = Vector2(deck_view_card_scale, deck_view_card_scale)
		if use_card_edge:
			card_view.edge_color_override_enabled = true
			card_view.edge_color = _card_edge_color
			card_view.edge_width_px = card_edge_width_px
		slot.custom_minimum_size = scaled_card_size
		slot.add_child(card_view)
		_grid.add_child(slot)
		card_view.set_card_data(card)
		# The card carries its own slot to the handler - the slot is where
		# it has to land again, and looking it up later through get_parent()
		# wouldn't work while the card is out of the tree it came from.
		card_view.clicked.connect(_on_card_clicked.bind(card_view, slot))

# Largest column count whose total width (n cards plus (n-1) gaps between
# them) still fits _available_grid_width, floored at 1 (a single huge
# card never divides out to zero columns), capped at max_columns
# regardless of how much width is actually available, and also capped at
# card_count - a pile with fewer cards than would otherwise fit no longer
# reserves more columns than it has cards for, which used to leave a
# short last row inside an unnecessarily wide grid (still centered as a
# block by GridCenterContainer, but reading as lopsided internally).
func _compute_column_count(scaled_card_width: float, card_count: int) -> int:
	var columns: int = int((_available_grid_width + grid_h_separation) / (scaled_card_width + grid_h_separation))
	columns = maxi(columns, 1)
	columns = mini(columns, max_columns)
	return mini(columns, maxi(card_count, 1))

# Frees the wrapping CanvasLayer DeckPanel._open_deck_view() parents this
# under (see DeckPanel.DECK_VIEW_LAYER's own doc), not just this node -
# that CanvasLayer has no purpose once this is gone, and would otherwise
# linger as an empty, harmless-but-orphaned node. Falls back to freeing
# self directly if that's ever not the case (defensive only - every real
# caller today goes through that wrapper).
func close() -> void:
	closed.emit()
	var wrapper := get_parent()
	if wrapper is CanvasLayer:
		wrapper.queue_free()
	else:
		queue_free()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()

# Escape backs out one level at a time: it puts an inspected card down
# before it closes the view, so the key never skips a step the click
# can't.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _inspected != null:
			_end_inspect()
		else:
			close()
		get_viewport().set_input_as_handled()

# --- Inspect ---

# A grid card was clicked, or the inspected one was clicked again. Only
# those two reach here: while a card is out, the scrim covers the grid,
# so no OTHER card can be clicked and there is no card-to-card swap to
# handle. _inspect_busy holds off both for the length of a transition,
# so a click landing mid-flight can't start a second one on a card that
# is currently between parents.
func _on_card_clicked(_card_data: CardData, card_view: CardView, slot: Control) -> void:
	if _inspect_busy:
		return
	if _inspected == card_view:
		_end_inspect()
	elif _inspected == null:
		_begin_inspect(card_view, slot)

func _on_inspect_scrim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_end_inspect()
		get_viewport().set_input_as_handled()

# Lifts the card out of its slot into the overlay, keeping it exactly
# where it looked, then grows it to the middle of the screen. Its global
# position is captured and re-applied by hand rather than trusting the
# reparent: the card leaves a ScrollContainer (scrolled, and clipping)
# for a full-rect layer, and the two don't share an origin.
func _begin_inspect(card_view: CardView, slot: Control) -> void:
	var from_position: Vector2 = card_view.global_position
	slot.remove_child(card_view)
	_inspect_layer.add_child(card_view)
	card_view.global_position = from_position

	_inspected = card_view
	_inspect_slot = slot
	_inspect_layer.visible = true
	_tween_inspect(card_view, _inspect_centre(card_view), inspect_scale, 1.0)

# Puts it back: the reverse tween onto the slot's own screen position,
# then home into the slot at a clean zero offset so the grid owns its
# placement again.
func _end_inspect() -> void:
	if _inspected == null or _inspect_busy:
		return
	var card_view: CardView = _inspected
	var slot: Control = _inspect_slot
	_inspected = null
	_inspect_slot = null
	_tween_inspect(card_view, slot.global_position, deck_view_card_scale, 0.0)
	_inspect_tween.tween_callback(func() -> void:
		if is_instance_valid(card_view) and is_instance_valid(slot):
			card_view.get_parent().remove_child(card_view)
			slot.add_child(card_view)
			card_view.position = Vector2.ZERO
		_inspect_layer.visible = false)

# Top-left that centres the card at `inspect_scale`. pivot_offset is
# ZERO on these (see open()), so a card grows down-right from its own
# position and its rendered size is card_size x scale - the centring has
# to account for that rather than just using the viewport's middle.
func _inspect_centre(card_view: CardView) -> Vector2:
	return (get_viewport_rect().size - card_view.card_size * inspect_scale) / 2.0

func _tween_inspect(card_view: CardView, to_position: Vector2, to_scale: float, scrim_alpha: float) -> void:
	if _inspect_tween != null and _inspect_tween.is_valid():
		_inspect_tween.kill()
	_inspect_busy = true
	_inspect_tween = create_tween()
	_inspect_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_inspect_tween.set_parallel(true)
	_inspect_tween.tween_property(card_view, "global_position", to_position, inspect_duration_sec)
	_inspect_tween.tween_property(card_view, "scale", Vector2.ONE * to_scale, inspect_duration_sec)
	_inspect_tween.tween_property(_inspect_scrim, "modulate:a", scrim_alpha, inspect_duration_sec)
	_inspect_tween.chain()
	_inspect_tween.tween_callback(func() -> void: _inspect_busy = false)
