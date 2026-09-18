extends Control
class_name PileReadout

# One pile of the battle Deck as a line of ink: a tracked caps label
# ("DECK" / "DISCARD", Alegreya Sans Bold at label_alpha) and its count
# right after in Alegreya Sans Regular at full ink - the discard line also
# runs "SPENT n" on once anything is exhausted. Drawn, not boxed; sized to
# its own text so it can sit flush in a corner (align_right for the
# bottom-right one). Clicking it opens a DeckView of the pile, the same
# view the field's DeckPanel opens (see DeckPanel.open_view()) - toggled,
# so a second click closes it rather than stacking another.
#
# Two live in BattleOverlay: the DECK line at the bottom of the
# bottom-left resource stack (under BattleResources) and the DISCARD line
# under End Turn bottom-right. Both are the overlay's children, bound to
# the fight's Deck in enter_battle() and freed with the overlay.

enum Pile { DRAW, DISCARD }

@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
@export var count_font: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
@export var font_size_px: int = 12
@export var tracking_em: float = 0.16
@export_range(0.0, 1.0) var label_alpha: float = 0.62
# Space between a label and its count, and between the two runs of the
# discard line.
@export var label_count_gap_px: float = 6.0
@export var run_gap_px: float = 14.0
@export var draw_label_text: String = "DECK"
@export var discard_label_text: String = "DISCARD"
@export var spent_label_text: String = "SPENT"
@export var align_right: bool = false

var _deck: Deck = null
var _pile: Pile = Pile.DRAW
var _ink: Color = Color.BLACK
var _label_font_tracked: Font = null
var _deck_view_instance: DeckView = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	refresh_style()

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

func _exit_tree() -> void:
	_unbind()

func _on_deck_changed(_card: CardData = null) -> void:
	_relayout()

# Re-reads the theme's ink - called at _ready() and by BattleOverlay's F2
# flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_label_font_tracked = InkType.tracked(label_font, font_size_px, tracking_em)
	_relayout()

func _pile_cards() -> Array[CardData]:
	if _deck == null:
		return []
	return _deck.draw_pile if _pile == Pile.DRAW else _deck.discard_pile

func _spent_count() -> int:
	if _deck == null or _pile != Pile.DISCARD:
		return 0
	return _deck.exhaust_pile.size()

# The runs, left to right: [label, count] pairs.
func _runs() -> Array[PackedStringArray]:
	var runs: Array[PackedStringArray] = []
	var label_text: String = draw_label_text if _pile == Pile.DRAW else discard_label_text
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

# Sized to the text; when align_right the control grows leftward from its
# own right edge so a corner anchor stays put.
func _relayout() -> void:
	if not is_inside_tree():
		return
	var right_edge: float = position.x + size.x
	var new_size := Vector2(_line_width(), _line_height())
	size = new_size
	if align_right:
		position.x = right_edge - new_size.x
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

func _toggle_deck_view() -> void:
	if _deck_view_instance != null and is_instance_valid(_deck_view_instance):
		_deck_view_instance.close()
		return
	if _deck == null:
		return
	# No counts in the header - the line itself already shows them.
	var header_text: String = "Draw pile" if _pile == Pile.DRAW else "Discard pile"
	var deck_view: DeckView = DeckPanel.open_view(get_tree(), _pile_cards(), header_text)
	deck_view.closed.connect(func() -> void: _deck_view_instance = null)
	_deck_view_instance = deck_view
