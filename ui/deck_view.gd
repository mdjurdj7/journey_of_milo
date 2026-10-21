extends Control
class_name DeckView

# Emitted right before queue_free(), regardless of which close path fired
# (DeckPanel's own toggle-close, a click off the cards, BACK, or Escape) -
# DeckPanel connects to this to clear its own "a view from me is
# currently open" reference (see its _on_deck_view_closed()), so that
# stays accurate no matter how this instance actually closed.
signal closed()
# Pick mode only (pick_mode): the card clicked, emitted just before the
# view closes. A view that closes without it was cancelled.
signal card_picked(card: CardData)

# A pile of cards to scan, in the screens' own language: ink on the world
# - the reward screen's ink scrim, bone labels with an ink outline,
# tracked caps, no box or panel. The heading (the caller's text, in caps:
# DECK, DRAW PILE, HAND ONE OVER) at the top; then the cards in rows by
# type - ATTACKS, SKILLS, POWERS, STANCES (and OTHER, should a card be
# none of those) - each under its caps heading, its count and a hairline,
# sorted by cost then name; then BACK at the bottom. POWERS and STANCES
# share a line when both are short enough to. Identical cards (the same
# name as carried, tempered or not, a fight-only copy apart) are one card
# with "×N" under it. The rows scroll; the wheel reaches the scroll
# through the cards.
#
# BACK, Escape, or a click anywhere off the cards closes it. A click on a
# card lifts it to read (Inspect, below) - or, in pick mode, picks it.
# Dumb about where its cards and heading came from - DeckPanel decides
# that (whole deck vs. a battle pile) and calls open() with a plain card
# list and a heading string.
#
# Opened via DeckPanel.open_view(), under the SceneTree's own root in a
# CanvasLayer of its own, so it renders full-screen over both the field
# and any battle overlay. Every size is in the 1080p canvas's pixels.

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const VOICE_FONT_PATH := "res://assets/fonts/Spectral-Italic.ttf"

@export_group("Page")
# The reward screen's scrim: its ink, so the world recedes rather than
# turning to a new surface.
@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.62):
	set(value):
		scrim_color = value
		_relayout()
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_relayout()
# The text outline under bone, and the rules' hairlines.
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_relayout()
# BACK at rest, and each heading's count: the utility grey.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_relayout()
@export var text_outline_px: int = 1:
	set(value):
		text_outline_px = maxi(value, 0)
		_relayout()
# The heading, BACK and the row headings, in tracked caps.
@export var label_size_px: int = 22:
	set(value):
		label_size_px = maxi(value, 1)
		_relayout()
@export_range(0.0, 1.0) var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_relayout()
# The heading's line top, from the top of the screen.
@export var title_top_px: float = 48.0:
	set(value):
		title_top_px = value
		_relayout()
@export var title_rows_gap_px: float = 32.0:
	set(value):
		title_rows_gap_px = value
		_relayout()
@export var back_text: String = "BACK":
	set(value):
		back_text = value
		_relayout()
# BACK's line bottom, from the bottom of the screen.
@export var back_bottom_px: float = 44.0:
	set(value):
		back_bottom_px = value
		_relayout()
@export var rows_back_gap_px: float = 28.0:
	set(value):
		rows_back_gap_px = value
		_relayout()
# The rows' width, centred.
@export_range(0.1, 1.0) var content_width_fraction: float = 0.85:
	set(value):
		content_width_fraction = value
		_relayout()
# BACK focused: bone, with this hairline to its left (the reward
# screen's).
@export var hairline_length_px: float = 28.0:
	set(value):
		hairline_length_px = value
		_relayout()
@export var hairline_gap_px: float = 14.0:
	set(value):
		hairline_gap_px = value
		_relayout()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_relayout()

@export_group("Rows")
@export var attacks_text: String = "ATTACKS":
	set(value):
		attacks_text = value
		_relayout()
@export var skills_text: String = "SKILLS":
	set(value):
		skills_text = value
		_relayout()
@export var powers_text: String = "POWERS":
	set(value):
		powers_text = value
		_relayout()
@export var stances_text: String = "STANCES":
	set(value):
		stances_text = value
		_relayout()
@export var other_text: String = "OTHER":
	set(value):
		other_text = value
		_relayout()
# The count beside each row's heading - its cards, stacks counted in full.
@export var count_size_px: int = 22:
	set(value):
		count_size_px = maxi(value, 1)
		_relayout()
@export var heading_count_gap_px: float = 14.0:
	set(value):
		heading_count_gap_px = value
		_relayout()
@export var heading_rule_gap_px: float = 10.0:
	set(value):
		heading_rule_gap_px = value
		_relayout()
# The hairline under each heading: ink-free bone at this alpha.
@export_range(0.0, 1.0) var rule_alpha: float = 0.35:
	set(value):
		rule_alpha = value
		_relayout()
@export var rule_cards_gap_px: float = 16.0:
	set(value):
		rule_cards_gap_px = value
		_relayout()
# Between one row and the next heading.
@export var group_gap_px: float = 40.0:
	set(value):
		group_gap_px = value
		_relayout()
# Between POWERS and STANCES when they share a line.
@export var shared_group_gap_px: float = 56.0:
	set(value):
		shared_group_gap_px = value
		_relayout()
# Every card at this scale (hand_container.gd's own doc names it).
@export_range(0.1, 1.0) var deck_view_card_scale: float = 0.75:
	set(value):
		deck_view_card_scale = value
		_relayout()
@export var card_gap_px: float = 20.0:
	set(value):
		card_gap_px = value
		_relayout()
# Under a stack of identical cards, right-aligned: how many.
@export var stack_count_format: String = "×%d":
	set(value):
		stack_count_format = value
		_relayout()
@export var stack_count_size_px: int = 20:
	set(value):
		stack_count_size_px = maxi(value, 1)
		_relayout()
@export var stack_count_gap_px: float = 6.0:
	set(value):
		stack_count_gap_px = value
		_relayout()

# Inspect: clicking a card lifts THAT SAME CardView out of its slot, over
# a dim, at reading size. The same instance rather than a second one so
# the card can't drift from the row's - one layout, one set of colours,
# text simply larger. Lifting it out of the tree is also what makes it
# possible at all: in the rows it lives inside a ScrollContainer, which
# clips, so a card scaled up in place would be cut off. A stack's card
# lifts; its count stays under the slot.
@export_group("Inspect")
@export var inspect_scale: float = 2.2
@export var inspect_duration_sec: float = 0.15
# CardView's own ink at 35% - the same dark the cards are drawn with, so
# the dim reads as the deck receding rather than as a new surface.
@export var inspect_scrim_color: Color = Color(0.165, 0.165, 0.18, 0.35)
@export_group("")

# Off (every view DeckPanel opens for browsing): a click lifts a card to
# read, as above. On (DeckPanel.open_picker() - the collector's HAND ONE
# OVER): a click picks that card instead - one of a stack's, all alike -
# card_picked, then close(); BACK, Escape or a click off the cards closes
# with no pick, which is the caller's cancel. Read at the click.
@export var pick_mode: bool = false

# A pick that waits for a yes (the collector's removal - set by the host
# before open()): with pick_confirm_format set, a click in pick mode lifts
# the card to pick_inspect_scale instead, its centre at pick_inspect_
# centre_fraction of the height, and three lines under it - the confirm
# (pick_confirm_format with the card's name, in caps, then pick_confirm_
# price in Spectral numerals when it is 0 or more), pick_detail_format
# (with the pile's count and one fewer) in the grey, and BACK. The confirm
# emits card_picked and closes; BACK, Escape or a click anywhere else
# puts the card down with nothing picked. The mouse focuses by hovering;
# ui_up/ui_down move between the confirm and BACK, ui_accept acts.
@export_group("Pick Confirm")
@export var pick_confirm_format: String = "":
	set(value):
		pick_confirm_format = value
		_redraw_footer()
@export var pick_confirm_price: int = -1:
	set(value):
		pick_confirm_price = value
		_redraw_footer()
@export var pick_detail_format: String = "":
	set(value):
		pick_detail_format = value
		_redraw_footer()
@export var pick_inspect_scale: float = 1.5
@export_range(0.0, 1.0) var pick_inspect_centre_fraction: float = 0.4
# From the lifted card's bottom edge to the confirm line's top.
@export var pick_footer_gap_px: float = 36.0:
	set(value):
		pick_footer_gap_px = value
		_redraw_footer()
@export var pick_line_gap_px: float = 14.0:
	set(value):
		pick_line_gap_px = value
		_redraw_footer()
@export var pick_price_gap_px: float = 16.0:
	set(value):
		pick_price_gap_px = value
		_redraw_footer()

# The heading as the host wrote it, in Spectral Italic at voice_size_px -
# a world line (the collector's "It will not give it back.") - in place of
# the tracked caps.
@export var header_voice: bool = false:
	set(value):
		header_voice = value
		_relayout()
@export var voice_size_px: int = 26:
	set(value):
		voice_size_px = maxi(value, 1)
		_relayout()
@export_group("")

@onready var _scrim: ColorRect = $Scrim
@onready var _page: Control = $Page
@onready var _scroll: ScrollContainer = $ScrollContainer
@onready var _rows: VBoxContainer = $ScrollContainer/Rows
@onready var _inspect_layer: Control = $InspectLayer
@onready var _inspect_scrim: ColorRect = $InspectLayer/InspectScrim

# What open() was given, kept for a live relayout.
var _cards: Array[CardData] = []
var _header_text: String = ""
# Held, as every drawn face here is: a font loaded and dropped in a draw
# callback is freed with its glyphs as the callback returns.
var _label_font: Font = null
var _numeral_font: Font = null
var _back_hovered: bool = false
# Every slot in the rows, in order - get_card_views().
var _slots: Array[Control] = []
# The card currently lifted out for inspection, and the slot it came
# from - the slot stays in its row holding its footprint, so nothing
# reflows while a card is out and it has somewhere exact to go back to.
var _inspected: CardView = null
var _inspect_slot: Control = null
var _inspect_tween: Tween = null
# True for the length of a lift or a return - see _on_card_clicked().
var _inspect_busy: bool = false
# A pick waiting for its confirm (pick_confirm_format): the card lifted,
# its footer drawn on _footer, and which footer line has focus.
enum Footer { NONE = -1, CONFIRM, BACK }
var _pending_pick: CardData = null
var _footer: Control = null
var _footer_focus: int = Footer.NONE
var _voice_font: Font = null
var _card_height: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)

	_page.draw.connect(_draw_page)
	# PASS, not STOP: the scroll takes the wheel, and a click on its empty
	# space goes on up to _gui_input() and closes. Horizontal scroll is
	# never wanted - every row wraps to the width.
	_scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_rows.mouse_filter = Control.MOUSE_FILTER_PASS

	# Above everything else, so the lifted card and its dim cover the rows.
	# IGNORE on the layer itself and STOP on the scrim inside it: while a
	# card is out, the scrim is what catches "click anywhere", and it has to
	# catch it BEFORE this node's own _gui_input() closes the whole view.
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
	# The pending pick's lines, over the dim; the lifted card, added after
	# it, sits above them but never reaches down to them.
	_footer = Control.new()
	_footer.name = "PickFooter"
	_footer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_footer.draw.connect(_draw_footer)
	_inspect_layer.add_child(_footer)

	_refresh_page()

# `card` as the run's weapon makes it (the run state's as_carried()), or
# `card` itself with no run to ask. The run state is found at runtime by
# path and by what it answers, never named: naming the autoload here would
# compile it into every script that loads this view, and a headless
# script compiles those before the autoloads exist (keyword_table.gd's
# live_values() does the same).
func _as_carried(card: CardData) -> CardData:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var run_state: Node = tree.root.get_node_or_null(^"RunState") if tree != null else null
	if run_state == null or not run_state.has_method(&"as_carried"):
		return card
	return run_state.call(&"as_carried", card) as CardData

func open(cards: Array[CardData], header_text: String) -> void:
	_cards = cards.duplicate()
	_header_text = header_text
	_build()
	_page.queue_redraw()

# The cards on screen in the rows, slot by slot - a lifted one is out.
func get_card_views() -> Array[CardView]:
	var views: Array[CardView] = []
	for slot in _slots:
		if not is_instance_valid(slot):
			continue
		for child in slot.get_children():
			if child is CardView and not child.is_queued_for_deletion():
				views.append(child as CardView)
	return views

# A live edit: the page again, and the rows - not while a card is out,
# which has a slot to go back to.
func _relayout() -> void:
	if not is_node_ready():
		return
	_refresh_page()
	if _inspected == null and not _cards.is_empty():
		_build()

func _refresh_page() -> void:
	_scrim.color = scrim_color
	_label_font = InkType.tracked(InkType.text_bold_font(), label_size_px, tracking_em)
	_numeral_font = InkType.numeral_font()
	if header_voice and _voice_font == null:
		_voice_font = load(VOICE_FONT_PATH) as Font
	var view: Vector2 = get_viewport_rect().size
	var width: float = view.x * content_width_fraction
	var top: float = title_top_px + _line_height(label_size_px) + title_rows_gap_px
	var bottom: float = view.y - back_bottom_px - _line_height(label_size_px) - rows_back_gap_px
	_scroll.position = Vector2(roundf((view.x - width) * 0.5), roundf(top))
	_scroll.size = Vector2(roundf(width), maxf(roundf(bottom - top), 1.0))
	_page.queue_redraw()

func _line_height(size_px: int) -> float:
	if _label_font == null:
		return float(size_px)
	return _label_font.get_ascent(size_px) + _label_font.get_descent(size_px)

# --- Rows ---

func _build() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	_slots.clear()
	_rows.add_theme_constant_override("separation", roundi(group_gap_px))

	# A throwaway instance purely to read CardView's own card_size (never
	# added to the tree, so free() - not queue_free() - is safe).
	var reference_card := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	var card_size: Vector2 = reference_card.card_size * deck_view_card_scale
	reference_card.free()
	var slot_size := Vector2(card_size.x, card_size.y + stack_count_gap_px + _numeral_line_height())

	var groups: Dictionary = {}
	for stack: Dictionary in _stacks():
		var shown: CardData = stack["shown"]
		var key: int = int(shown.card_type) if [CardData.CardType.ATTACK, CardData.CardType.SKILL, CardData.CardType.POWER, CardData.CardType.STANCE].has(shown.card_type) else -1
		if not groups.has(key):
			groups[key] = [] as Array[Dictionary]
		(groups[key] as Array[Dictionary]).append(stack)

	var powers: Array[Dictionary] = groups.get(CardData.CardType.POWER, [] as Array[Dictionary])
	var stances: Array[Dictionary] = groups.get(CardData.CardType.STANCE, [] as Array[Dictionary])
	var share: bool = not powers.is_empty() and not stances.is_empty() and _line_width(powers.size(), slot_size.x) + shared_group_gap_px + _line_width(stances.size(), slot_size.x) <= _scroll.size.x

	for key: int in [CardData.CardType.ATTACK, CardData.CardType.SKILL, CardData.CardType.POWER, CardData.CardType.STANCE, -1]:
		if not groups.has(key):
			continue
		if share and key == CardData.CardType.STANCE:
			continue
		if share and key == CardData.CardType.POWER:
			var line := HBoxContainer.new()
			line.mouse_filter = Control.MOUSE_FILTER_PASS
			line.add_theme_constant_override("separation", roundi(shared_group_gap_px))
			_rows.add_child(line)
			_add_group(line, powers_text, powers, slot_size, _line_width(powers.size(), slot_size.x))
			_add_group(line, stances_text, stances, slot_size, _line_width(stances.size(), slot_size.x))
			continue
		_add_group(_rows, _group_text(key), groups[key], slot_size, 0.0)

# Each distinct card as carried (_as_carried() - Lash under Greyshelf's
# Tail), with every card of the pile it stands for - identical by name
# as carried (a tempered card's name has its +), a fight-only copy kept
# apart - sorted by cost, then name. A pick hands back the first of the
# stack's own cards, the ones the run's deck holds.
func _stacks() -> Array[Dictionary]:
	var by_key: Dictionary = {}
	var stacks: Array[Dictionary] = []
	for card in _cards:
		if card == null:
			continue
		var shown: CardData = _as_carried(card)
		var key: String = shown.card_name + ("#copy" if card.battle_copy else "")
		if not by_key.has(key):
			var stack: Dictionary = {"shown": shown, "cards": [] as Array[CardData]}
			by_key[key] = stack
			stacks.append(stack)
		((by_key[key] as Dictionary)["cards"] as Array[CardData]).append(card)
	stacks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var first: CardData = a["shown"]
		var second: CardData = b["shown"]
		if first.cost != second.cost:
			return first.cost < second.cost
		return first.card_name < second.card_name)
	return stacks

func _group_text(key: int) -> String:
	match key:
		CardData.CardType.ATTACK:
			return attacks_text
		CardData.CardType.SKILL:
			return skills_text
		CardData.CardType.POWER:
			return powers_text
		CardData.CardType.STANCE:
			return stances_text
	return other_text

# `count` slots side by side, gaps between.
func _line_width(count: int, slot_width: float) -> float:
	return float(count) * slot_width + float(maxi(count - 1, 0)) * card_gap_px

# One row: its heading and count, the hairline, then its cards wrapping
# to the width. `width` 0 fills the parent; else the block is that wide
# (a shared line's half).
func _add_group(parent: Container, text: String, stacks: Array[Dictionary], slot_size: Vector2, width: float) -> void:
	var block := VBoxContainer.new()
	block.mouse_filter = Control.MOUSE_FILTER_PASS
	block.add_theme_constant_override("separation", 0)
	if width > 0.0:
		block.custom_minimum_size = Vector2(width, 0.0)
	else:
		block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(block)

	var total: int = 0
	for stack in stacks:
		total += (stack["cards"] as Array[CardData]).size()
	var heading_text: String = text.to_upper()
	var count_text: String = str(total)
	var ascent: float = maxf(_label_font.get_ascent(label_size_px), _numeral_font.get_ascent(count_size_px))
	var descent: float = maxf(_label_font.get_descent(label_size_px), _numeral_font.get_descent(count_size_px))
	var heading := Control.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.custom_minimum_size = Vector2(0.0, ascent + descent)
	heading.draw.connect(func() -> void:
		var x: float = _text(heading, _label_font, heading_text, Vector2(0.0, ascent), label_size_px, bone)
		_text(heading, _numeral_font, count_text, Vector2(x + heading_count_gap_px, ascent), count_size_px, unfocused_color))
	block.add_child(heading)
	_add_spacer(block, heading_rule_gap_px)
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(0.0, hairline_thickness_px)
	rule.color = Color(bone.r, bone.g, bone.b, bone.a * rule_alpha)
	block.add_child(rule)
	_add_spacer(block, rule_cards_gap_px)

	var flow := HFlowContainer.new()
	flow.mouse_filter = Control.MOUSE_FILTER_PASS
	flow.add_theme_constant_override("h_separation", roundi(card_gap_px))
	flow.add_theme_constant_override("v_separation", roundi(card_gap_px))
	block.add_child(flow)
	for stack in stacks:
		_add_slot(flow, stack, slot_size)

# A CardView at rest in a slot that reserves its scaled footprint and the
# stack's count line under it. The card scales toward its own top-left
# (pivot ZERO), the corner the slot reserves from. PASS once it's in the
# tree (CardView's _ready() sets STOP) so the wheel still reaches the
# scroll through it; its click is taken here (_on_card_clicked()), so it
# never closes the view.
func _add_slot(flow: HFlowContainer, stack: Dictionary, slot_size: Vector2) -> void:
	var cards: Array[CardData] = stack["cards"]
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.custom_minimum_size = slot_size
	var card_view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	card_view.hover_enabled = false
	card_view.pivot_offset = Vector2.ZERO
	card_view.scale = Vector2(deck_view_card_scale, deck_view_card_scale)
	slot.add_child(card_view)
	flow.add_child(slot)
	card_view.mouse_filter = Control.MOUSE_FILTER_PASS
	card_view.set_card_data(stack["shown"] as CardData)
	_slots.append(slot)
	if cards.size() > 1:
		var count_text: String = stack_count_format % cards.size()
		var card_height: float = card_view.card_size.y * deck_view_card_scale
		slot.draw.connect(func() -> void:
			var ascent: float = _numeral_font.get_ascent(stack_count_size_px)
			var width: float = InkType.width(_numeral_font, count_text, stack_count_size_px)
			_text(slot, _numeral_font, count_text, Vector2(slot.size.x - width, card_height + stack_count_gap_px + ascent), stack_count_size_px, bone))
	# The card carries its own slot to the handler - the slot is where it
	# has to land again, and looking it up later through get_parent()
	# wouldn't work while the card is out of the tree it came from. The
	# handler gets the deck's own card, not the one shown.
	var own: CardData = cards[0]
	card_view.clicked.connect(func(_shown_card: CardData) -> void: _on_card_clicked(own, card_view, slot))

func _numeral_line_height() -> float:
	if _numeral_font == null:
		return float(stack_count_size_px)
	return _numeral_font.get_ascent(stack_count_size_px) + _numeral_font.get_descent(stack_count_size_px)

func _add_spacer(parent: Container, height_px: float) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0.0, height_px)
	parent.add_child(spacer)

# --- Page: the heading and BACK ---

# One bone run with its ink outline under it, as the reward screen draws
# its labels. Returns the advance width.
func _text(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	return InkType.draw_run(canvas, font, text, origin, size_px, color)

func _draw_page() -> void:
	if _label_font == null:
		return
	var view: Vector2 = get_viewport_rect().size
	var ascent: float = _label_font.get_ascent(label_size_px)
	if header_voice and _voice_font != null:
		var voice_width: float = InkType.width(_voice_font, _header_text, voice_size_px)
		_text(_page, _voice_font, _header_text, Vector2(roundf((view.x - voice_width) * 0.5), roundf(title_top_px + ascent)), voice_size_px, bone)
	else:
		var title: String = _header_text.to_upper()
		var title_width: float = InkType.width(_label_font, title, label_size_px)
		_text(_page, _label_font, title, Vector2(roundf((view.x - title_width) * 0.5), roundf(title_top_px + ascent)), label_size_px, bone)
	var back: Rect2 = _back_label_rect()
	var baseline: float = back.position.y + ascent
	_text(_page, _label_font, back_text, Vector2(back.position.x, baseline), label_size_px, bone if _back_hovered else unfocused_color)
	if _back_hovered:
		var mid: float = baseline - float(label_size_px) * 0.35
		_page.draw_rect(Rect2(back.position.x - hairline_gap_px - hairline_length_px, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# BACK's label, centred, back_bottom_px off the bottom.
func _back_label_rect() -> Rect2:
	var view: Vector2 = get_viewport_rect().size
	var width: float = InkType.width(_label_font, back_text, label_size_px)
	var height: float = _line_height(label_size_px)
	return Rect2(roundf((view.x - width) * 0.5), roundf(view.y - back_bottom_px - height), width, height)

# BACK's hit rect: the label and the hairline's room to its left.
func _back_rect() -> Rect2:
	var label: Rect2 = _back_label_rect()
	return label.grow_side(SIDE_LEFT, hairline_gap_px + hairline_length_px)

# --- Close ---

# Frees the wrapping CanvasLayer DeckPanel.open_view() parents this
# under (see DeckPanel.DECK_VIEW_LAYER's own doc), not just this node -
# that CanvasLayer has no purpose once this is gone. Falls back to freeing
# self directly if that's ever not the case.
func close() -> void:
	closed.emit()
	var wrapper := get_parent()
	if wrapper is CanvasLayer:
		wrapper.queue_free()
	else:
		queue_free()

# A click that reaches here landed off every card - on BACK, the scrim or
# the rows' empty space - and closes. The pointer over BACK focuses it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var over: bool = _back_rect().has_point((event as InputEventMouseMotion).position)
		if over != _back_hovered:
			_back_hovered = over
			_page.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()
		get_viewport().set_input_as_handled()

# Escape backs out one level at a time: it puts an inspected card down
# before it closes the view, so the key never skips a step the click
# can't.
func _unhandled_input(event: InputEvent) -> void:
	if _pending_pick != null and _inspected != null:
		if event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
			_set_footer_focus(Footer.BACK if _footer_focus == Footer.CONFIRM else Footer.CONFIRM)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			if _footer_focus != Footer.NONE:
				_activate_footer(_footer_focus)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _inspected != null:
			_end_inspect()
		else:
			close()
		get_viewport().set_input_as_handled()

# --- Inspect ---

# A card in the rows was clicked, or the inspected one was clicked again.
# Taken here, so the click goes no further up to _gui_input()'s close.
# While a card is out, the scrim covers the rows, so no OTHER card can be
# clicked and there is no card-to-card swap to handle. _inspect_busy
# holds off both for the length of a transition, so a click landing mid-
# flight can't start a second one on a card that is between parents.
func _on_card_clicked(card_data: CardData, card_view: CardView, slot: Control) -> void:
	card_view.accept_event()
	get_viewport().set_input_as_handled()
	if pick_mode and not _confirms_pick():
		card_picked.emit(card_data)
		close()
		return
	if _inspect_busy:
		return
	if _inspected == card_view:
		_end_inspect()
	elif _inspected == null:
		if pick_mode:
			_pending_pick = card_data
			_footer_focus = Footer.NONE
		_begin_inspect(card_view, slot)

func _on_inspect_scrim_gui_input(event: InputEvent) -> void:
	if _pending_pick != null and event is InputEventMouseMotion:
		_set_footer_focus(_footer_hit((event as InputEventMouseMotion).position))
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hit: int = _footer_hit((event as InputEventMouseButton).position) if _pending_pick != null else Footer.NONE
		if hit == Footer.CONFIRM:
			_activate_footer(Footer.CONFIRM)
		else:
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
	# Up for inspection: its keywords define themselves on hover.
	card_view.set_keyword_inspect(true)
	_tween_inspect(card_view, _inspect_centre(card_view), _inspect_target_scale(), 1.0)
	_redraw_footer()

# Puts it back: the reverse tween onto the slot's own screen position,
# then home into the slot at a clean zero offset so the row owns its
# placement again.
func _end_inspect() -> void:
	if _inspected == null or _inspect_busy:
		return
	var card_view: CardView = _inspected
	var slot: Control = _inspect_slot
	_inspected = null
	_inspect_slot = null
	_pending_pick = null
	_footer_focus = Footer.NONE
	_redraw_footer()
	card_view.set_keyword_inspect(false)
	_tween_inspect(card_view, slot.global_position, deck_view_card_scale, 0.0)
	_inspect_tween.tween_callback(func() -> void:
		if is_instance_valid(card_view) and is_instance_valid(slot):
			card_view.get_parent().remove_child(card_view)
			slot.add_child(card_view)
			card_view.position = Vector2.ZERO
		_inspect_layer.visible = false)

# Top-left that centres the card at `inspect_scale`. pivot_offset is
# ZERO on these (see _add_slot()), so a card grows down-right from its own
# position and its rendered size is card_size x scale - the centring has
# to account for that rather than just using the viewport's middle.
func _inspect_centre(card_view: CardView) -> Vector2:
	var view: Vector2 = get_viewport_rect().size
	var size: Vector2 = card_view.card_size * _inspect_target_scale()
	if _pending_pick != null:
		return Vector2((view.x - size.x) / 2.0, view.y * pick_inspect_centre_fraction - size.y / 2.0)
	return (view - size) / 2.0

func _inspect_target_scale() -> float:
	return pick_inspect_scale if _pending_pick != null else inspect_scale

# --- Pick confirm ---

func _confirms_pick() -> bool:
	return not pick_confirm_format.is_empty()

func _redraw_footer() -> void:
	if _footer != null:
		_footer.queue_redraw()

# The confirm line's text: the format with the pending card's name (as
# carried), in caps.
func _confirm_text() -> String:
	if _pending_pick == null:
		return ""
	var text: String = pick_confirm_format
	if text.contains("%s"):
		text = text % _as_carried(_pending_pick).card_name
	return text.to_upper()

func _detail_text() -> String:
	if pick_detail_format.is_empty():
		return ""
	return pick_detail_format % [_cards.size(), maxi(_cards.size() - 1, 0)]

# CardView's own height, read once from a throwaway instance.
func _reference_card_height() -> float:
	if _card_height <= 0.0:
		var reference_card := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
		_card_height = reference_card.card_size.y
		reference_card.free()
	return _card_height

# Footer row `index` (0 the confirm, 1 the detail, 2 BACK): its text,
# left edge, baseline and width (the confirm's price in it), centred under
# where the lifted card settles.
func _footer_line(index: int) -> Dictionary:
	var view: Vector2 = get_viewport_rect().size
	var card_bottom: float = view.y * pick_inspect_centre_fraction + _reference_card_height() * pick_inspect_scale / 2.0
	var pitch: float = _line_height(label_size_px) + pick_line_gap_px
	var ascent: float = _label_font.get_ascent(label_size_px) if _label_font != null else float(label_size_px)
	var text: String = back_text
	if index == 0:
		text = _confirm_text()
	elif index == 1:
		text = _detail_text()
	var width: float = InkType.width(_label_font, text, label_size_px)
	if index == 0 and pick_confirm_price >= 0:
		width += pick_price_gap_px + InkType.width(_numeral_font, str(pick_confirm_price), label_size_px)
	var baseline: float = roundf(card_bottom + pick_footer_gap_px + pitch * float(index) + ascent)
	return {"text": text, "left": roundf((view.x - width) * 0.5), "baseline": baseline, "width": width}

# The row's hit rect, with the hairline's room to its left.
func _footer_rect(index: int) -> Rect2:
	var line: Dictionary = _footer_line(index)
	var ascent: float = _label_font.get_ascent(label_size_px) if _label_font != null else float(label_size_px)
	var rect := Rect2(float(line["left"]), float(line["baseline"]) - ascent, float(line["width"]), _line_height(label_size_px))
	return rect.grow_side(SIDE_LEFT, hairline_gap_px + hairline_length_px)

func _footer_hit(position: Vector2) -> int:
	if _footer_rect(0).has_point(position):
		return Footer.CONFIRM
	if _footer_rect(2).has_point(position):
		return Footer.BACK
	return Footer.NONE

func _set_footer_focus(index: int) -> void:
	if index == _footer_focus:
		return
	_footer_focus = index
	_redraw_footer()

func _activate_footer(index: int) -> void:
	if _pending_pick == null or _inspect_busy:
		return
	if index == Footer.CONFIRM:
		var card: CardData = _pending_pick
		card_picked.emit(card)
		close()
	elif index == Footer.BACK:
		_end_inspect()

func _draw_footer() -> void:
	if _pending_pick == null or _label_font == null:
		return
	for index in 3:
		var line: Dictionary = _footer_line(index)
		var text: String = line["text"]
		var left: float = line["left"]
		var baseline: float = line["baseline"]
		var focused: bool = (index == 0 and _footer_focus == Footer.CONFIRM) or (index == 2 and _footer_focus == Footer.BACK)
		var color: Color = bone if focused else unfocused_color
		var advance: float = _text(_footer, _label_font, text, Vector2(left, baseline), label_size_px, color)
		if index == 0 and pick_confirm_price >= 0:
			_text(_footer, _numeral_font, str(pick_confirm_price), Vector2(roundf(left + advance + pick_price_gap_px), baseline), label_size_px, color)
		if focused:
			var mid: float = baseline - float(label_size_px) * 0.35
			_footer.draw_rect(Rect2(left - hairline_gap_px - hairline_length_px, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)

# For probes: the card a confirm is waiting on, else null.
func get_pending_pick() -> CardData:
	return _pending_pick

# For probes: the confirm and detail lines as shown ("" with nothing
# pending).
func get_confirm_text() -> String:
	return _confirm_text()

func get_detail_text() -> String:
	return _detail_text() if _pending_pick != null else ""

# For probes: the confirm or BACK, as a click or a key would.
func confirm_pick() -> void:
	_activate_footer(Footer.CONFIRM)

func back_out_of_pick() -> void:
	_activate_footer(Footer.BACK)

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
