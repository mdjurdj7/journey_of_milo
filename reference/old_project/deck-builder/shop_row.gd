extends Panel
class_name ShopRow
# One purchasable line in the shop window - a title, an optional short
# subtitle, a price, and a Buy button. Same "just report the click, let
# something else decide what it means" shape as LootRow/Card: this
# doesn't know what buying it actually DOES (add a card, remove a card,
# heal) - shop_window.gd owns that. Reused for every kind of offer (a
# card, the removal service, rest) so the shop reads as one consistent
# row style, not three different ones.

signal buy_pressed()

signal hovered(card_data: CardData)
signal unhovered()
# Only ever emitted for a row carrying card_data (see set_card_data()
# below) - service rows (Remove a Card, Rest) never call set_card_data(),
# so card_data stays null on them and _on_mouse_entered()/_on_mouse_
# exited() below simply never emit anything for them. They already show
# what they do via their subtitle text and don't need a preview.

const NORMAL_BORDER_WIDTH := 3
const HIGHLIGHT_BORDER_COLOR := Color(0.85, 0.85, 0.9, 1)
const HIGHLIGHT_BORDER_WIDTH := 6
# The removal offer's own highlight - a brighter, thicker NEUTRAL border,
# not a rarity color (aesthetic direction for the shop is deliberately
# undecided - see DESIGN.md's Biome adaptation note and this feature's
# own brief). Just enough visual weight that "this is the important one"
# reads at a glance among the plainer card rows.

const AFFORDABLE_TITLE_COLOR := Color(1, 1, 1, 1)
const UNAFFORDABLE_TITLE_COLOR := Color(0.55, 0.55, 0.6, 1)

@onready var title_label: Label = $TitleLabel
@onready var subtitle_label: Label = $SubtitleLabel
@onready var price_label: Label = $PriceLabel
@onready var buy_button: Button = $BuyButton

var card_data: CardData = null
# Set only for card offers (see set_card_data()) - drives hovered/
# unhovered below. Buying never reads this; buy_pressed fires purely off
# BuyButton's own press, entirely independent of hover state, so hovering
# to inspect a card can never itself trigger a purchase.

func _ready() -> void:
	buy_button.pressed.connect(func(): buy_pressed.emit())
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	# VBoxContainer parents (both the ones baked into shop_window.tscn and
	# the runtime CardRowsContainer shop_window.gd builds rows into) only
	# stretch a child to the container's full width if the child itself
	# opts in - setting this here, once, means every ShopRow does that
	# regardless of which of the two ways it got created.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

# The public entry point - a title (a card's name, or a service's name),
# an optional one-line subtitle (rarity, or a short description - empty
# hides it), and the price.
func set_offer(title: String, subtitle: String, price: int) -> void:
	title_label.text = title
	subtitle_label.text = subtitle
	subtitle_label.visible = subtitle != ""
	price_label.text = "%d g" % price

# shop_window.gd calls this only for the card-offer rows, right after
# set_offer() - what actually drives the hover preview (see hovered/
# unhovered above). BuyButton is a child of this same Panel, but a
# Control's mouse_entered/exited fire off ITS OWN rect regardless of
# which child the cursor happens to be over inside it, so hovering the
# button itself still counts as hovering the row - no special-casing
# needed to keep the preview up while the mouse is over Buy.
func set_card_data(data: CardData) -> void:
	card_data = data

func _on_mouse_entered() -> void:
	if card_data != null:
		hovered.emit(card_data)

func _on_mouse_exited() -> void:
	if card_data != null:
		unhovered.emit()

func set_highlighted(highlighted: bool) -> void:
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	var width := HIGHLIGHT_BORDER_WIDTH if highlighted else NORMAL_BORDER_WIDTH
	if highlighted:
		style.border_color = HIGHLIGHT_BORDER_COLOR
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	add_theme_stylebox_override("panel", style)

# shop_window.gd calls this after every purchase (its own gold total may
# have just changed, and this offer's own price never does once it's on
# screen) - dims the title and disables Buy the same way an unaffordable
# hand card dims (see card.gd's set_affordable()), rather than only ever
# discovering it can't be bought after clicking it.
func set_affordable(can_afford: bool) -> void:
	buy_button.disabled = not can_afford
	title_label.add_theme_color_override("font_color", AFFORDABLE_TITLE_COLOR if can_afford else UNAFFORDABLE_TITLE_COLOR)
