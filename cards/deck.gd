extends RefCounted
class_name Deck

signal drawn(card: CardData)
signal discarded(card: CardData)
signal shuffled()

@export var hand_size: int = 10

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []

func _init(starting_cards: Array[CardData] = []) -> void:
	draw_pile = starting_cards.duplicate()
	shuffle()

func shuffle() -> void:
	draw_pile.shuffle()
	shuffled.emit()

# Draws up to `amount` cards, reshuffling discard_pile into draw_pile
# whenever draw_pile runs dry. Stops early if hand is full or both piles
# are empty. exhaust_pile is never touched here - it never comes back.
func draw(amount: int) -> void:
	for i in amount:
		if hand.size() >= hand_size:
			return
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				return
			_reshuffle_discard_into_draw()
		var card: CardData = draw_pile.pop_back()
		hand.append(card)
		drawn.emit(card)

func discard(card: CardData) -> void:
	if not hand.has(card):
		return
	hand.erase(card)
	discard_pile.append(card)
	discarded.emit(card)

func discard_hand() -> void:
	for card in hand.duplicate():
		discard(card)

# Removes a card from hand for the rest of this Deck's lifetime (i.e. this
# fight) - unlike discard(), it never returns via _reshuffle_discard_into_draw().
func exhaust(card: CardData) -> void:
	if not hand.has(card):
		return
	hand.erase(card)
	exhaust_pile.append(card)

func _reshuffle_discard_into_draw() -> void:
	draw_pile = discard_pile
	discard_pile = []
	shuffle()
