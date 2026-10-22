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
# A card put into the fight from outside it (add(), add_copy()) - never a
# draw, so nothing that answers a draw hears of it.
signal added(card: CardData)
# A fight-only copy left the hand unplayed (discard()) - gone, in no pile.
signal vanished(card: CardData)
# A hand card went back to the bottom of the draw pile unplayed
# (hand_to_bottom() - Collateral's pick not played after all).
signal returned(card: CardData)

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
# The hand cards with Keep for this turn's end only (Sheathe - Battle
# Controller.sheathe()): each stays in the hand when the turn's hand is
# discarded (discard_hand()), then the Keep is gone - it doesn't hold
# through another turn's end, as kept's does. Played or otherwise out of
# the hand first, it loses it then. has_keep() answers for both;
# has_keep_once() tells this one apart, for the face's SHEATHED.
var kept_once: Array[CardData] = []
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

# The top `count` cards of draw_pile, the top first - the discard pile
# shuffled in first when it is empty, as draw() would; fewer when it
# holds fewer. Nothing moves (Collateral's look).
func peek_top(count: int) -> Array[CardData]:
	if draw_pile.is_empty() and not discard_pile.is_empty():
		_reshuffle_discard_into_draw()
	var top: Array[CardData] = []
	for i in mini(maxi(count, 0), draw_pile.size()):
		top.append(draw_pile[draw_pile.size() - 1 - i])
	return top

# `card`, in draw_pile, to its bottom - drawn last.
func to_bottom(card: CardData) -> void:
	var index: int = draw_pile.find(card)
	if index < 0:
		return
	draw_pile.remove_at(index)
	draw_pile.insert(0, card)

# `card`, in draw_pile, into the hand to be played from there (Collateral's
# pick) - even over hand_size, as it leaves again at once. Emits added, not
# drawn: it isn't a draw. False for a card not in draw_pile.
func take_from_draw(card: CardData) -> bool:
	var index: int = draw_pile.find(card)
	if index < 0:
		return false
	draw_pile.remove_at(index)
	hand.append(card)
	added.emit(card)
	return true

# `card`, in the hand, back to the bottom of draw_pile (Collateral's pick
# not played after all). Emits discarded, so the hand drops its view.
func hand_to_bottom(card: CardData) -> void:
	if not hand.has(card):
		return
	_leave_hand(card)
	draw_pile.insert(0, card)
	discarded.emit(card)

func discard(card: CardData) -> void:
	if not hand.has(card):
		return
	_leave_hand(card)
	# A fight-only copy (Twice Over's) is gone, not discarded: no pile, no
	# reshuffle ever brings it back.
	if card.battle_copy:
		vanished.emit(card)
		return
	discard_pile.append(card)
	discarded.emit(card)

# A fight-only copy of `card` (Twice Over) into the hand: the same card -
# tempered or not - marked CardData.battle_copy. Null when the hand is
# full; it never goes to the draw pile, so it can't outlive the turn.
func add_copy(card: CardData) -> CardData:
	if card == null or hand.size() >= hand_size:
		return null
	var copy := card.duplicate() as CardData
	copy.battle_copy = true
	hand.append(copy)
	added.emit(copy)
	return copy

# Every hand card to the discard pile but `keep` (Frayed Cord's end-of-
# turn keep, one occurrence each, so keeping one of two copies discards
# the other) and every card with Keep, on top of it. A fight-only copy
# goes whatever keeps it (discard()). A one-turn Keep (kept_once) is used
# up here: its cards stay, and lose it.
func discard_hand(keep: Array[CardData] = []) -> void:
	var keeping: Array[CardData] = keep.duplicate()
	for card in hand.duplicate():
		if card.battle_copy:
			discard(card)
			continue
		if kept.has(card) or kept_once.has(card):
			continue
		var index: int = keeping.find(card)
		if index >= 0:
			keeping.remove_at(index)
			continue
		discard(card)
	if not kept_once.is_empty():
		kept_once.clear()
		keep_changed.emit()

# `card`, in the hand, gains Keep (Bide). False for one not in the hand.
func grant_keep(card: CardData) -> bool:
	if not hand.has(card):
		return false
	if not kept.has(card):
		kept.append(card)
		keep_changed.emit()
	return true

# `card`, in the hand, gains Keep for this turn's end only (Sheathe). False
# for one not in the hand, or a fight-only copy, which no Keep holds.
func grant_keep_once(card: CardData) -> bool:
	if not hand.has(card) or card.battle_copy:
		return false
	if not kept_once.has(card):
		kept_once.append(card)
		keep_changed.emit()
	return true

func has_keep(card: CardData) -> bool:
	return kept.has(card) or kept_once.has(card)

# Whether `card`'s Keep is the one-turn kind alone (Sheathe's): Keep itself
# outranks it, so a card with both answers false.
func has_keep_once(card: CardData) -> bool:
	return kept_once.has(card) and not kept.has(card)

# `card` leaves the hand - by any route - and with it its Keep.
func _leave_hand(card: CardData) -> void:
	hand.erase(card)
	if kept.has(card) or kept_once.has(card):
		kept.erase(card)
		kept_once.erase(card)
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

# Devoured by the keyword (Take In - DevourFromHandEffect): out of the hand
# for the rest of this fight without being played - to the exhaust pile
# and spent_unplayed, as the Devour button's eaten cards go, so it is back
# next fight even if CONSUMED. A fight-only copy (Twice Over's) is only
# gone: no pile, nothing to come back. False for a card not in the hand.
func devour(card: CardData) -> bool:
	if not hand.has(card):
		return false
	if card.battle_copy:
		_leave_hand(card)
		return true
	exhaust(card)
	spent_unplayed.append(card)
	return true

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
