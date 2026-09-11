extends Control
class_name Enemy
# Same shape as Card (see card.gd): a scene that displays whatever
# EnemyData it's given, with a public entry point (set_enemy_data) that
# Battle calls after instancing it. SilhouetteHoverArea handles clicks
# (see "Targeting" below) - still the one exception to "every node here
# is mouse_filter = IGNORE." It used to also react to hover, to re-show
# the name label on demand - removed (2026-08-26, see the "Name
# introduction" section's own note) along with that whole mechanism.
#
# Battle stays the source of truth for the enemy's actual HP number
# (mirrors how it owns energy, hand, etc. — see battle.gd). This script
# never decides how much HP the enemy has; it only displays whatever
# numbers Battle tells it to, and plays a damage animation on request.

@onready var vitals_bar: VitalsBar = $VitalsBar
@onready var intent_display: IntentDisplay = $IntentDisplay
@onready var visual_container: CanvasGroup = $VisualRoot
# A CanvasGroup, not a plain Node2D (2026-08-26, rim highlight pass) -
# see enemy_rim_highlight.gdshader's own header for why: only a
# CanvasGroup pre-composites every child piece into one unified alpha
# buffer before a shader on IT runs, which is what lets the rim outline
# below trace the creature's actual silhouette as a whole instead of
# outlining each hand-drawn piece separately. Every existing consumer
# (position/scale/rotation/modulate tweens - lunge, flinch, the
# targetable pulse, recession, _play_flash()) is untouched by this:
# CanvasGroup extends Node2D, so all of it still works exactly as before.
@onready var name_label: Label = $NameLabel
@onready var hover_area: Control = $SilhouetteHoverArea
@onready var flavor_label: Label = $FlavorLabel
@onready var defeat_flavor_label: Label = $DefeatFlavorLabel
@onready var damage_preview_label: Label = $DamagePreviewLabel
@onready var grounding: Grounding = $Grounding

var enemy_data: EnemyData

const FLASH_COLOR := Color(1, 0.3, 0.3, 1)
const FLASH_LEG_DURATION := 0.08

# --- Chain impact feedback (MINIMUM VIABLE PROTOTYPE - see card_data.
# gd's own chaining note and battle.gd's _deal_damage_to_enemy()) ---
#
# flash_damage()'s empowered case reuses the SAME flash/number this
# function already plays for every hit - the red flash still fires
# first (this is still "you got hit"), then this burst layers ON TOP,
# rather than replacing it with an unrelated effect. Amber, not red -
# the same color CardTextStyles' "modified" style already uses for a
# boosted number (see card_text_styles.gd) - so the empowered hit reads
# as the SAME "this is boosted" signal the card in hand already taught
# the player to recognize, not a second color vocabulary to learn.
@export_group("Chain Impact")
@export var chain_burst_color: Color = Color(0.95, 0.65, 0.25, 1)
@export var chain_burst_radius_px: float = 70.0
@export var chain_burst_duration_sec: float = 0.35
# The beat-before-the-payoff delay used to live here (an await inside
# flash_damage()) but moved to battle.gd's own chain_payoff_delay_sec -
# see _trigger_chain_payoff()'s note there. The closer's own hit and the
# chain's own hit are now two entirely separate _deal_damage_to_enemy()
# calls, spaced apart at the point they're TRIGGERED, not by delaying
# the second one's reveal after it's already landed - simpler, and it's
# what actually let the two read as a sequence rather than one hit with
# a late flourish.

# --- Chain payoff flourish (DECIDED - see DESIGN.md's Guillotine note)
# ---
#
# The moment a chain payoff's STUN actually lands - distinct from every
# OTHER reaction already near this one: chain_burst_color above is gold
# and only ever plays for a DAMAGE payoff (never Guillotine's own STUN
# payoff - flash_damage() is never even called for it); FLASH_COLOR's
# red tint means "you got hit," reused by every ordinary attack, not
# this; show_intent_interrupt()'s own shake lives on the intent row, not
# the body, and reads as "queued attack cancelled," not "impact
# landing"; play_interrupt_flinch() IS on the body, but fires much later
# (see its own note - the enemy's own turn-resolution beat, not the
# instant the payoff resolves mid-player-turn). Ice-blue, cold rather
# than warm, on purpose - "seized," the stoppage.tres flavor's own word,
# not "hit" or "chained." Called by battle.gd's own _resolve_card_effect
# STUN case ONLY when chain_payoff is true, so this fires for ANY card's
# chain payoff that stuns, automatically, without Guillotine's own
# CardData knowing this exists - never for the Wardling's own pain turn
# (that path never sets chain_payoff, see _check_pain_turn_trigger()).
@export var chain_payoff_flourish_color: Color = Color(1.3, 1.7, 2.0, 1)
# OVERBRIGHT (>1.0 channels), not just a pale tint - same technique
# TARGETABLE_TINT above already uses for its own highlight. Raised
# 2026-08-25 (seen live, reported as invisible) from a same-brightness
# (0.75, 0.9, 1.0) tint: against a pale enemy (~0.75/0.85/0.9 body color)
# that color sat at nearly the SAME luminance as the body it was tinting,
# so the "flash" barely changed anything visible - unlike FLASH_COLOR's
# saturated red above, which reads clearly against any enemy precisely
# BECAUSE red departs hard from every creature's own hue. Going overbright
# instead of just more saturated guarantees contrast against ANY enemy
# color, pale or not, without needing to reason about each one's hue.
@export var chain_payoff_flourish_flash_leg_sec: float = 0.22
# Raised from 0.08 -> 0.16 (2026-08-25 visibility fix), then -> 0.22
# (2026-08-25, same day, seen live again and asked to read slower still).
# FLASH_COLOR's own 0.08s legs read fine because red's hue contrast alone
# sells the hit instantly; this flourish leaned on color contrast that
# wasn't actually there, so it needed a slower reveal to be seen at all,
# not just a stronger color.
@export var chain_payoff_flourish_hold_sec: float = 0.2
# Raised from 0.12 alongside the flash legs above, same request - a
# genuine pause AT full chain_payoff_flourish_color, between the flash-in
# and flash-out legs, so this reads as a held "seized" moment rather than
# a blink. Neither FLASH_COLOR's hit-flash nor TARGETABLE_TINT's pulse
# hold like this - both are meant to feel instant or looping, where this
# one specifically wants to be SEEN and register as "the payoff landed,"
# per DESIGN.md's Guillotine note.
@export var chain_payoff_flourish_shake_distance_px: float = 8.0
@export var chain_payoff_flourish_shake_leg_sec: float = 0.045
# Flash (in / hold / out) runs alongside a shake on visual_container's
# position, built to last exactly as long as the flash sequence above
# (see play_chain_payoff_flourish()'s own leg-count math) rather than a
# fixed handful of legs - previously a short, separate 3-leg burst that
# finished well before the (now much longer) flash did; the request was
# for the shake to keep going FOR AS LONG AS the flash is visible, so its
# total duration now follows the flash's own timing automatically instead
# of needing to be kept in sync by hand whenever the flash is retuned.
# Same "two tweens racing side by side" shape _play_flash() and play_
# attack_lunge() already use separately, just run together here. Each
# individual leg stays this short/sharp on purpose even though there are
# now more of them - a jittery back-and-forth reads as "seized/shaking,"
# where a few long, slow legs at the same total duration would just read
# as a lazy sway instead.

var _flourish_tween: Tween
var _flourish_shake_tween: Tween

# --- Targeting (DECIDED — see battle.gd's targeting state machine) ---
#
# A click anywhere on the silhouette (SilhouetteHoverArea, the same
# Control hover already uses) announces itself here and lets Battle
# decide what it means - resolving an armed card against this enemy, or
# nothing at all if no card is armed. This script never knows whether
# it's a legal target right now; that's Battle's call, same "displays
# what it's told, decides nothing itself" split every other Enemy method
# already follows.
signal enemy_clicked

# Right mouse button pressed anywhere on this enemy's silhouette. Battle
# treats this as "cancel targeting if any is active" (see battle.gd's
# own connect next to enemy_clicked above), same reasoning as card.gd's
# own right_clicked: hover_area's default STOP mouse filter would
# otherwise swallow the click at the GUI layer before battle.gd's
# _unhandled_input() background-cancel fallback ever saw it. Kept as a
# SEPARATE signal from enemy_clicked rather than folded in with a button-
# index parameter - a left click and a right click mean opposite things
# (commit vs. cancel) to whoever's listening, and Battle already has one
# handler per meaning for cards; enemies now match that shape.
signal right_clicked

const HOVER_AREA_VERTICAL_PADDING_PX := 24.0
# Extends hover_area above the head and below the feet by this much (see
# _apply_creature_layout() below) - the click/hover region should feel
# like it wants to connect, not need pixel-precise aim (this feature's
# own brief). Vertical only: hover_area's WIDTH already spans the full
# cluster_width_px, not just the silhouette's own narrower bounds, so it
# was already generous horizontally; the tight dimension was strictly
# vertical (head-to-feet, zero padding, until now).
#
# hover_area/HOVER_AREA_VERTICAL_PADDING_PX above decide what counts as
# a legal CLICK (unchanged by the snap tuning below - see SCOPE: click
# regions for committing a play stay exactly as generous as they already
# are). get_snap_region_global() below is a SEPARATE, much tighter test
# battle.gd uses purely to decide where the target LINE visually snaps -
# the two were the same rect before this pass (battle.gd's own _enemy_
# under_mouse() used to read hover_area directly), which is why a wide
# hover_area made the line snap almost the instant a card was armed near
# any enemy, with the unsnapped state barely visible (this feature's own
# brief).
@export_group("Target Line Snap")
@export var snap_margin_px: float = 16.0
# How far outside this enemy's ACTUAL rendered silhouette bounds
# (_silhouette_bounds, scaled - not hover_area's own much bigger click
# rect) the cursor still counts as "on this enemy" for the target line's
# snap (see get_snap_region_global() below). A "modest margin" (this
# feature's own brief) - deliberately much tighter than hover_area.
@export var snap_release_hysteresis_px: float = 24.0
# Extra distance beyond snap_margin_px the cursor must cross back out
# past before battle.gd's own _update_snap_target() releases this enemy
# as the snapped target, once it IS snapped - see get_snap_region_
# global()'s own include_release_hysteresis param. Prevents flicker
# right at the boundary without widening the initial grab (entering
# still only needs snap_margin_px; only LEAVING needs this on top).

@export_group("Targetable Response")
@export var targetable_scale_multiplier: float = 1.05
# How far visual_container scales up while this enemy is a legal target
# (see set_targetable() below). Was 1.12 - reduced substantially
# (2026-08-26 revision) per this feature's own brief: the old value,
# combined with the old continuous oscillation below, read as an
# aggressive, distracting bob rather than a quiet acknowledgment.
@export var targetable_scale_duration_sec: float = 0.15
# How long the one-shot scale-up (see _start_targetable_pulse() below)
# takes to settle into its held pose. Was TARGETABLE_PULSE_LEG_SEC (0.4),
# one leg of an infinite back-and-forth tween - now the ENTIRE animation,
# not half of one repeating cycle, so it's shortened to read as a snap
# into place rather than a slow drift.
# Warm/bright, not a color that could be mistaken for the red damage
# flash (_play_flash()) or the gold defeat-flavor text - "you can act on
# this," an invitation, not a warning.
const TARGETABLE_TINT := Color(1.3, 1.25, 1.0, 1)

var _targetable_tween: Tween

@export_group("Target Rim Highlight")
@export var rim_color: Color = Color(0.88, 0.84, 0.74, 0.55)
# Replaces the target line's own endpoint reticle (removed - see target_
# line.gd) as the "this is your target" signal on snap - see battle.gd's
# _update_snap_target() and set_snap_highlight() below. Left a plain,
# tunable Color rather than baked into the shader's own default so a
# LATER pass can drive it dynamically per-state (e.g. lethality) just by
# calling set_snap_highlight()'s own material update path again with a
# different color - explicitly not built now (out of scope for this
# pass), but nothing here would need to change shape to add it.
#
# Softened (2026-08-26, "hard white sticker" fix) from (0.96, 0.93,
# 0.86, 1.0) - alpha down to 0.55 is the actual "reduced alpha" the fix
# asked for (see enemy_rim_highlight.gdshader's own doc on this exact
# value - it's the ceiling on how opaque the rim can ever read, even at
# full intensity dead-center of the rim); RGB nudged warmer/softer too,
# since the original was reading closer to plain white in practice than
# its own numbers suggested.
@export var rim_thickness_px: float = 1.5
# Cut from 4.0 - "closer to a hairline than the current band," per this
# pass's own brief.
@export var rim_intensity: float = 1.0
# The "on" value set_snap_highlight(true) applies - see its own doc for
# why this isn't the shader's live value directly (0.0 means off, this
# export is only ever read at the moment highlighting turns on).
# Unchanged at 1.0 - the "quieter" ask is carried entirely by rim_color's
# own reduced alpha, rim_thickness_px's own cut, and rim_falloff/rim_
# directional_amount below now doing real softening work the shader
# didn't have before; stacking a SECOND blanket dimmer here on top of
# all of that risked needing to re-brighten one to compensate for the
# other during tuning, for no benefit over having just the one lever.
@export var rim_falloff: float = 1.6
# See enemy_rim_highlight.gdshader's own doc on pow(outline_alpha, rim_
# falloff) - the dedicated "how gradual is the feathered edge" dial this
# pass's own brief asked to keep tunable on its own, separate from
# thickness (which controls WHERE the falloff zone sits, not how soft
# its own transition is).
@export var rim_directional_amount: float = 0.6
@export var rim_light_direction: Vector2 = Vector2(0.35, 1.0)
# See enemy_rim_highlight.gdshader's own doc on both - directional
# variation was cheap enough to actually build (one extra dot product
# per existing ring sample, no new texture reads) rather than skipped
# per this pass's own escape hatch, but rim_directional_amount can still
# be dialed back to 0.0 for the flat, uniform-all-around fallback that
# escape hatch describes, with no shader edit needed, if a directional
# rim ever reads as too uneven once seen against a real fight.

const RIM_SHADER := preload("res://enemy_rim_highlight.gdshader")

const SNAP_HIGHLIGHT_Z_INDEX := 4000
# Applied to rim_highlight_overlay ONLY (see its own doc below), NEVER to
# visual_container - and only while THIS specific enemy is the current
# snap target (set_snap_highlight() below). CHANGED (2026-08-26, second
# pass) from elevating visual_container directly - that first version
# put the actual creature sprite above an armed card too, not just its
# rim glow, since enemy_rim_highlight.gdshader's normal mode re-draws the
# creature's own base pixels unchanged underneath the highlight (see that
# shader's own fragment() - there was no way to elevate "just the glow"
# through visual_container's single material without ALSO elevating
# everything else it draws). The reported regression ("armed card still
# gets overlapped by enemies when the reticle is hovering over them") was
# exactly this: card.gd's own set_armed() z-order fix only holds for a
# NON-highlighted enemy under that first version. Comfortably above
# whatever card.gd's _NEXT_ELEVATED_Z_INDEX counter realistically reaches
# in one play session (that counter is a static, ever-incrementing
# hover/arm count, never reset - see its own doc) while staying well
# under Godot's hard z_index clamp (+/-4096), so there's real headroom on
# both sides. Not dynamically read from the card's own counter - keeping
# the two systems independent is simpler and safer than coordinating a
# shared live value between unrelated scripts for a purely cosmetic
# ordering guarantee.

# --- Recession (Outbound only - see DESIGN.md's Bestiary: Outbound) ---
#
# The primary signal for Outbound's escape mechanic (see battle.gd's
# _escape_distance/_tick_escape_distance()): as distance climbs, this
# creature visibly travels rightward, offscreen-ward, along the ground
# plane - not a bar or a floating number, and (2026-08-27 rework) not a
# shrink/fade either. This is a left-right side-scroller; "away" already
# means offscreen-right, so recession doesn't need a second, Z-axis-style
# vocabulary (drift + shrink + fade toward a vanishing point) on top of
# that - the silhouette, HP bar, and intent used to end up reading as
# three different distances at once. Pure horizontal travel keeps them
# reading as one thing at one distance. The silhouette stays full size
# and full opacity the entire time - only position moves.
#
# _rest_position/_recession_offset exist because THREE other animations
# already target visual_container's position directly and return it to a
# hardcoded rest value when they finish (play_attack_lunge()'s rest_x,
# play_chain_payoff_flourish()'s rest_x, play_interrupt_flinch()'s
# Vector2.ONE scale) - without this, recession would be silently erased
# the next time any of them played, since none of them previously had
# any notion of "rest" being anything but the creature's ORIGINAL spawn
# position. Every enemy but Outbound leaves these at their defaults
# forever, making those functions' behavior identical to before this
# existed. Kept as Vector2 (not a plain float) even though only .x ever
# moves now - _rest_position + _recession_offset stays a one-line Vector2
# add at every call site rather than needing a Vector2(..., 0) wrap.
var _rest_position: Vector2 = Vector2.ZERO
var _recession_offset: Vector2 = Vector2.ZERO

# IntentDisplay's own baked spawn position (2026-08-24, see intent_
# follows_recession above) - a SEPARATE cache from _rest_position: it's
# a different node, positioned independently (a sibling of visual_
# container, not parented under it), so it needs its own "where did
# this start" anchor to drift from. No corresponding lunge/flinch/pulse
# risk here the way visual_container has - nothing else in this file
# ever touches IntentDisplay's own position outside of _apply_creature_
# layout() (the one-time layout pass) and this.
var _intent_rest_position: Vector2 = Vector2.ZERO

@export_group("Recession (Outbound only)")
@export var recession_travel_px: float = 320.0
# How far right, at full distance (fraction 1.0), visual_container
# travels from its rest position (2026-08-27, replacing the old
# drift+shrink+fade rework - see this section's own header). +X is
# always away from the player regardless of slot (see play_attack_
# lunge()'s own note on why -X is always "toward the player"). Chosen so
# Outbound lands clearly far but still fully on-screen at max distance,
# not exiting the frame before the escape itself actually ends the fight
# (see battle.gd's _tick_escape_distance()) - an offscreen enemy would be
# untargetable with its own vitals orphaned, bad in what's meant to read
# as a race.
@export var recession_tween_sec: float = 0.6
# Slower than every other animation on this node (lunge/flinch/pulse are
# all well under 0.5s combined) - this is travel, not a reaction, and
# should read as continuous motion, not a snap, matching one tick's
# worth of distance.

@export var intent_follows_recession: bool = true
# Whether IntentDisplay travels along with the receding silhouette
# (2026-08-24) - a SEPARATE tween from visual_container's own (see
# set_recession()'s own note): IntentDisplay is a sibling, positioned
# via a one-time baked absolute value at spawn (_apply_creature_
# layout()), not parented under visual_container or otherwise live-
# linked to it. Kept tight to the silhouette (same _recession_offset,
# same tween timing) rather than leading or lagging it - the two
# drifting at different rates is what read as detached before. The HP
# bar (vitals_bar) and NameLabel deliberately stay PINNED regardless of
# this - a moving health readout is worst exactly when the race is
# tightest - and hover_area (the click/hover target) staying put avoids
# a moving target. The intent number is smaller and reads as diegetic
# (part of the creature's own presence) rather than system-voice (like
# the HP bar), so it can follow without becoming a readability problem
# the way the bar would.

var _recession_tween: Tween

# Called by battle.gd's _tick_escape_distance() whenever Outbound's
# distance changes - fraction is distance/escape_distance_max, clamped
# here defensively even though the caller's own math shouldn't exceed
# 1.0. A SEPARATE tween from _lunge_tween/_flinch_tween/_targetable_
# tween/_flourish_tween (all of which still exist and still animate this
# same node) - in practice they never overlap in time with this
# (recession only ticks once, at the end of an enemy turn, well after
# that same turn's own lunge/flinch has already finished; the next
# attack/stun is at least a full player turn later, far past recession_
# tween_sec) - a known, accepted gap rather than building real tween
# arbitration across several independent animation sources for one
# enemy's presentation.
#
# Also drives IntentDisplay's own follow (2026-08-24, see intent_
# follows_recession's own note) - a genuinely separate concern from the
# visual_container tween above: IntentDisplay's own existing animations
# (refresh_intent()/show_intent_interrupt(), both via _intent_refresh_
# tween) only ever touch rotation/modulate:a, never position, so there's
# no same-property fight the way visual_container's several sources had
# to be reconciled for - this tween and that one can run concurrently
# without either erasing the other.
func set_recession(fraction: float) -> void:
	fraction = clamp(fraction, 0.0, 1.0)
	_recession_offset = Vector2(recession_travel_px * fraction, 0.0)

	if _recession_tween:
		_recession_tween.kill()
	_recession_tween = create_tween()
	_recession_tween.set_parallel(true)
	_recession_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_recession_tween.tween_property(visual_container, "position", _rest_position + _recession_offset, recession_tween_sec)

	if intent_follows_recession:
		_recession_tween.tween_property(intent_display, "position", _intent_rest_position + _recession_offset, recession_tween_sec)

# --- Attack lunge (DECIDED — see DESIGN.md's Combat Telegraphing note)
# ---
#
# A brief, fast jerk toward the player when this enemy resolves an
# ATTACK intent - not a full animation, just enough motion to sell "this
# thing just hit me." DEFEND never calls this (see battle.gd's
# _resolve_enemy_intent()) - block gain stays visually calm/static.
@export var attack_lunge_distance_px: float = 30.0
@export var attack_lunge_out_sec: float = 0.08
@export var attack_lunge_return_sec: float = 0.15
# Enemies always sit to the player's right (see DESIGN.md's Battle
# Layout note) - "toward the player" is always -X regardless of which
# slot this enemy occupies in a multi-enemy formation, so the lunge
# needs no per-instance facing/direction logic.

var _lunge_tween: Tween

# --- Pain turn (DECIDED — see DESIGN.md's Bestiary: the Wardling and
# enemy_data.gd's pain_turn_hp_threshold) ---
#
# A quick hunch/squash on visual_container, played when an interrupted
# turn actually resolves (see battle.gd's _resolve_enemy_intent()) -
# distinct from play_attack_lunge()'s horizontal jerk (this enemy isn't
# doing anything TO the player, so it shouldn't read as an attack) and
# from flash_damage()'s red tint (whatever triggered this already
# flashed separately, potentially turns ago in real time if the player
# took a while to end their turn, or - for a chain-payoff stun, see
# battle.gd's _apply_intent_interrupt() - already had its own hit number
# a moment earlier). Animates scale, not position - scale's rest value
# is always Vector2.ONE, so there's no layout math to duplicate the way
# play_attack_lunge() needs rest_x for. Named generically (2026-08-23) -
# originally authored for the Wardling's own pain turn specifically, now
# shared with any chain payoff that stuns via CardEffect.EffectType.STUN
# (see card_effect.gd) - the animation itself is identical either way,
# only the export names changed.
@export var interrupt_flinch_squash_scale: Vector2 = Vector2(1.08, 0.9)
@export var interrupt_flinch_out_sec: float = 0.12
@export var interrupt_flinch_return_sec: float = 0.35

var _flinch_tween: Tween

# --- Intent refresh (DECIDED — see DESIGN.md's Combat Telegraphing
# note) ---
#
# battle.gd's _advance_enemy_intent() calls refresh_intent() (not
# show_intent() directly) once this enemy's turn resolves - fades the
# CURRENT intent (icon+number+flavor together, via intent_display's own
# modulate, which cascades to both) out, holds empty for intent_refresh_
# gap_sec, then fades the NEW one in. Runs even when the new value is
# identical to the one just used - the fade-out/hold/fade-in cycle
# itself is what tells the player "this is a new turn's intent," not a
# comparison against the previous number. show_intent() itself (used
# for the very first intent at spawn, and by the on-demand hover path
# nothing here touches) stays a plain instant set - only an ADVANCE
# should read as a reset.
@export var intent_refresh_fade_sec: float = 0.25
@export var intent_refresh_gap_sec: float = 0.4

# --- Intent interrupt (DECIDED — see DESIGN.md's Bestiary: the Wardling;
# generalized 2026-08-23 for Guillotine's chain payoff, see card_effect.
# gd's STUN) ---
#
# show_intent_interrupt() below plays THIS instead of a calm crossfade
# when it's replacing an intent that's currently on screen - the
# difference between "this turn finished" (refresh_intent()'s smooth
# fade) and "this turn got CANCELLED" (a shake, then a harsher/faster
# cut) has to be legible at a glance, not just implied by timing. Same
# shake technique as card.gd's play_refused() (rotate right, left, back
# to rest), just applied to the whole intent icon+number group instead
# of a card - "this queued attack just got knocked off track," not "this
# card can't be played." Originally named for the Wardling's own pain
# turn specifically (its only trigger when this was built) - renamed
# generic now that a second, unrelated trigger (a chain payoff landing)
# reaches the exact same animation. The trigger doesn't change WHAT this
# looks like, only WHY it's happening, which is carried entirely by the
# flavor/combat-message text passed in, not by anything visual here.
@export var intent_interrupt_shake_rotation: float = 0.09
@export var intent_interrupt_shake_leg_sec: float = 0.045
@export var intent_interrupt_fade_out_sec: float = 0.12
# Deliberately shorter than intent_refresh_fade_sec (0.25) - a snap, not
# a settle.

var _intent_refresh_tween: Tween

# --- Name introduction (DECIDED — see DESIGN.md's Combat Telegraphing
# note) ---
#
# The name isn't a permanent label (see open question 1/Pillar 4(b): the
# world doesn't annotate itself) - it's an INTRODUCTION. It fades in near
# the silhouette when this enemy enters the fight (battle start, or a
# mid-battle arrival like the Beachwrack's debris spawn - both route
# through set_enemy_data() below, so both get exactly one intro), holds
# briefly so it's actually readable, then fades out for good. All
# exported so the pacing can be tuned by feel.
#
# Used to ALSO be re-triggerable on demand by hovering the silhouette
# (_on_silhouette_mouse_entered()/_exited()) - removed (2026-08-26): a
# world-voice element (the name) re-showing on a system-voice trigger
# (the cursor crossing hover_area, which happens constantly once a card
# is armed and the target line/rim highlight are doing the actual
# targeting work) read as a status readout, not flavor, and it competed
# with those two for the same visual attention. The name shows exactly
# once now, full stop - no combat event of any kind brings it back.
#
# Positioned in code (_apply_creature_layout(), name_gap_px below), a
# fixed gap above wherever the intent display actually ends up - NOT a
# fixed screen position. Intent's own position already varies per
# creature (a short creature's head sits lower than a tall one's), so
# anchoring the name to a constant offset instead of to intent itself
# would put it at an inconsistent distance from the cluster it's
# introducing - see DESIGN.md's optional-UI-elements convention for the
# same principle applied to the flavor line below.
@export var name_fade_in_sec: float = 0.4
@export var name_hold_sec: float = 2.0
@export var name_fade_out_sec: float = 0.6

# An elite (or boss - see enemy_data.gd's is_elite doc; a dedicated boss
# like BOSS_01 sets this true directly on its own resource) gets a more
# prominent introduction: longer hold, bigger gold-toned text, and a
# small scale "pop" on the way in instead of a plain fade - "this fight
# registers as an event," per the ask.
@export var elite_name_hold_sec: float = 3.5
@export var elite_name_font_scale: float = 1.3
@export var elite_name_pop_start_scale: float = 1.15
@export var elite_name_color: Color = Color(0.85, 0.65, 0.15, 1)
@export var normal_name_color: Color = Color(1, 1, 1, 1)
@export var name_font_size: int = 30

var _name_tween: Tween
# Whether _play_name_intro()'s tween is still mid-flight - see
# _on_name_intro_finished() and FlavorLabel's own "shares NameLabel's
# band" note in _apply_creature_layout(). NOT the same thing as name_
# label.modulate.a > 0.0 (which is only true during the fade-in/hold
# portion, not the whole intro window from spawn through fade-out) - this
# stays true for the tween's entire lifetime, which is exactly the window
# FlavorLabel needs suppressed.
var _name_intro_playing: bool = false

# --- Vitals cluster layout (DECIDED — bottom-anchored: the HP bar sits
# at a fixed position, the silhouette's FEET sit a fixed gap above it,
# and the silhouette's actual HEAD - not a fixed zone sized for the
# tallest creature - is what the intent cluster keys off. A short
# creature (Thicket Stalker) just doesn't reach as high as a tall one
# (the Wardling); nothing centers them in shared dead space.) ---
#
# Computed in code rather than baked into enemy.tscn's offsets, the same
# reason Card.gd computes its own layout from exports in _apply_layout()
# - every value below is meant to be retuned by eye in the Inspector,
# not by hunting through scene-file pixel offsets.
#
# Intent's position is the one fixed point everything else keys off -
# NameLabel positions a fixed gap ABOVE it (see name_gap_px below), and
# FlavorLabel (2026-08-27, "flavor text above the head" pass) shares that
# exact same band rather than reserving a separate spot of its own (see
# _apply_creature_layout()'s own note on why one shared band is correct,
# not just convenient). Neither ever reserves space for the OTHER's
# absence: both are pure overlays, their own modulate-only fades, never
# toggling `visible` and so never affecting anyone's layout (see the
# "Name introduction" note above) - an enemy without flavor text (or
# between hovers) never leaves a gap under its intent (see DESIGN.md's
# optional-UI-elements convention).
#
# Split into two passes because of a real ordering constraint: the
# BAR's position never depends on which creature this is, so
# _apply_bar_layout() can run immediately in _ready(). The SILHOUETTE
# and INTENT positions do depend on the creature's actual rendered
# bounds (see VisualBounds.compute() in visual_bounds.gd), which isn't
# known until _setup_visual() has actually instanced it - so
# _apply_creature_layout() runs from set_enemy_data(), after that.
@export_group("Vitals Cluster Layout")
@export var cluster_width_px: float = 500.0
# This Control's own width - was implicitly read from `size.x` (baked
# anchor width, resolved before _ready() when Enemy was a plain anchored
# child of UI). Now that Enemy lives inside EnemyZone (an HBoxContainer -
# see battle.tscn's Battle Layout note), width instead comes from
# container layout timing, which isn't guaranteed to have already run by
# the time _ready() fires. Explicit and Container-timing-independent
# instead: _ready() sets both custom_minimum_size.x and size.x from this
# (same defensive pair vitals_bar.gd/block_badge.gd already use, for the
# same "clamping only prevents shrinking, not growing back down" reason),
# and every internal layout formula below reads this instead of size.x.
#
# NO LONGER a flat authored constant in practice (2026-08-30, dynamic-
# cluster-width pass) - this default (500) is only ever what's actually
# in effect for the single frame between add_child() and set_enemy_data()
# (see _ready()'s own first _apply_bar_layout() call, which fires before
# enemy_data even exists), the same narrow window status_badge_row_
# height_override_px's own two-pass doc already describes. set_enemy_
# data() overwrites this with a REAL measured value the instant it can -
# see _apply_dynamic_cluster_width() below, called right after _setup_
# visual() has actually measured this specific creature's own rendered
# silhouette. Previously a genuinely fixed 500px for every enemy
# regardless of how big or small it actually rendered - the root cause
# of the layout-overflow investigation this pass follows from: boxes with
# no relationship to the silhouettes inside them were simultaneously too
# wide for a small creature and too narrow for a large one.
@export var cluster_width_padding_px: float = 24.0
# The gap between a silhouette's own measured horizontal edge and its
# reserved box's edge (2026-08-30, dynamic-cluster-width pass) - added on
# BOTH sides (see _apply_dynamic_cluster_width()'s own doc), so this is
# HALF of the total extra width a box gets beyond the silhouette's own
# real rendered width. A hand-eyeballed starting point, same as every
# other spacing value in this file and battle.gd's own enemy_separation_
# default/three_plus - expect to retune once seen live across the actual
# roster. Exported specifically so this is a single tunable number, not
# a magic literal buried in the formula that uses it.
@export var silhouette_scale: float = 2.6
# Applied to the same shared silhouette asset field_blob.gd instances
# for the field encounter (see its FIELD_VISUAL_SCALE) - just bigger
# here, since battle is where the player actually looks at what they're
# fighting. Bumped again in the Battle Layout tuning pass (was 1.9) -
# the creature is the visual anchor of this cluster, not an afterthought
# next to its own UI, and needs real presence now that both sides have
# more open space to occupy (see battle.tscn's Battle Layout note).
@export var bar_top_px: float = 420.0
# Fixed - doesn't move based on which creature this is (important for a
# future multi-enemy row, where every enemy's bar should align
# horizontally regardless of creature height). Sized with the tallest
# currently authored creature (the Wardling, scaled) in mind, so its
# intent cluster doesn't get pushed above this panel's own top edge -
# retune if a taller creature is ever added. MUST match
# PlayerBattleVisual.bar_top_px - see that export's own comment for why
# (this is the mechanism behind the "same horizontal baseline" the
# Battle Layout tuning pass asked for).
@export var bar_gap_px: float = 15.0
# Gap between the silhouette's actual bottom (its feet - see each
# enemy_visual_*.tscn, all re-authored so the origin IS the feet, shapes
# drawn at y <= 0 extending upward) and the top of the HP bar.
@export var intent_gap_px: float = 11.0
# Gap between the top of the silhouette (its actual head, derived from
# the creature's rendered bounds - see VisualBounds.compute() - times
# silhouette_scale) and the bottom of the intent display above it. The
# GLOBAL default every enemy uses unless it sets EnemyData.intent_gap_
# override_px (see _effective_intent_gap_px() below) - was 6.0, raised
# to 11.0 (2026-08-26, per a layout audit across all 7 enemies) because
# 6px read as crowded, especially against low/wide silhouettes like the
# Tideworn's. 11.0 is the MAXIMUM this global default can be while still
# keeping every currently authored enemy's NameLabel clear of the
# layout's own top edge (Beachwrack and Wardling are the tightest, at
# roughly 6px and 10px of headroom respectively at the old 6px gap) -
# see _effective_intent_gap_px()'s own clamp for what happens if a
# future creature (or an override) would exceed that budget.
@export var growth_indicator_gap_px: float = 11.0
# The grower-only counterpart to intent_gap_px above (2026-08-26, growth
# indicator tracking fix) - same default, so a grower at its baseline
# scale (scale_factor 1.0) reads identically to how intent_gap_px already
# rendered it. Unlike intent_gap_px, this is measured against the
# silhouette's CURRENT scaled top (see set_growth_scale()'s own
# _growth_indicator_rest_y()), not the fixed baseline height every other
# enemy's intent sits above - a grower's cap keeps rising as it swells,
# so a fixed screen position (what intent_display.position normally is,
# set once in _apply_creature_layout() and never revisited) would let the
# gap close as the mushroom grows into it. This export exists so that
# closing distance can be retuned without touching the shared intent_
# gap_px every non-grower still depends on.
@export var bar_width_px: float = 220.0
# Narrower than the panel - the bar should read as THIS creature's bar,
# proportional to it, not a full-width UI strip that happens to be
# nearby. VitalsBar's own height comes from its own bar_height_px export
# (see vitals_bar.gd) - this enemy.tscn's VitalsBar instance overrides it
# smaller than the shared default to match the tighter cluster.
@export var bottom_margin_px: float = 25.0
@export var name_gap_px: float = 10.0
# Fixed gap between the top of the intent display and the bottom of the
# name overlay above it - see the "Name introduction" note above for why
# this is measured from intent's position rather than a constant screen
# offset. NameLabel's own HEIGHT comes from whatever offset_top/
# offset_bottom is baked in enemy.tscn (only its Y position is computed
# here) - not exported, since it's a fixed label box, not part of the
# per-creature layout math.

# --- Flavor text legibility (DECIDED - shared by the intent flavor line
# AND defeat text below, one treatment for both so "floating atmospheric
# text over the field" reads as one consistent thing, not two) ---
#
# Both labels sit directly over whatever's behind them - the room/battle
# background, or a light-colored enemy silhouette - with no panel or
# bubble of their own (a panel would make this
# read as a UI element, which the brief is specifically avoiding: this is
# meant to stay atmospheric text, just legible atmospheric text). This
# used to be its own pair of exports here (flavor_outline_color/_size) -
# now reads from OverlayStyle instead (see overlay_style.gd's own header
# for the full "one shared treatment, not N independent copies"
# reasoning, which generalizes exactly this note beyond flavor text to
# every other combat overlay element with the identical problem).
#
# Went through a few rounds (see git history/DESIGN.md for the earlier
# dark-fill/light-outline attempt, and the bold-weight bump that
# followed it) before landing here: solid white fill, carried mainly by
# WEIGHT rather than the outline. flavor_bold_strength fake-bolds the
# font (FontVariation.variation_embolden - see _apply_bold() below, the
# same technique vitals_bar.gd/block_badge.gd/intent_display.gd already
# use for their own numbers) enough that the letterforms themselves
# supply most of the contrast against the backdrop's ground/sky alike;
# the outline is a light supporting edge on top of that, not the
# primary legibility mechanism, so it goes through OverlayStyle's own
# opacity_override (in the other direction from flavor_outline_width
# below - FAINTER than the shared outline_opacity, not thicker) rather
# than the heavier fully-opaque outline every other overlay element
# uses. Compared width/opacity pairs side by side via screenshot against
# both the ground and the pale sky - width 3 / opacity 0.3 reads as a
# genuinely feint shadow, present on close inspection, invisible as
# "chrome" from a normal glance.
#
# flavor_bold_strength REDUCED from 1.8 to 1.3 (2026-08-27, "flavor text
# above the head" pass) alongside flavor_font_size's own reduction - the
# two compounded into a "chunky" read once this moved into the primary
# scanning path above the creature; still enough weight to carry most of
# the contrast per this note's own reasoning, just not as heavy-handed
# about it.
@export var flavor_bold_strength: float = 1.3
@export var flavor_outline_width: int = 3
@export_range(0.0, 1.0, 0.01) var flavor_outline_opacity: float = 0.3

@export_subgroup("Flavor Line")
# The optional per-intent/per-escalation-stage flavor text (see
# enemy_intent.gd's flavor_text and battle.gd's _escalation_descriptor())
# - atmospheric, not tactical (the icon+number above already told the
# player everything they need to ACT on). MOVED (2026-08-27, "flavor
# text above the head" pass - see this pass's own report) from beneath
# the HP bar to directly above IntentDisplay, in NameLabel's own band -
# see _apply_creature_layout()'s own note on why hover text belongs in
# the primary scanning path above the creature now, and on how it shares
# that band with NameLabel without colliding. Still hidden entirely (not
# just blank) when there's nothing to show or nobody's hovering - see
# _refresh_flavor_visibility().
@export var flavor_head_gap_px: float = 8.0
# The gap between IntentDisplay's own TOP edge and the bottom of
# FlavorLabel - the flavor-text counterpart to intent_gap_px (which gaps
# IntentDisplay above the HEAD), same "global default, EnemyData.flavor_
# gap_override_px can override it per-creature" shape (see enemy_data.gd
# and _effective_flavor_gap_px() below). Close to name_gap_px (10.0) on
# purpose - FlavorLabel now occupies functionally the same slot NameLabel
# does (see this subgroup's own header note) - picked slightly tighter
# since flavor lines run longer/more varied than a name and don't need
# quite as much separation from intent's own icon. Eyeballed, expect to
# retune once seen live against every enemy - see _effective_flavor_
# gap_px()'s own clamp for what happens if a short creature can't afford
# even this much.
@export var flavor_label_height_px: float = 30.0
@export var flavor_font_size: int = 13
# REDUCED from 16 (2026-08-27, same pass) - the old size read as chunky
# once combined with flavor_bold_strength below, now that this sits in
# the primary scanning path above the creature (where IntentDisplay's own
# number is deliberately the dominant read) rather than as secondary text
# tucked beneath the HP bar.
@export var flavor_color: Color = Color(1, 1, 1, 0.85)
# White, carried by weight (flavor_bold_strength above) with a faint
# supporting outline rather than a dominant one - see the Flavor Text
# Legibility note above. Pulled to 0.85 alpha (from fully opaque) so
# flavor text reads as secondary to IntentDisplay's own number, the
# deliberately dominant read in the cluster (see the Combat Telegraphing
# note below). The outline treatment is unchanged - still the thing
# keeping this readable across a bright ground or a pale sky, just now
# backing a slightly quieter fill.
@export var flavor_fade_in_sec: float = 0.15
@export var flavor_fade_out_sec: float = 0.8
# Asymmetric on purpose (2026-08-27, same pass) - fast in, slow out.
# Hovering onto an enemy should feel immediately responsive (the player
# is actively asking a question, "what does this do"), but the answer
# shouldn't feel like it's snatched away the instant the cursor drifts -
# a slow fade-out reads as the text settling back into the scenery
# rather than the UI flinching. Reuses _play_name_intro()'s tween
# creation approach (kill-then-create on a dedicated tween, see
# _fade_flavor_to()) rather than instant show/hide.

# --- Defeat (DECIDED — see EnemyData.defeat_flavor and battle.gd's
# victory sequencing) ---
#
# play_defeat_sequence() below fades the silhouette (and IntentDisplay,
# and NameLabel if its own intro happened to still be running) out
# together, and - only if this enemy has EnemyData.defeat_flavor set -
# fades DefeatFlavorLabel in over the SAME area the silhouette just
# vacated (see _apply_creature_layout()'s positioning of it at the
# silhouette's mid-body point). An enemy with no defeat_flavor never
# shows this label at all - Battle still gets its pause either way (see
# battle.gd), but the resolution itself is silent. Its outline reads
# from OverlayStyle same as FlavorLabel's own (see that subgroup's note)
# rather than its own copy - same bold-white/faint-outline treatment as
# the intent flavor line, deliberately (same ground-level position, same
# problem).
@export_group("Defeat")
@export var defeat_fade_out_sec: float = 0.9
@export var defeat_flavor_fade_in_sec: float = 1.1
@export var defeat_flavor_font_size: int = 22
@export var defeat_flavor_color: Color = Color(1, 1, 1, 1)
# Matches flavor_color's own treatment - same reasoning above.

# --- Damage preview (see battle.gd's own "Damage preview seam" note) ---
#
# The falloff readout - shown only while the player hovers a damage-
# dealing hand card AND this enemy is the fight's own _escaping_enemy
# (today: only Outbound; inert - hidden, untouched - for every other
# enemy). Sits just above the HP bar (see _apply_bar_layout()), NOT a
# reserved layout slot the way FlavorLabel's is - this is transient, on-
# demand text, not a permanent part of the panel, so nothing else needs
# to make room for it whether it's showing or not. A distinct, muted
# rust tone rather than the "modified" amber CardTextStyles/the chain
# burst already use - that vocabulary means BOOSTED; this is a
# reduction, and reusing the same color for the opposite meaning would
# teach the wrong lesson.
@export_group("Damage Preview")
@export var damage_preview_gap_px: float = 6.0
@export var damage_preview_height_px: float = 24.0
@export var damage_preview_font_size: int = 15
@export var damage_preview_color: Color = Color(0.85, 0.5, 0.4, 0.95)

const INTENT_DISPLAY_HEIGHT := 48.0
# Matches intent_display.tscn's own fixed height - IntentDisplay owns
# its own internal layout, so this isn't exported here; it's just how
# much room to reserve for it before stacking the rest of the cluster.
# Icon+number only now - the flavor line that used to also live inside
# IntentDisplay (making this 80) moved out to FlavorLabel, see the
# "Flavor Line" export group above.
#
# A Panel+StyleBoxFlat frame briefly raised this to 76 (2026-08-26,
# intent-frame pass) and was reverted the same day (read as a sticker
# pasted over the scene) - back to 48, matching intent_display.tscn's own
# reverted offset_bottom.

# No authored silhouette yet -> a plain gray octagon, so an unarted enemy
# still shows SOMETHING here instead of an empty gap where a creature
# should be (there was no fallback shape in battle before - only field
# blobs had one - this is that same idea, extended to battle). Drawn
# feet-at-origin too (see _octagon_points()), same convention as every
# real silhouette.
const FALLBACK_COLOR := Color(0.5, 0.5, 0.55, 1)
const FALLBACK_RADIUS := 40.0

# Set by _setup_visual() once the actual creature is known - the
# rendered bounds of whatever's currently showing (a real silhouette or
# the fallback octagon), computed generically via VisualBounds.compute()
# (see visual_bounds.gd) rather than a hardcoded per-enemy number, so
# swapping in real art later needs no layout change here. In the
# visual's own PRE-scale local space - _apply_creature_layout() is what
# multiplies by silhouette_scale. See the "Vitals cluster layout" note
# above for why this can't just be a _ready()-time computation the way
# the bar's position is - it isn't known until a creature is chosen.
var _silhouette_bounds: Rect2 = Rect2()

# Set by _setup_visual() below, ONLY when a real EnemyData.visual_scene
# exists (stays null for the fallback octagon, which has no EnemyVisual
# script/hit-reaction nodes to call into) - lets flash_damage() below
# trigger a per-enemy hit reaction (see EnemyVisual.play_hit_reaction())
# without _setup_visual() needing to hand that instance anywhere else;
# nothing before this pass ever needed to keep it past that one function.
var _visual_instance: EnemyVisual = null

# --- Rim highlight overlay (2026-08-26, armed-card z-order fix) ---
#
# A SEPARATE CanvasGroup, sibling to visual_container, holding its OWN
# fresh instantiate() of enemy_data.visual_scene (same "duplicate the
# scene to render it a second way" technique OverlayStyle.make_icon_
# shadow() already uses for intent icon shadows) with its own material -
# same shader, same params, outline_only=true (see that uniform's own
# doc). Only its z_index ever moves (SNAP_HIGHLIGHT_Z_INDEX while
# highlighted, 0 otherwise) - visual_container's OWN z_index never
# changes, which is the actual fix: the creature's real sprite stays
# under an armed card always, only this transparent-except-the-glow
# duplicate goes on top.
var rim_highlight_overlay: CanvasGroup = null
var _rim_overlay_material: ShaderMaterial = null

# --- Growth scale ramp (see enemy_data.gd's min_growth_scale/max_growth_
# scale doc, and set_growth_scale() below) - RESTORED (2026-08-29) after
# a brief removal the same pass; kept alongside the newer per-stage
# sprite swap rather than replacing it ---
#
# The rim overlay's own SEPARATE instantiate() of visual_scene (see its
# doc above) needs its OWN copy of whatever growth scale the real body
# is currently at - the RemoteTransform2D that keeps rim_highlight_
# overlay in sync with visual_container only pushes visual_container's
# transform onto the overlay's outer wrapper, it never reaches into this
# INNER copy's own .scale. Stored the same way _visual_instance is
# (set once, in _setup_visual(), alongside its non-overlay counterpart) -
# also the reach-through set_growth_sprite_stage() below uses to keep a
# grower's rim-highlight copy showing the same stage sprite as the real
# body.
var _rim_overlay_visual: Node2D = null
var _growth_scale_tween: Tween = null
var _visual_root: Node2D = null
var _visual_root_base_scale: float = 1.0
# The actual node growth scaling multiplies onto (see set_growth_scale()
# below) - whichever one _setup_visual() actually built, a real
# EnemyVisual instance OR the plain fallback octagon, since a grower
# with no art yet still has to scale correctly. Deliberately NOT the
# same thing as _visual_instance above (typed EnemyVisual, stays null
# for the fallback case) - this is generic over either. base_scale is
# whatever that node's OWN baseline scale already was before growth
# (silhouette_scale for real art, 1.0 for the fallback, which _setup_
# visual() deliberately never scales - see its own branch) - captured
# once so growth multiplies ON TOP of the existing baseline instead of
# overwriting or assuming one.

func _ready() -> void:
	# hover_area used to also connect mouse_entered/mouse_exited here, to
	# re-show the name on hover as an "on demand" fallback (see the "Name
	# introduction" section's own note, and _on_silhouette_mouse_entered/
	# _exited's own removal below) - removed (2026-08-26): the name is a
	# one-time introduction now, not something hovering should bring back,
	# and the target line/rim highlight already fully own "which enemy is
	# targeted" - hovering an enemy no longer needs to do anything to its
	# name at all.
	# gui_input is a signal every Control already has (fires for input
	# within its rect) - connecting to it, rather than giving hover_area
	# its own script, is exactly how mouse_entered/exited above already
	# work, just for clicks instead of hover.
	hover_area.gui_input.connect(_on_hover_area_gui_input)
	# mouse_entered/mouse_exited ARE back now (2026-08-26, flavor-hover
	# pass) - but driving FlavorLabel's visibility, not the name (see
	# _refresh_flavor_visibility() below). Reusing hover_area rather than
	# a second hitbox - it already exists, already the click target, and
	# its mouse_filter is untouched by targeting mode (set_targetable()
	# only pulses visual_container; only play_defeat_sequence() ever sets
	# it to IGNORE), so hover keeps working identically whether or not a
	# card is currently armed. A SEPARATE, wider region than battle.gd's
	# own _update_snap_target()/get_snap_region_global() (the tighter
	# region driving the rim highlight/target line snap during targeting)
	# - the two aren't meant to move in lockstep, they answer different
	# questions ("is the cursor near this creature at all" vs. "should
	# the line snap here").
	hover_area.mouse_entered.connect(_on_hover_area_mouse_entered)
	hover_area.mouse_exited.connect(_on_hover_area_mouse_exited)
	name_label.modulate.a = 0.0
	flavor_label.add_theme_font_size_override("font_size", flavor_font_size)
	flavor_label.add_theme_color_override("font_color", flavor_color)
	OverlayStyle.apply_to_label(flavor_label, false, flavor_outline_width, flavor_outline_opacity)
	_apply_bold(flavor_label, flavor_bold_strength)
	# Alpha-only, like name_label's own init just above - no .visible
	# toggle any more (2026-08-27, "flavor text above the head" pass): see
	# _refresh_flavor_visibility()'s own note for why FlavorLabel now
	# mirrors NameLabel's "always structurally visible, modulate.a is the
	# only signal" shape instead of flipping .visible on top of it.
	flavor_label.modulate.a = 0.0
	defeat_flavor_label.add_theme_font_size_override("font_size", defeat_flavor_font_size)
	defeat_flavor_label.add_theme_color_override("font_color", defeat_flavor_color)
	OverlayStyle.apply_to_label(defeat_flavor_label, false, flavor_outline_width, flavor_outline_opacity)
	_apply_bold(defeat_flavor_label, flavor_bold_strength)
	defeat_flavor_label.visible = false
	defeat_flavor_label.modulate.a = 0.0
	damage_preview_label.add_theme_font_size_override("font_size", damage_preview_font_size)
	damage_preview_label.add_theme_color_override("font_color", damage_preview_color)
	OverlayStyle.apply_to_label(damage_preview_label, false, flavor_outline_width, flavor_outline_opacity)
	_apply_bold(damage_preview_label, flavor_bold_strength)
	damage_preview_label.visible = false
	_apply_bar_layout()
	_setup_rim_highlight()

# The creature-independent half of the layout - see the class-level note
# above. Also settles this Control's own final height, since the bar's
# position (now fixed, not derived from any creature's silhouette) is
# what that height actually depends on.
#
# FlavorLabel no longer has a slot here at all (2026-08-27, "flavor text
# above the head" pass) - it moved to directly above IntentDisplay (see
# _apply_creature_layout()'s own note), which depends on the creature's
# measured head_y and so can't be positioned in this creature-INDEPENDENT
# half any more. Nothing below the HP bar needs to reserve space for it
# any more either - custom_minimum_size below no longer factors it in.
func _apply_bar_layout() -> void:
	# Same defensive pair as vitals_bar.custom_minimum_size.x/size.x
	# below - see cluster_width_px's own comment for why this can no
	# longer just read size.x.
	custom_minimum_size.x = cluster_width_px
	size.x = cluster_width_px

	vitals_bar.position = Vector2((cluster_width_px - bar_width_px) / 2.0, bar_top_px)
	# Control.size is clamped to never go below custom_minimum_size, for
	# ANY parent - not just inside a Container. vitals_bar.tscn's root
	# still carries its old custom_minimum_size.x (380, from the
	# player-bar's original full width), so without this, asking for
	# anything narrower than 380 here would silently get clamped back up
	# to it - the bar would shift (this function's position math still
	# uses the requested bar_width_px) without actually narrowing.
	vitals_bar.custom_minimum_size.x = bar_width_px
	vitals_bar.size.x = bar_width_px

	# Sits just above the bar, same horizontal centering as vitals_bar
	# itself - transient/on-demand (see the Damage Preview export group's
	# own note), not a permanent slot every creature reserves whether it's
	# ever shown or not, so it's not folded into custom_minimum_size below.
	damage_preview_label.position = Vector2((cluster_width_px - bar_width_px) / 2.0, bar_top_px - damage_preview_gap_px - damage_preview_height_px)
	damage_preview_label.size = Vector2(bar_width_px, damage_preview_height_px)

	custom_minimum_size = Vector2(cluster_width_px, bar_top_px + vitals_bar.size.y + bottom_margin_px)

# The creature-dependent half - see the class-level note above. Called
# from set_enemy_data(), right after _setup_visual() has actually
# instanced this creature's silhouette and measured its bounds.
#
# Anchors on the silhouette's ACTUAL bottom edge (_silhouette_bounds.end
# .y), not just an assumed 0 - every enemy_visual_*.tscn is authored so
# that edge already sits at y = 0 (see DESIGN.md's enemy silhouettes
# note), but reading the real value instead of assuming it means a
# shape that's slightly off that convention (or a future Sprite2D with
# some built-in padding) still lands correctly instead of silently
# drifting off the bar.
func _apply_creature_layout() -> void:
	var feet_y := bar_top_px - bar_gap_px
	var scaled_bottom := _silhouette_bounds.end.y * silhouette_scale
	visual_container.position = Vector2(cluster_width_px / 2.0, feet_y - scaled_bottom) + enemy_data.battle_visual_offset_px
	_rest_position = visual_container.position
	# The recession baseline (see set_recession()'s own note) - cached
	# here, once, as the true anchor every OTHER animation on this node
	# (lunge/flinch/pulse) needs to return to. Untouched for every enemy
	# but Outbound, since _recession_offset below never moves unless
	# set_recession() is called.

	var head_y := _scaled_head_y()
	# Padded on both edges (see HOVER_AREA_VERTICAL_PADDING_PX's own doc)
	# - kept in separate locals rather than padding head_y itself, since
	# head_y also anchors IntentDisplay/NameLabel/mid_body_y below, none
	# of which should shift just because the click region grew.
	var hover_top_y := head_y - HOVER_AREA_VERTICAL_PADDING_PX
	var hover_bottom_y := _scaled_feet_y() + HOVER_AREA_VERTICAL_PADDING_PX
	hover_area.position = Vector2(0.0, hover_top_y)
	hover_area.size = Vector2(cluster_width_px, hover_bottom_y - hover_top_y)

	intent_display.position = Vector2(enemy_data.intent_horizontal_offset_px, head_y - _effective_intent_gap_px(head_y) - INTENT_DISPLAY_HEIGHT)
	# IntentDisplay's own anchors don't track cluster_width_px (see
	# enemy.tscn's IntentDisplay instance override, which pins it to a
	# fixed, non-stretching box) and its icon+number are placed with
	# hardcoded internal pixel offsets - so its horizontal centering has
	# to be driven explicitly from here too, the same way vitals_bar's
	# position is, rather than left to anchors that only happened to look
	# right at the original single-enemy cluster_width_px. Recomputed
	# every call (spawn AND multi-enemy re-scale), so a shrunk cluster
	# (see battle.gd's two/three_enemy_scale_factor) re-centers correctly
	# instead of staying pinned at the old, wider layout's position.
	intent_display.center_within(cluster_width_px)
	_intent_rest_position = intent_display.position
	# The recession baseline for IntentDisplay (see intent_follows_
	# recession's own note) - cached AFTER center_within(), which only
	# touches icon_root/value_label INSIDE IntentDisplay, never this
	# node's own outer position, so the order here doesn't matter for
	# correctness - kept after it anyway to read top-to-bottom as "fully
	# laid out, then remembered."
	# A fixed gap above intent's ACTUAL position, not a fixed screen
	# offset - see the "Name introduction" note above. name_label.size.y
	# is whatever fixed height is baked in enemy.tscn; only the Y
	# position changes per creature.
	name_label.position.y = intent_display.position.y - name_gap_px - name_label.size.y

	# FlavorLabel (2026-08-27, "flavor text above the head" pass) shares
	# NameLabel's own anchor - intent_display.position.y, the top edge of
	# IntentDisplay - rather than a flat pixel offset above the sprite:
	# battle_visual_scale alone spans a 4x range across today's enemies
	# (Tideworn 0.5, Beachwrack 1.2, the Mushrooms 2.0), so a fixed offset
	# would land at wildly different points relative to each creature's
	# actual measured head. Deliberately landing in the SAME band NameLabel
	# occupies rather than a third tier above it - stacking a permanent
	# third tier would need INTENT_GAP_PX's own tight per-creature budget
	# (see _effective_intent_gap_px()'s own doc: Beachwrack/Wardling clear
	# it by only ~6-10px today) to also make room for FlavorLabel's height
	# at ALL times, even though flavor only ever shows on hover. The two
	# never actually need to render at once (see _refresh_flavor_
	# visibility()'s own _name_intro_playing gate), so sharing one band is
	# correct, not just convenient.
	flavor_label.size = Vector2(cluster_width_px, flavor_label_height_px)
	flavor_label.position = Vector2(0.0, intent_display.position.y - _effective_flavor_gap_px(intent_display.position.y) - flavor_label_height_px)

	# Centered on the silhouette's own mid-body, not a fixed screen spot -
	# "where the creature WAS" has to track per-creature height the same
	# way intent/name do, so a short creature's defeat text doesn't land
	# in empty air above where it actually stood.
	var mid_body_y := (head_y + _scaled_feet_y()) / 2.0
	defeat_flavor_label.position.y = mid_body_y - defeat_flavor_label.size.y / 2.0

# The gap ABOVE the silhouette's head actually used for this creature -
# EnemyData.intent_gap_override_px if this creature sets one (a positive
# value means "use this instead"; 0.0, the default, means "no override,
# use the shared intent_gap_px"), otherwise the shared intent_gap_px.
#
# Also the clipping guard this feature's own brief required: a gap large
# enough to push NameLabel's own top edge above y=0 (this Control's own
# top, the layout's ceiling - see bar_top_px's own doc on why that
# boundary matters) is never silently allowed through, override or
# global default alike. max_safe_gap is head_y minus everything ELSE
# that sits between the silhouette's head and NameLabel's own top edge
# (INTENT_DISPLAY_HEIGHT, name_gap_px, NameLabel's own height) - solving
# name_label.position.y = 0 for the gap. A gap over that budget gets
# clamped to it (never negative either, via maxf - a creature short
# enough that even a zero gap would clip is a real problem, but this at
# least won't make it WORSE) and logged via push_warning() so a bad
# override or a future too-tall creature shows up in the run output
# rather than just quietly drifting off the top of the screen.
func _effective_intent_gap_px(head_y: float) -> float:
	var gap := intent_gap_px
	if enemy_data.intent_gap_override_px > 0.0:
		gap = enemy_data.intent_gap_override_px
	var max_safe_gap := head_y - INTENT_DISPLAY_HEIGHT - name_gap_px - name_label.size.y
	if gap > max_safe_gap:
		push_warning("Enemy '%s': intent gap %.1fpx would push NameLabel above the layout's top edge (max safe gap here is %.1fpx) - clamped." % [enemy_data.enemy_name, gap, max_safe_gap])
		gap = maxf(max_safe_gap, 0.0)
	return gap

# FlavorLabel's own counterpart to _effective_intent_gap_px() above
# (2026-08-27, "flavor text above the head" pass) - same "global default,
# EnemyData override, clamp against the layout's own ceiling" shape, just
# measured from IntentDisplay's own top edge (intent_top_y, already
# resolved by the time _apply_creature_layout() calls this) rather than
# from head_y directly, since FlavorLabel stacks on IntentDisplay, not on
# the head. Takes intent_top_y as a parameter instead of recomputing
# _effective_intent_gap_px(head_y) itself - _apply_creature_layout()
# already paid that cost once for intent_display's own position, and
# calling it twice would risk a duplicate push_warning for the same
# creature if intent's OWN gap was already clamped.
func _effective_flavor_gap_px(intent_top_y: float) -> float:
	var gap := flavor_head_gap_px
	if enemy_data.flavor_gap_override_px > 0.0:
		gap = enemy_data.flavor_gap_override_px
	var max_safe_gap := intent_top_y - flavor_label_height_px
	if gap > max_safe_gap:
		push_warning("Enemy '%s': flavor gap %.1fpx would push FlavorLabel above the layout's top edge (max safe gap here is %.1fpx) - clamped." % [enemy_data.enemy_name, gap, max_safe_gap])
		gap = maxf(max_safe_gap, 0.0)
	return gap

# The silhouette's actual head/feet in Enemy's own local space (i.e.
# visual_container.position.y adjusted by the scaled bounds) - shared by
# _apply_creature_layout() and get_floating_number_anchor() so there's
# one definition of "where this creature's head/feet actually are," not
# two
# copies of the same math. battle_head_offset_px (see EnemyData's own
# note) folds in here, not into _silhouette_bounds itself, so it only
# ever affects where the MEASURED top is read as being, never the real
# rendered geometry - the same "correction lives at the read site, not
# baked into the measurement" shape field_foot_offset_px already uses on
# the field side.
func _scaled_head_y() -> float:
	return visual_container.position.y + (_silhouette_bounds.position.y + enemy_data.battle_head_offset_px) * silhouette_scale

func _scaled_feet_y() -> float:
	return visual_container.position.y + _silhouette_bounds.end.y * silhouette_scale

const TARGET_ANCHOR_HEIGHT_FRACTION := 0.3
# How far down from the head this creature's target-line anchor sits, as
# a fraction of its own head-to-feet height - see get_target_anchor_
# position() below. 0.3 (upper body/chest, well above the true 0.5
# midpoint) is deliberate: hover_area extends HOVER_AREA_VERTICAL_
# PADDING_PX below the feet, close to where vitals_bar sits just past
# that padding, so a target-line endpoint that tracked the raw cursor
# anywhere in that generous hover region could land right on the HP bar
# - reading as the line "lying on the ground" instead of connecting to
# the creature (this feature's own brief). Snapping to a fixed point
# safely inside the silhouette's own upper half fixes that regardless of
# where the cursor happens to be within hover_area.

# The on-screen point the target line (see target_line.gd) should snap
# to once this enemy becomes the valid target - NOT the raw cursor
# position (see TARGET_ANCHOR_HEIGHT_FRACTION's own doc above for why).
# get_global_transform() (this is a Control - see this file's own
# extends - which has no Node2D-style to_global() of its own) turns the
# local point into the same canvas-pixel space hover_area.get_global_
# rect() and TargetLine's own drawing already use.
func get_target_anchor_position() -> Vector2:
	var head_y := _scaled_head_y()
	var anchor_y := head_y + (_scaled_feet_y() - head_y) * TARGET_ANCHOR_HEIGHT_FRACTION
	return get_global_transform() * Vector2(cluster_width_px / 2.0, anchor_y)

# The region battle.gd tests the cursor against for the target line's
# visual snap (see its own _update_snap_target()) - built from this
# creature's ACTUAL rendered silhouette bounds (_silhouette_bounds,
# scaled), grown by snap_margin_px (see its own doc for why this is a
# separate, tighter rect than hover_area's click region). Two corner
# points transformed individually, not a single Transform2D*Rect2 xform
# - same "just transform the points I actually need" shape get_target_
# anchor_position() above and card.gd's get_targeting_anchor_position()
# already use, rather than relying on an operator overload this file
# doesn't otherwise exercise. include_release_hysteresis adds snap_
# release_hysteresis_px on top - battle.gd passes true only while THIS
# enemy is already the snapped target (see snap_release_hysteresis_px's
# own doc), false otherwise.
func get_snap_region_global(include_release_hysteresis: bool = false) -> Rect2:
	var margin := snap_margin_px
	if include_release_hysteresis:
		margin += snap_release_hysteresis_px
	var scaled_position := visual_container.position + _silhouette_bounds.position * silhouette_scale
	var scaled_size := _silhouette_bounds.size * silhouette_scale
	var local_rect := Rect2(scaled_position, scaled_size).grow(margin)
	var xform := get_global_transform()
	var top_left := xform * local_rect.position
	var bottom_right := xform * (local_rect.position + local_rect.size)
	return Rect2(top_left, Vector2.ZERO).expand(bottom_right)

# The public entry point for giving this enemy something to display —
# called once, right after Battle instances the scene, same pattern as
# Card.set_card_data(). The name isn't a permanent label during combat
# (see the "Name introduction" section above) - the silhouette itself
# (shape, color, size) identifies the creature moment to moment; the
# name plays as a brief introduction instead.
func set_enemy_data(data: EnemyData) -> void:
	enemy_data = data
	# EnemyData.status_badge_row_height_override_px (2026-08-29, charge-
	# badge legibility pass) - applied here, as early as possible, and
	# _apply_bar_layout() is re-run right after: that function already ran
	# ONCE at _ready() (before enemy_data even existed, so it could only
	# ever have used vitals_bar's un-overridden default row height there),
	# and its own custom_minimum_size/size.x depend on vitals_bar.size.y
	# (see that function's own doc) - without re-running it, THIS node's
	# outer footprint would silently stay sized for the smaller, default
	# row even though vitals_bar itself grew. 0.0 (every enemy except a
	# Charge-boss) skips this EARLY call - _apply_bar_layout() runs again
	# unconditionally below regardless, for a different reason (dynamic
	# cluster width, not status badge height), so this isn't the only
	# place it can still matter for a Charge-boss - it's what makes the
	# outer footprint correct even before _setup_visual() has anything to
	# measure yet.
	if data.status_badge_row_height_override_px > 0.0:
		vitals_bar.override_status_badge_row_height(data.status_badge_row_height_override_px)
		_apply_bar_layout()
	vitals_bar.update_hp(data.max_hp, data.max_hp)
	update_block(0)
	# No show_intent() call here anymore - Battle calls it explicitly,
	# right after this, via _update_intent_display() (see battle.gd's
	# _spawn_enemy()). That's what lets escalation apply to the VERY
	# FIRST intent shown too, not just ones shown after an advance -
	# Battle is the only thing that knows about turn_number/escalation,
	# so it has to be the one deciding what this initial display says.
	_setup_visual()
	# cluster_width_px is now derived from THIS creature's own measured
	# silhouette (2026-08-30, dynamic-cluster-width pass), so it can only
	# be computed here, after _setup_visual() has actually instanced the
	# visual and measured _silhouette_bounds - see _apply_dynamic_cluster_
	# width()'s own doc. _apply_bar_layout() has to run again right after,
	# unconditionally this time (not just the Charge-boss case above) -
	# it's the one place vitals_bar/custom_minimum_size/damage_preview_
	# label actually read cluster_width_px, and the value it read at
	# _ready() (whatever the flat cluster_width_px default was at that
	# point) is now stale.
	_apply_dynamic_cluster_width()
	_apply_bar_layout()
	_apply_creature_layout()
	# Contact shadow (2026-09-01, battle grounding pass, ordering fix) -
	# AFTER _apply_creature_layout(), not from inside _setup_visual() any
	# more: the shadow's own position is baked ONCE, at call time, from
	# visual_container's CURRENT transform (see EntityShadow.attach()'s own
	# doc) - calling it before _apply_creature_layout() has set visual_
	# container.position captured the scene's pre-layout identity transform
	# instead, landing the shadow far from the actual creature (2026-09-01
	# investigation report). _apply_creature_layout() has exactly one call
	# site (this one) and the multi-enemy scale factor is already baked into
	# silhouette_scale/bar_width_px BEFORE set_enemy_data() ever runs (see
	# battle.gd's _spawn_enemies()) - nothing re-layouts an already-spawned
	# enemy, so this runs exactly once per Enemy instance, no idempotency
	# needed.
	grounding.apply_contact_shadow(self, visual_container)
	_setup_name_label()
	_play_name_intro()

# Derives cluster_width_px from this specific creature's own measured
# silhouette rather than leaving it a flat constant every enemy shares
# regardless of how big or small it actually renders (2026-08-30,
# dynamic-cluster-width pass - see cluster_width_px's own doc for the
# overflow investigation this follows from). real_width is the
# silhouette's ACTUAL rendered horizontal extent - _silhouette_bounds is
# in local, pre-scale space (see VisualBounds.compute()), so silhouette_
# scale (already carrying battle_visual_scale AND any multi-enemy
# compression, both pre-multiplied in before this ever runs - see
# _setup_visual()'s own doc and battle.gd's _spawn_enemies()) converts it
# to real screen pixels the exact same way _apply_creature_layout()'s own
# scaled_bottom already does for the vertical axis. cluster_width_padding_
# px is added on BOTH sides (hence the *2.0) - the gap between the
# silhouette's own edge and the box's edge, not a single shared margin.
#
# GROWTH TRACK ENEMIES (the Mushroom) reserve their WORST-CASE width up
# front - max_growth_scale, not the stage-0 baseline this function would
# otherwise measure - rather than shrinking to fit each growth stage and
# re-widening as it swells. Deliberately NOT re-called from set_growth_
# scale() to track live growth: cluster_width_px feeds custom_minimum_
# size.x on a direct child of EnemyZone (an HBoxContainer), so changing
# it after this creature has already been laid out alongside its
# neighbors would make EVERY sibling visibly slide sideways as EnemyZone
# re-flows the whole row around a mid-fight change to just this one
# child's box - a worse visual problem than the one being fixed here.
# Reserving the full worst-case box from the start means growth still
# never spills its slot (this pass's own hard requirement), at the cost
# of a not-yet-fully-grown Mushroom sitting in a box slightly wider than
# its CURRENT size needs - invisible either way, since the box itself
# has no rendered border/fill, only its width affects anything (spacing
# to its neighbors).
#
# Floored at bar_width_px - a creature measured narrower than its own HP
# bar (the smallest real silhouettes, heavily compressed, could plausibly
# land under 220px) still needs a box wide enough for the bar without
# the bar formula in _apply_bar_layout() ever going negative-relative-
# to-cluster-width.
func _apply_dynamic_cluster_width() -> void:
	var growth_mult: float = enemy_data.max_growth_scale if enemy_data.growth_stage_track_length > 0 else 1.0
	var real_width: float = _silhouette_bounds.size.x * silhouette_scale * growth_mult
	cluster_width_px = maxf(real_width + cluster_width_padding_px * 2.0, bar_width_px)

func _setup_visual() -> void:
	# battle_visual_scale (see enemy_data.gd's own note) is the per-enemy
	# correction for a silhouette authored at its own arbitrary coordinate
	# scale - 1.0 for every enemy except Tideworn today, a pure no-op
	# multiply. Folded directly into silhouette_scale itself, the same
	# "mutate the shared export once, before anything reads it" pattern
	# _spawn_enemies() already uses for its own multi-enemy scale_factor -
	# not a local variable scoped to just the visual.scale assignment
	# below, since _apply_creature_layout()'s own scaled_bottom and
	# _scaled_head_y()/_scaled_feet_y() all read silhouette_scale
	# directly too. A local-only version of this fix would have rendered
	# Tideworn at the right size while still doing every layout
	# computation (feet-planting, hover_area, intent/name positioning)
	# against the WRONG, unscaled height - exactly the kind of silent
	# mismatch this mutation avoids. Safe to run once per instance, same
	# assumption _spawn_enemies()'s own mutation already relies on -
	# set_enemy_data() (and therefore this) never runs twice on the same
	# Enemy node.
	silhouette_scale *= enemy_data.battle_visual_scale
	if enemy_data.visual_scene != null:
		var visual: Node2D = enemy_data.visual_scene.instantiate() as Node2D
		visual.scale = Vector2(silhouette_scale, silhouette_scale)
		visual_container.add_child(visual)
		_visual_instance = visual as EnemyVisual
		_visual_root = visual
		_visual_root_base_scale = silhouette_scale
		# visual's own children (Polygon2D pieces today, maybe a Sprite2D
		# or AnimatedSprite2D later) are what actually draw something -
		# visual itself is just the EnemyVisual wrapper, so bounds are
		# computed from ITS children, not visual itself.
		_silhouette_bounds = VisualBounds.compute(visual)
		var overlay_content: Node2D = enemy_data.visual_scene.instantiate() as Node2D
		overlay_content.scale = Vector2(silhouette_scale, silhouette_scale)
		_setup_rim_highlight_overlay(overlay_content)
		_rim_overlay_visual = overlay_content
	else:
		var fallback := Polygon2D.new()
		fallback.polygon = _octagon_points(FALLBACK_RADIUS)
		fallback.color = FALLBACK_COLOR
		visual_container.add_child(fallback)
		_visual_root = fallback
		_visual_root_base_scale = 1.0
		# No wrapper here - fallback IS the shape, directly under
		# visual_container, so bounds are computed from THAT instead.
		_silhouette_bounds = VisualBounds.compute(visual_container)
		var overlay_fallback := Polygon2D.new()
		overlay_fallback.polygon = _octagon_points(FALLBACK_RADIUS)
		overlay_fallback.color = FALLBACK_COLOR
		_setup_rim_highlight_overlay(overlay_fallback)
		_rim_overlay_visual = overlay_fallback

# A circle centered on (0, -radius) rather than the origin - its BOTTOM
# touches y = 0, matching every real silhouette's feet-at-origin
# convention (see enemy_visual_*.tscn), not its old vertically-centered
# shape.
func _octagon_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 8:
		var angle := i * TAU / 8.0
		points.append(Vector2(cos(angle), sin(angle)) * radius + Vector2(0, -radius))
	return points

# Sets the text and the elite-vs-routine STYLING once, up front - the
# intro/hover animations below only ever touch modulate/scale after
# this, never re-derive color or font size mid-fight.
func _setup_name_label() -> void:
	name_label.text = enemy_data.enemy_name
	if enemy_data.is_elite:
		name_label.add_theme_font_size_override("font_size", roundi(name_font_size * elite_name_font_scale))
		name_label.add_theme_color_override("font_color", elite_name_color)
	else:
		name_label.add_theme_font_size_override("font_size", name_font_size)
		name_label.add_theme_color_override("font_color", normal_name_color)
	OverlayStyle.apply_to_label(name_label)
	name_label.pivot_offset = name_label.size / 2.0

# Fire-and-forget - a Tween runs independently of whatever called this,
# so this never delays or blocks _spawn_enemy()/_start_battle() from
# continuing; the player can act on turn 1 while this is still playing.
# Routine enemies get a plain fade in/hold/fade out; an elite (or boss -
# see enemy_data.gd's is_elite doc) additionally pops in from elite_name_
# pop_start_scale instead of appearing at rest, and holds longer - "this
# registers as an event."
func _play_name_intro() -> void:
	_kill_name_tween()
	_name_intro_playing = true
	name_label.modulate.a = 0.0
	var hold := elite_name_hold_sec if enemy_data.is_elite else name_hold_sec
	_name_tween = create_tween()
	if enemy_data.is_elite:
		# set_parallel(true) runs the fade and the scale-pop together;
		# chain() switches back to sequential mode for hold/fade-out below,
		# which both branches share.
		name_label.scale = Vector2(elite_name_pop_start_scale, elite_name_pop_start_scale)
		_name_tween.set_parallel(true)
		_name_tween.tween_property(name_label, "modulate:a", 1.0, name_fade_in_sec)
		_name_tween.tween_property(name_label, "scale", Vector2.ONE, name_fade_in_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_name_tween.chain()
	else:
		name_label.scale = Vector2.ONE
		_name_tween.tween_property(name_label, "modulate:a", 1.0, name_fade_in_sec)
	_name_tween.tween_interval(hold)
	_name_tween.tween_property(name_label, "modulate:a", 0.0, name_fade_out_sec)
	# Flavor text shares NameLabel's own band (see _apply_creature_
	# layout()'s own note) - suppressed for this window rather than
	# stacked in a third tier, so it can't render on top of the name
	# intro if the player happens to be hovering right as an enemy spawns.
	# CONNECT_ONE_SHOT rather than awaiting this tween inline: _play_name_
	# intro() is deliberately fire-and-forget (see this function's own
	# header), so nothing here can just `await _name_tween.finished`
	# without turning this into a blocking coroutine every caller would
	# need to await instead.
	_name_tween.finished.connect(_on_name_intro_finished, CONNECT_ONE_SHOT)

func _on_name_intro_finished() -> void:
	_name_intro_playing = false
	# Re-checks hover state now that the intro's done - a player who was
	# hovering the whole time (blocked from seeing flavor per the
	# suppression above) sees it fade in the instant it's no longer
	# competing with the name, rather than needing to re-hover to trigger it.
	_refresh_flavor_visibility()

func _kill_name_tween() -> void:
	if _name_tween:
		_name_tween.kill()

func _on_hover_area_gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		enemy_clicked.emit()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()

# --- Flavor-text hover gating (2026-08-26, reworked 2026-08-27 - "flavor
# text above the head" pass) - see _update_flavor_label()'s own doc for
# why FlavorLabel moved off "always on" in the first place.
# _flavor_hovered is the only new state this needed: FlavorLabel.text
# already persists whatever the current intent's flavor is regardless of
# visibility, so "should this be showing right now" is always just
# _flavor_hovered and text != "" and not _name_intro_playing, recomputed
# fresh in _refresh_flavor_visibility() below rather than cached
# anywhere else. ---
var _flavor_hovered: bool = false
# Whether THIS enemy is currently mid-Charge-window (2026-08-29, charge-
# display pass) - a plain mirror of battle.gd's own EnemyCombatant.charge_
# phase == WINDOW, set/cleared by battle.gd's _advance_boss_charge() via
# set_charging() below at the exact two points that flag already flips
# (window open, window close - see that function's own call sites), never
# derived or duplicated here. Enemy has no notion of "charging" beyond
# this one bool; every enemy defaults to false and is completely
# unaffected, same "empty/false means unaffected" shape this codebase's
# opt-in fields already follow elsewhere (see enemy_data.gd's Charge
# section). Deliberately OR'd into FlavorLabel's existing hover gate
# (_refresh_flavor_visibility()/refresh_intent()'s own should-show checks
# below) rather than replacing _flavor_hovered - hovering a charging
# Leviathan should still just show what's already showing, not fight this
# flag or double-animate.
var _charging: bool = false
var _flavor_tween: Tween
# FlavorLabel's own dedicated tween (2026-08-27) - separate from
# _intent_refresh_tween/_name_tween, even though refresh_intent()/show_
# intent_interrupt() also animate this same label's modulate:a. Keeping
# it separate means a hover-triggered fade (_refresh_flavor_visibility()
# below) and an intent-driven crossfade can never fight over the SAME
# Tween object mid-flight - whichever one starts most recently simply
# kills the other first (see _fade_flavor_to()), the same "kill before
# create" rule every other per-purpose tween in this file already
# follows (_name_tween, _intent_refresh_tween itself). The two triggers
# coinciding at all (a hover ending in the
# exact frame an enemy's turn also advances) is rare and low-stakes
# either way - worst case is a one-frame jump in an already-fading
# alpha, never a stuck or fought-over state.
var _flavor_hovered_at_last_refresh: bool = false

func _on_hover_area_mouse_entered() -> void:
	_flavor_hovered = true
	_refresh_flavor_visibility()

func _on_hover_area_mouse_exited() -> void:
	_flavor_hovered = false
	_refresh_flavor_visibility()

# battle.gd's own set/clear call for _charging above - called from
# _advance_boss_charge() the instant charge_phase actually flips to/from
# WINDOW, so this Enemy-side bool never drifts out of sync with the real
# state battle.gd owns. Re-checks visibility immediately (not just left
# for the next refresh_intent() to pick up) for the same reason the hover
# handlers above do: a player un-hovering WHILE the window is open must
# NOT hide the tally (see _refresh_flavor_visibility()'s own updated
# should_show), and that has to hold the instant _charging flips, not
# only on this enemy's next turn advance.
func set_charging(active: bool) -> void:
	_charging = active
	_refresh_flavor_visibility()

# The one place FlavorLabel's shown/hidden STATE actually changes now -
# both _play_name_intro()'s own _on_name_intro_finished() (intro just
# ended, re-check in case the player was hovering the whole time) and the
# hover handlers above funnel through here. Deliberately NOT called from
# _update_flavor_label() any more (2026-08-26's original version was) -
# every caller of that function either runs before hovering is even
# possible (the initial spawn-time show_intent()) or is already mid-
# crossfade with its OWN fade-in immediately following the text swap
# (refresh_intent(), show_intent_interrupt() - see their own notes), so
# re-deriving "should this be showing" from content alone would either be
# a no-op or actively fight an in-progress animated transition those
# functions are already driving deliberately.
#
# should_show is compared against what it was at the LAST call here, not
# against flavor_label's own modulate/visible state (both of which are
# mid-tween most of the time now) - _flavor_hovered_at_last_refresh is
# the one piece of state this function owns, so a redundant call (should_
# show unchanged) is a no-op instead of restarting an identical fade.
func _refresh_flavor_visibility() -> void:
	# (_flavor_hovered or _charging) - 2026-08-29, charge-display pass:
	# _charging forces this on for the whole Charge window regardless of
	# hover (see its own doc above), same "OR another reason to show" shape
	# show_intent_interrupt()'s own unconditional force-show already
	# established, just persistent across turns instead of firing once.
	# _flavor_hovered is untouched - hovering still works exactly as
	# before for every enemy, charging or not.
	var should_show := (_flavor_hovered or _charging) and not _name_intro_playing and flavor_label.text != ""
	if should_show == _flavor_hovered_at_last_refresh:
		return
	_flavor_hovered_at_last_refresh = should_show
	if should_show:
		_fade_flavor_to(1.0, flavor_fade_in_sec)
	else:
		_fade_flavor_to(0.0, flavor_fade_out_sec)

# Shared by the hover fade above AND refresh_intent()/show_intent_
# interrupt()'s own intent-driven crossfades (2026-08-27) - kill-then-
# create on _flavor_tween, same shape _play_name_intro() already uses for
# name_label. FlavorLabel is alpha-only now, like name_label (see
# _ready()'s own init) - no .visible toggle, so there's nothing here to
# set beyond the tween itself.
func _fade_flavor_to(target_alpha: float, duration: float) -> void:
	if _flavor_tween:
		_flavor_tween.kill()
	_flavor_tween = create_tween()
	_flavor_tween.tween_property(flavor_label, "modulate:a", target_alpha, duration)

# Battle calls this while a card is armed (see battle.gd's
# _begin_targeting()/_cancel_targeting()) - true for every living enemy
# at once, false again once a target's chosen or targeting's cancelled.
# Pulses visual_container specifically (the silhouette itself), not this
# whole Control, so it can never compete with _play_flash()'s own
# modulate use on self.
func set_targetable(active: bool) -> void:
	if active:
		_start_targetable_pulse()
	else:
		_stop_targetable_pulse()

# A SINGLE scale-up into a held pose (2026-08-26 revision - see
# targetable_scale_multiplier's own doc) - NOT the infinite back-and-
# forth loop this used to be (kill-and-restart defensively, same as
# before, but nothing here schedules a return leg or repeats; the tween
# simply finishes with visual_container sitting at its scaled-up size
# until _stop_targetable_pulse() below snaps it back down). Reads as a
# quiet "this is targetable" acknowledgment, not a continuous bob
# competing for attention with the rest of the scene.
func _start_targetable_pulse() -> void:
	if _targetable_tween:
		_targetable_tween.kill()
	visual_container.modulate = TARGETABLE_TINT
	_targetable_tween = create_tween()
	_targetable_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_targetable_tween.tween_property(visual_container, "scale", Vector2.ONE * targetable_scale_multiplier, targetable_scale_duration_sec)

func _stop_targetable_pulse() -> void:
	if _targetable_tween:
		_targetable_tween.kill()
		_targetable_tween = null
	visual_container.scale = Vector2.ONE
	visual_container.modulate = Color(1, 1, 1, 1)

# Creates and assigns the rim shader's ShaderMaterial once, at _ready() -
# rim_intensity starts at 0.0 (off) regardless of what the exported
# rim_intensity above is configured to; that export is only READ once
# highlighting actually turns on (see set_snap_highlight() below), never
# applied directly here. Every OTHER rim export, by contrast, IS the
# shader's live value at all times - there's no "on/off" state for any
# of those, only for intensity.
func _setup_rim_highlight() -> void:
	var material := ShaderMaterial.new()
	material.shader = RIM_SHADER
	material.set_shader_parameter("rim_color", rim_color)
	material.set_shader_parameter("rim_thickness_px", rim_thickness_px)
	material.set_shader_parameter("rim_intensity", 0.0)
	material.set_shader_parameter("rim_falloff", rim_falloff)
	material.set_shader_parameter("rim_directional_amount", rim_directional_amount)
	material.set_shader_parameter("rim_light_direction", rim_light_direction)
	visual_container.material = material

# Builds rim_highlight_overlay - see its own var doc for why this exists
# as a wholly separate CanvasGroup rather than reusing visual_container's
# material a second time. `content` is a FRESH copy of whatever visual_
# container's own child just was (a real visual_scene instance, or a
# matching fallback octagon - see _setup_visual()'s two call sites),
# already scaled to silhouette_scale by the caller - this function only
# wraps it, it never decides what it looks like.
#
# Kept in perfect sync with visual_container's own LIVE transform via a
# RemoteTransform2D, not a one-time position/scale copy - visual_
# container moves continuously during exactly the window this might be
# showing (set_targetable()'s own pulse runs on every targetable enemy
# for the whole time a card is armed, which overlaps this overlay's own
# active window entirely). A RemoteTransform2D child of visual_container
# pushes its own (therefore visual_container's) global transform onto a
# remote target every frame with no per-frame scripting on this end -
# the idiomatic Godot tool for exactly this "keep a second node glued to
# a live one" problem, chosen over hand-rolled per-frame copying.
func _setup_rim_highlight_overlay(content: Node2D) -> void:
	rim_highlight_overlay = CanvasGroup.new()
	rim_highlight_overlay.z_index = 0
	rim_highlight_overlay.clear_margin = visual_container.clear_margin
	# Read from visual_container rather than hardcoded (enemy.tscn's own
	# VisualRoot bakes 32.0, well past CanvasGroup's own 10.0 default,
	# specifically so a creature's composited buffer isn't clipped at its
	# own edge before the rim shader ever runs) - this overlay's own
	# composited buffer needs the identical margin for the same reason,
	# and reading it live means it can't silently drift out of sync if
	# that baked value is ever retuned.
	rim_highlight_overlay.add_child(content)
	add_child(rim_highlight_overlay)

	var overlay_material := ShaderMaterial.new()
	overlay_material.shader = RIM_SHADER
	overlay_material.set_shader_parameter("rim_color", rim_color)
	overlay_material.set_shader_parameter("rim_thickness_px", rim_thickness_px)
	overlay_material.set_shader_parameter("rim_intensity", 0.0)
	overlay_material.set_shader_parameter("rim_falloff", rim_falloff)
	overlay_material.set_shader_parameter("rim_directional_amount", rim_directional_amount)
	overlay_material.set_shader_parameter("rim_light_direction", rim_light_direction)
	overlay_material.set_shader_parameter("outline_only", true)
	rim_highlight_overlay.material = overlay_material
	_rim_overlay_material = overlay_material

	var remote := RemoteTransform2D.new()
	visual_container.add_child(remote)
	remote.remote_path = remote.get_path_to(rim_highlight_overlay)

# Battle calls this on exactly one enemy at a time - whichever one the
# target line is currently snapped to (see battle.gd's own _snapped_
# enemy/_update_snap_target()) - to replace the target line's old
# endpoint reticle as the "this is your target" signal. A SEPARATE
# on/off switch from set_targetable() above: set_targetable() still
# marks every living enemy as a legal target for the whole time a card
# is armed (unchanged, out of scope for this pass); this marks ONE
# specific enemy as the one the cursor is actually connected to right
# now, which the two together can disagree about whenever more than one
# enemy is alive.
func set_snap_highlight(active: bool) -> void:
	var material := visual_container.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter("rim_intensity", rim_intensity if active else 0.0)
	# rim_highlight_overlay mirrors the SAME rim_intensity and gets its
	# z_index elevated (2026-08-26, second pass - see SNAP_HIGHLIGHT_Z_
	# INDEX's own doc for why visual_container itself no longer moves).
	# visual_container's own z_index is never touched here anymore - the
	# actual creature sprite stays under an armed card exactly like any
	# non-highlighted enemy; only the transparent-except-the-glow overlay
	# goes on top.
	if _rim_overlay_material != null:
		_rim_overlay_material.set_shader_parameter("rim_intensity", rim_intensity if active else 0.0)
	if rim_highlight_overlay != null:
		rim_highlight_overlay.z_index = SNAP_HIGHLIGHT_Z_INDEX if active else 0

# Battle calls this once, from _on_enemy_defeated() (either fire-and-
# forget if other enemies are still up, or awaited as the last step
# before its own post-fade beat/Continue-button step if this was the
# final one - see battle.gd's victory sequencing) - the silhouette,
# IntentDisplay, NameLabel (in case its own intro tween was still
# holding/fading), and VitalsBar all fade out together, since none of
# them mean anything once this enemy is out of the fight (this enemy
# stays put as a child of EnemyZone - see battle.gd's _on_enemy_
# defeated() - so its whole cluster, HP bar included, has to actually
# disappear here rather than relying on being removed from the scene).
# DefeatFlavorLabel only joins that fade-in if this enemy actually has
# EnemyData.defeat_flavor set - left blank, defeat is silent, exactly as
# commented on that field. hover_area stops accepting input entirely,
# not just visually - a defeated enemy must stop being clickable (see
# battle.gd's Enemy_clicked handling), and without this, its still-
# present (just faded) hitbox would keep swallowing clicks that should
# fall through to "clicked elsewhere, cancel targeting" instead.
func play_defeat_sequence() -> void:
	_kill_name_tween()
	if _lunge_tween:
		_lunge_tween.kill()
	if _intent_refresh_tween:
		_intent_refresh_tween.kill()
	hover_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_container, "modulate:a", 0.0, defeat_fade_out_sec)
	tween.tween_property(intent_display, "modulate:a", 0.0, defeat_fade_out_sec)
	tween.tween_property(name_label, "modulate:a", 0.0, defeat_fade_out_sec)
	tween.tween_property(vitals_bar, "modulate:a", 0.0, defeat_fade_out_sec)
	tween.tween_property(flavor_label, "modulate:a", 0.0, defeat_fade_out_sec)
	if enemy_data.defeat_flavor != "":
		defeat_flavor_label.text = enemy_data.defeat_flavor
		defeat_flavor_label.visible = true
		tween.tween_property(defeat_flavor_label, "modulate:a", 1.0, defeat_flavor_fade_in_sec)
	await tween.finished

# Battle calls this whenever the enemy's HP changes - VitalsBar (see
# vitals_bar.gd, shared with the player's own HP bar) owns the actual
# tween/embedded-number/low-HP-color display; this is just the pass-
# through Battle already calls.
func update_hp(current: int, max_hp: int) -> void:
	vitals_bar.update_hp(current, max_hp)

# Battle calls this whenever the enemy's block changes (gained from a
# Defend intent, or chewed through by a player attack) - shown as a
# shield badge at the HP bar's left end, hidden entirely at 0 (see
# block_badge.gd).
func update_block(amount: int) -> void:
	vitals_bar.update_block(amount)

# Battle calls this whenever this enemy's active-status list changes -
# see vitals_bar.gd's update_statuses() for the actual badge display.
# `statuses` is battle.gd's own EnemyCombatant.statuses - the REAL list,
# read here, never written to (see _charge_badge's own doc below for why
# a synthetic charge-window badge is layered on top of a duplicate rather
# than appended into the caller's actual array).
func update_statuses(statuses: Array[ActiveStatus]) -> void:
	if _charge_badge == null:
		vitals_bar.update_statuses(statuses)
		return
	var display_statuses := statuses.duplicate()
	display_statuses.append(_charge_badge)
	vitals_bar.update_statuses(display_statuses)

# The Charge window's own StatusBadgeRow indicator (2026-08-29, charge-
# display pass) - display-only, deliberately never added to battle.gd's
# real EnemyCombatant.statuses (see update_statuses() above, which is the
# ONLY place this ever reaches VitalsBar/StatusBadge - it's merged into a
# local COPY of whatever real list battle.gd hands over, right before
# that copy goes to vitals_bar.update_statuses(), and never merged back
# into the caller's own array). That's what keeps this invisible to
# status-modifier logic (_apply_status_modifiers()), tick logic (_tick_
# statuses()), and every other battle.gd function that iterates
# combatant.statuses for a real gameplay reason - none of them ever see
# this object, because it never lives in that array to begin with.
#
# null (every enemy, and a Charge-boss outside its own window) means no
# badge - same "empty/null means unaffected" shape _charging above uses.
# battle.gd's _advance_boss_charge() is the only caller of set_charge_
# badge()/clear_charge_badge() below, mirroring the exact same phase
# transitions that drive set_charging() - two independent Enemy-side
# flags for two independent display concerns (Issue 1's persistent
# flavor line vs. Issue 2's badge), even though both happen to flip at
# the same moments in the same function.
var _charge_badge: ActiveStatus = null

# Sets/refreshes the badge's own countdown number (EnemyData.charge_
# indicator_status's icon_color stays fixed - only `magnitude` changes,
# once per charge-window turn, as battle.gd recomputes turns remaining).
# Reuses the ONE ActiveStatus instance across those calls rather than
# rebuilding it each turn - nothing about StatusBadge/set_status() cares
# either way (it fully re-reads magnitude/data.icon_color every call),
# this is just the smaller change. No-ops if `status_data` is null - a
# Charge-boss that hasn't authored charge_indicator_status simply never
# gets a badge, same "unauthored optional resource, feature quietly
# doesn't apply" tolerance debris_spawn_enemy/attack_impact_sfx already
# have elsewhere on EnemyData. battle.gd is expected to call Enemy.
# update_statuses(combatant.statuses) right after this (see that
# function's own doc) - this alone only updates what WOULD be shown on
# the next render, it doesn't trigger one itself.
func set_charge_badge(status_data: StatusEffectData, magnitude: int) -> void:
	if status_data == null:
		return
	if _charge_badge == null:
		_charge_badge = ActiveStatus.new(status_data)
	_charge_badge.magnitude = magnitude

func clear_charge_badge() -> void:
	_charge_badge = null

# Battle calls this right after applying damage: a red flash and a
# floating "-N" number, so a hit reads as a hit even though nothing else
# about the enemy's position changes. empowered (see battle.gd's
# _deal_damage_to_enemy()) is true only for the chain's own payoff hit -
# everything below still happens exactly as before for a normal hit
# (empowered defaults false), this just adds a burst on top when it's
# true. No delay in here anymore (see chain_burst_duration_sec's own
# note) - by the time this runs for a chain payoff, battle.gd has
# already spaced it apart from the closer's own hit; this just needs to
# render immediately once called, same as any other hit.
#
# kind defaults to FloatingNumber.Kind.DEAL (every normal AND chain hit)
# - _play_flash() itself always tints red regardless, unconditionally
# ("you got hit" should never stop meaning that, chain or otherwise);
# only the FLOATING NUMBER'S look is what a caller can override, for a
# hit that needs to visibly read as a DIFFERENT kind of damage (see
# battle.gd's _deal_damage_to_enemy() weapon_reflect/retaliation
# handling).
func flash_damage(amount: int, empowered: bool = false, kind: FloatingNumber.Kind = FloatingNumber.Kind.DEAL) -> void:
	if empowered:
		_play_chain_burst()
	_play_flash()
	if _visual_instance:
		_visual_instance.play_hit_reaction()
	# Parented to the nearest CanvasLayer ancestor, NOT to self (see
	# get_floating_number_anchor() below) - self.modulate is what
	# _play_flash() just tinted red above, and a child Label would
	# inherit that tint, which is why the old same-parent version barely
	# read against the flash. Every Enemy today is only ever instanced
	# under battle.tscn's UI CanvasLayer (see battle.gd's ENEMY_SCENE
	# usage) - _find_floating_number_layer() walks up to find it rather
	# than hardcoding that path, so this doesn't break if that instancing
	# ever moves.
	FloatingNumber.spawn(_find_floating_number_layer(), get_floating_number_anchor(), amount, kind)

# The one NEW visual element for an empowered hit (the flash/number
# above are shared with every hit) - a filled circle built entirely in
# code (same "no separate scene file needed for something this simple"
# instinct FloatingNumber itself follows), scaling up from small while
# fading out. Positioned at the same mid-body point the floating number
# rises from, so it reads as coming from the hit itself rather than
# floating in unrelated space.
func _play_chain_burst() -> void:
	var burst := Polygon2D.new()
	burst.polygon = _circle_points(chain_burst_radius_px, 24)
	burst.color = chain_burst_color
	var mid_body := (_scaled_head_y() + _scaled_feet_y()) / 2.0
	burst.position = Vector2(visual_container.position.x, mid_body)
	burst.scale = Vector2(0.2, 0.2)
	add_child(burst)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector2.ONE, chain_burst_duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(burst, "modulate:a", 0.0, chain_burst_duration_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.finished.connect(burst.queue_free)

# N evenly-spaced points around a circle of the given radius, centered
# on the origin - Polygon2D has no built-in "draw a circle" shape, so
# this is the small amount of geometry needed to fake one with a many-
# sided polygon (24 segments reads as round at this size).
func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

# Battle calls this when this enemy resolves an ATTACK intent (see
# battle.gd's _resolve_enemy_intent()) - a quick out-and-back jerk on
# visual_container (the silhouette itself), independent of the flash/
# number flash_damage() plays on whoever gets HIT, since this is the one
# doing the hitting. rest_x is derived from _rest_position.x (see the
# Recession export group's own note) plus any current _recession_offset,
# rather than read back from visual_container.position.x itself, so a
# lunge re-triggered before the last one fully returned can't drift the
# resting position over repeated calls - and, for Outbound specifically,
# so an attack mid-fight jerks from and returns to wherever it's
# currently receded TO, not its original spawn spot (a no-op change for
# every other enemy, whose _recession_offset never moves off zero).
func play_attack_lunge() -> void:
	if _lunge_tween:
		_lunge_tween.kill()
	var rest_x := _rest_position.x + _recession_offset.x
	_lunge_tween = create_tween()
	_lunge_tween.tween_property(visual_container, "position:x", rest_x - attack_lunge_distance_px, attack_lunge_out_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_lunge_tween.tween_property(visual_container, "position:x", rest_x, attack_lunge_return_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# Battle calls this when this enemy's turn resolves as an INTERRUPTED
# turn (see battle.gd's _resolve_enemy_intent()) instead of a real
# intent - either the Wardling's own pain turn or a chain-payoff stun
# (see the export group above) - see it for why this animates scale
# rather than position the way the lunge does. Recession no longer
# touches scale at all (2026-08-27 rework - see the Recession export
# group's own note), so this is a plain Vector2.ONE-relative squash now,
# with nothing left to compose against.
func play_interrupt_flinch() -> void:
	if _flinch_tween:
		_flinch_tween.kill()
	_flinch_tween = create_tween()
	_flinch_tween.tween_property(visual_container, "scale", interrupt_flinch_squash_scale, interrupt_flinch_out_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_flinch_tween.tween_property(visual_container, "scale", Vector2.ONE, interrupt_flinch_return_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# Battle calls this the instant a chain payoff's STUN resolves (see the
# Chain Payoff Flourish export group above for why this is distinct from
# every other reaction near it). Two tweens racing in parallel: a
# modulate flash on `self` (in / hold / out - same out-and-back shape
# _play_flash() uses, just slower and with a hold in the middle) and a
# position shake on visual_container, alternating left/right back to
# rest - same "corner case" rest_x math play_attack_lunge() already uses,
# so this can't drift the resting position if re-triggered, or fight a
# lunge/recession animation already in flight. The shake's own leg count
# (see the loop below) is computed from the flash's total duration, not
# fixed, so "shaking for as long as the flash is visible" holds
# automatically no matter how chain_payoff_flourish_flash_leg_sec/_hold_
# sec above get retuned next.
func play_chain_payoff_flourish() -> void:
	if _flourish_tween:
		_flourish_tween.kill()
	_flourish_tween = create_tween()
	_flourish_tween.tween_property(self, "modulate", chain_payoff_flourish_color, chain_payoff_flourish_flash_leg_sec)
	_flourish_tween.tween_interval(chain_payoff_flourish_hold_sec)
	_flourish_tween.tween_property(self, "modulate", Color(1, 1, 1, 1), chain_payoff_flourish_flash_leg_sec)

	if _flourish_shake_tween:
		_flourish_shake_tween.kill()
	var rest_x := _rest_position.x + _recession_offset.x
	var flash_total_sec := 2.0 * chain_payoff_flourish_flash_leg_sec + chain_payoff_flourish_hold_sec
	# At least 2 legs (out, back) even if a leg duration retune ever made
	# this math round down to fewer - a shake needs to actually move and
	# return, not sit still. The LAST leg always targets rest_x regardless
	# of parity, so this can't end mid-shake off to one side no matter how
	# many legs the duration above works out to.
	var leg_count: int = maxi(2, roundi(flash_total_sec / chain_payoff_flourish_shake_leg_sec))
	_flourish_shake_tween = create_tween()
	_flourish_shake_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for i in leg_count:
		var leg_target_x: float = rest_x
		if i < leg_count - 1:
			leg_target_x = rest_x - chain_payoff_flourish_shake_distance_px if i % 2 == 0 else rest_x + chain_payoff_flourish_shake_distance_px
		_flourish_shake_tween.tween_property(visual_container, "position:x", leg_target_x, chain_payoff_flourish_shake_leg_sec)

# Battle calls this to show whichever intent is now "current" (always
# via _update_intent_display(), never directly - see battle.gd). The
# damage/block NUMBER always comes from intent.value unless Battle
# passes an override (display_value >= 0) - an already-escalated number
# for this turn, for an enemy whose intent values grow over the fight
# (see DESIGN.md's Bestiary: the Wardling). The icon itself is always
# intent.type - escalation never changes WHAT an enemy is about to do,
# only how much.
#
# display_flavor is the ONLY thing that reaches FlavorLabel here (2026-
# 08-27, "cut routine flavor" pass - see this pass's own report) -
# battle.gd's _update_intent_display() only ever passes it a non-empty
# string for an escalating enemy's current-stage wording (see battle.gd's
# _escalation_descriptor()); every other enemy passes "". intent.flavor_
# text (enemy_intent.gd) is deliberately NEVER read here any more - it
# used to be the fallback when display_flavor was empty, which meant
# FlavorLabel narrated nearly every routine turn, restating what the
# icon+number already show. That data is still fully authored on disk
# (see EnemyIntent.flavor_text's own doc for why it wasn't deleted) -
# this function just stopped looking at it. Load-bearing flavor text
# (an interrupted intent's blank icon, pain_turn_flavor/combat_message -
# see show_intent_interrupt()) never went through this function at all,
# so none of that is affected.
func show_intent(index: int, display_value: int = -1, display_flavor: String = "", display_value_suffix: String = "") -> void:
	if enemy_data.intents.is_empty():
		intent_display.clear()
		_update_flavor_label("")
		return
	var intent: EnemyIntent = enemy_data.intents[index]
	var value := display_value if display_value >= 0 else intent.value
	# status_magnitude (2026-09-02, status-telegraph pass) - straight off
	# the status resource's own exported default_magnitude (see intent_
	# display.gd's show_intent() for what this decides), not intent.value
	# and not hardcoded - the Saltdarner's poison spray authors value=0
	# (see enemy_intent.gd's status_data doc: damage and status are
	# independent numbers on the same intent), so reading THIS field
	# instead is what actually shows "3," not "0."
	var status_magnitude := intent.status_data.default_magnitude if intent.status_data != null else 0
	intent_display.show_intent(intent.type, value, display_value_suffix, status_magnitude)
	_update_flavor_label(display_flavor)

# The Mushroom's own display entry point (see enemy_data.gd's growth_
# stage_track_length doc and battle.gd's _advance_growth_stage()) -
# structurally separate from show_intent() above rather than a special
# case bolted onto it, since a grower's own `intents` array is EMPTY
# (show_intent() would just clear() on it, per its own first line) and
# there is no real EnemyIntent resource backing this number at all - the
# countdown comes straight from battle.gd's own stage-tracking, not
# intent.value. remaining is turns until eruption, already computed by
# the caller - this only pushes it to the display, same "caller owns the
# numbers" split every other VitalsBar/IntentDisplay readout in this
# codebase already follows.
func show_growth_countdown(remaining: int) -> void:
	intent_display.show_intent(EnemyIntent.IntentType.GROWTH, remaining)
	_update_flavor_label("")

# The Mushroom's own growth-scale ramp (see enemy_data.gd's min_growth_
# scale/max_growth_scale doc) - layered ON TOP of _visual_root_base_scale
# (itself fixed at spawn, see _setup_visual()'s own note), never
# replacing or feeding back into silhouette_scale/_silhouette_bounds.
# _apply_creature_layout()'s own HP-bar/intent-display math reads ONLY
# those two, neither of which this touches - that separation is what
# keeps the vitals cluster fixed in place while only the rendered
# creature grows, per this feature's own brief.
#
# Scales from _visual_root's own LOCAL origin - Node2D.scale's default
# pivot - since every silhouette is hand-authored with its feet AT that
# origin (see DESIGN.md's authoring convention). That's what makes the
# mushroom swell "upward and outward from where the stem meets the
# ground" for free, no separate anchor math needed: the origin itself
# never moves, only how far each vertex sits from it.
#
# Mirrors the SAME target scale onto the rim-highlight overlay's own
# copy (_rim_overlay_visual - see its own doc) so an armed-card glow
# never drifts out of sync with the body it's supposed to trace - the
# RemoteTransform2D that keeps the overlay glued to visual_container
# never reaches this inner copy's own scale on its own.
#
# animate=false (spawn - see battle.gd's _show_initial_intent_or_
# growth()) snaps straight to the target with no tween, so a mushroom
# staggered to start mid-track renders at its correct size on the very
# first frame, never at 1.0 first and then jumping. animate=true (every
# subsequent stage advance) tweens instead, eased out so it settles
# rather than pops.
#
# The growth indicator (intent_display, showing the countdown - see
# show_growth_countdown()) rides along in the SAME tween, via _growth_
# indicator_rest_y() below - see growth_indicator_gap_px's own doc for
# why this can't just reuse _apply_creature_layout()'s one-time head_y.
#
# RESTORED (2026-08-29) after a brief removal the same pass - layers
# alongside the newer per-stage sprite swap (set_growth_sprite_stage()
# below) rather than replacing it: the body keeps swelling AND changing
# art together now.
func set_growth_scale(scale_factor: float, animate: bool, duration_sec: float = 0.0) -> void:
	var target := Vector2.ONE * _visual_root_base_scale * scale_factor
	var indicator_y := _growth_indicator_rest_y(scale_factor)
	if not animate:
		if _growth_scale_tween:
			_growth_scale_tween.kill()
		if _visual_root:
			_visual_root.scale = target
		if _rim_overlay_visual:
			_rim_overlay_visual.scale = target
		intent_display.position.y = indicator_y
		_intent_rest_position = intent_display.position
		return
	if _growth_scale_tween:
		_growth_scale_tween.kill()
	_growth_scale_tween = create_tween()
	_growth_scale_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_growth_scale_tween.set_parallel(true)
	if _visual_root:
		_growth_scale_tween.tween_property(_visual_root, "scale", target, duration_sec)
	if _rim_overlay_visual:
		_growth_scale_tween.tween_property(_rim_overlay_visual, "scale", target, duration_sec)
	_growth_scale_tween.tween_property(intent_display, "position:y", indicator_y, duration_sec)
	_intent_rest_position = Vector2(intent_display.position.x, indicator_y)
	# Set immediately rather than on tween completion - _intent_rest_
	# position is only ever consulted by the Outbound-only recession
	# tween (see its own doc), which no grower participates in today, so
	# there's no real window where a mid-flight value would be read as
	# the wrong "rest" spot.

# The Mushroom's own final-turn telegraph (2026-08-29 - REPLACES show_
# growth_countdown() on the LAST turn before eruption, see battle.gd's
# _advance_growth_stage() for the exact "remaining <= 1" call site) -
# an eruption is a real, lands-for-damage attack (see EnemyData.growth_
# eruption_damage and battle.gd's _erupt_mushroom(), which routes it
# through the same _enemy_attack_player() every ATTACK intent uses), so
# the turn before it happens deserves the same Combat Telegraphing
# promise every other attack gets: the number shown is exactly what
# lands. Same "bypass show_intent()'s intents-array indexing" reasoning
# show_growth_countdown() above already uses (a grower's own `intents`
# stays empty) - just an ATTACK-type icon instead of GROWTH, and the raw
# eruption damage instead of the countdown.
func show_growth_eruption_warning(damage: int) -> void:
	intent_display.show_intent(EnemyIntent.IntentType.ATTACK, damage)
	_update_flavor_label("")

# The Mushroom's own per-stage sprite swap (2026-08-29, see EnemyVisual.
# growth_stage_textures's own doc) - called from battle.gd's own spawn
# display and every _advance_growth_stage() advance. Mirrors both
# instances a grower has (_visual_instance, the real body, AND the rim-
# highlight overlay's own separate copy) so an armed-card glow can never
# trace a stale stage's silhouette - the exact mismatch this would be if
# only the real body updated. A no-op for every enemy without growth_
# stage_textures configured - EnemyVisual.set_growth_sprite_stage()
# itself is the one place that actually checks for that; this just
# forwards to whichever instances exist.
func set_growth_sprite_stage(stage: int) -> void:
	if _visual_instance:
		_visual_instance.set_growth_sprite_stage(stage)
	if _rim_overlay_visual is EnemyVisual:
		(_rim_overlay_visual as EnemyVisual).set_growth_sprite_stage(stage)

# The growth indicator's target Y for a given scale_factor - the same
# "gap above the actual rendered top" shape _apply_creature_layout()'s
# head_y math already uses for intent_gap_px, but re-evaluated against
# the silhouette's CURRENT growth scale (silhouette_scale * scale_factor)
# instead of the fixed baseline silhouette_scale alone. That's the whole
# fix (2026-08-26, growth indicator tracking): _apply_creature_layout()
# computes intent_display.position exactly ONCE, at spawn, from the
# unscaled silhouette - fine for every intent-having enemy, since none of
# them change height mid-fight, but wrong for a grower, whose cap keeps
# rising toward that frozen position as it swells. Called from set_
# growth_scale() only (the one place a grower's scale ever changes),
# never from _apply_creature_layout() itself, so every non-grower's
# intent positioning is completely untouched.
func _growth_indicator_rest_y(scale_factor: float) -> float:
	var effective_scale := silhouette_scale * scale_factor
	var head_y := visual_container.position.y + (_silhouette_bounds.position.y + enemy_data.battle_head_offset_px) * effective_scale
	return head_y - growth_indicator_gap_px - INTENT_DISPLAY_HEIGHT

# Battle calls this instead of show_intent() when an intent is ADVANCING
# (see battle.gd's _advance_enemy_intent()) rather than being shown for
# the first time - see the "Intent refresh" export note above for why
# this always runs the fade cycle rather than only when the number
# actually changes. Awaited by battle.gd so the next beat of the turn
# (or the next enemy's own turn) doesn't start until this one's intent
# has actually finished settling into its new state.
func refresh_intent(index: int, display_value: int = -1, display_flavor: String = "", display_value_suffix: String = "") -> void:
	if _intent_refresh_tween:
		_intent_refresh_tween.kill()
	# Read off the label's ACTUAL current alpha, not re-derived from
	# _flavor_hovered (2026-08-27, interrupt-hover-gating revert) - the
	# two aren't the same question. show_intent_interrupt() forces
	# FlavorLabel fully visible UNCONDITIONALLY, regardless of hover (see
	# its own doc on why) - so a Wardling interrupted while nobody's
	# hovering it sits at alpha 1.0 with _flavor_hovered still false. If
	# this read _flavor_hovered here instead, flavor_was_visible would
	# come back false, this function would skip fading FlavorLabel out at
	# all, and the interrupt's forced-visible line would stay stuck at
	# full alpha forever (silently showing whatever text loads next -
	# escalation wording, on a Wardling - to a player who was never
	# hovering) - a real bug, caught by this pass's own verification.
	# Checking modulate.a instead answers the right question - "is
	# anything actually showing right now, for ANY reason" - so this
	# always fades out whatever was really on screen.
	var flavor_was_visible := flavor_label.modulate.a > 0.01

	_intent_refresh_tween = create_tween()
	_intent_refresh_tween.tween_property(intent_display, "modulate:a", 0.0, intent_refresh_fade_sec)
	if flavor_was_visible:
		_fade_flavor_to(0.0, intent_refresh_fade_sec)
	await _intent_refresh_tween.finished

	await get_tree().create_timer(intent_refresh_gap_sec).timeout

	show_intent(index, display_value, display_flavor, display_value_suffix)
	intent_display.modulate.a = 0.0
	# (_flavor_hovered or _charging) - see _refresh_flavor_visibility()'s
	# own updated doc for why; same OR, same reasoning, just this
	# function's own separate copy of the check (see this function's own
	# header note on why it doesn't call _refresh_flavor_visibility()
	# instead).
	var flavor_now_visible := (_flavor_hovered or _charging) and not _name_intro_playing and flavor_label.text != ""
	if flavor_now_visible:
		flavor_label.modulate.a = 0.0

	_intent_refresh_tween = create_tween()
	_intent_refresh_tween.tween_property(intent_display, "modulate:a", 1.0, intent_refresh_fade_sec)
	if flavor_now_visible:
		_fade_flavor_to(1.0, intent_refresh_fade_sec)
	await _intent_refresh_tween.finished

# Battle calls this the INSTANT this enemy's queued intent gets
# cancelled - either the Wardling's HP first crossing its pain-turn
# threshold (see battle.gd's _check_pain_turn_trigger() and enemy_data.
# gd's pain_turn_hp_threshold) or a chain payoff stunning it (see battle.
# gd's _apply_intent_interrupt() and card_effect.gd's STUN) - mid-turn,
# potentially while the player is still deciding their next move, not
# just once the interrupted turn actually resolves. That timing matters:
# whatever intent is CURRENTLY showing was a real, un-resolved promise
# ("this is what lands" - see DESIGN.md's Combat Telegraphing note, the
# same fairness rule _escalated_intent_value() already upholds for
# escalation). Leaving the old intent on screen until resolution would
# mean the player ends their turn expecting a hit that quietly doesn't
# happen - the opposite of that rule.
#
# The exit here is deliberately NOT refresh_intent()'s calm crossfade -
# see the "Intent interrupt" export group above. A shake (reads as
# "knocked off track") then a fast, harsh fade (reads as "cut off," not
# "settled") sells INTERRUPTED rather than finished. Shares
# _intent_refresh_tween with refresh_intent() (so an in-flight one
# correctly interrupts this, or vice versa, instead of the two fighting
# over the same properties) even though the shake/fade-out portion here
# is its own sequence - the fade-IN once the interrupted state lands,
# below, is identical to refresh_intent()'s own.
#
# Called the same beat flash_damage() already popped whatever number
# triggered this (a hit crossing the pain-turn threshold, or Guillotine's
# own damage landing just before its chain payoff fires) - starting the
# shake immediately, right here, rather than after some further pause,
# is what makes the hit and the interrupt read as one event instead of
# two.
func show_intent_interrupt(message: String) -> void:
	if _intent_refresh_tween:
		_intent_refresh_tween.kill()
	# See refresh_intent()'s own note on why this reads modulate.a
	# directly rather than re-deriving from _flavor_hovered - same
	# reasoning applies here too: FlavorLabel could already be sitting at
	# full alpha from an EARLIER interrupt's own unconditional force-show
	# (below), with _flavor_hovered still false the whole time.
	var flavor_was_visible := flavor_label.modulate.a > 0.01

	# Rotate around its own center, not the default top-left corner - a
	# corner-hinged shake would read as toppling, not trembling. Computed
	# fresh each call rather than cached once, since IntentDisplay's size
	# isn't settled until after the creature's own layout has run at
	# least once (see _apply_creature_layout()).
	intent_display.pivot_offset = intent_display.size / 2.0

	_intent_refresh_tween = create_tween()
	_intent_refresh_tween.tween_property(intent_display, "rotation", intent_interrupt_shake_rotation, intent_interrupt_shake_leg_sec)
	_intent_refresh_tween.tween_property(intent_display, "rotation", -intent_interrupt_shake_rotation, intent_interrupt_shake_leg_sec * 2)
	_intent_refresh_tween.tween_property(intent_display, "rotation", 0.0, intent_interrupt_shake_leg_sec)
	_intent_refresh_tween.set_parallel(true)
	_intent_refresh_tween.tween_property(intent_display, "modulate:a", 0.0, intent_interrupt_fade_out_sec)
	if flavor_was_visible:
		_fade_flavor_to(0.0, intent_interrupt_fade_out_sec)
	await _intent_refresh_tween.finished

	await get_tree().create_timer(intent_refresh_gap_sec).timeout

	intent_display.show_interrupted()
	_update_flavor_label(message)
	intent_display.modulate.a = 0.0
	flavor_label.modulate.a = 0.0

	_intent_refresh_tween = create_tween()
	_intent_refresh_tween.tween_property(intent_display, "modulate:a", 1.0, intent_refresh_fade_sec)
	# UNCONDITIONAL - deliberately NOT hover-gated, unlike everything else
	# FlavorLabel shows (escalation descriptors, routine flavor before it
	# was cut). Briefly hover-gated during the "cut routine flavor" pass
	# (2026-08-27), then reverted the same day: an interrupted intent (see
	# intent_display.gd's show_interrupted()) renders a completely blank
	# icon - no glyph, no number, nothing - specifically because THIS line
	# was expected to carry the whole moment on its own. Escalation still
	# has the icon's own number to lean on even when its descriptor is
	# hidden; an interrupt has nothing else at all, so gating it behind
	# hover would mean a player who stuns an enemy without hovering it
	# gets zero explanation for why its intent just vanished. This
	# asymmetry - interrupts forced, escalation gated - is intentional,
	# not an inconsistency to "fix" in some future pass.
	_fade_flavor_to(1.0, intent_refresh_fade_sec)
	await _intent_refresh_tween.finished

# Above the head now, in NameLabel's own band (2026-08-27 - see the
# "Flavor Line" export group above and _apply_creature_layout()'s own
# note), hidden entirely (not shown blank) when there's nothing to say.
#
# Hover-gated (2026-08-26) - permanently-visible flavor text didn't scale
# past one or two enemies on screen at once. Intent icons (IntentDisplay)
# are a SEPARATE node, untouched by any of this - they're the mechanical
# read and stay permanently visible regardless of hover, exactly as
# before. text is still stored/updated unconditionally here even while
# hidden, so hovering later shows whatever's actually current rather than
# something stale.
#
# Deliberately does NOT call _refresh_flavor_visibility() any more (2026-
# 08-27) - see that function's own doc for why: every caller of THIS
# function either runs before hovering is possible at all, or is already
# mid-crossfade and about to drive flavor_label's own fade-in itself
# right after this text swap (refresh_intent(), show_intent_interrupt()).
func _update_flavor_label(text: String) -> void:
	flavor_label.text = text

# A one-off, load-bearing FlavorLabel announcement (2026-08-29, Leviathan
# mark attack) - same "force fully visible, bypass hover/_charging
# entirely" technique show_intent_interrupt() already established for
# its own unconditional message (see that function's own doc for why:
# an event the player must not miss can't be gated behind hover), minus
# the icon shake/fade sequence, since this isn't an interrupted intent,
# just information. First (and today, only) caller: battle.gd's own MARK
# case in _resolve_enemy_intent(), announcing WHICH card just got marked
# the instant it happens - see CardData.marked_cost_modifier's own doc
# for why that can't just be read off the card face at the moment it
# happens (the marked card is sitting in the discard or draw pile, not
# rendered as a live Card node anywhere on screen right then).
#
# Deliberately does NOT fade back out on its own - left at full alpha
# until the NEXT real refresh_intent() call (next turn's own intent
# advance) naturally fades it out and in with new content, the exact
# same handoff show_intent_interrupt()'s own forced-visible message
# already relies on (see refresh_intent()'s own "flavor_was_visible"
# note for why reading modulate.a directly, not _flavor_hovered, is what
# makes that handoff correct).
func announce(message: String) -> void:
	_update_flavor_label(message)
	_fade_flavor_to(1.0, flavor_fade_in_sec)

# --- Damage preview (see battle.gd's own "Damage preview seam" note and
# the Damage Preview export group above) ---
#
# Battle calls this every time _update_damage_preview() decides this
# enemy's falloff should be showing (today: only while a damage card is
# hovered and this enemy is _escaping_enemy) - inert for every enemy
# that never receives a call, same "nothing calls it, nothing shows"
# shape every other opt-in display on this scene already follows.
# scalar is the SAME 1.0-at-zero-distance-down-to-0.0-at-max value
# _escape_falloff_scalar() already computes for the real hit - this is
# purely a read of existing state, not a second calculation of it.
func update_damage_falloff(scalar: float) -> void:
	var percent := roundi((1.0 - scalar) * 100.0)
	# Nothing to report yet (early in a fight, before distance has risen)
	# reads as no display at all, not a "-0% dmg" that's technically
	# correct but says nothing - same "empty means nothing to show"
	# instinct _update_flavor_label() above already follows.
	if percent <= 0:
		hide_damage_falloff()
		return
	damage_preview_label.text = "-%d%% dmg" % percent
	damage_preview_label.visible = true

func hide_damage_falloff() -> void:
	damage_preview_label.visible = false

# Wraps whatever font the label already resolves in a FontVariation that
# fakes bold via glyph embolden - no separate bold font asset to manage.
# Same technique as vitals_bar.gd's/block_badge.gd's/intent_display.gd's
# own _apply_bold() - flavor text is the first thing in THIS file that
# needed it (see the Flavor Text Legibility note above).
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)

# A quick tint to red and back. modulate multiplies this node's color
# (and every child's, since it inherits down) — animating it toward red
# and back to white(1,1,1,1) is the "flash."
func _play_flash() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", FLASH_COLOR, FLASH_LEG_DURATION)
	tween.tween_property(self, "modulate", Color(1, 1, 1, 1), FLASH_LEG_DURATION)

# Where a floating number spawned for this enemy should start: the
# center of Enemy's own global rect. Control has no to_global()/
# to_local() (those are CanvasItem-but-not-Control - a parse error
# caught this the first time around); get_global_rect() is the
# Control-native way to read a global point instead. No coordinate
# conversion needed despite FloatingNumber ending up parented on the
# shared UI CanvasLayer rather than under this Control (see flash_
# damage()'s own note): Enemy only ever reaches the tree via battle.gd's
# enemy_zone.add_child(instance), and enemy_zone is $UI/EnemyZone - a
# child of that SAME CanvasLayer. A Control's global_position/global_
# rect reflect its layout chain WITHIN one CanvasLayer only (never that
# layer's own transform/offset), so Enemy's global rect and a direct UI
# child's local .position are already the same coordinate space.
func get_floating_number_anchor() -> Vector2:
	return get_global_rect().get_center()

# Every Enemy today lives under EnemyZone, itself under battle.tscn's UI
# CanvasLayer (see battle.gd's ENEMY_SCENE usage) - walks up rather than
# hardcoding that path so this keeps working if the exact intermediate
# nodes ever change, same instinct as get_floating_number_anchor() above.
func _find_floating_number_layer() -> Node:
	var node := get_parent()
	while node != null and not (node is CanvasLayer):
		node = node.get_parent()
	return node
