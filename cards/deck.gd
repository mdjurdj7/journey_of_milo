extends RefCounted
class_name Deck

signal drawn(card: CardData)
signal discarded(card: CardData)
# A card went to the exhaust pile - Spent for the fight - from the hand
# (exhaust()) or from its own play (settle_play()).
signal exhausted(card: CardData)
signal shuffled()
# A card gained Keep (grant_keep()) or lost it (it left the hand).
signal keep_changed()
# A card put into the fight from outside it (add()) - never a draw, so
# nothing that answers a draw hears of it.
signal added(card: CardData)

@export var hand_size: int = 10

var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []
var exhaust_pile: Array[CardData] = []
# The exhaust pile's cards that got there from the hand without being
# played (Devour): Spent for this fight whatever their
# removal scope, so a CONSUMED card among them stays in the run
# (RegionField._apply_consumed_removals() skips them, one occurrence
# each).
var spent_unplayed: Array[CardData] = []
# The hand cards with Keep (Bide): each stays in the hand at the end of
# every turn (discard_hand()) until it leaves it by any route - played,
# Spent, devoured - and loses Keep then. Held here, not on the card: the
# fight's cards are the run deck's own, and each fight's Deck is built
# fresh, so Keep never carries from one fight to the next.
var kept: Array[CardData] = []
# The card being played, from its commit (begin_play()) until its effects
# have resolved (end_play()); null between plays. Out of the hand from the
# commit - no slot, not counted toward hand_size - and in no pile until
# settle_play() puts it in its own. While it is still playing, a reshuffle
# leaves it in the discard pile, so a draw on the card can never draw the
# card itself.
var playing: CardData = null

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
			# Only the card being played was there: nothing to draw.
			if draw_pile.is_empty():
				return
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
	_leave_hand(card)
	discard_pile.append(card)
	discarded.emit(card)

# Every hand card to the discard pile but `keep` (Frayed Cord's end-of-
# turn keep, one occurrence each, so keeping one of two copies discards
# the other) and every card with Keep, on top of it.
func discard_hand(keep: Array[CardData] = []) -> void:
	var keeping: Array[CardData] = keep.duplicate()
	for card in hand.duplicate():
		if kept.has(card):
			continue
		var index: int = keeping.find(card)
		if index >= 0:
			keeping.remove_at(index)
			continue
		discard(card)

# `card`, in the hand, gains Keep (Bide). False for one not in the hand.
func grant_keep(card: CardData) -> bool:
	if not hand.has(card):
		return false
	if not kept.has(card):
		kept.append(card)
		keep_changed.emit()
	return true

func has_keep(card: CardData) -> bool:
	return kept.has(card)

# `card` leaves the hand - by any route - and with it its Keep.
func _leave_hand(card: CardData) -> void:
	hand.erase(card)
	if kept.has(card):
		kept.erase(card)
		keep_changed.emit()

# A play commits: `card` leaves the hand - in no pile yet, and no longer
# counted toward hand_size while its effects resolve. False, and nothing
# moved, for a card not in the hand.
func begin_play(card: CardData) -> bool:
	if not hand.has(card):
		return false
	_leave_hand(card)
	playing = card
	return true

# The playing card into its pile - the exhaust pile when `exhaust`
# (Spent, Consumed, a Power or a Stance), else the discard pile - with the
# pile's own signal, so its readout ticks now. Once per play.
func settle_play(exhaust: bool) -> void:
	if playing == null or discard_pile.has(playing) or exhaust_pile.has(playing):
		return
	if exhaust:
		exhaust_pile.append(playing)
		exhausted.emit(playing)
	else:
		discard_pile.append(playing)
		discarded.emit(playing)

# The play's effects have resolved: from here a reshuffle may take it.
func end_play() -> void:
	playing = null

# Removes a card from hand for the rest of this Deck's lifetime (i.e. this
# fight) - unlike discard(), it never returns via _reshuffle_discard_into_draw().
func exhaust(card: CardData) -> void:
	if not hand.has(card):
		return
	_leave_hand(card)
	exhaust_pile.append(card)
	exhausted.emit(card)

# Every discard into the draw pile but the card still being played, which
# stays where it is - a draw on a card never draws the card itself.
func _reshuffle_discard_into_draw() -> void:
	var held: Array[CardData] = []
	if playing != null and discard_pile.has(playing):
		discard_pile.erase(playing)
		held.append(playing)
	draw_pile = discard_pile
	discard_pile = held
	shuffle()
