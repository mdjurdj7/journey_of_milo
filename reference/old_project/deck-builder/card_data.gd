extends Resource
# "extends Resource" means this isn't a node that lives in a scene — it's a
# data container. Resources are Godot's way of making reusable, saveable
# pieces of data (like a card) that you can create once and reference from
# anywhere.

class_name CardData
# This line lets us use "CardData" as a type name elsewhere in the project,
# and lets Godot list it as a resource type we can create in the editor.

# The enum below defines the kinds of cards we support right now.
# CardType.ATTACK is stored internally as 0, CardType.SKILL as 1,
# CardType.STANCE as 2 (added 2026-08-28, plumbing-only pass - see
# placeholder_stance.tres). STANCE appended AFTER SKILL, not inserted
# between ATTACK and SKILL - existing .tres files store card_type as a
# raw integer index, so reordering ATTACK/SKILL would silently remap
# every already-authored card to the wrong type. A future fourth type
# must append the same way.
enum CardType { ATTACK, SKILL, STANCE }

# Ordered from most to least common - see reward_screen.gd's weighted
# roll, which relies on this order to "fall back a tier" by just
# subtracting 1 from whichever rarity it rolled.
enum Rarity { COMMON, RARE, ULTRA_RARE, SECRET_RARE }

# --- Chaining (MINIMUM VIABLE PROTOTYPE - see DESIGN.md's Open
# Questions: Combat tempo / momentum-sequencing note) ---
#
# DESIGN.md flags the full chain/skillchain system as needing its own
# dedicated design session before being built for real - open questions
# there (decay vs. hard reset, universal vs. character-specific, what a
# completed chain actually rewards) are all still unanswered. This enum
# is deliberately NOT that system: it's the smallest possible slice (two
# roles, one numeric bonus, two existing cards) built to let the design
# actually be felt in play before committing to the real thing. See
# battle.gd's own chain_empowered note for how OPENER/CLOSER resolve.
enum ChainRole { NONE, OPENER, CLOSER }

@export var chain_role: ChainRole = ChainRole.NONE
# NONE (most cards; the exceptions today are the OPENERs Bite Down and
# Ballast, and the CLOSER Guillotine - plus the retired Heavy Blow, also
# a CLOSER - see their own .tres files) means this card doesn't
# participate in chaining at all and is completely unaffected by any of
# the logic above. Bite Down
# used to be a CLOSER here; removed (2026-08-26, see DESIGN.md's
# Wanderer entry - "Bite Down's chain payoff: REVERSED") because a
# refund payoff on a card whose whole identity is an unavoidable HP
# cost made the unchained play feel like a mistake rather than a
# choice - Bite Down still always costs its HP regardless of chain
# state, unaffected by the change below. Opener swapped from Slash to
# this card (2026-08-23, see DESIGN.md's own note on this) - Bite Down
# is OPENER now, Slash back to NONE, Guillotine the live CLOSER (it
# carries a real chain_followup_effect; Heavy Blow, the original test
# Closer, is retired).

@export var chain_followup_effect: CardEffect = null
# Only read for a CLOSER-role card (see battle.gd's _trigger_chain_
# payoff()) - what happens as the chain's own separate payoff hit, on
# top of (not instead of) this card's own effects above, which always
# resolve unmodified whether chained or not. Null falls back to Battle's
# shared default payoff (a flat bonus-damage hit, its own
# CHAIN_PAYOFF_DAMAGE) - the "one flat number" prototype behavior this
# field was always meant to eventually replace per-Closer (see that
# shared effect's own comment). Guillotine, the live Closer, DOES set it
# (to Stoppage - a STUN-type payoff, res://resources/chain_payoffs/
# stoppage.tres); the retired Heavy Blow left it null. A card
# that SETS this overrides the shared default entirely with its own
# payoff instead, reusing the exact same CardEffect vocabulary/
# resolution every other effect already uses - a non-damage chain
# payoff needs zero new resolution code, only a new EffectType would
# (see card_effect.gd's own doc), which HEAL/BLOCK/SELF_DAMAGE/DRAW
# already aren't. Bite Down used to be that example (a HEAL-type
# refund) - removed 2026-08-26, see DESIGN.md; Guillotine's Stoppage (a
# STUN payoff) is the live example now. The mechanism itself is
# untouched - nothing about this field's own behavior changed.

# @export makes a variable show up and be editable in the Godot Inspector,
# so we can fill in each card's values without writing code for every card.

@export var card_name: String = ""
# The name printed on the card, e.g. "Slash".

@export var energy_cost: int = 1
# How much energy the player spends to play this card.

@export var toll_cost: int = 0
# Card-level Toll REQUIRED to play this card and SPENT on play (2026-09-08,
# Owed pass) - 0 (every card before Owed) means no Toll gate at all, same
# "0 means unaffected" idiom energy_cost's own sibling fields elsewhere in
# this project use. Distinct from CardEffect.toll_cost (see that file's
# own doc) - THAT field is effect BEHAVIOR (e.g. TOLL_BLOCK/TOLL_RETALIATE
# reading how much Toll their own resolution consumes/requires as part of
# what the card DOES), read per-effect inside _resolve_card_effect(). THIS
# field is a second, independent gate on whether the card can be played AT
# ALL in the first place, checked alongside energy_cost by battle.gd's
# _is_card_playable()/_on_card_clicked(), the same two-part "visual dim +
# actually-enforced refusal" shape energy affordability and the existing
# _card_toll_requirement() check both already use.

@export var card_type: CardType = CardType.ATTACK
# Whether this card is an Attack, a Skill, or a Stance (see the enum above).

@export var rarity: Rarity = Rarity.COMMON
# How rare this card is - shown as a border color on the card face (see
# card.gd) and used to weight reward offers (see reward_screen.gd).
# Defaults to COMMON, so any card that doesn't care about rarity yet
# (or shouldn't) doesn't need to set this explicitly.

@export var requires_target: bool = false
# True if playing this card needs an enemy chosen first (see battle.gd's
# _on_card_clicked()/_begin_targeting()) - clicking the card arms it and
# waits for a click on a living enemy, exactly like a multi-enemy fight
# always has, REGARDLESS of how many enemies are actually on the board
# right now. This is an AUTHORED property, not something battle.gd
# infers from the effects list below - deliberately, so "does this card
# target an enemy" is a fact about the card itself, not a side effect of
# what its effects happen to contain or how many enemies are alive.
# Every card with a DAMAGE/TOLL_DAMAGE/TOLL_THRESHOLD_DAMAGE effect sets
# this true (Slash, Bite Down, Slam, Riposte, Guillotine, Reckoning,
# Compound); a card whose effects are all self/skill-facing (Guard, Iron
# Will, Kept Warmth, Advance, Paid in Pain, Retaliation) leaves it false
# and plays immediately on click, same as it always has.

@export var effects: Array[CardEffect] = []
# What this card actually does when played, in order - see card_effect.gd.
# A card with more than one effect (like Riposte: gain block, then damage
# the enemy) just lists them one after another. Battle resolves each one
# in turn (see _resolve_card_effect() in battle.gd).

@export_multiline var description: String = ""
# The card's RULES text ONLY - mechanical effect, nothing else.
# @export_multiline gives us a bigger text box in the Inspector instead
# of a single-line field - see riposte.tres for a multi-line example.
# Rendered by card.gd in every play/reward context (hand, reward screen,
# card-choice) - see flavor_text below for why those contexts
# deliberately never show anything else.
#
# CONVENTION (formalized 2026-08-27, condition-indicator pass): one
# clause per line, with a literal \n between them - never a flowing
# paragraph, wrapping only when a single clause itself is too long for
# the card's width to avoid. Compound: "Deal 6 damage.\nIf Toll is 15 or
# more, deal 16 damage instead." Each clause reads as its own distinct
# visual unit this way (matters more now that some clauses can carry
# their own emphasis - see [cond_active]/[cond_inactive] below), and it
# already matched how every existing multi-effect card (Bite Down,
# Siphon, Riposte) was authored - this just makes the convention
# explicit instead of implicit.
#
# Raw BBCode is legal here (DescriptionLabel is a RichTextLabel), plus
# two families of semantic tags card.gd expands at render time, never
# typed as raw BBCode directly:
#   - [keyword]/[modified]/[entity]/[reduced] - see card_text_styles.gd's
#     own STYLES dict. Fixed, context-free colors/weights.
#   - [cond_active]/[cond_inactive] - see card_text_styles.gd's own
#     expand_conditional() and battle.gd's _card_condition_active(). Wrap
#     the WHOLE CLAUSE (CORRECTED 2026-08-27 from an earlier, narrower
#     "just the number" version - see this fix's own report: emphasizing
#     a lone numeral read as typographic noise, not a state change) each
#     side of a CONDITIONAL effect (today: TOLL_THRESHOLD_DAMAGE) reads,
#     so battle state can re-weight (never replace - see this pass's own
#     DESIGN note) whichever clause currently applies. Compound: "[cond_
#     inactive]Deal 6 damage.[/cond_inactive]\n[cond_active]If Toll is 15
#     or more, deal 16 damage instead.[/cond_active]" - one clause per
#     line (see this convention's own note above), each line wrapped in
#     full. Only meaningful on a card whose effects actually have a
#     condition to report; authoring them on a non-conditional card is
#     harmless (they render as a no-op if _card_condition_active() never
#     finds a matching effect_type) but pointless.

@export_multiline var flavor_text: String = ""
# World-voice text, separate from description on purpose (2026-08-26
# fix - see DESIGN.md's Toll/Reckoning note): a reward/choose-a-card
# screen is a fast mechanical comparison task, and flavor text is a
# reading task dropped in the middle of it - it also visibly compresses
# the effect text and shifts its position relative to a neighboring
# card with none, which is what actually happened to Reckoning before
# this split (its flavor line was concatenated straight into
# description). NOT rendered by card.gd anywhere today - nothing in
# play or on a reward screen should ever show this. Reserved for the
# deck viewer to surface later (browsing, not optimizing, is where
# flavor belongs), which doesn't exist yet - empty for every card until
# then, same "field exists, no reader yet" shape CardData.art_texture
# already has.

@export var art_texture: Texture2D = null
# The card's illustration, shown in the art slot (see card.gd's ArtSlot/
# ArtTexture) - optional, same "empty means no effect" shape as EnemyData's
# visual_scene. Left null (every card today), the slot just renders as
# its own plain framed box, exactly as it always has - no missing-texture
# error, nothing broken. Assets are expected to live in assets/cards/art/
# once any exist. NOTE: anything dropped in here during development is
# expected to be placeholder-quality (rough sourced/generated images, not
# final), subject to wholesale replacement once real art direction is
# decided - see DESIGN.md's Polish Backlog: ART DIRECTION SESSION.

# Which pool a played copy of this card leaves for (2026-08-28, removal-
# scope pass - REPLACES the old bare `consumed: bool`, see removal_scope
# below) - NONE is index 0 on purpose, so an unset/older card keeps
# exactly today's behavior (goes to Battle's discard pile, comes back on
# reshuffle, forever) with no explicit choice required. SPENT and
# CONSUMED are mutually exclusive by construction now (one enum value,
# not two independent bools that could both be set) - see battle.gd's
# _play_card() for what each one actually does at resolution time.
enum RemovalScope { NONE, SPENT, CONSUMED }

@export var removal_scope: RemovalScope = RemovalScope.NONE
# NONE: ordinary card, goes to discard_pile, can reshuffle back in
# forever within this fight (unchanged behavior).
# SPENT: leaves THIS fight's draw/hand/discard rotation for the rest of
# the fight (Battle's spent_pile, never reshuffled back in - see
# _reshuffle_discard_into_draw()'s own note on why it's excluded) but
# returns automatically next fight, since Battle rebuilds every pile
# from RunState.deck fresh at _start_battle() and never removes a SPENT
# card from RunState.deck at all.
# CONSUMED: also removed from RunState.deck itself the instant it's
# played (see battle.gd's _play_card() calling RunState.remove_card_
# from_deck()) - gone for the rest of the RUN, not just this fight,
# unless another copy is picked up later. It also can't come back within
# the fight it's played in (goes to Battle's run_removed_pile instead of
# the discard pile, so a mid-fight reshuffle can't hand it back either -
# see battle.gd's _reshuffle_discard_into_draw()).

@export var play_sfx: String = ""
# Optional per-card override for the sound played the instant THIS card
# is played (see battle.gd's _play_card()) - empty (every card today
# except Guillotine) plays the shared generic "card_play" cue exactly as
# before, same "empty means no effect" shape EnemyData's attack_impact_
# sfx already uses for the enemy-attack-lands equivalent. A name, not a
# file path - has to be a real key in AudioManager.SFX_FILES, so "which
# file plays" still lives in exactly one place (audio_manager.gd), never
# duplicated here. First use: Guillotine's own heavier cue, distinct from
# the shared punchy card_play sound every other card still uses.
#
# ALWAYS fires immediately (same frame the card is played), regardless of
# impact_delay below (2026-08-25 correction) - it used to wait and fire
# alongside the delayed damage/HP/hit-reaction instead, back when this
# was assumed to be a short impact-only cue. Guillotine's own clip is a
# wind-up-then-impact recording now (an actual "woosh" into the hit), so
# it has to START at play time for its own wind-up to fill the
# impact_delay wait - starting it only once that wait was already over
# would just replay the wind-up a second time, after the hit had already
# visually landed.

@export var upgrades: Array[CardData] = []
# This card's possible upgrades, as full replacement CardData resources -
# empty or unset (every card today) means this card cannot be upgraded
# at all. An upgrade REPLACES this card in the deck outright (see
# card_upgrade_service.gd) rather than modifying it with a delta/
# modifier - deliberately, per DESIGN.md's Card Upgrades note: an
# upgrade needs to be able to change ANY field (damage, cost, chain
# role, name, flavor...), which a numeric-only delta system can't
# express, so even a plain "+3 damage" upgrade goes through full
# resource replacement like everything else.
#
# Most cards will have exactly one entry (a straight improvement).
# Signature cards may have two, offering a directional choice instead -
# the list itself carries both shapes with no mode flag: card_upgrade_
# service.gd only ever branches on `upgrades.size()` (1 vs. more), never
# on anything authored here.
#
# An upgraded card's OWN `upgrades` list is expected to stay empty - no
# chained upgrades. This is an authoring convention, not something
# enforced in code (see card_upgrade_service.gd's own header for why).

@export var impact_delay: float = 0.0
# Seconds between playing this card and its impact actually landing - the
# damage number, HP change, and enemy hit reaction all fire together once
# this elapses, rather than all firing instantly the moment the card is
# played. This card's own play_sfx (see its own doc above) is NOT part of
# that group - it always starts at play time regardless of this value, so
# a sufficiently long/wind-up-shaped clip can fill the wait itself. 0.0
# (every card today except Guillotine) means exactly today's behavior -
# nothing about this field changes anything until a card actually sets
# it. Guillotine sets 0.5: a single heavy hit reads as weighty wind-up-
# then-impact, not an instant number, now that it's gone back to being
# one hit instead of three (see DESIGN.md's Guillotine entry). Raised
# from an initial 0.2 (2026-08-27, same day) once seen live - 0.2 read
# as too quick to register as a wind-up.
#
# Deliberately does NOT delay the player's own step-forward nudge (see
# battle.gd's _play_card()) - the nudge IS the swing, and has to start
# immediately to fill the gap before impact, not wait alongside it.
#
# Applied ONCE per card, before its whole effects list resolves - NOT
# per-effect and NOT per-target. A card with more than one hit-type
# effect (Guillotine's own old 3-hit shape, before its 2026-08-26
# rework - or a future card built the same way) would still only pay
# this delay once, up front, then run its existing multi_hit_delay_sec
# stagger between hits exactly as it does today; there's no card left
# that combines the two to verify this against directly, but the
# implementation (one wait before the resolution loop starts, not
# inside it) makes a per-hit repeat structurally impossible rather than
# just untested.

# --- Runtime state (DECIDED - see DESIGN.md's Per-Copy Card Identity
# section) ---
#
# var, NOT @export - every OTHER field on this resource is authored data,
# baked into a .tres and never written after load; this is the first
# exception, and deliberately marked as one rather than blended in above.
# This is the tradeoff Option A (duplicate CardData per deck slot,
# 2026-08-29) accepted going in: per-copy identity makes it SAFE for a
# specific copy to carry its own runtime state without leaking onto every
# other copy of the same card, but nothing stops that state from being
# authored by mistake if it were exported - leaving it a plain var is
# what keeps the Inspector (and every .tres on disk) from ever showing or
# saving a value that should only ever exist at runtime, transiently, on
# one specific in-memory copy.
var marked_cost_modifier: int = 0
# Leviathan's mark attack (see EnemyIntent.IntentType.MARK, battle.gd's
# own MARK case in _resolve_enemy_intent()) is the first and only writer
# today - added straight onto this ONE specific CardData instance in the
# discard or draw pile, never onto every card sharing this name. 0 (every
# card, always, until marked) means no modifier - _effective_energy_cost()
# in battle.gd and _update_cost_display() in card.gd both add this
# directly onto the base energy_cost wherever a card's cost is computed
# or shown, so an unmarked card (the only case that existed before this
# field did) is completely unaffected. Cleared back to 0 the instant the
# marked card is played (battle.gd's _play_card()) or combat ends
# (_close_out_battle()) - never persists past either boundary, and never
# needs to: a card can only ever be marked while it's sitting in THIS
# fight's own discard or draw pile, so both of those are the only
# lifetimes this value is ever meant to outlive.
#
# Deliberately just an int, not a richer "list of active card effects"
# structure - this is ONE field for ONE effect, per this feature's own
# brief, not the start of a general per-card status system. A second,
# unrelated kind of per-card runtime state showing up later is exactly
# the signal DESIGN.md's own Per-Copy Card Identity section names as the
# point to revisit a CardInstance wrapper instead of continuing to grow
# plain fields here.
