extends Node
# Registered as a scene autoload (card_upgrade_service.tscn), same
# reason every other autoload here is (see run_state.gd's own header) -
# a single, always-there object any script can call CardUpgradeService.
# offer_upgrade() on, from anywhere, with no scene wiring. First real
# caller: shop_window.gd's "Upgrade a Card" offer (see its own
# manage_pause=false call - the shop has already paused the tree, so
# this service must not unpause it again on close). Items, events, and
# NPC interactions are still just planned sources; battle.gd's own
# DevUpgradeButton remains as a no-shop-needed test path.
#
# --- Why full resource replacement, not a delta/modifier ---
#
# An upgrade needs to be able to change a card's damage, energy cost, HP
# cost, Toll interaction, chain role, name, and flavor text - not just
# its numbers. A numeric delta/modifier system (the kind weapon_
# modifier.gd already uses for equipment) can only express "add N to
# this field," which can't touch chain_role, card_name, or flavor_text
# at all. CardData.upgrades holds full CardData resources instead - an
# upgrade is authored as an ordinary card in its own right, and
# "upgrading" is swapping which resource sits in that deck slot. See
# card_data.gd's own upgrades doc for the data side of this.
#
# --- Selection UI: DeckViewer, not a new overlay ---
#
# Reuses deck_viewer.tscn's existing selection mode (open_cards()'s
# selection_mode param) rather than building a second card-picker -
# shop_window.gd's own "Remove a Card" flow already proves this exact
# shape works for "pick one card out of the live deck" (as opposed to
# reward_screen.gd's card-choice modal, built for a small CURATED set of
# fresh options, not the deck itself). DeckViewer's own header states it
# can be added "as a plain child anywhere in its tree" with "no wiring
# back to the caller needed" - this service owns its OWN private
# instance (see card_upgrade_service.tscn) for exactly that reason,
# rather than depending on whichever scene happens to already have one
# wired up (the way shop_window.gd currently requires field_room.gd to
# hand it a reference).
#
# --- No chained upgrades ---
#
# An upgraded card's own `upgrades` list is expected to stay empty (see
# card_data.gd's own doc) - this is an AUTHORING convention, not
# something enforced here. offer_upgrade() below doesn't special-case
# "is this card itself an upgrade" at all; it just reads whatever
# `upgrades` the chosen card happens to have. As long as every upgrade
# .tres leaves that field empty, chaining is structurally impossible
# without extra code, which is the point - adding an explicit guard here
# would be defending against a case authoring already prevents.

enum Outcome { UPGRADED, CANCELLED, NO_ELIGIBLE_CARDS }

@onready var deck_viewer: DeckViewer = $DeckViewer

var _busy: bool = false
# Guards against a second offer_upgrade() call while one is already
# awaiting a selection - both would fight over this one shared deck_
# viewer instance otherwise. Not expected to matter for the single dev-
# button caller this commit ships with, but the service is meant to be
# callable from anywhere, so it has to be safe against that on its own
# rather than trusting every future caller to disable its own button.
var _pending_choice: CardData = null

# The one entry point. `filter`, if given, is a Callable taking a
# CardData and returning bool - only cards it accepts (AND that have at
# least one upgrade authored - see card_data.gd) are eligible. An
# invalid/unset Callable (the default) means every upgradeable card in
# the deck is eligible. Returns a Dictionary ({"outcome": Outcome,
# "old_card": CardData, "new_card": CardData} - old_card/new_card are
# null unless outcome is UPGRADED) rather than a typed result object,
# same "plain Dictionary for a one-shot multi-field return" shape
# battle.gd's own _resolve_damage() already uses.
#
# manage_pause=true by default (the dev-button caller, battle.gd, isn't
# already paused - this call pauses the tree itself and unpauses it on
# close, same default open_cards() itself uses). Pass false when the
# caller has ALREADY paused the tree through some other still-open
# overlay - shop_window.gd's own "Remove a Card" flow documents the exact
# same need for its own nested DeckViewer: letting this service's close()
# also resume the tree would wake the field up while the shop is still
# visibly open on top of it.
func offer_upgrade(filter: Callable = Callable(), manage_pause: bool = true) -> Dictionary:
	if _busy:
		return _result(Outcome.CANCELLED)
	var eligible := _gather_eligible(filter)
	if eligible.is_empty():
		# Reported cleanly, no overlay ever shown - a caller (a shop, an
		# event) is expected to check this and not offer the upgrade
		# service at all rather than let the player buy/trigger one with
		# nothing to spend it on. See this feature's own brief.
		return _result(Outcome.NO_ELIGIBLE_CARDS)

	_busy = true
	var chosen: CardData = await _await_card_choice(eligible, "Choose a Card to Upgrade", manage_pause)
	if chosen == null:
		_busy = false
		return _result(Outcome.CANCELLED)

	var options: Array[CardData] = chosen.upgrades
	var picked: CardData = options[0]
	if options.size() > 1:
		picked = await _await_card_choice(options, "Choose an Upgrade for %s" % chosen.card_name, manage_pause)
		if picked == null:
			_busy = false
			return _result(Outcome.CANCELLED)

	# Cancellation up to this exact point leaves the deck completely
	# untouched - nothing above this line ever writes to RunState.deck.
	RunState.replace_card_in_deck(chosen, picked)
	_busy = false
	return _result(Outcome.UPGRADED, chosen, picked)

# The removal counterpart to offer_upgrade() above (2026-09-04, removal-
# picker pass) - a SIBLING method, not a mode branch inside offer_
# upgrade() itself: that function's own signature/return shape (chosen +
# picked upgrade, Outcome.UPGRADED/NO_ELIGIBLE_CARDS) is genuinely
# upgrade-specific, and a removal has no second "which upgrade" step and
# no "no eligible cards" case worth its own Outcome value (see below).
# What's actually shared - the ONE thing worth generalizing - is the
# picker plumbing itself: this reuses _await_card_choice()/deck_viewer/
# _busy directly, exactly the same private machinery offer_upgrade()
# already runs on, rather than standing up a second DeckViewer instance
# (a full parallel service) for what is otherwise an identical "pick one
# card out of the live deck, or back out" interaction. Unfiltered - the
# FULL RunState.deck, unlike offer_upgrade()'s own upgrades-only _gather_
# eligible() - same shape shop_window.gd's own "Remove a Card" purchase
# already uses (a direct, unfiltered deck_viewer.open_cards(RunState.
# deck, ...) call), the actual precedent this reuses.
#
# Returns the removed CardData, or null if the player backed out (Close/
# Escape - same cancellation grammar offer_upgrade() itself has) without
# picking - RunState.deck is left completely untouched in that case,
# same "cancellation touches nothing" guarantee offer_upgrade() gives.
# No minimum-deck-size guard - none exists anywhere in this project
# today (remove_card_from_deck() itself is a bare deck.erase(), and
# shop_window.gd's own Remove a Card purchase is already repeatable with
# no floor), so this doesn't invent one; the only defensive check is an
# EMPTY deck (nothing to open a picker over at all), which returns null
# without ever showing the overlay.
func offer_removal(manage_pause: bool = true) -> CardData:
	if _busy or RunState.deck.is_empty():
		return null
	_busy = true
	var chosen: CardData = await _await_card_choice(RunState.deck, "Choose a Card to Remove", manage_pause)
	_busy = false
	if chosen != null:
		RunState.remove_card_from_deck(chosen)
	return chosen

# Whether offer_upgrade(filter) would find at least one eligible card,
# WITHOUT opening any UI - the same _gather_eligible() the real flow
# uses, just checked for emptiness. A caller that wants to grey out or
# hide its own "offer an upgrade" button (a shop, say) calls this
# instead of re-deriving "has at least one upgradeable card" itself,
# so the eligibility rule only ever lives in one place.
func has_eligible_cards(filter: Callable = Callable()) -> bool:
	return not _gather_eligible(filter).is_empty()

func _result(outcome: Outcome, old_card: CardData = null, new_card: CardData = null) -> Dictionary:
	return {"outcome": outcome, "old_card": old_card, "new_card": new_card}

# Every deck card with at least one authored upgrade, further narrowed
# by `filter` if one was given. Re-reads RunState.deck fresh on every
# call rather than caching - the deck can change between calls (a card
# played/removed/added) and this is cheap enough that caching would only
# risk going stale for no real benefit.
func _gather_eligible(filter: Callable) -> Array[CardData]:
	var eligible: Array[CardData] = []
	for card: CardData in RunState.deck:
		if card.upgrades.is_empty():
			continue
		if filter.is_valid() and not filter.call(card):
			continue
		eligible.append(card)
	return eligible

# Fires when a card is clicked while deck_viewer is open in selection
# mode (see _await_card_choice() below) - a named method, not an inline
# lambda, so the defensive "disconnect before reconnect" pattern below
# actually works: Callable equality for a lambda literal is per-
# instance (a new closure every time), so is_connected() could never
# match a previous one the way it can for a stable bound method.
func _on_choice_selected(data: CardData) -> void:
	_pending_choice = data
	deck_viewer.close()

# Opens deck_viewer in selection mode over `cards` and waits for the
# player to either pick one (card_selected, see _on_choice_selected()
# above) or close it without picking (the Close button or Escape - both
# route through DeckViewer's own close(), which this only ever observes
# via visibility_changed, not by hooking those controls directly - it
# doesn't matter WHICH way the player backed out, only that they did).
# Returns the picked CardData, or null on cancellation.
func _await_card_choice(cards: Array[CardData], title: String, manage_pause: bool) -> CardData:
	_pending_choice = null
	if deck_viewer.card_selected.is_connected(_on_choice_selected):
		deck_viewer.card_selected.disconnect(_on_choice_selected)
	deck_viewer.card_selected.connect(_on_choice_selected, CONNECT_ONE_SHOT)
	deck_viewer.open_cards(cards, title, true, manage_pause)
	while deck_viewer.visible:
		await deck_viewer.visibility_changed
	return _pending_choice
