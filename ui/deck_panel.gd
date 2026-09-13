extends Panel
class_name DeckPanel

# A small dark panel with a deck-icon placeholder and a text label
# ("Deck 9", "Discard 3  Spent 2" - the word in the normal text tone, its
# count right after in a lighter one); clicking opens a DeckView of
# whatever this instance currently represents. Two independent setup
# modes, switched via the two public methods below (never both active at
# once - each clears the other's state):
#
# - show_whole_deck(cards): a static list, no live Deck - used by the
#   persistent field-HUD instance while no battle is running. Shown under
#   draw_label_text ("Deck") same as the DRAW pile below, since that's
#   the same panel/position once battle starts.
# - bind_to_deck(deck, pile): tracks one pile (DRAW or DISCARD) of a live
#   battle Deck, updating on its drawn/discarded/shuffled signals - used
#   by that same persistent instance once battle starts (DRAW) and by
#   the separate instance BattleOverlay creates at the mirrored bottom-
#   right position (DISCARD, which also appends the exhaust/"spent" count
#   once nonzero).
#
# This node doesn't know or care who owns it or where it's positioned -
# RegionField/BattleOverlay each configure their own instance's exports
# (panel_size etc.) before adding it to the tree, same as HandContainer
# already does for CardView.card_size. BattleOverlay's own discard
# instance copies every export straight off the field's persistent
# instance rather than hardcoding a second set of numbers, so the two
# stay mirrored by construction.

const DECK_VIEW_SCENE_PATH := "res://ui/deck_view.tscn"

enum Pile { DRAW, DISCARD }

# DeckView's own header in field mode ("Belongings") - battle mode uses
# "Draw pile"/"Discard pile" instead (see _open_deck_view() below), since
# the panels themselves already show the pile name.
@export var deck_title: String = "Belongings"

@export var draw_label_text: String = "Deck"
@export var discard_label_text: String = "Discard"
@export var spent_label_text: String = "Spent"
# Each count is rendered in the current text_color at this alpha (never a
# separate hue) so "Deck" reads as the primary word and its number as a
# quieter detail after it, in both the on-pale and on-dark value sets.
@export_range(0.0, 1.0) var count_tone_alpha: float = 0.6

@export var panel_size: Vector2 = Vector2(160.0, 44.0)
@export var panel_margin: float = 10.0
@export var icon_size: Vector2 = Vector2(20.0, 20.0)
@export var text_font_size_px: int = 16

@onready var _icon: ColorRect = $Icon
@onready var _text_label: RichTextLabel = $TextLabel

var _deck: Deck = null
var _pile: Pile = Pile.DRAW
var _bound_to_deck: bool = false
var _whole_deck_cards: Array[CardData] = []
var _text_color: Color = Color.WHITE

func _ready() -> void:
	custom_minimum_size = panel_size
	size = panel_size
	# Safety net at this smaller size - a long "Discard N  Spent N" string
	# at text_font_size_px could plausibly run past the label's own
	# available width; this keeps any overflow from spilling past the
	# panel's own edge instead of clipping it mid-word (RichTextLabel has
	# no clip_text of its own the way Label does).
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_apply_style()
	_apply_layout()
	_update_text()

# Re-reads this panel's theme colors and re-renders whichever text is
# currently showing (the count's own color is baked into that text as a
# BBCode tag - see _tagged() below - so a stale render would keep the OLD
# tone even after the theme's colors change) - called by RegionField
# right after it applies this region's on-pale/on-dark value set to the
# shared BattleTheme resource, since (like CardView/EnemyStatus) this
# panel reads theme colors once and caches them, rather than tracking the
# theme live.
func refresh_style() -> void:
	_apply_style()
	_update_text()

func _apply_style() -> void:
	var panel_color: Color = get_theme_color("panel_color", "CardFace")
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	_text_color = get_theme_color("text_color", "CardFace")

	var style := StyleBoxFlat.new()
	style.bg_color = panel_color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	style.shadow_size = 0
	add_theme_stylebox_override("panel", style)

	_icon.color = panel_light_color

	_text_label.add_theme_color_override("default_color", _text_color)
	_text_label.add_theme_font_size_override("normal_font_size", text_font_size_px)

func _apply_layout() -> void:
	_icon.position = Vector2(panel_margin, panel_margin)
	_icon.size = icon_size
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text_left: float = panel_margin + icon_size.x + panel_margin
	# No native RichTextLabel vertical_alignment (unlike Label) - centered
	# by hand instead, against an estimated single-line height (font size
	# * a standard ~1.3 line-height multiplier) rather than the actual
	# rendered content height, which isn't reliably available the same
	# frame text is set. Close enough for a short, single-line label;
	# retune text_font_size_px/panel_size.y together if it reads off.
	var line_height: float = float(text_font_size_px) * 1.3
	_text_label.position = Vector2(text_left, (panel_size.y - line_height) / 2.0)
	_text_label.size = Vector2(panel_size.x - text_left - panel_margin, line_height)
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

# label_text in the normal text tone, count right after it in the same
# color at count_tone_alpha - the one shared building block both
# show_whole_deck()/_refresh_from_deck() below build their text from, so
# "word normal, count lighter" never drifts between the two.
func _tagged(label_text: String, count: int) -> String:
	var toned := _text_color
	toned.a = count_tone_alpha
	return "%s [color=#%s]%d[/color]" % [label_text, toned.to_html(true), count]

func show_whole_deck(cards: Array[CardData]) -> void:
	_unbind_from_deck()
	_whole_deck_cards = cards
	_update_text()

func bind_to_deck(deck: Deck, pile: Pile) -> void:
	_unbind_from_deck()
	_deck = deck
	_pile = pile
	_bound_to_deck = true
	deck.drawn.connect(_on_deck_changed)
	deck.discarded.connect(_on_deck_changed)
	deck.shuffled.connect(_on_deck_changed)
	_update_text()

func unbind_from_deck() -> void:
	_unbind_from_deck()

func _unbind_from_deck() -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_deck_changed)
		_deck.discarded.disconnect(_on_deck_changed)
		_deck.shuffled.disconnect(_on_deck_changed)
	_deck = null
	_bound_to_deck = false

func _on_deck_changed(_card: CardData = null) -> void:
	_update_text()

func _update_text() -> void:
	if not _bound_to_deck:
		_text_label.text = _tagged(draw_label_text, _whole_deck_cards.size())
		return
	if _deck == null:
		return

	var pile_cards: Array[CardData] = _deck.draw_pile if _pile == Pile.DRAW else _deck.discard_pile
	var label_text: String = draw_label_text if _pile == Pile.DRAW else discard_label_text
	var text: String = _tagged(label_text, pile_cards.size())
	if _pile == Pile.DISCARD and _deck.exhaust_pile.size() > 0:
		text += "  " + _tagged(spent_label_text, _deck.exhaust_pile.size())
	_text_label.text = text

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_deck_view()
		get_viewport().set_input_as_handled()

func _open_deck_view() -> void:
	var cards: Array[CardData]
	var header_text: String
	if _bound_to_deck and _deck != null:
		cards = _deck.draw_pile if _pile == Pile.DRAW else _deck.discard_pile
		# No counts here - the panels themselves already show them.
		header_text = "Draw pile" if _pile == Pile.DRAW else "Discard pile"
	else:
		cards = _whole_deck_cards
		header_text = deck_title

	var deck_view := (load(DECK_VIEW_SCENE_PATH) as PackedScene).instantiate() as DeckView
	get_tree().root.add_child(deck_view)
	deck_view.open(cards, header_text)
