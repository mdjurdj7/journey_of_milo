extends Resource
# "extends Resource" means this isn't a node that lives in a scene — it's a
# data container, same idea as CardData. See card_data.gd for the fuller
# explanation of what a Resource is and why we use one here.

class_name EnemyIntent
# One entry in an enemy's intent pattern: what it's about to do, and how
# strong it is. An EnemyData holds an array of these (see enemy_data.gd)
# and — once the turn system exists — the enemy will cycle through them
# in order, one per turn.

enum IntentType { ATTACK, DEFEND, IDLE, WIND_UP, GROWTH, CHARGE_ATTACK, MARK }
# Mirrors CardData's CardType enum: IntentType.ATTACK is stored as 0,
# IntentType.DEFEND as 1. IDLE (2, added for the Tideworn's "falling
# apart" turn - see DESIGN.md's Bestiary) is a genuine no-op: nothing
# lands, nothing is gained. battle.gd's resolution match on this enum
# simply has no IDLE case, which is a safe no-op in GDScript rather
# than an error - no extra resolution code needed. IntentDisplay shows
# a quiet three-dot ellipsis icon for it (intent_icon_idle.gd, wired up
# in intent_display.gd's ICON_SCENES/show_intent()) but no number -
# rather than a shield/blade icon reading "0," which would look like a
# display bug (see BlockBadge's own "never show a null state" instinct
# elsewhere in this codebase), or no icon at all, which read as MISSING
# information rather than "this enemy isn't acting" (no mechanical read
# for the player at a glance, especially with more than one idle enemy
# on screen at once - the actual problem this pass fixed).
#
# GROWTH (4, added for the Mushroom - see DESIGN.md's Bestiary) is a
# SECOND kind of no-op, structurally: like IDLE, it has no case in
# battle.gd's _resolve_enemy_intent() match, so it never declares or
# resolves a combat action through the normal intent-resolution path at
# all. But unlike every other type here, a GROWTH-type enemy never
# actually carries a real EnemyIntent for this in its own `intents`
# array - the Mushroom's is empty, same as any enemy with nothing to
# declare. This enum value exists purely to pick GROWTH's own icon
# (intent_icon_growth.tscn) and drive its muted, system-voice number
# treatment (see intent_display.gd's show_intent()) through Enemy.show_
# growth_countdown() - a display-only seam, entirely separate from
# `intents`/current_intent_index/_advance_enemy_intent(). The actual
# stage-track advancement that decides what number to show lives in
# battle.gd's own _advance_growth_stage(), called unconditionally per
# turn regardless of stun/status/anything else - see that function's
# own doc for why it deliberately does NOT run through this enum's
# match case the way ATTACK/DEFEND/WIND_UP do.
#
# WIND_UP (3, added for the Beachwrack's telegraphed heavy swing - see
# DESIGN.md's Bestiary) resolves exactly like IDLE (a genuine no-op,
# same "no case in battle.gd's match = safe no-op" mechanism, no new
# resolution code) - the difference is entirely in what it SHOWS, not
# what it DOES. IntentDisplay reuses ATTACK's own icon scene directly
# (see intent_display.gd's ICON_SCENES), rendered dim rather than
# unfilled (2026-08-26, pending-opacity pass - see intent_display.gd's
# pending_icon_opacity/pending_value_opacity for why hollow-vs-filled
# was dropped for this: that grammar now means spent-vs-available on
# the energy pips, and this needed its own distinct one). WIND_UP shows
# its real number too, dimmed separately from the icon (see intent_
# display.gd's own doc for why the two need different values) - it's a
# genuine two-turns-out preview now, not just a shape telling the player
# "something's coming" with no number to plan against (an earlier
# version hid the number here - see git history/DESIGN.md - back when
# the icon alone had to carry that whole message). Combat Telegraphing's
# "the number shown is what lands" rule still holds: the swing is
# forced to happen exactly one turn after its wind-up (see battle.gd's
# _pick_erratic_intent_index()), so the previewed number is guaranteed
# accurate, not a guess.
#
# CHARGE_ATTACK (5, added for Leviathan's charge rework - see enemy_
# data.gd's Charge section and battle.gd's _advance_boss_charge()) is a
# real, full-strength attack, structurally identical to ATTACK at
# resolution time (see battle.gd's _resolve_enemy_intent(), which
# matches ATTACK and CHARGE_ATTACK together) - it exists as its OWN type
# only so a Charge-boss's charge-window attack can be found unambiguously
# by battle.gd's _charge_intent_index(), even when the boss ALSO has more
# than one plain ATTACK-type intent (Leviathan authors two: a 14 and a
# 10, picked randomly outside the charge window - see EnemyData.charge_
# attack_value's own doc for why the actual damage number lives there
# instead of on this intent's own `value`). IntentDisplay shows it with
# the exact same icon+number treatment as ATTACK (see intent_display.gd's
# ICON_SCENES) - a charge-window attack should read as a real, undimmed
# threat, not a preview like WIND_UP.
#
# MARK (6, added for Leviathan's mark attack, 2026-08-29) is a real
# resolved action with no damage of its own - see battle.gd's own MARK
# case in _resolve_enemy_intent(), which marks one CardData in the
# player's discard or draw pile (see CardData.marked_cost_modifier's own
# doc) rather than dealing HP loss. Exists as its own type for the same
# "found unambiguously among several baseline attacks" reason CHARGE_
# ATTACK does just above - Leviathan's _pick_baseline_attack_index()
# picks randomly among its plain ATTACK-type entries (14/10) same as
# before; MARK is a THIRD baseline option alongside them, never confused
# with either since it's a different type. IntentDisplay gives MARK its
# own dedicated icon (intent_icon_mark.tscn, 2026-08-29 - previously
# reused ATTACK's own chevron as a placeholder) shown at full opacity
# (same "a real hostile action" register CHARGE_ATTACK's reuse already
# established) but with no number - same "genuine no-op number, would
# read as a display bug otherwise" reasoning IDLE's own doc gives, since
# there's no damage value for this intent to preview.
@export var type: IntentType = IntentType.ATTACK
# What kind of thing this intent does.

@export var value: int = 0
# How much: damage dealt if type is ATTACK, block gained if type is
# DEFEND. Meaningless for IDLE - never read at resolution or display
# time for it. WIND_UP now DOES read and show this (2026-08-26,
# pending-opacity pass - see IntentType's own doc above) as its
# recessive two-turns-out preview number, so a WIND_UP entry's value
# MUST match its paired ATTACK's value exactly (see beachwrack.tres) -
# this is no longer just a human-readability convention, an actual
# mismatch would now show the player a wrong number.

@export var erratic_weight: float = 1.0
# Only consulted by erratic selection (see EnemyData.erratic_intent_
# selection) - when battle.gd's _pick_erratic_intent_index()/_pick_
# erratic_initial_index() choose freely among several candidates, this
# is each one's relative likelihood (see weighted_random.gd: double the
# weight = double the odds, not a percentage on its own). Every intent
# defaults to 1.0 - equal odds among candidates, the exact same result
# a plain unweighted pick already gave, so no enemy's stationary
# distribution changes unless a specific intent is explicitly tuned
# down (or up) from here. First real use: the Beachwrack's Settle
# intent, weighted down after playtesting found it coming up too often
# at an even 50/50 - see its own Bestiary entry.

@export var turn_one_locked: bool = false
# Excludes THIS specific intent from an erratic enemy's very first pick
# (see battle.gd's _pick_erratic_initial_index_turn_one_locked(), the
# Sputter's own initial-index picker) - a per-INTENT flag rather than a
# type-based exclusion because two intents can share the same IntentType
# (the Sputter's Strike and Scissor are both ATTACK) while only one of
# them needs locking out of turn one; filtering by type alone would have
# caught both. False (every intent except the Sputter's Scissor) means
# no effect - this intent is a normal candidate on every turn, including
# the first, same "false/empty means unaffected" idiom every other
# opt-in field on EnemyIntent/EnemyData already uses. Does NOT lock this
# intent out of any LATER turn - _pick_erratic_intent_index() (the
# normal turn-to-turn advance) never reads this field at all, so once
# an enemy is past its first pick, a turn_one_locked intent is a fully
# normal weighted candidate again.
@export var no_immediate_repeat: bool = false
# Excludes THIS specific intent from being picked as the very next turn's
# free choice if it was ALSO the intent picked last turn (see battle.gd's
# _pick_erratic_intent_index()) - only meaningful for erratic selection;
# a non-erratic enemy's fixed intent loop never reads this at all. A
# per-INTENT flag, not a type-based exclusion (same reasoning turn_one_
# locked's own doc gives for itself) - two intents can share a type while
# only one of them should never repeat. False (every intent before the
# Sputter's Block) means no effect - this intent is a normal candidate
# on every turn, including right after itself, same "false/empty means
# unaffected" idiom every other opt-in field on this class already uses.
# First real use: the Sputter's Block (2026-09-08) - reads as a stall
# when it comes up twice back to back, so it's flagged to never repeat
# immediately.
@export var status_data: StatusEffectData = null
# A status this intent applies to the PLAYER when it resolves (battle.gd's
# _resolve_enemy_intent()), independent of `type`/`value` - null (every
# intent before Saltdarner) means no status, same "empty means unaffected"
# idiom every other opt-in field here already uses. Applied via the same
# _apply_status() every CardEffect.APPLY_STATUS/TOLL_RETALIATE call already
# uses (see card_effect.gd's status_data), not a new mechanism - so
# stacking follows whatever StatusEffectData.stack_rule the resource
# itself declares, same as everywhere else. Orthogonal to `type`/`value`:
# an ATTACK intent with both a nonzero value AND a status_data deals its
# damage through the normal _enemy_attack_player() path (Rally/Toll
# included) AND separately applies the status - the two never share one
# code path, so a TICK status's own damage (resolved later, at the next
# turn boundary via _tick_statuses()/_deal_status_tick_damage_to_player())
# stays outside Rally exactly like every other status tick already is.

@export var flavor_text: String = ""
# CURRENTLY UNUSED (2026-08-27, "cut routine flavor" pass - see this
# pass's own report) - enemy.gd's show_intent() no longer reads this
# field at all, for ANY intent, on ANY enemy. It used to render beneath
# the icon+number on every routine turn (ATTACK/DEFEND/WIND_UP/IDLE),
# restating what the icon+number already show - cut for exactly that
# reason. Several enemies still have real authored text sitting here
# (Beachwrack, Tideworn, Unrelieved, Outbound) - deliberately NOT
# deleted, so this remains reversible: the data is intact, only the read
# site stopped looking at it (see enemy.gd's show_intent() own note).
# FlavorLabel today only ever shows load-bearing text that has no other
# signal on screen - EnemyData.pain_turn_flavor, CardEffect.
# combat_message on a STUN resolution, and EnemyData.escalation_stage_
# descriptions - none of which read this field.
