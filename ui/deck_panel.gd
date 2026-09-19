extends Control
class_name DeckPanel

# A deck count as a line of ink: a tracked caps label ("DECK" /
# "DISCARD", Alegreya Sans Bold at label_alpha) and its count right after
# in Alegreya Sans Regular at full ink - the discard line also runs
# "SPENT n" on once anything is exhausted. Drawn, not boxed; sized to its
# own text so it can sit flush in a corner (align_right / align_bottom
# keep that corner edge put when the text changes width/height). Clicking
# it opens a DeckView of whatever it currently represents - toggled, so a
# second click closes it rather than stacking another.
#
# The one implementation behind every deck line, in two modes, switched
# via the two public methods below (never both active at once - each
# clears the other's state):
#
# - show_whole_deck(cards): a static list, no live Deck - the field HUD's
#   persistent instance (region_field.tscn, bottom-left), showing the
#   run's Belongings under draw_label_text since that's the same corner
#   the battle DECK line takes over. The list is held by reference;
#   RegionField re-lays it out on RunState.deck_changed.
# - bind_to_deck(deck, pile): tracks one pile (DRAW or DISCARD) of a live
#   battle Deck, updating on its drawn/discarded/shuffled signals - the
#   two instances BattleOverlay creates (DECK bottom-left under
#   BattleResources, DISCARD bottom-right under End Turn) while the field
#   instance is hidden. Both are the overlay's children, freed with it.
#
# Reads the theme's Battle/ink token, so it inverts with the on-pale/
# on-dark value set (see BattleTheme) - re-read via refresh_style().

const DECK_VIEW_SCENE_PATH := "res://ui/deck_view.tscn"

# CanvasLayer ordering across the whole field/battle UI: FieldHUD = 1 (HP
# bars), BattleLayer = 2 (hand, target line, End Turn - see region_field.
# tscn), DeckView's own scrim = 3, always on top of both regardless of
# which is active when it opens. DeckView itself has no CanvasLayer of
# its own (it's a plain Control, reused by both the field's persistent
# line and the battle lines - see its own doc) - open_view() below wraps
# it in one on the way into the tree; DeckView.close() frees that wrapper
# again (see its own doc).
const DECK_VIEW_LAYER: int = 3

enum Pile { DRAW, DISCARD }

# DeckView's header in whole-deck mode - the battle piles use "Draw pile"/
# "Discard pile" instead (see _open_deck_view() below), since the lines
# themselves already show the pile name.
@export var deck_title: String = "Belongings"

@export var label_font: Font = InkType.text_bold_font():
	set(value):
		label_font = value
		_refresh_if_ready()
@export var count_font: Font = InkType.text_font():
	set(value):
		count_font = value
		_refresh_if_ready()
@export var font_size_px: int = 12:
	set(value):
		font_size_px = value
		_refresh_if_ready()
# One tracking value for every caps label in the battle UI - see InkType.
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_refresh_if_ready()
@export_range(0.0, 1.0) var label_alpha: float = 0.62:
	set(value):
		label_alpha = value
		queue_redraw()
# Space between a label and its count, and between the two runs of the
# discard line.
@export var label_count_gap_px: float = 6.0:
	set(value):
		label_count_gap_px = value
		_relayout()
@export var run_gap_px: float = 14.0:
	set(value):
		run_gap_px = value
		_relayout()
@export var draw_label_text: String = "DECK":
	set(value):
		draw_label_text = value
		_relayout()
@export var discard_label_text: String = "DISCARD":
	set(value):
		discard_label_text = value
		_relayout()
@export var spent_label_text: String = "SPENT":
	set(value):
		spent_label_text = value
		_relayout()
# Which edges stay put when the text resizes this control: align_right
# for a line flush in a right-hand corner (the battle DISCARD line),
# align_bottom for one anchored by its bottom edge (the field instance,
# anchored bottom-left in region_field.tscn).
@export var align_right: bool = false:
	set(value):
		align_right = value
		_relayout()
@export var align_bottom: bool = false:
	set(value):
		align_bottom = value
		_relayout()

var _deck: Deck = null
var _pile: Pile = Pile.DRAW
var _whole_deck_cards: Array[CardData] = []
var _ink: Color = Color.BLACK
var _label_font_tracked: Font = null

# The DeckView this line currently has open, if any - see
# _toggle_deck_view()'s own doc. Cleared via DeckView.closed, not just by
# this line's own toggle-close, so it stays accurate whether the view
# closed via this line, a scrim click, or Escape.
var _deck_view_instance: DeckView = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	refresh_style()

func _exit_tree() -> void:
	_unbind()

func show_whole_deck(cards: Array[CardData]) -> void:
	_unbind()
	_whole_deck_cards = cards
	_relayout()

func bind_to_deck(deck: Deck, pile: Pile) -> void:
	_unbind()
	_deck = deck
	_pile = pile
	deck.drawn.connect(_on_deck_changed)
	deck.discarded.connect(_on_deck_changed)
	deck.shuffled.connect(_on_deck_changed)
	_relayout()

func _unbind() -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_deck_changed)
		_deck.discarded.disconnect(_on_deck_changed)
		_deck.shuffled.disconnect(_on_deck_changed)
	_deck = null

func _on_deck_changed(_card: CardData = null) -> void:
	_relayout()

# Re-reads the theme's ink and rebuilds the tracked label font - called
# at _ready(), by RegionField right after it applies this region's value
# set to the shared BattleTheme, and by BattleOverlay's F2 flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_label_font_tracked = InkType.tracked(label_font, font_size_px, tracking_em)
	_relayout()

func _refresh_if_ready() -> void:
	if is_inside_tree():
		refresh_style()

func _bound() -> bool:
	return _deck != null

func _pile_cards() -> Array[CardData]:
	if not _bound():
		return _whole_deck_cards
	return _deck.draw_pile if _pile == Pile.DRAW else _deck.discard_pile

func _spent_count() -> int:
	if not _bound() or _pile != Pile.DISCARD:
		return 0
	return _deck.exhaust_pile.size()

# The runs, left to right: [label, count] pairs.
func _runs() -> Array[PackedStringArray]:
	var runs: Array[PackedStringArray] = []
	var label_text: String = discard_label_text if _bound() and _pile == Pile.DISCARD else draw_label_text
	runs.append(PackedStringArray([label_text, str(_pile_cards().size())]))
	if _spent_count() > 0:
		runs.append(PackedStringArray([spent_label_text, str(_spent_count())]))
	return runs

func _line_width() -> float:
	var width: float = 0.0
	var runs := _runs()
	for i in runs.size():
		if i > 0:
			width += run_gap_px
		width += InkType.width(_label_font_tracked, runs[i][0], font_size_px) + label_count_gap_px + InkType.width(count_font, runs[i][1], font_size_px)
	return width

func _line_height() -> float:
	return label_font.get_height(font_size_px) if label_font != null else float(font_size_px)

# Sized to the text; when align_right/align_bottom the control grows
# leftward/upward from its own right/bottom edge so a corner anchor stays
# put.
func _relayout() -> void:
	if not is_inside_tree():
		return
	var right_edge: float = position.x + size.x
	var bottom_edge: float = position.y + size.y
	var new_size := Vector2(_line_width(), _line_height())
	size = new_size
	if align_right:
		position.x = right_edge - new_size.x
	if align_bottom:
		position.y = bottom_edge - new_size.y
	queue_redraw()

func _draw() -> void:
	if _label_font_tracked == null or count_font == null:
		return
	var label_color: Color = _ink
	label_color.a = label_alpha
	var baseline: float = label_font.get_ascent(font_size_px)
	var x: float = 0.0
	var runs := _runs()
	for i in runs.size():
		if i > 0:
			x += run_gap_px
		x += InkType.draw_run(self, _label_font_tracked, runs[i][0], Vector2(x, baseline), font_size_px, label_color)
		x += label_count_gap_px
		x += InkType.draw_run(self, count_font, runs[i][1], Vector2(x, baseline), font_size_px, _ink)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_toggle_deck_view()
		get_viewport().set_input_as_handled()

# Toggle, not always-open: clicking while a view from this line is
# already open closes that one instead of stacking a second on top of it
# (each with its own scrim, needing its own Escape).
func _toggle_deck_view() -> void:
	if _deck_view_instance != null and is_instance_valid(_deck_view_instance):
		_deck_view_instance.close()
		return
	_open_deck_view()

func _open_deck_view() -> void:
	var header_text: String = deck_title
	if _bound():
		# No counts here - the line itself already shows them.
		header_text = "Draw pile" if _pile == Pile.DRAW else "Discard pile"
	var deck_view: DeckView = open_view(get_tree(), _pile_cards(), header_text)
	deck_view.closed.connect(_on_deck_view_closed)
	_deck_view_instance = deck_view

func _on_deck_view_closed() -> void:
	_deck_view_instance = null

# Opens a DeckView over everything. See DECK_VIEW_LAYER's own doc -
# DeckView has no CanvasLayer of its own, so this is what actually puts it
# above FieldHUD/BattleLayer regardless of which is active right now. The
# caller owns the returned view's `closed` handling.
static func open_view(tree: SceneTree, cards: Array[CardData], header_text: String) -> DeckView:
	var deck_view := (load(DECK_VIEW_SCENE_PATH) as PackedScene).instantiate() as DeckView
	var layer := CanvasLayer.new()
	layer.layer = DECK_VIEW_LAYER
	tree.root.add_child(layer)
	layer.add_child(deck_view)
	deck_view.open(cards, header_text)
	return deck_view
