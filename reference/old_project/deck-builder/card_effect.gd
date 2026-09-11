extends Resource
# Same pattern as CardData and EnemyIntent (see card_data.gd /
# enemy_intent.gd): a plain data container, not a node.

class_name CardEffect
# One effect a card causes when played. A CardData holds an array of
# these instead of one-off damage/block fields (see card_data.gd), so a
# card can do several things in order, and adding a new kind of thing a
# card can do never means adding another field to CardData. Battle
# resolves each one through _resolve_card_effect() in battle.gd.

enum EffectType { DAMAGE, BLOCK, SELF_DAMAGE, DRAW, HEAL, TOLL_DAMAGE, STUN, TOLL_BLOCK, TOLL_RETALIATE, SELF_DAMAGE_TOLL, TOLL_THRESHOLD_DAMAGE, DAMAGE_ALL, APPLY_STATUS, FIRST_CARD_DAMAGE, TOLL_FRACTION_DAMAGE_ALL, UNDAMAGED_BLOCK, GAIN_ENERGY, ABSORB, APPLY_STATUS_TO_TARGET }
# TOLL_FRACTION_DAMAGE_ALL/UNDAMAGED_BLOCK/GAIN_ENERGY/ABSORB/APPLY_STATUS_
# TO_TARGET appended at the END (2026-08-28, 2026-08-29, 2026-09-04,
# 2026-09-05, 2026-09-08) - every earlier value's own integer is baked
# into existing .tres files as a raw number, so a new entry can only ever
# be added here, never inserted mid-list without silently corrupting
# every card authored before it.
# What this effect does when resolved:
#   DAMAGE      - deal `value` damage to the enemy (through its block).
#   BLOCK       - gain `value` player block.
#   SELF_DAMAGE - lose `value` player HP directly, ignoring block.
#   DRAW        - draw `value` cards.
#   HEAL        - restore `value` player HP, capped at max HP.
#   TOLL_DAMAGE - consume ALL of battle.gd's own `toll` and deal that
#                 much damage to the enemy. `value` is unused/ignored -
#                 the amount is whatever Toll currently is, read fresh
#                 at resolution time, not an authored number (see
#                 battle.gd's own _resolve_card_effect()). A card using
#                 this should also be recognized by _card_needs_target()
#                 (targeted, like DAMAGE) and _card_toll_requirement()
#                 (unplayable while Toll is 0) - both derive this from
#                 the effect type, the same way _card_needs_target()
#                 already does for DAMAGE, rather than a new authored
#                 flag on CardData.
#   STUN        - cancels the target's queued intent for its next turn
#                 (see battle.gd's _apply_intent_interrupt()). `value` is
#                 unused, same "ignored for this type" shape as TOLL_
#                 DAMAGE above - a stun doesn't scale, it either lands or
#                 it doesn't. Reuses the EXACT same interrupt mechanism
#                 the Wardling's own below-threshold pain turn already
#                 uses (see enemy_data.gd's pain_turn_hp_threshold) - not
#                 a parallel implementation. Reads combat_message below
#                 for what shows under the target when it lands; today
#                 only reachable as a CardData.chain_followup_effect (see
#                 its own doc), never a card's own top-level effect, but
#                 nothing about resolution requires that - a future card
#                 could stun directly.
#   TOLL_BLOCK  - consume a FIXED `toll_cost` of battle.gd's own `toll`
#                 (not all of it - contrast TOLL_DAMAGE above) and gain
#                 `value` player block, DOUBLED if RunState.player_hp is
#                 below half of RunState.player_max_hp at resolution time
#                 (see battle.gd's own _resolve_card_effect()). The 2x is
#                 hardcoded, not a second authored multiplier field - the
#                 first card using this (Paid in Pain) specifies a fixed
#                 double, not a per-card tunable ratio; a future card
#                 needing a different ratio is what would turn this into
#                 a real field, not before. A card using this should also
#                 be recognized by battle.gd's toll-requirement gating the
#                 same way TOLL_DAMAGE already is, except the minimum
#                 needed is `toll_cost` itself, not just "any Toll at
#                 all" - see battle.gd's own toll-requirement function.
#                 Untargeted, like BLOCK - not added to _card_needs_
#                 target(). Also recognized by battle.gd's own
#                 _card_condition_active() (2026-08-27, condition-
#                 indicator pass, extended from Compound to Paid in
#                 Pain) - active below half HP, the exact same check
#                 _resolve_card_effect() doubles `value` on, shared via
#                 _is_player_below_half_hp() rather than typed twice.
#   TOLL_RETALIATE - consume a FIXED `toll_cost` of Toll (same shape as
#                 TOLL_BLOCK above) and apply `status_data` to the
#                 player's own status list (battle.gd's player_statuses),
#                 UNLESS that exact status is already active - in which
#                 case this is a complete no-op and does NOT spend Toll
#                 either (see battle.gd's own _resolve_card_effect() for
#                 why that check has to happen BEFORE the spend, not left
#                 to status_data's own StackRule.IGNORE, which would
#                 still let the Toll already be gone by the time it no-
#                 ops). `value` is unused here - status_data's own fields
#                 (StatusEffectData.default_magnitude/duration_turns/etc)
#                 carry whatever the applied status needs; this effect
#                 only decides WHETHER to apply it and what it costs.
#                 Untargeted, like TOLL_BLOCK - not added to _card_needs_
#                 target(). Recognized by battle.gd's toll-requirement
#                 gating the same way TOLL_BLOCK already is (minimum
#                 needed is `toll_cost`). First use: Retaliation (see
#                 resources/cards/classes/wanderer/retaliation.tres),
#                 applying resources/statuses/retaliation_primed.tres.
#   SELF_DAMAGE_TOLL - lose up to `value` HP, floored so it can NEVER
#                 take the player below 1 (unlike plain SELF_DAMAGE
#                 above, which can kill) - and gain exactly `toll_gain`
#                 Toll in TOTAL, no matter how much of that HP loss the
#                 floor actually clamped away. The part of the loss that
#                 DOES land still goes through the normal self-damage
#                 path (battle.gd's _deal_self_damage(), same Rally-
#                 exempt, block-ignoring behavior as SELF_DAMAGE), which
#                 still feeds the ordinary per-HP-lost Toll accrual in
#                 _set_player_hp() same as any other self-damage - this
#                 effect then tops that up with whatever's left of
#                 `toll_gain` (see battle.gd's own _resolve_card_
#                 effect()), so the total toll gained always lands
#                 exactly on the authored number. Untargeted like
#                 SELF_DAMAGE - not added to _card_needs_target(). Not
#                 gated by _card_toll_requirement() - this GRANTS Toll,
#                 it never costs any to play. First use: Advance (lose 5
#                 HP, gain 10 Toll flat even at 1 HP, where none of that
#                 5 can actually be lost).
#   DAMAGE_ALL  - deal `value` damage to EVERY living enemy (see battle.
#                 gd's own _living_enemies()), not just one - the first
#                 targeted-but-not-single-target case, so it deliberately
#                 does NOT set CardData.requires_target (there is no
#                 "which enemy" to pick, so this plays immediately on
#                 click like an untargeted card does, even though it
#                 hits enemies). Same OUTGOING_DAMAGE status modifier and
#                 weapon CATEGORY_DAMAGE modifier pipeline as plain DAMAGE
#                 above, computed ONCE for the card, then applied to each
#                 living enemy via battle.gd's own _deal_damage_to_enemy()
#                 (which still separately re-applies that TARGET's own
#                 INCOMING_DAMAGE modifiers/falloff per enemy) - a multi-
#                 enemy fight isn't a new targeting system here, just a
#                 loop over the same per-target resolution every other
#                 damage source already funnels through. First use: Full
#                 Weight (resources/cards/classes/wanderer/full_weight.tres).
#   APPLY_STATUS - apply `status_data` to the player's own status list
#                 (battle.gd's player_statuses), unconditionally - no Toll
#                 cost, no already-active check (contrast TOLL_RETALIATE
#                 above, which is Toll-gated AND no-ops instead of
#                 stacking). Reapplying while already active still just
#                 goes through status_data's own StackRule exactly like
#                 TOLL_RETALIATE's does. `value` is unused here, same
#                 "field exists, only certain types read it" shape as
#                 every other type above. Untargeted - not added to
#                 _card_needs_target(). First use: Full Weight, applying
#                 resources/statuses/overextended.tres (blocks the choke
#                 point where player block is granted - see battle.gd's
#                 own _gain_player_block() - for the entirety of the
#                 player's next turn).
#   FIRST_CARD_DAMAGE - deal `value` damage, or `threshold_value` instead
#                 if this is the first card the player has played this
#                 turn. Same "reads a live condition, replaces the base
#                 number, never adds to it" shape as TOLL_THRESHOLD_DAMAGE
#                 below, just gated on battle.gd's own cards_played_this_
#                 turn counter (reset at the start of each player turn,
#                 incremented once a card's own effects finish resolving -
#                 see _play_card()'s own note on why it increments THERE,
#                 not earlier) instead of Toll. Checked fresh at
#                 resolution time reading cards_played_this_turn == 0,
#                 same "read the live number, not a snapshot" rule every
#                 other condition here follows. `toll_cost`/`toll_
#                 threshold` are unused, same "field exists, only certain
#                 types read it" shape every other type follows. Targeted
#                 and hit-shaped exactly like TOLL_THRESHOLD_DAMAGE -
#                 added to both _card_needs_target() (via CardData.
#                 requires_target, authored directly) and _is_hit_
#                 effect(). Also recognized by _card_condition_active()
#                 (same live check, read while the card still sits in
#                 hand - true there means "would be first if played right
#                 now," i.e. the identical cards_played_this_turn == 0
#                 test, just evaluated a moment earlier). First use: Left
#                 Hand (resources/cards/classes/wanderer/npc_offers/
#                 left_hand.tres) - deal 6, or 10 played first, replacing
#                 an earlier flat-6 version whose "+4 if first" clause was
#                 authored in the description but never backed by code
#                 (no cards-played-this-turn tracking existed at all until
#                 this effect type needed one).
#   TOLL_THRESHOLD_DAMAGE - deal `value` damage, or `threshold_value`
#                 instead if `toll` is currently >= `toll_threshold`.
#                 Reads Toll as a CONDITION ONLY - unlike every other
#                 TOLL_* type above, this one never spends any (see
#                 battle.gd's own _resolve_card_effect() - there's no
#                 toll -= line in this case at all). Checked fresh at
#                 resolution time, same "read the live number, not a
#                 snapshot from when the card was drawn/played" rule
#                 Paid in Pain's own HP check already follows. Targeted
#                 and hit-shaped exactly like plain DAMAGE - added to
#                 both _card_needs_target() and _is_hit_effect() the
#                 same way TOLL_DAMAGE already is. NOT added to
#                 _card_toll_requirement() - reading Toll isn't spending
#                 it, so this never gates whether the card can be played,
#                 only which damage number it deals once it is. First
#                 use: Compound (deal 6, or 16 at 15+ Toll).
#   TOLL_FRACTION_DAMAGE_ALL - spend floor(toll * `toll_fraction`) of
#                 battle.gd's own `toll` and deal that much bonus damage
#                 to EVERY living enemy - a hybrid of TOLL_DAMAGE (spends
#                 Toll, amount read fresh at resolution time, not an
#                 authored number) and DAMAGE_ALL (hits every living
#                 enemy, not just one). Unlike TOLL_DAMAGE, this does NOT
#                 spend everything - only the authored fraction, so it
#                 stays meaningful as a SECOND effect stacked after a
#                 flat DAMAGE_ALL hit rather than replacing it. `value`
#                 is unused, same "field exists, only certain types read
#                 it" shape every type above already follows. The Toll
#                 REMOVED from the pool is the raw spent amount, before
#                 any OUTGOING_DAMAGE/weapon amplification - only the
#                 damage dealt is amplified, same split TOLL_DAMAGE's own
#                 case already makes. Untargeted like DAMAGE_ALL - not
#                 added to _card_needs_target(). NOT added to
#                 _card_toll_requirement() either - at 0 Toll this is a
#                 harmless no-op (spends 0, deals 0 bonus), and the
#                 card's own base DAMAGE_ALL hit still lands regardless,
#                 so nothing about this should ever block play the way
#                 TOLL_DAMAGE's own all-or-nothing spend does. Hit-shaped
#                 like DAMAGE_ALL - added to _is_hit_effect() so a card
#                 stacking this after a flat DAMAGE_ALL hit gets the
#                 usual multi-hit stagger gap between the two waves.
#                 First use: Owed in Full (resources/cards/classes/
#                 wanderer/owed_in_full.tres) - deal 6 to all enemies,
#                 then spend half (all, upgraded) Toll for a second wave.
#   UNDAMAGED_BLOCK - gain `value` player block, PLUS `bonus_value` more
#                 if the player took no HP loss, from any source, during
#                 their previous turn (see battle.gd's own _took_damage_
#                 last_turn/_took_no_damage_last_turn()). ADDS, unlike
#                 TOLL_THRESHOLD_DAMAGE/FIRST_CARD_DAMAGE above, which
#                 REPLACE value with threshold_value - Held Position's own
#                 text is explicit about that ("gain 4 MORE"), which is
#                 why this reads a separate `bonus_value` field rather
#                 than reusing threshold_value's own REPLACE-shaped
#                 meaning for something that behaves differently. Read
#                 fresh at resolution time (battle.gd's own _resolve_
#                 card_effect()), same "live check, not a snapshot from
#                 when the card was drawn" rule every other conditional
#                 type here already follows. Also recognized by battle.
#                 gd's own _card_condition_active() the same way TOLL_
#                 BLOCK/FIRST_CARD_DAMAGE already are. Untargeted, like
#                 BLOCK - not added to _card_needs_target(). First use:
#                 Held Position (resources/cards/classes/wanderer/npc_
#                 offers/held_position.tres) - the "+4 if no damage last
#                 turn" clause was authored in its description before
#                 this effect type existed to back it, same "described
#                 but not backed by code until this type needed to exist"
#                 history FIRST_CARD_DAMAGE's own doc already tells for
#                 Left Hand above.
#   GAIN_ENERGY - add `value` to battle.gd's own current `energy`,
#                 clamped at `max_energy` (see battle.gd's own _resolve_
#                 card_effect() for why the clamp - a data-layer cap that
#                 didn't exist before this type needed one, matching an
#                 existing DISPLAY-layer ceiling rather than inventing a
#                 gameplay one). No "this turn only" bookkeeping needed -
#                 energy already resets to max_energy at the start of
#                 every player turn (battle.gd's own _start_player_turn()/
#                 _start_battle()), so a gain is inherently already spent
#                 or gone by the next one, same as the base energy pool
#                 itself. Untargeted, like BLOCK - not added to _card_
#                 needs_target(). First use: Kept Coin (resources/cards/
#                 kept_coin.tres) - a single-use (removal_scope = CONSUMED)
#                 found-object card, 0 cost, gain 2 energy.
#   ABSORB      - gain `value` battle.gd's own absorb_pool (see that
#                 var's own doc) - a SECOND, independent damage-reduction
#                 pool from BLOCK above, subtracted in _resolve_damage()
#                 AFTER block, and unlike block, NOT reset every turn -
#                 it persists for the rest of the fight until spent.
#                 Untargeted, like BLOCK - not added to _card_needs_
#                 target(). Also unlike BLOCK, NEVER blocked by
#                 overextended.tres's own NO_BLOCK_STATUS check (Full
#                 Weight's "no block next turn" debuff gates block
#                 specifically, not this pool). First use: Forbearance
#                 (resources/cards/classes/wanderer/forbearance.tres) -
#                 1 energy, gain 8 absorb.
#   APPLY_STATUS_TO_TARGET - apply `status_data` to the CHOSEN ENEMY's own
#                 status list (contrast APPLY_STATUS above, which always
#                 targets the player) - battle.gd's _resolve_card_effect()
#                 applies it to the same `target` its DAMAGE branch reads,
#                 so a card using this type MUST set requires_target true
#                 on its own CardData (same "an AUTHORED property, not
#                 inferred from effects" rule requires_target's own doc
#                 already states) or there is no target to read. `value`
#                 is unused here, same "field exists, only certain types
#                 read it" shape every other type above already follows.
#                 First use: Owed (resources/cards/classes/wanderer/
#                 owed.tres), applying resources/statuses/owed.tres.

@export var effect_type: EffectType = EffectType.DAMAGE
@export var value: int = 0

@export var toll_cost: int = 0
# Read by TOLL_BLOCK and TOLL_RETALIATE above - the fixed amount of Toll
# each consumes. Unused/ignored by every other type, same "field exists,
# only certain types read it" shape `value` already has for TOLL_DAMAGE/
# STUN.

@export var toll_threshold: int = 0
# Only read by TOLL_THRESHOLD_DAMAGE above - the Toll level that must be
# met or exceeded for `threshold_value` to replace `value`. Unused/
# ignored by every other type, same "field exists, only certain types
# read it" shape every other field here already follows. Deliberately
# separate from `toll_cost` above rather than reused - `toll_cost` names
# an amount SPENT, and this type never spends anything, so borrowing
# that field would misname what it holds.

@export var threshold_value: int = 0
# Only read by TOLL_THRESHOLD_DAMAGE above - the damage dealt instead of
# `value` once `toll_threshold` is met. Unused/ignored by every other
# type, same "field exists, only certain types read it" shape every
# other field here already follows.

@export var status_data: StatusEffectData = null
# Read by TOLL_RETALIATE, APPLY_STATUS, and APPLY_STATUS_TO_TARGET above -
# which status to apply. Unused/ignored by every other type, same "field
# exists, only certain types read it" shape every other CardEffect field
# already follows.

@export var toll_gain: int = 0
# Only read by SELF_DAMAGE_TOLL above - the FLAT total Toll that effect
# guarantees, topping up whatever the floor-clamped HP loss already
# accrued automatically. Unused/ignored by every other type, same
# "field exists, only certain types read it" shape every other field
# here already follows.

@export_range(0.0, 1.0, 0.01) var toll_fraction: float = 1.0
# Only read by TOLL_FRACTION_DAMAGE_ALL above - what portion of current
# Toll that effect spends (floor(toll * toll_fraction)), e.g. 0.5 for
# "half your Toll," 1.0 for "all your Toll." Unused/ignored by every
# other type, same "field exists, only certain types read it" shape
# every other field here already follows. Deliberately separate from
# toll_cost above rather than reused - toll_cost names a FIXED authored
# amount (TOLL_BLOCK/TOLL_RETALIATE always spend the exact same number
# every time), while this scales with whatever Toll actually is at
# resolution time, the same live-read TOLL_DAMAGE's own consumed-amount
# already is - a fixed-vs-scaling distinction, not just a naming choice.

@export var bonus_value: int = 0
# Only read by UNDAMAGED_BLOCK above - the extra block ADDED on top of
# `value` when its condition is met. Unused/ignored by every other type,
# same "field exists, only certain types read it" shape every other
# field here already follows. Deliberately NOT threshold_value - see
# UNDAMAGED_BLOCK's own doc for why that field's established REPLACE
# meaning (TOLL_THRESHOLD_DAMAGE/FIRST_CARD_DAMAGE) would misname an
# ADD here.

@export_multiline var combat_message: String = ""
# Shown under the target when this effect resolves, the SAME flavor-
# label channel/style an enemy's own intent text and EnemyData.pain_
# turn_flavor already render through (see enemy.gd's show_intent_
# interrupt()) - only meaningful for STUN today, empty/unused by every
# other type, same "field exists, only certain types read it" shape
# TOLL_DAMAGE's own note above already established for `value`.
# Deliberately NOT named flavor_text - CardData already has a field by
# that name with the opposite rule (world-voice text, NEVER rendered in
# combat - see its own doc); this one is the one thing on this Resource
# that's specifically FOR combat display, so it needed its own name to
# avoid reading as a contradiction of that rule.
