extends RefCounted
class_name Deck

signal drawn(card: CardData)
signal discarded(card: CardData)
signal shuffled()
# Cards left the hand for set_aside_pile, or came back from it.
signal set_aside_changed()
# A card put into the fight from outside it (add()) - never a draw, so
# nothing that answers a draw hears of it.
signal added(card: CardData)

@export var hand_size: int = 10

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []
# Set aside from the hand (Bide) until the start of the next turn: out of
# the hand and of every pile a draw or a reshuffle reads, back in the hand
# by return_set_aside(). A fight that ends first just drops it - each
# fight's Deck is built fresh from the run's deck.
var set_aside_pile: Array[CardData] = []

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

# A card from outside the fight (the F1 row's Add card) straight into
# the hand, or onto the top of draw_pile - drawn next - when the hand is
# full. Emits added, not drawn: it isn't a draw.
func add(card: CardData) -> void:
	if hand.size() < hand_size:
		hand.append(card)
	else:
		draw_pile.append(card)
	added.emit(card)

func discard(card: CardData) -> void:
	if not hand.has(card):
		return
	hand.erase(card)
	discard_pile.append(card)
	discarded.emit(card)

# Every hand card to the discard pile but `keep` (the end-of-turn keep) -
# one occurrence each, so keeping one of two copies discards the other.
func discard_hand(keep: Array[CardData] = []) -> void:
	var keeping: Array[CardData] = keep.duplicate()
	for card in hand.duplicate():
		var index: int = keeping.find(card)
		if index >= 0:
			keeping.remove_at(index)
			continue
		discard(card)

# `cards` leave the hand for set_aside_pile - one occurrence each; a card
# not in the hand is skipped.
func set_aside(cards: Array[CardData]) -> void:
	var moved: bool = false
	for card in cards:
		if not hand.has(card):
			continue
		hand.erase(card)
		set_aside_pile.append(card)
		moved = true
	if moved:
		set_aside_changed.emit()

# Every set-aside card back into the hand, in the order set aside - after
# the turn's draw, so they never count against it. One that would take
# the hand past hand_size goes to the discard pile instead of vanishing.
func return_set_aside() -> void:
	if set_aside_pile.is_empty():
		return
	var overflow: Array[CardData] = []
	for card in set_aside_pile:
		if hand.size() >= hand_size:
			overflow.append(card)
			continue
		hand.append(card)
	set_aside_pile.clear()
	set_aside_changed.emit()
	for card in overflow:
		discard_pile.append(card)
		discarded.emit(card)

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
