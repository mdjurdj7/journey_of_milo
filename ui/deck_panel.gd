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
#   battle Deck, updating on its drawn/discarded/exhausted/shuffled/added
#   signals - the two instances BattleOverlay creates (DECK bottom-left under
#   BattleResources, DISCARD bottom-right under End Turn) while the field
#   instance is hidden. Both are the overlay's children, freed with it.
#
# The field instance alone also takes the field HUD row's look:
# use_row_style() (RegionField) draws it as the row's first item - two
# card outlines, the count as a Spectral numeral, "DECK" after it, over
# the row's halo when it has one (see HudRowStyle) - and has it draw the
# row's optional
# backing fade - and its count then counts to each new deck size over
# the style's hud_count_sec, one ease-out (the first size it is shown, the
# floor load, at once). The battle lines never get a row style and keep
# the label-then-count line above.
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

# The field HUD row's style, once use_row_style() has switched this line
# to it; null on the battle lines.
var _row_style: HudRowStyle = null
var _backing_texture: GradientTexture2D = null
# The row style's counting numeral: what it shows on the way to the deck
# size, the tween, and whether a first size has been shown yet.
var _row_count_shown: float = 0.0
var _row_count_tween: Tween = null
var _row_count_seeded: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	gui_input.connect(_on_gui_input)
	refresh_style()

func _exit_tree() -> void:
	_unbind()

# Draws this line as the field HUD row's first item from here on - the
# field instance only (see the class doc).
func use_row_style(row_style: HudRowStyle) -> void:
	if _row_style != null:
		_row_style.changed.disconnect(_on_row_style_changed)
	_row_style = row_style
	_row_style.changed.connect(_on_row_style_changed)
	if not get_viewport().size_changed.is_connected(queue_redraw):
		get_viewport().size_changed.connect(queue_redraw)
	_relayout()

func show_whole_deck(cards: Array[CardData]) -> void:
	_unbind()
	_whole_deck_cards = cards
	if _row_style != null:
		if _row_count_seeded:
			_start_row_count()
		else:
			_row_count_seeded = true
			_set_row_count_shown(float(cards.size()))
	_relayout()

# A fresh count from the numeral shown now to the deck's size.
func _start_row_count() -> void:
	_kill_row_count()
	var target: float = float(_pile_cards().size())
	if _row_style.hud_count_sec <= 0.0 or not is_inside_tree():
		_set_row_count_shown(target)
		return
	_row_count_tween = create_tween()
	_row_count_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_row_count_tween.tween_method(_set_row_count_shown, _row_count_shown, target, _row_style.hud_count_sec).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	# Lands on the exact size, whatever the last step's rounding.
	_row_count_tween.tween_callback(_set_row_count_shown.bind(target))

func _kill_row_count() -> void:
	if _row_count_tween != null:
		_row_count_tween.kill()
		_row_count_tween = null

func _set_row_count_shown(value: float) -> void:
	_row_count_shown = value
	_relayout()

# The row style's numeral: the count on its way.
func _row_numeral() -> String:
	return str(roundi(_row_count_shown))

# A style edit re-lays the line - and re-times a running count from where
# it stands (hud_count_sec live).
func _on_row_style_changed() -> void:
	if _row_count_tween != null and _row_count_tween.is_valid():
		_start_row_count()
	_relayout()

func bind_to_deck(deck: Deck, pile: Pile) -> void:
	_unbind()
	_deck = deck
	_pile = pile
	deck.drawn.connect(_on_deck_changed)
	deck.discarded.connect(_on_deck_changed)
	deck.exhausted.connect(_on_deck_changed)
	deck.shuffled.connect(_on_deck_changed)
	deck.added.connect(_on_deck_changed)
	_relayout()

func _unbind() -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_deck_changed)
		_deck.discarded.disconnect(_on_deck_changed)
		_deck.exhausted.disconnect(_on_deck_changed)
		_deck.shuffled.disconnect(_on_deck_changed)
		_deck.added.disconnect(_on_deck_changed)
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
	if _row_style != null:
		return _row_style.item_width(InkGlyph.Kind.DECK, _row_numeral(), "", draw_label_text)
	var width: float = 0.0
	var runs := _runs()
	for i in runs.size():
		if i > 0:
			width += run_gap_px
		width += InkType.width(_label_font_tracked, runs[i][0], font_size_px) + label_count_gap_px + InkType.width(count_font, runs[i][1], font_size_px)
	return width

func _line_height() -> float:
	if _row_style != null:
		return _row_style.row_height()
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
	if _row_style != null:
		_draw_backing()
		_row_style.draw_item(self, _ink, InkGlyph.Kind.DECK, _row_numeral(), "", draw_label_text)
		return
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

# The row's backing fade (HudRowStyle.hud_backing_alpha, off at 0): ink,
# strongest at the screen's bottom-left corner, gone by hud_backing_size_px
# to the right and up. Drawn here, under the row's other items (this line
# comes first under FieldHUD), and it hides with the row for a fight.
func _draw_backing() -> void:
	if _row_style.hud_backing_alpha <= 0.0:
		return
	if _backing_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		gradient.add_point(0.45, Color(1.0, 1.0, 1.0, 0.5))
		_backing_texture = GradientTexture2D.new()
		_backing_texture.gradient = gradient
		_backing_texture.fill = GradientTexture2D.FILL_RADIAL
		_backing_texture.fill_from = Vector2(0.0, 1.0)
		_backing_texture.fill_to = Vector2(1.0, 1.0)
	var corner := Vector2(-global_position.x, get_viewport_rect().size.y - global_position.y)
	var backing_size: Vector2 = _row_style.hud_backing_size_px
	draw_texture_rect(_backing_texture, Rect2(corner - Vector2(0.0, backing_size.y), backing_size), false, Color(_ink, _row_style.hud_backing_alpha))

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
# `layer_index` lifts it over something higher than the field's own HUD
# and battle layers (a screen at layer 100); the default is DECK_VIEW_LAYER.
static func open_view(tree: SceneTree, cards: Array[CardData], header_text: String, layer_index: int = DECK_VIEW_LAYER) -> DeckView:
	var deck_view := (load(DECK_VIEW_SCENE_PATH) as PackedScene).instantiate() as DeckView
	var layer := CanvasLayer.new()
	layer.layer = layer_index
	tree.root.add_child(layer)
	layer.add_child(deck_view)
	deck_view.open(cards, header_text)
	return deck_view

# A DeckView that picks rather than browses (DeckView.pick_mode): one card
# clicked emits card_picked and closes; closing without one is a cancel.
# At `layer_index`, so it can open over a screen. The caller owns both
# signals.
static func open_picker(tree: SceneTree, cards: Array[CardData], header_text: String, layer_index: int) -> DeckView:
	var deck_view: DeckView = open_view(tree, cards, header_text, layer_index)
	deck_view.pick_mode = true
	return deck_view
