extends RefCounted
class_name SiftOutcomeResolver
# Executes a drawn SiftOutcomeData's own effect_type (2026-08-28,
# wreckage-heap effect-resolution pass) - the counterpart to
# SiftOutcomePool.draw() above it (which only ever decides WHICH entry
# gets drawn, never what it does once drawn). field_heap.gd's own pull()
# is the one caller, awaiting this before it emits its own `pulled`
# signal - see that file's own doc for why resolution has to finish
# before that emit (the HUD refresh it triggers needs to see the FINAL
# RunState.player_hp, sifting cost and any HP_CHANGE effect both already
# applied).
#
# Limited to exactly the categories SiftOutcomeData.EffectType's own doc
# lists - each confirmed (this feature's own report) to already have a
# run-scoped path outside battle. Statuses and trinkets are explicitly
# NOT implemented here, per this pass's own brief - not because they're
# hard, but because neither has an existing run-scoped path today (see
# that report): a status is purely battle-scoped state, and a trinket has
# a settable slot but no offer/choice UI. Adding either would be new
# architecture, not wiring.


# defer_hp_change, if true, skips the HP_CHANGE branch entirely below
# instead of applying it immediately (2026-09-03, water-drink pass) -
# field_heap.gd's own click-to-drink Cold Water interaction needs the
# heal to land AT THE CLICK, not at draw time, so it opts in here and
# calls apply_hp_change() itself once the player actually drinks (see
# that function's own doc, and field_heap.gd's own _play_water_reveal()).
# Defaults to false, so every OTHER caller - field_curio.gd's own
# Investigate is the only other one today - keeps resolving HP_CHANGE
# immediately, exactly as before this parameter existed; nothing about
# any OTHER effect_type branch below reads this parameter at all.
# on_gold_granted, if valid, is called with the ACTUAL rolled amount
# right after RunState.add_gold() (2026-09-04, gold-range pass) - same
# opt-in-callback shape offer_grant_card above already establishes:
# every OTHER caller (field_curio.gd's own Investigate) passes nothing
# and is completely unaffected. field_heap.gd's own Sift pull passes
# _spawn_gold_number here so the floating "+N" it shows always matches
# what was actually granted, not the entry's own fixed `value` - the
# amount isn't known until AFTER the roll happens inside this function,
# so there's no way for the caller to know it ahead of the call.
static func resolve(outcome: SiftOutcomeData, defer_hp_change: bool = false, offer_grant_card: Callable = Callable(), on_gold_granted: Callable = Callable()) -> void:
	match outcome.effect_type:
		SiftOutcomeData.EffectType.NONE:
			pass
		SiftOutcomeData.EffectType.GOLD:
			var amount: int = _roll_value(outcome)
			RunState.add_gold(amount)
			if on_gold_granted.is_valid():
				on_gold_granted.call(amount)
		SiftOutcomeData.EffectType.GRANT_CARD:
			var drawn_card: CardData = _draw_weighted_card(outcome)
			if offer_grant_card.is_valid():
				# Opt-in shape (2026-09-04, weighted-grant pass) - same
				# "a specific caller opts into different behavior, every
				# other caller keeps today's" split defer_hp_change already
				# establishes for HP_CHANGE above. field_heap.gd's own Sift
				# pull passes _play_grant_card_reveal here: the drawn card
				# shows in-field, click-to-take-or-walk-away, and THIS
				# function grants (RunState.add_card_to_deck) and plays
				# add_card only on accept - both moved out of this branch
				# entirely for that caller (see the callback's own doc for
				# why). field_curio.gd's own Investigate never passes one,
				# so it falls straight to the else below, unaffected.
				await offer_grant_card.call(drawn_card)
			else:
				RunState.add_card_to_deck(drawn_card)
				AudioManager.play_sfx("add_card")
		SiftOutcomeData.EffectType.REMOVE_CARD:
			# Player-chosen now (2026-09-04, removal-picker pass) - REPLACES
			# the old RunState.remove_card_from_deck(outcome.card), which
			# silently no-op'd whenever the deck held no copy of whatever
			# card this ENTRY happened to be authored with (Array.erase()'s
			# own behavior). outcome.card is no longer read here - left in
			# the schema (GRANT_CARD still reads it) rather than deleted,
			# per this pass's own brief. Same "generalize the existing
			# picker" reuse UPGRADE_CARD just below already established for
			# CardUpgradeService's own DeckViewer instance - see that
			# service's offer_removal() for why this got a new sibling
			# method rather than a mode branch inside offer_upgrade()
			# itself. Cancelling (Close/Escape) leaves the deck untouched
			# and this branch simply completes - same as a cancelled
			# UPGRADE_CARD today, no special handling needed here for it.
			await CardUpgradeService.offer_removal()
		SiftOutcomeData.EffectType.UPGRADE_CARD:
			# Unfiltered, same default the shop's own "Upgrade a Card"
			# offer uses - manage_pause defaults to true, so this pauses
			# the tree itself (the field isn't already paused the way a
			# modal-driven caller would leave it) and unpauses on close.
			await CardUpgradeService.offer_upgrade()
		SiftOutcomeData.EffectType.HP_CHANGE:
			if not defer_hp_change:
				apply_hp_change(outcome)
		_:
			# Catches a future EffectType value this function hasn't been
			# taught yet, or a stale raw int left over from a renumbered
			# enum (same integer-fragility CardEffect.EffectType's own doc
			# warns about) - warn and no-op rather than crash the pull.
			push_warning("SiftOutcomeData names an unsupported effect_type (%s) - resolving as no-op." % outcome.effect_type)

# Applies an HP_CHANGE outcome's own clamped RunState.player_hp change -
# split out of resolve()'s own HP_CHANGE branch (2026-09-03, water-drink
# pass) so a caller can apply it at a DIFFERENT moment than the rest of
# resolve() (field_heap.gd's water-card click, specifically), rather than
# only ever at draw time. Still the ONLY place this math lives - resolve()
# itself calls this directly when defer_hp_change is false, so the two
# never drift into two separate copies of the same clamp.
#
# Floored at 1, never fatal - see SiftOutcomeData.EffectType's own HP_
# CHANGE doc for why a hazard-flavored (negative) entry can't be allowed
# to kill the player in the field. Dispatches to RunState.heal()/lose_hp()
# by sign (2026-09-05, HP-signal pass) rather than one shared clamp - a
# non-negative value can only ever raise HP (heal's ceiling-only clamp
# matches exactly, since adding to an already->=1 value can't need a
# floor), a negative value can only ever lower it (lose_hp's floor-1
# matches exactly, same as before).
static func apply_hp_change(outcome: SiftOutcomeData) -> void:
	if outcome.value >= 0:
		RunState.heal(outcome.value)
	else:
		RunState.lose_hp(-outcome.value)

# GRANT_CARD's own draw - the SAME WeightedRandom.pick() technique every
# other odds roll in this project uses (2026-09-04, weighted-grant pass),
# zipping outcome.weighted_cards/weighted_card_weights into a real
# Dictionary at the one place that actually needs one, rather than
# authoring a Dictionary-shaped resource (Godot's Inspector has no clean
# editor for a CardData-keyed Dictionary - see SiftOutcomeData.weighted_
# cards' own doc for why two parallel Arrays instead). Falls back to the
# older, simpler `card` field when weighted_cards is empty (every
# GRANT_CARD entry except this heap's own) - same "empty means use the
# old shape" idiom every other opt-in field in this project already
# follows.
# GOLD's own roll (2026-09-04, gold-range pass) - value_max > value means
# "authored as a range," a uniform randi_range(value, value_max) inclusive
# stands in for the old fixed `value`; value_max left at its 0 default (or
# any value <= value) falls back to `value` unchanged, same "empty/
# default means old behavior" idiom _draw_weighted_card() above already
# follows for weighted_cards. Deliberately only wired into the GOLD
# branch above today (see value_max's own doc on SiftOutcomeData) - kept
# as its own function, not inlined, so a later effect_type could reuse it
# without duplicating the range check.
static func _roll_value(outcome: SiftOutcomeData) -> int:
	if outcome.value_max > outcome.value:
		return randi_range(outcome.value, outcome.value_max)
	return outcome.value

static func _draw_weighted_card(outcome: SiftOutcomeData) -> CardData:
	if outcome.weighted_cards.is_empty():
		return outcome.card
	var weights: Dictionary = {}
	for i in outcome.weighted_cards.size():
		var w: float = outcome.weighted_card_weights[i] if i < outcome.weighted_card_weights.size() else 1.0
		weights[outcome.weighted_cards[i]] = w
	return WeightedRandom.pick(weights)
