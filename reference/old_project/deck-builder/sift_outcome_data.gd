extends Resource
class_name SiftOutcomeData
# One entry in a wreckage heap's outcome table (2026-08-28, wreckage-heap
# room v1) - "extends Resource" so this is data, editable as a .tres/
# embedded sub-resource without touching GDScript, same "static Resource,
# never mutated at runtime" shape as EnemyData/NPCData/WeaponData. Field
# names are deliberately neutral (effect_type/text/weight/prerequisite),
# not heap/sift/wreckage-prefixed, per this feature's own brief - nothing
# about this schema assumes it will only ever be drawn from a heap.

enum EffectType { NONE, GOLD, GRANT_CARD, REMOVE_CARD, UPGRADE_CARD, HP_CHANGE }
# Same embedded-enum-plus-parallel-fields shape as CardEffect.EffectType
# (see card_effect.gd) - "field exists, only certain types read it,"
# rather than a free-form String matched by hand. Limited to the
# categories SiftOutcomeResolver.resolve() actually implements (2026-08-28
# effect-resolution pass) - each one confirmed to already have a run-
# scoped path outside battle (RunState.add_gold/add_card_to_deck/remove_
# card_from_deck, CardUpgradeService.offer_upgrade, RunState.player_hp).
# Deliberately does NOT include a status or trinket type - this pass's
# own brief explicitly excludes both (neither has an existing run-scoped
# path - see this feature's own report). SiftOutcomeResolver.resolve()'s
# own `_:` default branch is what keeps a future value appended here
# (or a stale raw int from an old .tres, same integer-fragility CardEffect.
# EffectType's own doc already warns about) from ever hard-failing - see
# its own doc.
#   NONE        - no mechanical effect; `text` alone is the outcome. A
#                 legitimate "you find nothing of use" result, not a
#                 placeholder for "not authored yet."
#   GOLD        - RunState.add_gold(value), or a uniform-random roll in
#                 [value, value_max] when value_max is set above value
#                 (see that field's own doc) - a floating "+N" showing the
#                 actual rolled amount, not just the fixed value line, is
#                 required once the amount can vary (2026-09-04, gold-
#                 range pass).
#   GRANT_CARD  - a weighted pick among `weighted_cards` (see that field's
#                 own doc), shown in-field as a click-to-take-or-walk-
#                 away offer, added to the deck only if taken (2026-09-04,
#                 weighted-grant pass). Falls back to the older, simpler
#                 RunState.add_card_to_deck(card) - granted immediately,
#                 no offer - for any entry that leaves `weighted_cards`
#                 empty, so this stays backward-compatible with a future
#                 table that only ever wants ONE fixed, unconditional
#                 grant.
#   REMOVE_CARD - await CardUpgradeService.offer_removal() (2026-09-04,
#                 removal-picker pass) - opens the SAME shared DeckViewer
#                 offer_upgrade() uses, unfiltered over the full live
#                 deck, and removes whichever card the player picks. This
#                 entry's own `card` field is NOT read for this type any
#                 more (left set, unused - see that field's own doc);
#                 the choice is the player's now, not authored per-entry.
#   UPGRADE_CARD - await CardUpgradeService.offer_upgrade(), unfiltered,
#                 same as the shop's own "Upgrade a Card" service - opens
#                 its own DeckViewer selection over every eligible card in
#                 the live deck. Reports NO_ELIGIBLE_CARDS quietly (via
#                 CardUpgradeService's own Outcome) if nothing in the deck
#                 has an upgrade authored - no separate handling needed
#                 here for that case.
#   HP_CHANGE   - RunState.heal(value) for a non-negative value, RunState.
#                 lose_hp(-value) for a negative one (SiftOutcomeResolver.
#                 apply_hp_change(), 2026-09-05, HP-signal pass - REPLACES
#                 a single RunState.player_hp += value clamped to [1,
#                 player_max_hp] directly) - lose_hp()'s own floor-1 is
#                 never fatal, same floor pay_window.gd's own Blood cost
#                 and this heap's own sifting cost already use, for the
#                 same reason (see field_heap.gd's own doc): there is no
#                 field-side death handling anywhere in this project, so a
#                 HAZARD-flavored HP_CHANGE (a negative value) has to stay
#                 non-lethal the same way every other outside-battle HP
#                 loss already does. A healing HP_CHANGE (positive value)
#                 was never at risk of this - heal()'s own ceiling-only
#                 clamp needs no floor at all.

@export var effect_type: EffectType = EffectType.NONE

@export var value: int = 0
# GOLD: the amount granted (or the LOW end of a rolled range - see
# value_max below). HP_CHANGE: the signed HP delta (positive heals,
# negative damages). Unused/ignored by every other type, same "field
# exists, only certain types read it" shape CardEffect's own `value`
# already follows.

@export var value_max: int = 0
# Optional roll range's HIGH end (2026-09-04, gold-range pass) - 0/unset
# by default, meaning "no range, use `value` as a fixed amount," same
# "empty/default means old behavior" idiom weighted_cards below already
# follows. When set ABOVE `value`, SiftOutcomeResolver rolls a uniform
# random int in [value, value_max] inclusive for the effective amount
# instead of using `value` directly (see SiftOutcomeResolver._roll_
# value()). Generic to the schema - any type whose own field reads
# `value` could opt into a range this way - but only GOLD's own resolver
# branch actually rolls it today; wiring a second type in later is a
# resolver-side change, not a schema one. This heap's own GOLD entry is
# the first and only author of this field (value 30, value_max 60) -
# every other entry leaves it at 0 and resolves exactly as before.

@export var card: CardData = null
# GRANT_CARD: the card added to the deck, but ONLY when weighted_cards
# below is empty (see its own doc - the fallback, unoffered, single-card
# path). Unused/ignored by every other type, REMOVE_CARD included
# (2026-09-04, removal-picker pass - the player picks which card leaves
# the deck now, not this field; see that EffectType's own doc above) and
# UPGRADE_CARD (intentionally unfiltered - see its own doc above, never
# scoped to this field either).

@export var weighted_cards: Array[CardData] = []
@export var weighted_card_weights: Array[float] = []
# GRANT_CARD only (2026-09-04, weighted-grant pass) - the smallest shape
# that carries "pick ONE of a few cards, unevenly likely" without a
# general loot-pool resource: two parallel arrays, not a Dictionary
# (Godot's Inspector has no clean CardData-keyed-Dictionary editor, and a
# .tres can't embed one legibly either - two Arrays are both, same
# "parallel arrays over a Dictionary" shape SiftOutcomeData's own sibling
# fields already avoid needing). Zipped into a real Dictionary and handed
# to WeightedRandom.pick() at resolution time (SiftOutcomeResolver.
# resolve()) - the SAME weighted-pick utility every other odds roll in
# this project already uses, not a new one. weighted_card_weights[i] is
# weighted_cards[i]'s own weight; a weight array shorter than the cards
# array (shouldn't happen, not validated) falls back to 1.0 for whichever
# entries have no matching weight. Empty (every GRANT_CARD entry except
# this heap's own) means "use the older single `card` field instead, no
# offer, immediate grant" - see that field's own doc.

@export_multiline var text: String = ""
# The line shown when this entry is drawn - world-voice, same register
# NPCData.dialogue_text/EnemyData.flavor_text already use for their own
# "what the player reads" field.

@export var weight: float = 1.0
# This entry's own odds relative to every other STILL-UNDRAWN entry in the
# same table, same WeightedRandom.pick() shape combat_weight/treasure_
# weight/event_weight already use - see SiftOutcomePool.draw().

@export var prerequisite: String = ""
# Reserved for a future "this entry can only be drawn if ___" condition -
# authored into the schema now so entries can already carry one without a
# later migration, but INERT: nothing reads this field yet, and this pass
# deliberately does not build any conditional-evaluation logic to act on
# it (explicit instruction, 2026-08-28 wreckage-heap room v1 brief).
