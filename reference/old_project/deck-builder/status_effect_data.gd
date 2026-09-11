extends Resource
class_name StatusEffectData
# The STATIC definition of a status effect - same "plain data container,
# define once as a .tres" shape as CardData/EnemyData. This is mechanism
# only: no named/flavored statuses exist yet (see DESIGN.md's Combat
# tempo open question - statuses/keywords are meant to be designed to
# SERVE this game's own tempo, not imported wholesale from another
# game's vocabulary, and that design session hasn't happened). The one
# instance that exists right now (resources/statuses/test_effect.tres)
# is an explicitly-named dev placeholder for exercising this plumbing,
# not a real status - see its own file header before reusing it as a
# template for real content.
#
# The RUNTIME half - the mutable state of one status actually affecting
# one combatant right now (current magnitude, turns remaining) - lives
# in ActiveStatus instead, the same "static Resource vs. per-fight
# mutable state" split EnemyIntent/EnemyCombatant already use.

enum Category { TICK, MODIFIER, INFORMATIONAL }
# TICK - resolves an effect using magnitude at a turn boundary (see
#   battle.gd's _tick_statuses()) - the generic mechanism a future damage-
#   over-time status would use, dealing `magnitude` un-blockable damage
#   to its own holder each turn (same "bypasses block" precedent battle.
#   gd's SELF_DAMAGE card effect already sets - see _deal_self_damage()).
# MODIFIER - adjusts incoming or outgoing damage by magnitude (see
#   modifier_target/modifier_operation below and battle.gd's _apply_
#   status_modifiers()) - the generic mechanism a future amplify/weaken-
#   style status would use.
# INFORMATIONAL - no mechanical effect of its own. A pure marker -
#   displays, ticks its own duration down, expires - for a future status
#   whose only job is to be checked FOR by some other system (a card
#   effect that reads "does the target have status X"), which doesn't
#   exist yet either.

enum ModifierTarget { INCOMING_DAMAGE, OUTGOING_DAMAGE }
enum ModifierOperation { ADD, MULTIPLY }
# Only meaningful when category == MODIFIER. ADD adds magnitude directly
# to the damage total; MULTIPLY treats magnitude as a PERCENTAGE (50
# means "+50%", -25 means "-25%") rather than a raw multiplier - keeps
# every status's magnitude an int, consistent with every other number in
# this game's combat math (CardEffect.value, EnemyIntent.value, HP,
# block - nothing else here is fractional). See battle.gd's _apply_
# status_modifiers() for the actual math.

enum StackRule { REFRESH_DURATION, ADD_MAGNITUDE, REFRESH_AND_ADD, IGNORE }
# What happens when this exact status (same StatusEffectData) is applied
# again while already active on the same combatant - see ActiveStatus.
# apply_stack(). Configurable PER STATUS (a field on this resource, not
# one hardcoded global rule) since different future statuses will want
# different answers - REFRESH_DURATION is the proposed sensible DEFAULT:
# most status effects in this genre (a DoT, a debuff) conventionally
# reset their clock on reapplication rather than stacking magnitude
# infinitely, which avoids runaway power-creep from repeated small
# applications being the default behavior for every future status by
# accident. ADD_MAGNITUDE/REFRESH_AND_ADD stay available as an explicit
# per-status opt-in for whatever future status specifically wants
# escalating stacks. IGNORE is the true non-stackable case (2026-08-27) -
# a fresh application while already active does nothing at all: no
# refreshed clock, no added magnitude, the existing instance just keeps
# running exactly as it was. Distinct from REFRESH_DURATION (which still
# DOES something on reapplication, just not magnitude) - a status that
# wants reapplying it to be a complete no-op needs this, not that.
#
# "Does nothing at all" is about magnitude/duration specifically, not
# about ActiveStatus.stack_count (2026-08-28) - that counter increments
# on every apply_stack() call regardless of which StackRule is chosen,
# since "how many times has this been applied" is a separate question
# from "did that change magnitude or duration." Selfeater's own IGNORE
# status is the first thing that needs both answers to differ: magnitude
# has to stay flat (a fixed damage bonus) while stack_count still climbs
# (an escalating cost curve reads it) - see attack_hp_drain_base's own
# doc below.

@export var id: String = ""
# A short, stable, code-safe identifier ("test_effect") - snake_case,
# no spaces (not enforced by code, just the expected convention). Used
# for stacking lookups and any future logic that needs to check "does
# this combatant have STATUS X specifically" independent of display_
# name, which can change without breaking anything referencing this by
# id.

@export var display_name: String = ""
# Shown on hover/tooltip once one exists - the badge itself (see status_
# badge.gd) is icon+number only, same "the world doesn't annotate
# itself" restraint DESIGN.md's enemy name-introduction note already
# argues for elsewhere.

@export var category: Category = Category.INFORMATIONAL

@export var default_magnitude: int = 0
# The value a fresh application starts at, before any stacking rule
# adjusts it. What this number MEANS depends entirely on category:
# damage-per-turn for TICK, the add/percentage amount for MODIFIER,
# purely cosmetic (or meaningless) for INFORMATIONAL.

const DURATION_UNTIL_REMOVED := -1
# A status with this exact duration never expires on its own (see
# ActiveStatus.tick_duration()/is_expired()) - something else (a cleanse
# effect, defeat, end of combat) has to remove it instead. Named, not a
# bare -1 magic number at every call site that cares.

const DURATION_UNTIL_TRIGGERED := -2
# A second "doesn't expire via the turn counter" sentinel (2026-08-27),
# distinct from DURATION_UNTIL_REMOVED above even though both skip
# ActiveStatus.tick_duration()'s decrement identically - the difference
# is WHO removes it and WHEN. DURATION_UNTIL_REMOVED needs an outside
# actor (a cleanse, defeat, end of combat) with no natural end otherwise.
# DURATION_UNTIL_TRIGGERED is for a status that's waiting to PROC once -
# whatever consumes it (a damage hook checking for this status, e.g. a
# future single-use reflect/counter effect) is expected to remove it
# immediately and synchronously the instant it fires (battle.gd's own
# _remove_status(), not a tick pass - see _tick_statuses()'s own note on
# why a tick-cleared removal would be too late for a status meant to
# fire at most once per multi-enemy turn). No consumer sets this yet in
# this commit - the mechanism exists ahead of the first status that
# needs it, same "insertion point defined before anything populates it"
# shape this commit's incoming-damage hook already has.

@export var default_duration_turns: int = 1
# How many turns a fresh application lasts, in the unit ActiveStatus.
# turns_remaining actually counts down in. DURATION_UNTIL_REMOVED and
# DURATION_UNTIL_TRIGGERED both opt out of natural expiry entirely (see
# their own docs for how the two differ in who removes them instead).

@export var clears_on_trigger: bool = false
# The combined duration mode (2026-08-27): "expires when triggered OR
# after N turns, whichever comes first." Orthogonal to default_duration_
# turns rather than a third magic sentinel value packed into it, because
# unlike DURATION_UNTIL_REMOVED/DURATION_UNTIL_TRIGGERED (which both
# mean "don't run the normal countdown at all"), this mode NEEDS a real,
# decrementing default_duration_turns - it's the countdown itself that
# provides the "N turns" half. This flag just marks that the status is
# ALSO eligible for early, synchronous removal via battle.gd's _remove_
# status() (same call a pure DURATION_UNTIL_TRIGGERED status expects -
# see its own doc) whenever whatever it's watching for fires, on top of
# whatever the countdown would do on its own.
#
# No code actually branches on this flag - _remove_status() removes
# anything it's handed regardless, and _remove_expired_statuses() only
# ever sees whichever instances are still actually IN the array by the
# time it runs (both _tick_statuses()/_remove_expired_statuses() iterate
# a fresh .duplicate() each call - see their own notes), so a status
# already removed early by _remove_status() simply isn't present for the
# later tick pass to find, erase, or error on - "whichever happens first
# wins" is true by construction, not something enforced here. This field
# exists purely so a StatusEffectData's own duration model documents "an
# external trigger can also end this" without a future reader having to
# trace consuming code to discover that. Retaliation Primed (see
# resources/statuses/retaliation_primed.tres) is the first user: a real
# 1-turn countdown (the "still primed for the Wanderer's next enemy
# phase, then gone" fallback) combined with this flag (so a damage hook
# can also clear it the instant it actually procs).

@export var modifier_target: ModifierTarget = ModifierTarget.INCOMING_DAMAGE
@export var modifier_operation: ModifierOperation = ModifierOperation.ADD
# Only meaningful when category == MODIFIER - see the Category doc above.

@export var stack_rule: StackRule = StackRule.REFRESH_DURATION

# --- Per-attack HP drain (2026-08-28, Selfeater/STANCE pass) ---
#
# Independent of category - a MODIFIER-category status can ALSO drain the
# holder's own HP every time they play an ATTACK card, on top of whatever
# its category already does (Selfeater: MODIFIER + this, at the same
# time, on the same status). 0/0 (every status other than Selfeater's own
# today) means no drain at all - the same "empty means unaffected" shape
# every optional field on this resource already follows. Deliberately
# NOT expressed as its own Category value: TICK/MODIFIER/INFORMATIONAL
# are mutually-exclusive resolution MODES (see the Category doc above),
# but this is a bolt-on side effect that can coexist with whichever mode
# a status already uses - a future status wanting BOTH a MODIFIER bonus
# AND a per-attack cost (like Selfeater) needs this to be additive, not
# a fourth mode that would force choosing between it and MODIFIER.
#
# base is the cost at stack 1; increment is added per stack BEYOND the
# first (stack N costs base + increment * (N - 1) - see ActiveStatus.
# stack_count's own doc for where N comes from). An exported base+
# increment pair rather than a hardcoded curve or a lookup array, so the
# whole curve is two Inspector numbers, easy to retune from playtesting
# with no code change - this is placeholder tuning, expected to move.
@export var attack_hp_drain_base: int = 0
@export var attack_hp_drain_increment: int = 0

@export var is_persistent_stance: bool = false
# Suppresses this status from the status badge row entirely (see vitals_
# bar.gd's own update_statuses() - the SINGLE choke point every caller
# already funnels through, whether it's battle.gd, enemy.gd, or player_
# battle_visual.gd, so this only ever needs checking in one place, not
# once per call site). DISPLAY SUPPRESSION ONLY: an ActiveStatus built
# from a status flagged this way still lives in player_statuses/
# combatant.statuses exactly like any other, still ticks (or doesn't,
# per its own duration), still drives whatever category/modifier/
# attack_hp_drain_* fields it has - this flag never touches any of that,
# only whether update_statuses() builds it a StatusBadge.
#
# --- Why a new field, not an existing one (2026-08-28, Selfeater badge-
# suppression pass) ---
#
# category (TICK/MODIFIER/INFORMATIONAL) answers "what mechanical effect
# does this resolve" - a different question from "should this get a
# generic timed-effect badge." A TICK or a MODIFIER status can equally
# plausibly be either a real timed effect or a persistent stance, so
# category can't stand in for this without conflating two independent
# axes.
#
# default_duration_turns == DURATION_UNTIL_REMOVED was the other real
# candidate, and the wrong one: it answers "does this expire on the turn
# counter," not "does this represent a persistent stance instead of a
# timed effect." A future PERMANENT DEBUFF (needing an outside cleanse -
# the exact same duration shape as Selfeater) would legitimately WANT its
# badge to keep showing for as long as it's active, precisely because it
# never expires on its own and the player needs the reminder. Gating on
# DURATION_UNTIL_REMOVED alone would silently hide that debuff's badge
# too, for a reason that has nothing to do with why Selfeater's own badge
# should be hidden - see this pass's own report for the full comparison.
#
# Selfeater is the only status this is true for today: it's represented
# by player_battle_visual.gd's own stance-tint glow and by every modified
# card face reading attack_hp_drain directly (card.gd's own set_attack_
# hp_drain()/show_status_value_preview()), not by a generic badge - a
# badge would put it visually alongside real timed buffs/debuffs and
# flatten a distinction the design depends on (this pass's own brief).

@export var icon_color: Color = Color(0.6, 0.6, 0.65, 1)
# Placeholder visual - status_badge.gd renders a plain flat-colored
# circle, this color, plus the magnitude number. No real status-icon
# art/direction exists yet, same "small hand-drawn shape, one exported
# color" placeholder language every other combat visual in this game
# already uses until one does.

@export var badge_diameter_override_px: float = 0.0
# 0.0 (every status today except boss_01_charging_indicator.tres) means
# "use StatusBadge's own default diameter" - same "zero means unaffected"
# idiom every other opt-in field in this project already follows. Read by
# VitalsBar.update_statuses() and applied via StatusBadge.set_diameter_
# override() BEFORE that badge is added to the tree (see that function's
# own doc for why it can't be applied any later) - a per-STATUS override,
# not a per-enemy or global one, so a future status wanting a bigger
# badge just sets this on its own .tres, with zero code changes and zero
# effect on any other status's badge. First use: the Leviathan charge-
# window indicator (2026-08-29, charge-badge legibility pass) - the
# default 18px badge read as too small to register as load-bearing state
# once seen live against the boss arena's own pale water background.
# StatusBadge derives its numeral's font size and outline width
# proportionally FROM this one number rather than needing their own
# separate override fields here - see that function's own doc.

@export var tooltip_text: String = ""
# "" (every status today except boss_01_charging_indicator.tres) means no
# tooltip - Godot's own Control.tooltip_text mechanism (applied by
# StatusBadge.set_status()) already no-ops on an empty string, so this
# needs no separate "has a tooltip" flag. First use: the Leviathan
# charge-window indicator's placeholder flavor line - see enemy_data.gd's
# own charge_indicator_status doc (a .tres resource has no comment syntax
# of its own to carry this note) for why that specific string isn't final
# wording.

@export var badge_label_override: String = ""
# "" (every status today except braced.tres) means the badge shows str(
# active.magnitude) as it always has - same "empty/zero means unaffected"
# idiom tooltip_text/badge_diameter_override_px above already use. First
# use: Braced (2026-09-07, status-badge-contrast pass) - its own raw
# magnitude (-50, a MULTIPLY percentage - see modifier_operation's own
# doc) read as ambiguous out of context ("-50" what: HP, damage, percent?
# see this pass's own report). Read by StatusBadge.set_status() in place
# of str(active.magnitude) whenever non-empty - a per-STATUS opt-in, not
# a generated-from-magnitude formatting rule, so this affects Braced's
# own badge only and leaves every other status's numeral exactly as it
# was (this pass's own brief: "do not restyle other statuses' labels").

@export var badge_glyph_color_override: Color = Color(0, 0, 0, 0)
# Alpha 0 (every status today except braced.tres) means the badge's
# numeral stays StatusBadge.value_color, its own shared default - same
# "alpha 0 means unset" sentinel condition_frame_style's own bg_color
# already uses elsewhere in this project (border-only, never a fill).
# First use: Braced (2026-09-07, status-badge-contrast pass), paired
# with this same status's own icon_color going dark for contrast (see
# that field's own doc) - a pale glyph is only needed once the badge
# BEHIND it is dark; every other status keeps StatusBadge's own shared
# white, untouched.

@export var badge_border_color_override: Color = Color(0, 0, 0, 0)
# Alpha 0 (every status today except braced.tres) means the badge's
# border stays StatusBadge.badge_border_color, its own shared default -
# same sentinel shape badge_glyph_color_override above uses. First use:
# Braced (2026-09-07, rendered-luminance follow-up) - StatusBadge's own
# corner_radius is always exactly half its diameter (a full circle
# inscribed in a square Control, see that script's own _ready()), so
# roughly 21.5% of the badge's own bounding box is genuinely transparent
# by construction (the corners outside the circle), and the shared
# border ring (badge_border_color, luma ~0.42) covers a further 20-31%
# of it depending on diameter - together enough to explain a live-
# measured 0.46 against an intended 0.20 fill even with NO modulate or
# alpha involved anywhere (verified: even a pure-white backdrop behind
# the transparent corners only accounts for up to ~0.44 at this badge's
# size - see this pass's own report for the full math). The transparent
# corners can't be closed without changing corner_radius (a shape
# change, not made here), but the border ring CAN be neutralized - set
# to closely match icon_color below so the visible disc reads as one
# uniform dark mark instead of a dark fill inside a distinctly lighter
# ring, closing the one gap a bg_color choice alone can actually fix.
