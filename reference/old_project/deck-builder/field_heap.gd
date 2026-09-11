extends Area2D
# The wreckage heap's own interactable (2026-08-28, wreckage-heap room
# v1) - duplicated out of field_npc.gd's own contact-trigger/world-voice
# offer-label shape rather than edited in place or pulled into a shared
# abstraction (explicit instruction for this pass: reuse that path
# directly, don't refactor it into a shared abstraction in this commit) -
# same "duplicate a proven shape for a second, structurally different
# use" precedent weapon_pickup_window.gd's own header already establishes
# for reward_screen.tscn's inline overlay.
#
# Sifting is an explicit two-option CHOICE (2026-08-28, choice-not-
# contact pass), not a contact trigger and not a click on the pile
# itself - contact only ever shows the prompt, never charges anything.
# This is where field_npc.gd's own single-Label offer pattern actually
# resisted reuse: her OfferLabel is plain decorative text, with EVERY
# click routed through the Area2D's own collision shape (one click = one
# resolved interaction, via field_room.gd's dedicated click handler) -
# there was no per-option click detection to reuse for a real two-choice
# menu. Sift/Leave are real Buttons instead (flat, styled to match her
# same world-voice Spectral/OverlayStyle look), each handling its own
# `pressed` signal directly - the same technique weapon_pickup_window.gd
# already uses for Take it/Leave it, just world-voice text instead of a
# system-voice modal. Clicking the PILE's own silhouette now only ever
# means "walk toward it" (see field_room.gd's own _on_heap_clicked()) -
# it no longer resolves anything by itself once the player is in contact.
# Instanced by field_room.gd's _spawn_heap().

signal pulled(outcome: SiftOutcomeData, hp_paid: int)
# Reports what got pulled and what it actually cost - by the time this
# fires, the sifting cost, the draw-tracking, the escalating cost, AND the
# drawn entry's own SiftOutcomeResolver.resolve() have all already
# finished (see _on_sift_pressed()'s own await ordering), so anything
# downstream sees the fully-settled RunState. Same "just report it, let
# something else react" split field_chest.gd's own weapon_offered already
# follows. field_room.gd USED TO be this signal's only listener, refreshing
# its own HUD's HP bar (VitalsBar was push-fed, not self-updating) - that
# listener is GONE (2026-09-05, HP-signal pass: RunState.player_hp_changed
# reaches every player-owned VitalsBar directly now, with no need for this
# signal's help). Left in place, unconnected, rather than removed - the
# outcome/cost report itself is still real information a future listener
# could want, independent of the now-obsolete HP-bar reason it was
# originally added for.

signal _grant_offer_settled(accepted: bool)
# Private to this script (2026-09-04, weighted-grant pass) - the "race"
# primitive _play_grant_card_reveal() below awaits: whichever of the
# card's own click or a walk-away decline (see _on_body_exited()) fires
# first emits this exactly once, with which one it was. GDScript has no
# built-in "await whichever of two signals fires first," so this is the
# shared completion point both paths funnel into instead - the same
# "two triggers, one shared resolution point" shape EnemyCombatant.
# intent_interrupted_pending already uses for two unrelated triggers
# (the Wardling's pain turn, a chain-payoff stun) converging on one flag.

@export var sift_outcome_table: SiftOutcomeTable = null

var deck_button: TextureButton = null
var deck_label: Label = null
# Set by field_room.gd's own _spawn_heap() right after instantiate() -
# same "plain var, wired externally by whoever owns the real UI node"
# shape shop_window.gd's own deck_viewer/player_hp_bar already use
# (2026-09-04, weighted-grant pass). deck_button is read by _play_grant_
# card_reveal() below only for the accept fly-animation's own target
# position (the icon's own screen rect, unchanged by the 2026-09-05 Deck/
# Map icon pass - deck_button used to BE the text button carrying its own
# label, now it's the icon TextureButton sitting beside a separate
# DeckLabel); deck_label is what actually gets the deck-count text.
# Both null-safe by construction (every real room load wires them;
# nothing here would crash without them, since a heap with an empty
# sift_outcome_table would never reach GRANT_CARD anyway).

const CARD_SCENE := preload("res://card.tscn")
# Reused for the HP_CHANGE water reveal below - the same self-contained
# Control every other card reveal in this project instances (field_
# forge.gd's upgrade reveal, field_room.gd's chest/Keeper offer cards,
# reward_screen.gd's rare-drop reveal).
const WATER_DISPLAY_CARD: CardData = preload("res://resources/wreckage_heap/water_display_card.tres")
# A display-only CardData resource (2026-09-03, water-reveal pass) - NOT
# a real card: its own description field is a placeholder ("Restore N
# HP") that _play_water_reveal() below overwrites on a DUPLICATE before
# ever handing it to a Card instance, never on this shared preloaded
# resource itself (mutating THIS instance in place would leak the last-
# shown HP value into every future draw, since Godot caches one shared
# Resource object per resource path). Lives in resources/wreckage_heap/,
# a directory NO existing pool-scan or dev tool ever reads - battle.gd's
# dev Add Card button only scans res://resources/cards/ and its class
# subfolders (see its own DEV_ADD_CARD_DIRS-equivalent array), and card_
# pool.gd's CardPool.load_class_pool() (the shop/reward roll's own
# source) only ever reads CharacterData.card_pool_folder, also under
# resources/cards/classes/. This resource is never referenced from any
# SiftOutcomeData.card field, any NPCData.granted_cards, or RunState.deck
# either - the only way it's ever instantiated is _play_water_reveal()
# below, and nothing anywhere calls RunState.add_card_to_deck() with it.

# PER_INSTANCE: this heap draws against its own Array[int] (_instance_
# sift_outcomes_drawn below), reset the same way as every other per-visit
# field this file already has (_current_cost, _exhausted) - simply by
# being a plain instance var on a scene rebuilt fresh every room load, no
# explicit reset code needed. PER_RUN: unchanged existing behaviour,
# drawing against RunState.sift_outcomes_drawn, shared by every heap
# instance the run generates. See _drawn_list() below for the one place
# this is read.
#
# Added (2026-09-01, pool-scoping pass) because this event now appears at
# MOST ONCE per run (docs/REGION_01_v1.md §8's own "no room that reads as
# arranged/prepared" framing rules out a repeatable wreckage-scavenging
# loop scattered across the map the way this was originally built for) -
# sharing a drawn-set across instances has nothing left to accomplish for
# a thing there's only ever one of, and worse, it actively prevented a
# BOUNDED per-heap dig count: this heap's own pool is now sized so every
# dig up to its own stage count is guaranteed to succeed (5 entries as of
# the 2026-09-01 pool-restoration pass, AT LEAST stage_textures.size() by
# construction - see _ready()'s own assert), which only means anything if
# draws against it aren't also being silently consumed by some other heap
# nobody's visited yet. A pool LARGER than the stage count (today's case)
# just means digs past the mound's own last stage keep succeeding without
# the visual advancing any further - see _set_mound_stage()'s own clamp.
# PER_RUN itself is UNCHANGED
# and kept working end to end (RunState.sift_outcomes_drawn's own
# mechanism is untouched) - a future repeatable/multi-instance event is
# exactly what it's kept for.
enum SiftPoolScope { PER_INSTANCE, PER_RUN }
@export var sift_pool_scope: SiftPoolScope = SiftPoolScope.PER_INSTANCE

var _instance_sift_outcomes_drawn: Array[int] = []
# This heap's own draw-without-replacement set when sift_pool_scope is
# PER_INSTANCE - same "generated once, thrown away with the rest of this
# room" per-visit lifetime as _current_cost/_exhausted below, not staged
# anywhere longer-lived, since (unlike RunState.sift_outcomes_drawn) it
# has no reason to survive past this one heap's own visit.

func _drawn_list() -> Array[int]:
	if sift_pool_scope == SiftPoolScope.PER_RUN:
		return RunState.sift_outcomes_drawn
	return _instance_sift_outcomes_drawn

@export_group("Sifting Cost")
@export var sifting_start_cost: int = 5
@export var sifting_cost_step: int = 3
# Flat, escalating per PULL, reset every fresh visit - _current_cost below
# is plain instance state, and a heap is rebuilt fresh every time its room
# loads (same "per-instance state IS per-visit state" reasoning field_
# chest.gd's own `opened` already relies on). Never carried across visits,
# unlike RunState.sift_outcomes_drawn's own run-scoped draw-without-
# replacement set. Preserved across repeated Leave/re-approach cycles
# WITHIN one visit (2026-08-28, choice-not-contact pass) - Leave only
# fades the prompt (see _on_leave_pressed()), it never resets _current_
# cost, so walking off and back mid-visit resumes at whatever the
# escalation had already reached, per this pass's own brief.

@export_group("Approach")
@export var trigger_width_multiplier: float = 1.1
@export var approach_stop_multiplier: float = 0.55
# Both DERIVED from heap_trigger_width_px below (2026-08-28, large-pile
# pass; renamed 2026-09-01, staged-dune pass - see that export's own doc
# for why "heap_width_px" stopped being an accurate name), not independent
# flat pixel values any more - a flat default would have silently stopped
# making sense the moment the reference width changed without a matching
# by-hand retune. A multiplier guarantees "the contact zone scales with
# the pile" stays true regardless of how heap_trigger_width_px is ever
# tuned, not just true today. trigger_width_multiplier > 1.0 means the
# contact zone still extends a little past the visual silhouette
# (matching field_npc.gd's own "widen past the visual edge" reasoning),
# just a MUCH smaller margin than her own ratio would produce blown up to
# this pile's scale (see this pass's own report on why - a 400/220-style
# ratio applied to a 1320px pile would eat most of the room's own
# walkable width). approach_stop_multiplier is smaller (roughly the
# pile's own half-width) since a click-to-approach should stop AT the
# visual edge, not well past it.
var trigger_width_px: float
var approach_stop_distance_px: float

@export_group("Mound")
@export var stage_textures: Array[Texture2D] = []
# assets/regions/beach/Dunes/heap_stage_0.png..heap_stage_3.png (2026-09-01,
# staged-dune pass - REPLACES the flat hand-drawn Polygon2D trapezoid this
# file used to build in _build_geometry()) - four stages, native sizes
# 530x228 / 496x193 / 496x130 / 551x90, pure white on transparent, base-
# anchored, assigned in the scene rather than hardcoded as preloads here
# (same pattern field_room.gd's landform/foreground texture arrays already
# use). Index i is stage i - _set_mound_stage() below indexes straight
# into this array, clamped to its own bounds. Region 1 must not read as
# ruins or damage (docs/REGION_01_v1.md §8) - this is a sand pile the
# player digs into, re-fictioned from wreckage; nothing here represents
# destruction.
@export var buried_object_texture: Texture2D = null
# assets/regions/beach/Dunes/buried_object_a.png (386x212, pure white on
# transparent, base-anchored) - an angular slab, drawn ONCE at _build_
# geometry() time and never swapped (unlike stage_textures above); what
# changes per stage is how much of it the shrinking mound silhouette
# leaves exposed, by the art's own design - no code-side masking/reveal
# animation. See _build_geometry()'s own doc for the draw-order mechanics
# that put it behind the mound.
@export var heap_color: Color = Color(0.42, 0.38, 0.33, 1)
# UNCHANGED value (2026-09-01, staged-dune pass) - previously the flat
# Polygon2D.color of the old trapezoid, now the base color fed into
# silhouette_vertical_shade.gdshader via _apply_mound_shade() below (see
# that function's own doc). Kept deliberately darker than ground_color_
# wet/_dry (field_room.gd's own region-gradient ground tint, luminance
# ~0.70-0.77) so the heap still reads as an interactable silhouette
# against the ground, not as background landform - landform_mid_textures
# now occupies similar mid-layer silhouettes since the 2026-08-30 landform
# pass, which is exactly the read this color has to stay distinct from.
@export var buried_object_color: Color = Color(0.35, 0.36, 0.40, 1)
# Deliberately a COOL blue-grey, not a warmer/browner shade of heap_color
# above - "tinted separately from the sand so it reads as not being sand"
# (this pass's own brief). No warm accent (docs/REGION_01_v1.md §8), so
# the separation is carried by hue/temperature (a mineral tone) rather
# than by a warm contrast this region is specifically not allowed to use.
@export var buried_object_scale: float = 1.0
# 2026-09-01, tuning-node pass - SPLIT OUT from mound_scale below, which
# used to size the buried object too (both sprites shared one uniform
# multiplier). An easy, independent size knob for the buried object alone
# - see _build_geometry() below, the only place this is read (the buried
# object is sized/positioned once and never touched again, unlike the
# mound, which _set_mound_stage() repositions every dig).
@export_range(0.0, 0.5, 0.01) var mound_vertical_shade: float = 0.08
# Same shade amount and meaning as field_room.gd's landform_vertical_
# shade (a lit crest, a shadowed base - see silhouette_vertical_shade.
# gdshader's own comment) - matched to that default since the mound is a
# similarly-scaled silhouette, not independently tuned.
@export var mound_scale: float = 1.0
# Uniform multiplier on every stage sprite's OWN native pixel size
# (2026-09-01, staged-dune pass) - REPLACES heap_width_px/heap_height_px
# forcing the old procedural trapezoid to an exact target size. The four
# stage assets vary in BOTH width and height by design (530x228 down to
# 551x90 - a crater widening as it shallows, not a uniform shrink), so
# normalizing each one to a shared target width would fight the artist's
# own silhouette changes instead of showing them. Left at 1.0 (native
# pixel size, no scaling) - no scale value was supplied for this pass;
# retune this one number once a real target size is known, rather than
# the per-stage math this replaces. No longer sizes the buried object too
# (2026-09-01, tuning-node pass) - see buried_object_scale above, split
# out for an independent size knob.
@export var mound_offset: Vector2 = Vector2.ZERO
# 2026-09-01, tuning-node pass - an easy X/Y nudge for the mound sprite's
# own rendered position, added on top of its usual base-anchor placement
# (see _set_mound_stage() below, the only place this is read). Deliberately
# NOT a change to this node's own `position` - that's the heap's Area2D
# origin, which the collision trigger, the approach-stop distance, and
# RoomState's own placement all key off (see heap_trigger_width_px's own
# doc); nudging the SPRITE instead leaves every one of those exactly where
# gameplay already expects them, so this is purely a visual fudge factor,
# never a gameplay one. Does not affect the buried object, which has no
# offset of its own - only the mound's own X/Y was asked for.
@export var heap_trigger_width_px: float = 551.0
# RENAMED from heap_width_px (2026-09-01, staged-dune pass) - REPLACES its
# role as the reference width trigger_width_px/approach_stop_distance_px
# and field_room.gd's own wall-clearance clamp (_spawn_heap()) scale
# against. Can no longer be "the mound's width" in the old singular sense
# now that width varies by stage (496-551px, and NOT monotonically - stage
# 3's 551px crater is wider than stage 0's own 530px pile, see stage_
# textures' own doc) - defaults to 551.0, the WIDEST of the four stages
# measured directly off the assets, not the first one.
#
# Sized against the widest stage on purpose, not held fixed at stage 0's
# own width: a trigger sized to a narrower stage would leave part of an
# EARLIER, wider stage's own visible silhouette outside the interactive
# zone; sized to the widest stage instead, every stage's own silhouette
# sits safely within it, at the cost of a slightly generous margin on the
# narrower stages rather than a broken one on the wide stage. A plain
# @export, not computed from stage_textures' own real sizes at _ready()
# time (the more robust-looking option) - field_room.gd's own _spawn_
# heap() reads this value directly off the instance immediately after
# instantiate(), BEFORE _ready() ever runs (see its own doc for why:
# avoiding a reorder of its "configure fully, then add_child()"
# convention for one clamp) - a value only known once _ready() runs would
# arrive too late for that read. Keep this in sync by hand if a future
# stage asset ends up wider than 551px, same "hand-maintained, expect to
# retune when assets change" contract every other native-pixel-derived
# number in this project's asset-facing exports already carries (see
# field_room.gd's vegetation_scale_min/_max for the same shape).
#
# heap_height_px is GONE, not renamed - it drove only the old _build_
# geometry()'s trapezoid math (see Phase 1's own report), which no longer
# exists; each stage sprite now uses its own texture's real native height
# directly (see _set_mound_stage() below), so there is no longer a single
# height for one flat export to describe.
#
# Walkability - RE-CHECKED against this new value, not just carried over:
# trigger_width_px = 551 * 1.1 = 606.1px (up from 496 * 1.1 = 545.6px, an
# ~11% widening - unavoidable once the reference width has to cover the
# actual widest stage rather than an arbitrary flat number), still well
# inside RoomState.standard_room_width's own 2720px walkable span and the
# ~1296px placement zone room_type.gd's own HEAP doc describes.
# field_room.gd's own heap_min_wall_clearance_px clamp (still 150px,
# untouched) absorbs the rest exactly as it already did before this pass.
#
# There is no PHYSICAL blocking either way, independent of the above -
# Area2D (this node's own base type) has no collision response, only
# overlap detection, so the player was never at risk of being unable to
# walk THROUGH the pile's own collision shape even before any of this was
# checked; the real question was always the CONTACT/TRIGGER zone eating
# too much of the room to comfortably walk around, not a hard block.

const OFFER_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# Same world-voice serif field_npc.gd's own OFFER_FONT uses - what the
# heap "says" (the cost of the next pull, what you just found) is world
# content, not a system-voice HUD readout. Applied to the Sift/Leave
# Buttons below too, not just ResultLabel - the choice itself is world-
# voice, same register as the prompt it replaces.

@export_group("Offer Prompt")
@export var prompt_width_px: float = 420.0
@export var prompt_head_clearance_px: float = 400.0
# RAISED from 260 back to 400 (2026-08-29, vertical-clearance pass -
# consistency companion to field_chest.gd's own identical fix) - 260 was
# a deliberate later retune (prompt-hierarchy pass), not a regression,
# but nobody re-checked it against how tall the player's rendered figure
# actually is before shipping it. See field_chest.gd's own prompt_head_
# clearance_px doc for the real measurement this now uses: scanned the
# alpha channel of every frame BOTH player animations actually use (35
# frames total) for the topmost non-transparent pixel, found it at row 30
# of the 256px atlas cell (not row 0, the old assumption), converted
# through the same offset/scale chain to a real measured top of ~296px
# above the player's own origin - LOWER than the old "-350" assumption,
# not higher, so this was never about the sprite being taller than
# documented. 400 clears that measured ~296px top by a real ~104px
# margin. This prompt follows the PLAYER directly (see below), so this
# same measurement applies here even more directly than on the chest,
# which only shares the player's Y when standing on it.
#
# The prompt now FOLLOWS THE PLAYER (2026-08-28, prompt-follows-player
# pass), not the pile - see _process() below. REPLACES the old prompt_
# vertical_gap_px (positioned a fixed offset above the mound's own PEAK,
# i.e. heap_height_px) - that read as pinned near the top of the screen
# once the pile was tall, and more fundamentally never actually followed
# the player at all: the heap's own trigger zone is wide enough (see
# trigger_width_multiplier's own doc) that the player can be in contact
# while standing well to either side of the pile's own center, where a
# pile-relative prompt simply wasn't above them.
#
# Same fixed-offset-above-the-body TECHNIQUE field_chest.gd's own gold
# number already uses (see its own doc: Player's visual sprite's own top
# edge sits at local y=-350, derived from Player/Visual's baked scale/
# offset chain) - 400 clears that with a small margin rather than sitting
# flush with the very top of the head. field_npc.gd's own OfferLabel
# does NOT do this (see this pass's own report) - hers is a flat offset
# from HER OWN Area2D origin, exactly like this heap's prompt used to be,
# never updated per-frame. That's a shared latent gap, not something
# unique to the heap - it just never shows up for her because she's
# person-sized with a narrow, roughly-person-width trigger zone, so
# "fixed above her" and "above whichever player is in contact" are
# nearly always the same point. Not touched here since it wasn't part of
# this pass's own ask.
@export var offer_font_size: int = 24
# The world-voice line's own size (2026-08-29, prompt-hierarchy pass) -
# RAISED from 20, the shared value this used to hand to BOTH ResultLabel
# and the Sift/Leave buttons (same bug field_chest.gd's own identical
# pass fixes - see that file's own doc). Label-only now - see offer_
# button_font_size below for the buttons' own, deliberately smaller, size.
# No local offer_color export any more (2026-08-30, world-voice color
# fix) - reads HudPalette.WORLD_TEXT directly at the point of use (see
# _style_prompt_text() below), one shared world-voice color instead of
# an independent copy per field prompt.
@export var offer_button_font_size: int = 20
# Sift/Leave's own size - split out from offer_font_size above so the
# buttons can be smaller than the world-voice line rather than tied to
# its size (2026-08-29, prompt-hierarchy pass). RAISED 16 -> 20
# (2026-08-31, prompt-readability pass) - 16 read as too small to
# comfortably click/read live, the same complaint field_chest.gd's own
# prompt_button_font_size and field_curio.gd's own offer_button_font_size
# got at the same time (all three share this exact value by design - see
# each file's own doc). 20 stays visibly smaller than offer_font_size's
# 24 (preserving the prompt-hierarchy pass's own reasoning: a Button's
# hover feedback and hit padding already give it more visual weight than
# plain Label text at the same size, so equal sizes would make the
# mechanical choice outread the world-voice line it's responding to), but
# is a real, legible step up from 16. Mechanical UI, still subordinate to
# the line it's responding to - see _style_button()'s own doc for the
# color half of that same subordination (untouched by this pass).
@export var offer_fade_in_sec: float = 0.2
@export var offer_fade_out_sec: float = 1.1
@export var outcome_display_sec: float = 1.6
# How long a drawn outcome's own result text sits (ChoiceRow hidden the
# whole time) before the Sift/Leave choice reappears - same "let the
# player actually read it before moving on" reasoning field_chest.gd's
# own GOLD_NUMBER_DURATION_SEC wait already established this same pass.

@export_group("Water Reveal")
# The HP_CHANGE outcome's own card-shaped presentation (2026-09-03) -
# see _play_water_reveal() below. Fade timing deliberately reuses offer_
# fade_in_sec/offer_fade_out_sec/outcome_display_sec above rather than
# adding new ones - "fades in alongside the existing result text... same
# hold" (this pass's own brief), so it shares the exact same numbers the
# text it's appearing next to already uses, not independently tuned
# ones that could drift out of sync with it.
@export var water_display_card_scale: float = 0.55
# RETUNED (2026-09-04) to match field_room.gd's own npc_offer_card_scale
# exactly - this card is a click-to-accept OFFER now (the 2026-09-03
# water-drink pass made it interactive, chest/Keeper-shaped, not a
# passive celebratory reveal), so it should read at the same size as
# every other offered card, not at RARE_DROP_CARD_SCALE/upgrade_reveal_
# scale's own "big, static reveal" size this used to match. Applied to a
# WRAPPER around the card now, not to set_scale_factor() directly (see
# _play_water_reveal()'s own note) - the same "render at 1.0, scale a
# wrapper outside" pattern card.gd's own set_scale_factor() doc points
# at, and npc_offer_card_scale itself already uses.

@export_group("Grant Card Reveal")
# GRANT_CARD's own card-shaped presentation (2026-09-04, weighted-grant
# pass) - see _play_grant_card_reveal() below. A dedicated export group,
# not folded into Water Reveal above despite sharing the same overall
# shape (centered CanvasLayer offer, click to accept) - the two are
# independently tunable on purpose, the same "start identical, stay
# separately retunable" reasoning card.gd's own removal_scope_font_
# size_px/chain_role_font_size_px already establish for a pair of knobs
# that also happen to start at matching values.
@export var grant_card_scale: float = 0.55
# Matches water_display_card_scale/field_room.gd's own npc_offer_card_
# scale - the project's established "offered card" size, not the old
# big-reveal one either of those two moved away from.
@export var grant_card_accept_duration_sec: float = 0.5
# Matches field_room.gd's own npc_offer_card_accept_duration_sec - the
# fly-to-deck animation's own duration on accept. Declining reuses
# offer_fade_out_sec instead (see _play_grant_card_reveal()'s own doc) -
# a decline is a plain fade, not a flight, so it doesn't need this one.
@export var reveal_position_y_fraction: float = 0.65
# REPLACES grant_card_offer_gap_px (2026-09-05, fixed-reveal-position
# pass) - that field measured a gap below ResultLabel's own live rect,
# which chased a moving target: ResultLabel follows the PLAYER (see
# _process()'s own doc), and the player's own screen position ranges
# across nearly the ENTIRE viewport width (confirmed by tracing Camera2D's
# own anchor_fraction/limit_left/limit_right math - the player can reach
# screen-X anywhere from ~40 to ~1880 on a 1920-wide viewport, not just
# "left of center"), so no fixed X or Y derived from the player's current
# position could ever be reliably clear of it. This field instead fixes
# BOTH reveals' own Y as a FRACTION of viewport height, independent of
# the player entirely - see _play_water_reveal()/_play_grant_card_reveal()
# below, both of which compute the same Vector2 expression independently
# (no shared helper - project convention).
#
# 0.65 was chosen against the one axis that actually IS stable regardless
# of player position: OfferPrompt's own top edge sits at a FIXED screen-Y
# of floor_line_y (830) - prompt_head_clearance_px (400) = 430 always
# (RoomState.floor_line_y is the player's fixed world-Y, and the field
# camera's own vertical clamp - limit_top=0/limit_bottom=1080, exactly one
# viewport-height apart - pins its vertical center permanently, at zoom
# 1.0, so screen-Y equals world-Y 1:1 with zero drift). Both reveals only
# ever show while ChoiceRow is hidden (see field_heap.gd's own choice_row.
# visible = false, set before either reveal runs), so the only thing to
# clear during a reveal is ResultLabel's own height at that moment - a
# generous estimate (up to ~3 wrapped lines at offer_font_size, ~130px)
# puts its worst-case bottom edge at ~560. At 0.65 * 1080 = 702 (viewport
# height 1080, see project.godot's window/size/viewport_height), a card
# scaled to half-height ~95px (345 * 0.55 / 2) has its own top edge at
# ~607 - a ~47px margin below that 560 estimate. Retune this fraction
# directly if a future, longer outcome line ever wraps further than
# assumed here.

@export_group("Gold Number")
# GOLD's own floating "+N" (2026-09-04, gold-range pass) - required now
# that the amount varies (30-60, see sift_outcomes.tres' own GOLD entry),
# where the fixed 15 before this pass had no such readout. Same
# structural trick (a plain Label, parented onto the player so it rises
# from wherever the player actually is, tweened up and faded) field_
# chest.gd's own _spawn_gold_number() already establishes for its chest-
# gold reward - reused here in shape only, NOT in color/font: that one is
# GOLD_NUMBER_COLOR (an amber matching gold_display.gd's own coin), read
# as a celebratory reward number. This one is deliberately muted system-
# voice instead (HudPalette.SYSTEM_TEXT, no font override - project
# default sans, not OFFER_FONT's world-voice Spectral) - a mechanical
# readout confirming what the HUD counter is about to tick to, not a
# second flourish competing with the pile's own world-voice ResultLabel
# line sitting right above it.
@export var gold_number_font_size: int = 32
# Matches field_chest.gd's own GOLD_NUMBER_COLOR font size exactly - same
# on-screen scale for "a number just granted," even though the color
# register differs.
@export var gold_number_rise_px: float = 60.0
@export var gold_number_duration_sec: float = 0.9
# Both match field_chest.gd's own GOLD_NUMBER_RISE_PX/DURATION_SEC - well
# under outcome_display_sec's own 1.6s hold above, so the number always
# finishes rising and fading before _show_prompt() below brings the
# choice row back.

@export_group("Shard Collection")
# The buried object's own payoff (2026-09-04, dug-shard pass) - the FIRST
# real shard pickup in the game (RunState.add_shards()'s own doc: "no
# world shard pickup exists yet" - see that field's own note; only a
# dev-only test button called it before this). No existing placed-shard
# grammar exists to match, so this establishes its own, closest to this
# project's dominant "click to interact" convention: click the shard
# sprite once fully revealed (_build_geometry()'s own _shard_area, an
# Area2D sized to buried_object_texture, using the SAME Area2D.input_
# event click-detection field_room.gd's own heap-pile/curio/NPC clicks
# already use - see _on_shard_clicked() below), a floating "+1" in the
# SAME muted system-voice register Gold Number above uses (this is a
# system readout of a resource just granted, not a world-voice moment),
# and a "shard_collected" AudioManager cue - registered as an empty-
# string placeholder for now (silent, no file yet - see that key's own
# doc in audio_manager.gd), the same "wire ahead of the art" convention
# every other placeholder SFX in that dictionary already follows.
@export var shard_number_font_size: int = 32
@export var shard_number_rise_px: float = 60.0
@export var shard_number_duration_sec: float = 0.9
# Same starting values as Gold Number's own three knobs above - NOT
# shared code (duplicated on purpose, this file's own "duplicate a
# proven shape" convention - see the file's header), just the same
# tuning for the same kind of moment (a muted system-voice "+N" for a
# resource just granted).

@export var shadow_y_offset: float = 0.0
# Overrides RoomState.entity_shadow_y_offset's own -18 default (2026-08-30,
# shadow-tuning pass) - this heap's visuals (both the mound and the buried
# object sprites, as of the 2026-09-01 staged-dune pass - see _build_
# geometry() below) are base-anchored with their own base already sitting
# exactly at local y=0, same as the flat Polygon2D trapezoid this replaced
# - no trailing cloth/limb, nothing for VisualBounds to overestimate.
# Confirmed live (pre-staged-dune pass, against the old trapezoid): the
# shadow already lands exactly at this heap's own origin (0px offset) -
# the -18 global default would lift it 18px above its real, already-
# correct base. Re-verify live now that VisualBounds measures TWO sibling
# sprites instead of one shape - see _build_geometry()'s own doc for why
# that's expected to still land correctly, not assumed unchanged.

@onready var visual_root: Node2D = $VisualRoot
@onready var offer_prompt: Control = $PromptCanvas/OfferPrompt
@onready var result_label: Label = $PromptCanvas/OfferPrompt/PromptColumn/ResultLabel
@onready var choice_row: HBoxContainer = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow
@onready var sift_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/SiftButton
@onready var leave_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/LeaveButton
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _pending_grant_card_decline: Callable = Callable()
# Set by _play_grant_card_reveal() below while its own offer is up,
# cleared (and called) by _on_body_exited() the instant the player walks
# out of contact - see that function's own doc. Empty/invalid whenever no
# GRANT_CARD offer is currently showing, same "empty means unaffected"
# idiom every other opt-in field in this project already uses - _on_body_
# exited() checks is_valid() before ever calling it.

var _current_cost: int
var _exhausted: bool = false
var _dig_count: int = 0
# How many SUCCESSFUL digs this heap has resolved this visit - drives
# _set_mound_stage() below (dig count IS the stage index, clamped to
# stage_textures' own bounds - see that function's own doc). Same per-
# visit lifetime as _current_cost/_exhausted just above: a plain instance
# var, reset for free by this being a fresh scene instance every room
# load, never incremented by an exhausted (outcome == null) attempt - see
# _on_sift_pressed() below for where that distinction is actually made.
var _mound_sprite: Sprite2D
var _buried_object_sprite: Sprite2D
var _shard_area: Area2D
# Built in _build_geometry() alongside _buried_object_sprite, only when
# buried_object_texture is set - null on any heap variant that leaves
# that field empty, same "optional, guarded at every read site" shape
# _buried_object_sprite itself already follows. input_pickable starts
# false (not collectable, no interaction - this pass's own brief) and
# flips true the moment _set_mound_stage() below first reaches the last
# stage - see that function's own doc for why toggling one flag there is
# enough, no separate "already revealed" bookkeeping needed.
var _shard_collected: bool = false
# Guards _on_shard_clicked() below against a second click after the
# first already granted the shard - input_pickable is flipped false the
# same moment this is set true (belt-and-suspenders, same double-guard
# shape _play_grant_card_reveal()'s own card.mouse_filter/CONNECT_ONE_
# SHOT pairing already uses elsewhere in this file).
var _offer_tween: Tween
var _player_in_contact: Player = null
# Set on contact, cleared on exit (see _on_body_entered()/_on_body_
# exited()) - drives _process()'s own per-frame follow. Not the same
# thing as field_room.gd's own _heap_in_contact (which only tracks
# whether a CLICK on the pile should walk-to-it or no-op) - this is
# purely "who to follow," kept local since nothing outside this file
# needs it.

func _ready() -> void:
	# PROTECTS THE "every dig up to the last stage always yields something"
	# guarantee (2026-09-01, pool-restoration pass) - that guarantee is
	# just draw-without-replacement's own ordinary behavior (a pool with N
	# entries never returns null before its Nth draw), so it holds
	# automatically for as long as the pool has AT LEAST as many entries
	# as there are stages to reach. It does NOT hold automatically the
	# other way: shrink sift_outcome_table below stage_textures.size()
	# (accidentally, in a future edit) and the pool would exhaust before
	# the mound ever reaches its own last stage - _set_mound_stage()'s own
	# clampi() would silently hide that by just holding at whatever stage
	# was last reached, no crash, no visible sign anything's wrong. This
	# assert is what turns that into a loud failure instead - same
	# "announce a violation immediately" shape RoomState's own entrance-
	# clearance assertion and field_room.gd's background_tile_width assert
	# already use for their own structural preconditions. Only fires when
	# both arrays are actually populated - an artist mid-authoring either
	# one shouldn't get an unrelated crash for the other still being empty.
	if sift_outcome_table != null and not stage_textures.is_empty():
		assert(sift_outcome_table.entries.size() >= stage_textures.size(), "field_heap.gd: sift_outcome_table has fewer entries (%d) than stage_textures (%d) - the pool would exhaust before the mound could ever reach its own last stage." % [sift_outcome_table.entries.size(), stage_textures.size()])
	_current_cost = sifting_start_cost
	trigger_width_px = heap_trigger_width_px * trigger_width_multiplier
	approach_stop_distance_px = heap_trigger_width_px * approach_stop_multiplier
	_build_geometry()
	# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
	# gd's own doc.
	EntityShadow.attach(self, visual_root, shadow_y_offset)
	_configure_offer_prompt()
	# Duplicated before mutating - same "shared .tscn resource, per-
	# instance copy" rule field_npc.gd's own _ready() already follows for
	# its identical shape/size override.
	var shape: RectangleShape2D = collision_shape.shape.duplicate()
	shape.size.x = trigger_width_px
	collision_shape.shape = shape
	_style_prompt_text(result_label)
	_style_button(sift_button)
	_style_button(leave_button)
	offer_prompt.modulate.a = 0.0
	sift_button.pressed.connect(_on_sift_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	set_process(false) # Only ever needs to run while a player is in contact - see _process() below.

# Tracks _player_in_contact every frame while set (see _on_body_entered()/
# _on_body_exited(), the only two writers, and set_process() calls
# alongside them). DRAW-ORDER FIX (2026-08-29, consistency companion to
# field_chest.gd's own identical fix - see its own doc for the full
# investigation): OfferPrompt now lives on its own CanvasLayer
# ($PromptCanvas in field_heap.tscn) instead of the plain Node2D world
# tree - a same-canvas z_index comparison against the player's own
# sprite measured as correct and still lost visually on the chest, so
# this no longer relies on same-canvas z-sort at all. The cost: this
# Control's own position is now raw VIEWPORT PIXELS, not world units, so
# the same world-space anchor this always computed (player position plus
# a fixed offset) has to be projected through the CURRENT camera
# transform before being assigned - still recomputed every frame, same
# as before, just with one extra step. Y stays a fixed clearance above
# wherever the player currently is, not the pile - see prompt_head_
# clearance_px's own doc for why.
func _process(_delta: float) -> void:
	var world_anchor: Vector2 = _player_in_contact.global_position + Vector2(-prompt_width_px / 2.0, -prompt_head_clearance_px)
	offer_prompt.position = get_viewport().canvas_transform * world_anchor

# Two base-anchored Sprite2Ds (2026-09-01, staged-dune pass - REPLACES
# the single flat Polygon2D trapezoid this used to build) - the buried
# object FIRST, the mound SECOND, both children of the same visual_root.
# Godot draws later siblings on top of earlier ones with no z_index
# involved (same plain draw-order mechanic field_room.gd's own Background/
# MidLayer-over-FarLayer split relies on) - adding the buried object
# before the mound is what puts it BEHIND the mound, per this pass's own
# brief, with nothing else needed to enforce that.
#
# The buried object is sized/positioned ONCE here and never touched again
# - see buried_object_texture's own doc for why "progressively revealed
# as the mound shrinks" is the ART's job (each stage's own silhouette),
# not a runtime mask/clip this function or _set_mound_stage() computes.
#
# The mound itself starts with no texture assigned - _set_mound_stage(0)
# at the end here is what actually shows stage 0, through the exact same
# code path every later dig uses, rather than a separate one-off case
# duplicating _set_mound_stage()'s own sizing math.
func _build_geometry() -> void:
	if buried_object_texture != null:
		_buried_object_sprite = Sprite2D.new()
		_buried_object_sprite.texture = buried_object_texture
		_buried_object_sprite.centered = false
		_buried_object_sprite.scale = Vector2(buried_object_scale, buried_object_scale)
		var native_size := buried_object_texture.get_size()
		_buried_object_sprite.position = Vector2(-native_size.x * buried_object_scale / 2.0, -native_size.y * buried_object_scale)
		_apply_mound_shade(_buried_object_sprite, buried_object_color)
		visual_root.add_child(_buried_object_sprite)

		# The shard's own clickable region (2026-09-04, dug-shard pass) -
		# sized/positioned to match _buried_object_sprite exactly, same
		# rect the sprite itself just used. monitoring/monitorable both
		# false - this Area2D only ever needs INPUT picking (a click),
		# never physics body/area overlap detection, so both are turned
		# off rather than left at their Area2D default of true.
		# input_pickable starts false - see _shard_area's own doc above.
		_shard_area = Area2D.new()
		_shard_area.monitoring = false
		_shard_area.monitorable = false
		_shard_area.input_pickable = false
		var shard_shape := CollisionShape2D.new()
		var shard_rect := RectangleShape2D.new()
		shard_rect.size = native_size * buried_object_scale
		shard_shape.shape = shard_rect
		shard_shape.position = _buried_object_sprite.position + (native_size * buried_object_scale) / 2.0
		_shard_area.add_child(shard_shape)
		_shard_area.input_event.connect(_on_shard_clicked)
		visual_root.add_child(_shard_area)

	_mound_sprite = Sprite2D.new()
	_mound_sprite.centered = false
	_mound_sprite.scale = Vector2(mound_scale, mound_scale)
	_apply_mound_shade(_mound_sprite, heap_color)
	visual_root.add_child(_mound_sprite)
	_set_mound_stage(0)

# Shared shader ASSET, not a shared code helper (see field_heap.gd's own
# header, and EntityShadow's own doc for this project's ONE deliberate
# code-sharing exception - _apply_mound_shade() below is an independent,
# duplicated copy of field_room.gd's own _apply_vertical_shade(), reusing
# only the .gdshader FILE both scripts point at, exactly the same "reuse
# the asset, not the code" split every tintable texture in this project
# already follows). See silhouette_vertical_shade.gdshader's own comment
# for the gradient-multiply mechanics, and field_room.gd's landform_
# vertical_shade export for why modulate is reduced to alpha-only here
# too - the identical double-tint trap applies to any Sprite2D this
# shader is attached to, not just field_room.gd's own silhouettes.
const MOUND_SHADE_SHADER := preload("res://silhouette_vertical_shade.gdshader")

func _apply_mound_shade(sprite: Sprite2D, base_color: Color) -> void:
	sprite.modulate = Color(1.0, 1.0, 1.0, base_color.a)
	var material := ShaderMaterial.new()
	material.shader = MOUND_SHADE_SHADER
	material.set_shader_parameter("top_color", base_color.lightened(mound_vertical_shade))
	material.set_shader_parameter("bottom_color", base_color.darkened(mound_vertical_shade))
	sprite.material = material

# Stage i is stage_textures[i], clamped to the array's own bounds - a dig
# count past the last authored stage (expected in ordinary play now that
# the pool is LARGER than the stage count, 5 entries vs 4 stages as of the
# 2026-09-01 pool-restoration pass - see _ready()'s own assert, which only
# guarantees the pool is at least as big as the stage count, not equal)
# just holds at the LAST stage rather than erroring or going blank; per
# this pass's own brief, that's also the correct behavior on the FINAL
# successful dig specifically - it stops at whatever stage it reached
# rather than jumping to some separate "fully excavated" state that has
# no texture of its own anyway.
#
# Repositions the mound every call, not just at stage 0 (_build_geometry()
# above) - each stage texture has a DIFFERENT native size (530x228 down to
# 551x90), so the base-anchoring math has to be redone per texture, not
# just the texture swapped in place.
func _set_mound_stage(stage: int) -> void:
	if stage_textures.is_empty():
		return
	var clamped_stage := clampi(stage, 0, stage_textures.size() - 1)
	_mound_sprite.texture = stage_textures[clamped_stage]
	var native_size := _mound_sprite.texture.get_size()
	_mound_sprite.position = Vector2(-native_size.x * mound_scale / 2.0, -native_size.y * mound_scale) + mound_offset
	# The shard becomes collectable the moment the mound FIRST reaches its
	# own last stage (2026-09-04, dug-shard pass) - idempotent (every dig
	# past this point calls _set_mound_stage() with the SAME clamped_stage,
	# re-setting input_pickable to true again is harmless), so no separate
	# "already revealed" flag is needed beyond the flag itself. Guarded on
	# _shard_area != null for the same reason _buried_object_sprite's own
	# build is guarded - a heap variant with no buried_object_texture has
	# no shard to reveal at all.
	if clamped_stage == stage_textures.size() - 1 and _shard_area != null:
		_shard_area.input_pickable = true

# Only the column's own WIDTH is fixed up-front here - its actual
# on-screen POSITION is set every frame by _process() instead (see its
# own doc), since it now tracks the player rather than sitting at a
# fixed spot relative to this node. Same "position the whole block, let
# a Container lay out its own children" split weapon_pickup_window.tscn's
# own ContentColumn already uses for the width/layout half of this.
func _configure_offer_prompt() -> void:
	var column: VBoxContainer = offer_prompt.get_node("PromptColumn")
	column.custom_minimum_size.x = prompt_width_px
	column.size.x = prompt_width_px

# Calls OverlayStyle.apply_to_label() directly (2026-08-29, prompt-
# hierarchy pass) - REPLACES a local outline_col computed from this
# file's own offer_outline_width/offer_outline_opacity (0.35, well below
# the shared outline_opacity of 0.85), the exact "weaker copy" field_
# chest.gd's own prompt_label already moved off of one pass earlier (see
# its own doc). Raising contrast for the world-voice line (this pass's
# own brief) is exactly what using the shared, stronger treatment does,
# with no separate opacity number to tune here any more.
#
# use_light_outline=true (2026-08-30, world-voice color fix) - WORLD_TEXT
# is dark, so it needs OverlayStyle's light outline preset, same as
# field_curio.gd/field_chest.gd's own prompt labels.
func _style_prompt_text(label: Label) -> void:
	label.add_theme_font_override("font", OFFER_FONT)
	label.add_theme_font_size_override("font_size", offer_font_size)
	label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(label, true)

# REGISTER FIX (2026-08-29, cache-room pass, consistency companion to
# field_chest.gd's own identical fix - kept as its own separate commit,
# per that pass's own instruction) - Sift/Leave are mechanical UI, not
# this pile's own "voice" the way ResultLabel's outcome text above is
# (still Spectral/HudPalette.WORLD_TEXT, untouched) - no font override (project
# default sans, not OFFER_FONT's Spectral any more), HudPalette.SYSTEM_
# TEXT for the fill, same direct-read convention every other SYSTEM_TEXT
# consumer already follows. OverlayStyle.light_color() replaces color()
# here specifically because SYSTEM_TEXT is a DARK color - the shared
# dark outline_color() would sit invisibly close to it (see field_chest.
# gd's own identical note - this is light_color()'s third consumer now,
# after enemy.gd's FlavorLabel and field_chest.gd's own Take/Leave).
# outline_size now reads OverlayStyle.outline_width directly (2026-08-29,
# prompt-hierarchy pass) - REPLACES the local offer_outline_width this
# used to read, since that export is gone (see _style_prompt_text()'s own
# doc); matches field_chest.gd's own button outline exactly. font_size
# now reads offer_button_font_size, not offer_font_size - see that
# export's own doc for why the buttons need their own, smaller number.
func _style_button(button: Button) -> void:
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", offer_button_font_size)
	button.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)
	var hover_color: Color = HudPalette.SYSTEM_TEXT.lightened(0.35)
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_outline_color", OverlayStyle.light_color())
	button.add_theme_constant_override("outline_size", OverlayStyle.outline_width)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_player_in_contact = body
		set_process(true)
		_show_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_player_in_contact = null
		set_process(false) # Freezes the prompt at its last followed position, then fades out from there - same "just fade whatever's already showing" simplicity field_npc.gd's own hide_offer() already gets away with.
		_fade_offer_to(0.0, offer_fade_out_sec)
		# Declines an active GRANT_CARD offer, if one is up (2026-09-04,
		# weighted-grant pass) - walking away IS the decline for this
		# specific offer (contrast the water card's own "no decline path,
		# once shown it will be taken" - see _play_water_reveal()'s own
		# doc for why that one's different). _pending_grant_card_decline is
		# only ever non-empty while _play_grant_card_reveal() below is
		# actively awaiting a choice; calling and clearing it here is what
		# lets that function's own await resolve on this path instead of
		# only ever on the card's own click.
		if _pending_grant_card_decline.is_valid():
			var decline := _pending_grant_card_decline
			_pending_grant_card_decline = Callable()
			decline.call()

# Re-establishes the full "choosing" state - ChoiceRow visible, Sift
# hidden once exhausted (2026-08-28 brief: "only leave is offered"),
# ResultLabel only showing the exhausted flavor line, never the cost
# (that lives on SiftButton's own text now - see its own doc). Called on
# every fresh contact AND after a pull's own result-display window ends,
# so it's the one place "what does the choice look like right now" is
# decided.
func _show_prompt() -> void:
	choice_row.visible = true
	sift_button.visible = not _exhausted
	if _exhausted:
		result_label.text = "Nothing left worth taking."
		result_label.visible = true
	else:
		sift_button.text = "Sift the wreckage (-%d HP)" % _next_pull_cost()
		result_label.visible = false
	_fade_offer_to(1.0, offer_fade_in_sec)

# Floored at 1 HP remaining, same guard pay_window.gd's own _blood_cost()
# uses for its Pay in Blood cost, and for the same underlying reason: this
# HP loss goes straight to RunState.player_hp with no Toll/battle.gd
# involvement (see this feature's own report - Toll only exists inside a
# live Battle instance, so there is no existing path to route field self-
# damage through), which also means there is no field-side death handling
# to catch player_hp reaching 0 outside combat. Pay House's own floor is
# the one existing precedent for exactly this gap, reused directly rather
# than inventing a second answer to it.
func _next_pull_cost() -> int:
	return mini(_current_cost, RunState.player_hp - 1)

func _fade_offer_to(target_alpha: float, duration: float) -> void:
	if _offer_tween:
		_offer_tween.kill()
	_offer_tween = create_tween()
	_offer_tween.tween_property(offer_prompt, "modulate:a", target_alpha, duration)

# Dismisses the prompt exactly like walking out of contact does (same
# _fade_offer_to() call _on_body_exited() itself uses), WITHOUT moving the
# player and WITHOUT touching field_room.gd's own contact-tracking - the
# player is still physically standing in the trigger zone afterward.
# Bringing the choice back requires a fresh contact event (walk off, walk
# back in), per this pass's own brief ("re-enter contact to resume") -
# deliberately not wired to reopen on a stray click while still standing
# here, which would make Leave feel like it didn't do anything.
func _on_leave_pressed() -> void:
	_fade_offer_to(0.0, offer_fade_out_sec)

# The Sift choice - charges the cost, resolves the outcome, shows the
# result, then returns to the (updated) prompt. Never reachable while
# exhausted (SiftButton is hidden in that state - see _show_prompt()), so
# no separate _exhausted guard is needed here the way pull() used to
# carry one.
#
# _dig_count only advances PAST the null check (2026-09-01, staged-dune
# pass) - nothing is charged and nothing is drawn on the exhausted branch,
# so no sand came off; advancing the stage there would let the mound
# reveal that a dig failed, exactly what this pass's own brief says it
# must not do. Advanced BEFORE _next_pull_cost()/the HP charge below, not
# after - order doesn't affect either computation (neither reads _dig_
# count), but keeps every piece of "this dig succeeded" state moving
# together at the top of the success path rather than split across it.
func _on_sift_pressed() -> void:
	var outcome: SiftOutcomeData = SiftOutcomePool.draw(sift_outcome_table, _drawn_list())
	if outcome == null:
		_exhausted = true
		_show_prompt()
		return
	AudioManager.play_sfx("sift_dig")
	_dig_count += 1
	_set_mound_stage(_dig_count)
	var hp_paid: int = _next_pull_cost()
	RunState.lose_hp(hp_paid)
	_current_cost += sifting_cost_step
	choice_row.visible = false
	result_label.visible = true
	result_label.text = outcome.text
	if outcome.effect_type == SiftOutcomeData.EffectType.HP_CHANGE:
		# Trimmed back to everything BEFORE the last line (2026-09-04) -
		# outcome.text's own last line ("You drink.") is the moment of
		# actually drinking, which shouldn't read on screen before the
		# player has clicked the card to do it. _play_water_reveal()
		# appends that line back once the click actually happens - see
		# its own matching note. A single-line outcome.text is untouched
		# (nothing to defer).
		var lines := outcome.text.split("\n")
		if lines.size() > 1:
			result_label.text = "\n".join(lines.slice(0, lines.size() - 1))
		# Interactive, chest-style (2026-09-03, water-drink pass) - AWAITED,
		# not fire-and-forget: the heal itself is applied AT the click
		# (_play_water_reveal() below calls SiftOutcomeResolver.apply_hp_
		# change() directly, never resolve()), so this branch skips
		# resolve()/the emit/the fixed hold entirely and does its own
		# equivalent of each at the click instead - see that function's own
		# doc. _show_prompt() below only runs once the water is actually
		# drunk and its card cleared - no decline path, no timer dismissal;
		# "once shown, it will be taken," same as field_room.gd's own
		# chest card. Only ever true for the SIFT's own HP_CHANGE -
		# REMOVE_CARD/GOLD/GRANT_CARD/UPGRADE_CARD/NONE are untouched,
		# they still go through the shared branch below exactly as before.
		await _play_water_reveal(outcome, hp_paid)
	else:
		# Awaited BEFORE the emit below, not after - UPGRADE_CARD's own
		# CardUpgradeService.offer_upgrade() call doesn't resolve until the
		# player picks (or cancels), and this outcome's own effect has to
		# have already landed in RunState by the time `pulled` emits -
		# whatever's listening has to see BOTH the sifting cost above and
		# whatever this effect just did, not race it. _play_grant_card_
		# reveal (2026-09-04, weighted-grant pass) is the SAME opt-in shape
		# defer_hp_change established for HP_CHANGE above - only read by
		# resolve()'s own GRANT_CARD case (see its own doc); every other
		# type reached through this same call is completely unaffected by
		# passing it. The prompt can't return before this offer resolves
		# either way - _show_prompt() below only runs once this whole
		# await chain (resolve() -> the offer's own click-or-walk-away)
		# finishes.
		await SiftOutcomeResolver.resolve(outcome, false, _play_grant_card_reveal, _spawn_gold_number)
		pulled.emit(outcome, hp_paid)
		await get_tree().create_timer(outcome_display_sec).timeout
	if not is_inside_tree():
		return # The room could in principle be torn down mid-wait - defensive, mirrors field_chest.gd's own identical guard.
	_show_prompt()

# --- Water reveal (HP_CHANGE only - see _on_sift_pressed()'s own call
# site above) ---
#
# Interactive, chest-style (2026-09-03, water-drink pass - REPLACES an
# earlier passive timed display, same commit lineage) - the card persists
# indefinitely, no timer dismissal, no decline: clicking it is the ONLY
# way this function ever returns. Same "once shown, it will be taken"
# model field_room.gd's own chest card (_on_chest_card_offered()/_on_
# chest_offer_card_clicked()) already establishes for its own click-to-
# accept flow, mirrored directly rather than sharing code with it - this
# file's own header already states the "duplicate a proven shape, don't
# extract a shared abstraction" convention it follows for everything else
# (field_npc.gd's contact/prompt shape, most recently).
#
# The heal, the sound, and the HUD refresh all land TOGETHER at the
# click - not at draw time, not spread across it. SiftOutcomeResolver.
# apply_hp_change() is called directly here, never resolve() (see that
# function's own defer_hp_change doc) - the CALLER (_on_sift_pressed())
# already skipped resolve() entirely for this outcome, so this is the
# only place the HP change actually happens.
#
# NO fly-to-deck on dismiss - that flourish is the real-card-grant tell
# (see field_room.gd's own _on_npc_offer_card_clicked()), and this isn't
# one: never added to RunState.deck, never passed to RunState.add_card_
# to_deck() anywhere - see WATER_DISPLAY_CARD's own doc for the full
# case that nothing can ever pick this resource up on its own.
#
# `outcome`/`hp_paid` are handed straight to pulled.emit() below, at the
# click - the SAME signal/HUD-refresh path every other outcome type
# already fires, just retimed to when the water is actually drunk
# instead of when it was drawn.
#
# .duplicate() before writing the real value into `description` - NEVER
# mutates WATER_DISPLAY_CARD itself, which Godot caches as ONE shared
# Resource instance across every load() of that same path; writing to it
# directly would leak this draw's own HP number into every future one.
# Same shallow-duplicate convention RunState.add_card_to_deck()/card_
# upgrade_service.gd already use for CardData - a String field is all
# that's overwritten, nothing deeper needs to be independent.
func _play_water_reveal(outcome: SiftOutcomeData, hp_paid: int) -> void:
	var display_card: CardData = WATER_DISPLAY_CARD.duplicate()
	display_card.description = "Restore %d HP" % outcome.value

	var layer := CanvasLayer.new()
	add_child(layer)
	# A wrapper carries water_display_card_scale now, not set_scale_
	# factor() on the card itself (2026-09-04, offer-size match pass) -
	# see that export's own doc and card.gd's set_scale_factor() doc for
	# why: factor 1.0 keeps the card's own internal proportions correct,
	# and a plain outer transform scale is what field_room.gd's own
	# npc_offer_card_scale already does for exactly this "smaller than
	# card.gd's own minimum factor allows" case.
	var wrapper := Node2D.new()
	wrapper.scale = Vector2(water_display_card_scale, water_display_card_scale)
	layer.add_child(wrapper)
	var card: Card = CARD_SCENE.instantiate()
	wrapper.add_child(card)
	card.set_scale_factor(1.0)
	card.set_card_data(display_card)
	# AFTER set_card_data() - see hide_cost()'s own doc for why the order
	# matters (set_card_data() is what would otherwise turn a cost
	# representation back on).
	card.hide_cost()
	# mouse_filter left at its own default (interactive), UNLIKE the
	# earlier passive version of this reveal - this card is genuinely
	# clickable now. Hover feedback stays fully enabled too, same as
	# field_room.gd's own Keeper/chest cards ("Hover feedback is left
	# fully enabled... this one is clickable" - that file's own doc):
	# there's exactly one clickable thing on screen right now, nothing to
	# disambiguate away from, and hovering "what am I about to drink" is
	# the right affordance for a real interaction, not a distraction.
	# card.position centers the card's own local origin on the WRAPPER's
	# local (0,0) - same "-design_size/2, half its own UNSCALED size"
	# shape field_room.gd's own _show_npc_offer_card() uses, just off
	# custom_minimum_size (equal to design_size at factor 1.0) since this
	# card has no separate design_size constant of its own to read.
	card.pivot_offset = card.custom_minimum_size / 2.0
	card.position = -card.custom_minimum_size / 2.0
	# Fixed screen position (2026-09-05, fixed-reveal-position pass) -
	# REPLACES the old raw get_viewport().get_visible_rect().size / 2.0
	# (dead viewport center on both axes). That center Y (540 at this
	# project's 1080 viewport height) does NOT reliably clear ResultLabel's
	# own worst-case rendered height during a reveal (see reveal_position_y_
	# fraction's own doc for the full collision analysis) - changed for that
	# concrete geometric reason, not for symmetry with the grant-card path.
	# X stays at viewport-center: the collision analysis found no X is ever
	# safe (the player's own screen position ranges across nearly the whole
	# viewport width), so centering costs nothing and reads as deliberate.
	wrapper.position = Vector2(
		get_viewport().get_visible_rect().size.x / 2.0,
		get_viewport().get_visible_rect().size.y * reveal_position_y_fraction
	)
	wrapper.modulate.a = 0.0

	var fade_in_tween := create_tween()
	fade_in_tween.tween_property(wrapper, "modulate:a", 1.0, offer_fade_in_sec)
	await fade_in_tween.finished

	# The only way out of this function - no timer, no decline. Persists
	# on screen for as long as it takes: this reveal is centered-screen
	# UI (a CanvasLayer, not anchored to the player or to the heap's own
	# world position the way offer_prompt is - see _process() above), so
	# walking out of the heap's own contact zone doesn't touch it at all;
	# _on_body_exited() only ever fades offer_prompt (see its own doc),
	# never reaches into this reveal. The heal can't be lost to a stray
	# walk-off mid-offer, matching the chest pattern's own persistence -
	# the one way it COULD still be lost is leaving the ROOM entirely
	# (a scene transition mid-await, same pre-existing edge case every
	# other awaited field interaction in this project already carries,
	# not something new here - see is_inside_tree()'s own guard back in
	# _on_sift_pressed(), which this function's own caller still reaches
	# once this eventually resolves).
	await card.card_clicked
	# IGNORE immediately, before anything else - same double-click guard
	# field_room.gd's own _on_chest_offer_card_clicked() uses and for the
	# same reason: belt-and-suspenders alongside `await` only ever
	# resuming once for this one signal connection.
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# outcome.text's own LAST line ("You drink.") lands here, at the
	# click, not before (2026-09-04) - _on_sift_pressed() already trimmed
	# result_label down to everything BEFORE it the moment this outcome
	# was drawn (see that function's own matching note), so this is the
	# other half of that same split: appended back as its own second
	# line only once the water is actually drunk. A single-line
	# outcome.text (no second line authored) leaves result_label
	# untouched here - nothing to defer.
	var lines := outcome.text.split("\n")
	if lines.size() > 1:
		result_label.text += "\n" + lines[lines.size() - 1]

	SiftOutcomeResolver.apply_hp_change(outcome)
	AudioManager.play_sfx("water_drink")
	pulled.emit(outcome, hp_paid)

	var fade_out_tween := create_tween()
	fade_out_tween.tween_property(wrapper, "modulate:a", 0.0, offer_fade_out_sec)
	await fade_out_tween.finished

	layer.queue_free()

# --- Grant card reveal (GRANT_CARD only - see _on_sift_pressed()'s own
# call site, and SiftOutcomeResolver.resolve()'s own offer_grant_card
# parameter) ---
#
# Same overall shape as _play_water_reveal() above (a centered CanvasLayer
# offer, the drawn card shown at grant_card_scale via a wrapper, fade in,
# await), but UNLIKE that one this genuinely can be declined - walking
# out of the heap's own contact zone (_on_body_exited()) is the decline,
# not just "no interaction yet." The card shown here is the REAL drawn
# CardData, unmodified - no WATER_DISPLAY_CARD-style duplicate-and-
# rewrite-description step, since this card's own face (including its
# single-use marker, if the drawn card happens to be CONSUMED-scope - see
# card.gd's own REMOVAL_SCOPE_KEYWORD_TEXT) is exactly what should show.
#
# Sound moved HERE from SiftOutcomeResolver.resolve()'s own old immediate-
# grant branch (2026-09-04, weighted-grant pass) - resolve() no longer
# plays add_card or calls RunState.add_card_to_deck() itself for any
# caller that hands it this callback (see that function's own doc); both
# only ever happen on ACCEPT, below, never on draw and never on decline.
# field_curio.gd's own Investigate never passes this callback, so its own
# GRANT_CARD entries (if it ever draws one) are completely unaffected -
# resolve() still grants immediately for it, exactly as before this pass.
func _play_grant_card_reveal(card_data: CardData) -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var wrapper := Node2D.new()
	wrapper.scale = Vector2(grant_card_scale, grant_card_scale)
	layer.add_child(wrapper)
	var card: Card = CARD_SCENE.instantiate()
	wrapper.add_child(card)
	card.set_scale_factor(1.0)
	card.set_card_data(card_data)
	card.pivot_offset = card.custom_minimum_size / 2.0
	card.position = -card.custom_minimum_size / 2.0
	# Fixed screen position (2026-09-05, fixed-reveal-position pass) -
	# REPLACES the old "measure ResultLabel's live rect, position below it"
	# approach (2026-09-04, card-below-text fix) - that chased a moving
	# target twice over: ResultLabel follows the PLAYER (see _process()'s
	# own doc), and the collision analysis behind reveal_position_y_
	# fraction found the player's own screen position ranges across nearly
	# the ENTIRE viewport width, not just near screen-center, so no position
	# derived from wherever the player currently stands could ever be
	# reliably clear of it. No more await get_tree().process_frame either -
	# that wait existed solely to let PromptColumn's own deferred re-sort
	# settle before reading result_label.get_global_rect(); with nothing
	# left to measure, there's nothing left to wait for. Nothing else in
	# this function depended on that frame's delay.
	var card_half_height: float = card.custom_minimum_size.y * grant_card_scale / 2.0
	wrapper.position = Vector2(
		get_viewport().get_visible_rect().size.x / 2.0,
		get_viewport().get_visible_rect().size.y * reveal_position_y_fraction
	)
	wrapper.modulate.a = 0.0

	var fade_in_tween := create_tween()
	fade_in_tween.tween_property(wrapper, "modulate:a", 1.0, offer_fade_in_sec)
	await fade_in_tween.finished

	# The race: whichever of these two fires first settles the offer -
	# see _grant_offer_settled's own doc for why a shared signal, not a
	# direct `await card.card_clicked`, is what's actually awaited below.
	# card_clicked emits one argument (card_data: CardData - see card.gd's
	# own signal declaration) - this lambda MUST accept it even though it
	# doesn't use it. A zero-arg lambda connected here silently never runs:
	# Godot errors at emit time on the arity mismatch and the connected
	# callable never executes, so this whole await hangs forever on every
	# accept click (confirmed live, 2026-09-05 diagnosis pass).
	var on_click := func(_clicked_card_data: CardData): _grant_offer_settled.emit(true)
	card.card_clicked.connect(on_click, CONNECT_ONE_SHOT)
	_pending_grant_card_decline = func(): _grant_offer_settled.emit(false)

	var accepted: bool = await _grant_offer_settled

	# Whichever path won, the OTHER one's own trigger is now stale - clear
	# both unconditionally rather than branching on `accepted` to decide
	# which cleanup is needed, so a future third trigger (none exists
	# today) couldn't accidentally skip one by mistake.
	_pending_grant_card_decline = Callable()
	if card.card_clicked.is_connected(on_click):
		card.card_clicked.disconnect(on_click)
	# IGNORE immediately, same double-click/double-decline guard _play_
	# water_reveal() above already uses - belt-and-suspenders alongside
	# CONNECT_ONE_SHOT and the walk-away path only ever firing once.
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if accepted:
		RunState.add_card_to_deck(card_data)
		AudioManager.play_sfx("add_card")
		# Same deck-count refresh field_room.gd's own _on_npc_offer_card_
		# clicked() already does at its own equivalent moment - deck_label
		# is a plain external reference (see deck_button's own doc above),
		# not guaranteed non-null in principle, so this stays defensive even
		# though every real room load wires it.
		if deck_label != null:
			deck_label.text = "Deck (%d)" % RunState.deck.size()
		# Fly-to-deck (2026-09-04) - same shape field_room.gd's own _on_
		# npc_offer_card_clicked() uses for the Keeper's own accept: shrink
		# the wrapper toward deck_button's own screen position, fade the
		# card out over the same animation. Unlike her version, no camera-
		# transform conversion is needed here - this wrapper already lives
		# in a CanvasLayer (screen space), and deck_button is ALSO screen-
		# space UI, so both sides of the tween are already in the same
		# coordinate space with nothing to convert.
		var world_target: Vector2 = deck_button.get_global_transform_with_canvas().origin if deck_button != null else wrapper.position
		var fly_tween := create_tween()
		fly_tween.set_parallel(true)
		fly_tween.tween_property(wrapper, "position", world_target, grant_card_accept_duration_sec)
		fly_tween.tween_property(wrapper, "scale", wrapper.scale * 0.15, grant_card_accept_duration_sec)
		fly_tween.tween_property(card, "modulate:a", 0.0, grant_card_accept_duration_sec)
		await fly_tween.finished
	else:
		# Declined - a plain fade, no sound, nothing granted. The outcome
		# itself was already consumed from the pool the moment it was
		# drawn (SiftOutcomePool.draw(), back in _on_sift_pressed()), so
		# there's nothing left here to "give back" by declining - same
		# "the dig is spent either way" grammar the removal picker's own
		# cancellation already established.
		var decline_tween := create_tween()
		decline_tween.tween_property(wrapper, "modulate:a", 0.0, offer_fade_out_sec)
		await decline_tween.finished

	layer.queue_free()

# --- Gold number (GOLD only - see _on_sift_pressed()'s own resolve()
# call site above) ---
#
# Passed to SiftOutcomeResolver.resolve() as on_gold_granted (2026-09-04,
# gold-range pass) - called with the ACTUAL rolled amount, after RunState.
# add_gold() has already run, so the HUD counter and this number always
# agree. Single-arg on purpose (unlike field_chest.gd's own _spawn_gold_
# number(amount, player), which takes the player explicitly) - this
# script already holds _player_in_contact as its own state (set by _on_
# body_entered(), only ever null while no sift is reachable at all, which
# can't be true here since _on_sift_pressed() itself is unreachable
# without it), so there's nothing for the resolver's own generic callback
# signature to pass through.
#
# Scoped to THIS heap's own GOLD outcome only - not a general reward-
# number system. A later caller wanting the same floating-number trick
# for a different gold source (on-contact field gold, a shop purchase)
# would lift this function's own body (or field_chest.gd's near-identical
# one) into a shared helper; neither exists today, so this stays local.
func _spawn_gold_number(amount: int) -> void:
	var number_label := Label.new()
	number_label.text = "+%d" % amount
	number_label.add_theme_font_size_override("font_size", gold_number_font_size)
	number_label.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)
	# use_light_outline=true - SYSTEM_TEXT is a dark color (same reasoning
	# _style_button()/_style_prompt_text() above already document for
	# this file's own Sift/Leave buttons and world-voice line).
	OverlayStyle.apply_to_label(number_label, true)
	# Same measured offset field_chest.gd's own _spawn_gold_number() uses -
	# the SAME Player scene (see that function's own doc for the full
	# derivation), so the same offset lands in the same place here: just
	# above the player-visual's own head, not at its collision origin.
	number_label.position = Vector2(-16.0, -350.0)
	_player_in_contact.add_child(number_label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(number_label, "position:y", number_label.position.y - gold_number_rise_px, gold_number_duration_sec)
	tween.tween_property(number_label, "modulate:a", 0.0, gold_number_duration_sec)
	tween.chain().tween_callback(number_label.queue_free)

# --- Shard collection (2026-09-04, dug-shard pass - see _shard_area's
# own doc for the full precedent it's built against) ---
#
# Same InputEventMouseButton/left-click filter every other Area2D.input_
# event handler in this project uses (field_room.gd's _on_heap_clicked()/
# _on_curio_clicked()/_on_npc_clicked()) - mirrored here rather than
# shared, this file's own established "duplicate a proven shape"
# convention. Unlike those, no `heap`-style bound extra argument is
# needed - _shard_area is 1:1 with this single heap instance, not shared
# across many like field_room.gd's own room-level dispatch.
#
# Independent of the whole Sift/Leave flow on purpose (this pass's own
# brief) - _shard_collected/_shard_area are read/written ONLY here and in
# _set_mound_stage() above; nothing about _on_sift_pressed()'s own
# sequence reads either, so digging with the shard uncollected, or
# collecting mid-dig-sequence, can never conflict with it.
func _on_shard_clicked(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# Belt-and-suspenders (2026-09-04) - _shard_area.input_pickable is
	# ALREADY what stops a real click from ever reaching this handler
	# before full reveal (Godot's own physics-picking dispatch never
	# calls input_event on a non-pickable Area2D), so this re-check is
	# defensive, not the primary gate. Reads input_pickable directly
	# rather than a second parallel flag - it's already the single source
	# of truth for "is this revealed yet," see _set_mound_stage()'s own
	# doc for where it flips true.
	if _shard_area.input_pickable and not _shard_collected:
		_shard_collected = true
		_shard_area.input_pickable = false
		RunState.add_shards(1)
		RunLogger.log_shard_gained(1, "heap")
		AudioManager.play_sfx("shard_collected")
		_spawn_shard_number()
		# Post-collection visual state: fade the buried object out,
		# leaving the mound's own last-stage crater texture showing
		# nothing inside it - already a coherent "already dug out" read
		# with the EXISTING art (that stage's own crater silhouette has
		# no shard drawn into it at all - buried_object_texture is a
		# wholly separate sprite, layered behind it, never baked into any
		# stage_textures entry - see buried_object_texture's own doc). No
		# new art asset is needed for this. offer_fade_out_sec reused
		# rather than a dedicated new duration - this file's own existing
		# "component fades" length, same one every other decline/dismiss
		# fade in this script already uses.
		var fade_tween := create_tween()
		fade_tween.tween_property(_buried_object_sprite, "modulate:a", 0.0, offer_fade_out_sec)
	get_viewport().set_input_as_handled()

# Anchored to visual_root (world space, the SAME parent the mound/buried-
# object sprites already use), NOT to _player_in_contact the way Gold
# Number's own _spawn_gold_number() is - collecting the shard doesn't
# require contact (this pass's own brief: independent of the sift flow),
# so _player_in_contact isn't guaranteed non-null at click time the way
# it is inside _on_sift_pressed()'s own call chain. Anchoring to the
# shard's own position sidesteps that entirely, and arguably reads better
# anyway: this number is about what's AT the heap, not what the player is
# carrying yet.
#
# x=0 is _buried_object_sprite's own horizontal center (its position.x is
# already -halfwidth, i.e. base-anchored so its CENTER sits at local
# x=0 - see that sprite's own position math in _build_geometry()) - no
# extra centering math needed. The -8.0 nudge is the same "a fresh Label
# doesn't know its own width yet" approximate fudge field_chest.gd's own
# _spawn_gold_number() uses (its own -16.0 for a wider "+NN"/"+NNN" gold
# figure; "+1" is always exactly two characters, so a smaller nudge here).
func _spawn_shard_number() -> void:
	var number_label := Label.new()
	number_label.text = "+1"
	number_label.add_theme_font_size_override("font_size", shard_number_font_size)
	number_label.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)
	# use_light_outline=true - SYSTEM_TEXT is a dark color, same reasoning
	# _spawn_gold_number()/_style_button()/_style_prompt_text() above
	# already document.
	OverlayStyle.apply_to_label(number_label, true)
	number_label.position = Vector2(-8.0, _buried_object_sprite.position.y)
	visual_root.add_child(number_label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(number_label, "position:y", number_label.position.y - shard_number_rise_px, shard_number_duration_sec)
	tween.tween_property(number_label, "modulate:a", 0.0, shard_number_duration_sec)
	tween.chain().tween_callback(number_label.queue_free)
