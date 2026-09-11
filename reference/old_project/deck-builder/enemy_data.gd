extends Resource
# Same pattern as CardData (see card_data.gd): a plain data container, not
# a node, so we can define an enemy once as a .tres file and reuse/save it
# without writing any code for that specific enemy.

class_name EnemyData
# Lets us use "EnemyData" as a type name elsewhere (like Battle) and lets
# Godot list it as a resource type we can create in the editor — exactly
# like CardData does for cards.

@export var enemy_name: String = ""
# The name shown above the enemy, e.g. "Thicket Stalker".

@export var max_hp: int = 1

@export var intents: Array[EnemyIntent] = []
# The enemy's attack pattern, in order. Battle shows intents[0] as the
# "current" intent for now; the turn system will later advance through
# this array and loop back to the start when it runs out.

@export var visual_scene: PackedScene = null
# The enemy's silhouette (see enemy_visual.gd and, e.g.,
# enemy_visual_thicket_stalker.tscn) - the SAME scene is instanced both
# as the field encounter blob (field_blob.gd) and in battle (enemy.gd),
# just at a different scale per context - one asset, not two. Left
# empty, an enemy just shows the plain fallback shape in both places
# instead of crashing or rendering nothing - "unarted enemies still
# work."

@export var battle_visual_scale: float = 1.0
# Per-enemy multiplier on top of Enemy's own exported silhouette_scale
# (see enemy.gd's _setup_visual()) - the battle-side counterpart to
# field_visual_scale below, for exactly the same reason: every
# silhouette is hand-drawn at its own arbitrary coordinate scale, so two
# creatures "at the same" silhouette_scale can still render at wildly
# different actual sizes (first hit by the Tideworn's 2026-08-27 art
# pass - the new, far more detailed shape was authored at a much larger
# raw coordinate range than the old placeholder it replaced, and nothing
# in battle had ever needed a per-enemy scale knob before). 1.0 (every
# enemy defaults to this) means no adjustment, same "empty/no-op unless
# a specific creature needs it" shape field_visual_scale already uses.
# No live-update setter the way field_visual_scale has - battle has no
# equivalent of field_blob.gd's own `changed`-signal listener, since
# _setup_visual() only ever runs once, at spawn.

@export var battle_head_offset_px: float = 0.0
# Manual per-enemy nudge to where "the top of this creature" is measured
# for battle layout - hover_area's own top edge, and (since both derive
# from the exact same _scaled_head_y() - see enemy.gd) IntentDisplay and
# NameLabel's positions above it, all move together with this. Added
# with battle_visual_scale above (2026-08-27) - VisualBounds.compute()
# measures ALL of a silhouette's children uniformly with no notion of
# which piece actually reads as "the creature," so a shape with a tall
# decorative element (Tideworn's own Shell, riding well above its actual
# body) drags the auto-computed top up with it, floating the intent
# display and hover area far above where the creature visibly stands.
# 0.0 (every enemy defaults to this) means no correction - most
# silhouettes don't need one, the same "only set this if a SPECIFIC
# creature's auto-measurement is off" shape field_foot_offset_px already
# established for the opposite end. Same units convention too: the
# silhouette's own RAW authored coordinates (not final battle pixels,
# not yet multiplied by silhouette_scale/battle_visual_scale) - positive
# moves the measured top DOWN (toward the body, shrinking the effective
# head-to-feet span), negative moves it UP.

@export var battle_visual_offset_px: Vector2 = Vector2.ZERO
# Manual per-enemy nudge to visual_container's own final battle position -
# see enemy.gd's _apply_creature_layout(), which sets visual_container.
# position = Vector2(cluster_width_px / 2.0, feet_y - scaled_bottom) then
# adds this on top. Since hover_area/IntentDisplay/NameLabel/FlavorLabel
# are ALL computed FROM visual_container.position (via _scaled_head_y()/
# _scaled_feet_y() - see battle_head_offset_px above), this moves the
# whole creature - sprite, hitbox, and every label above it - together as
# one unit, not just the art. 0.0 (every enemy before BOSS_01) means no
# correction, same "0.0 means unaffected" shape every other manual
# battle-layout override on this resource already uses. Exists because
# real sprite art (unlike a hand-drawn Polygon2D, which IS its own exact
# visible bounds by construction) can carry authored padding VisualBounds.
# compute() has no way to see - it reads a Sprite2D's full texture size,
# not its opaque pixel bounds - so a sprite with empty margin baked into
# the file lands measurably off from where a Polygon2D silhouette with
# identical VISIBLE size would. Positive x moves right, positive y moves
# down - plain screen-pixel direction, not the silhouette's own raw
# authored coordinate space battle_head_offset_px uses (that field only
# nudges a MEASUREMENT; this one nudges the actual rendered position, so
# there's no per-enemy scale to divide out).

@export var intent_gap_override_px: float = 0.0
# Per-creature override for enemy.gd's own intent_gap_px (the gap between
# the top of this creature's silhouette and its intent display above it)
# - 0.0 (every enemy today) means no override, use enemy.gd's shared
# default exactly as before this field existed, same "0.0 means no
# correction" shape battle_head_offset_px above already established.
# Exists because the SAME pixel gap reads differently depending on
# silhouette shape - a low, wide creature can look crowded at a gap a
# tall, narrow one reads as generous above - so a single global value
# can never be right for every creature at once, only right on average.
# Read (and safety-clamped against NameLabel clipping above the layout's
# own top edge - see enemy.gd's _effective_intent_gap_px()) in enemy.gd's
# _apply_creature_layout(), the SAME read site the global default already
# used, not a second, parallel positioning path.

@export var flavor_gap_override_px: float = 0.0
# Per-creature override for enemy.gd's own flavor_head_gap_px (the gap
# between IntentDisplay's own top edge and FlavorLabel above it) - same
# "0.0 means no override, use the shared default" shape intent_gap_
# override_px above already established, for the exact same reason:
# headroom above IntentDisplay is already tight for some silhouettes
# (see enemy.gd's intent_gap_px doc - Beachwrack/Wardling clear the
# shared intent gap by only ~6-10px today) before FlavorLabel's own gap
# is even added on top of it. Read (and safety-clamped against
# FlavorLabel clipping above the layout's own top edge - see enemy.gd's
# _effective_flavor_gap_px()) in enemy.gd's _apply_creature_layout().

@export var intent_horizontal_offset_px: float = 0.0
# Per-creature horizontal correction for IntentDisplay - see enemy.gd's
# _apply_creature_layout(), which centers IntentDisplay on cluster_
# width_px / 2.0 (the SAME point visual_container itself is placed at -
# i.e. this creature's own AUTHORED LOCAL ORIGIN), never on the
# silhouette's actual rendered bounding box. That's correct on average
# but silently wrong for any silhouette not drawn symmetrically around
# its own origin - a long trailing body/tail pulls the true visual mass
# away from x=0 with nothing here noticing. 0.0 (every enemy before this
# field existed) means no correction, same "0.0 means unaffected" shape
# battle_head_offset_px/intent_gap_override_px above both already use.
# Positive shifts the intent RIGHT (toward mass sitting right of
# origin), negative shifts it LEFT - added directly to IntentDisplay's
# own position.x, nothing else. Most values here were derived by
# measuring each silhouette's own real bounds (VisualBounds.compute(),
# the exact function enemy.gd already trusts for vertical feet-
# anchoring) and scaling the resulting BOUNDING-BOX center offset by
# this creature's effective silhouette_scale (enemy.gd's shared 2.6
# default times battle_visual_scale above) - not hand-eyeballed, though
# still meant to be retuned here directly (no code change needed) if it
# ever reads wrong once seen live.
#
# Beachwrack's value is the ONE exception (2026-08-26, regression fix):
# a bounding-box center over the whole visual_scene (or any subset of
# it) turned out to be a bad proxy for this specific silhouette - it's
# dominated by whichever single vertex sits most extreme in each
# direction, regardless of how little drawn area is actually near it.
# Excluding the scaffolding/kelp salvage entirely only moved the number
# ~10% (-93.6 -> -84.2px) because the creature's OWN head/body art still
# has an outlying vertex or two pulling the box just as far left on its
# own - nowhere close to fixing the reported "floating well off the
# creature" bug. Tried an AREA-WEIGHTED centroid instead, across just
# the creature's own polygons (Head/Mouth/Body/BodyLight/BodyDark/Eye/
# FrontLeg/BackLeg/BackLeg2 - scaffolding and kelp still excluded) -
# weighting each shape by its own filled area via the shoelace formula
# rather than just its bounding corners got to -66.4px, better but still
# visibly too far left once seen live. Hand-tuned down from there to the
# value actually in beachwrack.tres now - every measured approach here
# was a starting point, not a substitute for checking it live. This
# measurement technique was NOT applied to Tideworn/Wardling's still
# bounding-box-derived values above - revisit them the same way (and
# expect to hand-tune the result afterward too) if either ever reads
# wrong live.

@export var field_visual_scale: float = 1.0:
	set(value):
		field_visual_scale = value
		emit_changed() # built-in Resource signal - see field_blob.gd's own listener for why.
# Per-enemy multiplier on top of field_blob.gd's own FIELD_VISUAL_SCALE/
# ENCOUNTER_VISUAL_SCALE baseline - since every silhouette is hand-drawn
# at its own arbitrary coordinate scale (see Run Structure & Navigation's
# enemy silhouettes note), two creatures authored at "the same" scale
# value can still render at wildly different actual sizes. 1.0 (every
# enemy defaults to this) means "render at exactly the shared baseline,
# no per-creature adjustment" - only an enemy that's been checked against
# the player's actual field size (see DESIGN.md's field movement
# redesign: composition & scale pass) should set anything else. Applied
# uniformly to both the real-art and plain-fallback-square branches of
# field_blob.gd's _build_member_visual(), so an enemy's intended relative
# size holds even before real art exists for it.

@export var field_foot_offset_px: float = 0.0:
	set(value):
		field_foot_offset_px = value
		emit_changed() # same live-update mechanism as field_visual_scale above.
# Manual per-enemy nudge for where this creature's FEET land on the field
# floor line, on top of field_blob.gd's automatic anchor (which measures
# the silhouette's own real rendered bottom edge via VisualBounds - see
# _build_member_visual()) - most enemies need this to stay at 0.0, since
# the automatic anchor already gets it right for a shape authored with
# feet at true y=0 (see DESIGN.md's silhouette-authoring convention).
# Only set this if a SPECIFIC creature's silhouette still looks off the
# ground after checking - it's the same idea as player_visual.gd's own
# foot_offset_px, just for enemies. In the silhouette's own RAW authored
# units (not final field pixels), same as everything else about a
# silhouette's shape - positive moves the figure DOWN (deeper into the
# ground), negative moves it UP (floating above the line).

@export var is_elite: bool = false
# Marks this enemy as ELITE-tier content (see DESIGN.md's Bestiary: the
# Wardling, and open question 14 on whether ELITE eventually becomes its
# own run-graph node type) - a real tag EnemyPool can filter on, rather
# than every caller that cares having to know it's specifically the
# Wardling by name. Every enemy defaults to false.
#
# Also drives Enemy's name-introduction treatment (see enemy.gd's
# _play_name_intro()) - an elite gets the longer, larger, gold-toned
# intro instead of the routine one. A dedicated boss (see the Charge
# section below) sets this true directly on its own .tres (see boss_01.
# tres) rather than inheriting it from anywhere - UNLIKE the old boss
# placeholder (removed 2026-08-29, see battle.gd's git history for
# _make_boss_variant()), which used to force this on a scaled-up COPY of
# a normal enemy at fight time, since there was no dedicated boss
# resource yet to just author it on directly.

@export var defeat_flavor: String = ""
# Optional. When set, this text fades in where the silhouette WAS as it
# fades out on defeat (see battle.gd's victory sequencing) - replacing
# the creature, not labeling it. Small and understated on purpose, not
# a headline. Left blank (most enemies), defeat is silent - no text,
# and nothing reserves space for it. See wardling.tres for the first
# use: "The Wardling is still."

@export var defeat_sfx: String = ""
# Optional cue played the instant THIS enemy is defeated (see battle.gd's
# _on_enemy_defeated()) - "" (every enemy without one authored) means
# silent, same "empty means no effect" convention pain_turn_sfx already
# uses, guarded the same way at its one read site rather than relying on
# AudioManager.play_sfx() to no-op on "". A name, not a file path - has
# to be a real key in AudioManager.SFX_FILES, same "which file plays
# lives in exactly one place" reasoning every other *_sfx field on this
# resource already follows. Generic over WHICH enemy dies, not scoped to
# any one mechanic - first use is Supply's own death cue (2026-08-29,
# GUN/SUPPLY), but any enemy can set this.

@export var pool_weight: float = 1.0
# How likely EnemyPool.pick_random() is to pick this enemy relative to
# the others, same weighted-roll technique as room_state.gd's room-type
# roll (see weighted_random.gd) - NOT a uniform pick_random() per file.
# Every enemy defaults to 1.0 (equal odds, the old behavior) unless
# tuned down for something meant to be rarer - see wardling.tres.

# --- Escalation (DECIDED — see DESIGN.md's Bestiary: the Wardling) ---
#
# Lets an enemy's intent values grow as the fight goes on, WITHOUT
# touching the existing fixed-loop `intents` array above or any other
# enemy - both fields default to empty, which battle.gd's escalation
# helpers treat as "no escalation, use intent.value exactly as
# authored." Only an enemy that explicitly fills these in (the Wardling)
# is affected; Thicket Stalker/Glasswing read intent.value unchanged,
# same as before this existed.
@export var escalation_multipliers: Array[float] = []
# One entry per escalation STAGE, in order - stage 0 covers the first
# `escalation_stage_length` turns, stage 1 the next batch, and so on;
# once the fight outlasts every defined stage, the LAST multiplier in
# this array just keeps applying (the fight doesn't de-escalate, or
# crash, if it runs long). Multiplies intent.value, rounded - see
# battle.gd's _escalated_intent_value().
@export var escalation_stage_length: int = 1
# How many turns each stage above covers.
@export var escalation_stage_descriptions: Array[String] = []
# One flavor line per stage, parallel to escalation_multipliers above -
# rendered beneath the intent icon+number (see intent_display.gd), not
# in front of the number. The ICON and the DAMAGE NUMBER are never
# affected by this array - only that dimmer line of tone underneath.
# Left empty, no flavor line shows regardless of what
# escalation_multipliers says (so a future enemy could escalate its
# NUMBERS without needing custom text, if that's ever useful).

# --- Pain turn (DECIDED — see DESIGN.md's Bestiary: the Wardling) ---
#
# A one-time interruption to the escalation arc above, not a modification
# of it: the first time this enemy's HP drops below pain_turn_hp_
# threshold (a fraction of max_hp), its currently-queued intent resolves
# as a beat of visible anguish instead - no attack, no defend, no icon,
# no number, just pain_turn_flavor. Exactly once per fight (see battle.gd's
# EnemyCombatant.pain_turn_used). Both default to "off" (0.0 / "") - every
# enemy except the Wardling is unaffected, same "empty means no effect"
# shape escalation_multipliers above already uses.
@export_range(0.0, 1.0, 0.01) var pain_turn_hp_threshold: float = 0.0
@export var pain_turn_flavor: String = ""

@export var pain_turn_sfx: String = ""
# Optional cue played the instant a pain turn actually triggers (see
# battle.gd's _check_pain_turn_trigger()) - "" (every enemy without one
# authored, including a hypothetical future pain-turn enemy that hasn't
# recorded its own yet) means silent, same convention attack_impact_sfx
# further down this file already uses: a name, not a file path, has to be
# a real key in AudioManager.SFX_FILES so "which file plays" still lives
# in exactly one place. NOT a shared generic fallback the way attack_
# impact_sfx's own empty case is (that one falls back to the shared
# damage_player cue) - there's no generic "pain turn" stock sound to fall
# back to, since this is meant to read as THIS creature's own specific
# reaction, not a mechanic-wide cue. Wardling's own value: "ragged_breath"
# (Works_Wardling/Ragged Breath.mp3).

# --- Erratic intent selection (DECIDED — see DESIGN.md's Bestiary: The
# Tideworn) ---
#
# Every enemy's intents array above normally advances in a fixed loop
# (see battle.gd's _advance_enemy_intent(): index+1, wrapping) - the
# Tideworn's whole design point is that it does NOT have a throughline
# the way the Wardling's escalation or any other enemy's repeating
# pattern does, so it needs a genuinely different selection rule rather
# than another tuning knob on the existing one. False (every enemy
# except the Tideworn) is completely unaffected - battle.gd still just
# advances the fixed loop exactly as before this existed. True picks a
# fresh random index into `intents` - independently, including possible
# repeats - both at spawn and on every subsequent advance, instead of
# stepping through them in order.
@export var erratic_intent_selection: bool = false

# --- Debris spawn (DECIDED — see DESIGN.md's Bestiary: the Beachwrack)
# ---
#
# Lets a landed hit from THIS enemy bring a second enemy into the fight,
# once per fight - the Beachwrack's "Knocks Something Loose": its Wind-
# Up Swing connecting (not fully blocked) shakes a Tideworn free of its
# own accumulated debris. Empty (every enemy except the Beachwrack) is
# completely unaffected - battle.gd's _check_debris_spawn_trigger() no-
# ops immediately whenever this is null, same "empty/zero means no
# effect" shape escalation_multipliers/pain_turn_hp_threshold above
# already use. Deliberately not scoped to a specific INTENT (there's no
# "which intent triggers this" field) - the Beachwrack's own pattern
# only ever has one real attack in it, so "this enemy's attack landed"
# already IS "the Wind-Up Swing landed" for this creature; a future
# enemy with more than one attack in its pattern wanting this on only
# SOME of them would need a real per-intent flag, not decided here.
@export var debris_spawn_enemy: EnemyData = null
# Which enemy joins the fight - the ACTUAL tuned resource (e.g.
# tideworn.tres), not a fresh copy, so the spawned creature is the real
# thing, not a stat-alike reskin (see DESIGN.md's Fiction note).

# --- Attack impact sound (DECIDED — see DESIGN.md's Bestiary: the
# Beachwrack) ---
#
# Optional per-enemy override for the sound played when THIS enemy's
# attack lands on the player - empty (every enemy) plays the shared
# generic "damage_player" cue exactly as before, same "empty means no
# effect" shape every other opt-in field on this resource already uses.
# A name, not a file path - it has to be a real key in AudioManager.
# SFX_FILES (see battle.gd's _enemy_attack_player()), so "which file
# plays" still lives in exactly one place (audio_manager.gd), never
# duplicated here. First use: the Beachwrack's own heavy impact sound,
# distinct from the shared punchy hit.wav every other enemy's attack
# still uses - a creature this size landing a swing shouldn't sound
# identical to a Wardling's claw.
@export var attack_impact_sfx: String = ""

# --- Escape (DECIDED — see DESIGN.md's Bestiary: Outbound) ---
#
# CONFIG only, not live state - "how fast does distance rise, and at
# what point does it end the fight" for THIS enemy type. The actual
# accumulated distance for a given fight is NOT stored here (a Resource
# like this one can be shared/reloaded across multiple fights - writing
# live per-fight progress onto it would leak between them) - it lives on
# battle.gd itself instead (see its own _escape_distance/_escaping_enemy
# note), since the encounter, not the enemy, is what owns "how far along
# is this escape." Both default to 0.0 - every enemy except Outbound is
# completely unaffected, same "empty/zero means no effect" shape pain_
# turn_hp_threshold/escalation_multipliers/debris_spawn_enemy above
# already use. Combat resolution stays ignorant of this everywhere
# except ONE seam (battle.gd's _deal_damage_to_enemy()) - nothing about
# card effects, targeting, or _resolve_damage() itself knows this exists.
@export var escape_distance_ramp: Array[float] = []
# How much distance accumulates at the end of each enemy turn (see
# battle.gd's _tick_escape_distance()), indexed by turns elapsed since
# combat start (0 for the first enemy turn, 1 for the second, ...) and
# clamped to the final entry if the fight runs past the table - an
# ACCELERATING retreat, not a flat per-turn amount (2026-08-27 retune,
# replacing the flat escape_distance_per_turn this field used to be -
# same "empty means this enemy doesn't use the mechanic" shape that had,
# just an empty array instead of 0.0, since a flat rate has no natural
# empty-array equivalent otherwise). Outbound's own [10, 15, 20, 25, 30]
# sums to exactly escape_distance_max (100) across 5 turns - the ramp's
# own shape, not escape_distance_max, is what actually tunes how many
# turns an unpressured escape takes; keep the two in sync by eye when
# either changes.
@export var escape_distance_max: float = 0.0
# The threshold that ends the fight via the escape resolution path (see
# battle.gd's _on_battle_escaped()) once accumulated distance reaches
# it. Also the denominator for the damage falloff scalar applied at the
# one seam above (see battle.gd's own ESCAPE_FALLOFF_* constants for the
# current curve shape, plateau-then-linear-to-a-floor, not a bare linear
# ramp to 0.0 anymore as of the same 2026-08-27 retune).

# --- Growth track (DECIDED — see DESIGN.md's Bestiary: the Mushroom) ---
#
# A rooted, non-attacking enemy that advances an involuntary stage track
# every one of its own turns and erupts once the track completes -
# structurally unrelated to `intents` above (a Mushroom's own `intents`
# stays empty - see enemy_intent.gd's GROWTH doc for why this needed a
# fully separate mechanism rather than another IntentType case in the
# normal resolution match). growth_stage_track_length <= 0 (every enemy
# except the Mushroom) means "not a grower" - battle.gd's own _advance_
# growth_stage() no-ops immediately whenever this is 0, same "zero/empty
# means no effect" shape escalation_multipliers/debris_spawn_enemy above
# already use.
@export var growth_stage_track_length: int = 0
# How many of this enemy's own turns until it erupts.
@export var growth_start_stage: int = 0
# How far along the track this enemy STARTS, at spawn - lets several
# growers in the same encounter be staggered (see resources/encounters/
# own Mushroom-patch note) so their eruptions land on different turns
# instead of simultaneously. 0 (the default) starts at the very
# beginning, showing the full track_length as its first countdown value.
@export var growth_eruption_damage: int = 15
# Damage dealt to the player when this enemy's track completes - routes
# through the exact same _enemy_attack_player() every ATTACK intent uses
# (see battle.gd's _advance_growth_stage()), so it's blockable, accrues
# Toll, and opens a Rally pool exactly like a normal attack, with zero
# special-casing in either system.

@export var min_growth_scale: float = 1.0
@export var max_growth_scale: float = 1.35
# The visual swells across the track, from min at growth_stage 0 (spawn,
# the full countdown) to max at growth_stage growth_stage_track_length-1
# (the LAST stage shown before eruption - see battle.gd's own _growth_
# scale_for_stage()). Driven by growth_stage progress, not the raw
# countdown number, so retuning growth_stage_track_length alone still
# spans the same min-to-max range over however many stages now exist -
# no matching retune needed here. Applied to Enemy.set_growth_scale() as
# a multiplier ON TOP of silhouette_scale, never replacing it - see that
# function's own doc for why that's what keeps the HP bar/countdown
# fixed in place while only the rendered creature grows. RESTORED
# (2026-08-29) after a brief removal the same pass - kept alongside the
# newer per-stage sprite swap (EnemyVisual.growth_stage_textures) rather
# than replacing it: the two layer together (a still-swelling body,
# wearing a progressively worse-looking sprite), not an either/or.
@export var growth_scale_tween_duration_sec: float = 0.25
# How long each stage's scale change takes to settle - see Enemy.set_
# growth_scale()'s own animate=true path. Deliberately independent of
# ENEMY_TELEGRAPH_PAUSE/ENEMY_RESOLVE_PAUSE (battle.gd) - this only
# needs to feel like a visible swell, not sync to the turn's own pacing
# beats, so it runs fire-and-forget rather than being awaited.

@export var min_layer: int = 0
# Which run-graph layer this enemy first becomes eligible to be picked
# for an ordinary combat room (see EnemyPool.pick_random()'s current_
# layer param and room_state.gd's _generate_combat_layout()) - a hard
# floor, not a soft weighting curve: below this layer, this enemy simply
# isn't a candidate at all, same "excluded, not rolled-then-clamped"
# idiom room_state.gd's own _pick_blob_count() already uses. 0 (every
# enemy except Outbound) means no restriction -
# eligible from the very first layer, exactly today's behavior. Distinct
# from pool_weight above, which only affects the ODDS among whichever
# candidates already cleared this floor, not whether an enemy clears it.

# --- Charge (DECIDED - see DESIGN.md's Bestiary: BOSS_01) ---
#
# A stationary boss's periodic multi-turn Charge (2026-08-29 rework -
# REMOVES the old TELEGRAPH/SWING preamble this mechanic used to open
# with): outside the charge window, the boss attacks normally every turn
# (Leviathan picks randomly between two baseline attacks - see battle.gd's
# _pick_baseline_attack_index()); once turns_before_first_telegraph normal
# turns have passed, a WINDOW begins - charge_window_turns turns during
# which the boss keeps attacking (at charge_attack_value below, a fixed,
# reduced hit, NOT the baseline attacks) while player damage accumulates
# against it. If the total lands below charge_damage_threshold by the
# window's last turn, the boss gains an outgoing-damage buff (see
# charge_buff_status below) - otherwise nothing happens. No wind-up turn
# and no forced full-strength payoff swing any more - the charge window's
# own attacks ARE the telegraph now (a real, undimmed hit every turn,
# alongside the accumulating-damage readout), not a single hit previewed
# one turn in advance.
# Structurally separate from `intents`/current_intent_index's own fixed-
# loop-or-erratic advancement, same "own dedicated state, own dedicated
# advance function, intents stays small and mostly decorative" shape
# growth_stage_track_length (the Mushroom) and escape_distance_ramp
# (Outbound) already established - see battle.gd's _advance_boss_charge()
# for the actual state machine, and EnemyCombatant's own charge_* fields
# for the per-fight live state (mirroring growth_stage's own split from
# this resource's STATIC config).
#
# charge_window_turns <= 0 (every enemy except a Charge-boss) means "no
# Charge mechanic at all" - the same "zero/empty means unaffected" idiom
# growth_stage_track_length/escape_distance_max/pain_turn_hp_threshold
# above all already use. BOSS_01's own value is 3 turns - this field's
# OWN default here is 0 (off), not 3; the "default 3" from this pass's
# own brief is BOSS_01's authored value, not a global default every
# future Charge-boss would silently inherit.
@export var charge_window_turns: int = 0
@export var charge_damage_threshold: int = 0
# Total player damage that must land on this boss DURING the window (all
# turns combined, post-block HP loss - see battle.gd's _deal_damage_to_
# enemy() hook, gated on this same field) to interrupt the Charge. A
# FIXED number, not a percentage read at check-time - see battle.gd's
# EnemyCombatant.charge_effective_threshold for why the LIVE value used
# for any one window is this number clamped against the boss's own HP at
# the moment the window begins (a late-fight window can't demand more
# damage than the boss actually has left, or the Charge would become
# impossible to interrupt without simply killing the boss outright,
# silently changing what "interrupted" even means).
@export var charge_buff_multiplier: float = 1.5
# The Charge buff's own outgoing-damage multiplier if the window's
# accumulated damage falls short - 1.5 means "+50% damage." Applied by
# constructing a fresh ActiveStatus from charge_buff_status below, then
# OVERWRITING its magnitude/turns_remaining directly from this field and
# charge_buff_duration_turns (not the status resource's own baked-in
# default_magnitude/default_duration_turns) - see battle.gd's own
# application site. This is what lets this ONE exported float retune the
# buff's real strength with no second number to keep in sync inside a
# separate .tres file, the same "one number, one place" reasoning this
# whole export group already follows throughout.
@export var charge_buff_duration_turns: int = 3
@export var charge_attack_value: int = 0
# The fixed damage a Charge-boss's window attacks deal (2026-08-29 rework)
# - read directly by battle.gd's _update_intent_display()/_resolve_enemy_
# intent() whenever the current intent's type is EnemyIntent.IntentType.
# CHARGE_ATTACK, INSTEAD OF that intent's own `value` (which stays
# unauthored/unused, same "meaningless, never read" shape IDLE's own
# value already has - see enemy_intent.gd). Deliberately the single
# source of truth rather than also authoring it on the CHARGE_ATTACK
# intent itself: two numbers that have to be kept in sync by hand is
# exactly the trap WIND_UP's own doc already warns about for a mismatched
# paired value - this field is the only place Leviathan's charge-window
# damage is ever written. 0 (every enemy except a Charge-boss) is never
# read - CHARGE_ATTACK is never used on any other enemy today.
@export var turns_before_first_telegraph: int = 1
# How many normal-attack turns run before the charge WINDOW begins - both
# at fight start AND after every resolved Charge (interrupted or bought a
# buff), read fresh each time normal attacks resume. Name kept from this
# field's original TELEGRAPH-era authoring (see this section's own 2026-
# 08-29 rework note - there's no telegraph turn any more, only the
# window itself) rather than renamed, since renaming an @export var
# changes the property key boss_01.tres serializes it under. Not JUST
# "before the first" despite the name - see battle.gd's _advance_boss_
# charge() for the actual gate: normal-phase turns don't even start
# counting toward this total while charge_buff_status is still active on
# the boss, which is what structurally guarantees "the buff duration and
# the charge cycle must not overlap" (this pass's own brief) - a new
# window literally cannot begin until the buff (if any) has already
# expired, no separate overlap check needed anywhere else.
@export var charge_buff_status: StatusEffectData = null
# The StatusEffectData shape (category/modifier_target/modifier_operation)
# the Charge buff applies - see charge_buff_multiplier's own doc for why
# its OWN default_magnitude/default_duration_turns are overwritten at
# application time rather than read directly. Same "EnemyData references
# the actual tuned resource" shape debris_spawn_enemy above already uses.
# null (every enemy except a Charge-boss) means nothing to apply -
# battle.gd's own charge-check guards on charge_window_turns > 0 already,
# so this is never read for an enemy that doesn't also set that.
#
# boss_01_charge_buff.tres's own badge_diameter_override_px (2026-08-29,
# post-charge badge pass) was raised to MATCH charge_indicator_status's
# own 36px override below - the buff badge is a real ActiveStatus (see
# battle.gd's own application site), so it goes through StatusBadgeRow
# unmodified and just picks up the shared StatusEffectData.badge_
# diameter_override_px mechanism directly, no new code needed. Its
# tooltip_text ("Trashing wildly.") is PLACEHOLDER WORLD-VOICE TEXT ONLY,
# same "not settled" caveat charge_indicator_status's own tooltip carries
# below - both share this section's own open naming/fiction/art status.

@export var charge_indicator_status: StatusEffectData = null
# The icon/color a Charge-boss's window shows in its own StatusBadgeRow
# WHILE charging (2026-08-29, charge-display pass) - see boss_01_
# charging_indicator.tres: category left at its own INFORMATIONAL default
# (status_effect_data.gd), no modifier_target/modifier_operation set,
# since this never becomes a real ActiveStatus on the combatant - see
# battle.gd's Enemy.set_charge_badge()/clear_charge_badge() (called from
# _advance_boss_charge()), which synthesize a display-only ActiveStatus
# wrapping THIS resource purely for StatusBadge to read (icon_color +
# magnitude, same as charge_buff_status's own real badge already shows)
# and never write it into EnemyCombatant.statuses itself - status-
# modifier/tick logic, and anything else that iterates statuses for
# gameplay purposes, never sees it. Distinct resource from charge_buff_
# status above (a different color) deliberately - the two badges can be
# on screen in different fights of the same run and shouldn't read as the
# same thing: this one means "still vulnerable, still building," the
# buff means "the check already happened and failed." null (every enemy
# except a Charge-boss) means no badge ever shows - set_charge_badge()
# no-ops safely if called with null (never happens for a real Charge-boss
# today, but avoids depending on that).
#
# boss_01_charging_indicator.tres's own icon_color was retuned 2026-08-29
# (charge-badge legibility pass) from an earlier blue to a warm rust/iron
# tone - blue read as DEFENSIVE alongside the player's own Guard cards,
# wrong register for what is a THREAT readout. Its badge_diameter_
# override_px (~2x StatusBadge's own default - see that field's own doc
# on status_effect_data.gd) needs status_badge_row_height_override_px
# below to have room to render without overflowing into the HP number
# above it. Its tooltip_text ("Attempting to free itself from its
# chains.") is PLACEHOLDER WORLD-VOICE TEXT ONLY - final wording for
# Leviathan is not settled (naming/fiction/art are still entirely open,
# same as the rest of this Charge section's own doc already notes).

@export var status_badge_row_height_override_px: float = 0.0
# Per-creature override for vitals_bar.gd's own status_badge_row_height_
# px (2026-08-29, charge-badge legibility pass) - 0.0 (every enemy except
# a Charge-boss) means no override, same "zero means unaffected" shape
# every other *_override_px field on this resource already uses. Exists
# because charge_indicator_status's own badge (see that field's own doc)
# is authored roughly 2x the standard badge diameter (StatusEffectData.
# badge_diameter_override_px), and StatusBadgeRow's shared default height
# (18px, tuned for the standard badge) is too short to hold it without
# visually overflowing into the HP number above it. Tuned as tight as
# safely possible above the badge's own diameter (2026-08-29, spacing
# pass - boss_01.tres's own value dropped from an initial 40 to 38, a
# 2px margin rather than 4, after the wider reservation visibly read as
# the badge floating detached from the rest of the vitals stack) rather
# than left generous - too MUCH slack here is exactly the failure mode
# this field's own existence is meant to avoid, just in the opposite
# direction from clipping. A STATIC per-boss reservation, not something
# that grows/shrinks as the charge window opens and closes - see enemy.
# gd's set_enemy_data() (the one read site) and VitalsBar.override_
# status_badge_row_height()'s own doc for why reflowing this live would
# only trade a moment of layout jank for no real benefit, since nothing
# else is positioned off this row's exact
# bottom edge for an enemy.

# --- Encounter-linked damage (DECIDED - see DESIGN.md's Bestiary:
# GUN/SUPPLY, the Sunken Works' first two-entity encounter) ---
#
# Lets one enemy's own ATTACK damage depend on ANOTHER enemy's CURRENT
# hp, re-evaluated fresh at both display and resolution time - see
# battle.gd's _encounter_linked_damage() (the _escalated_intent_value()-
# shaped function this exists for: one function, two callers, so the
# number shown is always exactly what lands). Same "own dedicated state,
# zero/null/empty means completely unaffected" shape every other per-
# enemy mechanic on this resource already uses (Charge, escalation,
# escape, growth track, pain turn) - GUN is the only enemy that sets any
# of these fields today.
@export var damage_source_enemy: EnemyData = null
# The OTHER enemy this one's damage is linked to (SUPPLY, for GUN).
# battle.gd looks this exact Resource up among the fight's own live
# EnemyCombatants by reference equality (combatant.data == this) - see
# _find_combatant_by_data()'s own doc for why it searches the full
# `enemies` array, not just the living ones (SUPPLY's hp/is_defeated
# still need to be readable after it dies). null (every enemy except
# GUN) means this whole mechanic is off.

@export var damage_step_thresholds: Array[float] = []
# damage_source_enemy's remaining hp FRACTION (0.0-1.0, not a raw hp
# number - stays correct regardless of damage_source_enemy's own max_hp)
# at which this enemy's damage steps DOWN to the next entry in damage_
# step_values. N-1 thresholds for N brackets, authored in descending
# order (the highest fraction first) - GUN's own values: [0.5, 0.333].
# Empty (every enemy except GUN) means no stepping at all.

@export var damage_step_values: Array[int] = []
# The N damage values themselves, one per bracket, read in the SAME
# order as damage_step_thresholds: index 0 applies while damage_source_
# enemy's hp fraction is above thresholds[0], index 1 applies between
# thresholds[0] and thresholds[1], and so on down to the last entry
# (below the last threshold, but damage_source_enemy still alive - NOT
# the same thing as damage_source_dead_value below, which only applies
# once it's actually defeated). Must have exactly one more entry than
# damage_step_thresholds - battle.gd's own read site assumes this and
# doesn't separately validate it. GUN's own values: [12, 6, 4].

@export var damage_source_dead_value: int = 0
# What this enemy's ATTACK deals once damage_source_enemy is fully
# defeated - a SEPARATE value from damage_step_values' own last entry,
# not required to sit above or below it in general, but for GUN
# specifically it's DELIBERATELY BELOW the lowest step (3, vs. damage_
# step_values' own last entry of 4) - see this encounter's own design
# report for why the reverse ordering is a real bug, not a style choice:
# if finishing damage_source_enemy off ever left this enemy HARDER
# hitting than leaving it barely alive, "stop at 1 hp" becomes optimal
# play, which is exactly backwards from the intent (committing to the
# kill should always pay off once started). 0 (every enemy except GUN)
# is a genuine no-op only because damage_source_enemy is also null for
# everyone else - battle.gd never reads this field unless that one is
# set.

@export var damage_source_alive_sfx: String = ""
# Overrides this enemy's own landed-hit sound while damage_source_enemy
# is still alive - same "empty means fall through to the shared default"
# convention attack_impact_sfx above already uses, read by battle.gd's
# _encounter_linked_impact_sfx() (the ONE place either of these two SFX
# fields is ever consulted) right alongside that existing override, not
# a second parallel sound system. GUN's own value points at its "with
# Supply" attack cue - distinct from damage_source_dead_sfx below because
# the two states are meant to be audibly different, not just visually
# different via the damage number.

@export var damage_source_dead_sfx: String = ""
# The companion to damage_source_alive_sfx above, for once damage_
# source_enemy is fully defeated (the same moment damage_source_dead_
# value's own fallback damage kicks in). Empty (every enemy except GUN)
# falls through to the shared default the same way.

@export var damage_source_dead_flavor: String = ""
# The flavor-line counterpart to damage_source_dead_sfx above - overrides
# _encounter_link_descriptor()'s own default "Damage scales with X's HP"
# line (which stops being true the instant damage_source_enemy dies -
# see _encounter_linked_damage() above's own damage_source_dead_value
# fallback) with a line describing THIS state instead, once damage_
# source_enemy is confirmed defeated (see battle.gd's _is_damage_source_
# defeated()). Empty (every enemy except GUN) means nothing shows once
# damage_source_enemy dies, same "empty means nothing to show" fallback
# _encounter_link_descriptor() already uses for the no-link case -
# deliberately NOT falling back to the alive-state line, which would be
# actively wrong once the source is dead. GUN's own value: "Running in
# low-power mode."

# --- Mark attack (DECIDED - Leviathan, 2026-08-29) ---
#
# A third baseline option alongside the boss's two plain ATTACK intents -
# see battle.gd's _pick_baseline_attack_index() (now also picking among
# MARK-type entries) and _resolve_mark_attack() for the actual state
# machine. Marks one specific CardData instance in the player's discard
# pile (or draw pile, if discard is empty) with extra energy cost until
# it's played - see CardData.marked_cost_modifier's own doc for the field
# this writes to, and why per-copy card identity (DESIGN.md's own
# section, landed 2026-08-29) is what makes targeting one COPY rather
# than a whole card TYPE safe to build at all.
@export var mark_cost_increase: int = 0
# How much extra energy a marked card costs until played - read directly
# by _resolve_mark_attack() rather than hardcoding "+1" in battle.gd,
# same "one exported number, not a magic literal in code" reasoning
# charge_attack_value already established for Leviathan's charge-window
# damage. 0 (every enemy except a boss with a mark attack) means nothing
# to apply - no enemy without a MARK-type intent in its own `intents`
# array ever reaches this field at all, so 0 is never actually read for
# anyone else, same "zero means unaffected" idiom every other opt-in
# field on this resource already uses.
