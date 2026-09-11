extends Node2D
# This script runs the whole battle screen: it owns this battle's draw
# pile, hand, and discard pile (copied fresh from RunState.deck each
# fight - see _start_battle()), and reacts when a card in hand gets
# clicked.

enum BossChargePhase { NORMAL, WINDOW }
# A Charge-boss's own cycle (see enemy_data.gd's Charge section and
# EnemyCombatant.charge_phase below) - NORMAL (ordinary attacks, and the
# only phase a non-Charge enemy's combatant ever sits in) and WINDOW (the
# multi-turn charge itself - the boss keeps attacking, at charge_attack_
# value rather than a baseline attack, while player damage accumulates).
# No separate TELEGRAPH/SWING phase any more (2026-08-29 rework - REMOVES
# the old wind-up-then-forced-full-swing preamble this used to open with):
# the window's own attacks now ARE the telegraph, landing every turn
# alongside the accumulating-damage readout, rather than a single hit
# previewed one turn in advance. No separate BUFFED phase either - a
# resolved Charge's buff is tracked entirely by whether EnemyData.charge_
# buff_status is currently present in the combatant's own `statuses` (see
# _advance_boss_charge()), not by a third enum value, since "is buffed"
# already has a real, generically-ticking source of truth in the status
# scaffold - a parallel phase flag would just be a second place that same
# fact could go stale or disagree.

# One living (or recently-living) enemy's BATTLE-owned state - the same
# "Battle owns the numbers, Enemy just displays them" split the old
# scalar enemy_hp/enemy_max_hp/enemy_block/current_intent_index vars
# already followed, just per-enemy now instead of assuming exactly one.
# An inner class rather than a new file: this is Battle's own internal
# bookkeeping, not a general-purpose reusable piece the way WeightedRandom/
# EnemyPool/VisualBounds are.
class EnemyCombatant:
	var data: EnemyData
	var instance: Enemy
	var max_hp: int = 0
	var hp: int = 0
	var block: int = 0
	var current_intent_index: int = 0
	var is_defeated: bool = false
	var pain_turn_used: bool = false
	# Set true the first time this combatant's HP crosses data.pain_turn_
	# hp_threshold (see _check_pain_turn_trigger()) - guards the "exactly
	# once per fight" rule, since nothing else about a pain turn (not
	# current_intent_index, not turn_number) changes in a way that would
	# otherwise prevent it firing again on a later threshold crossing (an
	# enemy healed back up and dropped below 50% a second time, say).
	# Wardling/pain-turn-specific ONLY - unlike intent_interrupted_pending
	# below, this is NOT shared with a chain-payoff stun (see card_effect.
	# gd's STUN): a Guillotine stun has no "once per fight" limit of its
	# own, and reusing this same flag for it would wrongly couple the two
	# unrelated mechanics (stunning via a card could block, or be blocked
	# by, the Wardling's own real pain turn).
	var intent_interrupted_pending: bool = false
	# True for the stretch between "an interrupt was triggered" and "this
	# combatant's NEXT _resolve_enemy_intent() call has consumed it" - set
	# by EITHER _check_pain_turn_trigger() (the Wardling's own HP-
	# threshold pain turn) or _apply_intent_interrupt() directly (a chain-
	# payoff stun - see card_effect.gd's STUN), read (and cleared) by
	# _resolve_enemy_intent(), which is what actually overrides that one
	# resolution. Named generically (2026-08-23) - originally pain_turn_
	# pending, Wardling-only until a second, unrelated trigger needed the
	# exact same "cancel this turn's intent" behavior; see _apply_intent_
	# interrupt()'s own note for why the two triggers share this flag
	# while pain_turn_used above deliberately stays un-shared.
	var debris_spawn_used: bool = false
	# Same one-shot shape as pain_turn_used above, for EnemyData.debris_
	# spawn_enemy (see its own note) - guards "once per fight maximum"
	# for the Beachwrack's Knocks Something Loose, the same way pain_
	# turn_used guards the Wardling's pain turn.
	var statuses: Array[ActiveStatus] = []
	# See status_effect_data.gd/active_status.gd - this enemy's own active
	# statuses, entirely independent of the player's (see player_statuses
	# below) or any other enemy's, same "per-combatant mutable state"
	# reasoning every other field on this class already follows.
	var growth_stage: int = 0
	# The Mushroom's own runtime progress (see enemy_data.gd's growth_
	# stage_track_length doc) - deliberately its OWN field, not reusing
	# current_intent_index above: HP and stage track are independent by
	# requirement (see battle.gd's _advance_growth_stage()), and a grower
	# never advances current_intent_index at all (its own `intents` stays
	# empty), so the two could never safely share one field even if it
	# were tempting to. Initialized from data.growth_start_stage at spawn
	# (see _spawn_enemies()), then advances by exactly 1 per own turn,
	# unconditionally.

	# --- Charge (2026-08-29, BOSS_01 pass - see enemy_data.gd's own
	# Charge section for the static config these fields track live state
	# against) - all five default to harmless no-op values for every
	# enemy that isn't a Charge-boss, same "zero/empty means unaffected"
	# shape growth_stage above and pain_turn_used/debris_spawn_used
	# already follow. Advanced by battle.gd's own _advance_boss_charge(),
	# called INSTEAD of _advance_enemy_intent() when EnemyData.charge_
	# window_turns > 0 (see _resolve_enemy_intent()'s own call site).
	var charge_phase: BossChargePhase = BossChargePhase.NORMAL
	var charge_normal_turns_elapsed: int = 0
	# Counts NORMAL-phase turns where the buff (if any) is NOT currently
	# active toward triggering the next WINDOW (see EnemyData.turns_
	# before_first_telegraph) - deliberately does not advance AT ALL while
	# charge_buff_status is present in `statuses`, which is the entire
	# mechanism that guarantees "a new window should not begin while the
	# buff is still active" (this feature's own brief) without a separate
	# overlap check anywhere else.
	var charge_window_turns_elapsed: int = 0
	var charge_window_damage: int = 0
	# Accumulated LANDED damage (post-block HP loss, matching RunLogger.
	# log_damage_dealt()'s own convention) during the current WINDOW -
	# incremented by _deal_damage_to_enemy()'s own gated hook, reset to 0
	# every time a fresh WINDOW phase begins.
	var charge_effective_threshold: int = 0
	# EnemyData.charge_damage_threshold, clamped against this combatant's
	# OWN hp at the moment the current WINDOW began (see _advance_boss_
	# charge()) - a late-fight Charge can't demand more damage to
	# interrupt than the boss actually has left, which would make
	# interrupting it strictly impossible without simply killing the boss
	# outright (at which point "interrupted" stops meaning anything - the
	# fight's already over). Recomputed fresh per window, not per fight,
	# so an EARLY window (boss at or near full HP) still uses the full
	# configured threshold.

# preload() loads a resource once, when the game starts, and hands you a
# reference to it — like a shortcut you can reuse instead of typing the
# full file path every time.
const CARD_SCENE := preload("res://card.tscn")
const ENEMY_SCENE := preload("res://enemy.tscn")

# The hand never holds more cards than this.
const MAX_HAND_SIZE := 10
# Passed to each hand card's set_scale_factor() (see card.gd) - hand
# cards render at 115% of design_size, everywhere else (deck viewer,
# reward screen) still sets its own scale independently.
const HAND_CARD_SCALE := 1.00
# card.tscn's design_size (247.5 x 345) times HAND_CARD_SCALE - what a
# hand card's actual custom_minimum_size becomes once scaled. CARD_WIDTH
# figures out how much horizontal room a full hand needs (_update_hand_
# spacing()); CARD_HEIGHT sizes HandContainer's own box (_ready()'s call
# to _apply_hand_container_height()) and, from that, where Continue can
# sit without overlapping it (see VICTORY_BUTTON_HAND_GAP_PX below). All
# derived, not hardcoded, so retuning HAND_CARD_SCALE alone keeps
# everything else in sync instead of quietly drifting from what the
# cards actually render at.
const CARD_WIDTH := 247.5 * HAND_CARD_SCALE
const CARD_HEIGHT := 345.0 * HAND_CARD_SCALE
# The normal gap between cards, in pixels. Also the starting value baked
# into HandContainer's "separation" setting in battle.tscn.
const DEFAULT_HAND_SEPARATION := 27

@export var hand_max_span_px: float = 1800.0
# Caps how wide the hand's resting fan is allowed to spread, independent
# of the window/viewport width - see _update_hand_spacing()'s available_
# width, which is min(viewport-derived width, this) rather than the
# viewport's own full width alone. HandContainer's alignment is CENTER
# (see battle.tscn), so a smaller cap pulls the fan in symmetrically
# from both edges into a band centered in the window, rather than the
# fan extending edge to edge.
#
# WIDENED BACK OUT (2026-08-25, center-slot pass) from an intervening
# 900 (2026-08-25, same day, earlier) - that value existed purely to
# stop a hovered right-side card from resting under EnemyZone's own box
# (see armed_card_center_y_px above for the fuller history), but at 900
# a 5+ card hand overlapped ITSELF too heavily instead - cramped,
# off-center-reading spacing, name/cost text harder to read at rest.
# Selected cards now solve the ORIGINAL overlap properly (armed_card_
# center_y_px - one fixed point regardless of slot, not a hand-width
# question at all), so the narrow cap was paying that cost for a
# problem it no longer needs to solve on its own. 1800 restores
# effectively the pre-cap behavior on the standard 1920-wide viewport
# (viewport_available_width there is ~1786, so this cap is a no-op
# there, same as having no cap at all) while still being A real,
# tunable ceiling this export exists to provide - not removed outright.
#
# NOT a full fix for a merely-HOVERED (not yet selected) right-side
# card - hover only ever lifts a card vertically (see hover_offset),
# never shifts it horizontally, so a wide-fanned hand's own rightmost
# resting card can still sit under EnemyZone while just hovered, same as
# before ANY of this work. Deliberately accepted for this pass, on the
# reasoning that the sustained, decision-relevant overlap (staring at a
# card while choosing whether to commit to it) only ever happens once
# armed, and that's the state this pass actually fixes.
#
# Once a hand is big enough to hit the tight-separation branch below,
# its resulting span converges to (approximately) this exact value
# regardless of hand size - the compression formula solves separation
# so total width lands at available_width - which is what makes this a
# single, reliable "how wide can the hand get" knob rather than
# something that has to be re-tuned per hand size. Smaller hands that
# already fit under this cap at DEFAULT_HAND_SEPARATION are untouched.

# --- Vertical composition rebalance (DECIDED - see DESIGN.md's Battle
# Layout) ---
#
# The hand used to sit fully on screen, always - shrinking the cards
# (HAND_CARD_SCALE) was the only lever for reclaiming vertical space,
# and it fought directly against readability. Instead, the hand now
# sits mostly BELOW the screen's bottom edge at rest, rising fully into
# view on hover - extending Card's own existing hover pop-out (see
# card.gd's hover_offset), not a second mechanism.
@export var hand_rest_visible_height_px: float = 237.0
# How much of a hand card's own height - from its TOP: the cost badge,
# the name banner, then the FULL art slot - stays visible above the
# screen's bottom edge when not hovered, with only the description
# below the fold.
#
# RETUNED TWICE during the hand-fan/arc work (2026-08-25) before landing
# here - both earlier values were wrong in ways worth recording so the
# next retune doesn't repeat them:
#
# 1. The original 238 assumed a perfectly horizontal card (~3px past the
#    art slot's own bottom edge). Rotation pivots each card around its
#    own CENTER, so a horizontal boundary doesn't stay horizontal once a
#    card tilts - it shifts by half_card_width * sin(angle) at the
#    card's left/right edges, in OPPOSITE directions on each side. 238
#    didn't budget for that at all.
# 2. The FIRST fix (raised to 252) only checked ONE side of that shift
#    (clearing the art slot) and never checked the OTHER side against
#    the description panel's own start - which, verified directly
#    against the real node positions, sits only 8px past the art slot's
#    bottom edge (235 -> 243 at the time). 252 was already 9px PAST the
#    description panel's top edge with ZERO rotation applied - every
#    card, every hand, all the time. A real regression, caught only once
#    the arc's own math forced a from-scratch re-derivation.
#
# The actual fix had two parts, not one number: card.gd's zone_
# separation between ArtSlot and DescriptionPanel was widened from 8px
# to 24px (see card.gd's art_description_gap_extra_px - funded entirely
# by shrinking NameBanner's own oversized padding, verified no card name
# wraps at the new height), which is what gave rotation enough real room
# in the first place; 237 is the fold value that actually fits inside
# the resulting margin, verified against art_slot's bottom (219, moved
# up when NameBanner shrank) and description_panel's top (243, unmoved)
# simultaneously, across every hand size 1-10 - see _update_hand_fan()'s
# own arc math for why both sides have to be checked together, not
# separately, once vertical translation (arc_rise_px/arc_drop_px) is
# added on top of rotation.
#
# NOTE - the "no description visible at rest" goal turned out not to be
# a zero-tolerance constraint after all (see arc_rise_px's own doc): a
# few px of panel edge, or even a partial line on the rare long-
# description card, is accepted. 237 keeps ordinary cards fully clear of
# the description regardless; it does not by itself prevent the arc's
# own rise from exposing text on outlier cards - that risk is arc_rise_
# px's to own, not this value's.
#
# Raised again from an earlier 140px (name+badge+~top third of the art)
# once that read as too little to identify a card by its art alone -
# only possible now because combatant_top_offset_px moved UP rather
# than down this pass (see its own comment): the two exports draw on
# the SAME limited vertical budget between the combatants and the
# screen's bottom edge, and the previous pass's conflict (grounding the
# combatants ate the room this export needed) is exactly why it
# couldn't go this high before - moving the combatants up instead of
# further down freed real room here too, not just "more space above the
# combatants" on its own. Applied in
# _apply_hand_container_height(): HandContainer's own box (which every
# hand Card's clickable "slot" - see card.gd's own header comment - sits
# inside) moves so only this many pixels of it show above the fold,
# while each hand card's own hover_offset (see below) is set large
# enough to cancel that sink and bring the card fully back into view.
# The card's underlying REST state (visual.position = Vector2.ZERO)
# never changes - it's the SLOT itself that's positioned mostly
# off-screen, which is what makes hovering the visible sliver (the only
# part the mouse can physically reach) still register as hovering the
# whole card, even though most of its own rect technically extends
# below the screen.

@export var hover_rise_extra_px: float = 50.0
# How much further a hovered hand card rises past "fully back on
# screen" - matches Card's own default hover_offset magnitude (50px),
# preserved here so a risen hand card still pops up with the same
# familiar amount of extra lift on top of un-sinking, not just barely
# clearing the fold.
#
# No armed_extra_lift_px alongside this any more (REMOVED 2026-08-25,
# center-slot pass) - armed no longer means "rise further past hover
# within the hand slot," it means "fly to armed_card_center_y_px below,"
# a fixed screen point that has nothing to do with hover_rise_extra_px's
# own budget. See card.gd's set_armed() for the mechanism.
@export var hand_hover_duration_sec: float = 0.18
# Hand cards now travel much further on hover (see hand_rest_visible_
# height_px) than Card's own default hover_duration (0.1s) was tuned
# for - a touch longer keeps the rise reading as a deliberate lift
# rather than an unnaturally fast snap, while keeping the exact same
# easing curve (TRANS_SINE/EASE_OUT) Card's hover tween already uses -
# a magnitude tweak, not a new animation.

@export_group("Draw Sounds")
# card_draw_single plays on every draw of every battle, timed to each
# card's own arrival (see _play_draw_sfx() and _reveal_drawn_card() below)
# - card_draw_hand (the turn-start composite) is RETIRED from every call
# site now that turn-start cards arrive one at a time too (see the Draw
# Arrival Animation group below), but its own AudioManager.SFX_FILES/
# VOLUME_TRIM_DB entries are left registered, unused, rather than deleted
# - a future non-animated draw path could still want it. Volume trim lives
# in AudioManager (the one place every OTHER sound's loudness lives too -
# see its own VOLUME_TRIM_DB); pitch RANGE lives here instead, exported
# locally rather than added to AudioManager itself, since pitch variance
# is a gameplay-timing concern only these two draw sounds need today, not
# a general AudioManager feature every sound should carry.
@export var draw_sfx_pitch_min: float = 0.95
@export var draw_sfx_pitch_max: float = 1.05
# deck_reshuffle (see AudioManager.SFX_FILES) gets its OWN pitch-range
# export pair, not a reuse of draw_sfx_pitch_min/max above - same "each
# sound independently tunable by ear" convention every other trim/range in
# this project already follows (card_draw_hand and card_draw_single have
# separate VOLUME_TRIM_DB entries despite near-identical reasoning), even
# though the default happens to start out identical to the draw range.
@export var shuffle_sfx_pitch_min: float = 0.95
@export var shuffle_sfx_pitch_max: float = 1.05

@export_group("Draw Arrival Animation")
# Per-card timing for the turn-start/mid-turn deal - see _draw_cards()'s
# own doc for the full sequence these two drive. Exported so they can be
# tuned by feel without touching code, same reason every other hand-timed
# export here (hand_hover_duration_sec above, prompt_fade_in_sec-style
# exports elsewhere in this project) is exported rather than a local
# constant. RETUNED (2026-09-03) - the original 0.06/0.15 pairing (a
# 5-card hand settled in ~0.25s) read as a jarring flicker rather than a
# legible deal; slowed to land a 5-card hand at ~0.45-0.55s instead, per
# this pass's own brief.
@export var draw_arrival_stagger_sec: float = 0.07
@export var draw_arrival_travel_sec: float = 0.16

# --- Hand fan (2026-08-25) - rotation; see the Arc section below for
# the vertical-translation half added in the same day's second pass ---
#
# HandContainer's own HBoxContainer layout is completely untouched - no
# vertical offset, no per-card Y shift lives here. Each card instead
# gets a small ROTATION, applied to card.gd's own Visual node (see
# Card.set_fan_transform()) the exact same way hover/armed already
# animate Visual's position/scale - a transform on top of the existing
# layout, not a second positioning system.
@export_range(0.0, 20.0, 0.5) var fan_max_tilt_deg: float = 5.0
# The leftmost card tilts -fan_max_tilt_deg, the rightmost +fan_max_
# tilt_deg, everything between interpolates linearly, center card(s)
# landing near 0 (near-vertical) - see _update_hand_fan(). Conservative
# default per this pass's own brief ("subtle... a held hand, not a
# dramatic spread"). This is the value actually reached only at
# fan_reference_hand_size or fewer cards - see that export below for how
# a bigger hand tightens it.
@export var fan_reference_hand_size: int = 5
# The hand size fan_max_tilt_deg's own full angle is tuned for - matches
# _draw_cards(5)'s normal turn draw, the hand size this was actually
# eyeballed against. Only hands LARGER than this shrink the effective
# max, proportionally (fan_reference_hand_size / current hand size,
# floored at 1.0), so a full 10-card hand fans at roughly half the angle
# instead of spreading the same ±5° across twice as many, tighter-
# packed cards. See _update_hand_fan()'s own math. Hands SMALLER than
# this do NOT automatically get the full angle any more - see fan_full_
# amplitude_hand_size below for the small-hand side of this.
@export var fan_full_amplitude_hand_size: int = 5
# CORRECTED (2026-08-25, third fan pass) - the previous two passes only
# ever shrank the fan for hands LARGER than fan_reference_hand_size;
# small hands always got the FULL angle and FULL arc, which read as
# actively wrong rather than just "not fanned enough" - two cards each
# tilted a full 5° with no curve between them to justify it reads as two
# crooked cards, not the start of a hand. There's nothing for a fan to
# describe until there's enough cards to form a curve; a dome or a tilt
# on a 1-2 card hand is a decoration with no shape to decorate.
#
# fan_full_amplitude_hand_size is the hand size at which BOTH fan_max_
# tilt_deg and the arc (arc_rise_px/arc_drop_px) reach their full
# configured value - ramped up from near-zero at 1-2 cards via smooth-
# step (see _update_hand_fan()'s ramp_up_factor), not a hard cutoff, so
# there's no visible snap as a card is drawn into a growing hand. Held
# at full from this size up to fan_reference_hand_size, where the
# existing large-hand shrink above takes back over - the two are
# separate tunables on purpose (one shapes the small end, one the large
# end) even though they default to the same value.

# --- Arc (2026-08-25, second fan pass) - vertical translation on top of
# the rotation above, not a replacement for it ---
#
# The first fan pass was rotation-only ("flat tilt") - cards stayed on
# one horizontal line and just tilted. That reads as inverted: rotating
# a rectangle around its own CENTER makes the MORE-tilted (outer) cards'
# top corners rise HIGHER than the barely-tilted center card's, the
# opposite of a real held hand's silhouette (center raised, edges
# lowered). This section adds the actual height difference; fan_max_
# tilt_deg above is untouched - cards still rotate exactly as before,
# this only shifts them vertically too.
#
# DIRECTION - VERIFIED, and once gotten backwards mid-pass, worth
# recording precisely: raising a card (moving visual.position.y
# negative) shifts the fold's EFFECTIVE local-y UP the card - the fixed
# screen cutoff now falls further DOWN into the card's own content,
# revealing MORE, including - if pushed far enough - the description
# panel. Lowering a card does the reverse: less of it shows, risking a
# crop into the art slot instead. So raising is the EXPOSURE-risk
# direction and lowering is the ART-crop-risk direction - confirmed both
# by re-deriving the geometry independent of any specific zone size, and
# by direct engine measurement (a raised center card's own "showing"
# boundary moved from local-y 252 to ~280 at a 28px rise, exactly
# matching the derivation). This is NOT a case of "pick whichever
# direction the current zone gap happens to favor" - the mapping is
# fixed by which side of the fold each zone sits on, unrelated to how
# wide the gap between them is.
#
# BUDGET, given that: card_face's own ArtSlot/DescriptionPanel gap is
# 24px (see card.gd's art_description_gap_extra_px), and fan_max_tilt_
# deg's own 5° rotation already spends ~10.8px of it on ONE edge card
# simultaneously on BOTH sides (its own showing side AND its own cutting
# side) - verified by grid search (not hand-solved algebra, which missed
# this the first time) that safely splitting what's left between rise
# and drop tops out around 5-6px TOTAL with a real buffer on both sides,
# nowhere near "substantial" on its own.
#
# CONSTRAINT RELAXED (2026-08-25, same day, later): "no description
# visible at rest" was being treated as zero-tolerance, which is what
# produced that ~5-6px ceiling. It isn't zero-tolerance - a few px of
# panel edge, or even a partial line on an unusually long description,
# is acceptable; a full LEGIBLE line at rest is the actual failure.
# Verified against every shipped card's real text position (not just
# panel edges): ordinary cards' text starts at local-y 266+ and never
# gets close regardless of arc_rise_px below; the one outlier is
# Retaliation (its description is long enough to grow DescriptionPanel
# itself, starting its own text at local-y 240 instead of the usual
# 266+). At this value, a center-raised Retaliation would show ~21px of
# its own first line (out of the whole hand, only reachable if that
# specific card lands near hand-center) - a real, deliberately-accepted
# tradeoff, not an oversight. Dial this down (16 -> ~13px shown, 10 ->
# ~8px, both verified) if that reads as too legible once seen live;
# every other shipped card is completely unaffected at any of these
# values.
@export var arc_rise_px: float = 24.0
# How far the CENTER of the hand rises above the flat line - see this
# whole section's own doc for the direction/budget/relaxed-constraint
# history behind this specific number.
@export var arc_drop_px: float = 6.0
# How far the EDGES of the hand drop below the flat line - the safe
# direction (risks cropping ArtSlot, not exposing DescriptionPanel).
# Kept modest rather than maxed out: ArtSlot is usually empty today (no
# card has real art yet - see card.gd's own "future art hook" note), so
# there's little for a bigger drop to visibly damage right now, but a
# smaller value leaves headroom for whatever a future art pass adds
# without this needing a second retune.

# --- Armed/selected card center slot (2026-08-25, center-slot pass) ---
#
# Where a card animates to and holds while armed, waiting for a target
# click (see card.gd's set_armed(), _begin_targeting() below) - ONE
# fixed point every hand card flies to regardless of which slot it came
# from, replacing a per-slot "lift straight up from wherever you are"
# pose that put a right-side card directly over the enemy sprite/HP bar/
# flavor text while a left-side one cleared them entirely. Card.gd owns
# HOW a card gets there (the top_level flight - see its own doc); this
# is only WHERE.
#
# X is deliberately NOT its own export - always dead-center of the
# current viewport (_armed_card_center_position() below), computed
# fresh rather than stored, so "center-horizontal" (this feature's own
# hard requirement, not just a starting guess) can't drift off-center
# from a future tuning pass touching the wrong number. Y is the one
# genuinely open question, hence the only exported value here.
@export var armed_card_center_y_px: float = 747.0
# LOWERED (2026-08-25, live-tuning pass) from an initial 620, which read
# as raising the card almost to screen-center - too far up. 747 is
# halfway between that 620 and a resting hand card's own center Y
# (873.75 = HandContainer's slot top, 593.25, plus its below-fold sink,
# 108px, plus half CARD_HEIGHT, 172.5px - see hand_rest_visible_height_
# px's own geometry) - i.e. this cuts the ORIGINAL rise-above-the-hand
# in half rather than picking a new number from scratch.
#
# Still not a verified-safe value - EnemyZone's own box top sits at
# combatant_top_offset_px (264px), and nothing here confirms where a
# real enemy's own sprite/HP bar/intent/flavor text actually sit within
# that (taller) box, only where the box's edges are - that needs eyes on
# a real single-enemy fight, not more math (see this feature's own
# commit / DESIGN.md note). Dial this down (toward the hand) if the
# armed card still reads as too close to the enemy, or
# up (toward the enemy) if it reads as sitting in the hand itself.
@export var combatant_top_offset_px: float = 329.0
# Where PlayerBattleVisual's/EnemyZone's own box TOP sits (screen Y,
# both top-anchored) - both move from this SAME value (see _apply_
# combatant_vertical_position()), preserving each box's own baked
# HEIGHT (460/498px respectively) so nothing inside either one needs to
# change, just where the whole box sits - HP bars, block badges, intent
# icons, enemy name labels, AND floating damage numbers (enemy.gd's
# get_floating_number_anchor(), read from visual_container's own LOCAL
# position same as everything else here, even though the FloatingNumber
# itself ends up parented to the shared UI CanvasLayer - see flash_
# damage()'s own note) all move up automatically with it, no separate
# fix needed for any of them.
#
# Raised (moved UP the screen, -216px = 20% of the 1080-tall viewport,
# from the previous pass's 480) to sit higher on the backdrop's concrete
# apron with more visual room between the combatants and the hand below
# them - a deliberate framing choice this time, not a "stand on the
# ground" correction the way the previous pass's move was. This also
# happens to be what let hand_rest_visible_height_px grow enough to show
# full card art (see its own comment) without reopening the previous
# pass's collision with the HP bars - moving the combatants UP rather
# than pushing them further DOWN freed the same shared vertical budget
# from the other direction instead of consuming more of it.

@export var enemy_zone_anchor_x: float = 0.68
# Where EnemyZone's own box CENTERS horizontally, as a fraction of
# viewport width (battle.tscn's own anchor_left/anchor_right, both
# always equal - EnemyZone is a fixed-width box pinned to one point, not
# stretched). Exported here (2026-08-26, enemy-positioning pass) rather
# than left as a baked .tscn value, since this is exactly the kind of
# number that needed retuning more than once already (0.69 -> 0.62 ->
# 0.68, see below) and will likely need it again once seen live.
#
# RAISED (2026-08-26, second pass) from 0.62 back toward the right -
# 0.62 was chosen specifically to clear the OLD EndTurnButton, which sat
# at a fixed mid-right band (y ~542-588px) squarely in the enemy row's
# own vertical space. EndTurnButton has since moved to a real bottom-
# right corner (_apply_end_turn_button_layout() - y ~785-827px at
# 1920x1080, well below where a real creature's bottom edge actually
# sits, ~685px per that pass's own live-measured verification) - the
# collision 0.62 was avoiding no longer exists, and pulling the group
# left to dodge it was leaving the whole right half of the field empty
# instead. The binding constraints are different now (see below) and
# both looser than the old EndTurnButton-collision one was.
#
# EnemyZone centers on this ONE fixed point regardless of enemy count
# (alignment = CENTER in battle.tscn), so whichever count has the
# WIDEST total content (cluster_width_px * scale factor, summed with
# enemy_separation_default/three_plus's own gaps - see _apply_enemy_
# zone_separation()) determines BOTH edges at once. At 1920x1080, with
# enemy_separation_default = 40.0 and enemy_separation_three_plus =
# -20.0 (see their own doc for why those also changed this pass), 3
# enemies is the widest case in both directions:
#   1: 500px wide  -> span [1055.6, 1555.6]
#   2: 540px wide  -> span [1035.6, 1575.6]
#   3: 635px wide  -> span [988.1,  1623.1]
# Right edge (3 enemies, 1623.1px) has clearance before DiscardLabel's
# own left edge - respected as the hard boundary even though real
# creatures won't reach Discard's own y-band. DiscardLabel's left edge
# moved 1687px -> 1730px (2026-08-30, DiscardLabel-narrowing pass - see
# its own node comment in battle.tscn, and the row-capacity re-check that
# pass's own report ran) - narrowed to its real measured text width
# instead of a flat 200px box, reclaiming some of the unused margin
# toward the viewport edge. Left edge (988.1px) has 268.9px of clearance
# before PlayerBattleVisual's own right edge (719.2px) - far looser,
# untouched by that pass (PlayerBattleVisual was explicitly out of scope
# for it).
#
# The specific px figures in this block predate the dynamic-cluster-
# width pass (2026-08-30) - cluster_width_px is no longer a flat 500px
# every enemy shares (see Enemy._apply_dynamic_cluster_width()), so the
# "1: 500px / 2: 540px / 3: 635px" table above no longer reflects real
# per-enemy sizing. Left as historical reasoning for why enemy_zone_
# anchor_x landed at 0.68, not a live-accurate capacity figure - see
# battle.gd's own row-capacity investigations for current numbers.
#
# Still not a verified-safe value in the same sense combatant_top_
# offset_px's own doc flags - measured against each Enemy's ABSTRACT
# cluster_width_px box, not any real enemy's actual rendered silhouette
# bounds, which the Beachwrack investigation (see enemy_data.gd's own
# intent_horizontal_offset_px doc) already showed can extend meaningfully
# past that box for an asymmetric or oversized creature - the 63.9px
# right-side margin is real but not huge. Retune down (or compress
# separation further) if a real 3-enemy encounter's widest creature ever
# visually reaches Discard/EndTurn despite it.

# Energy is a resource state, so — like hand/draw_pile/discard_pile above
# — it lives here in Battle, not on Card or CardData. Card only ever
# reports a cost (CardData.energy_cost); Battle is the only thing that
# knows what "having enough energy" means and what happens when you
# don't. Keeping it centralized like this means that if a future
# character uses a different resource system (rage, cooldowns, etc. —
# see DESIGN.md), swapping it out is a change contained to this script.
var max_energy: int = 3
var energy: int = 3

# Player HP is RUN-level state - it has to survive past this battle
# ending (see item 2 in DESIGN.md's run structure work), so it lives in
# the RunState autoload instead of here. See run_state.gd for the fuller
# explanation of that split. Block resets every battle, so it stays
# local, right alongside energy above.
var player_block: int = 0

# Absorb: a second, independent damage-reduction pool (2026-09-05,
# Forbearance pass) - granted by CardEffect.EffectType.ABSORB (see
# resources/cards/classes/wanderer/forbearance.tres), subtracted in
# _resolve_damage() AFTER block, so a hit spends block first, then
# absorb, then HP - same ordering _enemy_attack_player() already
# applies for that combined subtraction. UNLIKE player_block, this
# does NOT reset every turn - it persists for the WHOLE fight until
# spent (reset only in _start_battle() below, never in
# _start_player_turn()), which is the entire point of the card's own
# "Absorb persists until spent" text. Also unlike player_block,
# gaining this is NEVER gated by overextended.tres's own
# NO_BLOCK_STATUS check (see _gain_absorb() below) - Full Weight's
# "no block next turn" debuff blocks BLOCK specifically, not this
# separate pool. Damage absorbed here never opens Rally, same as
# blocked damage - see _enemy_attack_player()'s own call order.
var absorb_pool: int = 0

# Toll: what the Sunken Works extracts from you, per combat (DESIGN.md's
# Toll note). Accrues by the amount of HP actually LOST, from ANY
# source, in ONE place - see _set_player_hp() below, the single point
# every player-HP-losing (and -gaining) call site routes through.
# Deliberately NOT a status effect (no StatusEffectData, no ActiveStatus,
# no StatusBadge) - it's its own concept with its own display (see
# toll_display.gd). Same "fight-scoped, lives right alongside player_
# block" reasoning as that field above - never capped, never decreases,
# reset once per fresh battle instance (_start_battle()), NOT per turn
# (contrast player_block, which _start_player_turn() clears each turn).
var toll: int = 0

# --- Damage-taken tracking (Held Position, 2026-08-29) ---
#
# Backs the "if you took no damage last turn" condition - see CardEffect.
# EffectType.UNDAMAGED_BLOCK's own doc and _took_no_damage_last_turn()
# below. Two vars, not one, for the same reason RunLogger's own per-turn
# accumulator needs a snapshot: "last turn" has to stay a FIXED answer for
# the whole of the player's current turn (read possibly several times, by
# several different Held Position copies in hand), while "this turn" is
# still actively accumulating as more damage lands - collapsing them into
# one var would mean the answer changes mid-turn if the player takes a hit
# from a card of their own after already checking it once.
var _took_damage_this_turn: bool = false
var _took_damage_last_turn: bool = false
# false at battle start (see _start_battle()) - turn 1 has no "last turn"
# yet, so the condition defaults to MET, the same generous "nothing to
# report yet reads as the safe case" instinct empty/zero already means
# everywhere else in this file.

# --- Rally (the Wanderer's innate passive - see CharacterData.rally_
# recovery_percent's own doc for the recovery-rate half) ---
#
# The recoverable pool: fills from UNBLOCKED damage the player takes
# from an ENEMY ATTACK specifically (see _enemy_attack_player() below,
# the same "not fully blocked" damage_to_hp threshold Toll/debris-spawn/
# Retaliation all already use) - never from self-inflicted damage
# (Blood Tithe, a future Toll generator - see _deal_self_damage(),
# which never touches this var) or a status DoT tick (_deal_status_
# tick_damage_to_player(), same exclusion). Drained by _deal_damage_to_
# enemy() whenever the player deals damage, capped at whatever's
# actually in here right now - this is what makes "no path heals the
# Wanderer without a recoverable pool backing it" true structurally,
# not just by convention: an empty pool caps recovery at 0 regardless
# of rally_recovery_percent. Fight-scoped and reset in _start_battle(),
# same as toll/player_block above, but ALSO cleared at the end of every
# player turn (_on_end_turn_button_pressed()) and on battle end (_close_
# out_battle()) - unlike Toll, this is explicitly NOT persistent: it
# expires at the end of the Wanderer's next turn after whatever filled
# it, not "for the rest of the fight."
var rally_pool: int = 0

# --- Trinket: TOLL_THRESHOLD_FREE_CARD (see trinket_modifier.gd) ---
#
# Per-combat state, same shape/lifetime as rally_pool above - lives on
# Battle, not RunState or CharacterData (an equipped trinket's own
# CONFIG, like an equipped weapon's, is static per-run data; the fact
# that IT fired this fight is fight-scoped state, the same split
# CharacterData.rally_recovery_percent/battle.gd's own rally_pool
# already draw). Two separate bools, not one: _trinket_free_card_armed
# is "the next card played is free," consumed the instant a card is
# played (see _play_card()); _trinket_free_card_fired is "already
# armed once this combat," which OUTLIVES that consumption - without a
# separate flag, Toll dropping back below the threshold and re-crossing
# it later in the same fight would arm a second free card, which the
# effect's own brief explicitly rules out ("fires once per combat, on
# first upward crossing only").
var _trinket_free_card_armed: bool = false
var _trinket_free_card_fired: bool = false

# One recovery per discrete damage EVENT (2026-08-26, rally-recovery-
# rework), computed from the largest single hit within that event, not
# summed across every hit - a RallyWindow is the accumulator for one
# such event. "Event" boundaries: one per card played (_apply_card_
# effects()), one per chain payoff (_trigger_chain_payoff() - a
# structurally separate hit, see that function's own note), one per
# Retaliation proc (_check_retaliation_trigger()), one ad hoc for the
# dev-damage button (not player-facing, no event of its own to join).
# Weapon reflect (_reflect_self_damage()) is the one exception: it joins
# whatever window its OWN triggering SELF_DAMAGE effect belongs to,
# rather than opening its own, since it reads as damage the CARD
# produced, not a separate event.
#
# Held as an OBJECT reference (RefCounted), not a transient "is a window
# currently open" flag, specifically because weapon reflect's own hit
# lands after an internal delay (weapon_reflect_delay_sec) - by the time
# it fires, _apply_card_effects() has already returned and a DIFFERENT
# card's window could plausibly be open by then. A flag would risk
# crediting that late hit to the wrong (newer) window; an explicit
# reference, captured once and threaded through _resolve_card_effect()/
# _reflect_self_damage() as a parameter, always points at the SAME
# window regardless of how much later it actually contributes - no
# explicit "close" is needed either, a window simply stops mattering
# once nothing holds a reference to it any more.
class RallyWindow:
	var max_hit: int = 0
	var paid: int = 0

# Called once per hit that should count toward SOME rally window - see
# RallyWindow's own doc for why this takes an object reference rather
# than reading ambient state. window == null means this hit belongs to
# no event at all (shouldn't happen at a real call site, but makes this
# a safe no-op rather than a crash if one's ever missed). Only pays out
# the DELTA when max_hit actually increases, never re-pays the whole
# target on every hit - that's what makes "50% of the largest hit, not
# the sum" hold regardless of how many hits land in this window, in
# whatever order, and what naturally reproduces today's exact single-hit
# math when a window only ever sees one hit (paid starts at 0, target
# equals the old inline formula exactly). Still capped at rally_pool at
# the moment of EACH payout (not reserved up front) - the existing
# cross-window pool-starvation quirk is intentional and unchanged (see
# rally_pool's own doc); only summing WITHIN a window is what's fixed.
func _contribute_to_rally_window(window: RallyWindow, damage_to_hp: int) -> void:
	if window == null or damage_to_hp <= window.max_hit:
		return
	window.max_hit = damage_to_hp
	var target_total: int = window.max_hit * RunState.current_class.rally_recovery_percent / 100
	var additional: int = mini(target_total - window.paid, rally_pool)
	if additional > 0:
		rally_pool -= additional
		window.paid += additional
		_heal_player(additional, false, true)

# --- Escape distance (DECIDED - see DESIGN.md's Bestiary: Outbound) ---
#
# Fight-scoped, same "lives on battle.gd, not on EnemyCombatant/EnemyData"
# reasoning as toll above - distance is a property of THIS encounter, not
# a stat every enemy carries (see EnemyData.escape_distance_ramp/_max's
# own note for why the CONFIG lives there instead). _escaping_
# enemy is found once, at spawn time (see _spawn_enemies()) - null for
# every fight that doesn't include an enemy with escape_distance_max set
# (today: every fight except one against Outbound), in which case _escape_
# falloff_scalar() and _tick_escape_distance() below are both permanent
# no-ops and nothing about this section ever does anything. Both reset in
# _start_battle(), same as player_block/toll.
var _escaping_enemy: EnemyCombatant = null
var _escape_distance: float = 0.0

# --- Chaining (MINIMUM VIABLE PROTOTYPE - see card_data.gd's own note)
# ---
#
# True from the moment an OPENER-role card is played until either a
# CLOSER-role card consumes it or the turn ends unused - a single flag,
# not a counter or a timer, because at most one empowerment can ever be
# "in flight": playing a second Opener while already empowered has
# nothing further to set (chain_empowered is already true), so it's
# WASTED rather than refreshed. This is a deliberate choice, not an
# oversight - there's no duration to refresh in the first place (the
# empowerment already lasts until end of turn or consumption, whichever
# comes first, and playing a second Opener can't extend either of
# those), so "refresh" would be a distinction with no actual effect to
# express. Resets every battle, same fight-scoped lifetime as player_
# block above. See _update_chain_state()/_refresh_chain_indicators()
# for how this gets set/cleared and reflected on every CLOSER card
# currently in hand, and _discard_entire_hand() for the end-of-turn
# expiry.
var chain_empowered: bool = false

const CHAIN_PAYOFF_DAMAGE := 8
# The chain's own hit, landing as a SEPARATE resolution right after a
# Closer's own (see _trigger_chain_payoff() below) - not a bonus folded
# into the Closer's value anymore (see card_data.gd's own chaining
# note for why: this is meant to read as a chain COMPLETING, not a card
# being buffed). Heavy Blow's own 12 is untouched; this adds 8 more on
# top of it as its own distinct hit, for the same 20-ish total-damage
# ballpark the previous +6-to-18 approach landed in, tuned up slightly
# now that the payoff carries its own full impact treatment (burst/
# shake/sound - see _deal_damage_to_enemy()) and needs to read as a
# satisfying hit in its own right, not a token addendum next to a
# bigger number that already landed.

@export var chain_payoff_delay_sec: float = 0.3
# The gap between the Closer's own hit landing and the chain payoff
# triggering - see _trigger_chain_payoff()'s own note for why this is
# a delay before the payoff even RESOLVES, not just before its visuals
# reveal. 0.3s (mid-range of a "0.2-0.4s, clearly two beats" target) -
# short enough the two hits still read as one sequence, long enough
# they don't blur into a single event.

@export var multi_hit_delay_sec: float = 0.15
# The gap between two consecutive hit-type effects on the SAME card (see
# _apply_card_effects()) - Guillotine's three DAMAGE entries, first real
# user. Meaningfully shorter than chain_payoff_delay_sec (0.3s) on
# purpose: these are three pieces of ONE strike landing in a flurry, not
# separate beats the way a chain payoff is its own distinct moment -
# same "distinct hit, not its own big beat" register weapon_reflect_
# delay_sec (0.15s) already established for a smaller, more incidental
# second hit.

@export var multi_hit_delay_extra_sec: Array[float] = [0.1, 0.3]
# Per-GAP additions on top of multi_hit_delay_sec above, indexed by
# which gap it is (index 0 = between hit 1 and hit 2, index 1 = between
# hit 2 and hit 3, ...) - out-of-range (a card with more consecutive
# hits than this array has entries for) just falls back to the plain
# base delay, same "empty means no extra effect" idiom as everywhere
# else. Added (2026-08-23) because Guillotine's third hit landed too
# fast at a flat, uniform gap - the accumulating pause reads as the
# strike gathering weight into its LAST hit, rather than three
# identical, evenly-spaced pieces. Global on battle.gd, not authored
# per-card, same shape multi_hit_delay_sec itself already has. Guillotine
# was reworked to a single hit (2026-08-26 - see DESIGN.md's own note),
# so no card exercises this today - left in place, unchanged, as general
# infrastructure for whichever future multi-hit card needs it next,
# rather than removed along with Guillotine's own multi-hit shape.

# The chain payoff's own CardEffect, built once in _ready() rather than
# as a const (Resources can't be constructed in a GDScript const
# initializer) - see _trigger_chain_payoff() for why routing it through
# the same _resolve_card_effect() every other effect uses, instead of
# calling _deal_damage_to_enemy() directly, is what lets a FUTURE chain
# payoff be something other than damage with zero new resolution code.
var _chain_payoff_effect: CardEffect

# --- Chain impact feedback (see _deal_damage_to_enemy()'s own note) ---
#
# The payoff has to be FELT, not just read off a bigger number - screen
# shake is the one channel of this that lives here rather than on Enemy
# (the flash/burst/hitstop/sound live on enemy.gd - see its own Chain
# Impact export group), since only Battle has a reference to the whole
# UI CanvasLayer a shake needs to move. Both tiers exist (not just an
# "empowered" one) so "stronger than a normal attack of the same
# magnitude" is an actual comparison the player can feel, not a made-up
# baseline - see _play_screen_shake()'s own note for why a CanvasLayer's
# own offset, not a Camera2D, is what moves here.
@export_group("Chain Impact")
@export var normal_hit_shake_px: float = 4.0
@export var normal_hit_shake_duration_sec: float = 0.12
@export var empowered_hit_shake_px: float = 14.0
@export var empowered_hit_shake_duration_sec: float = 0.22

# --- Weapon reflect feedback (The Creditor - see _reflect_self_
# damage()/_deal_damage_to_enemy()'s own notes) ---
#
# Deliberately lighter than the chain payoff's own treatment above: this
# is a smaller, more incidental effect (a side effect of paying a card's
# own cost), not a dedicated "moment" the way a completed chain is - so
# it gets its own floating-number look (FloatingNumber.Kind.
# DEAL_WEAPON_REFLECT - see floating_number.gd) and a layered sfx cue,
# riding the NORMAL screen-shake tier rather than a third shake tier of
# its own.
@export_group("Weapon Reflect Impact")
@export var weapon_reflect_delay_sec: float = 0.15
# Shorter than chain_payoff_delay_sec (0.3s) - long enough that this
# reads as a second, distinct hit rather than a number popping on top
# of the card's own damage number in the same frame, short enough that
# it doesn't ask to be felt as its own big beat the way a chain payoff
# does.

const BRACED_STATUS := preload("res://resources/statuses/braced.tres")
# Braced's own hardcoded identity (2026-09-05, Brace card pass) - needed
# ONLY to find and consume the status by resource identity (see _consume_
# next_hit_statuses() below); braced's actual halving effect needs no
# per-status code at all, since MODIFIER/MULTIPLY already resolves
# through the fully generic _apply_status_modifiers() every other
# incoming/outgoing damage modifier already uses. Same "one hardcoded
# reference so whatever consumes a marker knows which resource to look
# for" shape RETALIATION_PRIMED_STATUS just below already establishes,
# for the same reason: clears_on_trigger documents intent but branches on
# nothing by itself (see status_effect_data.gd's own doc) - something
# has to actively look for and remove this one.

const UNFLINCHING_STATUS := preload("res://resources/statuses/unflinching.tres")
# Unflinching's own hardcoded identity (2026-09-08, Unflinching card pass)
# - same reasoning BRACED_STATUS's own doc gives immediately above; its
# -100% halving-to-zero effect is the SAME generic MODIFIER/MULTIPLY path
# Braced uses, at a different magnitude, needing no effect-specific code
# either. Only exists here so _consume_next_hit_statuses() below has a
# resource identity to look for, same as BRACED_STATUS.

const NEXT_HIT_CONSUMED_STATUSES: Array[StatusEffectData] = [BRACED_STATUS, UNFLINCHING_STATUS]
# Statuses spent by the next enemy attack resolving at all, before block - distinct from Retaliation Primed, which is consumed post-damage by its own trigger.

const RETALIATION_PRIMED_STATUS := preload("res://resources/statuses/retaliation_primed.tres")
# The one hardcoded piece of Retaliation-specific knowledge battle.gd
# needs (see _check_retaliation_trigger() below) - unlike a MODIFIER or
# TICK status, which resolve through entirely generic machinery with no
# per-status code anywhere, an INFORMATIONAL marker status (see status_
# effect_data.gd's own Category doc) is BY DESIGN "checked for by some
# other system," which means whatever checks for it has to know which
# resource it's looking for. Placeholder numbers (5 Toll, 1.5x) live on
# the CardEffect/.tres instead of here - RETALIATION_DAMAGE_MULTIPLIER_
# PERCENT below is the one number that couldn't: it's read at the moment
# the status PROCS, which has no CardEffect in scope by then (the card
# that primed it already finished resolving, possibly turns ago).
const RETALIATION_DAMAGE_MULTIPLIER_PERCENT := 150

const NO_BLOCK_STATUS := preload("res://resources/statuses/overextended.tres")
# The one hardcoded piece of Full Weight-specific knowledge battle.gd
# needs (see _gain_player_block() below) - same "an INFORMATIONAL marker
# status is BY DESIGN checked for by some other system, which has to know
# which resource it's looking for" reasoning RETALIATION_PRIMED_STATUS's
# own comment above already gives. default_duration_turns = 2 on the
# resource itself (not a number here) is what makes this survive the
# ENTIRE turn after the one it's applied on: _start_player_turn() ticks
# once at the start of each of the player's own turns (see its own doc),
# so applying with 2 during turn N leaves 1 remaining at the start of
# turn N+1 (still active, not yet expired) and only reaches 0 - expiring
# immediately, before anything else in that turn runs - at the start of
# turn N+2. A duration of 1 would instead expire at the very start of
# turn N+1, before that turn's own actions ever ran, never actually
# blocking a single block-gain during it.

const SELFEATER_STATUS := preload("res://resources/statuses/selfeater_mark.tres")
# Selfeater's own permanent mark (2026-08-28, first STANCE card) - same
# "the one hardcoded piece of X-specific knowledge battle.gd needs"
# reasoning RETALIATION_PRIMED_STATUS/NO_BLOCK_STATUS above already give,
# for a different reason: this status's MODIFIER half (the +3 outgoing-
# damage bonus) resolves through entirely generic machinery with zero
# per-status code (see _apply_status_modifiers()) - but its OTHER two
# behaviors don't. The per-attack HP drain (not yet wired - see this
# card's own report-back on victory/defeat sequencing before it lands)
# and the stance visual tint (_update_selfeater_visual() below) both need
# to know SPECIFICALLY which status they're looking for and reading
# stack_count off of, the same way an INFORMATIONAL marker status already
# does for Retaliation/Full Weight.
const SELFEATER_TINT_COLOR := Color(0.42, 0.3, 0.55, 1)
# Desaturated violet - matches CARD_TYPE_ART_COLORS[CardData.CardType.
# STANCE] in card.gd (same family, so the card and its own battle-visual
# effect read as the same idea) but toned down, since a glow over the
# player's own silhouette needs to read as a status effect, not compete
# with the card face's own saturation. PLACEHOLDER - see _update_
# selfeater_visual()'s own doc: no real art/shader treatment exists yet.

var player_statuses: Array[ActiveStatus] = []
# See status_effect_data.gd/active_status.gd - resets to empty every
# battle, same lifetime as player_block above (a status is fight-scoped
# state, not RUN-scoped like player_hp).

# Every enemy currently in the fight, battle-owned state and all - see
# EnemyCombatant above. Order is spawn order; nothing about targeting or
# turn resolution depends on that order beyond "living enemies act in
# the order they were spawned in" (see _run_enemy_turn()).
var enemies: Array[EnemyCombatant] = []

# True once the battle has resolved, one of three ways (see _battle_
# outcome below for WHICH). Placeholder for the real win/lose flow a
# future map/run loop will bring - for now it just stops cards and End
# Turn from doing anything once the fight is over.
var battle_over: bool = false

# Set once, by _close_out_battle(), the instant battle_over flips true -
# read back by _on_post_battle_button_pressed() to decide where Continue
# actually goes (reward_screen.tscn, run_complete_screen.tscn, the title
# screen, or straight back to field_room.tscn for an escape - see that
# function's own match). Replaces an earlier version that read defeat_
# label.visible as a stand-in for "did we lose," which only ever had two
# states to distinguish; a UI flag was never really the source of truth,
# and a third outcome makes that finally worth fixing properly instead of
# growing a second parallel flag.
var _battle_outcome: RunLogger.BattleOutcome = RunLogger.BattleOutcome.VICTORY

# True for the whole stretch between pressing End Turn and the new player
# turn actually starting (hand discarded, enemy acting, intent
# advancing). Cards check this so they can't be played mid-resolution,
# and the End Turn button is also disabled as a second guard against
# clicking it again while it's already running.
var input_locked: bool = false

# Shown as "Turn: N". Battle start is turn 1; each new player turn after
# that increments it (see _start_player_turn()).
var turn_number: int = 1

# How many cards the player has played THIS turn, reset to 0 at the start
# of each of the player's own turns (see _start_player_turn()) - distinct
# from turn_number above, which counts BATTLE turns, not card plays
# within one. Incremented once per _play_card() call, but only AFTER that
# card's own _apply_card_effects() has finished (see _play_card()'s own
# note on why) - so while a card's effects are resolving, this still
# reads "how many cards were played before this one," the exact value
# FIRST_CARD_DAMAGE's own condition needs (== 0 means this card IS the
# first). First reader: card_effect.gd's FIRST_CARD_DAMAGE.
var cards_played_this_turn: int = 0

const ENEMY_TELEGRAPH_PAUSE := 0.4 # Beat before the intent resolves.
const ENEMY_RESOLVE_PAUSE := 0.6 # Beat after, so the flash/number land.
const DEBRIS_SPAWN_FADE_SEC := 0.4 # See _spawn_additional_enemy().
const DEBRIS_SPAWN_PADDING_SCALE := 0.4
# RENAMED from DEBRIS_SPAWN_CLUSTER_WIDTH_SCALE (2026-08-30, dynamic-
# cluster-width pass) - same value, same "read snug against the host"
# intent, different mechanism: cluster_width_px is no longer a flat
# constant this could usefully multiply (see Enemy._apply_dynamic_
# cluster_width()) - a multiply landing on it here would just be
# overwritten the instant set_enemy_data() runs. Applied to Enemy.
# cluster_width_padding_px instead (see _spawn_additional_enemy() below)
# - a SMALLER padding budget is what actually still shrinks the
# newcomer's own box relative to a normal spawn's, now that the box
# itself is derived from real measured width rather than an arbitrary
# 500px every enemy used to share. See _spawn_additional_enemy().

# --- Victory sequencing (see _on_all_enemies_defeated()) ---
#
# Exported, not const like the enemy-turn pauses above, so the pacing can
# be retuned by feel in the Inspector - victory_beat_pause_sec especially:
# the pause between the silhouette finishing its fade and Continue
# appearing is the one that makes this moment breathe instead of
# snapping straight to a button.
@export var victory_dim_fade_sec: float = 0.9
@export var victory_beat_pause_sec: float = 0.4
@export var victory_continue_fade_sec: float = 0.5
const VICTORY_DIM_ALPHA := 0.6

# Where Continue sits for a WIN specifically, overriding BattleOverlay's
# baked default (which is what Defeat's "New Run" still uses unchanged -
# see _on_player_defeated()). Computed in _on_all_enemies_defeated() from
# hand_container.offset_top (itself set from CARD_HEIGHT - see
# _apply_hand_container_height()), not baked as fixed offsets, so
# retuning HAND_CARD_SCALE can't silently reopen the hand-overlap this
# was moved up to avoid.
const VICTORY_BUTTON_HAND_GAP_PX := 30.0 # Clearance above the hand's top edge.
const VICTORY_BUTTON_HEIGHT_PX := 67.0 # Matches BattleOverlay's baked PostBattleButton height.

# These three arrays are the actual game state: which CardData resources
# are currently in the draw pile, in hand, or in the discard pile. They're
# separate from what's drawn on screen — the on-screen Card instances in
# HandContainer are just a visual representation of the "hand" array.
var draw_pile: Array[CardData] = []
var hand: Array[CardData] = []
var discard_pile: Array[CardData] = []

# Where a CONSUMED card (see card_data.gd's RemovalScope) goes when
# played, instead of discard_pile - never touched by _reshuffle_discard_
# into_draw(), so a consumed card genuinely can't come back for the rest
# of this fight even if the discard pile reshuffles mid-battle. The card
# is ALSO removed from RunState.deck the moment it's played (see
# _play_card()'s own call to RunState.remove_card_from_deck()) - a
# consumed card is gone for the rest of the RUN, not just this fight.
# run_removed_pile only exists so this battle's already-drawn local
# piles stay correct in the meantime; RunState.deck is the permanent
# record. Named for what it DOES (removed from the run), not after the
# RemovalScope.CONSUMED enum value itself (2026-08-28, removal-scope
# pass, renamed from consumed_pile) - a future rename of that enum
# value's own name shouldn't have to cascade into renaming this too.
var run_removed_pile: Array[CardData] = []

# Where a SPENT card (see card_data.gd's RemovalScope) goes when played,
# instead of discard_pile - same "never touched by _reshuffle_discard_
# into_draw()" exclusion run_removed_pile above already has, so a spent
# card can't come back within THIS fight either. UNLIKE run_removed_pile,
# nothing here ever calls RunState.remove_card_from_deck() - a SPENT card
# stays in RunState.deck the whole time, so it's back in the draw pile
# automatically next fight (Battle rebuilds every pile from RunState.deck
# fresh at _start_battle() - see that function's own doc) with no
# restoration code needed. spent_pile itself simply ceases to exist along
# with the rest of this battle's local state once this scene is gone.
var spent_pile: Array[CardData] = []

# @onready grabs a reference to a child node once the scene has finished
# building itself, so the node is guaranteed to exist when we grab it.
# $Name means "find my child node called Name."
@onready var ui: CanvasLayer = $UI
# Referenced directly (not just addressed via $UI/... for each child)
# for _play_screen_shake() below - a CanvasLayer's own "offset" is the
# one property that visibly moves EVERYTHING under it at once, which is
# what a screen shake actually needs (no Camera2D exists in this static,
# non-scrolling scene - see _apply_battle_backdrop()'s own note).
@onready var backdrop_texture: TextureRect = $UI/BackdropTexture
@onready var hand_container: HBoxContainer = $UI/HandContainer
@onready var discard_label: Label = $UI/DiscardLabel
@onready var room_label: Label = $UI/RoomLabel
@onready var battle_label: Label = $UI/BattleLabel
@onready var turn_label: Label = $UI/TurnLabel
@onready var gold_label: Label = $UI/GoldLabel
@onready var class_label: Label = $UI/ClassLabel
@onready var player_resource_cluster: PlayerResourceCluster = $UI/PlayerResourceCluster
@onready var player_battle_visual: PlayerBattleVisual = $UI/PlayerBattleVisual
@onready var enemy_zone: HBoxContainer = $UI/EnemyZone
@onready var end_turn_button: Button = $UI/EndTurnButton
@onready var dev_damage_button: Button = $UI/DevDamageButton
@onready var dev_status_button: Button = $UI/DevStatusButton
@onready var dev_escape_button: Button = $UI/DevEscapeButton
@onready var dev_upgrade_button: Button = $UI/DevUpgradeButton
@onready var dev_add_card_button: Button = $UI/DevAddCardButton
@onready var deck_button: Button = $UI/DeckButton
@onready var deck_viewer: DeckViewer = $DeckViewer
@onready var defeat_label: Label = $UI/DefeatLabel
@onready var dim_background: ColorRect = $BattleOverlay/DimBackground
@onready var post_battle_button: Button = $BattleOverlay/PostBattleButton
@onready var target_line: TargetLine = $UI/TargetLine

# --- Targeting (see _on_card_clicked()/_on_enemy_clicked()) ---
#
# The whole state machine is these two vars: null means normal hand
# state; non-null means "a card is armed, waiting for the player to
# click a living enemy to resolve it against." Nothing else tracks
# whether targeting is active - every check in this file is just
# `_pending_target_card_instance != null`.
var _pending_target_card_instance: Card = null
var _pending_target_data: CardData = null

# Which living enemy (if any) the target line is currently visually
# snapped to - see _update_snap_target() below. A SEPARATE notion from
# what actually resolves a click (_on_enemy_clicked(), driven by Godot's
# own gui_input on each enemy's hover_area, never reads this) - purely
# the hysteresis memory for the line's own snap state, per this
# feature's own brief (SCOPE: only WHEN the line visually snaps changes,
# never what counts as a legal click).
var _snapped_enemy: EnemyCombatant = null

# --- Damage preview seam (see card.gd's card_hover_changed) ---
#
# Which hand card is currently hovered, if any - a SEPARATE state
# machine from targeting above, on purpose: this tracks "the player is
# looking at this card," not "a card is armed and waiting for a target,"
# and the two don't always coincide (a card can be hovered with nothing
# armed, or armed and no longer hovered at all - see set_armed()'s own
# note on why hover keeps tracking underneath an armed pose). Tracked by
# INSTANCE, not just data, since two hand copies of the same CardData
# (e.g. two Slashes) would otherwise be ambiguous about which one's
# mouse_exited should actually clear this.
#
# This is the generic seam for "what would the currently-hovered card
# actually do right now" - today _update_damage_preview() below only
# ever reads Outbound's escape falloff, but a weapon modifier already
# silently changes a card's real damage, and the (dormant) status-
# modifier system is a second invisible number-changer - both are real
# future readers of this same hover state, not something that needs its
# own separate hover plumbing when they're built.
var _hovered_card_instance: Card = null
var _hovered_card_data: CardData = null

func _ready() -> void:
	# "pressed" is a signal every Button already has, built into Godot.
	# We're connecting it to our own function below.
	end_turn_button.pressed.connect(_on_end_turn_button_pressed)
	post_battle_button.pressed.connect(_on_post_battle_button_pressed)
	dev_damage_button.pressed.connect(_on_dev_damage_button_pressed)
	dev_status_button.pressed.connect(_on_dev_status_button_pressed)
	dev_escape_button.pressed.connect(_on_dev_escape_button_pressed)
	dev_upgrade_button.pressed.connect(_on_dev_upgrade_button_pressed)
	dev_add_card_button.pressed.connect(_on_dev_add_card_button_pressed)
	deck_button.pressed.connect(_on_deck_button_pressed)
	_chain_payoff_effect = CardEffect.new()
	_chain_payoff_effect.effect_type = CardEffect.EffectType.DAMAGE
	_chain_payoff_effect.value = CHAIN_PAYOFF_DAMAGE
	_apply_hand_container_height()
	_apply_combatant_vertical_position()
	_apply_enemy_zone_horizontal_anchor()
	_apply_battle_backdrop()
	_apply_boss_music()
	_start_battle()

# The battle scene is fixed-size, non-interactive, and static (DESIGN.md's
# Run Structure & Navigation: room framing removal reasoning doesn't apply
# here at all - there's no camera to scroll, no edges to walk toward), so
# a single rendered image per biome is the natural backdrop, not generated
# shapes the way the field room's own parallax layers are. RunState.
# current_biome is the shared seam (see biome_data.gd) - the same object
# a future map header would read a biome's identity from, not a second
# copy of that data living here.
#
# Two-layer fallback, same "empty means fall back gracefully, not broken"
# shape CardData.art_texture/EnemyData.visual_scene already use:
# BattleBackground (see battle_background.gd - always present, laid out
# once in its own _ready(), reads nothing from biome_data.gd at all)
# shows a palette-driven sky/ground/shadow underneath; BackdropTexture
# draws ON TOP of it and is only made visible once a real battle_
# backdrop texture exists. A biome with no art yet still reads as
# biome-appropriate rather than a missing-texture error. This USED to be
# a single flat ColorRect (biome_data.gd's own since-removed backdrop_
# fallback_color) specifically to avoid "elaborate generated scenery
# that's throwaway work once real art lands" - deliberately superseded
# (2026-08-27, see battle_background.gd's own header) for the fallback
# path specifically; Sunken Works already has real art (SunkenWorks1.png)
# and is completely unaffected either way, since BackdropTexture still
# covers whatever's under it whenever one exists.
@export_range(0.0, 1.0, 0.01) var battle_backdrop_crossover: float = 0.55
# Region 1's wet-to-dry gradient (docs/REGION_01_v1.md §3), extended from
# the field ground to the battle backdrop (2026-09-01, wet/dry backdrop
# pass) - below this, battle_backdrop_wet; at or above, battle_backdrop_
# dry (see _apply_battle_backdrop() below). Same crossover SHAPE field_
# room.gd's own foreground_band_crossover already established for the
# coastal-vs-grass foreground band, an independent value since the two
# pick between different image pairs on different scenes - no reason
# they'd need to agree on the same threshold.
func _apply_battle_backdrop() -> void:
	var biome: BiomeData = RunState.current_biome
	# RoomState.region_progress at THIS point is the depth of the room the
	# fight is actually happening in, not stale or reset - RoomState is an
	# autoload and survives the field-to-battle transition untouched
	# (field_blob.gd's own contact handler sets pending_enemy_data/
	# pending_encounter_enemies/player_position/has_saved_position before
	# calling SceneTransition.go_to("res://battle.tscn"), but never calls
	# load_room() again or touches region_progress itself), so this reads
	# the SAME value the field room's own ground tint was just computed
	# from, not a separate or delayed one.
	var backdrop: Texture2D = biome.battle_backdrop
	if RoomState.region_progress < battle_backdrop_crossover:
		if biome.battle_backdrop_wet != null:
			backdrop = biome.battle_backdrop_wet
	else:
		if biome.battle_backdrop_dry != null:
			backdrop = biome.battle_backdrop_dry
	if RoomState.current_room_type == RoomType.Kind.BOSS and biome.boss_battle_backdrop != null:
		backdrop = biome.boss_battle_backdrop
	backdrop_texture.texture = backdrop
	backdrop_texture.visible = backdrop != null
	# STRETCH_KEEP_ASPECT_COVERED fills BackdropTexture's own full-rect
	# size exactly (see battle.tscn: anchored 0,0 to 1,1) with no
	# letterboxing, cropping whatever overflows rather than leaving any
	# margin - the same fill behavior card.gd's own ArtTexture uses for
	# card art, applied here at scene scale instead of a card's.
	# EXPAND_IGNORE_SIZE lets the rect fill its anchors regardless of the
	# texture's own source resolution, rather than the texture dictating
	# a minimum size back to its container.
	backdrop_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

# BOSS_01's own battle theme (see music_manager.gd's MUSIC_FILES/
# VOLUME_TRIM_DB) - same "one room-scoped play_music() call, no explicit
# stop needed" shape field_room.gd already uses for room1_waves/room1_
# alt_drone (see DESIGN.md's Unrelieved entry): scene_transition.gd's
# stop_music() already fires at the start of every go_to(), which is how
# every path out of a battle (victory, defeat, escape) leaves the scene,
# so nothing here needs to stop this track explicitly. Gated the same
# way _apply_battle_backdrop() above gates the boss backdrop - a normal
# battle just leaves whatever track was already playing alone.
func _apply_boss_music() -> void:
	if RoomState.current_room_type == RoomType.Kind.BOSS:
		MusicManager.play_music("boss_01")

# Value-separation regression this backdrop surfaced, fixed once (battle.
# tscn's InfoLabelBackground, a static panel - see also DESIGN.md's Run
# Structure & Navigation: value separation note for the field's own
# version of this rule): RoomLabel/BattleLabel/TurnLabel/GoldLabel/
# ClassLabel share a pale, semi-transparent font_color (0.75, 0.78, 0.85,
# 0.7) tuned against a plain dark scene, with no background panel of
# their own - fine before this backdrop existed, nearly invisible against
# a bright sky once it did (confirmed via screenshot). Every OTHER piece
# of battle UI already sits on a solid opaque panel of its own (HP bars,
# cards, the End Turn/dev buttons) rather than relying on text color
# alone - this cluster of five labels was the one exception, not
# something the backdrop itself did wrong. A single dark, semi-opaque
# ColorRect behind the whole cluster (rather than rewriting five labels'
# own color) was the smaller, more consistent fix.

# Positions HandContainer so only hand_rest_visible_height_px of a card's
# own height shows above the screen's bottom edge at rest - both offsets
# computed from that ONE number (plus CARD_HEIGHT) rather than battle.
# tscn's old baked offset_bottom, since the whole point now is that the
# box extends PAST the screen edge, not up to a fixed margin above it.
# offset_top ends up representing "how far above the screen bottom the
# VISIBLE top of the hand sits" - which _apply_energy_display_position()
# and _on_all_enemies_defeated()'s own Continue-button math already read
# it as, so neither needed to change to keep working correctly once this
# switched from "the hand's true top" to "the hand's visible top." Runs
# once, before any card is ever drawn - nothing here depends on battle
# state, just on the (fixed, at runtime) card scale/rest height.
func _apply_hand_container_height() -> void:
	hand_container.offset_top = -hand_rest_visible_height_px
	hand_container.offset_bottom = CARD_HEIGHT - hand_rest_visible_height_px
	_apply_energy_display_position()
	_apply_end_turn_button_layout()

# PlayerBattleVisual/EnemyZone both start at combatant_top_offset_px now
# (see its own comment for why that number), keeping whatever HEIGHT
# battle.tscn already bakes for each - only the box's own vertical
# position changes, not its content or internal layout, so intent icons/
# name labels/vitals bars (all positioned in LOCAL space relative to
# their own parent) move down along with their box automatically, no
# separate fix needed for any of them.
func _apply_combatant_vertical_position() -> void:
	var player_height := player_battle_visual.offset_bottom - player_battle_visual.offset_top
	player_battle_visual.offset_top = combatant_top_offset_px
	player_battle_visual.offset_bottom = combatant_top_offset_px + player_height
	var enemy_height := enemy_zone.offset_bottom - enemy_zone.offset_top
	enemy_zone.offset_top = combatant_top_offset_px
	enemy_zone.offset_bottom = combatant_top_offset_px + enemy_height

# EnemyZone's own box only ever needs its CENTER point moved (see enemy_
# zone_anchor_x's own doc) - its width (the offset_left/right pair
# battle.tscn already bakes, both relative to this anchor) stays fixed,
# same "move the box, not its internal geometry" shape _apply_
# combatant_vertical_position() above already uses for the vertical
# axis. Both anchor_left and anchor_right are set to the same value
# (never stretched, matching battle.tscn's own anchors_preset = -1) so
# EnemyZone stays a fixed-width box pinned to one point, not a
# stretching one.
func _apply_enemy_zone_horizontal_anchor() -> void:
	enemy_zone.anchor_left = enemy_zone_anchor_x
	enemy_zone.anchor_right = enemy_zone_anchor_x

# battle.tscn's own EnemyZone node moved (2026-08-26, enemy-positioning
# pass) from BEFORE every plain utility button (Deck/Dev*/EndTurn) to
# AFTER all of them - pure tree-order z-fix: siblings under the same
# parent with no z_index of their own draw in declaration order, later
# wins, and an enemy's real rendered silhouette can extend past this
# box's own abstract layout bounds (see enemy_zone_anchor_x's own doc
# above) far enough to reach EndTurnButton's corner - the reported
# "snail occluded by End Turn" bug. Still declared BEFORE DefeatLabel/
# TargetLine in battle.tscn, both of which need to stay on top of an
# enemy for their own reasons regardless of this fix (TargetLine
# additionally now carries its own explicit z_index - see target_line.
# gd - so it wins even against an armed card's elevated z_index too, not
# just tree order). NOT documented as a comment in battle.tscn itself -
# this project's own .tscn parser silently drops the NEXT declared node
# when a comment sits directly before its [node] header with no blank-
# line buffer (confirmed via this exact edit: DefeatLabel vanished from
# PackedScene.get_state() the first time this comment was added inline;
# same failure mode already hit once before on pip.tscn - see pip.gd's
# own header). Documentation for a .tscn node's OWN properties belongs
# in the owning script from now on, not the scene file.

# PlayerResourceCluster and HandContainer share the same bottom-anchored
# scheme (anchor_top/bottom = 1.0), so - unlike Continue's own hand-
# relative math in _on_all_enemies_defeated(), which has to convert
# through an absolute Y because it crosses from a center-anchored node -
# this is just subtraction in a shared coordinate space. Keeps "just
# above the hand's left edge" true regardless of HAND_CARD_SCALE,
# instead of a static offset that only happened to clear the hand at
# today's scale.
const RESOURCE_CLUSTER_HEIGHT_PX := 193.0
# player_resource_cluster.gd now sizes itself from real content (see its
# own 2026-08-25 fix) rather than a fixed export - this is that real,
# measured total height (padding + pip row + gap + Toll's own two
# measured label rows), kept here only because THIS positioning math
# needs a height BEFORE the cluster has necessarily laid itself out this
# frame. If player_resource_cluster.gd's own padding/gap/font sizes
# change again, re-measure this alongside it (a mismatch isn't silently
# wrong the way the old fixed-height panel was, though - grow_vertical=0
# on this node means a real size taller than this assumption still grows
# UPWARD, away from the hand, not into it).
@export var energy_display_hand_gap_px: float = -50.0
# Cut from 20 (2026-08-25 fix) - Toll/the pips are player-facing
# controls that belong grouped with the hand below them, not floating a
# full 20px above it; closing most of that gap reads as one player-
# facing cluster instead of two separately-anchored HUD pieces.

func _apply_energy_display_position() -> void:
	player_resource_cluster.offset_bottom = hand_container.offset_top - energy_display_hand_gap_px
	player_resource_cluster.offset_top = player_resource_cluster.offset_bottom - RESOURCE_CLUSTER_HEIGHT_PX

# --- End Turn button (2026-08-26, reposition/shrink pass) ---
#
# Used to sit at a FIXED mid-frame offset (anchors_preset = 3, offset_top
# -538/offset_bottom -490 in battle.tscn - a screen-center-ish band that
# put it inside the combat area, where a real enemy silhouette extending
# past EnemyZone's own abstract box (see enemy_zone_anchor_x's own doc)
# could reach it - the reported "snail occluded by End Turn" bug, worked
# around separately by reordering EnemyZone to draw after every utility
# button (see _apply_enemy_zone_horizontal_anchor()'s neighboring
# comment). Moved here instead: same right-anchored scheme End Turn
# already used (anchor_left/top/right/bottom all still 1.0, untouched in
# battle.tscn), just re-anchored vertically off hand_container.offset_top
# - the SAME "just above the hand's fold line" pattern _apply_energy_
# display_position() above already uses, for the same reason (stays
# correct if hand_rest_visible_height_px/CARD_HEIGHT are ever retuned,
# rather than a static offset that only happens to clear today's fold).
# This puts it structurally BELOW EnemyZone's own abstract box bottom
# edge (combatant_top_offset_px + this Enemy's own baked height, ~762px
# at today's values - see _apply_combatant_vertical_position()) instead
# of just nudged clear of it, which is what actually resolves the
# occlusion rather than papering over it with draw order.
@export var end_turn_button_width_px: float = 150.0
@export var end_turn_button_height_px: float = 42.0
# SHRUNK from a baked 200x48 - measured headlessly against a fresh
# Button with this same "End Turn" text at font_size 22: raw glyphs
# alone are 96x31, Godot's own default theme already pads that to a
# natural 104x39 minimum (barely more than the glyphs - most of the old
# 200x48 footprint was this scene's own oversized baked offsets, not
# theme padding). 150x42 stays comfortably above that natural minimum
# (27px/5.5px of click-comfort margin per side) while cutting the old
# footprint by 25%/12.5% - not shrunk all the way to the theme's own
# minimum, which read as cramped once seen live.
@export var end_turn_right_margin_px: float = 33.0
# Matches DiscardLabel/DeckButton's own established 33px edge-margin
# convention elsewhere in this same corner of the HUD, rather than a
# fresh, unrelated number.
@export var end_turn_hand_gap_px: float = 16.0
# Clearance above hand_container's own top edge - a real gap (double
# energy_display_hand_gap_px's own 8, since this is a click TARGET,
# not a passive readout grouped with the hand the way Toll/pips are;
# a hair-thin gap here would read as glued to the hand it's supposed to
# sit near, not grouped with it).
#
# Deliberately NOT also dodged against a HOVERED hand card's rise
# (hover lifts a card to roughly hand_container's fold minus ~158px,
# well above this button's own band) - hand_max_span_px's own doc
# already accepts the equivalent trade-off for EnemyZone ("hover only
# ever lifts a card vertically... deliberately accepted for this pass")
# on the reasoning that the sustained, decision-relevant overlap only
# matters once a card is ARMED, and an armed card flies to armed_card_
# center_y_px at the viewport's horizontal CENTER (see that export's own
# doc), nowhere near this button's own right-edge position. "Any hand
# size" (this pass's own brief) is a RESTING-fan concern - card COUNT
# changes the fan's width, not any single card's hover state - and the
# resting fan sits entirely below this button once end_turn_hand_gap_px
# clears hand_container's own top edge, regardless of how many cards
# are in it.
func _apply_end_turn_button_layout() -> void:
	end_turn_button.offset_right = -end_turn_right_margin_px
	end_turn_button.offset_left = end_turn_button.offset_right - end_turn_button_width_px
	end_turn_button.offset_bottom = hand_container.offset_top - end_turn_hand_gap_px
	end_turn_button.offset_top = end_turn_button.offset_bottom - end_turn_button_height_px

# Resets every piece of BATTLE-level state back to a fresh start: energy,
# block, intent tracking, the turn counter, a freshly shuffled copy of
# RunState.deck, a brand new enemy, and turn 1's draw. Called once from
# _ready() - every battle after the first is a fresh instance of this
# scene too now (Victory routes through the reward screen first; see
# _on_post_battle_button_pressed below), so there's no in-place re-run
# case to handle here anymore. Deliberately does NOT touch RunState -
# that's already been decided by whatever led here before this scene
# runs (title screen's Begin Run, or the reward screen's Continue).
func _start_battle() -> void:
	AudioManager.play_sfx("combat_start")
	battle_over = false
	input_locked = false
	end_turn_button.disabled = false
	deck_button.disabled = false
	defeat_label.visible = false
	dim_background.visible = false
	dim_background.color.a = 0.0
	post_battle_button.visible = false
	# True by default now (was false) - a WIN leaves it disabled until its
	# fade-in finishes (see _on_all_enemies_defeated()), so Continue can't be
	# clicked mid-fade. A LOSS still flips it straight back to false
	# itself (see _on_player_defeated()) since its button shows instantly.
	post_battle_button.disabled = true

	player_block = 0
	absorb_pool = 0
	_set_toll(0)
	_took_damage_this_turn = false
	_took_damage_last_turn = false
	rally_pool = 0
	_trinket_free_card_armed = false
	_trinket_free_card_fired = false
	_escaping_enemy = null
	_escape_distance = 0.0
	energy = max_energy
	turn_number = 1

	draw_pile.clear()
	discard_pile.clear()
	run_removed_pile.clear()
	spent_pile.clear()
	# .duplicate() so shuffling and drawing THIS battle's copy never
	# mutates RunState.deck itself - the run's deck composition only ever
	# changes when a reward is picked (see RunState.add_card_to_deck()).
	draw_pile = RunState.deck.duplicate()
	draw_pile.shuffle()

	for combatant in enemies:
		combatant.instance.queue_free() # Only present after the first battle.
	enemies.clear()
	_spawn_enemies()
	var enemy_names: Array[String] = []
	for combatant in enemies:
		enemy_names.append(combatant.data.enemy_name)
	RunLogger.log_battle_start(enemy_names)

	_draw_cards(5)
	_update_pile_labels()
	_update_energy_label()
	_update_player_panel()
	_update_turn_label()
	_update_room_label()
	_update_battle_label()
	_update_gold_label()
	_update_class_label()
	_update_deck_button()

# The single button shown on Victory ("Continue"), Defeat ("New Run"),
# and Escape ("Continue" - see _on_battle_escaped()) - see _on_all_
# enemies_defeated()/_on_player_defeated()/_on_battle_escaped() for where
# its text/visibility get set. Which path runs now switches on the real
# outcome _close_out_battle() recorded (_battle_outcome) rather than
# reading defeat_label.visible as a stand-in for "did we lose" - that
# only ever had two states to distinguish, and a UI flag was never
# really the source of truth. Disabling the button immediately guards
# against a double-click firing this twice (e.g. queuing two scene
# transitions).
func _on_post_battle_button_pressed() -> void:
	post_battle_button.disabled = true
	match _battle_outcome:
		RunLogger.BattleOutcome.DEFEAT:
			# A loss ends the run here - RunState isn't touched. The title
			# screen's Begin Run button is the only place a fresh run starts
			# (see title_screen.gd), so this just navigates back to it.
			RunLogger.end_run(false)
			SceneTransition.go_to("res://title_screen.tscn")
		RunLogger.BattleOutcome.VICTORY:
			if RoomState.current_room_type == RoomType.Kind.BOSS:
				# Beating the boss ends the run in victory - no reward screen
				# (the run's over, there's no next battle to carry a reward
				# into), just a summary before heading back to the title screen.
				RunLogger.end_run(true)
				SceneTransition.go_to("res://run_complete_screen.tscn")
			else:
				# A win goes to the reward screen before the next battle -
				# see reward_screen.gd, which is now where advancing to the
				# next battle number and transitioning back to Battle
				# actually happens.
				SceneTransition.go_to("res://reward_screen.tscn")
		RunLogger.BattleOutcome.ESCAPE:
			# No reward screen, no gold, no card offer - the player leaves
			# the node with nothing, straight back to the field it was
			# fought from. This IS escape's reward branch, not a bypass of
			# one: it currently awards nothing, but it's the one place that
			# decision is made, the same dispatch point victory's own
			# reward routing goes through above. A future escape-specific
			# drop (unreleased - see DESIGN.md's own note) is a change
			# INSIDE this branch, not a new path alongside it.
			SceneTransition.go_to("res://field_room.tscn")

# Enemy.cluster_width_px/bar_width_px/silhouette_scale (its own single-
# enemy-tuned defaults, untouched - see enemy.gd) get multiplied by this
# once per battle, based on how many enemies are actually in it. 1 always
# gets factor 1.0 (today's sizing, exactly). EnemyZone (an HBoxContainer,
# alignment = CENTER) already packs and centers whatever children it has
# with a fixed separation regardless of count - what it can't do on its
# own is stop 2-3 FULL single-enemy-sized clusters from just being wide,
# sparse boxes with a lot of dead margin around each creature, which is
# what actually read as "fixed slots with a gap" rather than a tight
# group. Shrinking each cluster instead of changing how they're packed
# is what makes a pair or trio read as one deliberate formation.
@export_group("Multi-Enemy Layout")
@export var two_enemy_scale_factor: float = 0.5
@export var three_enemy_scale_factor: float = 0.45

@export var enemy_separation_default: float = 40.0
# EnemyZone's theme separation for 1-2 enemies (1-enemy has no gap to
# apply this to, but the field stays consistent with the export below).
# LOWERED (2026-08-26, second pass) from 80.0 - at 2 enemies, 80px
# between two already-shrunk 250px clusters (two_enemy_scale_factor)
# read as empty field rather than deliberate spacing between them. Was
# battle.tscn's own original baked value before _apply_enemy_zone_
# separation() existed (see that function's own doc for why this moved
# to script) - not re-derived from any formula, just tightened until it
# read as a gap instead of a gap-shaped absence.
@export var enemy_separation_three_plus: float = -20.0
# 2026-08-26, enemy-compression pass (retuned second pass alongside
# enemy_separation_default above): at 3 enemies, cluster_width_px/the
# scale factors are off-limits for this fix (see this pass's own brief),
# so shrinking the GAP BETWEEN enemies is the one remaining lever to
# keep the widest formation clear of its neighbors on both sides at once
# - same shape as _update_hand_spacing()'s negative separation for an
# overflowing hand, deliberately allowing actual silhouette overlap
# rather than just tightening toward zero (see enemy_zone_anchor_x's own
# doc for the resulting 63.9px/268.9px clearances this produces).
# -20.0 keeps the SAME ratio to enemy_separation_default the original
# pass landed on by coincidence (three_plus = -0.5 * default: 80 -> -40,
# now 40 -> -20) - not re-derived from scratch, since halving the
# now-smaller default's magnitude and flipping its sign still produces a
# modest, real overlap (20px per neighbor pair) without needing as much
# forced compression as before now that enemy_zone_anchor_x isn't also
# fighting a since-relocated EndTurnButton. Chosen as a starting point,
# not a verified-live value (same caveat enemy_zone_anchor_x's own doc
# flags) - retune directly if real 3-enemy art crowds a neighbor past
# individually-readable, or if it still reads as too loose.

func _multi_enemy_scale_factor(count: int) -> float:
	match count:
		2: return two_enemy_scale_factor
		3: return three_enemy_scale_factor
		_: return 1.0

# Only ever needs to run ONCE per battle, at spawn time (unlike hand
# spacing, which recomputes on every draw/discard) - a defeated enemy's
# Enemy node stays in EnemyZone for its own fade-out (play_defeat_
# sequence() - see _on_enemy_defeated()), never removed mid-battle, so
# the child count this reads never changes after _spawn_enemies() runs
# once. Requirement (this pass's own brief): stays at enemy_separation_
# default through 2 enemies, only 3+ compresses - matches enemy_zone_
# anchor_x's own math, which only becomes a real problem at 3 (2 enemies
# already had enough clearance under the old separation - see that
# export's own doc).
func _apply_enemy_zone_separation(count: int) -> void:
	var separation := enemy_separation_default if count <= 2 else enemy_separation_three_plus
	enemy_zone.add_theme_constant_override("separation", roundi(separation))

# Instances one Enemy scene per EnemyData in _resolve_enemies_data(),
# exactly like _add_card_to_hand_display() instances Card from a
# CardData - create, add to the tree, then hand it the data to display.
# Into EnemyZone (an HBoxContainer - see battle.tscn's Battle Layout
# note), not directly under UI - what actually centers the group, and
# spaces multiple clusters apart, is EnemyZone's own alignment/
# separation, not anything Enemy or this function need to know about.
# The scale override below has to land BEFORE add_child() - Enemy's
# _ready() (which reads cluster_width_px/bar_width_px) and set_enemy_
# data() (which reads silhouette_scale) both run off whatever's already
# set on the instance by the time each of those fires.
#
# cluster_width_px is NOT pre-scaled here any more (2026-08-30, dynamic-
# cluster-width pass - REMOVES the old `instance.cluster_width_px *=
# scale_factor` line) - Enemy.set_enemy_data() now derives cluster_
# width_px itself, from this specific creature's own measured silhouette
# (see Enemy._apply_dynamic_cluster_width()), so presetting it here would
# just be immediately overwritten. Compression still reaches the final
# box width - it's baked into silhouette_scale below, which _apply_
# dynamic_cluster_width() reads directly - so a compressed encounter
# still gets a narrower box for a narrower creature, just derived from
# the real render size instead of a second, independent shrink applied
# to an arbitrary flat constant. bar_width_px keeps its own pre-scale
# exactly as before - out of scope for this pass, unrelated to the
# overflow problem cluster_width_px's own doc describes.
func _spawn_enemies() -> void:
	var enemies_data := _resolve_enemies_data()
	var scale_factor := _multi_enemy_scale_factor(enemies_data.size())
	_apply_enemy_zone_separation(enemies_data.size())
	for i in enemies_data.size():
		var enemy_data: EnemyData = enemies_data[i]
		print("Enemy: %s" % enemy_data.enemy_name)
		# No scale-up step here any more (2026-08-29, BOSS_01 pass -
		# REMOVES the old _make_boss_variant() call and the placeholder it
		# existed for) - room_state.gd's _generate_boss_layout() now hands
		# over a real, dedicated boss EnemyData (already tuned at its own
		# real numbers, is_elite already set on the resource itself), not
		# a normal enemy standing in for one that needed scaling up here.
		var instance: Enemy = ENEMY_SCENE.instantiate()
		instance.bar_width_px *= scale_factor
		instance.silhouette_scale *= scale_factor
		enemy_zone.add_child(instance)
		instance.set_enemy_data(enemy_data)

		var combatant := EnemyCombatant.new()
		combatant.data = enemy_data
		combatant.instance = instance
		combatant.max_hp = enemy_data.max_hp
		combatant.hp = combatant.max_hp
		if enemy_data.erratic_intent_selection and not enemy_data.intents.is_empty():
			# The Tideworn's first intent is random too, not just its later
			# advances (see _advance_enemy_intent()) - "erratic" means every
			# selection, including the very first one the player ever sees.
			# _pick_erratic_initial_index(), not a raw random index - see
			# its own comment for why a locked wind-up follow-up can't be
			# the very first thing shown either. An enemy with any
			# EnemyIntent.turn_one_locked entry (the Sputter's Scissor)
			# routes through the turn-one-gated variant instead - see
			# that function's own doc.
			if enemy_data.intents.any(func(i: EnemyIntent): return i.turn_one_locked):
				combatant.current_intent_index = _pick_erratic_initial_index_turn_one_locked(enemy_data)
			else:
				combatant.current_intent_index = _pick_erratic_initial_index(enemy_data)
		elif not enemy_data.intents.is_empty():
			# Rotation stagger for same-type pack encounters (2026-09-02,
			# Saltdarner pack pass) - the i-th combatant in THIS encounter
			# starts i steps into its own fixed rotation instead of every
			# duplicate opening on the identical intent in lockstep. i=0
			# always lands on i % size == 0 regardless of size, so the
			# first combatant (solo encounters, and slot 0 of any mixed
			# one) is completely unaffected - existing behavior for every
			# encounter authored before this pass holds exactly as before.
			# Guarded on non-empty `intents` (not just non-erratic) - an
			# enemy with an EMPTY intents array (Tender/supply.tres, a
			# passive damage-source enemy with no attack pattern of its
			# own - see EncounterData's own Gun/Supply reference) would
			# otherwise divide by zero here at i=1. Left at its class
			# default (0) instead, which is exactly what it already was
			# before this pass - _resolve_enemy_intent() bails out on an
			# empty intents array before current_intent_index is ever
			# read for one, so this guard changes nothing observable for
			# Gun/Supply, the one encounter today where a slot-1 enemy
			# isn't a duplicate of slot 0's own type.
			combatant.current_intent_index = i % enemy_data.intents.size()
		# The lambda captures `combatant` from this exact iteration, the
		# same trick _add_card_to_hand_display() uses for card_instance -
		# so when THIS enemy's click comes back, we already know which
		# combatant it is without searching for it.
		instance.enemy_clicked.connect(func(): _on_enemy_clicked(combatant))
		# See enemy.gd's right_clicked doc - a right-click on an enemy
		# cancels active targeting rather than committing to it. Safe
		# unconditionally, same as the card connect above.
		instance.right_clicked.connect(_cancel_targeting)
		enemies.append(combatant)
		if enemy_data.escape_distance_max > 0.0:
			# Outbound is solo-only (see its own EnemyData note) - never
			# expected to overwrite an already-found _escaping_enemy within
			# one fight, but not guarded against it either: a future second
			# escaping enemy in the same room would just mean the LAST one
			# found here wins, not a crash.
			_escaping_enemy = combatant
		_show_initial_intent_or_growth(combatant)

# Which enemies this battle fights. Checked in order:
# 1. RoomState.pending_encounter_enemies - either the field blob the
#    player just touched was an AUTHORED multi-enemy encounter (see
#    encounter_data.gd and DESIGN.md's Bestiary: Authored encounters), OR
#    dev_encounter_picker.gd set this directly (see its own header) -
#    both fight exactly that group, this function has no way to tell
#    which caller set it and doesn't need to. Returned SHUFFLED (2026-08-29,
#    see its own note below) - _spawn_enemies() below places each entry
#    left-to-right in array order, so this is what actually decides the
#    on-screen arrangement, not just which enemies show up.
# 2. RoomState.pending_enemy_data - the ordinary single-enemy case,
#    wrapped in a one-element array.
# 3. Only reachable via the title screen's "Dev: Battle Chain" shortcut,
#    which skips the field (and so never sets either pending field)
#    entirely: a fresh EnemyPool.pick_random(), same as every other
#    battle number.
#
# REMOVED (2026-08-27, dev-encounter-picker pass) the old battle_number-
# keyed pin (battle 1 always Beachwrack, 2 always Outbound, 3 always
# Wardling, only 4+ random) - that existed to give fast, reliable access
# to a specific fight for playtesting a mechanic that needed to actually
# be seen (wind-up/debris spawn, escape, an elite). dev_encounter_
# picker.tscn now covers that need directly and reproducibly (pick
# exactly the encounter you want, any time) without needing to burn
# through a whole chain first, so the pin no longer earns its
# complexity. Dev Battle Chain reads as "random throughout" now, not "1-3
# pinned, 4+ random" - its remaining value is exercising the multi-fight
# SEQUENCE, not landing on any specific one.
func _resolve_enemies_data() -> Array[EnemyData]:
	if not RoomState.pending_encounter_enemies.is_empty():
		# Shuffled left-to-right position (2026-08-29) - an authored
		# encounter's own `enemies` array is written in whatever order
		# reads clearest as DESIGN (Mushroom Patch's own mushroom_a/b/c,
		# authored smallest-growth-stage-first purely for readability on
		# disk), not necessarily the order they should ALWAYS appear on
		# screen - left unshuffled, that authoring order becomes the
		# fight's own permanent visual arrangement, e.g. Mushroom Patch
		# reading "smallest to largest" left-to-right in literally every
		# fight. .duplicate() first - RoomState.pending_encounter_enemies
		# is shared state another caller could still read after this
		# (a fresh battle re-touching the same field blob without leaving
		# the room), so shuffling in place would leak this fight's random
		# arrangement into that later read instead of it getting its own
		# independent roll. Also reorders _living_enemies()'s own turn
		# sequence, not just the visual - accepted, not worked around:
		# nothing about how these enemies act depends on turn order
		# relative to each other (Mushroom Patch's own growers don't
		# interact), so there's no mechanical reason to decouple the two.
		var enemies_data := RoomState.pending_encounter_enemies.duplicate()
		enemies_data.shuffle()
		return enemies_data
	var single: EnemyData = RoomState.pending_enemy_data
	if single != null:
		return [single]
	return [EnemyPool.pick_random()]

# Randomizes pitch_scale within draw_sfx_pitch_min/max (see that export's
# own doc) and plays sound_name through AudioManager's own established
# play_sfx() convention - the SAME method every other sound in this
# project already goes through, just handed a non-default pitch_scale.
func _play_draw_sfx(sound_name: String) -> void:
	AudioManager.play_sfx(sound_name, randf_range(draw_sfx_pitch_min, draw_sfx_pitch_max))

# Same shape as _play_draw_sfx() above, own pitch range (shuffle_sfx_
# pitch_min/max) - see that export's own doc for why it isn't just a
# second caller of _play_draw_sfx() itself.
func _play_shuffle_sfx() -> void:
	AudioManager.play_sfx("deck_reshuffle", randf_range(shuffle_sfx_pitch_min, shuffle_sfx_pitch_max))

# --- Draw arrival / deal (see card.gd's place_at_draw_origin()/begin_
# draw_arrival() for the per-card animation these drive, and the Draw
# Arrival Animation export group above for the timing) ---
#
# _deal_in_progress gates _input() below - true for the span of one
# _draw_cards() call (a "deal"), so a click/key press anywhere else in
# the game (when no deal is running) never touches deal state at all.
# _deal_skip_requested, once set, makes every remaining step of the
# CURRENT deal resolve instantly with no sound - see _reveal_drawn_card()
# and _draw_cards() itself. _deal_cards_in_flight is every card THIS
# deal has placed so far (see _reveal_drawn_card()) - _input() walks it
# directly to snap already-traveling cards the INSTANT skip fires, rather
# than waiting for each one's own coroutine to next notice the flag
# (which, for a card already past begin_draw_arrival(), never happens on
# its own - _draw_cards()'s loop has already moved on to a later card).
var _deal_in_progress: bool = false
var _deal_skip_requested: bool = false
var _deal_cards_in_flight: Array[Card] = []

# Moves "amount" cards from draw_pile into hand, both as data (the hand
# array) and visually (a new Card instance in HandContainer, dealt in one
# at a time - see _reveal_drawn_card()). If the draw pile runs dry
# partway through, the discard pile is shuffled back into it first, like
# reshuffling a real discard pile - _reshuffle_discard_into_draw() is
# UNCHANGED and fires exactly where it always did, mid-loop, which is
# what makes its own sound land correctly BETWEEN two cards' arrivals
# rather than all at once before either (see this feature's own brief).
#
# Every mechanical step below (the hand-full break, the pile checks, the
# actual pop/append) is byte-identical to this function's pre-animation
# form and runs FULLY SYNCHRONOUSLY per card, before that card's own
# presentation is even started - "cards are in hand the moment they're
# drawn in data," per this feature's own brief, holds for every card
# regardless of how far through the deal it lands or whether a skip is
# already in effect by the time it's this card's turn.
func _draw_cards(amount: int) -> void:
	_deal_in_progress = true
	_deal_skip_requested = false
	_deal_cards_in_flight = []
	var deck_origin: Vector2 = deck_button.global_position + deck_button.size / 2.0
	for i in amount:
		if hand.size() >= MAX_HAND_SIZE:
			print("Hand is full (%d cards) — can't draw." % MAX_HAND_SIZE)
			break
		if draw_pile.is_empty():
			if discard_pile.is_empty():
				_deal_in_progress = false
				return # Nothing left anywhere — stop drawing.
			_reshuffle_discard_into_draw()
		var data: CardData = draw_pile.pop_back()
		hand.append(data)
		var card_instance: Card = _add_card_to_hand_display(data)
		_update_hand_spacing()
		_update_hand_fan()
		await _reveal_drawn_card(card_instance, deck_origin)
		if i < amount - 1 and not _deal_skip_requested:
			await _await_deal_stagger(draw_arrival_stagger_sec)
	_deal_in_progress = false

# Reveals ONE freshly-drawn card: places it at the draw pile's own screen
# anchor, waits one process_frame - HandContainer's own HBoxContainer
# sort is DEFERRED, so this card's global_position (read by card.gd's
# begin_draw_arrival()) is stale garbage any earlier than that, confirmed
# empirically before writing this - then plays its sound and begins its
# travel. If a skip was already requested (either before this card's own
# placement, or during that one-frame wait), snaps straight to the final
# resting state instead - no sound, no travel - matching every other
# card the same skip affects, per this feature's own "remaining sounds
# suppressed" brief.
func _reveal_drawn_card(card: Card, from_global_position: Vector2) -> void:
	if _deal_skip_requested:
		card.skip_draw_arrival()
		return
	card.place_at_draw_origin(from_global_position)
	_deal_cards_in_flight.append(card)
	await get_tree().process_frame
	if _deal_skip_requested:
		card.skip_draw_arrival()
		return
	_play_draw_sfx("card_draw_single")
	card.begin_draw_arrival(draw_arrival_travel_sec)

# Same polling shape as field_forge.gd's own _await_hold() - not a
# shared helper (different class, different skip flag), same established
# "poll once a frame, bail the instant skip fires" convention.
func _await_deal_stagger(duration: float) -> void:
	if duration <= 0.0:
		return
	var timer := get_tree().create_timer(duration)
	while timer.time_left > 0.0:
		if _deal_skip_requested:
			return
		await get_tree().process_frame

# Any real input during a deal (a card click, End Turn, ...) completes it
# instantly - "the deal must never delay the player," per this feature's
# own brief. Deliberately does NOT call get_viewport().set_input_as_
# handled() - the SAME event still has to go on and register normally
# wherever it actually lands (a card now sitting fully in its resting
# slot, the End Turn button, ...), which only works because _input()
# fires BEFORE Godot's own GUI click dispatch (Control._gui_input()) -
# every card's final state is already resolved by the time THAT runs, so
# a click mid-deal correctly registers as a click on whichever now-
# settled card actually ends up under the cursor. battle.gd's existing
# _unhandled_input() (targeting cancel) is untouched and unaffected -
# that only ever sees events NEITHER this nor the GUI layer consumed.
func _input(event: InputEvent) -> void:
	if not _deal_in_progress or _deal_skip_requested:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_deal_skip_requested = true
		for card in _deal_cards_in_flight:
			card.skip_draw_arrival()

# Swaps ONLY draw_pile and discard_pile - run_removed_pile/spent_pile
# are excluded by simply never being mentioned here, not by some extra
# guard. Deliberate for both: a CONSUMED card is gone from RunState.deck
# entirely, so pulling it back into this fight's rotation would resurrect
# a card the run itself no longer owns; a SPENT card is meant to sit out
# the REST of this fight specifically, so folding it back in on the very
# next reshuffle would defeat the whole point of the scope. Do not add
# either pile here - a future edit "helpfully" including them would
# silently break both mechanics at once.
func _reshuffle_discard_into_draw() -> void:
	# Hooked HERE, not at _draw_cards()'s own call site - unlike card_
	# upgrade's forge-only hook (offer_upgrade() has three callers, only
	# one of which wants the sound), this function has exactly one caller
	# today (confirmed via project-wide search) and no reason a future
	# second caller would want the reshuffle to happen silently, so the
	# single source of truth for "a reshuffle occurred" is also the right
	# place for its own sound.
	_play_shuffle_sfx()
	draw_pile = discard_pile
	discard_pile = []
	draw_pile.shuffle()

# Creates one Card instance for a piece of CardData, adds it to the
# on-screen hand, and listens for its click signal. Returns the instance
# (2026-09-03, deal-animation pass) so _draw_cards() can hand it straight
# to _reveal_drawn_card() - previously void since nothing needed it back.
func _add_card_to_hand_display(data: CardData) -> Card:
	var card_instance: Card = CARD_SCENE.instantiate()
	hand_container.add_child(card_instance)
	# Before set_card_data() - see set_scale_factor()'s own comment on why
	# that order matters.
	card_instance.set_scale_factor(HAND_CARD_SCALE)
	# Bigger hover rise than Card's own default - see hand_rest_visible_
	# height_px's own comment for why hand cards specifically need this.
	# sink is exactly enough to cancel HandContainer's own below-fold
	# offset; hover_rise_extra_px on top of that reproduces Card's own
	# default hover-vs-rest distance, just anchored to the new, much
	# lower rest position instead of Vector2.ZERO. No armed_offset
	# equivalent any more - armed now flies to armed_card_center_y_px
	# instead (see card.gd's set_armed()), independent of this sink.
	var sink: float = CARD_HEIGHT - hand_rest_visible_height_px
	card_instance.hover_offset = Vector2(0, -(sink + hover_rise_extra_px))
	card_instance.hover_duration = hand_hover_duration_sec
	card_instance.set_card_data(data)
	card_instance.set_affordable(_is_card_playable(data))
	# A card drawn while its own condition is ALREADY true (Compound drawn
	# mid-turn at Toll 16, say) needs to show that the instant it appears,
	# not wait for the next Toll change to happen to refresh it - _update_
	# hand_affordability() only ever walks cards already in hand_
	# container, which this one isn't yet the moment it's created (see
	# battle.gd's own _card_condition_active() and card.gd's set_
	# condition_active()).
	card_instance.set_condition_active(_card_condition_active(data))
	# Same "freshly-drawn card needs its correct starting state, not just
	# whatever the next unrelated refresh happens to leave it at" reasoning
	# set_condition_active() above already gives - _update_hand_stance_
	# indicators() only ever walks cards already in hand_container, which
	# this one isn't yet. Harmless no-op (0, hidden) the far more common
	# time no drain-carrying status is active.
	card_instance.set_attack_hp_drain(_total_attack_hp_drain())
	_update_status_card_preview(card_instance, data)
	_update_hand_outgoing_damage_preview(card_instance, data)
	if data.chain_role == CardData.ChainRole.CLOSER:
		# A Closer drawn mid-turn, after an Opener already landed, needs to
		# glow the instant it's in hand - the player shouldn't have to
		# notice it's a Closer AND separately remember an Opener went off
		# earlier. Harmless no-op (active=false) the far more common time
		# nothing's currently live.
		card_instance.set_chain_available(chain_empowered)
	# func(clicked_data): ... defines a small function right here, called
	# a "lambda." It "remembers" card_instance from this exact call, which
	# is how _on_card_clicked below knows exactly which on-screen card to
	# remove, even if two cards in hand show the same data (e.g. two
	# Slashes).
	card_instance.card_clicked.connect(func(clicked_data): _on_card_clicked(card_instance, clicked_data))
	card_instance.card_hover_changed.connect(func(hovered_data, hovering): _on_card_hover_changed(card_instance, hovered_data, hovering))
	# See card.gd's right_clicked doc - a right-click anywhere on a card
	# cancels active targeting, same as a right-click on an enemy or on
	# empty background. Safe unconditionally (no pending-target guard
	# needed) - _cancel_targeting() is already a no-op when nothing is
	# armed.
	card_instance.right_clicked.connect(_cancel_targeting)
	return card_instance

# card.gd's card_hover_changed fires for every hand card, unconditionally
# (see its own note) - this is where Battle decides what it MEANS, same
# split every other Card signal already follows. Tracks by instance (see
# _hovered_card_instance's own note on why) - EXIT restores that exact
# instance's own text directly (it's still right here as a parameter,
# no need to route through _update_damage_preview() for that half), and
# only clears the tracked hover if the EXITING instance is the one we're
# currently tracking, so a fast mouse move from card A to card B (B's
# mouse_entered arriving before A's mouse_exited) can't have A's own
# exit wipe out B's already-current hover.
func _on_card_hover_changed(card_instance: Card, card_data: CardData, hovering: bool) -> void:
	if hovering:
		_hovered_card_instance = card_instance
		_hovered_card_data = card_data
		_update_damage_preview()
	elif _hovered_card_instance == card_instance:
		card_instance.restore_description()
		_hovered_card_instance = null
		_hovered_card_data = null

# THE dispatch point for the damage-preview seam (see _hovered_card_
# instance's own note) - decides WHETHER to show a preview and reads
# whichever live, invisible modifier applies, writing straight to the
# hovered CARD's own face (2026-08-24, moved off enemy.gd's Damage
# PreviewLabel - see card.gd's show_modified_damage() for the full
# design-rule note on why: a player-side modifier is target-independent
# and belongs on the card unconditionally; a target-side one is normally
# ambiguous with more than one enemy and belongs on the target instead -
# Outbound's escape falloff is target-side but gets the card-face
# exception ONLY because it's guaranteed solo, never a general rule).
# DamagePreviewLabel itself is untouched, still there, inert - a future
# target-side modifier that can't collapse to one card-face number is
# still its job. Today's only reader is Outbound's escape falloff
# (_escape_falloff_scalar()); a weapon modifier or the status-modifier
# system reading in here later is a change to this one function, not a
# new hover path. _card_needs_target() is reused as "does this card deal
# damage" - every card with requires_target set true today is a damage
# card (see CardData.requires_target's own doc), independent of how many
# enemies are alive or whether anything's actually armed, which is
# deliberately NOT part of this condition: Outbound is solo, so arming
# never happens in a real fight against it, and gating on it would mean
# this either never fires or only fires on a technicality the player
# can't perceive. scalar < 1.0
# is the same "nothing to report yet" guard the old label used (no
# falloff yet reads as no visible change, not a same-number recolor).
func _update_damage_preview() -> void:
	if _hovered_card_instance == null:
		return
	var scalar: float = _escape_falloff_scalar(_escaping_enemy) if _escaping_enemy != null else 1.0
	var show_preview := _card_needs_target(_hovered_card_data) and _escaping_enemy != null and scalar < 1.0
	if show_preview:
		_hovered_card_instance.show_modified_damage(scalar)
	else:
		_hovered_card_instance.restore_description()

# Enemies still standing, in spawn order - the one place "who's a legal
# target / who still acts on their turn" gets decided. A defeated enemy
# never leaves the `enemies` array (its combatant stays around for
# bookkeeping - see _on_enemy_defeated()), it just stops showing up here.
func _living_enemies() -> Array[EnemyCombatant]:
	return enemies.filter(func(e): return not e.is_defeated)

# True if this card needs a target chosen before it plays - reads
# CardData.requires_target directly (see its own doc). USED TO be
# derived here by scanning data.effects for a DAMAGE/TOLL_DAMAGE/
# TOLL_THRESHOLD_DAMAGE entry; that inference is gone on purpose
# (2026-08-25 - see requires_target's own doc) so targeting is a fact
# authored on the card, never a side effect of what its effects contain
# or how many enemies happen to be alive.
func _card_needs_target(data: CardData) -> bool:
	return data.requires_target

# The minimum Toll a card needs sitting in `toll` before it can be
# played at all - 0 for a card with no Toll-gated effect (never blocks
# play). TOLL_DAMAGE needs any Toll at all (1, since Toll is always a
# whole number - "toll < 1" is the same test "toll <= 0" always was).
# TOLL_BLOCK needs its own authored toll_cost specifically, since unlike
# TOLL_DAMAGE it only ever consumes that fixed amount, never "whatever
# Toll currently is" (see card_effect.gd's own doc for both). Derived
# from the effect list, not an authored flag on CardData, same shape
# _card_needs_target() above already uses. Folded into both hand
# affordability (see _is_card_playable()) and _on_card_clicked()'s own
# refusal check, the same two-part pattern (visual dim + an actually-
# enforced refusal, not just a look) energy affordability already uses -
# a card gated on Toll should never be playable-but-useless, per Back
# Pay's own original brief.
func _card_toll_requirement(data: CardData) -> int:
	var requirement := 0
	for effect in data.effects:
		if effect.effect_type == CardEffect.EffectType.TOLL_DAMAGE:
			requirement = maxi(requirement, 1)
		elif effect.effect_type == CardEffect.EffectType.TOLL_BLOCK or effect.effect_type == CardEffect.EffectType.TOLL_RETALIATE:
			requirement = maxi(requirement, effect.toll_cost)
	return requirement

# THE single place "can the player currently play this card at all"
# is decided - energy affordability AND (for a card like Reckoning) a
# Toll requirement. Used both when a card first enters the hand and
# whenever anything changes that could affect OTHER cards already in
# hand (spending energy, spending Toll - see _update_hand_affordability()
# below and _set_player_hp()'s own call into it).
func _is_card_playable(data: CardData) -> bool:
	if _effective_energy_cost(data) > energy:
		return false
	if toll < _card_toll_requirement(data):
		return false
	# Card-level toll_cost (2026-09-08, Owed pass) - see CardData.toll_cost's
	# own doc for why this is a SEPARATE check from _card_toll_requirement()
	# above: that one is "does this card even DO anything useful right now"
	# (Reckoning with 0 Toll is legal but pointless); this one is "can the
	# player afford to PLAY this card at all" (Owed's own 10 Toll is spent
	# outright, same gate energy_cost already is).
	if toll < data.toll_cost:
		return false
	return true

# The exact HP check TOLL_BLOCK's own resolution doubles block on -
# pulled into its own function (2026-08-27) so _card_condition_active()
# below can share it instead of re-typing the same "< half max HP"
# comparison a second time and risking the two silently drifting apart.
func _is_player_below_half_hp() -> bool:
	return RunState.player_hp < RunState.player_max_hp * 0.5

# Held Position's own condition - see _took_damage_last_turn's own doc
# for the tracking this reads, and CardEffect.EffectType.UNDAMAGED_BLOCK
# for the effect it gates. A plain field read, same trivial shape _is_
# player_below_half_hp() above has - pulled into its own function anyway
# so _card_condition_active() below and _resolve_card_effect()'s own
# UNDAMAGED_BLOCK case can't drift apart on what "the condition" means.
func _took_no_damage_last_turn() -> bool:
	return not _took_damage_last_turn

# THE single place "is this card's conditional effect live right now" is
# decided (2026-08-27, condition-indicator pass) - same shape as _is_
# card_playable()/_card_toll_requirement() above: one small function,
# derives a fact from effect_type, so a future conditional card extends
# THIS match instead of card.gd/card_text_styles.gd needing to know
# anything new (see DESIGN.md's own note on this pass for the fuller
# reasoning). Four cases today:
#   - TOLL_THRESHOLD_DAMAGE: true once toll clears effect.toll_threshold
#     - the exact same comparison battle.gd's own _resolve_card_effect()
#     uses to pick which number actually lands.
#   - TOLL_BLOCK (2026-08-27, Paid in Pain extension): true below half
#     HP, via the shared _is_player_below_half_hp() above - same
#     doubling condition _resolve_card_effect() checks, not a re-typed
#     copy of it.
#   - FIRST_CARD_DAMAGE (Left Hand fix): true while cards_
#     played_this_turn == 0 - "would be first if played right now," the
#     same test _resolve_card_effect() runs, just read a moment earlier
#     (before this card's own play would increment the counter).
#   - UNDAMAGED_BLOCK (Held Position fix, 2026-08-29): true via _took_no_
#     damage_last_turn() above - same "read the live/frozen state, not a
#     re-derived copy" discipline every other case here already follows.
# All four read the live value fresh here rather than a cached snapshot,
# so this can never show a stale answer relative to what playing the card
# would actually do right now. A card with more than one qualifying
# effect would report whichever one this loop finds first - not
# reachable today (every conditional card so far has exactly one
# qualifying effect), an unspecified-but-harmless ordering if that ever
# changes, same spirit as room_state.gd's own "first match wins" note on
# its escaping-enemy placement.
func _card_condition_active(data: CardData) -> bool:
	for effect in data.effects:
		if effect.effect_type == CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE:
			return toll >= effect.toll_threshold
		elif effect.effect_type == CardEffect.EffectType.TOLL_BLOCK:
			return _is_player_below_half_hp()
		elif effect.effect_type == CardEffect.EffectType.FIRST_CARD_DAMAGE:
			return cards_played_this_turn == 0
		elif effect.effect_type == CardEffect.EffectType.UNDAMAGED_BLOCK:
			return _took_no_damage_last_turn()
	return false

# Runs when a specific card in hand is clicked - this is where clicking
# becomes *playing*, or (for any card with requires_target set - see
# CardData's own doc) *arming*. See the class-level targeting vars' own
# comment for the full state machine; this function and _on_enemy_
# clicked() below are its only two entry points.
func _on_card_clicked(card_instance: Card, data: CardData) -> void:
	if battle_over or input_locked:
		return
	# Clicking ANY card while a target is already pending cancels that
	# first - clicking the same armed card again is how the player backs
	# out deliberately, and stops right there; clicking a DIFFERENT card
	# cancels the stale target and falls through to evaluate this new
	# click fresh, as if targeting had never started.
	if _pending_target_card_instance != null:
		var clicked_the_armed_card := card_instance == _pending_target_card_instance
		_cancel_targeting()
		if clicked_the_armed_card:
			return
	if _effective_energy_cost(data) > energy:
		card_instance.play_refused()
		AudioManager.play_sfx("card_refused")
		return
	if toll < _card_toll_requirement(data):
		# Same refusal feedback as an unaffordable energy cost - a card
		# gated on Toll should never be playable-but-useless (see this
		# card's own brief), so this is enforced here too, not just the
		# visual dim _is_card_playable() already drives.
		card_instance.play_refused()
		AudioManager.play_sfx("card_refused")
		return
	if toll < data.toll_cost:
		# Card-level toll_cost's own enforcement (2026-09-08, Owed pass) -
		# same "not just the visual dim" reasoning the _card_toll_
		# requirement() check just above already carries; _is_card_
		# playable() drives the greyed-out look, but nothing reads that
		# here, so the actual click has to re-check independently or a
		# greyed-out card would still play if clicked.
		card_instance.play_refused()
		AudioManager.play_sfx("card_refused")
		return
	if _card_needs_target(data):
		# ALWAYS arms and waits for an enemy click now, regardless of how
		# many enemies are alive (2026-08-25 - removed the old single-
		# enemy auto-play shortcut). With exactly one enemy alive,
		# _begin_targeting() below still calls set_targetable(true) on
		# it same as it would with several - the resulting highlight
		# pulse is what reads as "this is the presumptive target," not a
		# skipped click.
		_begin_targeting(card_instance, data)
		return
	# This card doesn't target anything - target stays null, and
	# _resolve_card_effect() never reads it.
	_play_card(card_instance, data, null)

# Dead-center of the current viewport, at armed_card_center_y_px - see
# that export's own doc for why X is computed here rather than stored
# alongside it.
func _armed_card_center_position() -> Vector2:
	return Vector2(get_viewport().get_visible_rect().size.x / 2.0, armed_card_center_y_px)

# Arms `card_instance`, waiting for a target click - see _on_enemy_
# clicked()/_cancel_targeting() for how this resolves or unwinds. No
# energy spent, no discard, card stays fully in hand until a target is
# actually chosen.
func _begin_targeting(card_instance: Card, data: CardData) -> void:
	_pending_target_card_instance = card_instance
	_pending_target_data = data
	_snapped_enemy = null
	card_instance.set_armed(true, _armed_card_center_position())
	for combatant in _living_enemies():
		combatant.instance.set_targetable(true)
	target_line.start(card_instance)

# Un-arms the card and un-highlights every living enemy, then clears the
# state machine back to "nothing pending." Shared by every cancellation
# path AND by a successful resolution (see _on_enemy_clicked()) - a
# chosen target needs the highlight turned off too, not just an
# abandoned one.
#
# FIXED (2026-08-26) - this used to iterate the raw `enemies` array
# (every combatant ever spawned, defeated or not), on the assumption
# that set_targetable(false) on an already-faded-out enemy was a
# harmless no-op. It isn't: _stop_targetable_pulse() unconditionally
# sets visual_container.modulate = Color(1,1,1,1), which stomps the
# alpha play_defeat_sequence() had faded to 0 - a defeated enemy that
# was never made targetable in the first place (_begin_targeting() only
# ever loops _living_enemies(), same as here now) would still get
# un-targetabled here, silently un-fading it back to fully visible.
# Reported live: killing the Beachwrack first, then targeting/attacking
# the Tideworn, made the dead Beachwrack's sprite reappear - every
# subsequent _cancel_targeting() call (armed-then-cancelled, or armed-
# then-resolved) was the trigger. _living_enemies() matches what
# actually got turned ON, so nothing here can un-fade a corpse anymore.
func _cancel_targeting() -> void:
	if _pending_target_card_instance:
		_pending_target_card_instance.set_armed(false)
	for combatant in _living_enemies():
		combatant.instance.set_targetable(false)
	if _snapped_enemy != null:
		_snapped_enemy.instance.set_snap_highlight(false)
	_pending_target_card_instance = null
	_pending_target_data = null
	_snapped_enemy = null
	target_line.stop()

# Connected once per enemy at spawn time (see _spawn_enemies()) - a click
# on any enemy silhouette funnels here regardless of whether targeting is
# even active, so this is also where "clicked an enemy while nothing is
# armed" quietly does nothing.
func _on_enemy_clicked(combatant: EnemyCombatant) -> void:
	if battle_over or input_locked or _pending_target_card_instance == null:
		return
	if combatant.is_defeated:
		return
	var card_instance := _pending_target_card_instance
	var data := _pending_target_data
	_cancel_targeting()
	_play_card(card_instance, data, combatant)

# Only does anything while targeting is active - drives the target
# line's per-frame snap state (see _update_snap_target() below).
func _process(_delta: float) -> void:
	if _pending_target_card_instance == null:
		return
	_update_snap_target()

# Decides which living enemy (if any) the target line is currently
# snapped to, and feeds TargetLine accordingly (see target_line.gd's own
# set_target()/clear_target()). A SEPARATE, much tighter test than what
# actually resolves a click (_on_enemy_clicked(), driven by Godot's own
# gui_input on hover_area, never reads _snapped_enemy or this function
# at all) - see enemy.gd's get_snap_region_global() and snap_margin_px's
# own doc for why the two regions are deliberately no longer the same
# rect (they used to be: this function used to just test hover_area
# directly, which was wide enough that the line snapped almost the
# instant a card was armed near any enemy - this feature's own brief).
#
# Hysteresis: once _snapped_enemy is set, it's only tested against ITS
# OWN region grown by snap_release_hysteresis_px (the release boundary,
# a little further out) - a cursor sitting right at snap_margin_px's own
# edge can't flicker in and out every frame, since leaving now requires
# crossing the larger boundary, not the one that let it in. Only once
# nothing is currently snapped does this scan every living enemy's
# tighter entry region (get_snap_region_global() with the default
# false) looking for a new one.
func _update_snap_target() -> void:
	var mouse_pos := get_viewport().get_mouse_position()
	var previously_snapped := _snapped_enemy
	if _snapped_enemy != null:
		var still_snapped := not _snapped_enemy.is_defeated and _snapped_enemy.instance.get_snap_region_global(true).has_point(mouse_pos)
		if not still_snapped:
			_snapped_enemy = null
	if _snapped_enemy == null:
		for combatant in _living_enemies():
			if combatant.instance.get_snap_region_global().has_point(mouse_pos):
				_snapped_enemy = combatant
				break
	# The rim highlight (see enemy.gd's set_snap_highlight() - replaces
	# the target line's old endpoint reticle) only needs touching on an
	# actual CHANGE of snapped enemy, not every frame - unlike target_
	# line.set_target() below, whose anchor position doesn't need a
	# change guard here (TargetLine's own set_target()/clear_target()
	# already no-op appropriately).
	if _snapped_enemy != previously_snapped:
		if previously_snapped != null:
			previously_snapped.instance.set_snap_highlight(false)
		if _snapped_enemy != null:
			_snapped_enemy.instance.set_snap_highlight(true)
	if _snapped_enemy != null:
		target_line.set_target(_snapped_enemy.instance.get_target_anchor_position())
	else:
		target_line.clear_target()

# The actual "play this card" tail - spend energy, move it to discard/
# consumed, remove its on-screen instance, resolve its effects against
# `target` (null for anything that doesn't need one). Shared by both
# ways a card can finish resolving: immediately (requires_target false,
# see _on_card_clicked()) or after a target was chosen
# (_on_enemy_clicked()).
func _play_card(card_instance: Card, data: CardData, target: EnemyCombatant) -> void:
	energy -= _effective_energy_cost(data)
	# CardData.toll_cost's own spend (2026-09-08, Owed pass) - through the
	# existing _set_toll() chokepoint, same as every other Toll mutation in
	# this file, so RunLogger's own accrual/peak tracking stays correct
	# (see _set_toll()'s own doc: a spend is a negative delta, which that
	# function already ignores for accrual purposes regardless of source -
	# SELF, its own default, is exactly as correct here as any other tag).
	# _is_card_playable()/_on_card_clicked() have already confirmed
	# toll >= data.toll_cost before this ever runs, so this can't go
	# negative in practice.
	if data.toll_cost > 0:
		_set_toll(toll - data.toll_cost)
	# TOLL_THRESHOLD_FREE_CARD's own consumption (see trinket_modifier.gd
	# and _effective_energy_cost()'s own note) - the flag applies to
	# WHATEVER card is actually played next, no player choice about
	# which, so this clears unconditionally on every real play rather
	# than checking which card it was. Harmless when the flag was
	# already false (this is just a false-to-false no-op then).
	_trinket_free_card_armed = false
	# STANCE is treated as skill-shaped for every play-feel decision in
	# this function (2026-08-28, card-type-plumbing pass) - computed once,
	# reused at every site below that used to read `!= SKILL`/`== SKILL`
	# bare, so a reader doesn't have to independently re-derive "and
	# STANCE too" at each one. Playing a stance is not a swing: no attack
	# nudge, no immediate-fire sfx, and the same commit-and-exit hold a
	# Skill gets instead of vanishing instantly - see this pass's own
	# brief for why (a Stance has nothing else carrying its own "this
	# landed" moment, same reasoning the original SKILL commit-and-exit
	# pass gave below).
	var is_skill_shaped_card := data.card_type == CardData.CardType.SKILL or data.card_type == CardData.CardType.STANCE
	# A small forward nudge on the Wanderer's own silhouette, ATTACK cards
	# only - see player_battle_visual.gd's play_attack_nudge() for why
	# card_type is the right signal (same one weapon scoping already
	# uses). Fired here, not awaited, and NEVER delayed by impact_delay
	# (see CardData's own doc) even for a card that sets one - this is
	# the swing, not the impact, and has to start the instant the card is
	# confirmed played to fill the gap before the hit lands, same
	# telegraphing beat enemy.gd's own play_attack_lunge() fires on for
	# the reverse direction. Already excludes STANCE by construction
	# (an explicit == ATTACK gate, not a != SKILL one) - no change needed
	# here for the skill-shaped-Stance pass above, just confirming it.
	if data.card_type == CardData.CardType.ATTACK:
		player_battle_visual.play_attack_nudge()
	# Always fires immediately now, regardless of impact_delay (2026-08-25
	# correction - see impact_delay's own doc) - this used to wait for a
	# nonzero impact_delay and defer the sound to land together with the
	# damage number/HP change/hit reaction instead, on the assumption the
	# clip was a short impact-only cue that shouldn't announce the hit
	# before it's seen. Guillotine's own play_sfx is a single wind-up-
	# then-impact clip now (a real "woosh"), not an impact-only one - it
	# has to START here, at the same instant as the attack nudge above, so
	# its own wind-up actually FILLS the impact_delay wait instead of
	# playing a second time (from its own beginning) after that wait
	# already elapsed. See _apply_card_effects() below, which no longer
	# plays this a second time once the delay is over.
	#
	# Skill-shaped cards (SKILL and now STANCE) do NOT fire here
	# (2026-08-26, commit-and-exit pass; STANCE folded in 2026-08-28) -
	# see the branch further down, which fires this same line once the
	# card's own commit push has actually landed, so the sound registers
	# together with the effect it's for instead of a beat before the card
	# even starts reacting. Attack timing above is completely unchanged.
	if data.card_type == CardData.CardType.ATTACK:
		AudioManager.play_sfx(data.play_sfx if data.play_sfx != "" else "card_play")
	print("Played %s" % data.card_name)
	# Clears Leviathan's mark, if this card happened to carry one
	# (2026-08-29, mark attack pass) - see CardData.marked_cost_modifier's
	# own doc: "clears when the card is played" applies to any card, not
	# just ones the mark attack itself set, and 0 is already a no-op for
	# every card that was never marked, so this needs no guard.
	data.marked_cost_modifier = 0
	hand.erase(data)
	match data.removal_scope:
		CardData.RemovalScope.CONSUMED:
			run_removed_pile.append(data)
			RunState.remove_card_from_deck(data) # Gone for the rest of the run, not just this fight.
			_update_deck_button()
		CardData.RemovalScope.SPENT:
			# Deliberately does NOT call RunState.remove_card_from_deck() -
			# see spent_pile's own doc above. That omission is the entire
			# mechanism a SPENT card returning next fight rests on.
			spent_pile.append(data)
		CardData.RemovalScope.NONE:
			discard_pile.append(data)
	# The CardData itself is already correctly filed into discard_pile/
	# run_removed_pile/spent_pile above regardless of anything that
	# happens to the VISUAL card instance below - a card can never be
	# "stranded outside its pile" by the commit/exit animation, since that
	# game-state bookkeeping doesn't wait on it at all.
	if _hovered_card_instance == card_instance:
		# Played while still hovered - mouse_exited won't reliably fire on
		# a node that's about to be freed, so this clears the dangling
		# reference explicitly rather than trusting the signal to catch
		# it. The card itself is leaving hand for good here (not just
		# losing hover), so this clears its _description_overrides outright
		# rather than merely restoring - matches clear_description_
		# overrides()'s own "explicit, not a refresh side effect" contract
		# (see card.gd). Moot in practice since the instance is about to be
		# freed, but matches the same clearing rule every other hand-exit
		# point follows rather than being a silent exception.
		card_instance.clear_description_overrides()
		_hovered_card_instance = null
		_hovered_card_data = null
	# Skill-shaped cards (SKILL and now STANCE - see is_skill_shaped_card's
	# own doc above) get a short commit-and-exit beat instead of vanishing
	# instantly (2026-08-26 - see card.gd's own play_commit()/play_exit()
	# doc for the full reasoning: an Attack already gets its own "this
	# landed" moment for free from targeting/impact/enemy flinch, a Skill
	# (or Stance) has nothing else carrying it). ATTACK keeps the exact
	# original instant-removal behavior below, untouched.
	if is_skill_shaped_card:
		await card_instance.play_commit()
		# is_instance_valid guards every resume point past an await in
		# this branch (see the two further down too) - if the battle
		# ended (or anything else freed this card) while the commit push
		# was mid-flight, there's nothing left to fire SFX on/hold/exit,
		# and every OTHER piece of state below (energy, hand/pile arrays,
		# chain_triggers, RunLogger) was already committed synchronously
		# above regardless, so there's nothing left to strand.
		if not is_instance_valid(card_instance):
			return
		AudioManager.play_sfx(data.play_sfx if data.play_sfx != "" else "card_play")
	else:
		card_instance.queue_free() # Removes the card's visuals from the scene.
	# Whether THIS play triggers the chain payoff - read before _update_
	# chain_state() below clears it, so a Closer played while a chain is
	# live still triggers even though the flag is about to flip false.
	var chain_triggers := data.chain_role == CardData.ChainRole.CLOSER and chain_empowered
	RunLogger.log_card_played(data.card_name, _chain_note_for(data) if chain_triggers else "")
	# Awaited (2026-08-23, for Guillotine's own multi-hit stagger - see
	# _apply_card_effects()'s own note) so a chain payoff below can't
	# start until every one of THIS card's own hits has actually landed.
	# Energy/hand/pile state was already updated synchronously above,
	# before this - only the trailing label refreshes and the chain
	# payoff wait on it. For a skill-shaped card (SKILL or STANCE), this is
	# also the effect resolving DURING the commit hold (the card is still
	# visually up at its pushed pose right now - see play_commit() above) -
	# block/heal/draw numbers land while the card is held, not after it's
	# gone.
	await _apply_card_effects(data, target)
	# Selfeater's own per-attack drain (2026-08-28, wired only after this
	# pass's own victory/defeat-sequencing report confirmed it's safe) -
	# checked HERE, after the await above, not earlier: _apply_card_
	# effects() already ran every one of this card's damage effects, and
	# if the last one killed the last enemy, _on_all_enemies_defeated() ->
	# _close_out_battle() already ran SYNCHRONOUSLY (before this line -
	# see that report for exactly why that's reliable, not a race) and
	# set battle_over true. "Damage resolves first, then victory is
	# checked, then the HP drain resolves" IS this exact ordering - a
	# winning blow skips the drain entirely by never reaching the call
	# below. ATTACK-only: Selfeater is itself a STANCE card, so playing it
	# never taxes itself.
	if not battle_over and data.card_type == CardData.CardType.ATTACK:
		_apply_attack_hp_drain()
	# Counts THIS play only after its own effects have fully resolved (see
	# cards_played_this_turn's own doc) - so a FIRST_CARD_DAMAGE effect
	# checking the counter DURING the await above still sees the count
	# from before this card, not one that already includes itself.
	cards_played_this_turn += 1
	if is_skill_shaped_card:
		if not is_instance_valid(card_instance):
			return
		# The rest of the hold, past whatever _apply_card_effects() itself
		# just took (typically ~instant for a Skill's own effects - no
		# multi-hit stagger, no impact_delay wind-up, both DAMAGE-only
		# concerns) - see skill_commit_hold_sec's own doc for why this is
		# a real, separate wait rather than assuming effect resolution
		# alone reads as a hold.
		await get_tree().create_timer(card_instance.skill_commit_hold_sec).timeout
		if is_instance_valid(card_instance):
			# Fire-and-forget on purpose (2026-08-26 - see this feature's
			# own brief): everything below this point (chain payoff, hand
			# spacing/affordability, energy/pile labels) reflects THIS
			# card having been played, not its own visual exit still
			# playing out - and critically, nothing here or in _on_card_
			# clicked() checks any "is a card mid-exit" flag, so a second
			# card can be clicked and played immediately regardless of
			# whether this one's exit tween has finished.
			card_instance.play_exit()
	# The Closer's own effects above resolve completely unmodified - its
	# printed damage is never boosted (see card_data.gd's own chaining
	# note for why: this is meant to read as a chain COMPLETING, not a
	# card being buffed). The payoff is a second, separate hit instead -
	# see _trigger_chain_payoff() for why it's structured as its own
	# effect resolution rather than a value added here. Called fire-and-
	# forget (not awaited) - it awaits its own delay internally, and
	# nothing below this point (chain state, hand spacing/affordability,
	# energy/pile labels) should wait on that; those all reflect THIS
	# card having been played, not the payoff that's about to follow it.
	if chain_triggers:
		_trigger_chain_payoff(target, data)
	_update_chain_state(data)
	_update_hand_spacing()
	_update_hand_fan()
	# Spending energy can make other cards still in hand unaffordable now,
	# so every remaining card needs to be re-checked, not just this one.
	_update_hand_affordability()
	_update_energy_label()
	_update_pile_labels()

# A short human-readable description of what a Closer's chain payoff is
# ABOUT to do, for RunLogger only - resolved the exact same way
# _trigger_chain_payoff() itself will (this card's own chain_followup_
# effect, falling back to the shared default), so the log always
# describes the payoff that's actually going to fire, never a guess.
func _chain_note_for(data: CardData) -> String:
	var followup: CardEffect = data.chain_followup_effect if data.chain_followup_effect != null else _chain_payoff_effect
	match followup.effect_type:
		CardEffect.EffectType.DAMAGE:
			return "chain: +%d dmg" % followup.value
		CardEffect.EffectType.HEAL:
			return "chain: refund %d HP" % followup.value
		CardEffect.EffectType.STUN:
			return "chain: Stoppage"
		_:
			return "chain"

# The chain's own hit - a completely separate resolution from the
# Closer's own effects above, not a value folded into them, which is
# what actually makes "the chain completing" a distinct beat from "the
# card doing its normal thing" rather than just a bigger number on one
# card play. Waits chain_payoff_delay_sec before resolving AT ALL - not
# a delay on the payoff's own visuals after an instant resolution, a
# delay on the trigger itself, so the closer's hit and the chain's hit
# are genuinely two separate events in time, not one event with a
# late-arriving flourish (see enemy.gd's flash_damage()'s own note,
# which used to own a smaller version of this delay before it moved
# here).
#
# Routes through _resolve_card_effect() (chain_payoff=true, for the
# impact-feedback tier only - see its own note) exactly the same way
# any of the Closer's own effects just did. WHICH CardEffect: the
# played card's own chain_followup_effect (CardData - see its own doc)
# if it set one, otherwise Battle's shared default (_chain_payoff_
# effect, a flat bonus-damage hit) - see card_data.gd's own note for why
# a per-Closer payoff needed zero new resolution code, only a new field
# to read. No Closer sets a non-DAMAGE payoff today (Bite Down's own
# HEAL-type refund was removed 2026-08-26, see DESIGN.md's Wanderer
# entry) but the match below still resolves HEAL/BLOCK/SELF_DAMAGE/DRAW
# payoffs correctly - a future card can set one without touching this
# function.
#
# The "corpse doesn't get a second hit" guard only makes sense for a
# payoff that actually needs a living target - DAMAGE, obviously, and
# STUN (see card_effect.gd) the same way: cancelling a dead enemy's next
# turn has nothing left to cancel. A non-targeted payoff (a future HEAL-
# type refund, say) has nothing to do with whether the enemy's still
# standing, and skipping it in that case would be a real bug: the player
# would lose their refund specifically for having dealt ENOUGH damage to
# finish the fight, exactly backwards from what "pay correctly, get it
# back" should mean. Scoped to DAMAGE/STUN specifically, not "any payoff
# at all."
func _trigger_chain_payoff(target: EnemyCombatant, data: CardData) -> void:
	await get_tree().create_timer(chain_payoff_delay_sec).timeout
	if battle_over:
		return
	var followup: CardEffect = data.chain_followup_effect if data.chain_followup_effect != null else _chain_payoff_effect
	var needs_living_target := followup.effect_type == CardEffect.EffectType.DAMAGE or followup.effect_type == CardEffect.EffectType.STUN
	if needs_living_target and target.is_defeated:
		return
	followup = _weapon_modified_chain_payoff(followup)
	RunLogger.log_chain_payoff_fired()
	# Its own RallyWindow (2026-08-26, rally-recovery-rework), separate
	# from the Closer card's own - see RallyWindow's own doc for why: the
	# payoff is a structurally separate hit (this function's own header
	# already treats it that way), so it gets its own shot at recovery
	# rather than being folded into whatever the Closer's own hit already
	# paid out.
	_resolve_card_effect(followup, target, true, null, RallyWindow.new())

# Applies an equipped weapon's CHAIN_PAYOFF_DAMAGE modifier to the
# payoff about to resolve, if one is equipped and the payoff is itself
# DAMAGE-type - a HEAL-type payoff (no card sets one today, see card_
# data.gd's own note) would be left untouched, same "a weapon about
# striking harder shouldn't inflate a sustain effect" reasoning as
# weapon_modifier.gd's own note. Builds a
# NEW CardEffect rather than mutating `followup` in place - `followup`
# is either Battle's own shared _chain_payoff_effect or a specific
# card's chain_followup_effect resource, and either one getting
# permanently bumped here would leak into every future payoff, not just
# this one.
func _weapon_modified_chain_payoff(followup: CardEffect) -> CardEffect:
	var weapon: WeaponData = RunState.equipped_weapon
	if weapon == null or weapon.modifier == null:
		return followup
	if weapon.modifier.kind != WeaponModifier.Kind.CHAIN_PAYOFF_DAMAGE:
		return followup
	if followup.effect_type != CardEffect.EffectType.DAMAGE:
		return followup
	var boosted := CardEffect.new()
	boosted.effect_type = followup.effect_type
	boosted.value = followup.value + weapon.modifier.value
	return boosted

# --- Chaining (see card_data.gd's own note) ---
#
# The one place chain_empowered actually changes - called once per card
# play, right after its effects (and, for a Closer consuming a live
# chain, the payoff - see _trigger_chain_payoff()) have already
# resolved. NONE-role cards (everything except Slash/Heavy Blow today)
# fall through both match cases untouched - chain_empowered persists
# across them exactly as the brief requires ("the next Closer played
# that same turn," not "the very next card").
func _update_chain_state(played_data: CardData) -> void:
	match played_data.chain_role:
		CardData.ChainRole.OPENER:
			chain_empowered = true
			RunLogger.log_opener_played()
		CardData.ChainRole.CLOSER:
			chain_empowered = false
	_refresh_chain_indicators()

# Every CLOSER-role card still in hand needs to agree with chain_
# empowered's current value - called after every play (state may have
# just changed) and whenever a new Closer is drawn (see _add_card_to_
# hand_display()). OPENER/NONE-role cards are skipped entirely: their
# own display never depends on chain state (see card.gd's _chain_role_
# suffix()/chain_glow), so there's nothing to refresh on them.
func _refresh_chain_indicators() -> void:
	for child in hand_container.get_children():
		if child is Card and child.card_data.chain_role == CardData.ChainRole.CLOSER:
			child.set_chain_available(chain_empowered)

# Playtest aid, not a real game mechanic - see battle.tscn's
# DevDamageButton. Routes through the exact same _deal_damage_to_enemy()
# a card's DAMAGE effect uses, so it respects block, flashes/plays the
# normal hit sound, and can trigger a real victory - a fast way to reach
# late-fight/post-victory states without hand-editing a card's numbers
# (see resources/cards/slash.tres's git history for the workaround this
# replaces). Always targets the first living enemy - this is a blunt dev
# tool, not something that needs its own targeting flow.
const DEV_DAMAGE_AMOUNT := 100

func _on_dev_damage_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	_deal_damage_to_enemy(_living_enemies()[0], DEV_DAMAGE_AMOUNT, false, false, false, RallyWindow.new()) # Dev-only, not player-facing - a throwaway window is simplest.

# Playtest aid for the status-effect scaffolding (see DESIGN.md's Status
# Effects section) - not a real game mechanic, same spirit as
# DevDamageButton above, and using the SAME dev-only "safe to click
# repeatedly" tolerance (a status ticking an enemy's own HP down is an
# accepted risk of dev testing, exactly like DevDamageButton already
# accepts defeating one). Targets the first living enemy - same
# _living_enemies()[0] convention DevDamageButton itself uses - rather
# than the player, so both dev buttons point at the same target and a
# TICK status's damage is visibly attributable to this button, not
# confused with an enemy's own attack landing on the player.
# _apply_status() itself doesn't care which list it's handed; this is
# just a convenient choice for eyeballing the result quickly.
const TEST_STATUS_DATA := preload("res://resources/statuses/test_effect.tres")

func _on_dev_status_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	var target := _living_enemies()[0]
	_apply_status(target.statuses, TEST_STATUS_DATA)
	target.instance.update_statuses(target.statuses)

# Playtest aid for the escape resolution below (see _on_battle_escaped())
# - not a real game mechanic yet (no distance/flee cost, no enemy-side
# trigger), same "safe to click, dev-only" spirit as DevDamageButton/
# DevStatusButton above. Fire-and-forget, same as _on_enemy_defeated()
# calling _on_all_enemies_defeated() - _on_battle_escaped() is itself
# async (it awaits the shared post-battle beat), and nothing here needs
# to wait on that.
func _on_dev_escape_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	_on_battle_escaped()

# Playtest aid for the card upgrade service (see card_upgrade_service.gd)
# - lets the full gather/select/swap flow be exercised without a shop to
# sell it. No filter passed (every upgradeable deck card is eligible),
# same "safe to click, dev-only" spirit as the other Dev buttons above.
# Fire-and-forget: offer_upgrade() is itself async (it awaits the
# player's own selection), and this button doesn't need to block on it,
# same shape as _on_dev_escape_button_pressed() above awaiting nothing
# from the async call it kicks off. NOTE this only ever touches RunState.
# deck - a card upgraded mid-battle here has no effect on THIS fight's
# own draw/hand/discard piles (Battle copied them from RunState.deck
# once, at _start_battle() - see that function's own doc), same already-
# accepted behavior add_card_to_deck()/remove_card_from_deck() have; the
# change is visible next battle, or immediately via the Deck button.
func _on_dev_upgrade_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	_run_dev_upgrade()

func _run_dev_upgrade() -> void:
	var result := await CardUpgradeService.offer_upgrade()
	match result["outcome"]:
		CardUpgradeService.Outcome.UPGRADED:
			var old_card: CardData = result["old_card"]
			var new_card: CardData = result["new_card"]
			print("Upgraded %s -> %s" % [old_card.card_name, new_card.card_name])
		CardUpgradeService.Outcome.CANCELLED:
			print("Card upgrade cancelled.")
		CardUpgradeService.Outcome.NO_ELIGIBLE_CARDS:
			print("No eligible cards to upgrade.")

# --- Dev: Add Card (2026-08-28) ---
#
# A GENERAL card injector, not a Selfeater-specific button - Selfeater
# and Siphon are both hard to reach through ordinary play today (neither
# is in the starter deck, and picking either up as a reward is down to
# chance), and there will be more cards in the same boat as this project
# grows. Rather than a one-off "Add Selfeater" button, this lists every
# card this project actually has and lets a dev add any of them,
# repeatedly, to RunState.deck directly.
#
# DEV AFFORDANCE - same convention every other Dev button on this screen
# already follows (see dev_encounter_picker.gd's own header for the full
# statement of it): a plainly-labeled, always-visible button, no release-
# build gating anywhere in this project to hook into.
#
# Reuses deck_viewer (this screen's own instance, already used by the
# ordinary Deck button - see _on_deck_button_pressed()) in selection
# mode, the same "DeckViewer, not a new overlay" reasoning card_upgrade_
# service.gd's own header gives for its own card-choice UI - a dev
# picking from a real, familiar card grid (full faces, current type/
# removal-scope badges and all) beats a plain text list, and this is the
# SAME grid every other card-picking flow in the game already uses.
# UNLIKE CardUpgradeService's one-shot pick-then-close flow, this does
# NOT disconnect after the first pick - "multiple adds should work, so
# Selfeater's stacking can be tested" means the picker has to survive
# repeated clicks on the same card, closing only when the dev actually
# closes it.
func _on_dev_add_card_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	_run_dev_add_card()

# Explicit known folders, not one recursive walk - DirAccess.get_files()
# doesn't recurse (same limitation dev_encounter_picker.gd's own
# SUNKEN_WORKS_ENCOUNTER_FOLDER note already documents for encounters),
# so every folder that actually holds addable cards needs its own entry.
# Deliberately EXCLUDES resources/cards/classes/wanderer/retired/ (cut
# content - same "never scanned, anywhere" convention EnemyPool/
# EncounterPool already follow for their own retired folders) and
# resources/cards/upgrades/ (an upgrade variant is meant to be reached by
# upgrading a base card via CardUpgradeService, never drafted directly -
# see card_data.gd's own upgrades doc; listing Slash+ next to Slash
# here would just be confusing, not useful).
const DEV_ADD_CARD_FOLDERS: Array[String] = [
	"res://resources/cards/",
	"res://resources/cards/classes/wanderer/",
	"res://resources/cards/classes/wanderer/npc_offers/",
	"res://resources/cards/classes/samurai/",
]

func _run_dev_add_card() -> void:
	var cards := _gather_dev_addable_cards()
	if deck_viewer.card_selected.is_connected(_on_dev_add_card_selected):
		deck_viewer.card_selected.disconnect(_on_dev_add_card_selected)
	deck_viewer.card_selected.connect(_on_dev_add_card_selected)
	# Title says "Deck", not "Hand" or "Battle" - deliberately, since this
	# card takes effect in RunState.deck ONLY. Battle already copied its
	# own draw/hand/discard piles from RunState.deck once, at _start_
	# battle() (see that function's own doc) - a card added here mid-fight
	# has no effect on THIS fight, same already-accepted behavior mid-
	# battle upgrades/removals have (see _update_deck_button()'s own doc).
	# It's drawable starting next battle, or visible immediately via the
	# ordinary Deck button.
	deck_viewer.open_cards(cards, "Dev: Add Card to RunState.deck (next battle, not this one)", true)
	while deck_viewer.visible:
		await deck_viewer.visibility_changed
	deck_viewer.card_selected.disconnect(_on_dev_add_card_selected)

func _on_dev_add_card_selected(data: CardData) -> void:
	RunState.add_card_to_deck(data)
	_update_deck_button()
	print("Dev: added %s to RunState.deck (deck now %d cards)" % [data.card_name, RunState.deck.size()])

# Re-scans disk every time this opens rather than caching - same "cheap
# enough that caching would only risk going stale for no real benefit"
# reasoning CardUpgradeService's own _gather_eligible() already uses;
# this is a dev tool opened rarely, over a handful of small folders.
func _gather_dev_addable_cards() -> Array[CardData]:
	var cards: Array[CardData] = []
	for folder in DEV_ADD_CARD_FOLDERS:
		var dir := DirAccess.open(folder)
		if dir == null:
			push_error("Dev: Add Card folder not found: %s" % folder)
			continue
		for file_name in dir.get_files():
			if file_name.ends_with(".tres"):
				cards.append(load(folder + file_name))
	return cards

# Guarded the same way cards/End Turn are (battle_over/input_locked) even
# though DeckViewer pauses the SceneTree the instant it opens - not
# because pausing fails to freeze battle.gd itself (it does - Battle has
# no PROCESS_MODE_ALWAYS override, so it stops the moment the tree
# pauses), but because get_tree().create_timer() defaults to
# process_always = true, meaning the enemy-turn pauses in
# _run_enemy_turn() would keep ticking - and the enemy's turn would
# resolve - while DeckViewer sits open on top if this were allowed to
# open mid-resolution. Blocking the open during input_locked (the exact
# window those timers run in) sidesteps that entirely. A click while
# targeting is active cancels instead of opening the deck - same "click
# elsewhere" cancel every other interactive Control gets, since a raw
# background click never reaches this (see _unhandled_input()) but a
# click ON a Button does.
func _on_deck_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	deck_viewer.open_deck()

# Catches a click that landed on neither a card nor an enemy nor any
# other interactive Control - i.e. genuinely empty background - while a
# target is pending, and cancels. Every OTHER Control that could
# otherwise swallow a click before it gets here already has its own
# explicit cancel-first guard (_on_end_turn_button_pressed(),
# _on_deck_button_pressed(), _on_dev_damage_button_pressed(), and
# _on_card_clicked() for a different/the same card) - this is
# specifically the background fallback, which is why HandContainer and
# EnemyZone both need mouse_filter = IGNORE in battle.tscn: neither has
# any click behavior of its own, so without that they'd silently consume
# a click that landed in the gaps around a card or silhouette instead of
# letting it reach here.
#
# Also the Escape-key cancel path (2026-08-25) - "ui_cancel" is Godot's
# own built-in action, bound to Escape by default with no project.godot
# entry needed. A right-click ON the armed card or a targetable enemy
# never reaches here at all (both are Controls with the default STOP
# mouse filter, so the GUI layer swallows the event before it can become
# "unhandled") - see card.gd's/enemy.gd's own right_clicked signal for
# how those two spots cancel instead.
func _unhandled_input(event: InputEvent) -> void:
	if _pending_target_card_instance == null:
		return
	if event is InputEventMouseButton and event.pressed:
		_cancel_targeting()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_cancel_targeting()
		get_viewport().set_input_as_handled()

# Walks a played card's effects array (CardData.effects) and resolves
# each one in order. A card just declares a list of {effect_type, value}
# pairs; Battle is what decides what each type actually does - same
# centralized-logic reasoning as energy above, extended to cover every
# kind of thing a card can do rather than just damage/block. `target` is
# only ever read by the DAMAGE branch (see _resolve_card_effect()) - null
# is perfectly legal for a card with no targeted effect. A Closer's own
# effects always resolve through here UNMODIFIED, chain-empowered or
# not - see _trigger_chain_payoff() for where the actual chain bonus
# lives now (a separate resolution, not a value added here).
#
# Async (2026-08-23, for Guillotine's own 3-hit strike) so a run of
# consecutive hits on the same target can be staggered - see multi_hit_
# delay_sec below. Awaited by _play_card() specifically so the chain
# payoff (if this card triggers one) can't start its own delay/visuals
# until every one of THIS card's own hits has actually landed - without
# that, a fast enough multi_hit_delay_sec could let the payoff's impact
# overtake a still-pending third hit. The SAME await is what makes
# CardData.impact_delay's own wind-up (2026-08-27, see its own doc)
# correctly hold the chain payoff back too, with no separate change
# needed at that call site - the payoff already couldn't start until
# this whole function returns, and now "this whole function" includes
# waiting out the delay before anything below even begins.
func _apply_card_effects(data: CardData, target: EnemyCombatant) -> void:
	# The wind-up (2026-08-27, see CardData.impact_delay's own doc) - a
	# single wait, before anything about this card's effects resolves at
	# all, not one per effect/target. That's what makes "applied once
	# per card" structural rather than just a convention to remember:
	# there's no per-hit path left below for a delay to accidentally
	# repeat on. battle_over re-checked immediately after, same guard the
	# loop below already uses per-iteration - the player could die to a
	# status tick mid-wait, and the effects below shouldn't fire into a
	# battle that's already over (the sound already started back in
	# _play_card(), before any of this could be known - see its own doc
	# for why that's correct rather than a gap this guard should cover).
	if data.impact_delay > 0.0:
		await get_tree().create_timer(data.impact_delay).timeout
		if battle_over:
			return
		# No sound played here any more (2026-08-25 correction - see
		# _play_card()'s own doc and impact_delay's own doc) - play_sfx
		# already started back in _play_card(), at the moment this card
		# was played, specifically so its own wind-up fills THIS wait
		# rather than starting fresh only once it's over.
	# One window for this whole card (2026-08-26, rally-recovery-rework -
	# see RallyWindow's own doc) - every DAMAGE-ish effect below, AND any
	# weapon-reflect hit a SELF_DAMAGE effect triggers, contributes to
	# this SAME object, so a multi-hit card recovers off its largest hit
	# once, not the sum of every hit.
	var rally_window := RallyWindow.new()
	var hit_gap_index := 0
	for i in data.effects.size():
		if battle_over: # e.g. SELF_DAMAGE just killed the player mid-card.
			return
		var effect: CardEffect = data.effects[i]
		_resolve_card_effect(effect, target, false, data, rally_window)
		if _is_hit_effect(effect) and i + 1 < data.effects.size() and _is_hit_effect(data.effects[i + 1]):
			# Only between two hit-type effects back to back (Guillotine's
			# three DAMAGE entries) - an unrelated pair (Riposte's block-
			# then-strike, Bite Down's damage-then-self-damage) stays
			# exactly as fast as it's always been. Checked on the NEXT
			# effect too, not just this one, so the gap only appears where
			# there's actually a second hit about to follow. hit_gap_index
			# counts GAPS, not effect indices - it only advances here, so
			# it correctly means "which hit-to-hit gap is this" even for a
			# card that mixes hit and non-hit effects (Guillotine doesn't
			# today, but this stays right for one that does).
			var extra: float = multi_hit_delay_extra_sec[hit_gap_index] if hit_gap_index < multi_hit_delay_extra_sec.size() else 0.0
			await get_tree().create_timer(multi_hit_delay_sec + extra).timeout
			hit_gap_index += 1

func _is_hit_effect(effect: CardEffect) -> bool:
	return effect.effect_type == CardEffect.EffectType.DAMAGE or effect.effect_type == CardEffect.EffectType.TOLL_DAMAGE or effect.effect_type == CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE or effect.effect_type == CardEffect.EffectType.DAMAGE_ALL or effect.effect_type == CardEffect.EffectType.FIRST_CARD_DAMAGE or effect.effect_type == CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL

# One card effect in, the matching game action out. Adding a new
# EffectType later (see card_effect.gd) means adding one case here - this
# is the only place that needs to know what an effect type *does*. Only
# DAMAGE reads `target` - every other type is untargeted and ignores it,
# same as before targeting existed. chain_payoff is true only when
# _trigger_chain_payoff() below is the caller - it doesn't change WHAT
# resolves, only which impact-feedback tier a DAMAGE effect plays (see
# _deal_damage_to_enemy()'s own note). source_card is the CardData this
# effect came from, ONLY passed by _apply_card_effects() - a chain
# payoff's own hit (chain_payoff=true) never passes one, since a
# CATEGORY_DAMAGE weapon modifier is scoped to cards actually being
# played, not to a payoff resolving after the fact (see
# _trigger_chain_payoff()'s own, separate CHAIN_PAYOFF_DAMAGE handling).
# rally_window is ONLY passed by _apply_card_effects()/_trigger_chain_
# payoff() (see RallyWindow's own doc) - threaded through here so the
# DAMAGE-ish branches below and SELF_DAMAGE's weapon reflect all
# contribute to whichever single window this whole call belongs to.
func _resolve_card_effect(effect: CardEffect, target: EnemyCombatant, chain_payoff: bool = false, source_card: CardData = null, rally_window: RallyWindow = null) -> void:
	match effect.effect_type:
		CardEffect.EffectType.DAMAGE:
			# Same display/resolution-sync caveat as the enemy's own attack
			# path (see _resolve_enemy_intent()'s note) - a card's shown cost
			# and its printed damage number are static text on the card
			# face, not computed per-turn the way an enemy's intent display
			# is, so there's no equivalent "already displayed a smaller
			# number" risk here specifically. Still a no-op today either
			# way - no status sets category == MODIFIER yet.
			var amplified := _apply_status_modifiers(effect.value, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				amplified = _weapon_modified_value(amplified, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			_deal_damage_to_enemy(target, amplified, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.DAMAGE_ALL:
			# Same amplification as plain DAMAGE above, computed once for
			# the whole card rather than once per enemy hit - it's entirely
			# player/card-side (OUTGOING_DAMAGE status modifiers, the
			# card's own weapon CATEGORY_DAMAGE modifier), so recomputing
			# it per target would just repeat the same math. Each living
			# enemy still gets its own independent _deal_damage_to_enemy()
			# call, which is where TARGET-side modifiers (INCOMING_DAMAGE,
			# Outbound's own escape falloff) correctly apply per-enemy.
			var amplified_all := _apply_status_modifiers(effect.value, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				amplified_all = _weapon_modified_value(amplified_all, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			for enemy in _living_enemies():
				_deal_damage_to_enemy(enemy, amplified_all, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.BLOCK:
			_gain_player_block(effect.value)
		CardEffect.EffectType.ABSORB:
			_gain_absorb(effect.value)
		CardEffect.EffectType.UNDAMAGED_BLOCK:
			# effect.bonus_value ADDS on top of effect.value - contrast TOLL_
			# THRESHOLD_DAMAGE/FIRST_CARD_DAMAGE above, which REPLACE value
			# with threshold_value. Held Position's own text is explicit
			# ("gain 4 MORE"), so this can't reuse either the field or the
			# replace-shape those two share. Read here, at resolution time,
			# not the display-only _card_condition_active() copy above -
			# this is what actually decides how much block lands.
			var block_gained := effect.value
			if _took_no_damage_last_turn():
				block_gained += effect.bonus_value
			_gain_player_block(block_gained)
		CardEffect.EffectType.APPLY_STATUS:
			_apply_status(player_statuses, effect.status_data)
			player_battle_visual.update_statuses(player_statuses)
			_update_selfeater_visual()
			_update_hand_stance_indicators()
		CardEffect.EffectType.APPLY_STATUS_TO_TARGET:
			# See CardEffect.EffectType's own doc on this value - applies to
			# `target` (the SAME EnemyCombatant the DAMAGE branch above
			# reads), never player_statuses. requires_target must be true
			# on the source card or `target` is null here - an authored-
			# data requirement, not something this branch itself enforces.
			_apply_status(target.statuses, effect.status_data)
			target.instance.update_statuses(target.statuses)
			# Owed-applied logging (2026-09-08, Owed status pass) - by the
			# status's own default_magnitude (the stack count actually
			# granted), not effect.value (unused by this type - see its
			# own doc). load(), not preload - see _collect_owed()'s own
			# doc in battle.gd for why Owed specifically is loaded lazily
			# rather than joining the preloaded status consts. Compared by
			# resource identity, same as _find_status()/_apply_status()
			# everywhere else in this file - load() returns the same
			# cached instance preload() would for this exact path, so this
			# is the same comparison, not a weaker one.
			if effect.status_data == load("res://resources/statuses/owed.tres"):
				RunLogger.log_owed_applied(effect.status_data.default_magnitude)
		CardEffect.EffectType.SELF_DAMAGE:
			_deal_self_damage(effect.value)
			_reflect_self_damage(effect.value, target, rally_window)
		CardEffect.EffectType.DRAW:
			_draw_cards(effect.value)
		CardEffect.EffectType.HEAL:
			_heal_player(effect.value, chain_payoff)
		CardEffect.EffectType.TOLL_DAMAGE:
			# effect.value is unused here (see card_effect.gd's own doc) -
			# the amount is whatever Toll actually is right now, consumed
			# to 0 as part of resolving this, not an authored number. Same
			# modifier pipeline as ordinary DAMAGE above (the Toll consumed
			# is the BASE amount, then weapon/status damage modifiers still
			# apply on top) - Reckoning isn't meant to be a special exception
			# to how every other damage-dealing card interacts with the
			# rest of the game's systems, just a different way of arriving
			# at its own base number.
			var consumed := toll
			_set_toll(0)
			var amplified := _apply_status_modifiers(consumed, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				amplified = _weapon_modified_value(amplified, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			_deal_damage_to_enemy(target, amplified, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE:
			# Toll is read here as a CONDITION ONLY - no toll -= anywhere
			# in this case, and no update_toll() call either, because
			# nothing about the readout changes.
			# Compound (this type's first use) must leave Toll exactly
			# as it found it.
			var base_damage := effect.value
			if toll >= effect.toll_threshold:
				base_damage = effect.threshold_value
			var amplified := _apply_status_modifiers(base_damage, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				amplified = _weapon_modified_value(amplified, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			_deal_damage_to_enemy(target, amplified, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.FIRST_CARD_DAMAGE:
			# cards_played_this_turn is read here as a CONDITION ONLY, same
			# "no toll -= anywhere in this case" shape TOLL_THRESHOLD_DAMAGE
			# above follows for Toll - nothing about the counter changes
			# from resolving this effect (it only ever changes via _play_
			# card()'s own increment, once, after this whole card is done).
			var first_card_base_damage := effect.value
			if cards_played_this_turn == 0:
				first_card_base_damage = effect.threshold_value
			var first_card_amplified := _apply_status_modifiers(first_card_base_damage, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				first_card_amplified = _weapon_modified_value(first_card_amplified, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			_deal_damage_to_enemy(target, first_card_amplified, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.STUN:
			# effect.value is unused (see card_effect.gd's own doc) - a stun
			# doesn't scale, it either cancels the target's queued intent or
			# it doesn't. Routes through the SAME interrupt _check_pain_
			# turn_trigger() already uses for the Wardling's own pain turn
			# (see _apply_intent_interrupt()'s own note) - not a parallel
			# implementation. The sound plays HERE, not inside the shared
			# function, specifically so the Wardling's own HP-threshold pain
			# turn (which has never had a sound) doesn't silently gain one
			# just because this call path now also reaches the same code.
			AudioManager.play_sfx("chain_stoppage")
			# The momentary flash+shake reads as the payoff LANDING, distinct
			# from _apply_intent_interrupt()'s own shake below (which is on
			# the intent row, not the body) - see enemy.gd's Chain Payoff
			# Flourish export group for the full contrast with every other
			# reaction near it. Gated on chain_payoff (never true for the
			# Wardling's own pain turn, which never reaches this case at
			# all today - see this case's own note above) so a future
			# direct/non-chain STUN card wouldn't get it by accident.
			if chain_payoff:
				target.instance.play_chain_payoff_flourish()
			_apply_intent_interrupt(target, effect.combat_message)
		CardEffect.EffectType.TOLL_BLOCK:
			# Consumes its OWN fixed toll_cost, not "whatever Toll is" -
			# contrast TOLL_DAMAGE above. _card_toll_requirement() already
			# guaranteed toll >= toll_cost before this could be played, so
			# this never drives toll negative - update_toll() handles 0
			# correctly on its own now (ticks down to it and shows the
			# dimmed zero-state - see toll_display.gd's own _apply_zero_
			# state()), so a spend landing exactly on the full amount
			# needs no separate call.
			_set_toll(toll - effect.toll_cost)
			var block_gained := effect.value
			if _is_player_below_half_hp():
				block_gained *= 2
			_gain_player_block(block_gained)
		CardEffect.EffectType.TOLL_RETALIATE:
			# _find_status(), not just "is player_statuses empty" - a
			# future card could apply a DIFFERENT status alongside this
			# one, so "already primed" has to mean THIS specific status,
			# not "any status at all." Checked BEFORE the toll spend
			# below, guarding the whole block - this card's own brief
			# requires replaying while already primed to cost nothing,
			# not just to re-apply a no-op via status_data's own
			# StackRule.IGNORE (which would still leave the Toll already
			# gone by the time apply_stack() no-ops it).
			if _find_status(player_statuses, effect.status_data) == null:
				# Same toll-spend shape as TOLL_BLOCK above - see its own
				# note on why a single update_toll() call is enough even
				# when this lands exactly on 0. _card_toll_requirement()
				# already guaranteed toll >= toll_cost before this could
				# be played.
				_set_toll(toll - effect.toll_cost)
				_apply_status(player_statuses, effect.status_data)
				player_battle_visual.update_statuses(player_statuses)
		CardEffect.EffectType.SELF_DAMAGE_TOLL:
			# Floors the loss at 1 HP remaining BEFORE calling the shared
			# self-damage path - _deal_self_damage() itself has no such
			# floor (see plain SELF_DAMAGE above, which can kill), so
			# this effect computes its own safe amount first rather than
			# letting the normal path clamp at 0. Whatever DOES land
			# still goes through _deal_self_damage() as-is, so it's
			# still Rally-exempt, still ignores block, and still feeds
			# the ordinary per-HP-lost Toll accrual in _set_player_hp()
			# same as any other self-damage (see card_effect.gd's own
			# doc on this type for why the top-up below still lands on
			# a flat total either way).
			var before_hp := RunState.player_hp
			var floored_loss: int = mini(effect.value, before_hp - 1)
			if floored_loss > 0:
				_deal_self_damage(floored_loss)
				_reflect_self_damage(floored_loss, target)
			var actual_lost := before_hp - RunState.player_hp
			var toll_topup := effect.toll_gain - actual_lost
			if toll_topup > 0:
				# This top-up is its own real accrual (a positive delta
				# log_toll_change() counts same as any other - see its own
				# doc), separate from whatever _deal_self_damage() above
				# already accrued via _set_player_hp() - still SELF-sourced,
				# same as the self-damage it's topping up.
				_set_toll(toll + toll_topup, RunLogger.TollSource.SELF)
				_update_hand_affordability()
		CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL:
			# Same "capture spent amount, then spend it" shape TOLL_DAMAGE
			# above uses, except only the authored FRACTION of toll (not
			# all of it) - see card_effect.gd's own doc on toll_fraction.
			# The pool loses the raw `spent` amount; amplification below
			# only affects the damage DEALT, same split TOLL_DAMAGE makes.
			var spent := floori(toll * effect.toll_fraction)
			_set_toll(toll - spent)
			var fraction_amplified := _apply_status_modifiers(spent, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
			if not chain_payoff:
				fraction_amplified = _weapon_modified_value(fraction_amplified, source_card, WeaponModifier.Kind.CATEGORY_DAMAGE)
			for enemy in _living_enemies():
				_deal_damage_to_enemy(enemy, fraction_amplified, chain_payoff, false, false, rally_window)
		CardEffect.EffectType.GAIN_ENERGY:
			# Clamped at max_energy (2026-09-04, Kept Coin pass) - energy
			# itself has no data-layer cap (nothing before this ever added
			# to it, only ever _play_card()'s own subtraction), but
			# ResourceDisplay's own pip row is built to exactly max_energy
			# pips and _animate_refill() indexes straight into it with no
			# bounds check - an unclamped gain pushing current past
			# max_value would crash there, not just look wrong. This
			# respects that existing display-layer ceiling rather than
			# inventing a new gameplay one; nothing here stops max_energy
			# itself from being raised by something else later; this
			# effect just never exceeds whatever it currently is at
			# resolution time. No update_energy_label()/_update_hand_
			# affordability() call needed here - _play_card()'s own tail
			# (after _apply_card_effects() returns) already refreshes both
			# unconditionally on every play, the same way BLOCK/DAMAGE/
			# every other effect type above already relies on it.
			energy = mini(energy + effect.value, max_energy)

# THE single point every player BLOCK gain routes through - BLOCK and
# TOLL_BLOCK above both call this instead of touching player_block
# directly (they used to; this replaced two separate, identical `player_
# block += X; _update_player_panel(); AudioManager.play_sfx(...)` copies).
# Checked here, not by zeroing player_block after the fact once it's
# already been added - Full Weight's own brief is explicit about this:
# suppression has to mean the gain never happens, not "happens then gets
# undone," which would still show the block_gained sfx/panel flash for a
# gain that's supposed to not exist. NO_BLOCK_STATUS's own doc (see its
# preload above) covers why its duration makes this correctly cover the
# player's ENTIRE next turn. A future block SOURCE that isn't a CardEffect
# (an enemy-turn player reaction, a relic-like passive) would need to
# route through here too to respect this - nothing else in this file
# grants player_block today (confirmed: the only other player_block
# writes are the turn-start/battle-start resets to 0, never a gain).
func _gain_player_block(amount: int) -> void:
	if _find_status(player_statuses, NO_BLOCK_STATUS) != null:
		return
	player_block += amount
	_update_player_panel()
	AudioManager.play_sfx("block_gained")

# Absorb's own grant path (2026-09-05, Forbearance pass) - mirrors _gain_
# player_block() immediately above, MINUS its NO_BLOCK_STATUS check: Full
# Weight's own "no block next turn" debuff (overextended.tres) gates
# BLOCK specifically, not this separate pool, so nothing here checks for
# it - absorb_pool's own doc explains why. Reuses the existing
# "block_gained" cue rather than inventing a new one - same "generic
# mechanic slot" reuse convention audio_manager.gd's own heal/wind_up
# entries already establish for a new-but-kindred effect.
func _gain_absorb(amount: int) -> void:
	absorb_pool += amount
	_update_player_panel()
	AudioManager.play_sfx("block_gained")

# THE single point every Toll mutation routes through, with NO exceptions
# - accrual and spend alike (same shape as _gain_player_block() above,
# extracted for the same reason: six near-identical `toll = X; player_
# resource_cluster.update_toll(toll); RunLogger.log_toll_change(toll)`
# copies replaced with one). Takes the FINAL new value, not a delta -
# every call site already computed its own target value before this
# existed (toll + lost, toll - effect.toll_cost, 0, toll + toll_topup),
# so this only ever assigns and pushes, never recomputes anything itself.
#
# _start_battle()'s own `toll = 0` reset (2026-08-28, added here after
# confirming it's safe) is the one call site that fires before anything
# else in a fresh battle - its extra log_toll_change(0) call is a
# verified no-op: RunLogger._last_toll/_battle_toll_peak/_battle_toll_
# accrued all get unconditionally overwritten back to 0 by RunLogger.
# log_battle_start(), called later in this SAME synchronous function
# (no `await` between the two calls), so nothing ever observes the
# transient values this produces. The UI push is equally inert -
# battle.tscn is always a fresh scene reload per battle (never the same
# instance calling _start_battle() twice), so player_resource_cluster's
# own TollDisplay already shows 0 from its own _ready(), and update_
# toll(0)'s `if value == _displayed_value: return` guard no-ops.
#
# Also where TOLL_THRESHOLD_FREE_CARD's own upward-crossing check lives
# (2026-08-28, trinket pass) - checked here, not duplicated at any of
# the five call sites above, since this is the one place both the OLD
# and NEW value are already in hand for every Toll change regardless of
# source. _trinket_free_card_fired guards against re-arming on a later
# re-crossing within the same combat (see its own doc).
func _set_toll(new_value: int, source: RunLogger.TollSource = RunLogger.TollSource.SELF) -> void:
	var old_value := toll
	toll = new_value
	player_resource_cluster.update_toll(toll)
	RunLogger.log_toll_change(toll, source)
	if not _trinket_free_card_fired and RunState.equipped_trinket != null and RunState.equipped_trinket.modifier != null and RunState.equipped_trinket.modifier.kind == TrinketModifier.Kind.TOLL_THRESHOLD_FREE_CARD:
		var threshold: int = RunState.equipped_trinket.modifier.value
		if old_value < threshold and new_value >= threshold:
			_trinket_free_card_armed = true
			_trinket_free_card_fired = true

# THE single point every player-HP change routes through (loss or gain -
# see _heal_player() below) - see the `toll` var's own doc comment above
# for why. `source` (2026-09-02, Toll source tracking pass - see RunLogger.
# TollSource's own doc) is passed straight through to _set_toll() below,
# purely for RunLogger's per-source accrual split; it has no effect on
# HOW MUCH Toll accrues, only on which bucket the accrual is attributed
# to. Defaults to SELF, same default _set_toll() itself uses, so a caller
# with nothing meaningful to report (_heal_player() below, which never
# accrues anyway since `lost` there is never positive) doesn't need to
# pass anything. Takes
# the FINAL new value (already computed/clamped by the caller exactly as
# before this existed - block absorption, self-damage, status ticks, and
# healing each still do their own math), and derives the ACTUAL amount
# lost from the real before/after delta rather than trusting whatever
# "amount" argument a caller passed in - this is what correctly handles
# an overkill hit at low HP (RunState.player_hp floors at 0, so the true
# loss can be smaller than the raw incoming amount) without Toll ever
# over-counting it. Only pushes to the HUD (toll_display.gd, via
# player_battle_visual.gd's own update_toll()) when Toll actually
# changed - healing (a non-positive `lost`) correctly no-ops here, which
# is also what makes "Toll does not decrease on healing" true without
# needing a separate check anywhere else.
func _set_player_hp(new_hp: int, source: RunLogger.TollSource = RunLogger.TollSource.SELF) -> void:
	var old_hp := RunState.player_hp
	# Converts to RunState.take_damage()/heal() internally (2026-09-05,
	# HP-signal pass) - this function still takes the FINAL value every
	# caller already computes (unchanged signature, unchanged callers),
	# but RunState's own mutators take a DELTA, so the conversion happens
	# here. The result is algebraically identical to the old `clampi(
	# new_hp, 0, max)` either way: take_damage(old_hp - new_hp) clamps
	# player_hp - (old_hp - new_hp), which is new_hp, to [0, max];
	# heal(new_hp - old_hp) clamps player_hp + (new_hp - old_hp), also
	# new_hp, to [_, max] (heal's own floor never binds here - a positive
	# delta off an already-non-negative old_hp can't go negative). This
	# function's OWN Toll/_took_damage_this_turn/_update_hand_
	# affordability side effects below stay exactly as they were,
	# recomputed fresh from old_hp/RunState.player_hp after the call -
	# battle mechanics, not something a general RunState-level signal
	# should know about.
	var delta := new_hp - old_hp
	if delta < 0:
		RunState.take_damage(-delta)
	elif delta > 0:
		RunState.heal(delta)
	var lost := old_hp - RunState.player_hp
	if lost > 0:
		_set_toll(toll + lost, source)
		# _took_damage_this_turn (see its own doc) - same "any HP loss, any
		# source, one chokepoint" reasoning Toll's own accrual line just
		# above already follows, deliberately not filtered to enemy
		# attacks only.
		_took_damage_this_turn = true
	if RunState.player_hp != old_hp:
		# A Toll-gated card (Reckoning) sitting in hand needs to light up
		# the INSTANT Toll becomes spendable, not wait for some other
		# event (playing a different card) to happen to refresh it -
		# same reasoning _play_card() already has for re-checking energy
		# affordability after anything that could change it. Extended
		# (2026-08-27, Paid in Pain condition-indicator pass) to fire on
		# HP GAIN too, not just loss: Paid in Pain's condition is "below
		# half HP" in EITHER direction, so healing back above half needs
		# to un-arm a Paid in Pain already sitting in hand just as
		# promptly as dropping below it arms one - the old loss-only gate
		# left that direction stale.
		_update_hand_affordability()

# SELF_DAMAGE ignores block entirely and goes straight to HP - a card
# hurting its own caster isn't something an incoming block should soak.
# Dying to your own card is a legal death, same as dying to the enemy.
func _deal_self_damage(amount: int) -> void:
	_set_player_hp(RunState.player_hp - amount, RunLogger.TollSource.SELF)
	RunLogger.log_damage_taken(amount)
	_update_player_panel()
	_spawn_player_damage_number(amount, RunLogger.TollSource.SELF)
	AudioManager.play_sfx("damage_player") # The drain-family cue - unchanged; see PlayerBattleVisual.play_hp_cost_flinch()'s own note on why only the CHARACTER's own reaction is new here, not the sound.
	# hp_loss_breath (2026-09-07, self-damage-sound pass) - layered ON TOP
	# of damage_player above, not instead of it, same "distinct additional
	# texture" shape chain_impact/weapon_reflect use elsewhere in this
	# file. This is THE self-damage chokepoint (every SELF_DAMAGE/SELF_
	# DAMAGE_TOLL card effect and _apply_attack_hp_drain()'s own Selfeater
	# drain all call this one function - see RunLogger.TollSource.SELF,
	# already threaded through above), so wiring it here covers all three
	# without a parallel flag.
	AudioManager.play_hp_loss_breath()
	player_battle_visual.play_hp_cost_flinch()
	# Defeat check FIRST, unchanged timing - the delay below never gates
	# this. Only once battle_over-relevant state is already fully settled
	# does this function wait at all, so nothing about WHEN a self-damage
	# kill is detected moves.
	if RunState.player_hp <= 0:
		_on_player_defeated()
		return
	# The "pay, then hit" gap (see AudioManager.hp_loss_breath_impact_
	# delay_sec's own doc) - LOCAL to this function's own tail, not
	# threaded up through this function's own callers (_resolve_card_
	# effect()'s SELF_DAMAGE/SELF_DAMAGE_TOLL branches, _apply_attack_hp_
	# drain()'s loop), none of which await this call today. That means
	# this delay does NOT currently postpone whatever effect a caller
	# resolves next - _apply_card_effects()'s own loop only awaits
	# between two consecutive HIT effects (see its own doc), never
	# between a SELF_DAMAGE and a neighboring DAMAGE, and threading an
	# await further up would change resolution timing for every card,
	# not just this one. Left this narrow deliberately - see this pass's
	# own report for the one card (Bite Down) where that gap actually
	# matters and why closing it needs a decision this function alone
	# can't make.
	if AudioManager.hp_loss_breath_impact_delay_sec > 0.0:
		await get_tree().create_timer(AudioManager.hp_loss_breath_impact_delay_sec).timeout

# Applies an equipped weapon's SELF_DAMAGE_REFLECT modifier (The
# Creditor - see weapon_modifier.gd's own note): the SAME amount just
# taken as SELF_DAMAGE lands on the card's own target as a separate
# follow-up hit, delayed slightly (weapon_reflect_delay_sec) so it
# reads as a distinct second hit rather than a number popping on top of
# the card's own damage number in the same frame - same "space the
# beats out" instinct chain_payoff_delay_sec already established for
# the chain payoff, just a shorter gap (this is a smaller, more
# incidental effect, not its own moment). No-ops with no equipped
# weapon, the wrong modifier kind, or no target - a SELF_DAMAGE-only
# card with no DAMAGE effect of its own never asked for a target in
# the first place (see _card_needs_target()), so there's nothing here
# for the weapon to hit either; "empty means unaffected," same as
# every other weapon modifier check in this file.
func _reflect_self_damage(amount: int, target: EnemyCombatant, rally_window: RallyWindow = null) -> void:
	var weapon: WeaponData = RunState.equipped_weapon
	if weapon == null or weapon.modifier == null:
		return
	if weapon.modifier.kind != WeaponModifier.Kind.SELF_DAMAGE_REFLECT:
		return
	if target == null or target.is_defeated:
		return
	await get_tree().create_timer(weapon_reflect_delay_sec).timeout
	if battle_over or target.is_defeated:
		return
	# rally_window is the SAME object _resolve_card_effect() was holding
	# when it called this, captured before this function's own await
	# above - see RallyWindow's own doc for why an object reference (not
	# an ambient flag) is what makes this land in the right window even
	# though _apply_card_effects() has already returned by now.
	_deal_damage_to_enemy(target, amount, false, true, false, rally_window)

# Capped at max HP - healing past full just does nothing extra, same
# spirit as _resolve_damage() capping HP loss at 0. Gates the floating
# number and sound behind actually healing (mirrors _deal_damage_to_enemy()
# only flashing/playing a sound when damage_to_hp > 0) so topping off an
# already-full player doesn't cue a heal that didn't happen - including
# for a chain-payoff refund (see below): if there's genuinely nothing to
# refund, there's nothing to show, same instinct either way.
#
# chain_payoff mirrors _deal_damage_to_enemy()'s own empowered parameter
# - true only when this IS a chain's own HEAL-type payoff (see _trigger_
# chain_payoff()), never for an ordinary heal card like Kept Warmth. No
# Closer sets a HEAL-type chain_followup_effect today (Bite Down's own
# refund was removed 2026-08-26 - see DESIGN.md's Wanderer entry), but
# this path is fully intact for whatever uses it next: deliberately its
# OWN visual language, not the chain system's usual amber - a refund is
# blood staying in the body, not a generic "something is building" bonus
# (see PlayerBattleVisual.play_chain_refund_aura()'s own note on why
# this reads as an aura around the CHARACTER, replacing an earlier
# version that flashed a burst near the HP bar and read as a UI effect
# instead).
func _heal_player(amount: int, chain_payoff: bool = false, rally_payoff: bool = false) -> void:
	var healed: int = mini(amount, RunState.player_max_hp - RunState.player_hp)
	_set_player_hp(RunState.player_hp + amount)
	_update_player_panel()
	if healed > 0:
		_spawn_player_heal_number(healed, chain_payoff)
		if rally_payoff:
			# REPLACES "heal" below, not layered on top of it - a Rally
			# recovery is its own moment (see rally_pool's own doc), not a
			# variant of an ordinary heal card landing, so it gets its own
			# cue outright rather than Kept Warmth's sound underneath it.
			AudioManager.play_sfx("rally_recover")
		else:
			AudioManager.play_sfx("heal")
		if chain_payoff:
			# Layered ON TOP of "heal" above, not instead of it - same
			# "distinct texture, additional cue" layering the enemy-side
			# chain_impact/damage_enemy pairing already established.
			# (chain_payoff and rally_payoff are never both true - see
			# their own call sites.)
			AudioManager.play_sfx("chain_refund")
			player_battle_visual.play_chain_refund_aura()

# empowered is true only for a CLOSER-role card resolving while chain_
# empowered was active (see _resolve_card_effect()'s DAMAGE branch,
# which is the only caller that ever passes true) - every other caller
# (the dev damage button, a status tick) leaves it at the default
# false and is completely unaffected. weapon_reflect is true only for
# The Creditor's own reflected hit (see _reflect_self_damage() above);
# retaliation is true only for Retaliation's own reflected hit (see
# _check_retaliation_trigger() below) - the three flags are never more
# than one true at once in practice (each is triggered by a different
# effect type), so no precedence rule between them exists or is needed.
# Reuses the SAME feedback this function already plays for every hit
# (flash_damage(), the "damage_enemy" sfx) rather than a parallel
# pipeline per hit kind - empowered/retaliation each just ask for their
# own additional layer on top, which lives here (not on Enemy) since only
# Battle can move the whole UI CanvasLayer - see _play_screen_shake()'s
# own note. weapon_reflect is the one exception (2026-08-29) - it REPLACES
# the damage_enemy sfx rather than layering over it, see that branch's
# own note below for why.
func _deal_damage_to_enemy(target: EnemyCombatant, amount: int, empowered: bool = false, weapon_reflect: bool = false, retaliation: bool = false, rally_window: RallyWindow = null) -> void:
	amount = _apply_status_modifiers(amount, target.statuses, StatusEffectData.ModifierTarget.INCOMING_DAMAGE)
	# THE one seam (see _escaping_enemy's own note) - every outgoing player
	# damage source (an ordinary card, Toll consumption, a chain payoff, a
	# weapon reflect, a Retaliation proc) already funnels through here, so
	# this is the only place that needs to know Outbound's falloff exists
	# at all. A no-op (scalar 1.0) for every target that isn't the fight's
	# own _escaping_enemy, i.e. every fight in the game except one against
	# Outbound.
	amount = roundi(amount * _escape_falloff_scalar(target))
	var result := _resolve_damage(amount, target.hp, target.block, 0)
	target.hp = result["hp"]
	target.block = result["block"]
	target.instance.update_hp(target.hp, target.max_hp)
	target.instance.update_block(target.block)
	if result["damage_to_hp"] > 0:
		RunLogger.log_damage_dealt(result["damage_to_hp"])
		# Charge window damage accumulation (2026-08-29, BOSS_01 pass) -
		# gated on charge_window_turns > 0, a no-op for every enemy
		# without the mechanic, same shape the pain-turn/debris-spawn
		# checks elsewhere in this file already use inline in a shared
		# resolution function. Landed damage only (this branch already
		# requires damage_to_hp > 0, i.e. post-block HP loss) - matches
		# RunLogger.log_damage_dealt()'s own convention just above,
		# confirmed as the right metric for this feature.
		#
		# Refreshed live, not just once per enemy turn - a player who
		# plays several damage cards in one turn should see the count go
		# up as each one lands, not wait for the boss's own next turn to
		# catch up ("progress must be legible or the mechanic is unfair,"
		# this feature's own brief). Called unawaited - _update_intent_
		# display()'s animate=false branch never actually suspends, so
		# this runs to completion synchronously without turning _deal_
		# damage_to_enemy() itself into an async function every one of
		# its many callers would then need to await.
		if target.data.charge_window_turns > 0 and target.charge_phase == BossChargePhase.WINDOW:
			target.charge_window_damage += result["damage_to_hp"]
			_update_intent_display(target, false)
		# weapon_reflect/retaliation each get their own FloatingNumber.Kind;
		# every other hit (normal or empowered) just omits the argument and
		# lets Enemy's own flash_damage() fall back to its Kind.DEAL default
		# - battle.gd has no business knowing what that default look
		# actually is.
		if weapon_reflect:
			target.instance.flash_damage(result["damage_to_hp"], empowered, FloatingNumber.Kind.DEAL_WEAPON_REFLECT)
		elif retaliation:
			target.instance.flash_damage(result["damage_to_hp"], empowered, FloatingNumber.Kind.DEAL_RETALIATION)
		else:
			target.instance.flash_damage(result["damage_to_hp"], empowered)
		if weapon_reflect:
			AudioManager.play_sfx("weapon_reflect") # REPLACES damage_enemy below (2026-08-29) - used to layer on top of it instead, same shape as chain_impact/retaliation_hit, but that read as a "double strike" for a card that deals direct damage AND self-damage in the same play (Bite Down: DAMAGE then SELF_DAMAGE), since the Creditor's reflected hit lands a beat after the card's own DAMAGE hit already played this exact damage_enemy cue once - two near-identical hit sounds in quick succession, not a distinct additional texture. The Creditor's own cue is meant to BE this hit's whole sound, not an accent on top of a repeated generic one.
		else:
			AudioManager.play_sfx(_damage_enemy_sfx_name())
		if empowered:
			AudioManager.play_sfx("chain_impact") # Layered ON TOP of damage_enemy above, not instead of it - both fire the same frame; see AudioManager's own pooled-player note for why that's a normal thing to do here.
			_play_screen_shake(empowered_hit_shake_px, empowered_hit_shake_duration_sec)
		else:
			if retaliation:
				AudioManager.play_sfx("retaliation_hit") # Layered ON TOP of damage_enemy above, same pairing shape chain_impact uses - a distinct texture, not a louder copy of the normal hit sound. NOT the same shape weapon_reflect uses above (see its own note) - Retaliation never fires alongside a preceding hit on the SAME target within the same beat the way the Creditor's reflect can, so the "sounds like an echo" problem doesn't apply here.
			_play_screen_shake(normal_hit_shake_px, normal_hit_shake_duration_sec)
		# Rally's recovery half (see rally_pool's/RallyWindow's own docs
		# for the fill half and the per-event accumulation) - this hit
		# only ever CONTRIBUTES to whatever window the caller says it
		# belongs to; the window itself decides whether/how much actually
		# pays out.
		_contribute_to_rally_window(rally_window, result["damage_to_hp"])
	# Owed collection (2026-09-08, Owed status pass) - OUTSIDE the
	# damage_to_hp > 0 branch above, deliberately: a fully-blocked hit is
	# still a hit the player LANDED (the attack resolved against this
	# enemy), which is what Owed's own tooltip says triggers it ("each
	# hit you land"), not "each point of damage that gets through" - see
	# this pass's own report for why block shouldn't gate this the way it
	# gates the log_damage_dealt()/floating-number/sfx bundle above.
	# Guarded on weapon_reflect/retaliation - both are the PLAYER's own
	# damage bouncing back at an enemy via a reflected/retaliated hit, not
	# a card the player actually played against this target, so neither
	# should drain a stack the same way playing an Attack does.
	if not weapon_reflect and not retaliation:
		_collect_owed(target)
	_check_pain_turn_trigger(target)
	if target.hp <= 0:
		_on_enemy_defeated(target)

# The Owed status's own consumption (see resources/statuses/owed.tres) -
# loaded via load(), not preload, since this is the one call site that
# needs it and a preload would keep the resource resident even for a
# fight that never sees Owed applied at all (every other status constant
# in this file - BRACED_STATUS, RETALIATION_PRIMED_STATUS, NO_BLOCK_
# STATUS, SELFEATER_STATUS - IS preloaded, but each of those is read from
# a fixed const checked unconditionally on nearly every hit; this one is
# behind an _apply_status_to_target-shaped card that doesn't exist in the
# starter deck, so it's fine - and more honest about the actual access
# pattern - to load it lazily instead). Finds by resource identity (same
# "same StatusEffectData means same status" comparison _apply_status()/
# _find_status() already use), not by any special-cased Owed-only lookup.
func _collect_owed(target: EnemyCombatant) -> void:
	var owed_data: StatusEffectData = load("res://resources/statuses/owed.tres")
	var active: ActiveStatus = _find_status(target.statuses, owed_data)
	if active == null or active.magnitude <= 0:
		return
	active.magnitude -= 1
	_heal_player(2, false, false)
	RunLogger.log_owed_collected()
	if active.magnitude == 0:
		_remove_status(target.statuses, active)
	target.instance.update_statuses(target.statuses)

const ESCAPE_FALLOFF_PLATEAU_DISTANCE := 20.0
# Full damage (no falloff at all) through this much distance - a kill
# stays fully live in the opening turns, before retreat has actually
# built up into something worth trading damage off against.
const ESCAPE_FALLOFF_FLOOR := 0.4
# The scalar never drops below this, even at escape_distance_max - a
# kill should stay THEORETICALLY live all the way to the last turn
# before the fight ends by escaping instead, not decay to a hit that
# can literally never finish the job.
# 2026-08-27 retune (see DESIGN.md's Bestiary: Outbound) - was a bare
# linear ramp to 0.0 at max distance; this is the escape-rate/falloff
# tuning pass that entry flagged as deferred.

# Plateau-then-linear: 1.0 (no falloff) through ESCAPE_FALLOFF_PLATEAU_
# DISTANCE, then a straight line down to ESCAPE_FALLOFF_FLOOR at the
# escaping enemy's own escape_distance_max (see EnemyData's own note on
# why that threshold is also this ramp's denominator). 1.0 (a pure no-op
# multiply) for any target that isn't _escaping_enemy, which covers
# every fight without Outbound in it without this needing its own
# separate early-return. clamp() guards the tail end: distance can equal
# (or, if a future enemy's tick doesn't divide the max evenly, slightly
# overshoot) the max in the same instant _tick_escape_distance() below
# is about to end the fight via escape - a stray call landing between
# that tick and the fight actually ending should read as "at the floor,"
# never below it.
func _escape_falloff_scalar(target: EnemyCombatant) -> float:
	if target != _escaping_enemy or _escaping_enemy == null:
		return 1.0
	if _escape_distance <= ESCAPE_FALLOFF_PLATEAU_DISTANCE:
		return 1.0
	var max_distance := _escaping_enemy.data.escape_distance_max
	var t := (_escape_distance - ESCAPE_FALLOFF_PLATEAU_DISTANCE) / (max_distance - ESCAPE_FALLOFF_PLATEAU_DISTANCE)
	return clamp(lerp(1.0, ESCAPE_FALLOFF_FLOOR, t), ESCAPE_FALLOFF_FLOOR, 1.0)

# Called once, at the end of _run_enemy_turn() (see its own call site) -
# "end of enemy turn," not "end of this one combatant's own resolution,"
# since Outbound is solo-only and the two are the same moment for it
# today; a future second escaping enemy sharing a room would still only
# need ONE tick per turn, not one per combatant, so this stays hooked to
# the turn boundary rather than moving into _resolve_enemy_intent().
# A permanent no-op for every fight without an _escaping_enemy.
func _tick_escape_distance() -> void:
	if battle_over or _escaping_enemy == null or _escaping_enemy.is_defeated:
		return
	# turn_number is still THIS (about-to-end) turn's number here - this
	# runs at the end of the enemy phase, before _start_player_turn()'s
	# own increment for the next one. turn_number starts at 1 (see
	# _start_battle()), so turn_number - 1 is 0 for the very first enemy
	# turn, 1 for the second, and so on - exactly "turns elapsed since
	# combat start," 0-indexed, matching escape_distance_ramp's own
	# indexing (see EnemyData's note). Clamped to the ramp's last entry
	# if the fight runs past the table.
	var ramp: Array[float] = _escaping_enemy.data.escape_distance_ramp
	var ramp_index := mini(turn_number - 1, ramp.size() - 1)
	_escape_distance += ramp[ramp_index]
	# The recession presentation (see enemy.gd's own set_recession() note)
	# - a continuous tween toward the new fraction, not a snap, called
	# even on the tick that crosses the escape threshold below (the
	# creature should still visibly finish drifting to its furthest point
	# rather than freezing mid-tween the instant the fight ends).
	_escaping_enemy.instance.set_recession(_escape_distance / _escaping_enemy.data.escape_distance_max)
	if _escape_distance >= _escaping_enemy.data.escape_distance_max:
		_on_battle_escaped() # Itself async - fire-and-forget, same as _on_enemy_defeated() calling _on_all_enemies_defeated().

# A short, decaying side-to-side jitter on the whole UI CanvasLayer's
# own offset - the one property that visibly moves EVERYTHING under it
# (backdrop, combatants, hand, HUD) at once, since this scene has no
# Camera2D to shake instead (it's static and non-scrolling - see
# _apply_battle_backdrop()'s own note). Re-triggering while a previous
# shake is still settling (two hits landing close together) kills the
# old tween and starts fresh from wherever it currently sits, same
# "don't fight the in-flight animation" rule every other tween in this
# codebase already follows (see card.gd's _play_hover_tween()).
var _shake_tween: Tween

func _play_screen_shake(magnitude_px: float, duration_sec: float) -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	var leg_count := 5
	var leg_duration := duration_sec / leg_count
	for i in leg_count:
		# Alternates sides and decays toward zero (1.0 -> 0.0 across the
		# legs) so the shake settles rather than cutting off abruptly -
		# the same "ease toward rest" instinct every other impact
		# animation in this codebase already follows.
		var falloff := 1.0 - (float(i) / leg_count)
		var offset := Vector2(magnitude_px * falloff * (1 if i % 2 == 0 else -1), 0)
		_shake_tween.tween_property(ui, "offset", offset, leg_duration)
	_shake_tween.tween_property(ui, "offset", Vector2.ZERO, leg_duration)

# --- Pain turn (DECIDED — see DESIGN.md's Bestiary: the Wardling and
# enemy_data.gd's pain_turn_hp_threshold) ---
#
# An enemy whose threshold is 0 (every enemy except the Wardling, today)
# is completely unaffected - this is a no-op for them, same "empty/zero
# means no effect" shape the escalation fields already use. Checked here,
# right after damage lands, rather than at the enemy's own resolution
# time - a killing blow that ALSO crosses the threshold correctly skips
# this (the target.hp <= 0 guard below), since a corpse doesn't get a
# pain turn; and triggering the instant the threshold crosses (mid-
# player-turn, not at end-of-turn) is what lets _apply_intent_interrupt()
# below swap the display immediately - see its own comment for why that
# timing matters for this game's telegraphing fairness rule.
func _check_pain_turn_trigger(target: EnemyCombatant) -> void:
	var threshold := target.data.pain_turn_hp_threshold
	if threshold <= 0.0 or target.pain_turn_used or target.hp <= 0:
		return
	if target.hp >= target.max_hp * threshold:
		return
	target.pain_turn_used = true
	# EnemyData.pain_turn_sfx (see its own doc) - "" for every enemy
	# without one authored stays silent, exactly today's behavior. Fired
	# here, not inside _apply_intent_interrupt() below, since that
	# function is shared with card_effect.gd's own STUN interrupt (a
	# chain payoff) - this cue is specifically the pain turn's own
	# reaction, not the generic "an intent got cancelled" moment.
	if target.data.pain_turn_sfx != "":
		AudioManager.play_sfx(target.data.pain_turn_sfx)
	_apply_intent_interrupt(target, target.data.pain_turn_flavor)

# --- Intent interrupt (DECIDED — see DESIGN.md's Bestiary: the Wardling;
# generalized 2026-08-23 for card_effect.gd's STUN) ---
#
# The one shared entry point for "cancel this enemy's queued intent and
# show a beat of flavor text instead" - _check_pain_turn_trigger() above
# (the Wardling's own HP-threshold pain turn) and _resolve_card_effect()'s
# STUN case (a chain payoff, e.g. Guillotine's) both call this instead of
# duplicating it. Deliberately does NOT own any "once per fight" guard
# itself - that belongs to whichever TRIGGER needs one (pain_turn_used,
# checked by the caller above before this ever runs) or doesn't (a chain
# payoff has no such limit - it can stun again every time it's played).
# Fire-and-forget, same as every other cosmetic reaction here (flash_
# damage(), play_defeat_sequence() when other enemies remain) - the
# player's turn shouldn't pause for it, and _resolve_enemy_intent()'s own
# telegraph pause already guarantees this has settled well before the
# interrupted turn actually resolves.
func _apply_intent_interrupt(target: EnemyCombatant, message: String) -> void:
	target.intent_interrupted_pending = true
	target.instance.show_intent_interrupt(message)

# --- Status effects (DECIDED — mechanism only, see DESIGN.md's Status
# Effects section) ---
#
# No named/flavored status exists yet - status_effect_data.gd's own
# header explains why (DESIGN.md's Combat tempo note: statuses should be
# designed to serve THIS game's tempo, not imported from another game's
# vocabulary, and that design session hasn't happened). Everything below
# is generic engine, exercised today only by the dev-only test status
# (see _on_dev_status_button_pressed()) - no CardEffect or EnemyData
# entry references any of this yet.

# Applies status_data to whichever statuses list is passed (player_
# statuses, or one EnemyCombatant's own statuses) - shared by both sides
# of the fight rather than duplicated per-target, since the actual
# apply-or-stack decision doesn't care WHOSE list it's touching. If this
# exact StatusEffectData is already active, stacks per its own stack_
# rule (see ActiveStatus.apply_stack()) instead of adding a second,
# separate instance of the same status. Callers are responsible for
# pushing the updated list to whichever VitalsBar shows it afterward
# (see enemy.gd/player_battle_visual.gd's update_statuses()) - this
# function only touches the data, same "caller owns pushing to display"
# split every other piece of combat state in this file already follows.
func _apply_status(statuses: Array[ActiveStatus], status_data: StatusEffectData) -> void:
	for active in statuses:
		if active.data == status_data:
			active.apply_stack()
			return
	statuses.append(ActiveStatus.new(status_data))

# The immediate-removal counterpart to _remove_expired_statuses() below -
# for a StatusEffectData.DURATION_UNTIL_TRIGGERED or clears_on_trigger
# status (see their own docs), either of which expects to be removed
# early rather than only via the turn counter. Whatever code detects the
# proc (a damage hook checking `statuses` for this status) is expected to
# call this SYNCHRONOUSLY, in the same function call that found and used
# it, not defer removal to the next tick pass - critical for a multi-
# enemy turn, where _run_enemy_turn() awaits each combatant's _resolve_
# enemy_intent() fully before the next one starts: as long as a single-
# use status is gone before that await returns, a second attacker later
# in the same enemy phase can never see it still active. First consumer:
# _check_retaliation_trigger() below. Caller still owns pushing the
# change to display afterward (instance.update_statuses()), same split
# every other status mutation here follows.
func _remove_status(statuses: Array[ActiveStatus], active: ActiveStatus) -> void:
	statuses.erase(active)

# Read-only lookup companion to _apply_status()/_remove_status() - "is
# this exact StatusEffectData currently active, and if so, which
# ActiveStatus instance is it" (not just a bool: a caller that means to
# remove or otherwise act on the match, like _check_retaliation_trigger()
# below, needs the actual instance, not just the fact that one exists).
# Null means not active, same "absence is the null case" shape every
# other lookup in this file already uses.
func _find_status(statuses: Array[ActiveStatus], status_data: StatusEffectData) -> ActiveStatus:
	for active in statuses:
		if active.data == status_data:
			return active
	return null

# Pushes Selfeater's own stack count (0 if not active) to player_battle_
# visual's placeholder tint hook (see its own set_stance_tint() doc) -
# called right after every player_statuses mutation that could plausibly
# be Selfeater (today: only the APPLY_STATUS case above, since nothing
# else adds to or removes from player_statuses mid-fight yet - Selfeater
# uses DURATION_UNTIL_REMOVED, so it never expires via the turn-boundary
# tick either). Re-deriving stack_count from _find_status() each call
# rather than threading it through from the caller - this is cheap
# (player_statuses is never more than a handful of entries) and keeps
# every call site identical regardless of what changed, the same
# "caller doesn't need to know what it changed, just that it changed"
# shape update_statuses() itself already has.
func _update_selfeater_visual() -> void:
	var active := _find_status(player_statuses, SELFEATER_STATUS)
	player_battle_visual.set_stance_tint(active.stack_count if active != null else 0)

# The sound name for the character's own hit landing on an enemy (2026-08-28,
# Selfeater strike sfx pass) - the ONE place that decides "damage_enemy" vs.
# its Selfeater-specific replacement, same "battle.gd decides WHAT" split
# _update_selfeater_visual() above already follows for the stance tint.
# Shared by every _deal_damage_to_enemy()-adjacent site that currently plays
# "damage_enemy" (the ordinary hit AND the DoT-tick hit below) rather than
# each deciding independently - "the default strike sound" is one cue with
# one Selfeater-active override, not a per-trigger choice.
func _damage_enemy_sfx_name() -> String:
	return "selfeater_strike" if _find_status(player_statuses, SELFEATER_STATUS) != null else "damage_enemy"

# Refreshes every stance-driven hand indicator together - the HP-drain
# badge (see card.gd's set_attack_hp_drain(), gates on card_type itself),
# the "what would THIS copy of a stance card actually do" description
# preview (see _update_status_card_preview() below), and (2026-08-28,
# generic-damage-preview pass) the "what will THIS attack actually deal"
# preview (see _update_hand_outgoing_damage_preview() below) - in ONE
# pass over hand_container, not three, following the exact reasoning
# _update_hand_affordability() already gives for folding its own
# condition-active refresh into the same loop: "both facts depend on
# exactly the same trigger... a second pass over hand_container would
# just be the same iteration done twice for no benefit." Called right
# after every player_statuses mutation that could plausibly change any of
# them (today: only the APPLY_STATUS case above, same trigger _update_
# selfeater_visual() reacts to). A freshly-drawn card gets its own
# starting values at draw time instead (see _add_card_to_hand_display()'s
# own calls) - this only ever walks cards that already have a Card
# instance in hand_container, the same "existing cards vs. a card not
# there yet" split _update_hand_affordability() itself draws for energy/
# Toll affordability.
func _update_hand_stance_indicators() -> void:
	var total_drain := _total_attack_hp_drain()
	for child in hand_container.get_children():
		if child is Card:
			child.set_attack_hp_drain(total_drain)
			_update_status_card_preview(child, child.card_data)
			_update_hand_outgoing_damage_preview(child, child.card_data)

# Pushes card_instance's own live "if I played this copy right now"
# preview - substituting its APPLY_STATUS effect's authored base numbers
# (status_data.default_magnitude / attack_hp_drain_base) for what they'd
# ACTUALLY be after playing it, given whatever's already active (see this
# pass's own brief: "the values the player would have AFTER playing it" -
# the hypothetical stack this copy would produce is current + 1, or 1 if
# nothing's active yet, never the CURRENT stack's own values). Generic
# over ANY card with an APPLY_STATUS effect, not hardcoded to Selfeater -
# the first (and only, today) matching effect wins; a card with none at
# all falls through to card_instance.restore_description(), reverting
# anything a PREVIOUS card_data on this same instance might have left
# behind (Card instances aren't pooled/reused across draws in this
# codebase, but this stays correct either way).
#
# Shares its two numbers with the real resolution paths (_effective_
# modifier_magnitude()/_attack_hp_drain_for_stack()) - never recomputed
# independently, so this can never drift from either the attack-card
# drain indicator or what actually gets charged/dealt when the card is
# played. card.gd's own show_status_value_preview() decides internally
# whether either number actually differs from the status's own base (see
# its own doc) - this always calls it unconditionally when a qualifying
# effect exists, never pre-checking that itself.
func _update_status_card_preview(card_instance: Card, data: CardData) -> void:
	for effect in data.effects:
		if effect.effect_type != CardEffect.EffectType.APPLY_STATUS or effect.status_data == null:
			continue
		var status_data: StatusEffectData = effect.status_data
		var active := _find_status(player_statuses, status_data)
		var stack_count_after: int = (active.stack_count if active != null else 0) + 1
		var damage_bonus := _effective_modifier_magnitude(status_data.default_magnitude, status_data.stack_rule, stack_count_after)
		var hp_cost := _attack_hp_drain_for_stack(status_data, stack_count_after)
		card_instance.show_status_value_preview(damage_bonus, hp_cost)
		return
	card_instance.restore_description()

# The live "what will this attack actually deal" preview (2026-08-28,
# generic-damage-preview pass) - Part 2 of the same brief Part 1's
# _description_overrides rework exists to support: WITHOUT that rework,
# this would have the exact same "silently erased by the next affordability
# refresh" bug show_status_value_preview() had, since it drives card.gd
# through the SAME persistent-override storage (see show_modified_
# outgoing_damage()'s own doc).
#
# Runs for EVERY card in hand, not only ones with an APPLY_STATUS effect
# (see _update_hand_stance_indicators() above, which calls this alongside
# _update_status_card_preview() for every child) - Slash/Bite Down/etc.
# have DAMAGE effects, never APPLY_STATUS, so _update_status_card_preview()
# alone could never reach them; this is what actually closes that gap.
#
# Generic over ANY OUTGOING_DAMAGE MODIFIER status currently active, not
# hardcoded to Selfeater - reads player_statuses through the exact same
# _apply_status_modifiers() the real DAMAGE-effect resolution path uses
# (see _resolve_card_effect()'s own DAMAGE/DAMAGE_ALL cases), so this can
# never show a number that resolution wouldn't actually produce.
#
# Scoped to DAMAGE and DAMAGE_ALL specifically, not every hit-type
# CardEffect _is_hit_effect() recognizes - TOLL_DAMAGE/TOLL_THRESHOLD_
# DAMAGE/FIRST_CARD_DAMAGE/TOLL_FRACTION_DAMAGE_ALL don't reliably have a
# literal printed number equal to effect.value at all (Reckoning's own
# TOLL_DAMAGE text has no damage number printed, by design - see card_
# effect.gd's own doc and show_modified_damage()'s matching exclusion),
# so blindly substituting against effect.value there could produce a
# substitution with nothing real to anchor it to the printed text, or
# silently do nothing while looking like it should have. DAMAGE/DAMAGE_
# ALL both always have a real, unconditionally-printed effect.value -
# the same guarantee show_modified_damage() above already relies on for
# its own DAMAGE-only scope, extended by exactly one type (DAMAGE_ALL,
# which shares the identical "value is the literal printed number" shape).
func _update_hand_outgoing_damage_preview(card_instance: Card, data: CardData) -> void:
	var overrides: Array[Dictionary] = []
	for effect in data.effects:
		if effect.effect_type != CardEffect.EffectType.DAMAGE and effect.effect_type != CardEffect.EffectType.DAMAGE_ALL:
			continue
		var modified := _apply_status_modifiers(effect.value, player_statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
		if modified != effect.value:
			overrides.append({"base": effect.value, "substitute": modified})
	card_instance.show_modified_outgoing_damage(overrides)

# Selfeater's own mechanic (2026-08-28, first STANCE card) - written
# generically over player_statuses rather than hardcoded to SELFEATER_
# STATUS specifically, since attack_hp_drain_base/attack_hp_drain_
# increment (see status_effect_data.gd's own doc) are generic fields any
# future status could set too, with zero new code here. Called once per
# ATTACK card played (see _play_card()'s own call site) - never per hit,
# per target, or per damage-type CardEffect, which is what keeps this a
# flat per-CARD cost regardless of how many hit effects that card has
# (contrast the MODIFIER damage bonus, which this pass's own report
# found DOES apply per hit-type effect for a card like Owed in Full -
# the drain deliberately doesn't inherit that quirk, since it lives
# entirely outside _resolve_card_effect()'s per-effect loop).
#
# Cost scales with THAT status's own stack_count (base at stack 1, +
# increment per stack beyond that - see ActiveStatus.stack_count's own
# doc), no cap beyond whatever _deal_self_damage() itself allows (this
# CAN kill - deliberate, see this pass's own report on why checking
# battle_over after each drain, not just once before the loop, is what
# keeps a second drain-carrying status - hypothetical today, nothing
# else sets these fields - from firing into an already-ended battle).
# Routes through _deal_self_damage(): Toll accrues, no Rally pool opens,
# block is bypassed - exactly Bite Down's own HP-cost semantics, per
# this card's own brief ("route it through _deal_self_damage(), which
# already has exactly these semantics").
func _apply_attack_hp_drain() -> void:
	for active in player_statuses:
		var cost := _attack_hp_drain_for_status(active)
		if cost > 0:
			_deal_self_damage(cost)
			if battle_over:
				return

# ONE status's own per-attack cost (0 if it doesn't carry a drain at all -
# see attack_hp_drain_base/attack_hp_drain_increment's own "empty means
# unaffected" doc). Split out (2026-08-28, hand-indicator pass) from what
# used to be inline in _apply_attack_hp_drain() above, so a second caller
# - _total_attack_hp_drain() below, which the hand's own HP-cost
# indicator reads (see card.gd's set_attack_hp_drain()) - can never
# disagree with what actually gets charged, by construction: both read
# THIS, neither recomputes the formula on its own.
func _attack_hp_drain_for_status(active: ActiveStatus) -> int:
	return _attack_hp_drain_for_stack(active.data, active.stack_count)

# The same formula as above, taking a StatusEffectData/stack_count pair
# directly instead of a live ActiveStatus (2026-08-28, card-preview
# pass) - the lower-level primitive _attack_hp_drain_for_status() itself
# now just forwards to, so a caller previewing a HYPOTHETICAL stack count
# (Selfeater's own card-face preview - see _update_status_card_preview()
# below - "what would THIS copy cost if played right now") can reuse the
# exact same math without needing a real ActiveStatus instance to exist
# yet (a card in hand while nothing's active has no ActiveStatus for its
# own status at all - stack 0 - but still needs to preview what stack 1
# would look like).
func _attack_hp_drain_for_stack(data: StatusEffectData, stack_count: int) -> int:
	if data.attack_hp_drain_base <= 0 and data.attack_hp_drain_increment <= 0:
		return 0
	return data.attack_hp_drain_base + data.attack_hp_drain_increment * (stack_count - 1)

# The TOTAL HP an ATTACK card played right now would actually cost,
# summed across every drain-carrying status currently active - exactly
# what _apply_attack_hp_drain() above would charge if that card were
# played this instant (same per-status formula via _attack_hp_drain_for_
# status(), same summing-across-statuses shape - today that's one status,
# Selfeater's, but this stays correct if a second drain-carrying status
# ever coexists with it). 0 when nothing's active, the same "no drain-
# carrying status means no cost at all" case _apply_attack_hp_drain()
# itself degrades to. Read-only - never mutates anything, safe to call
# just to decide what to SHOW without touching game state.
func _total_attack_hp_drain() -> int:
	var total := 0
	for active in player_statuses:
		total += _attack_hp_drain_for_status(active)
	return total

# Called once per combatant per turn boundary (see _start_player_turn()
# for the player, _resolve_enemy_intent() for each enemy - every
# combatant ticks its OWN statuses at the start of its OWN turn, the same
# convention most turn-based status systems use). `deal_tick_damage` lets
# one shared function work for both the player and any enemy despite
# them having entirely different "apply damage to me" functions - see
# the two call sites for what each actually passes.
#
# Deliberately does NOT erase expired statuses itself anymore (2026-08-27
# - see _remove_expired_statuses() below, now a separate step). The
# player's own call site still runs both back to back with nothing in
# between, so nothing changes for it - but the enemy side needs the gap:
# a 1-turn MODIFIER status applied by the player is meant to still affect
# the very attack that ticks it to 0 (see _resolve_enemy_intent()'s own
# note), which means it has to survive THIS tick, still present when
# _apply_status_modifiers() reads it a few lines later, and only actually
# leave the list once that attack has resolved. Erasing here, before that
# read, was exactly backwards - a duration-1 debuff would tick to 0 and
# vanish before ever modifying the hit it was aimed at.
func _tick_statuses(statuses: Array[ActiveStatus], deal_tick_damage: Callable) -> void:
	# Iterate a COPY - resolving a TICK status can defeat its holder mid-
	# loop, which could in principle mutate `statuses` out from under this
	# same loop by the time a later status in it gets its own turn (no
	# real status does this today - see the section header above) - same
	# defensive snapshotting _living_enemies() gets before _run_enemy_
	# turn() loops over it.
	for active in statuses.duplicate():
		if active.data.category == StatusEffectData.Category.TICK and active.magnitude > 0:
			deal_tick_damage.call(active.magnitude)
		active.tick_duration()

# The erasure half of the old combined function above - now its own
# step so a caller can read/apply whatever's still active BETWEEN
# ticking and erasing (see _tick_statuses()'s own note). Iterates a copy
# for the same reason that function already documents - erasing from the
# live array mid-loop would skip entries.
func _remove_expired_statuses(statuses: Array[ActiveStatus]) -> void:
	for active in statuses.duplicate():
		if active.is_expired():
			statuses.erase(active)

# TICK damage bypasses block entirely, straight to HP - same "this isn't
# something an incoming block should soak" stance _deal_self_damage()
# already takes for a card hurting its own caster; a damage-over-time
# status conventionally works the same way in this genre. Mirrors _deal_
# self_damage() almost exactly, kept as its own function rather than
# reused since the two exist for conceptually different reasons (a card
# choosing to hurt its owner vs. a status ticking) even though the math
# is identical today.
func _deal_status_tick_damage_to_player(amount: int) -> void:
	_set_player_hp(RunState.player_hp - amount, RunLogger.TollSource.STATUS)
	RunLogger.log_damage_taken(amount)
	_update_player_panel()
	_spawn_player_damage_number(amount, RunLogger.TollSource.STATUS)
	AudioManager.play_sfx("damage_player")
	if RunState.player_hp <= 0:
		_on_player_defeated()

func _deal_status_tick_damage_to_enemy(combatant: EnemyCombatant, amount: int) -> void:
	combatant.hp = max(combatant.hp - amount, 0)
	RunLogger.log_damage_dealt(amount)
	combatant.instance.update_hp(combatant.hp, combatant.max_hp)
	combatant.instance.flash_damage(amount)
	AudioManager.play_sfx(_damage_enemy_sfx_name())
	# Same threshold check a normal hit gets (see _deal_damage_to_enemy())
	# - a DoT tick crossing the Wardling's pain-turn threshold should
	# trigger it exactly like any other source of damage would.
	_check_pain_turn_trigger(combatant)
	if combatant.hp <= 0:
		_on_enemy_defeated(combatant)

# Applies every active MODIFIER-category status in `statuses` matching
# `target` to `amount`, in list order - ADD sums directly onto the
# running total; MULTIPLY treats magnitude as a PERCENTAGE (50 means
# "+50%") rather than a raw multiplier (see StatusEffectData.Modifier
# Operation for why). Order matters when more than one modifier is
# active at once, same as it would with real named effects later -
# nothing about this mechanism decides that for content, it just applies
# whatever's active in the order it's stored. Never called anywhere that
# matters yet in practice (see the section header above) - every real
# call site already wires this in (see _resolve_card_effect()/_enemy_
# attack_player()/_resolve_enemy_intent()), it's just a no-op until a
# status actually sets category == MODIFIER.
func _apply_status_modifiers(amount: int, statuses: Array[ActiveStatus], target: StatusEffectData.ModifierTarget) -> int:
	var result := amount
	for active in statuses:
		if active.data.category != StatusEffectData.Category.MODIFIER:
			continue
		if active.data.modifier_target != target:
			continue
		var effective_magnitude := _effective_modifier_magnitude(active.magnitude, active.data.stack_rule, active.stack_count)
		match active.data.modifier_operation:
			StatusEffectData.ModifierOperation.ADD:
				result += effective_magnitude
			StatusEffectData.ModifierOperation.MULTIPLY:
				result += roundi(result * effective_magnitude / 100.0)
	return max(result, 0)

# StackRule.IGNORE-specific scaling (2026-08-28, Selfeater stacking fix -
# split out into its own function in the card-preview pass right after,
# so a card-face preview with no live ActiveStatus to read from - see
# _update_status_card_preview() below - can reuse the exact same rule).
# IGNORE is the one stack_rule that deliberately freezes magnitude itself
# on reapplication (see ActiveStatus.apply_stack()'s own IGNORE case and
# StatusEffectData's doc on why: Selfeater needs a FLAT per-stack damage
# bonus decoupled from its own escalating per-stack HP drain, which reads
# stack_count independently via _attack_hp_drain_for_stack() - switching
# to ADD_MAGNITUDE instead would grow magnitude directly and re-couple
# the two numbers, exactly what the split was built to avoid). Scaling
# the READ by stack_count here, gated to IGNORE specifically, is how
# "more applications still means more effect" survives that freeze
# without touching magnitude itself.
#
# Deliberately NOT applied to every stack_rule: the other three already
# express reapplication directly in magnitude - ADD_MAGNITUDE/REFRESH_
# AND_ADD grow it explicitly on each apply_stack(), and REFRESH_
# DURATION's own doc is explicit that reapplying is meant to change
# nothing but the clock. Scaling by stack_count for those too would
# either double-count growth already baked into magnitude, or silently
# break REFRESH_DURATION's own "reapplying changes nothing but duration"
# promise the moment a future MODIFIER status picks it. No status besides
# Selfeater's own uses category == MODIFIER today (still true after this
# change - see this function's own history), so this branch has exactly
# one real caller right now; for anything that has never been reapplied
# (stack_count == 1, the default), this is a no-op regardless of which
# stack_rule it uses - unchanged behavior.
#
# Takes `magnitude` as a plain parameter, not an ActiveStatus, so the
# preview path can pass a StatusEffectData's own default_magnitude
# instead - equivalent to a real instance's current .magnitude ONLY for
# IGNORE-rule statuses (the one rule that freezes magnitude at exactly
# default_magnitude forever), which is also the only rule this function's
# own scaling branch ever fires for - so that equivalence always holds
# exactly where it's actually used.
func _effective_modifier_magnitude(magnitude: int, stack_rule: StatusEffectData.StackRule, stack_count: int) -> int:
	if stack_rule == StatusEffectData.StackRule.IGNORE:
		return magnitude * stack_count
	return magnitude

# Applies `amount` incoming damage to a block value first, then absorb,
# then whatever is left over spills onto HP - the "Guard 5 vs Attack 8 =
# 3 HP lost" rule, extended (2026-09-05, Forbearance pass) with a second,
# independent reduction pool subtracted in the same call. Written once so
# every direction that resolves damage (player-attacks-enemy, enemy-
# attacks-player) shares the exact same math instead of copies that could
# quietly drift apart.
#
# current_absorb is 0 for every caller except _enemy_attack_player() -
# enemies have no absorb pool of their own (EnemyCombatant only ever
# tracks its own `block`, a separate field from this function's own
# current_block/current_absorb parameters), so _deal_damage_to_enemy()
# passes 0 here and the "absorb"/"absorbed_by_absorb" keys below always
# come back 0 for it, unread by that caller - same "field exists, unused
# by callers that don't need it" shape every other optional field in this
# project already follows.
#
# "absorbed" keeps its existing meaning (block specifically, read by
# RunLogger.log_damage_blocked() and Retaliation's own doc) - absorb gets
# its own separate "absorbed_by_absorb" key rather than folding into that
# one, so a caller that cares about block specifically (existing code)
# and a caller that cares about absorb specifically (the new RunLogger
# call in _enemy_attack_player()) each read their own number, with
# nothing to disambiguate.
func _resolve_damage(amount: int, current_hp: int, current_block: int, current_absorb: int) -> Dictionary:
	var absorbed: int = min(current_block, amount)
	var after_block: int = amount - absorbed
	var absorbed_by_absorb: int = min(current_absorb, after_block)
	var damage_to_hp: int = after_block - absorbed_by_absorb
	return {
		"hp": max(current_hp - damage_to_hp, 0),
		"block": current_block - absorbed,
		"absorb": current_absorb - absorbed_by_absorb,
		"damage_to_hp": damage_to_hp,
		"absorbed": absorbed,
		"absorbed_by_absorb": absorbed_by_absorb,
	}

# Marks `target` defeated and stops it counting as living from here on
# (see _living_enemies()) - it fades out RIGHT AWAY regardless of
# whether the fight is actually over, rather than waiting to be noticed.
# If other enemies are still up, that fade is fire-and-forget (nothing
# awaits it - the fight keeps moving around it, same "never blocks the
# player's own turn" instinct Enemy's name-intro already follows). Only
# once every enemy is down does the real victory sequence run, awaiting
# THIS (the last) enemy's own fade - any earlier deaths in the same
# fight already finished fading independently by then.
#
# Deliberately stays put in EnemyZone (an HBoxContainer) rather than
# being removed - an earlier version pulled a defeated enemy out so the
# container would auto-recenter the survivors, but seeing that in play
# reads as the whole group jumping mid-fight, not a clean kill. A
# defeated enemy just fades to nothing where it stood (play_defeat_
# sequence()) and keeps reserving its slot; survivors never move.
func _on_enemy_defeated(target: EnemyCombatant) -> void:
	target.is_defeated = true
	# Owed-lost logging (2026-09-08, Owed status pass) - BEFORE _clear_
	# combatant_statuses() below, which wipes target.statuses outright;
	# whatever's still on this enemy has to be read here or it's gone.
	# load(), not preload - see _collect_owed()'s own doc for why this
	# status is loaded lazily rather than joining the small set of
	# preloaded status consts at the top of this file.
	var owed_data: StatusEffectData = load("res://resources/statuses/owed.tres")
	var owed_active: ActiveStatus = _find_status(target.statuses, owed_data)
	if owed_active != null and owed_active.magnitude > 0:
		RunLogger.log_owed_lost_on_death(owed_active.magnitude)
	_clear_combatant_statuses(target)
	# EnemyData.defeat_sfx (see its own doc) - "" for every enemy without
	# one authored stays silent, exactly today's behavior. Same explicit-
	# guard-before-play_sfx() shape pain_turn_sfx's own read site uses.
	if target.data.defeat_sfx != "":
		AudioManager.play_sfx(target.data.defeat_sfx)
	# GUN/SUPPLY logging (2026-08-29, see run_logger.gd's own doc on what
	# this is watched for) - generic over WHICH enemy reads this one via
	# damage_source_enemy, not hardcoded to GUN/SUPPLY by name. A no-op
	# for every fight that doesn't use the mechanic (every `other.data.
	# damage_source_enemy` is null, so this loop never matches).
	for other in enemies:
		if other.data.damage_source_enemy == target.data:
			RunLogger.log_damage_source_defeated(turn_number)
			break
	if _living_enemies().is_empty():
		_on_all_enemies_defeated(target) # Itself async - fire-and-forget, same as the fade below.
	else:
		target.instance.play_defeat_sequence()

# A dead enemy's statuses end immediately (2026-08-27) - its own named
# step, not inlined above, specifically so a future "let defeated bodies
# linger a while before actually despawning" change (see DESIGN.md) has
# one clearly-labeled seam to insert into (deferring THIS call to
# whatever the real despawn step ends up being) instead of having to go
# find and unpick a bare statuses.clear() sitting inline in _on_enemy_
# defeated() above. Pushes the now-empty list to display too, same
# "caller owns pushing to display" split every other status mutation
# here follows - a defeated silhouette is about to fade regardless, but
# nothing here should assume that fade is the only thing that'll ever
# read this list again.
func _clear_combatant_statuses(combatant: EnemyCombatant) -> void:
	combatant.statuses.clear()
	combatant.instance.update_statuses(combatant.statuses)

# The bookkeeping steps every resolution path needs, regardless of WHICH
# way the battle ended - factored out (2026-08-23, see escape's own note
# below) rather than duplicated a third time. Sets _battle_outcome (read
# back by _on_post_battle_button_pressed() to decide where Continue
# goes) alongside battle_over, since the two are only ever meaningful
# together - nothing checks battle_over without also eventually wanting
# to know which outcome it was.
#
# _cancel_targeting()/chain_empowered are NOT something the pre-existing
# victory/defeat paths ever needed: both are only ever reached as a
# direct result of a card's own damage resolving, which means whatever
# card caused them is already past its own targeting stage by the time
# either fires, and the whole scene tears down shortly after anyway.
# Escape breaks that assumption - it is reachable from a dev button (and,
# later, a real in-battle action) at ANY point, including with a card
# still armed mid-targeting - so this needs to be real cleanup, not
# dead code copied for symmetry. Applied to all three paths here rather
# than only escape, since it's harmless where it's a no-op and keeping
# one function correct is simpler than remembering which paths need it.
#
# Statuses (2026-08-27) get the same "every path, one place" treatment:
# combat ending clears every combatant's statuses, player included, no
# matter which of the three ways it ended. Victory reaches this only
# once every enemy is already defeated, and _clear_combatant_statuses()
# already ran for each of those at defeat time (see _on_enemy_defeated())
# - looping `enemies` again here is a harmless no-op for them, not double
# work that matters, and is what actually covers defeat/escape, where
# enemies can still be alive (and still holding statuses) when the fight
# ends.
func _close_out_battle(outcome: RunLogger.BattleOutcome) -> void:
	battle_over = true
	_battle_outcome = outcome
	RunLogger.log_battle_end(outcome, energy)
	end_turn_button.disabled = true
	deck_button.disabled = true
	_cancel_targeting()
	chain_empowered = false
	_refresh_chain_indicators()
	player_statuses.clear()
	player_battle_visual.update_statuses(player_statuses)
	for combatant in enemies:
		_clear_combatant_statuses(combatant)
	rally_pool = 0
	player_battle_visual.reset_rally_pool()
	_trinket_free_card_armed = false
	_trinket_free_card_fired = false
	# Clears any surviving Leviathan mark (2026-08-29, mark attack pass) -
	# "clears at end of combat" applies regardless of which of the three
	# ways this fight ended. RunState.deck alone is enough to reach: a
	# marked card still in the draw/hand/discard rotation is also still in
	# RunState.deck (per-copy identity - the SAME object, not a copy), and
	# a marked card that was already PLAYED this fight already had its own
	# mark cleared at play time (_play_card()) regardless of removal_scope,
	# so it can never reach this loop still carrying one.
	for card: CardData in RunState.deck:
		card.marked_cost_modifier = 0

# The shared "the fight is over, hold a beat, then offer Continue"
# sequence - originally _on_all_enemies_defeated()'s own body, now shared
# with escape (see its own note): both dim the background (blocking
# every click/hover on cards/End Turn/the deck button the instant this
# runs, not just once visible), hold a beat, then fade Continue in at the
# same hand-relative position. `beat_await` is whatever should be awaited
# IN PARALLEL with the dim fade before that beat pause - victory passes
# the defeated enemy's own silhouette+flavor fade (last_target.instance.
# play_defeat_sequence); escape has no enemy death to show, so it passes
# an empty Callable and this waits on the dim tween itself instead. See
# the "Victory sequencing" consts above for the three exported durations
# (still named for victory - escape reuses the same pacing, not a
# separate tuned feel).
func _play_post_battle_beat(beat_await: Callable) -> void:
	dim_background.visible = true
	var dim_tween := create_tween()
	dim_tween.tween_property(dim_background, "color", Color(0, 0, 0, VICTORY_DIM_ALPHA), victory_dim_fade_sec)

	if beat_await.is_valid():
		await beat_await.call()
	else:
		await dim_tween.finished
	await get_tree().create_timer(victory_beat_pause_sec).timeout

	post_battle_button.text = "Continue"
	# hand_container is anchored to the BOTTOM of the screen (anchor_top/
	# bottom = 1.0), so its offset_top is measured from the bottom edge.
	# post_battle_button is anchored to the CENTER (anchor_top/bottom =
	# 0.5), measured from mid-screen instead - two different zero points.
	# Converting through an absolute Y here is what keeps this correct;
	# subtracting one offset from the other directly (as an earlier
	# version of this did) put Continue up near the top of the screen.
	var viewport_height := get_viewport().get_visible_rect().size.y
	var hand_top_y := viewport_height + hand_container.offset_top
	var button_bottom_y := hand_top_y - VICTORY_BUTTON_HAND_GAP_PX
	post_battle_button.offset_bottom = button_bottom_y - viewport_height / 2.0
	post_battle_button.offset_top = post_battle_button.offset_bottom - VICTORY_BUTTON_HEIGHT_PX
	post_battle_button.modulate.a = 0.0
	post_battle_button.visible = true
	var button_tween := create_tween()
	button_tween.tween_property(post_battle_button, "modulate:a", 1.0, victory_continue_fade_sec)
	await button_tween.finished
	post_battle_button.disabled = false

# No "Victory!" heading anymore - by default a win shows nothing but
# Continue (see EnemyData.defeat_flavor for the one enemy that gets
# something in that empty space instead). Sequenced, not instant, so the
# kill actually registers - see _play_post_battle_beat()'s own note for
# the dim/beat/Continue sequence this hands off to.
func _on_all_enemies_defeated(last_target: EnemyCombatant) -> void:
	_close_out_battle(RunLogger.BattleOutcome.VICTORY)
	AudioManager.play_sfx("victory")
	await _play_post_battle_beat(last_target.instance.play_defeat_sequence)

# Deliberately unchanged by the victory rework above - still instant: no
# dim, no sequencing, New Run just appears at BattleOverlay's baked
# default position (the hand-relative position _play_post_battle_beat()
# computes only applies to a WIN's or an escape's Continue).
func _on_player_defeated() -> void:
	_close_out_battle(RunLogger.BattleOutcome.DEFEAT)
	defeat_label.visible = true
	post_battle_button.text = "New Run"
	post_battle_button.visible = true
	post_battle_button.disabled = false
	AudioManager.play_sfx("defeat")

# --- Escape (INFRASTRUCTURE ONLY - see DESIGN.md's own note) ---
#
# A third way a combat node can resolve, alongside victory/defeat: the
# encounter ends with the enemy neither killed nor the player defeated.
# No distance mechanic, no enemy-side trigger, no damage scaling exist
# yet - this is only reachable today via DevEscapeButton (see _on_dev_
# escape_button_pressed()), a manual trigger to verify the resolution
# path itself works before anything real can invoke it.
#
# Shares victory's own presentation (_play_post_battle_beat(), the same
# dim-then-beat-then-Continue sequence - the fight still needs a visible
# beat, not an instant cut, or it reads as a crash) MINUS the defeated-
# enemy animation, since nothing died - passes an empty Callable so
# _play_post_battle_beat() waits on the dim tween itself instead.
#
# The blob touched to start this fight still marks itself defeated and
# vanishes on return to the field - see field_blob.gd's own updated note
# on blob_defeated meaning RESOLVED, not KILLED. That's deliberate, not
# an oversight: escape consumes the node exactly like a win does, it just
# grants nothing.
func _on_battle_escaped() -> void:
	_close_out_battle(RunLogger.BattleOutcome.ESCAPE)
	AudioManager.play_sfx("escape")
	await _play_post_battle_beat(Callable())

func _update_player_panel() -> void:
	# HP push REMOVED (2026-09-05, HP-signal pass) - player_battle_visual.gd
	# now subscribes to RunState.player_hp_changed directly (see its own
	# _ready()), which take_damage()/heal() already emit from inside
	# _set_player_hp() above. Block/absorb/rally-pool below have no such
	# signal (they're battle-local, not RunState fields) and every OTHER
	# call site of this function still needs them pushed regardless of
	# whether HP itself changed (e.g. a block-only gain) - only the HP line
	# itself was redundant, not this whole function.
	player_battle_visual.update_block(player_block)
	player_battle_visual.update_absorb(absorb_pool)
	# Re-anchors RallyOverlay to [player_hp, player_hp + rally_pool] every
	# time this runs, using whatever rally_pool currently is - a no-op
	# recompute for most callers (Toll consumption, block gained), but
	# what makes self-damage/a status tick correctly shrink the overlay's
	# right edge (see rally_pool's own doc: self-damage never grows the
	# pool, so it shrinks the "still recoverable" ceiling instead of
	# extending it - only reachable by recomputing from the CURRENT hp
	# here, not by leaving the overlay wherever it was last told to go).
	# _enemy_attack_player() calls this BEFORE rally_pool actually grows
	# (see its own note), so it additionally pushes its own corrected call
	# right after - everything else that changes player_hp already routes
	# through this one function, so this is the only other update site
	# that needs its own explicit push.
	player_battle_visual.update_rally_pool(RunState.player_hp, rally_pool)

# --- Turn loop ---
#
# Pressing End Turn kicks off a short sequence: discard the hand, let the
# enemy act (with pauses so its move is readable), advance its intent,
# then start the next player turn. `_run_enemy_turn()` uses `await` to
# pause partway through without freezing the rest of the game - anything
# else (animations, the OS) keeps running during those pauses; execution
# of THIS function just waits its turn to continue. Whatever calls a
# function that awaits (like _on_end_turn_button_pressed below) can
# itself `await` that call to wait for the whole thing to finish.

func _on_end_turn_button_pressed() -> void:
	if battle_over or input_locked:
		return
	if _pending_target_card_instance != null:
		_cancel_targeting()
		return
	input_locked = true
	end_turn_button.disabled = true
	deck_button.disabled = true

	# Rally's pool expires here, at the end of the Wanderer's own turn -
	# BEFORE the enemy phase below gets a chance to refill it for the
	# NEXT turn's window (see rally_pool's own doc for why this timing,
	# not _start_player_turn(), is "the end of the Wanderer's next turn").
	# The drain call runs BEFORE rally_pool is actually zeroed - it reads
	# whatever's currently displayed on the vitals bar as its own tween
	# start point, so the order here doesn't matter for correctness, but
	# reads more naturally as "animate the expiry, then the fact of it."
	player_battle_visual.drain_rally_pool(RunState.player_hp)
	rally_pool = 0

	_discard_entire_hand()
	await _run_enemy_turn()

	if not battle_over:
		_start_player_turn()
		input_locked = false
		end_turn_button.disabled = false
		deck_button.disabled = false

# Every living enemy acts in turn, one at a time, not simultaneously -
# snapshotting _living_enemies() once up front (not re-querying it each
# iteration) so this is a fixed sequence for the turn, same "who was
# alive when the turn started" every other roguelike deckbuilder assumes.
# Nothing in this game lets one enemy defeat another, so the only way
# this loop stops early is the PLAYER dying partway through (an earlier
# enemy's attack) - the battle_over check before each iteration is what
# stops the rest of the enemies from acting after that happens. The
# trailing _tick_escape_distance() call is what makes "end of enemy
# turn" (see EnemyData's own Escape note) literally mean the end of
# THIS function, not a separate hook elsewhere - it never runs at all if
# the loop returned early above, same as everything else past that point.
func _run_enemy_turn() -> void:
	for combatant in _living_enemies():
		if battle_over:
			return
		await _resolve_enemy_intent(combatant)
		# Structurally separate from _resolve_enemy_intent() above, not a
		# case inside it (see enemy_intent.gd's GROWTH doc and _advance_
		# growth_stage()'s own note) - a grower's turn is its OWN beat, not
		# folded into intent resolution, which is what keeps it running
		# unconditionally even when intent resolution itself was skipped
		# or interrupted this turn. no-ops immediately for every non-
		# grower (growth_stage_track_length <= 0), so every other enemy's
		# turn is completely unaffected by this call existing.
		await _advance_growth_stage(combatant)
	_tick_escape_distance()

# Resolves one enemy's current intent: a pause so it's readable, the
# actual effect (damage or block), another pause so the result is
# readable, then advancing to ITS OWN intent for next time. Called once
# per living enemy per turn (see _run_enemy_turn()) - the existing
# telegraph/resolve pauses around each call are already what gives
# consecutive enemies' actions readable separation, no extra pause
# needed between them.
func _resolve_enemy_intent(combatant: EnemyCombatant) -> void:
	# Statuses tick at the start of THIS enemy's own turn - see the Status
	# effects section note above _tick_statuses(). A TICK status could in
	# principle defeat this enemy here (no real status does this today -
	# see that same section); if it does, is_defeated below is already
	# true, so bail out before touching an intent that no longer has
	# anyone to belong to.
	#
	# Deliberately does NOT also remove expired statuses here (see _tick_
	# statuses()'s own note, 2026-08-27) - that's deferred to AFTER this
	# intent resolves, below, so a duration-1 MODIFIER status still gets
	# read by _apply_status_modifiers() further down before it's erased.
	# Erasing it here, before that read, would tick a debuff to 0 and
	# remove it before it ever touched the attack it was meant to weaken.
	_tick_statuses(combatant.statuses, func(amount): _deal_status_tick_damage_to_enemy(combatant, amount))
	combatant.instance.update_statuses(combatant.statuses)
	if battle_over or combatant.is_defeated:
		return
	var enemy_data: EnemyData = combatant.instance.enemy_data
	if enemy_data.intents.is_empty():
		return
	var intent: EnemyIntent = enemy_data.intents[combatant.current_intent_index]

	await get_tree().create_timer(ENEMY_TELEGRAPH_PAUSE).timeout

	if combatant.intent_interrupted_pending:
		# Overrides this ONE resolution only - current_intent_index and
		# turn_number (and therefore escalation) are completely untouched,
		# so _advance_enemy_intent() below still moves on exactly as it
		# always would. The pause is a held breath, not a reset - see
		# DESIGN.md's Bestiary: the Wardling. Same for a chain-payoff stun
		# (see card_effect.gd's STUN) - it cancels this one resolution,
		# nothing about the enemy's own pattern/escalation.
		combatant.intent_interrupted_pending = false
		combatant.instance.play_interrupt_flinch()
	else:
		# Escalation (see _escalated_intent_value()) applies here, at
		# resolution time, not just on the display - the number the intent
		# label showed the player IS what lands, never a preview of
		# something smaller.
		var value := _escalated_intent_value(enemy_data, intent, turn_number)
		if intent.type == EnemyIntent.IntentType.CHARGE_ATTACK:
			# EnemyData.charge_attack_value, not intent.value - see that
			# field's own doc for why a Charge-boss's window damage is read
			# from there instead of being (redundantly) authored a second
			# time on this intent. Escalation never applies to it (Leviathan
			# has no escalation_multipliers), so this simply replaces the
			# line above rather than layering on top of it.
			value = enemy_data.charge_attack_value
		if intent.type == EnemyIntent.IntentType.ATTACK:
			# Encounter-linked damage (GUN/SUPPLY, see _encounter_linked_
			# damage()'s own doc) - a no-op for every enemy without damage_
			# source_enemy set. Gated to ATTACK, same scoping the OUTGOING_
			# DAMAGE modifier pass just below already uses, for the same
			# reason: this concept has no meaning for DEFEND/WIND_UP/etc.
			value = _encounter_linked_damage(enemy_data, value)
		if intent.status_data != null:
			# Deliberately OUTSIDE the match below and never routed through
			# _enemy_attack_player() - see EnemyIntent.status_data's own
			# doc for why this has to stay a separate code path: applying
			# the status here only ever attaches an ActiveStatus (via the
			# same _apply_status() CardEffect already uses), it never
			# moves HP, so it can't touch rally_pool or Toll by
			# construction, not by a guard added here. Whatever damage the
			# status itself deals happens later, at the next turn
			# boundary, through _tick_statuses()/_deal_status_tick_damage_
			# to_player() (unchanged), same as every other status tick.
			_apply_status(player_statuses, intent.status_data)
			player_battle_visual.update_statuses(player_statuses)
		match intent.type:
			EnemyIntent.IntentType.ATTACK, EnemyIntent.IntentType.CHARGE_ATTACK:
				# The lunge fires alongside the hit itself, not the intent
				# refresh below - see DESIGN.md's Combat Telegraphing note:
				# the player has to see cause (the jerk, the damage landing)
				# before the readout resets, not the two happening together.
				combatant.instance.play_attack_lunge()
				# _update_intent_display() mirrors this exact adjustment now
				# (2026-08-29, intent-display-modifier pass, its own separate
				# commit) - the two paths can no longer disagree about what a
				# MODIFIER status does to a queued attack. See that
				# function's own doc for the bug this closed and why it sat
				# unnoticed until BOSS_01 (the first status that ever sets
				# category == MODIFIER on an enemy in a live fight) needed it
				# to actually be true.
				var amplified := _apply_status_modifiers(value, combatant.statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
				_enemy_attack_player(amplified, combatant)
				if enemy_data.damage_source_enemy != null:
					# GUN/SUPPLY logging (see run_logger.gd's own doc on what
					# this is watched for) - the FINAL landed value, same
					# number the player's damage number popup shows, not the
					# pre-modifier bracket value.
					RunLogger.log_linked_attack_step(amplified)
				if _is_charge_buff_finishing_turn(enemy_data, combatant):
					# The Charged buff's own finishing blow (see _is_charge_
					# buff_finishing_turn()'s own doc) - a second identical
					# hit, paced with the same beat every other enemy-turn
					# pause in this file already uses, so the player
					# actually sees two separate hits land rather than one
					# cut off by the other. Guarded the same way _advance_
					# growth_stage() guards its own post-await work - either
					# hit could in principle end the battle first.
					await get_tree().create_timer(ENEMY_RESOLVE_PAUSE).timeout
					if not battle_over and not combatant.is_defeated:
						combatant.instance.play_attack_lunge()
						_enemy_attack_player(amplified, combatant)
			EnemyIntent.IntentType.DEFEND:
				# Deliberately no lunge/animation here - see enemy.gd's
				# play_attack_lunge() note: DEFEND stays visually calm.
				_enemy_gain_block(combatant, value)
			EnemyIntent.IntentType.WIND_UP:
				# Still a genuine no-op for game state (see enemy_intent.gd's
				# WIND_UP doc - no damage, no block, nothing that needs a
				# resolution branch) - this case exists ONLY to play the
				# telegraph sound, the audio half of the icon's own "not yet"
				# signal. Generic over any future WIND_UP enemy, exactly like
				# the icon itself - not Beachwrack-specific code, even though
				# it's the only enemy using it today.
				AudioManager.play_sfx("wind_up")
			EnemyIntent.IntentType.MARK:
				_resolve_mark_attack(enemy_data, combatant)

	# NOW it's safe to erase anything that just ticked to 0 - this
	# intent's own modifier read (above, if it was an ATTACK) already
	# happened while the status was still present. See _tick_statuses()'s
	# own note for why this can't run any earlier.
	_remove_expired_statuses(combatant.statuses)
	combatant.instance.update_statuses(combatant.statuses)

	await get_tree().create_timer(ENEMY_RESOLVE_PAUSE).timeout

	# is_defeated, not just battle_over - this enemy can die from
	# something that fires DURING its own attack's resolution above
	# (Retaliation - see _check_retaliation_trigger()'s own call into
	# _deal_damage_to_enemy() - is the live example, but any damage
	# source reaching _deal_damage_to_enemy() mid-resolution qualifies)
	# without ending the whole battle, if other enemies are still up.
	# _advance_enemy_intent() has no notion of "defeated," and unconditionally
	# re-fades IntentDisplay/flavor back IN with the next intent - exactly
	# undoing play_defeat_sequence()'s own fade-out (already fired, fire-
	# and-forget, from _on_enemy_defeated() above), which is what left a
	# dead enemy's intent icon and flavor text stuck on screen. A normal
	# card-play kill never hit this, since nothing on the PLAYER's turn
	# ever calls _advance_enemy_intent() for that enemy in the first
	# place - only ITS OWN turn resolution does, which is exactly the
	# path this guards.
	if not battle_over and not combatant.is_defeated:
		# A Charge-boss's own advancement replaces the normal fixed-loop/
		# erratic branch entirely (2026-08-29, BOSS_01 pass) - see
		# _advance_boss_charge()'s own doc for why this mirrors growth_
		# stage_track_length's "own dedicated state, own dedicated advance
		# function" shape rather than adding a case to _advance_enemy_
		# intent() itself. Every other enemy (charge_window_turns <= 0)
		# falls through to that exact same call, completely unaffected.
		if enemy_data.charge_window_turns > 0:
			await _advance_boss_charge(combatant)
		else:
			await _advance_enemy_intent(combatant)

func _enemy_attack_player(amount: int, combatant: EnemyCombatant) -> void:
	amount = _apply_status_modifiers(amount, player_statuses, StatusEffectData.ModifierTarget.INCOMING_DAMAGE)
	_consume_next_hit_statuses()
	var result := _resolve_damage(amount, RunState.player_hp, player_block, absorb_pool)
	_set_player_hp(result["hp"], RunLogger.TollSource.ENEMY)
	player_block = result["block"]
	absorb_pool = result["absorb"]
	_update_player_panel()
	RunLogger.log_damage_blocked(result["absorbed"])
	RunLogger.log_absorb_used(result["absorbed_by_absorb"])
	if result["damage_to_hp"] > 0:
		RunLogger.log_damage_taken(result["damage_to_hp"])
		_spawn_player_damage_number(result["damage_to_hp"], RunLogger.TollSource.ENEMY)
		# Rally's pool fill (see rally_pool's own doc) - THIS function is
		# specifically an ENEMY ATTACK landing, distinct from _deal_self_
		# damage()/_deal_status_tick_damage_to_player() (neither of which
		# ever touches rally_pool), so "unblocked enemy-attack damage
		# only" falls out of simply being the one call site, no extra
		# source-checking needed. Same damage_to_hp figure (post-block,
		# post-status-modifier) Toll/debris-spawn/Retaliation already key
		# off, for the same "not fully blocked" reasons.
		rally_pool += result["damage_to_hp"]
		# _update_player_panel() above already pushed the vitals bar once
		# this turn, before rally_pool grew - this corrected second push
		# is what the overlay's animation actually keys off (see this
		# function's own header note above).
		player_battle_visual.update_rally_pool(RunState.player_hp, rally_pool)
		# EnemyData.attack_impact_sfx (empty for every enemy except the
		# Beachwrack today) lets ONE enemy's landed hit sound different
		# from the shared generic cue - see its own doc comment.
		var impact_sfx: String = "damage_player" if combatant.data.attack_impact_sfx == "" else combatant.data.attack_impact_sfx
		# Encounter-linked override (GUN/SUPPLY, see _encounter_linked_
		# impact_sfx()'s own doc) - layered on TOP of the flat override
		# above, not instead of it: a no-op for every enemy without
		# damage_source_enemy set, so attack_impact_sfx's own existing
		# behavior (Beachwrack) is completely unaffected.
		impact_sfx = _encounter_linked_impact_sfx(combatant.data, impact_sfx)
		AudioManager.play_sfx(impact_sfx)
		_check_debris_spawn_trigger(combatant)
		_check_retaliation_trigger(result["damage_to_hp"], combatant)
	elif amount > 0:
		# Every point of this attack was absorbed by block - distinct cue
		# from a PARTIAL block, which still plays damage_player above
		# (some damage got through, so it should still read as a hit).
		# amount > 0 excludes the degenerate case of a 0-value attack
		# "fully blocking" nothing.
		AudioManager.play_sfx("full_block")
	if RunState.player_hp <= 0:
		_on_player_defeated()

# --- Next-hit-consumed statuses (Braced, resources/cards/brace.tres;
# Unflinching, resources/cards/classes/wanderer/unflinching.tres - both
# CardEffect.EffectType.APPLY_STATUS, see NEXT_HIT_CONSUMED_STATUSES'S
# own doc above) ---
#
# Consumption hook for _enemy_attack_player()'s own _consume_next_hit_
# statuses() call, right after _apply_status_modifiers() computes
# `amount` above - same "find by resource identity, remove synchronously"
# shape _check_retaliation_trigger() below establishes, deliberately
# simpler: both statuses' own damage reduction already happened
# generically, inside that same _apply_status_modifiers() call (a plain
# MODIFIER/MULTIPLY status either way - see status_effect_data.gd's own
# doc), so there's no reflected-damage math or RallyWindow to manage
# here, only whichever of the two is active to consume.
#
# Called unconditionally, NOT gated on result["damage_to_hp"] > 0 the way
# Retaliation's own trigger is - each status consumes on the first HIT
# (this function running at all), not the first hit that gets through
# block. Deliberately NOT generalized into clears_on_trigger support
# inside _apply_status_modifiers() itself - two cards don't justify that;
# see status_effect_data.gd's own doc on why that flag documents intent
# without branching on anything by itself.
#
# Multi-hit intents call _enemy_attack_player() once per hit (see
# _advance_enemy_intent()'s own two-call sequence for a 2-hit attack, and
# _erupt_mushroom()'s single call for a 1-hit one) - a 3x3 intent would
# call it three separate times, so whichever of these is active is found
# and removed on the FIRST of those calls and is simply absent (an
# ordinary no-op) by the second and third, which is what makes "one hit
# reduced" true here without this function needing to know anything
# about hit counts itself. Braced and Unflinching are never both
# consumed by the SAME hit in practice (each is its own APPLY_STATUS,
# and nothing stacks the two together today), but the loop below removes
# every match it finds regardless, rather than assuming at most one.
func _consume_next_hit_statuses() -> void:
	var removed_any := false
	for status_data in NEXT_HIT_CONSUMED_STATUSES:
		var active := _find_status(player_statuses, status_data)
		if active == null:
			continue
		_remove_status(player_statuses, active)
		removed_any = true
	if removed_any:
		player_battle_visual.update_statuses(player_statuses)

# --- Debris spawn (see EnemyData.debris_spawn_enemy's own note) ---
#
# Checked here, the same "right after damage lands" timing _check_pain_
# turn_trigger() already uses for the enemy-side equivalent - ANY
# damage getting through counts (result["damage_to_hp"] > 0 above, the
# same threshold "not fully blocked" already means everywhere else in
# this codebase), not just an unblocked hit. Guarded by debris_spawn_
# used so this can never fire twice for the same combatant even if it
# lands its attack again later in the same fight.
# --- Retaliation (see resources/cards/classes/wanderer/retaliation.tres,
# CardEffect.EffectType.TOLL_RETALIATE) ---
#
# damage_taken is result["damage_to_hp"] from the SAME _resolve_damage()
# call _enemy_attack_player() already used to move RunState.player_hp -
# not a separately recomputed number. That matters here specifically: a
# partially-blocked hit still triggers (per this card's own brief -
# "unblocked" for this purpose means the same "not fully blocked"
# threshold _check_debris_spawn_trigger() above already uses, not a
# stricter "block was exactly 0" reading), and it has to reflect exactly
# the damage that actually landed post-block, post-status-modifier - the
# same figure Toll itself accrues from (see _set_player_hp()'s own
# before/after-delta note) - never the attack's raw pre-block amount.
# Called from the "damage_to_hp > 0" branch above, so a fully-blocked hit
# (which lands in the elif below instead) never reaches this at all -
# the status stays primed, untouched, exactly as this card's brief wants.
#
# Removal is synchronous, via _remove_status(), the instant this fires -
# not deferred to any tick pass (see _remove_status()'s own note on why
# that matters for a multi-enemy turn: _run_enemy_turn() awaits each
# combatant's _resolve_enemy_intent() fully before the next one starts,
# so a status gone before this function returns can never be seen active
# by a second attacker later in the same enemy phase).
#
# The reflected hit deliberately skips player_statuses' own OUTGOING_
# DAMAGE modifiers and any equipped weapon's CATEGORY_DAMAGE bonus -
# same precedent The Creditor's own weapon reflect already set (see
# _reflect_self_damage()): a reflected hit is its own thing, not another
# card's damage going through the player's usual outgoing pipeline a
# second time. _deal_damage_to_enemy() still applies the TARGET's own
# incoming-damage modifiers and Outbound's escape falloff unconditionally
# either way, same as every other damage source that reaches it.
#
# Never touches RunState.player_hp/toll at all - structurally impossible
# to generate Toll from this path, since Toll only ever accrues inside
# _set_player_hp() (see its own doc), which this never calls. Reaches
# the enemy through the exact same _deal_damage_to_enemy() every other
# outgoing hit uses, so it triggers _check_pain_turn_trigger() exactly
# like any other damage source would (same as weapon_reflect/a chain
# payoff already do) - not a special case, just this function's own
# unconditional behavior for anything that calls it.
func _check_retaliation_trigger(damage_taken: int, source: EnemyCombatant) -> void:
	var active := _find_status(player_statuses, RETALIATION_PRIMED_STATUS)
	if active == null:
		return
	_remove_status(player_statuses, active)
	player_battle_visual.update_statuses(player_statuses)
	var reflected := roundi(damage_taken * RETALIATION_DAMAGE_MULTIPLIER_PERCENT / 100.0)
	# Its own RallyWindow (2026-08-26, rally-recovery-rework) - this fires
	# from an ENEMY's attack on the player, with no card being played at
	# all, so it can't join a card's window the way weapon reflect does;
	# it gets one recovery off its own single hit instead.
	_deal_damage_to_enemy(source, reflected, false, false, true, RallyWindow.new())

func _check_debris_spawn_trigger(combatant: EnemyCombatant) -> void:
	var spawn_data: EnemyData = combatant.data.debris_spawn_enemy
	if spawn_data == null or combatant.debris_spawn_used or battle_over:
		return
	combatant.debris_spawn_used = true
	_spawn_additional_enemy(spawn_data)

# Brings a second enemy into a fight already in progress - no existing
# path did this before the Beachwrack (every enemy normally spawns
# once, together, from _spawn_enemies() at battle start). Deliberately
# does NOT rescale the already-present enemy(s), or apply _multi_enemy_
# scale_factor() to the newcomer's SILHOUETTE (see DESIGN.md's own note
# on this) - the newcomer's creature renders at its own normal solo
# size, same as the Beachwrack itself stays at its own original size. A
# real visual trade-off, not an oversight - full retroactive rescaling
# would mean re-deriving cluster_width_px/bar_width_px/silhouette_scale
# for creature(s) already laid out, which nothing in this codebase does
# today.
#
# The newcomer's reserved LAYOUT BOX still reads snug against its host,
# though (bar_width_px scaled by DEBRIS_SPAWN_PADDING_SCALE, cluster_
# width_padding_px multiplied by the same factor before set_enemy_data()
# ever computes cluster_width_px from it - see that const's own doc for
# why this moved off cluster_width_px directly) - this is a DISTANCE fix,
# not a size fix: EnemyZone (an HBoxContainer) packs each enemy into its
# own reserved horizontal box, and the newcomer getting a full-padding
# solo-shaped box (meant for a creature fought alone, centered in the
# whole zone) left it reading as a second, separate encounter rather than
# something that just shook loose from the Beachwrack right next to it -
# see DESIGN.md's Fiction note. A smaller padding budget still pulls the
# newcomer's box snug against its neighbor while the creature INSIDE it
# renders at its own normal, fully recognizable size, unaffected either
# way - same outcome the old cluster_width_px multiply produced, reached
# through the box's own new derivation instead of overriding it after
# the fact.
func _spawn_additional_enemy(data: EnemyData) -> void:
	# Unlike _spawn_enemies() above, EnemyZone's child count CAN change
	# after this battle's own initial separation was set - a debris-
	# spawned enemy lands mid-fight, on top of whatever was already there
	# (defeated enemies stay as children too - see _on_enemy_defeated() -
	# so get_child_count() already correctly counts them regardless of
	# alive/dead). +1 accounts for the enemy this function is ABOUT to
	# add, read before add_child() below same as _spawn_enemies() reads
	# its own count before spawning.
	_apply_enemy_zone_separation(enemy_zone.get_child_count() + 1)
	var instance: Enemy = ENEMY_SCENE.instantiate()
	instance.cluster_width_padding_px *= DEBRIS_SPAWN_PADDING_SCALE
	instance.bar_width_px *= DEBRIS_SPAWN_PADDING_SCALE
	enemy_zone.add_child(instance)
	instance.set_enemy_data(data)

	var combatant := EnemyCombatant.new()
	combatant.data = data
	combatant.instance = instance
	combatant.max_hp = data.max_hp
	combatant.hp = combatant.max_hp
	if data.erratic_intent_selection and not data.intents.is_empty():
		# Same turn-one-lock routing _spawn_enemies() uses above - a
		# debris-spawned Sputter's own first intent is still its "turn
		# one" for this purpose, same per-enemy (not per-battle) initial-
		# vs-advance split every erratic enemy already follows.
		if data.intents.any(func(i: EnemyIntent): return i.turn_one_locked):
			combatant.current_intent_index = _pick_erratic_initial_index_turn_one_locked(data)
		else:
			combatant.current_intent_index = _pick_erratic_initial_index(data)
	# Same lambda-captures-combatant trick _spawn_enemies() itself uses,
	# so a click on this new silhouette resolves against the right
	# combatant exactly like every enemy spawned at battle start.
	instance.enemy_clicked.connect(func(): _on_enemy_clicked(combatant))
	instance.right_clicked.connect(_cancel_targeting)
	enemies.append(combatant)
	RunLogger.log_enemy_spawn(data.enemy_name)
	_show_initial_intent_or_growth(combatant)

	# "Debris shaking loose and reassembling," not "an enemy appearing
	# from nowhere" (see DESIGN.md's Fiction note) - a fade-in rather
	# than an instant pop, plus the same screen-shake/sound language
	# already established for a landed hit (see _deal_damage_to_enemy()),
	# at the normal (not chain-payoff) tier - this is a consequence of a
	# hit connecting, not the hit itself.
	instance.modulate.a = 0.0
	var spawn_tween := create_tween()
	spawn_tween.tween_property(instance, "modulate:a", 1.0, DEBRIS_SPAWN_FADE_SEC)
	AudioManager.play_sfx("debris_spawn")
	_play_screen_shake(normal_hit_shake_px, normal_hit_shake_duration_sec)

func _enemy_gain_block(combatant: EnemyCombatant, amount: int) -> void:
	combatant.block += amount
	combatant.instance.update_block(combatant.block)

func _advance_enemy_intent(combatant: EnemyCombatant) -> void:
	var enemy_data: EnemyData = combatant.instance.enemy_data
	if enemy_data.erratic_intent_selection:
		# The Tideworn (see DESIGN.md's Bestiary) - no throughline to step
		# through in order, a fresh independent pick every time, repeats
		# allowed. Every other enemy falls through to the normal fixed
		# loop below, completely unaffected.
		combatant.current_intent_index = _pick_erratic_intent_index(enemy_data, combatant.current_intent_index)
	else:
		combatant.current_intent_index = (combatant.current_intent_index + 1) % enemy_data.intents.size()
	await _update_intent_display(combatant, true)

# A Charge-boss's own advancement (2026-08-29, BOSS_01 pass; REWORKED
# 2026-08-29 - removes the old TELEGRAPH/SWING preamble entirely, see
# enemy_data.gd's Charge section for the current shape) - called INSTEAD
# OF _advance_enemy_intent() above (see _resolve_enemy_intent()'s own
# tail), same "own dedicated state, own dedicated advance function" shape
# _advance_growth_stage() already established for the Mushroom, adapted
# here for an enemy that (unlike a grower) DOES still resolve real
# ATTACK/CHARGE_ATTACK intents through the normal match in _resolve_
# enemy_intent() - only WHICH intent comes next is custom, not whether
# intent resolution happens at all. Ends by calling _update_intent_
# display() itself, exactly like _advance_enemy_intent() does - this is
# a drop-in replacement for that call, not a second, parallel step the
# way _advance_growth_stage() is (see _run_enemy_turn()'s own loop).
func _advance_boss_charge(combatant: EnemyCombatant) -> void:
	var enemy_data: EnemyData = combatant.instance.enemy_data
	var charge_attack_index := _charge_intent_index(enemy_data, EnemyIntent.IntentType.CHARGE_ATTACK)
	match combatant.charge_phase:
		BossChargePhase.NORMAL:
			# Deliberately does NOT advance the countdown AT ALL while the
			# buff is still active - see EnemyCombatant.charge_normal_
			# turns_elapsed's own doc for why this alone is what guarantees
			# "a new window should not begin while the buff is still
			# active" with no separate overlap check needed anywhere else.
			# The boss just keeps attacking normally (at its own current,
			# possibly-buffed strength via the live status, randomly
			# between the baseline attacks) every turn the buff holds.
			var buffed := _find_status(combatant.statuses, enemy_data.charge_buff_status) != null
			if not buffed:
				combatant.charge_normal_turns_elapsed += 1
				if combatant.charge_normal_turns_elapsed >= enemy_data.turns_before_first_telegraph:
					combatant.charge_phase = BossChargePhase.WINDOW
					combatant.charge_window_turns_elapsed = 0
					combatant.charge_window_damage = 0
					# Clamped against CURRENT hp at the moment this window
					# begins - see EnemyCombatant.charge_effective_threshold's
					# own doc for why a late-fight window can't demand more
					# than the boss actually has left.
					combatant.charge_effective_threshold = mini(enemy_data.charge_damage_threshold, combatant.hp)
					combatant.current_intent_index = charge_attack_index
					RunLogger.log_boss_charge_attempted()
					# Enemy-side display state (2026-08-29, charge-display pass) -
					# set the INSTANT the window actually opens, mirroring this
					# exact transition rather than duplicating it (see Enemy.
					# _charging/set_charge_badge()'s own doc). set_charging(true)
					# persists the "Damage: X / Y" flavor line for the whole
					# window regardless of hover; set_charge_badge() puts a
					# turns-remaining badge in StatusBadgeRow (3, going into this
					# first window turn) - update_statuses() is what actually
					# pushes the badge to the row (see its own doc for why
					# set_charge_badge() alone doesn't render anything).
					combatant.instance.set_charging(true)
					combatant.instance.set_charge_badge(enemy_data.charge_indicator_status, enemy_data.charge_window_turns - combatant.charge_window_turns_elapsed)
					combatant.instance.update_statuses(combatant.statuses)
					await _update_intent_display(combatant, true)
					return
			combatant.current_intent_index = _pick_baseline_attack_index(enemy_data)
		BossChargePhase.WINDOW:
			combatant.charge_window_turns_elapsed += 1
			if combatant.charge_window_turns_elapsed >= enemy_data.charge_window_turns:
				# THE check - binary, at the end of the window's own last
				# turn (this feature's own brief). Accumulated damage was
				# already fully tallied by the time this runs (see _deal_
				# damage_to_enemy()'s own gated hook, which fires during
				# THIS turn's earlier resolution, well before this
				# advancement step).
				var interrupted := combatant.charge_window_damage >= combatant.charge_effective_threshold
				RunLogger.log_boss_charge_check(interrupted, combatant.charge_window_damage)
				if not interrupted:
					# Constructs the buff via the normal, untouched _apply_
					# status() (see status_effect_data.gd/active_status.gd -
					# neither is modified by this feature), then overwrites
					# the fresh ActiveStatus's own magnitude/turns_remaining
					# directly from THIS boss's own exported tunables rather
					# than trusting charge_buff_status.tres's own baked-in
					# default_magnitude/default_duration_turns - see
					# EnemyData.charge_buff_multiplier's own doc for why.
					_apply_status(combatant.statuses, enemy_data.charge_buff_status)
					var active := _find_status(combatant.statuses, enemy_data.charge_buff_status)
					active.magnitude = roundi((enemy_data.charge_buff_multiplier - 1.0) * 100.0)
					active.turns_remaining = enemy_data.charge_buff_duration_turns
					# update_statuses() moved to the unconditional call below
					# (2026-08-29, charge-display pass) - it now also has to
					# clear the charge badge on EVERY window close, not just
					# this branch, so one shared call covers both instead of
					# this branch pushing its own and the other silently relying
					# on the badge clear's own call to also cover it.
				combatant.charge_phase = BossChargePhase.NORMAL
				# The window just ended - whether the charge paid off or
				# was interrupted, the boss resumes attacking (buffed or
				# not, randomly between the baseline attacks) starting NEXT
				# turn, same as NORMAL's own tail above. Leaving this at
				# charge_attack_index here would repeat the old idle_index
				# bug this same line already fixed once (2026-08-29): the
				# phase flips to NORMAL right above, but without this line
				# current_intent_index would still be pointing at the
				# charge-window's own attack slot, costing the boss (and
				# the fresh buff, if one was just granted) one full turn at
				# the wrong value before NORMAL's own case ever got a
				# chance to correct it.
				combatant.current_intent_index = _pick_baseline_attack_index(enemy_data)
				combatant.charge_normal_turns_elapsed = 0
				combatant.charge_window_turns_elapsed = 0
				combatant.charge_window_damage = 0
				# Clears BOTH Enemy-side display flags on EVERY window close -
				# interrupted or buffed, same single code path (see this
				# branch's own doc above for why this replaces the narrower
				# buff-only update_statuses() call that used to live inside
				# the `if not interrupted:` block above). set_charging(false)
				# lets the flavor line go back to hover-only; clear_charge_
				# badge() removes the countdown badge; update_statuses() is
				# what actually pushes both the badge removal AND (when a
				# buff was just applied above) the buff's own badge to
				# StatusBadgeRow in one render.
				combatant.instance.set_charging(false)
				combatant.instance.clear_charge_badge()
				combatant.instance.update_statuses(combatant.statuses)
			else:
				combatant.current_intent_index = charge_attack_index
				# Countdown refresh (2026-08-29, charge-display pass) - same
				# set_charge_badge()+update_statuses() pairing as window-open
				# above, just recomputing magnitude for this turn's remaining
				# count (charge_window_turns_elapsed was already incremented
				# at the top of this WINDOW case). set_charging() is NOT
				# re-called here - it's already true from window-open and
				# only needs to flip at the two real phase transitions.
				combatant.instance.set_charge_badge(enemy_data.charge_indicator_status, enemy_data.charge_window_turns - combatant.charge_window_turns_elapsed)
				combatant.instance.update_statuses(combatant.statuses)
	await _update_intent_display(combatant, true)

# Which baseline attack a Charge-boss shows outside its charge window
# (2026-08-29 rework; EXTENDED 2026-08-29, mark attack pass) - a free,
# equally-weighted pick between every plain ATTACK-type intent this enemy
# authors (Leviathan: 14, 10) PLUS every MARK-type intent (Leviathan: the
# one mark attack - see _resolve_mark_attack() below) - same WeightedRandom.
# pick()-over-erratic_weight technique _pick_erratic_intent_index() already
# uses, just scoped to these two types only so it can never land on the
# CHARGE_ATTACK-type entry (see that type's own doc in enemy_intent.gd for
# why it's a distinct type in the first place - MARK is a distinct type
# for the exact same "found unambiguously among several baseline options"
# reason). Turn 1 itself never calls this - the boss's very first intent
# comes from EnemyCombatant.current_intent_index's own default (0), which
# is why Leviathan's `intents` array authors its 14-damage attack at
# index 0, not from any logic here (see _spawn_enemies()/_show_initial_
# intent_or_growth() - a non-erratic enemy's first intent is whatever
# index 0 is).
func _pick_baseline_attack_index(enemy_data: EnemyData) -> int:
	var weights: Dictionary = {}
	for i in enemy_data.intents.size():
		var type := enemy_data.intents[i].type
		if type == EnemyIntent.IntentType.ATTACK or type == EnemyIntent.IntentType.MARK:
			weights[i] = enemy_data.intents[i].erratic_weight
	return int(WeightedRandom.pick(weights))

# Leviathan's third baseline option (2026-08-29, mark attack pass) - see
# EnemyIntent.IntentType's own MARK doc for why this is a distinct intent
# type rather than a third ATTACK entry. Marks ONE specific CardData
# instance (never a card TYPE - see CardData.marked_cost_modifier's own
# doc for why per-copy identity, landed in 7ffd9d0, is what makes this
# safe) with +enemy_data.mark_cost_increase energy cost until it's played.
#
# Pile choice: discard_pile if it has anything in it, draw_pile only as
# the fallback for an EMPTY discard - this feature's own brief states
# that rule explicitly, distinct from (and checked before) the separate
# "no UNMARKED candidate" rule below. Never both piles at once - a card
# sitting in hand is never a candidate at all (this boss's mark can only
# ever be discovered by looking at the discard/draw piles, never by
# already holding the card).
#
# Does not stack (this feature's own brief): candidates are filtered to
# marked_cost_modifier == 0 first, so a card that's already marked is
# simply invisible to this pick, same as any other exclusion filter in
# this file (see _erratic_locked_followup_indices() for the same shape
# applied to intent selection). If the CHOSEN pile has cards but every
# one of them is already marked, this does nothing THIS turn - it does
# NOT fall through to the other pile, matching this feature's own brief
# precisely ("if every candidate is already marked, the attack does
# nothing this turn"), not a broader "try harder to find any target"
# rule this brief never asked for.
func _resolve_mark_attack(enemy_data: EnemyData, combatant: EnemyCombatant) -> void:
	var pile: Array[CardData] = discard_pile if not discard_pile.is_empty() else draw_pile
	var pile_label := "discard pile" if not discard_pile.is_empty() else "draw pile"
	var candidates: Array[CardData] = pile.filter(func(c): return c.marked_cost_modifier == 0)
	if candidates.is_empty():
		return
	var marked: CardData = candidates.pick_random()
	marked.marked_cost_modifier = enemy_data.mark_cost_increase
	# See Enemy.announce()'s own doc for why this can't just be read off
	# the card's own face right now - it isn't rendered as a live Card
	# node anywhere on screen while it's sitting in a pile, only data.
	combatant.instance.announce("Marks %s (%s)" % [marked.card_name, pile_label])

# Which intent indices are "locked" - reachable ONLY by being the exact
# next entry after a WIND_UP in the array, never by a free random pick.
# The wind-up/swing pairing (see EnemyIntent.IntentType's own WIND_UP
# doc) is a hard fairness promise, not a preference like the no-
# consecutive-idle guardrail below - the player must always see a
# wind-up exactly one turn before its swing, every time, so the swing
# can never be reached any other way (including as the very first
# intent shown at spawn - see _pick_erratic_initial_index() below).
# Empty for any enemy with no WIND_UP intent (e.g. the Tideworn) -
# _pick_erratic_intent_index()'s existing behavior for those enemies is
# completely unaffected.
func _erratic_locked_followup_indices(enemy_data: EnemyData) -> Array[int]:
	var locked: Array[int] = []
	for i in enemy_data.intents.size():
		if enemy_data.intents[i].type == EnemyIntent.IntentType.WIND_UP:
			locked.append((i + 1) % enemy_data.intents.size())
	return locked

# Erratic selection's guardrails (see DESIGN.md's Bestiary: the Tideworn
# and the Beachwrack). Three rules, checked in order:
#
# 1. A WIND_UP is ALWAYS immediately followed by its own paired swing -
#    a forced transition, not a random pick among candidates. Reuses
#    the array's own authored order (the entry right after a WIND_UP IS
#    its paired hit), the same relationship the non-erratic fixed-loop
#    branch in _advance_enemy_intent() already relies on.
# 2. Otherwise: an IDLE turn can never be immediately followed by
#    another IDLE turn, so the player is never more than one turn away
#    from a real threat no matter how the sequence has gone so far -
#    and any intent locked by _erratic_locked_followup_indices() above
#    is excluded from this free pool entirely, since it may only be
#    reached via rule 1.
# 3. Any intent flagged EnemyIntent.no_immediate_repeat (2026-09-08, the
#    Sputter's own Block) can't be picked again the turn right after it
#    was picked - a PER-INTENT exclusion, unlike rule 2's type-wide one,
#    so it only ever affects whichever specific intent authors it (the
#    Sputter's Block reading as a stall twice in a row, nothing to do
#    with every DEFEND intent on every enemy - the Beachwrack's own
#    Brace is untouched, since it never sets this flag).
#
# Every other pairing (attack-into-attack, attack-into-idle, idle-into-
# attack, ...) stays a free pick via WeightedRandom.pick(), weighted by
# each candidate's own EnemyIntent.erratic_weight (default 1.0 = equal
# odds, same result a plain unweighted pick already gave) - these three
# exclusions don't touch how OFTEN anything comes up overall, just what
# it can immediately follow; erratic_weight is the knob for "how often,"
# per intent, when the default even split isn't what's wanted (see the
# Beachwrack's Settle intent).
#
# Only reached from _advance_enemy_intent() above, so previous_index is
# always a real prior turn - the very first intent at spawn goes through
# _pick_erratic_initial_index() below instead, which needs rule 1's
# exclusion but has no "previous" turn for rules 2/3 to apply against.
func _pick_erratic_intent_index(enemy_data: EnemyData, previous_index: int) -> int:
	var previous_type := enemy_data.intents[previous_index].type
	if previous_type == EnemyIntent.IntentType.WIND_UP:
		return (previous_index + 1) % enemy_data.intents.size()

	var locked := _erratic_locked_followup_indices(enemy_data)
	var previous_was_idle := previous_type == EnemyIntent.IntentType.IDLE
	var weights: Dictionary = {}
	for i in enemy_data.intents.size():
		if i in locked:
			continue
		if previous_was_idle and enemy_data.intents[i].type == EnemyIntent.IntentType.IDLE:
			continue
		if i == previous_index and enemy_data.intents[i].no_immediate_repeat:
			continue
		weights[i] = enemy_data.intents[i].erratic_weight
	return int(WeightedRandom.pick(weights))

# The very first intent an erratic enemy ever shows, at spawn (called
# from both _spawn_enemies() and _spawn_additional_enemy()) - free and
# weighted by erratic_weight like _pick_erratic_intent_index() above,
# EXCEPT it also excludes _erratic_locked_followup_indices() - a swing
# intent can only ever be reached the turn right after its own wind-up
# (rule 1 above), and there IS no previous turn at spawn, so it can
# never be the very first thing shown either. Without this, a fresh
# Beachwrack fight could in principle open directly on its full-damage
# swing with no wind-up ever having been seen - a real fairness break,
# not just a cosmetic one. Empty locked list (every enemy without a
# WIND_UP, e.g. the Tideworn) makes this identical to a plain unweighted
# pick, same as
# before this existed.
func _pick_erratic_initial_index(enemy_data: EnemyData) -> int:
	var locked := _erratic_locked_followup_indices(enemy_data)
	var weights: Dictionary = {}
	for i in enemy_data.intents.size():
		if i not in locked:
			weights[i] = enemy_data.intents[i].erratic_weight
	return int(WeightedRandom.pick(weights))

# The Sputter's own turn-one lockout (see DESIGN.md's Bestiary: the
# Sputter, and EnemyIntent.turn_one_locked's own doc) - a fourth
# weighted-pick-with-cap shape, deliberately NOT unified with
# _pick_erratic_initial_index() just above even though the two are
# almost identical: that one excludes _erratic_locked_followup_indices()
# (a WIND_UP's own paired swing) for a pairing-integrity reason with
# nothing to do with turn number; this one excludes whichever specific
# EnemyIntent entries author turn_one_locked = true, for a balance
# reason with nothing to do with WIND_UP pairing. Merging the two would
# braid together two unrelated exclusion reasons for no real gain -
# not attempted this pass (see this feature's own brief: judge
# extracting a shared helper only once there are real consumers to
# weigh it against - four, after this).
# Both exclusions are still applied together here (not turn_one_locked
# alone), so a future enemy that combines WIND_UP with a turn-one lock
# wouldn't quietly lose the pairing guarantee - though no enemy needs
# both today. Only ever called for an enemy's very first intent pick
# (see _spawn_enemies()/_spawn_additional_enemy()) - _pick_erratic_
# intent_index() (every later turn) never reads turn_one_locked at all,
# so a locked intent is a fully normal candidate again from turn two on.
func _pick_erratic_initial_index_turn_one_locked(enemy_data: EnemyData) -> int:
	var locked := _erratic_locked_followup_indices(enemy_data)
	var weights: Dictionary = {}
	for i in enemy_data.intents.size():
		if i in locked:
			continue
		if enemy_data.intents[i].turn_one_locked:
			continue
		weights[i] = enemy_data.intents[i].erratic_weight
	return int(WeightedRandom.pick(weights))

# --- Escalation (DECIDED — see DESIGN.md's Bestiary: the Wardling) ---
#
# An enemy whose EnemyData.escalation_multipliers is empty (every enemy
# except the Wardling, today) is completely unaffected by everything
# below - _escalated_intent_value() just returns intent.value unchanged,
# and _escalation_descriptor() returns "" (which Enemy.show_intent()
# treats as "no flavor line - fall back to the intent's own flavor_text,
# or nothing at all," exactly like before this existed).

# The one place an intent's value actually gets scaled for the current
# turn - called both when DISPLAYING an intent (_update_intent_display())
# and when RESOLVING it (_run_enemy_turn()), so the number the player saw
# coming is always the number that lands.
func _escalated_intent_value(enemy_data: EnemyData, intent: EnemyIntent, turn: int) -> int:
	if enemy_data.escalation_multipliers.is_empty():
		return intent.value
	var stage := _escalation_stage(enemy_data, turn)
	return roundi(intent.value * enemy_data.escalation_multipliers[stage])

# Which entry of escalation_multipliers/escalation_stage_descriptions
# applies on a given turn - turns are 1-indexed (turn_number starts at 1
# - see _start_battle()), stages are 0-indexed arrays, and once the fight
# outlasts every defined stage this just holds on the LAST one rather
# than going out of bounds.
func _escalation_stage(enemy_data: EnemyData, turn: int) -> int:
	var stage_length: int = maxi(enemy_data.escalation_stage_length, 1)
	var stage: int = (turn - 1) / stage_length
	return mini(stage, enemy_data.escalation_multipliers.size() - 1)

# "" if this enemy has no per-stage wording configured (escalation
# without custom text is a legal, if unused today, combination - see
# enemy_data.gd) - Enemy.show_intent() falls back to the intent's own
# flavor_text (or hides the flavor line entirely) when it gets an empty
# string back.
func _escalation_descriptor(enemy_data: EnemyData, turn: int) -> String:
	if enemy_data.escalation_stage_descriptions.is_empty():
		return ""
	var stage := _escalation_stage(enemy_data, turn)
	return enemy_data.escalation_stage_descriptions[mini(stage, enemy_data.escalation_stage_descriptions.size() - 1)]

# --- Encounter-linked damage (Sunken Works: GUN/SUPPLY, 2026-08-29) ---
#
# One enemy's own ATTACK damage, stepped down based on ANOTHER enemy's
# CURRENT hp - see EnemyData.damage_source_enemy/damage_step_thresholds/
# damage_step_values/damage_source_dead_value for the authored side of
# this. Called from both _update_intent_display() and _resolve_enemy_
# intent()'s own value computation - same "one function, two callers can
# never disagree" shape _escalated_intent_value() above already
# established for a different mechanic, and the exact discipline the
# MODIFIER-status fix (see that call site's own note) exists to enforce:
# the number GUN's intent shows is always exactly what lands.
#
# A no-op (returns `value` unchanged) for every enemy without damage_
# source_enemy set - every enemy except GUN today.
func _encounter_linked_damage(enemy_data: EnemyData, value: int) -> int:
	if enemy_data.damage_source_enemy == null:
		return value
	if _is_damage_source_defeated(enemy_data):
		return enemy_data.damage_source_dead_value
	var source := _find_combatant_by_data(enemy_data.damage_source_enemy)
	var fraction: float = float(source.hp) / float(source.max_hp)
	for i in enemy_data.damage_step_thresholds.size():
		if fraction > enemy_data.damage_step_thresholds[i]:
			return enemy_data.damage_step_values[i]
	return enemy_data.damage_step_values[enemy_data.damage_step_values.size() - 1]

# Shared by _encounter_linked_damage() above and _encounter_linked_
# impact_sfx() below, so the two can never disagree about which side of
# "alive vs. defeated" a given attack falls on - same "one function, N
# callers" discipline this whole mechanic already follows. false (not
# just "unaffected") for every enemy without damage_source_enemy set -
# callers that care about the no-op case still check that separately,
# same as _encounter_linked_damage() does above.
func _is_damage_source_defeated(enemy_data: EnemyData) -> bool:
	if enemy_data.damage_source_enemy == null:
		return false
	var source := _find_combatant_by_data(enemy_data.damage_source_enemy)
	return source == null or source.is_defeated

# The audio half of the encounter-link mechanic (2026-08-29) - GUN's own
# landed-hit sound differs depending on whether Supply is still alive,
# same "one enemy, one state, one cue" shape EnemyData.attack_impact_sfx
# already established for the Beachwrack, just conditioned on THIS
# mechanic's own live state instead of being a flat per-enemy override.
# Called from _enemy_attack_player() right alongside that existing
# override, not a second parallel sound-selection path - see that
# function's own call site.
#
# default_sfx passes through unchanged whenever there's nothing more
# specific to say: no damage_source_enemy at all (every enemy except
# GUN), or the relevant *_sfx field was left empty (same "empty means
# fall through" convention attack_impact_sfx's own read site already
# uses) - so an enemy that sets damage_source_enemy but only fills in
# ONE of the two sfx fields still gets a sane sound for the other state,
# rather than silently playing nothing.
func _encounter_linked_impact_sfx(enemy_data: EnemyData, default_sfx: String) -> String:
	if enemy_data.damage_source_enemy == null:
		return default_sfx
	if _is_damage_source_defeated(enemy_data):
		return enemy_data.damage_source_dead_sfx if enemy_data.damage_source_dead_sfx != "" else default_sfx
	return enemy_data.damage_source_alive_sfx if enemy_data.damage_source_alive_sfx != "" else default_sfx

# The encounter-link relationship, surfaced to the player BEFORE they
# commit to a target (this pass's own display requirement) - reuses
# _update_intent_display()'s existing flavor-line slot, same "no new UI"
# shape _charge_progress_descriptor() below already established for a
# different mechanic. Static, not a live countdown - GUN's own intent
# number already shows the CURRENT stepped value every turn (see
# _encounter_linked_damage() above); this only needs to explain WHY that
# number can change, once, not restate it every turn. Reads the source's
# own enemy_name rather than a hardcoded string, so this never needs
# updating if GUN/SUPPLY's working names change later (out of scope for
# this pass either way). "" for every enemy without damage_source_enemy
# set, same "empty means nothing to show" fallback _escalation_
# descriptor() above already uses for its own different reason.
func _encounter_link_descriptor(enemy_data: EnemyData) -> String:
	if enemy_data.damage_source_enemy == null:
		return ""
	if _is_damage_source_defeated(enemy_data):
		return enemy_data.damage_source_dead_flavor
	return "Damage scales with %s's HP" % enemy_data.damage_source_enemy.enemy_name

# Finds the OTHER combatant a linked-damage enemy (GUN) is reading -
# searches Battle's own full `enemies` array, not _living_enemies() - see
# that function's own doc: "a defeated enemy never leaves the `enemies`
# array... it just stops showing up here." GUN needs to keep reading
# SUPPLY's hp (0) and is_defeated (true) after it dies, not lose the
# reference the instant SUPPLY stops being "living."
func _find_combatant_by_data(data: EnemyData) -> EnemyCombatant:
	for combatant in enemies:
		if combatant.data == data:
			return combatant
	return null

# The index of the first entry of `type` in this enemy's own `intents` -
# used by _advance_boss_charge() above to find the Charge-window attack
# by its own dedicated CHARGE_ATTACK type (2026-08-29 rework), rather
# than scanning for "the first ATTACK-type intent" the way this used to:
# Leviathan now authors TWO plain ATTACK intents (the baseline 14/10,
# picked by _pick_baseline_attack_index() instead of this function - see
# its own doc), so "first ATTACK wins" stopped being able to tell "a
# baseline attack" and "the charge-window attack" apart the moment a
# second baseline attack existed. CHARGE_ATTACK exists as its own type
# specifically so this lookup stays unambiguous without needing to scan
# for anything more specific than "which type." Falls back to 0 if `type`
# isn't present at all - not a real case for Leviathan today (it authors
# exactly one CHARGE_ATTACK), but a safe default rather than an out-of-
# bounds index if that ever changes.
func _charge_intent_index(enemy_data: EnemyData, type: EnemyIntent.IntentType) -> int:
	for i in enemy_data.intents.size():
		if enemy_data.intents[i].type == type:
			return i
	return 0

# Whether THIS turn's ATTACK is the Charge buff's own finishing blow
# (2026-08-29, "double-hit finisher" pass) - true only on the LAST turn
# the Charged status is active, landing as two hits instead of one (see
# _resolve_enemy_intent()'s own ATTACK case). Detected off the status's
# own turns_remaining rather than a new per-combatant flag: _tick_
# statuses() (called at the very top of _resolve_enemy_intent(), before
# this turn's ATTACK ever resolves) already decrements it for THIS turn,
# and removal is deferred until AFTER the match runs (see that function's
# own note on why a duration-1 status must survive long enough to be
# read) - so "found, with turns_remaining <= 0" IS "this is the last turn
# it still applies," the same beat _apply_status_modifiers() below is
# already reading it at. A no-op (false) for every enemy without the
# Charge mechanic, and for every turn of the buff except its last.
func _is_charge_buff_finishing_turn(enemy_data: EnemyData, combatant: EnemyCombatant) -> bool:
	if enemy_data.charge_window_turns <= 0:
		return false
	var active := _find_status(combatant.statuses, enemy_data.charge_buff_status)
	return active != null and active.turns_remaining <= 0

# The DISPLAY-time counterpart to _is_charge_buff_finishing_turn() above
# (2026-08-29, "x2" finishing-hit indicator pass) - a separate predicate,
# not a reuse of it, because the two run at different points in the turn
# cycle and read the SAME turns_remaining differently as a result.
# _is_charge_buff_finishing_turn() runs at RESOLUTION time, after _tick_
# statuses() has already decremented the buff for the turn currently
# resolving - "turns_remaining <= 0" there means "THIS turn is the last
# one." This function runs at DISPLAY time instead, called from _update_
# intent_display() right after _advance_boss_charge() has picked the
# UPCOMING turn's intent - by that point the buff has already been
# ticked once for the turn that JUST resolved, so "one MORE tick (next
# turn) would bring it to 0" is spelled "turns_remaining == 1" here, not
# "<= 0". Read _update_intent_display()'s own call site for the concrete
# walk: applied at 3 turns_remaining (untouched, no tick yet) -> ticks to
# 2 after turn A resolves (this function reads 2, false, showing turn B's
# intent) -> ticks to 1 after turn B resolves (reads 1, TRUE, showing
# turn C's intent with " x2") -> ticks to 0 when turn C itself resolves,
# which is exactly when _is_charge_buff_finishing_turn() above fires the
# real second hit. A no-op (false) for every enemy without the Charge
# mechanic, same guard as its resolution-time counterpart.
func _charge_buff_finishes_next_turn(enemy_data: EnemyData, combatant: EnemyCombatant) -> bool:
	if enemy_data.charge_window_turns <= 0:
		return false
	var active := _find_status(combatant.statuses, enemy_data.charge_buff_status)
	return active != null and active.turns_remaining == 1

# The Charge progress readout (2026-08-29, BOSS_01 pass - this feature's
# own "progress must be legible or the mechanic is unfair" requirement).
# Reuses _update_intent_display()'s existing flavor-line slot (see its
# own call site below) rather than any new UI - "" outside the WINDOW
# phase (and for every non-Charge enemy, since charge_phase never leaves
# NORMAL for them), same "empty means nothing to show" fallback shape
# _escalation_descriptor() above already gives that same slot for a
# DIFFERENT enemy's different reason. System-voice by construction, not
# by a separate style choice - FlavorLabel carries no font override of
# its own (see enemy.gd), so this reads in the same plain sans/muted
# register as everything else that already lands there, never Spectral/
# world-voice, without this function needing to know that.
func _charge_progress_descriptor(combatant: EnemyCombatant) -> String:
	if combatant.charge_phase != BossChargePhase.WINDOW:
		return ""
	return "Damage: %d / %d" % [combatant.charge_window_damage, combatant.charge_effective_threshold]

# The one place Enemy.show_intent()/refresh_intent() gets called from -
# both the initial display (right after spawning, see _spawn_enemies(),
# animate=false - no previous intent to fade out FROM) and every advance
# (_advance_enemy_intent(), animate=true - see enemy.gd's Intent refresh
# note for why an advance always fades even when the number repeats)
# funnel through here, so there's exactly one place that knows how to
# turn "which intent slot, which turn" into "what the player should
# actually see." For a non-escalating enemy this computes the exact same
# value/blank descriptor show_intent() always used - no behavior change.
func _update_intent_display(combatant: EnemyCombatant, animate: bool = false) -> void:
	var enemy_data: EnemyData = combatant.instance.enemy_data
	var index := combatant.current_intent_index
	var value := -1
	var flavor := ""
	var value_suffix := ""
	if not enemy_data.intents.is_empty():
		var intent: EnemyIntent = enemy_data.intents[index]
		if intent.type == EnemyIntent.IntentType.CHARGE_ATTACK:
			# EnemyData.charge_attack_value, not intent.value - mirrors
			# _resolve_enemy_intent()'s own CHARGE_ATTACK handling exactly
			# (see EnemyData.charge_attack_value's own doc for why this
			# field, not a second authored value on the intent, is the one
			# source of truth). The two paths must never disagree about
			# what a Charge-window attack shows vs. what it deals - same
			# "the number shown is exactly what lands" reasoning the
			# MODIFIER-status fix just below already established for ATTACK,
			# so this gets the same OUTGOING_DAMAGE modifier pass. No
			# escalation here - Leviathan has no escalation_multipliers.
			value = enemy_data.charge_attack_value
			value = _apply_status_modifiers(value, combatant.statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
		else:
			value = _escalated_intent_value(enemy_data, intent, turn_number)
			# MODIFIER-status fix (2026-08-29, intent-display-modifier pass) -
			# _resolve_enemy_intent() has applied this same adjustment to an
			# ATTACK intent's value for a while (see its own ATTACK case,
			# _apply_status_modifiers() call) - this is what actually LANDS.
			# This display path never mirrored it, which was a real bug hiding
			# in plain sight: harmless only because no status has ever set
			# category == MODIFIER on an enemy in a live fight before now (see
			# that call site's own note), so this was a no-op everywhere it
			# ran. First real consequence otherwise: a queued attack shown at
			# its base value while a MODIFIER buff/debuff made it land at a
			# different one - a genuine violation of Combat Telegraphing's "the
			# number shown is exactly what lands" rule. Gated to ATTACK only,
			# same as the resolution side - OUTGOING_DAMAGE has no meaning for
			# DEFEND/IDLE/WIND_UP/GROWTH, and applying it there would be
			# nonsensical, not just redundant.
			if intent.type == EnemyIntent.IntentType.ATTACK:
				# Encounter-linked damage (GUN/SUPPLY, see _encounter_linked_
				# damage()'s own doc) - BEFORE the modifier-status pass below,
				# mirroring _resolve_enemy_intent()'s own order exactly (this
				# REPLACES the base value being modified, the same way the
				# CHARGE_ATTACK branch above replaces it with charge_attack_
				# value before ITS OWN modifier pass) - a no-op for every
				# enemy without damage_source_enemy set.
				value = _encounter_linked_damage(enemy_data, value)
				value = _apply_status_modifiers(value, combatant.statuses, StatusEffectData.ModifierTarget.OUTGOING_DAMAGE)
				# "x2" (2026-08-29, finishing-hit indicator pass) - shown
				# ahead of time on whichever turn's queued ATTACK will
				# resolve as the Charged buff's own finishing double-hit
				# (see _charge_buff_finishes_next_turn()'s own doc for why
				# this is a SEPARATE predicate from the resolution-time
				# _is_charge_buff_finishing_turn() check, not a reuse of
				# it). "" for every other intent/enemy - same "empty means
				# unaffected" shape every other opt-in field on this
				# display path already uses.
				if _charge_buff_finishes_next_turn(enemy_data, combatant):
					value_suffix = " x2"
		flavor = _escalation_descriptor(enemy_data, turn_number)
		if flavor == "":
			# Charge progress readout (2026-08-29, BOSS_01 pass) - only the
			# SECOND thing tried for this slot, after escalation's own
			# descriptor (see that function's own doc) - the two mechanics
			# don't coexist on any enemy today, but if they ever did,
			# escalation's authored flavor wins rather than being silently
			# overwritten by a number neither mechanic's own brief asked to
			# take priority.
			flavor = _charge_progress_descriptor(combatant)
		if flavor == "":
			# Encounter-link relationship (GUN/SUPPLY, see _encounter_link_
			# descriptor()'s own doc) - THIRD in line for this slot. No
			# enemy today combines this with escalation or Charge, but if
			# one ever did, both of those already win over a plain "why
			# this number moves" explainer.
			flavor = _encounter_link_descriptor(enemy_data)
	if animate:
		await combatant.instance.refresh_intent(index, value, flavor, value_suffix)
	else:
		combatant.instance.show_intent(index, value, flavor, value_suffix)

# Spawn-time counterpart to _update_intent_display() above - a grower
# (see enemy_data.gd's growth_stage_track_length doc) has an EMPTY
# `intents` array, so the normal path would just clear() its display
# forever. Called from both _spawn_enemies() and _spawn_additional_enemy()
# so a debris-spawned grower (none exist today, but nothing here assumes
# otherwise) gets the same correct first countdown a battle-start one
# does, from one shared place rather than two copies of this branch.
func _show_initial_intent_or_growth(combatant: EnemyCombatant) -> void:
	if combatant.data.growth_stage_track_length > 0:
		combatant.growth_stage = combatant.data.growth_start_stage
		var remaining := combatant.data.growth_stage_track_length - combatant.growth_stage
		# The eruption telegraph (2026-08-29 - see Enemy.show_growth_
		# eruption_warning()'s own doc) replaces the plain countdown the
		# one turn it would show "1" - matches _advance_growth_stage()'s
		# own "remaining <= 1" branch below, in case a future grower is
		# ever staggered to start already on its last stage (no authored
		# Mushroom does today).
		if remaining <= 1:
			combatant.instance.show_growth_eruption_warning(combatant.data.growth_eruption_damage)
		else:
			combatant.instance.show_growth_countdown(remaining)
		# Snapped, not tweened (animate=false) - a mushroom staggered to
		# start mid-track (growth_start_stage > 0) has to render at its
		# CORRECT size on the very first frame, never at min_growth_scale
		# first and then visibly jumping/ramping up to where it should
		# already be. See Enemy.set_growth_scale()'s own doc. RESTORED
		# (2026-08-29) alongside the sprite-stage swap below, not instead
		# of it.
		combatant.instance.set_growth_scale(_growth_scale_for_stage(combatant.data, combatant.growth_stage), false)
		# Sprite-stage swap (see Enemy.set_growth_sprite_stage()'s own
		# doc) - a no-op for every grower without growth_stage_textures
		# configured, so this is safe to call unconditionally for every
		# grower, sprite-based or not.
		combatant.instance.set_growth_sprite_stage(combatant.growth_stage)
	else:
		_update_intent_display(combatant)

# The growth-scale ramp's own math (see enemy_data.gd's min_growth_scale/
# max_growth_scale doc) - progress is measured against growth_stage_
# track_length - 1 (the LAST stage actually shown before eruption, per
# _advance_growth_stage()'s own "no separate show-0 beat" note), not
# track_length itself, so max_growth_scale lands exactly on that final
# countdown value rather than one stage short of it. Guards track_length
# <= 1 (a degenerate single-stage grower) by jumping straight to max -
# there's no earlier stage to interpolate from in that case.
func _growth_scale_for_stage(enemy_data: EnemyData, growth_stage: int) -> float:
	var span := enemy_data.growth_stage_track_length - 1
	if span <= 0:
		return enemy_data.max_growth_scale
	var progress := clampf(float(growth_stage) / float(span), 0.0, 1.0)
	return lerpf(enemy_data.min_growth_scale, enemy_data.max_growth_scale, progress)

# The Mushroom's own per-turn advance (see enemy_data.gd's growth_stage_
# track_length doc) - called from _run_enemy_turn(), structurally
# separate from _resolve_enemy_intent() rather than a case inside it
# (DECIDED - see enemy_intent.gd's GROWTH doc). That separation is what
# makes "not stopped by stun, damage, or status effects" true by
# construction: this function reads nothing but battle_over/is_defeated,
# never intent_interrupted_pending (the flag a chain-payoff STUN or the
# Wardling's pain turn actually sets) - there is no interrupt path INTO
# this function for either of those to cancel. is_defeated is checked
# regardless: a mushroom already killed by cards this fight (or earlier
# this same enemy phase, from a card that also happened to threaten
# multiple targets in some future system) never advances or erupts -
# "killed before erupting removes its pending eruption" falls out of this
# one guard, not separate bookkeeping tracking "does this combatant still
# have a pending eruption."
#
# no-ops immediately (growth_stage_track_length <= 0) for every enemy
# except a real grower - safe to call unconditionally from _run_enemy_
# turn() for every combatant without checking the flag at the call site.
func _advance_growth_stage(combatant: EnemyCombatant) -> void:
	if battle_over or combatant.is_defeated:
		return
	var enemy_data: EnemyData = combatant.data
	if enemy_data.growth_stage_track_length <= 0:
		return
	await get_tree().create_timer(ENEMY_TELEGRAPH_PAUSE).timeout
	if battle_over or combatant.is_defeated:
		return
	# Checked BEFORE incrementing, against the countdown value already on
	# screen (last shown as 1 if this is the turn it hits zero) - the
	# player was already told "this is the last one" the same way an
	# ATTACK's own shown number IS what lands this turn, not a preview of
	# the turn after. No separate "show 0" beat before erupting - the
	# eruption IS this turn's resolution, exactly like an ATTACK intent's
	# damage landing IS its own turn's resolution.
	var will_erupt := combatant.growth_stage + 1 >= enemy_data.growth_stage_track_length
	combatant.growth_stage += 1
	if will_erupt:
		await get_tree().create_timer(ENEMY_RESOLVE_PAUSE).timeout
		_erupt_mushroom(combatant, enemy_data)
	else:
		# "mushroom_growth" on every non-erupting advance (2026-08-29) -
		# the eruption turn plays "mushroom_explosion" instead (see _erupt_
		# mushroom()'s own call), never both, so the two cues stay a clean
		# either/or exactly matching "growth on any turn except the
		# explosion."
		AudioManager.play_sfx("mushroom_growth")
		var remaining := enemy_data.growth_stage_track_length - combatant.growth_stage
		# The eruption telegraph (see Enemy.show_growth_eruption_warning()'s
		# own doc) replaces the plain countdown on the LAST turn shown
		# before erupting - mirrors _show_initial_intent_or_growth()'s own
		# identical branch.
		if remaining <= 1:
			combatant.instance.show_growth_eruption_warning(enemy_data.growth_eruption_damage)
		else:
			combatant.instance.show_growth_countdown(remaining)
		# Fire-and-forget (not awaited) - the swell is a visible flourish,
		# not a beat the turn's own pacing needs to wait on (see enemy_
		# data.gd's growth_scale_tween_duration_sec doc). RESTORED
		# (2026-08-29) alongside the sprite-stage swap below, not instead
		# of it.
		combatant.instance.set_growth_scale(_growth_scale_for_stage(enemy_data, combatant.growth_stage), true, enemy_data.growth_scale_tween_duration_sec)
		# Sprite-stage swap (see Enemy.set_growth_sprite_stage()'s own
		# doc). No separate call in the will_erupt branch above: the
		# creature is destroyed by _erupt_mushroom() immediately after,
		# with nothing left to show a sprite on.
		combatant.instance.set_growth_sprite_stage(combatant.growth_stage)
		await get_tree().create_timer(ENEMY_RESOLVE_PAUSE).timeout

# Fires exactly once (this combatant is removed immediately after - see
# _on_enemy_defeated() below), always through the SAME _enemy_attack_
# player() every ATTACK intent already uses (2026-08-26, Mushroom pass) -
# blockable, accrues Toll, opens a Rally pool, with zero special-casing
# in either system, per this feature's own brief. No lunge/attack
# animation here (see enemy.gd's play_attack_lunge()) - a rooted,
# stationary creature doesn't lunge; _enemy_attack_player() already
# provides full player-side feedback (damage number, sound, HP change)
# on its own regardless of what the attacker's own sprite does.
#
# hp is forced to 0 and pushed to the vitals bar before defeat, same
# order _deal_damage_to_enemy() already uses for a card-killed enemy -
# HP and the stage track are independent (per this feature's own brief),
# so nothing about reaching the end of the track ever reduced this
# combatant's own hp before now; this is the one moment it does, as the
# direct consequence of erupting, not a side effect of the growth math
# above.
func _erupt_mushroom(combatant: EnemyCombatant, enemy_data: EnemyData) -> void:
	_enemy_attack_player(enemy_data.growth_eruption_damage, combatant)
	if battle_over or combatant.is_defeated:
		return
	combatant.hp = 0
	combatant.instance.update_hp(0, combatant.max_hp)
	_on_enemy_defeated(combatant)

# Offset from the player's vitals bar (see PlayerBattleVisual.
# get_floating_number_anchor()) to where its floating damage/heal numbers
# start - was a hardcoded Vector2(400, 0) tuned for the OLD bottom-left
# PlayerHPBar; exported now that the bar lives in a new screen location
# from the Battle Layout rework, since where "just to the right of the
# bar" actually looks right depends on where the bar itself ended up.
@export var player_damage_number_offset: Vector2 = Vector2(260.0, -10.0)

# source picks which FloatingNumber.Kind this reads as (TAKE_ENEMY/
# TAKE_SELF/TAKE_STATUS each get their own color - see floating_number.gd)
# - every call site already has this same RunLogger.TollSource in hand
# one or two lines above (it's what they just passed to _set_player_hp()),
# so this is just forwarding it, not deriving anything new.
func _spawn_player_damage_number(amount: int, source: RunLogger.TollSource) -> void:
	var kind: FloatingNumber.Kind
	match source:
		RunLogger.TollSource.ENEMY:
			kind = FloatingNumber.Kind.TAKE_ENEMY
		RunLogger.TollSource.SELF:
			kind = FloatingNumber.Kind.TAKE_SELF
		RunLogger.TollSource.STATUS:
			kind = FloatingNumber.Kind.TAKE_STATUS
	FloatingNumber.spawn($UI, player_battle_visual.get_floating_number_anchor() + player_damage_number_offset, amount, kind)

func _spawn_player_heal_number(amount: int, chain_payoff: bool = false) -> void:
	var kind := FloatingNumber.Kind.CHAIN_REFUND if chain_payoff else FloatingNumber.Kind.HEAL
	FloatingNumber.spawn($UI, player_battle_visual.get_floating_number_anchor() + player_damage_number_offset, amount, kind)

# Start of a new player turn: block expires (Slay the Spire rule - it
# survives the enemy's turn but not into yours), energy refills, and a
# fresh hand is drawn. The hand is always empty by the time this runs
# (End Turn discards it first), so every card drawn here starts fully
# affordable-checked against the refilled energy automatically - see
# _add_card_to_hand_display().
func _start_player_turn() -> void:
	RunLogger.end_turn(RunState.player_hp, energy)
	# Captured BEFORE resetting for the new turn - see _took_damage_last_
	# turn's own doc for why this needs to be a snapshot, not a live read.
	# This is the boundary: "last turn" becomes everything that happened
	# since the PREVIOUS call to this function (the rest of that turn,
	# plus the whole enemy phase that followed it) - a card read anywhere
	# during the turn that's about to start sees a fixed answer for the
	# whole of it.
	_took_damage_last_turn = _took_damage_this_turn
	_took_damage_this_turn = false
	player_block = 0
	energy = max_energy
	turn_number += 1
	cards_played_this_turn = 0
	# Opened here, BEFORE the status tick below, not after the battle_over
	# guard that follows it - a tick that kills the player still belongs
	# to THIS turn's log entry (see _on_player_defeated()'s own end_turn()
	# call), and _turn_hp_before needs to be the HP right as this turn
	# starts, before anything about it (including its own tick) resolves.
	RunLogger.begin_turn(turn_number, RunState.player_hp)
	# Statuses tick at the START of their holder's own turn - see the
	# Status effects section note above _tick_statuses(). A TICK status
	# could in principle defeat the player here (no real status does this
	# today - see that same section) - if it does, _on_player_defeated()
	# has already ended the battle by the time execution reaches here, so
	# bail out rather than refilling energy/drawing a hand for a fight
	# that's already over.
	_tick_statuses(player_statuses, _deal_status_tick_damage_to_player)
	_remove_expired_statuses(player_statuses)
	player_battle_visual.update_statuses(player_statuses)
	if battle_over:
		return
	_update_player_panel()
	_update_energy_label()
	_update_turn_label()
	_draw_cards(5)
	_update_pile_labels()

# HandContainer's width is fixed by its anchors in battle.tscn (it always
# spans the window width, minus a margin — see battle.tscn), but the fan
# itself is only ever as wide as it needs to be: HandContainer's own
# alignment is CENTER, so this function shrinks the gap ("separation")
# between cards as the hand grows, keeping the fan's actual rendered
# span within available_width (the SMALLER of the window's own width and
# hand_max_span_px - see that export's own doc) while HandContainer's
# box underneath stays exactly as wide as its anchors say. If cards
# still wouldn't fit at zero gap, the separation goes negative, which
# makes them overlap like a fanned hand of playing cards.
func _update_hand_spacing() -> void:
	var count := hand.size()
	if count <= 1:
		hand_container.add_theme_constant_override("separation", DEFAULT_HAND_SEPARATION)
		return
	# Deliberately NOT hand_container.size.x here - that's the container's
	# own reported size, which Godot clamps to be at least as big as its
	# computed minimum size (children's widths + separation). Reading it
	# to decide separation is circular: a separation that isn't tight
	# enough inflates the reported size, which then gets read back as
	# "more room than there really is," so the fix never fully catches up
	# to the true available space - and since HandContainer's
	# grow_horizontal is BOTH, Godot resolves that mismatch by growing it
	# symmetrically past both edges instead of clipping one side. Reading
	# the viewport's width directly (stable, independent of anything
	# HandContainer itself is doing) breaks that loop.
	var viewport_width := get_viewport().get_visible_rect().size.x
	var viewport_available_width := viewport_width - hand_container.offset_left + hand_container.offset_right
	# hand_max_span_px caps the fan independent of window width - see its
	# own doc for why (EnemyZone clearance). min(), not a straight
	# replacement, so a narrow window still shrinks the hand further than
	# this cap if it has to, same as before this export existed.
	var available_width := minf(viewport_available_width, hand_max_span_px)
	var total_card_width := count * CARD_WIDTH
	var gaps := count - 1
	var width_at_default_spacing := total_card_width + gaps * DEFAULT_HAND_SEPARATION
	if width_at_default_spacing <= available_width:
		hand_container.add_theme_constant_override("separation", DEFAULT_HAND_SEPARATION)
	else:
		var tight_separation := (available_width - total_card_width) / float(gaps)
		# floori() rounds down (toward negative infinity), not toward zero,
		# so this is never a fraction of a pixel too wide — important since
		# tight_separation can be negative (overlapping cards).
		hand_container.add_theme_constant_override("separation", floori(tight_separation))

# Assigns each hand card its own resting tilt AND vertical arc offset
# (see fan_max_tilt_deg/arc_rise_px's own docs) - leftmost -max angle,
# rightmost +max angle, linear in between; vertically, the CENTER rises
# by up to arc_rise_px and the EDGES drop by up to arc_drop_px, blended
# by the same dome_weight curve so the two meet smoothly with no seam at
# the point where "mostly rise" gives way to "mostly drop." Recomputed
# from scratch every time (not just for newly-added cards) because EVERY
# card's fractional position across the hand shifts whenever the hand's
# total size changes, not just the new arrival's. Called from the same
# two sites as _update_hand_spacing() (hand size just changed there too),
# never on its own - there's nothing for this to react to that spacing
# doesn't already react to.
func _update_hand_fan() -> void:
	var cards: Array = hand_container.get_children()
	var count := cards.size()
	if count == 0:
		return
	# Shrinks the effective max angle once the hand grows past the size
	# this was tuned for (fan_reference_hand_size) - min(1.0, ...) so a
	# hand at or below reference size isn't shrunk by THIS factor (the
	# ramp-up factor below is what actually governs small hands now).
	# count is never 0 here (guarded above).
	var large_hand_shrink: float = minf(1.0, float(fan_reference_hand_size) / float(count))
	# 0 at 1 card, smoothly rising to 1 at fan_full_amplitude_hand_size,
	# held at 1 beyond it (smoothstep clamps outside its own edge0/edge1
	# range, so count > fan_full_amplitude_hand_size just reads as 1.0
	# with no extra clamping needed here). Applied to BOTH the rotation
	# angle and the arc's vertical offset below - a 2-card hand isn't "a
	# smaller fan," it's barely a fan at all, since there's no curve for
	# a dome or a tilt to describe yet with only one or two points.
	var small_hand_ramp: float = smoothstep(1.0, float(fan_full_amplitude_hand_size), float(count))
	var effective_max_deg: float = fan_max_tilt_deg * large_hand_shrink * small_hand_ramp
	for i in count:
		var card: Card = cards[i]
		# count == 1: t lands at 0.5 (the lerp below then gives exactly
		# 0deg, and dome_weight below gives exactly 1.0 - a lone card
		# rotates upright and sits fully "center-raised," moot anyway
		# since small_hand_ramp is 0 at count 1) rather than dividing by
		# zero.
		var t: float = 0.5 if count == 1 else float(i) / float(count - 1)
		var angle_deg: float = lerpf(-effective_max_deg, effective_max_deg, t)
		# 1.0 at dead center (t=0.5), 0.0 at both edges (t=0 or 1) - a
		# smooth dome, not a triangle, so the rise-to-drop handoff has no
		# kink in it. cos() naturally gives 1.0 at input 0 and 0.0 at
		# input +-PI/2, which (t-0.5)*PI maps exactly onto for t in [0,1].
		var dome_weight: float = cos((t - 0.5) * PI)
		# Center (dome_weight=1): -arc_rise_px, no drop. Edges (dome_
		# weight=0): +arc_drop_px, no rise. Negative = up on screen
		# (Godot's Y grows downward), matching visual.position's own
		# convention - see card.gd's set_fan_transform(). small_hand_ramp
		# scales the WHOLE offset, same as it scales rotation above - at
		# a 2-card hand this is a few percent of arc_rise_px/arc_drop_px,
		# not their full value.
		var vertical_offset: float = small_hand_ramp * (-arc_rise_px * dome_weight + arc_drop_px * (1.0 - dome_weight))
		card.set_fan_transform(deg_to_rad(angle_deg), vertical_offset)

func _update_pile_labels() -> void:
	discard_label.text = "Discard: %d" % discard_pile.size()

func _update_turn_label() -> void:
	turn_label.text = "Turn: %d" % turn_number

func _update_room_label() -> void:
	room_label.text = "Room: %d" % RunState.room_number

func _update_battle_label() -> void:
	battle_label.text = "Battle: %d" % RunState.battle_number

func _update_gold_label() -> void:
	gold_label.text = "Gold: %d" % RunState.gold

# Set once per battle (same call site as the other three - see
# _start_battle()) rather than needing its own change-triggered update
# path like the others - the class doesn't change mid-run, let alone
# mid-fight (see run_state.gd's current_class).
func _update_class_label() -> void:
	class_label.text = "Class: %s" % RunState.current_class.character_name

# RunState.deck can change mid-battle - a CONSUMED card (see
# card_data.gd's RemovalScope) removes itself the instant it's played
# (see _play_card()) - so this isn't only called once at _start_battle();
# it's re-called anywhere that removal happens too. A SPENT card never
# triggers this - it never touches RunState.deck at all (see spent_
# pile's own doc), so the run-deck count has nothing to update for.
func _update_deck_button() -> void:
	deck_button.text = "Deck (%d)" % RunState.deck.size()

func _update_energy_label() -> void:
	player_resource_cluster.update_energy(energy, max_energy)

# Re-checks every card currently in hand against the current energy AND
# Toll and updates its dim state. Needed after anything that changes
# either (a card gets played, or Toll accrues/is spent - see _set_
# player_hp()'s own call into this) since a card that was playable a
# moment ago might not be anymore, or vice versa.
#
# ALSO refreshes condition-active state now (2026-08-27, condition-
# indicator pass) - deliberately folded into this SAME loop/function
# rather than a second one, since both facts depend on exactly the same
# trigger (something about Toll or energy just changed) and this
# function already runs at every one of those moments; a second pass
# over hand_container would just be the same iteration done twice for no
# benefit. NOT a full trigger-coverage story on its own, though - a card
# freshly entering hand never passes through here (this only walks what
# ALREADY has a Card instance) - see _add_card_to_hand_display()'s own
# matching set_condition_active() call for how a just-drawn card gets
# its correct starting state instead of a stale/default one.
func _update_hand_affordability() -> void:
	for child in hand_container.get_children():
		if child is Card:
			child.set_affordable(_is_card_playable(child.card_data))
			child.set_condition_active(_card_condition_active(child.card_data))

# --- Weapon modifiers (see weapon_modifier.gd) ---
#
# The energy a card actually costs to play, after an equipped weapon's
# CATEGORY_ENERGY_COST modifier (if any) - never below 0. Every read of
# CardData.energy_cost in this file (both affordability checks and the
# actual spend) routes through here instead of the raw field, so a cost
# modifier can never make a card LOOK unaffordable while it's actually
# playable, or vice versa.
func _effective_energy_cost(data: CardData) -> int:
	# TOLL_THRESHOLD_FREE_CARD (see trinket_modifier.gd) - independent of
	# the weapon check below; the two conditions never overlap (this one
	# is a fight-scoped one-shot flag, the weapon's is a per-card scope
	# filter), so which is checked first doesn't matter. Consumed in
	# _play_card(), right after this function is read for the actual
	# deduction - not here, since this function is also called from
	# _is_card_playable() to check every OTHER card in hand too, which
	# must not consume the flag just by looking.
	if _trinket_free_card_armed:
		return 0
	# marked_cost_modifier (2026-08-29, Leviathan mark attack pass) - added
	# on top of every return path below, AFTER the weapon discount (a flat
	# surcharge on top of whatever this card would otherwise cost, not
	# something a weapon's own CATEGORY_ENERGY_COST discount can absorb at
	# the same pipeline stage). 0 for every card that was never marked, so
	# every one of these return values is byte-identical to before this
	# field existed for the overwhelming majority of cards - see that
	# field's own doc on card_data.gd.
	var weapon: WeaponData = RunState.equipped_weapon
	if weapon == null or weapon.modifier == null:
		return data.energy_cost + data.marked_cost_modifier
	if weapon.modifier.kind != WeaponModifier.Kind.CATEGORY_ENERGY_COST:
		return data.energy_cost + data.marked_cost_modifier
	if not _card_matches_scope(data, weapon.modifier.target_scope):
		return data.energy_cost + data.marked_cost_modifier
	return max(data.energy_cost - weapon.modifier.value, 0) + data.marked_cost_modifier

# Applies an equipped weapon's CATEGORY_* modifier to a base numeric
# value, if one is equipped, its modifier is of the matching `kind`, and
# `source_card` (the card whose effect this is) falls within the
# modifier's target_scope. `source_card` null means "no card behind
# this value" (a status tick, the dev damage button) - those never
# match, which is correct: a weapon modifies CARDS, not arbitrary
# damage.
func _weapon_modified_value(base_value: int, source_card: CardData, kind: WeaponModifier.Kind) -> int:
	var weapon: WeaponData = RunState.equipped_weapon
	if weapon == null or weapon.modifier == null or source_card == null:
		return base_value
	if weapon.modifier.kind != kind:
		return base_value
	if not _card_matches_scope(source_card, weapon.modifier.target_scope):
		return base_value
	return base_value + weapon.modifier.value

# Whether `data` falls within a CATEGORY_* modifier's target_scope - see
# weapon_modifier.gd's own note on why this is a small purpose-built
# enum rather than reusing CardData.CardType/ChainRole directly.
func _card_matches_scope(data: CardData, scope: WeaponModifier.TargetScope) -> bool:
	match scope:
		WeaponModifier.TargetScope.ALL_ATTACKS:
			# Deliberately still == ATTACK only, not "!= SKILL" or anything
			# STANCE-inclusive (2026-08-28, card-type-plumbing pass) - a
			# Stance should NOT count as an attack for weapon-modifier
			# scope purposes, unlike the skill-shaped play-feel treatment
			# _play_card() gives it. Not an oversight; left unchanged on
			# purpose.
			return data.card_type == CardData.CardType.ATTACK
		WeaponModifier.TargetScope.OPENERS:
			return data.chain_role == CardData.ChainRole.OPENER
		WeaponModifier.TargetScope.CLOSERS:
			return data.chain_role == CardData.ChainRole.CLOSER
		_:
			return false

# Moves every card currently in hand to the discard pile, both as data
# and on-screen. Used at the start of End Turn - the player's leftover
# hand doesn't carry into the enemy's turn or the next player turn.
func _discard_entire_hand() -> void:
	if chain_empowered:
		RunLogger.log_chain_expired()
	chain_empowered = false
	# The turn is ending - an unused empowerment (see card_data.gd's own
	# chaining note) expires here rather than carrying into a future
	# turn. No _refresh_chain_indicators() call needed: every card in
	# hand, empowered-CLOSER or not, is about to be discarded below.
	for child in hand_container.get_children():
		if child is Card:
			discard_pile.append(child.card_data)
			# remove_child() first so HandContainer's layout updates
			# immediately, instead of briefly counting a card that's
			# about to disappear (queue_free() only deletes it at the
			# end of the frame, not instantly).
			hand_container.remove_child(child)
			child.queue_free()
	hand.clear()
	# Every hand card is about to be gone - whatever was hovered (if
	# anything) can't still be, and mouse_exited won't reliably fire on a
	# node that's about to be freed (same reasoning as _play_card()'s own
	# clear). Every card here is leaving hand for good, so this clears
	# overrides outright rather than merely restoring - see clear_
	# description_overrides()'s own "explicit, not a refresh side effect"
	# contract in card.gd. Without this, a card could be left showing its
	# modified text right up until it's freed, or the reference could
	# dangle into the enemy's own turn.
	if _hovered_card_instance != null:
		_hovered_card_instance.clear_description_overrides()
		_hovered_card_instance = null
		_hovered_card_data = null
