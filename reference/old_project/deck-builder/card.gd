extends Control
class_name Card
# class_name lets other scripts (like Battle) refer to "Card" as a type,
# e.g. when declaring a variable that should hold one of these.
#
# The root node is a plain Control, not the card's visible face — it's an
# invisible "slot" (custom_minimum_size = design_size, see below) that
# HandContainer positions and that owns all mouse input (clicks, hover).
# The actual card face lives in the "Visual" child (see card.tscn) and is
# what actually moves and scales for the hover animation below. Keeping
# them separate means the hover animation can move the *look* of the
# card without dragging the clickable area along with it.
#
# --- Card face structure ---
#
# Visual (Panel - outer frame, rarity border lives on THIS StyleBoxFlat)
#   Frame (MarginContainer - outer_margin_px on all sides, inset from the
#          rarity border to the content)
#     Zones (VBoxContainer - the three stacked bands, separated by
#            zone_separation_px)
#       NameBanner (PanelContainer, own subtle bg) -> NameLabel
#       ArtSlot (PanelContainer, own subtle "inset" bg) -> ArtTypeFill
#         (a ColorRect, flat card_type-colored background - see art_
#         type_fill's own onready var doc for why child ORDER, not
#         position, is what puts this behind ArtTexture) -> ArtTexture
#         (empty/hidden until real art exists - see _update_art_
#         texture()). This is the future art hook: whatever eventually
#         renders card art (a TextureRect, or an instanced scene for
#         something fancier) gets added as a child of THIS node,
#         layering over ArtTypeFill the same way ArtTexture already
#         does. Nothing else in the layout needs to change - Zones'
#         stretch ratios already reserve this node a fixed proportion of
#         the card's height regardless of what's inside it, and Panel
#         Container fits every child to that same content rect
#         automatically. See art_slot below.
#       DescriptionClip (plain Control, invisible - own zone_content_
#         margin_px note below explains why this exists at all) ->
#         DescriptionPanel (PanelContainer, own subtle bg) ->
#         DescriptionLabel (a RichTextLabel, bbcode_enabled - see card_
#         text_styles.gd for the semantic-tag layer on top of it.
#         size_flags_vertical = SHRINK_CENTER + fit_content = true stands
#         in for Label's old vertical_alignment, which RichTextLabel
#         doesn't have; [center] BBCode in _update_display() stands in
#         for horizontal_alignment, same reason.)
#   CostBadge (Panel, circular, NOT part of Zones - an overlay pinned to
#              the top-left corner via anchor/offset, sitting above
#              Frame in draw order so it reads over the name banner's
#              corner)
#     CostLabel
#
# Every zone's size comes from Zones' stretch ratios (name/art/description
# proportions of the CARD height) rather than fixed pixel heights - EXCEPT
# that this alone doesn't actually guarantee "never overflow," which is
# exactly the bug DescriptionClip fixes (2026-08-25, see its own doc a few
# lines below): a Container (like DescriptionPanel used to be, directly
# under Zones) always reports its CHILD's minimum size upward, and fit_
# content deliberately makes DescriptionLabel's minimum size grow with its
# text - so a long enough description could inflate Zones' own math and
# steal ratio-space from ArtSlot above it, regardless of the ratios
# themselves. DescriptionClip (a plain Control, not a Container) sits
# between Zones and DescriptionPanel specifically so Zones never sees that
# inflated number at all - see its own onready var doc below for the full
# mechanism. The one thing containers can't infer on their own is TEXT
# size and PIXEL margins/badge geometry, so those live in the exported
# variables below and get reapplied by _apply_layout() any time the
# overall scale changes (see set_scale_factor()).

# A "signal" is an announcement a node can make. Other nodes can "listen"
# for it without this script needing to know who's listening or what
# they'll do. This is how the card tells the world "I was clicked" without
# deciding for itself what clicking should mean — that's the Battle
# scene's job.
signal card_clicked(card_data: CardData)

# Right mouse button pressed anywhere on this card. Fires regardless of
# card_data or armed state - Battle is the one that decides it means
# "cancel targeting if any is active" (see battle.gd's own connect next
# to card_clicked above). Needed because a right-click on THIS card
# would otherwise never reach battle.gd's _unhandled_input() background-
# cancel fallback at all: this Control's default STOP mouse filter
# swallows every mouse event over its rect at the GUI layer, whether
# _gui_input()'s body does anything with it or not, so relying on
# propagation here would silently eat the click instead of canceling.
signal right_clicked

# Announces every hover start/stop, regardless of what this card does or
# whether anything's currently armed/targetable - a generic "the player
# is looking at this card" signal, not a targeting-specific one. This is
# the seam for any "what would this card actually do right now" preview
# (2026-08-23, first use: Outbound's damage falloff readout - see battle.
# gd's _on_card_hover_changed()) - a weapon modifier already silently
# changes a card's real damage, and the status-modifier system is
# dormant but real; both are invisible number-changers this same signal
# is meant to eventually let Battle preview too, not something built
# fresh per feature. Fires from _on_mouse_entered()/_on_mouse_exited()
# even while _armed (see set_armed()'s own note - _is_hovered keeps
# tracking underneath the suppressed animation), so a caller doesn't
# need to know or care about the armed state machine at all.
signal card_hover_changed(card_data: CardData, hovering: bool)

# The CardData this card instance is currently showing. It starts empty
# (null) until something calls set_card_data() below.
var card_data: CardData

# How far the card rises, how much it scales up, and how long that takes
# when hovered. @export (not const) so a caller that needs a bigger rise
# than the default - battle.gd's hand cards, which sit mostly below the
# screen's bottom edge at rest and need to travel much further to come
# fully into view (see its own hand_rest_visible_height_px) - can
# configure just its OWN instances without changing what a deck-viewer/
# reward-screen card (which never touches these) does. Same tween code,
# same easing, just a per-instance magnitude - "extending the existing
# hover pop-out behavior," not a second animation system.
@export var hover_offset: Vector2 = Vector2(0, -50)
@export var hover_scale: Vector2 = Vector2(1.1, 1.1)
@export var hover_duration: float = 0.1

# How much bigger the card gets while armed/selected - see set_armed()
# below. No armed_offset alongside it any more (REMOVED 2026-08-25,
# center-slot pass) - armed no longer means "lift further within the
# hand slot" (a local offset), it means "fly to one fixed on-screen
# point regardless of hand slot" (battle.gd's own armed_card_center_y_px
# - see _begin_targeting()), which only makes sense as a position the
# caller passes in, not a per-instance local export.
@export var armed_scale: Vector2 = Vector2(1.15, 1.15)
const ARMED_MODULATE := Color(1.15, 1.05, 0.6, 1)

# --- Skill commit-and-exit (2026-08-26 - see battle.gd's own _play_
# card()) ---
#
# A SKILL card vanishes from hand the instant it's clicked today, with
# nothing else carrying the moment the way an Attack's targeting/impact/
# enemy flinch already does for free - this is the fix: a short "this
# landed" beat before the card actually leaves. battle.gd decides WHICH
# cards get this (card_type == SKILL only - Attacks are untouched); this
# script only knows how to play the beat once asked (see play_commit()/
# play_exit() below).
#
# Same technique as hover/armed above (a parallel tween of visual's own
# position/scale, TRANS_SINE/EASE_OUT) but through its OWN tween
# (_skill_tween), not a reuse of _hover_tween - a card mid-commit/exit
# has to be immune to a stray mouse_entered/mouse_exited firing on its
# own shrinking hitbox and yanking it back toward its resting pose mid-
# animation. Also purely LOCAL position offsets, unlike armed's own
# top_level screen-space handling above - a SKILL card never arms/
# targets (no skill card sets CardData.requires_target today), so
# visual.top_level is always false for the entire lifetime of a card
# this plays on; nothing here needs to account for that mechanism.
@export var skill_commit_offset: Vector2 = Vector2(0, -30)
@export var skill_commit_scale: Vector2 = Vector2(1.08, 1.08)
# Same family as armed_scale (1.15) - a commit is a confirmation, not a
# second arming, so it stays noticeably smaller.
@export var skill_commit_duration_sec: float = 0.12
@export var skill_commit_hold_sec: float = 0.1
# How long the card sits at its committed pose AFTER battle.gd has fired
# its SFX and resolved its effects - the actual "hold" the brief asks
# for; the commit/exit tweens are just the push in and the pull out
# around it. Read by battle.gd's own _play_card(), not by anything in
# this file. TRIMMED (2026-08-26) from 0.15 - read as a hair too long
# before the card actually leaves the hand.
@export var skill_exit_offset: Vector2 = Vector2(0, -60)
@export var skill_exit_duration_sec: float = 0.15
# Start short across all five of the above - "err on the side of too
# fast" per this feature's own brief - retune from here, in one place,
# once seen live.

var _skill_tween: Tween

# Colors for the affordability dim (see set_affordable below).
const AFFORDABLE_MODULATE := Color(1, 1, 1, 1)
const UNAFFORDABLE_MODULATE := Color(0.6, 0.6, 0.6, 1)

# Border color per rarity (placeholder colors - final art direction comes
# later). Colors ArtSlot's own border, NOT Visual's outer one (see
# _update_rarity_border()) - REVERSED (2026-08-27, Slay the Spire-
# inspired border swap): rarity used to own the whole card's outer
# frame, with card_type only showing as the art-slot fill. Type reads
# faster while scanning a hand/grid than rarity does, so type now takes
# the outer frame instead (see CARD_TYPE_ART_COLORS below) and rarity
# moved to this smaller accent. COMMON's cool gray-blue was originally
# picked to match Visual's own old baked-in neutral border - it now
# sits on ArtSlot's warm-paper-family border instead, a slightly duller
# match than before; deferred palette wrinkle, not fixed here (both
# dicts are still provisional placeholders regardless). COMMON DARKENED/
# SATURATED (2026-08-27, same pass as the width bumps below) - the old
# value (0.4, 0.42, 0.48) was picked to blend into Visual's old neutral
# default border and read as noticeably duller than RARE/ULTRA_RARE/
# SECRET_RARE once it landed on ArtSlot's own warm, light border instead
# - this reads as a deliberate "cool steel" tier now rather than a washed-
# out non-color, without touching the three already-vivid tiers above it.
const RARITY_BORDER_COLORS := {
	CardData.Rarity.COMMON: Color(0.28, 0.32, 0.44, 1),
	CardData.Rarity.RARE: Color(0.25, 0.55, 0.95, 1),
	CardData.Rarity.ULTRA_RARE: Color(0.85, 0.65, 0.15, 1),
	CardData.Rarity.SECRET_RARE: Color(0.55, 0.25, 0.8, 1),
}

# ArtSlot's own fill (_update_art_type_fill()) - back to one entry per
# CardType (2026-09-07, low-chroma-restore pass, follow-up to d855888).
# d855888 flattened this to one neutral fill for every type - the old
# per-type red/blue/violet fills were the most chromatic thing on screen
# against the battle backdrop's own muted palette, and no CardData
# carries real art yet for the fill to sit behind anyway (see
# _update_art_texture() below for how a real texture layers on top of
# this once one exists) - but that lost type as a signal at the one spot
# in a hand/grid scan most likely to be looked at. These three restore
# the hue split at LOW CHROMA instead of dropping it: each keyed off the
# SAME hue family as the original CARD_TYPE_ART_COLORS (warm red-brown /
# cool blue-gray / violet) but desaturated near d855888's own neutral
# (126, 133, 128), not back toward the old vivid values. Luminance held
# within a few points across all three (~0.51-0.53, standard luma) on
# purpose - they read as the same material at different hues, not a
# value hierarchy where one type's card looks "heavier" than another's.
# card_type still drives the OUTER border (card_type_border_colors
# below) and everything else it always has; this is the one layer that
# reads type from a low-chroma hue instead of a bold one.
@export var art_placeholder_color_attack: Color = Color8(150, 128, 122)
# ~+28 R-B, luma ~0.53 - warm red-brown family (ATTACK's original hue).
@export var art_placeholder_color_skill: Color = Color8(120, 133, 145)
# ~-25 R-B, luma ~0.51 - cool blue-gray family (SKILL's original hue).
@export var art_placeholder_color_stance: Color = Color8(136, 126, 148)
# ~-12 R-B, luma ~0.52 - violet family (STANCE's original hue).

# Visual's own OUTER border color, one entry per CardType (2026-08-29,
# border-desaturation pass - REPLACES CARD_TYPE_ART_COLORS as _update_
# type_border()'s own source, see that dict's own doc for why they split).
# The brief this pass came from: the border read as a UI accent bolted
# onto the card rather than the card's own material, and was the single
# most saturated thing on screen against an otherwise muted palette -
# confirmed by checking, not assuming: EVERY type had the same problem,
# not just SKILL/Guard's blue (h=0.564 s=0.448 v=0.580) - ATTACK's red-
# brown (h=0.040 s=0.583 v=0.720) and STANCE's violet (h=0.718 s=0.382
# v=0.680) were equally vivid, just less complained-about.
#
# Each entry here is the SAME hue as its old CARD_TYPE_ART_COLORS value
# (hue is what carries type distinction - changing it would undermine
# the exact thing this pass has to preserve). Exported (not a const like
# CARD_TYPE_ART_COLORS) specifically so these feel-based values can be
# tuned by eye in the Inspector.
#
# RAISED (2026-08-29, saturation-recovery pass) - the first pass's s*0.5/
# v*0.55 overshot: ATTACK and SKILL landed close enough in raw darkness
# that the outer border stopped carrying any type signal at all, leaving
# the art panel fill as the only thing actually distinguishing them.
# Brought back up to roughly halfway between the ORIGINAL CARD_TYPE_ART_
# COLORS values and that overshot pass (s*0.75, v*0.775 relative to the
# true original, i.e. splitting the difference between the original's own
# 1.0/1.0 and the first pass's 0.5/0.55) - verified by rendering all
# three rows (original / overshot / this) side by side, not computed
# blind: this row reads as clearly separated per-type again while still
# staying visibly deeper/more muted than the original vivid values.
#   ORIGINAL (CARD_TYPE_ART_COLORS, pre-desaturation):
#     ATTACK (0.72, 0.4, 0.3)     s=0.583 v=0.720
#     SKILL  (0.32, 0.48, 0.58)   s=0.448 v=0.580
#     STANCE (0.5, 0.42, 0.68)    s=0.382 v=0.680
#   OVERSHOT (previous pass, s*0.5/v*0.55):
#     ATTACK (0.396, 0.308, 0.281) s=0.290 v=0.396
#     SKILL  (0.248, 0.292, 0.319) s=0.223 v=0.319
#     STANCE (0.325, 0.303, 0.374) s=0.190 v=0.374
#   CURRENT (this pass, s*0.75/v*0.775 of the ORIGINAL):
#     ATTACK (0.558, 0.372, 0.314) s=0.438 v=0.558
#     SKILL  (0.298, 0.391, 0.450) s=0.336 v=0.449
#     STANCE (0.422, 0.376, 0.527) s=0.287 v=0.527
@export var card_type_border_colors: Dictionary[CardData.CardType, Color] = {
	CardData.CardType.ATTACK: Color(0.558, 0.372, 0.314, 1),
	CardData.CardType.SKILL: Color(0.298, 0.391, 0.450, 1),
	CardData.CardType.STANCE: Color(0.422, 0.376, 0.527, 1),
}

# The appended rules-text keyword, one entry per non-NONE RemovalScope
# (2026-08-28, removal-scope pass; RENAMED from REMOVAL_SCOPE_BADGE_TEXT
# in the badge-removal pass right after - there's no badge left for
# "badge text" to describe, just a generated line in the rules text
# itself, see _removal_scope_suffix() below). NONE has no entry on
# purpose - _removal_scope_suffix() returns "" for it rather than this
# dict needing a blank placeholder, the same "absent means unused" shape
# CARD_TYPE_ART_COLORS above doesn't need only because CardType has no
# "none" value to skip. Kept here, as ONE dict, rather than scattered
# string literals at each call site - "Spent"/"Consumed" are PROVISIONAL
# (see this pass's own report: both scope names are likely to be renamed
# once real terminology is picked), so whatever they become later is a
# two-line edit here, not a hunt through the file.
const REMOVAL_SCOPE_KEYWORD_TEXT := {
	CardData.RemovalScope.SPENT: "Spent",
	CardData.RemovalScope.CONSUMED: "Consumed",
	# Kept as "Consumed" (2026-09-04) - the single-use card pass (Packed
	# Sand) briefly retitled this to "Single use." and back per direct
	# request: every CONSUMED-scope card (Kept Warmth, Slam, Packed Sand)
	# reads this one shared lookup, so it stays one consistent keyword
	# across all of them, not a Packed-Sand-specific label. Still
	# placeholder wording, per this dict's own header note above.
}

# --- Border widths (2026-08-27, thickness pass) ---
#
# Both borders below stay FIXED regardless of _scale_factor, same as
# every other zone border on this face (see _apply_layout()'s own note
# on why border_width_* is never multiplied by f) - these two are just
# the first ones pulled into real @export fields instead of staying
# raw numbers baked into card.tscn's StyleBoxFlat sub-resources, so
# they're tunable from the Inspector like everything else visual on
# this card already is. Applied once in _own_zone_styles() (never
# revisited in _apply_layout(), since a fixed value has nothing to
# recompute on a scale change).
@export var visual_border_width_px: float = 3.0
# Visual's own outer border (the whole card's main frame, type-colored -
# see card_type_border_colors/_update_type_border()). REDUCED from 7
# (2026-08-29, border-desaturation pass) - at 7px this outer border, the
# art panel's own rarity border (art_slot_rarity_border_width_px, 5px),
# and the card's geometric silhouette edge all landed at comparable
# weight, three nested outlines competing for attention. Cut below the
# art frame's own 5px specifically so the art panel reads as the sharp
# element and this reads as the quieter one, per this pass's own brief -
# not an arbitrary smaller number, a deliberate reversal of which of the
# two borders should win the eye first. art_slot_rarity_border_width_px
# itself is untouched; this is the only width this pass changes.
@export var art_slot_rarity_border_width_px: float = 5.0
# ArtSlot's own border WIDTH - name kept despite no longer being rarity-
# COLORED (2026-08-29, inner-border-removal pass disconnected _update_
# rarity_border(), see that function's own doc; renaming this export
# would silently break any existing per-instance override of it
# elsewhere, so the width knob keeps its old name even though "rarity"
# in it is now just history, not a current description). Still real:
# this is what gives the art panel the edge it needs to define itself
# against the card stock (this pass's own brief), now painted in the
# single flat art_slot_border_color for every card rather than varying
# by RARITY_BORDER_COLORS. Was a flat 2, bumped once already to 3 when
# rarity first moved here; raised further to 5 since a smaller ring
# around a smaller area needs relatively more width than Visual's own
# to read at a glance, not less - that sizing reasoning didn't change
# just because the color source did.

@export var visual_corner_radius_px: float = 10.0
# Visual's own outer-frame corner rounding (2026-08-29, sharp-edges pass) -
# pulled into a real export for the same reason visual_border_width_px
# was: it was a raw number baked into card.tscn's StyleBoxFlat_default
# (10, unchanged default here) with no way to compare against a smaller
# value without hand-editing the .tscn's sub-resource directly. FIXED
# regardless of _scale_factor, same as the two border widths above and
# for the same reason - applied once here, in _own_zone_styles(), never
# revisited in _apply_layout(). Deliberately NOT dropped straight to 0
# by this pass itself - the brief asks for a small-vs-zero comparison by
# eye, not a decision made in code, so the default stays exactly what
# was already on screen and this is the number to actually retune.
@export var art_slot_corner_radius_px: float = 6.0
# ArtSlot's own corner rounding (unchanged default, was baked into
# StyleBoxFlat_art_slot the same way visual_corner_radius_px's own 10 was) -
# a separate export, not a shared one, so the two frames can be compared
# and tuned independently, but expected to move together in practice per
# this pass's own brief ("apply the same treatment... so the two stay
# consistent") - they're just two numbers, not one, because ArtSlot's
# ring is already a different absolute size from Visual's outer frame
# (see art_slot_rarity_border_width_px's own doc on why its border width
# is independently tuned too, for the same "smaller ring needs its own
# number" reasoning).

# How far this rocks side to side (in radians) and how long each leg of
# the refusal shake takes (see play_refused below).
const SHAKE_ROTATION := 0.06
const SHAKE_LEG_DURATION := 0.05

# --- Layout (DESIGN values, i.e. at scale factor 1.0 - a hand card) ---
#
# Everything a card's internal layout needs that a Container can't work
# out on its own: pixel margins/spacing, the cost badge's fixed circular
# geometry, and font sizes. @export so this is tunable from the
# Inspector on card.tscn without touching this script - _apply_layout()
# below is the ONLY place that reads these, so editing one here and
# re-running immediately shows the effect.
@export_group("Card Layout")
@export var design_size: Vector2 = Vector2(247.5, 345)
@export var outer_margin_px: float = 10.0
@export var zone_separation_px: float = 8.0
@export var zone_content_margin_px: float = 6.0
# ArtSlot/DescriptionPanel: relative weights, NOT pixels - Godot
# container stretch ratios, splitting whatever height is left over
# between the two of them after NameBanner and the gap spacer below take
# their own FIXED shares first (see name_zone_height_px's own note for
# why NameBanner stopped being part of this stretch pool). 1.7 : 1.1
# gives the art slot the bigger share while staying "roughly square" at
# design_size, without being pixel-exact about it - retune the two
# together if the proportion ever feels off, they don't need to sum to
# any particular number.
@export var art_zone_stretch: float = 1.7
@export var description_zone_stretch: float = 1.1
@export var name_zone_height_px: float = 47.0
# FIXED pixels, not a stretch ratio (2026-08-25, arc-margin pass; cut
# again same day, layout pass). Sized to the name's own actual text
# height plus its normal zone padding, nothing more: Font.get_height()
# for the name's own Spectral font at name_font_size_px (22px) measures
# exactly 35.0px (verified headlessly, not the earlier "~35px" estimate)
# + zone_content_margin_px's own 12px (top+bottom) of padding = 47px -
# no separate cushion on top of that this time, unlike the previous cut
# (75 -> 59), which deliberately kept 12px of slack specifically to fund
# art_description_gap_extra_px below. That fund is untouched here - the
# height freed by THIS cut (12px more) just flows into ArtSlot/
# DescriptionPanel's own existing stretch ratios instead, same as any
# other height change upstream of them. Verified headlessly against
# every shipped card name (the pool's longest, "Paid in Pain," measures
# exactly 35px tall - one line, no wrap) that this is still comfortably
# single-line at NameBanner's real inner width - see this export's own
# git history for the measurement script if this ever needs re-checking
# against a longer future name.
@export var art_description_gap_extra_px: float = 8.0
# The actual reason name_zone_height_px shrank - see hand_rest_visible_
# height_px's own doc in battle.gd for the full story: rotation (and
# now the arc) needs real clearance between ArtSlot's bottom edge and
# DescriptionPanel's top edge to avoid ever exposing the description at
# rest, and the two zones' default 8px gap (zone_separation_px, shared
# with every other zone boundary) wasn't enough room for that at fan_
# max_tilt_deg's own 5°. This is ADDED on top of the normal separation
# via a dedicated spacer node (ArtDescriptionGapSpacer, a plain Control
# with no visual of its own) between ArtSlot and DescriptionPanel in
# Zones - inserting it as its own VBox child also contributes ONE more
# normal zone_separation_px gap "for free" (a new child means a new
# boundary), so the total extra room this buys is zone_separation_px +
# art_description_gap_extra_px, not just this export's own value in
# isolation. Deliberately NOT a bump to zone_separation_px itself - that
# constant is shared with the Name-Art boundary too, and widening it
# there would have cost ArtSlot height for no reason (that boundary was
# never the problem).
@export var cost_badge_diameter_px: float = 46.0
# UNCHANGED (2026-08-25 information-hierarchy pass) - growing this
# alongside cost_font_size_px was the original plan, but CostBadge is a
# corner OVERLAY on Visual (see card.tscn), not part of Zones' flow -
# it physically sits on top of NameBanner's own top-left corner, kept
# clear today only because NameLabel's centered text happens to leave
# that corner empty. Checked headlessly (real font metrics + circle-vs-
# text-bbox distance, not eyeballed) against every shipped card name at
# a candidate 54px: "Kept Warmth" moved from a 5.5px clearance to
# actually overlapping (-2.5px), and the next-widest two-word names
# ("Held Position", "Second Wind") were left barely clearing - real,
# shipped card names, not a hypothetical. Cost's font
# size (28, up from 24) does NOT depend on this value - the badge's
# footprint is diameter-driven, the glyph inside it is font-driven, and
# growing the glyph alone (with a still-positive 3.5px clearance to the
# badge's own edge - was 6.0px at the old font size) gets the size
# dominance this pass wants with zero change to the collision margin
# against any existing card name. If a future card name needs to be
# longer AND the badge needs to grow too, that's a real tradeoff to
# make deliberately then (smaller badge, a name-side inset, or shrinking
# name_font_size_px) - not something to eyeball now for a badge size
# this pass turned out not to need.
@export var cost_badge_margin_px: float = 43.0

@export_group("Cost Pip")
@export var cost_pip_scenes: Dictionary[int, PackedScene] = {}
# Cost value -> a PackedScene of hand-drawn Polygon2D art (2026-08-29,
# scene-cost-pip pass) - see card_cost_pip.tscn, the "1" variant, copied
# independently from pip.gd's own CoinIcon as a starting point per this
# pass's own brief (2, 3, 4 are meant to follow the same pattern later,
# each its own scene, not baked into this one). Checked BEFORE cost_pip_
# textures below in _update_cost_display() - a scene entry wins over a
# texture entry for the same cost if both somehow exist, since a hand-
# drawn vector pip is the more finished asset of the two, same "DATA, not
# a match statement" shape cost_pip_textures itself already established.
# Every scene here is expected to follow the exact structure card_cost_
# pip.tscn already does - a root Control with a Visual/CoinIcon Node2D
# holding the actual hand-drawn polygon - since _fit_cost_pip_scene()
# below reaches into that exact path, mirroring pip.gd's own _fit_coin_
# icon()/VisualBounds.compute() technique for fitting a hand-drawn shape
# of unknown raw coordinate scale into a fixed target footprint (see
# that function's own doc for why the same reuse, not a new mechanism).
@export var cost_pip_textures: Dictionary[int, Texture2D] = {}
# Cost value -> texture (2026-08-29, texture-cost-pip pass) - DATA, not a
# match statement, so a new authored cost value is a one-line Inspector
# edit here, never a code change (this pass's own brief). A key with no
# entry (or an explicit null) falls back to the procedural circle+numeral
# CostBadge/CostLabel already were - see _update_cost_display() below -
# an unauthored cost stays fully playable and legible, never renders
# nothing. Costs 0-3 are what the deck actually uses today (Advance/Come
# To at 0, Kept Warmth at 3), but this dict is never assumed to cover
# exactly that range anywhere in code - any int key works, any gap in it
# just falls back for that one value. Placeholder textures for 0-3 live
# in assets/ui/cost_pips/ (generated, not hand-drawn - throwaway until
# real engraved art replaces them) and are wired in as this instance's
# own override on card.tscn's root Card node, not a script-level default,
# same "content lives in the scene, not the script" split art_texture's
# own CardData.art_texture field already follows.
@export var cost_pip_size_px: float = 46.0
# Independent of cost_badge_diameter_px on purpose - the two currently
# default to the same value so the pip occupies exactly the old badge's
# footprint with nothing else in the header shifting (this pass's own
# brief), but engraved artwork arriving later may want different
# proportions than a flat circle, and shouldn't need cost_badge_
# diameter_px (which still drives the FALLBACK circle, and the drain
# badge's own derived size - see that export's own doc) to change along
# with it. The margin/position stays shared with CostBadge regardless
# (see _apply_layout() below) - only the SIZE is independently tunable.

@export var cost_pip_offset_px: Vector2 = Vector2.ZERO
# The easy placement knob (2026-08-29, pip-placement pass) - same shape
# attack_hp_drain_offset_px above already establishes: a plain positional
# nudge, added AFTER the derived badge_margin position below, independent
# of the size/margin math entirely, so fine-tuning position never means
# threading a new number through that formula. Positive x moves right,
# positive y moves down - same sign convention as attack_hp_drain_
# offset_px's own left-anchored offsets (CostBadge/CostPip/CostPipScene
# are all un-anchored/top-left in card.tscn, same as that badge).
#
# Applied to CostBadge, CostPip, AND CostPipScene TOGETHER, not just
# whichever one happens to be visible right now - the three occupy the
# exact same slot and only one is ever shown per card (see _update_cost_
# display()'s own priority order), so nudging only the currently-visible
# one would silently un-nudge itself the moment a different card (a
# different cost, hitting a different branch of that priority order)
# swapped which of the three is showing. One offset, applied to all
# three positions identically, is what keeps the nudge stable regardless
# of which branch ends up on screen.

@export_group("Attack HP Drain Indicator")
@export_range(0.1, 2.0, 0.01) var attack_hp_drain_scale_relative_to_cost: float = 0.65
# REWORKED (2026-08-28, drain-badge-review pass) from two independent
# absolute-pixel exports (attack_hp_drain_diameter_px/_font_size_px) into
# ONE ratio against CostBadge's own size - a circular plate, same shape
# as CostBadge, not just a colored number floating over ArtSlot. "The
# energy cost is the right reference for scale - this is also a cost"
# (the original drain-badge legibility pass's own brief) used to be
# satisfied by picking a diameter that happened to sit CLOSE to cost_
# badge_diameter_px and hoping the two stayed in proportion across future
# retunes of either - they didn't (RemovalMarker's removal freed this
# badge to move, and it got hand-tuned smaller/repositioned in the editor
# without a matching cost_badge_diameter_px change, the exact drift this
# rework closes). Now genuinely DERIVED: drain_size = cost_badge_diameter
# _px * this ratio, and the label's own font size scales the identical
# way against cost_font_size_px (see _apply_layout() below) - retuning
# CostBadge's own size/font moves this badge's size/font with it
# automatically, and the ONE knob that controls "how big is this relative
# to the cost badge" is this export, not two numbers that have to be
# kept in sync by hand. 0.65 is a starting point (this badge reads as a
# secondary cost, smaller than the primary energy cost) - retune by eye
# like everything else in this group.
#
# The gap between the two badges is likewise no longer its own export -
# see _apply_layout() below, which reuses cost_badge_margin_px directly
# as that gap, so both stay visually consistent without a second number
# to keep matched.
@export var attack_hp_drain_offset_px: Vector2 = Vector2.ZERO
# The easy placement knob (2026-08-28, drain-badge-placement pass) - the
# badge's BASE position is directly to the right of CostBadge, vertically
# centered on it (see _apply_layout() below, unchanged by this doc), but
# this Vector2 nudges it from there afterward, independent of anything
# cost-badge-related: positive x moves it further right (away from
# CostBadge), positive y moves it further down. Signs match the LEFT-
# anchored offsets _apply_layout() now sets (anchor_left/right both 0.0
# in card.tscn) - REVERSED from this badge's old right-anchored days,
# where positive x used to mean "further left" instead; if this ever
# reads backwards, check which edge the badge is anchored to before
# assuming the export itself is wrong. One field, drag both numbers in
# the Inspector, done - no need to touch cost_badge_margin_px (which
# would also move CostBadge) or re-derive a second gap formula to
# reposition just this badge. Applied in _apply_layout() AFTER the
# derived beside-cost-badge position, scaled by `f` like every other px
# export here, so it holds the same relative nudge at every card size
# (hand, reward screen, deck viewer). Zero by default - this is a pure
# addition on top of the existing derived placement, so
# leaving it untouched changes nothing.
@export var attack_hp_drain_number_color: Color = Color(0.95, 0.3, 0.3, 1)
@export var attack_hp_drain_plate_color: Color = Color(0.08, 0.08, 0.08, 1)
@export var attack_hp_drain_border_color: Color = Color(0.85, 0.15, 0.15, 1)
# Dark plate + red border/numeral, not red text alone (this pass's own
# brief, point 3: "Consider a background plate or outline behind the
# number rather than relying on the numeral color alone - the same
# problem BlockBadge solves with a filled plate and dark frame"). A
# near-black plate reads at strong contrast against EVERY card_type
# color this face uses (see CARD_TYPE_ART_COLORS in card.gd), including
# ATTACK's own red-brown - the specific case red-on-red used to
# disappear into. The "-" prefix set_attack_hp_drain() below already
# builds into the label text is what satisfies point 4 ("make sure it
# reads as a cost rather than damage") - a minus sign plus a dark cost-
# plate is the same visual grammar this face's OTHER costs already use
# (CostBadge itself is a plate with a number, not bare text), just
# recolored for "this cost is being taken FROM you," not spent
# willingly. No icon (HP drop, skull, etc.) - BlockBadge's own header
# comment documents exactly why one was tried and removed there: at a
# small badge's size, an icon crowds out the one thing that actually
# carries the number's magnitude, which is the number itself.
@export var attack_hp_drain_border_width_px: float = 2.0

@export_group("Card Fonts")
@export var name_font_size_px: int = 22
@export var description_font_size_px: int = 15
@export var cost_font_size_px: int = 28
@export var chain_role_font_size_px: int = 10
@export var chain_role_gap_px: float = 5.0
# Vertical space between the rules text and the Opener/Closer tag below
# it (2026-08-27, legibility pass) - inserted as a blank BBCode line at
# this height (scaled by _scale_factor, same as chain_role_font_size_px
# itself) in _chain_role_suffix() below, since RichTextLabel has no
# native "space before this line" property of its own; a blank line's
# own [font_size] is the standard way to get a controlled gap in BBCode.
# Previously just a bare "\n" with no dedicated control - the tag read
# as a trailing line of the rules text rather than a distinct label,
# which color alone (see HudPalette.SYSTEM_TEXT's own doc) can't fix on
# its own once the two are already the same tone.
@export var removal_scope_font_size_px: int = 10
@export var removal_scope_gap_px: float = 5.0
@export var removal_scope_text_color: Color = Color(0.22, 0.24, 0.29, 1)
# The generated "Spent"/"Consumed" rules-text line (2026-08-28, badge-
# removal pass - REPLACES the old RemovalMarker corner badge entirely,
# see _removal_scope_suffix() below and DESIGN.md's own note on why: the
# badge collided with longer card names and read as disabled at its own
# deliberately low contrast). SAME technique as chain_role_font_size_px/
# chain_role_gap_px right above - a blank [font_size=gap] spacer line,
# then the keyword at its own smaller size - not the shared [keyword] BB
# Code tag card_text_styles.gd defines, on purpose: this is a secondary
# annotation below the card's primary rules text, same standing as
# Opener/Closer, and should read with the SAME weight they do rather
# than inventing a second "secondary annotation" visual language.
# Independent exports rather than literally reusing chain_role_font_
# size_px/_gap_px - the two tags are conceptually unrelated (one's a
# permanent property of the card, one's a live combat-chain state) and
# may want to be tuned apart later, even though they start identical.
# removal_scope_text_color's default (0.22, 0.24, 0.29) matches HudPalette.
# SYSTEM_TEXT's OWN current value exactly, but is its own independent
# literal - same "tune it by eye in the Inspector without dragging
# another color along with it" reasoning attack_hp_drain_plate_color's
# own doc already established for its badge.
# --- Information hierarchy (2026-08-25) ---
#
# Cost is the primary scan across a hand ("what can I afford"), name is
# second ("what is this"), everything else - description/rules text,
# the removal-scope keyword, the chain-role suffix - is tertiary. Three
# levers establish that, all @export so a retune never means hunting
# through this script for a hardcoded Label property:
#   1. SIZE - cost_font_size_px above (28, was 24) is now clearly the
#      largest text on the face, well past name_font_size_px (22).
#      cost_badge_diameter_px deliberately stays 46 (unchanged) - see
#      that export's own note for why growing the badge, not just the
#      font, was verified and rejected.
#   2. FONT FAMILY - name_font below switches the name to Spectral, the
#      same world-voice serif title_screen.gd/weapon_pickup_window.gd
#      already use for character-facing text; cost and description stay
#      on Godot's default sans (system voice), unchanged.
#   4. WEIGHT (2026-08-29, name-weight pass) - see name_font's own doc
#      below for why Bold, not Medium/SemiBold.
#   3. COLOR/CONTRAST - cost_font_color stays near-black (max contrast,
#      unchanged from its old value); name_font_color moves to a warm
#      ink, visibly a step down from cost without going muted, since
#      the name is still meant to be the most CHARACTERFUL text on the
#      card, just not the loudest; the rules text (HudPalette.SYSTEM_
#      TEXT - see its own doc) moves off pure black to an actually-muted
#      slate.
@export var name_font: Font = preload("res://assets/fonts/Spectral-SemiBold.ttf")
# SEMIBOLD, not Bold (2026-08-29, name-weight pass, updated same pass
# once Spectral-SemiBold.ttf was added to assets/fonts/ - Medium still
# isn't vendored). One line to swap back to Spectral-Bold.ttf (still
# present) or point at Spectral-Medium.ttf once that file exists too -
# same one-line change either direction, nothing else in this file
# depends on which weight this resolves to.
# Deliberately NOT faked with an outline/shadow (this pass's own brief) -
# a real heavier weight redraws every stroke thicker at its own design
# metrics; an outline just outlines the SAME thin strokes, which reads
# as a different (and worse) effect entirely, not a stand-in for weight.
# ONLY affects name_label (see _apply_layout()'s own font override
# below) - description_label/cost_label never take a Spectral override
# at all (see FONT FAMILY above), so body text and the cost numeral are
# structurally untouched by this, not just left alone by convention.
@export var name_font_color: Color = Color(0.22, 0.13, 0.06, 1)
# Warm dark ink, not neutral near-black - shipped alongside the
# script's old near-black value (still on cost_font_color below) so the
# two can be A/B'd directly in-engine before committing to this one.
@export var cost_font_color: Color = Color(0.038397167, 0.038397167, 0.03839716, 1)
# Unchanged from the value previously baked into card.tscn's CostLabel -
# already near-black, already the highest-contrast text on the card, so
# establishing cost as the loudest element needed a size increase, not
# a color change. Pulled out to an @export here (was hardcoded directly
# on the Label node) so it's tunable the same way every other card-face
# color now is, not a special case.
#
# The rules text and the "Opener"/"Closer" tag _chain_role_suffix()
# appends below it BOTH read HudPalette.SYSTEM_TEXT directly now
# (2026-08-27, HudPalette migration - see that entry's own doc for the
# color value/history and why this moved off a per-script export).
# There's no local @export mirroring it here on purpose, same "direct-
# read consumer" pattern vitals_bar.gd already follows for HudPalette.
# FILL/TROUGH - no card has ever needed its own override, and a local
# export that could silently drift from the shared value is exactly
# the bug this migration exists to prevent (see HudPalette.SYSTEM_TEXT's
# own doc for the drift it already caused once). The tag stays smaller
# than description_font_size_px (chain_role_font_size_px above) so it
# reads as a secondary annotation, not the card's primary information -
# see _chain_role_suffix()'s own note for why this can't just reuse
# CardTextStyles' shared [keyword] tag (still bold and full-size,
# correctly so for an inline rules term like Kept Warmth's "Consumed").
#
# DescriptionLabel's FONT stays completely unset here - see that
# @onready var's own note for why that's flagged as an open question,
# not a decision.

# --- Panel colors (2026-08-25, warm-paper pass) ---
#
# Every value here used to be a bg_color/border_color baked directly
# into a StyleBoxFlat sub-resource in card.tscn - not tunable the way
# fonts already were, and not touched by any script. Pulled out here so
# a retune is an Inspector value, not a .tscn edit, same reasoning as
# the text colors that moved into "Card Fonts" above. All PROVISIONAL -
# first pass at "warm paper," not a final palette.
#
# The move: gray-blue (the old body sat in the same cool family as the
# Sunken Works sky/concrete - see battle_background.gd's SunkenWorks
# Palette.SKY_HIGH/SKY_HORIZON, which is what a hand actually renders
# against - so the hand read as part of that backdrop, not an object
# held in front of it) to a warm, light paper/bone register instead,
# with each zone given its own clearly separated VALUE (not just a
# thin border line) so Name/Art/Description read as distinct regions
# sitting on that paper rather than one flat surface.
@export_group("Card Colors")
@export var card_body_color: Color = Color(0.867, 0.845, 0.796, 1)
# Warm bone/paper, replacing Visual's old (0.849, 0.884, 0.920) gray-
# blue - deliberately kept LIGHT (this is aged paper, not leather or
# parchment brown) and close to the old value's own luminance, so the
# card face reads as bright, not muddy or dim - only the HUE moved.
# COOLED (2026-09-07, neutral-placeholder pass) from (0.89, 0.845,
# 0.735) - this was the single most chromatic thing on the card face
# next to the old per-type art fills (+39.5 R-B at standard luma
# ~0.846), and stayed gold even once those fills went neutral. R and B
# moved in opposite, unequal amounts (R down 0.023, B up 0.061 - not a
# straight swap) specifically so standard luma (0.299R+0.587G+0.114B)
# lands back at ~0.846, the same value as before - only R-B moved (39.5
# -> ~18), not brightness. G untouched.
@export var name_banner_color: Color = Color(0.803, 0.78, 0.737, 1)
# COOLED (2026-09-07, gold-off follow-up to d855888) from (0.84, 0.78,
# 0.64) - d855888 only touched card_body_color (Visual's own bg); this
# zone's fill was untouched and stayed the most chromatic cream surface
# on the card (+51 R-B, live-measured against a +18 report for the
# frame - the two were never the same surface). R and B moved, G held,
# landing at +17 R-B with standard luma unchanged (~0.782 -> ~0.782), so
# only hue moved, not brightness - same method d855888 used on
# card_body_color.
@export var name_banner_border_color: Color = Color(0.62, 0.55, 0.42, 1)
# A step down from card_body_color, unchanged since the warm-paper pass
# - not implicated in either correction below.
@export var art_slot_color: Color = Color(0.903, 0.885, 0.836, 1)
# COOLED (2026-09-07, gold-off follow-up to d855888) from (0.92, 0.885,
# 0.79, +33 R-B) - same treatment as name_banner_color/description_
# panel_color's own doc: R and B moved, G held, landing at +17 R-B with
# standard luma unchanged (~0.885), so this stays the lightest fill on
# the face (see this export's own doc above on why that ordering
# matters) at a cooler hue, not a darker or lighter one.
@export var art_slot_border_color: Color = Color(0.8, 0.76, 0.66, 1)
# CORRECTED (2026-08-25, second pass) - the warm-paper pass first tried
# ArtSlot as the DEEPEST inset (0.7, 0.64, 0.52, matching the old gray-
# blue palette's own "art slot is always the darkest zone" ordering).
# Verified in-engine and confirmed wrong for THIS card: with cost/name
# now established as the face's primary/secondary scan (see "Information
# hierarchy" note in Card Fonts above) and most of the pool sitting in
# the empty-art state for a long time yet, a dark, heavy ArtSlot read as
# the single heaviest thing on the card - outweighing both cost and
# name, exactly backwards. Flipped to slightly LIGHTER than card_body_
# color instead (was a large step darker) so an empty slot reads as
# reserved/pending space, not a filled panel competing for attention -
# the target order, heaviest to lightest, is cost badge > name >
# description text > art slot. Border lightened to match (was 0.55,
# 0.49, 0.38, tuned for contrast against the old DARK fill - unchanged,
# it would now be the boldest line on the card, recreating the same
# dominance problem in the border instead of the fill); this is now the
# lightest, quietest fill+border pairing on the whole face on purpose.
# NO LONGER just a pre-card_data default (2026-08-29, inner-border-
# removal pass) - used to get overridden dynamically by _update_rarity_
# border() once real card_data was set (2026-08-27, border swap); that
# call is disconnected now (see _update_rarity_border()'s own doc for
# why it's kept but unused), so THIS is simply ArtSlot's border color,
# full stop, for every card regardless of rarity - the flat, non-rarity
# edge the art panel keeps to define itself against the card stock.
@export var description_panel_color: Color = Color(0.8, 0.78, 0.733, 1)
# COOLED (2026-09-07, gold-off follow-up to d855888) from (0.82, 0.78,
# 0.68, +35.7 R-B) - same R/B-shift-with-G-held method as name_banner_
# color/art_slot_color's own docs. Standard luma held at ~0.781 (was
# 0.7806) DELIBERATELY, not incidentally - HudPalette.SYSTEM_TEXT's own
# doc measures its text contrast against this EXACT panel color and
# says to re-check that figure if this color ever changes; holding luma
# this close keeps that WCAG contrast reading effectively where it was,
# so this pass doesn't owe SYSTEM_TEXT a re-check of its own.
@export var description_panel_border_color: Color = Color(0.62, 0.55, 0.42, 1)
# CORRECTED (2026-08-25, second pass) - the warm-paper pass first tried
# LIGHTER than card_body_color (0.95, 0.925, 0.86), reasoning that the
# dark muted description_font_color needed a bright surface for
# contrast. That measured a clean ~6.7:1 but was verified in-engine to
# still LOOK like the same surface as the body - a ~0.08 simple-luma
# gap between two near-white warm tones just isn't perceptible, however
# good the text contrast math behind it is.
#
# Flipped to DARKER per this correction's own steer, but the honest
# finding from scanning the whole safe range: going darker does NOT
# buy a bigger gap here. description_font_color (0.3, 0.32, 0.37) is
# dark enough that its OWN 4.5:1 AA floor caps how far this panel can
# drop - past roughly a 0.08 simple-luma gap below card_body_color, the
# text's own contrast starts failing before the panel gets meaningfully
# more "separated" by the numbers. This value (0.065 gap, ~4.68:1) sits
# right at that same ceiling, not further past it - the same raw
# distance as the rejected lighter attempt, just in the other
# direction. The reason this direction is still worth using over the
# lighter one: a darker fill reads as a recessed inset (a real depth
# cue independent of the raw luminance delta), where a similarly-sized
# lighter fill just reads as "a bit brighter," which is a much weaker
# signal at the same numeric gap - if this still doesn't read as
# separated once seen live, that's this text color's contrast ceiling
# talking, not a value picked too conservatively, and the real fix
# would be a border/inset treatment rather than another fill nudge.
# border_color unchanged from the first pass (0.62, 0.55, 0.42) - still
# clearly darker than this fill (simple luma ~0.56 vs ~0.78), a normal
# frame-darker-than-fill relationship either way the fill moved.

# --- Chain glow (see card_data.gd's own chaining note - minimum
# viable prototype) ---
#
# An eligible Closer's ENTIRE indication that a chain is LIVE RIGHT NOW
# - see _chain_role_suffix()'s note for the separate, static "Closer"
# role label, which never changes with chain state and isn't what this
# glow is for. Originally a hard-edged border ring; playtesting found that too
# easy to miss and too similar to the hover state and the rarity
# border - both already-crowded "ring around the card" channels. Two
# changes fixed that:
#
# 1. A soft SHADOW instead of a border - StyleBoxFlat's own shadow_
# color/shadow_size (see card.tscn's ChainGlow - now sized to exactly
# match Visual's own rect, since the shadow blurs OUTWARD from that
# rect on its own; no more manual oversize/offset math to push a ring
# past Visual's edge). Reads as light spilling out from behind the
# card, not a line drawn around it - genuinely distinct from both the
# hard-edged rarity border and the hover state (which never drew a
# border at all, just moves the card).
#
# 2. A slow pulse (see set_chain_available() below) - motion is what
# actually catches the eye during play, and what makes this read as
# "alive" rather than a static decoration a busy hand can blend into.
# Same "kill and restart from wherever it is" infinite-loop tween shape
# as vitals_bar.gd's own low-HP pulse (_start_pulse()) - deliberately
# reusing that exact pattern rather than inventing a second one.
#
# Both live on chain_glow, a child of Visual (see its own onready note
# below) - hover/armed lift the card, the pulse breathes on top of
# that same lifted position, and neither fights the other since they
# animate different properties (position/scale vs. modulate:a).
@export_group("Chain Glow")
@export var chain_glow_color: Color = Color(0.95, 0.65, 0.25, 1)
# Same amber as CardTextStyles' "modified" style and enemy.gd's chain
# impact burst (see its own note) - one color vocabulary for "chain"
# across the whole feature, not a new one just for this.
@export_range(0.0, 1.0, 0.01) var chain_glow_intensity: float = 0.95
# The glow's OWN peak alpha (shadow_color's own alpha channel) - kept
# separate from the color picker's alpha for the same reason OverlayStyle
# keeps outline_opacity separate from outline_color: a dedicated slider
# is what an actual retune reaches for, a color picker's alpha corner is
# easy to miss.
@export var chain_glow_spread_px: float = 18.0
# How far the shadow blurs outward from the card's own edge - bigger
# reads as more of a glow "bleeding" past the card, smaller reads as
# tighter/closer to an outline. Godot's own StyleBoxFlat shadow blur
# radius, nothing custom.
@export var chain_glow_pulse_period_sec: float = 1.1
# Length of ONE leg of the breathe (dip, or rise back) - a full cycle
# is twice this. Same naming/shape as vitals_bar.gd's own low_hp_pulse_
# period_sec. Slow on purpose ("gentle... not flashing," per the brief)
# - fast enough to visibly be in motion, slow enough to read as a
# breathing glow, not an alert blinking.
const CHAIN_GLOW_PULSE_DIP := 0.4
# How far the pulse dips below chain_glow_intensity's own peak (as a
# fraction of it, same shape as vitals_bar.gd's low_hp_pulse_alpha_dip)
# - not its own export, since the brief asks for exactly four tunables
# (speed, intensity, spread, color); this is "how breathy," a fixed
# character of the effect rather than a per-tuning-pass knob.

@onready var chain_glow: Panel = $Visual/ChainGlow
# A child of Visual, not a sibling (see card.tscn) - hover/armed/refusal
# animations (_play_hover_tween(), play_refused()) only ever animate
# Visual's own position/scale/rotation, never a second node in parallel
# (see this script's own header note on why hover/armed share one
# tween). Nesting ChainGlow under Visual is what makes it inherit that
# same transform for free - Godot combines a child's own local
# transform with its parent's, so the glow rises/scales/shakes exactly
# in step with the card face without this script animating it
# separately or fighting the existing tweens over the same properties.

# --- Condition Indicator (2026-08-27 - see DESIGN.md's own note on the
# active-state-indicator pass) ---
#
# Signals "this card's conditional effect is live right now" (Compound's
# Toll>=15 today - see battle.gd's _card_condition_active()) two ways at
# once, both driven by set_condition_active() below:
#   1. The rules text itself re-weights (see _refresh_description_text()
#      and card_text_styles.gd's own expand_conditional()) - the active
#      number goes bright+bold, the inactive one dims, NEITHER is ever
#      removed or replaced (this pass's own DESIGN note: the conditional
#      STRUCTURE has to stay visible so the player can plan toward the
#      threshold, not just read the live value).
#   2. condition_frame below, a quiet border toggle - see its own note.
@export var condition_active_value_color: Color = Color(0.14, 0.1, 0.02, 1)
# The emphasized number's color once the condition is active - dark and
# warm (this card face's own ink family - see name_font_color's own
# "Card Fonts" note above), NOT the frame's cool accent below: emphasis
# here is bold + a slightly richer ink than the rules text's own muted
# HudPalette.SYSTEM_TEXT, not a second hue competing with the frame
# signal for attention.
@export_range(0.0, 1.0, 0.01) var condition_inactive_value_dim_alpha: float = 0.4
# How much the NOW-INACTIVE number fades once the condition activates -
# an alpha multiply on top of the rules text's own normal color
# (HudPalette.SYSTEM_TEXT), same "dim via alpha, not a second hardcoded
# color" shape card.gd's own zero-state/unaffordable treatments already
# use elsewhere in this project, rather than inventing a fifth muted tone
# just for this.
@export var condition_frame_color: Color = Color(0.85, 0.15, 0.4, 1)
# CORRECTED (2026-08-27, live-play fix): the ORIGINAL brief here picked a
# cool teal specifically to avoid colliding with ARMED_MODULATE's warm
# gold. That axis turned out to be wrong in practice - RARITY_BORDER_
# COLORS[RARE] (card.gd's own dict, above) is a prominent, saturated
# BLUE, and Compound is RARE, so a cool teal frame sat directly beside
# (and, worse, blended into - see condition_frame's own doc on the
# overlap bug this pass also fixed) a card border already in the same
# cool family. A vivid crimson/magenta clears BOTH signals it has to stay
# clear of: nowhere near RARE's blue, and nowhere near ARMED_MODULATE's
# gold even after that modulate multiplies it (a saturated magenta stays
# reddish-pink under a warm tint, never reading as "more gold").
@export_range(0.0, 1.0, 0.01) var condition_frame_intensity: float = 0.92
# The frame border's own peak alpha - RAISED substantially (was 0.6) per
# this same live-play fix: this is the PRIMARY signal for "this card's
# condition is active right now," with the text re-weighting (see this
# group's own header) as secondary support, not the other way around -
# it needs to read at a glance while scanning a hand, not reward a close
# look. Separate slider from the color picker's own alpha corner, same
# "a dedicated intensity knob is what an actual retune reaches for"
# reasoning chain_glow_intensity already established for its own peak
# alpha.
@export var condition_frame_width_px: float = 4.0
# Border thickness, scaled by _scale_factor like every other per-instance
# pixel value on this card. Widened slightly (was 3.0) alongside the
# expand fix below - a signal to notice while scanning the hand, not a
# second rarity border, but no longer required to stay whisper-thin now
# that condition_frame_expand_px keeps it out of the rarity border's own
# pixels entirely.
@export var condition_frame_expand_px: float = 5.0
# NEW (2026-08-27, live-play fix): how far the frame's own rect extends
# BEYOND Visual's outer edge, in every direction - see _apply_layout()'s
# own application of this to condition_frame's offsets. Root-caused, not
# just retuned: condition_frame used to share Visual's EXACT rect, so its
# border drew directly ON TOP of Visual's own rarity border (StyleBoxFlat_
# default, 4px, opaque) - a second, THINNER, semi-transparent border
# stacked in the identical pixel band as an opaque one underneath mostly
# just tints that existing border rather than reading as a separate
# element, which is why it reported as invisible in live play despite
# condition_frame.visible genuinely being true (confirmed headlessly -
# this was a rendering/compositing problem, not a toggle-wiring bug).
# Expanding the rect outward moves the whole ring onto its OWN pixels,
# clear of the rarity border, the same "extends outward, never overlaps
# the border" relationship chain_glow's own shadow already has with it -
# just via a wider rect instead of a blurred shadow, since this stays a
# hard-edged border by design (see condition_frame's own doc on why it's
# a different MECHANISM from chain_glow, not just a different color).

@onready var condition_frame: Panel = $Visual/ConditionFrame
# A THIRD sibling under Visual, after chain_glow (see card.tscn) -
# deliberately NOT sharing chain_glow's own node or mechanism. chain_glow
# is a soft, PULSING drop-shadow (StyleBoxFlat.shadow_color) meaning
# "a chain is live right now"; this is a static, BORDER-only StyleBoxFlat
# (transparent fill, colored border, no shadow, no pulse) meaning
# something else entirely. Different mechanism (border vs. shadow) AND
# different node (never toggled by the same call) is what keeps "chain
# live" and "condition active" from ever reading as the same signal at
# two intensities, the same separation concern condition_frame_color's
# own doc raises against ARMED_MODULATE.
@onready var visual: Panel = $Visual
@onready var frame: MarginContainer = $Visual/Frame
@onready var zones: VBoxContainer = $Visual/Frame/Zones
@onready var name_banner: PanelContainer = $Visual/Frame/Zones/NameBanner
@onready var name_label: Label = $Visual/Frame/Zones/NameBanner/NameLabel
@onready var art_slot: PanelContainer = $Visual/Frame/Zones/ArtSlot
# Earlier in ArtSlot's own child order than art_texture below (see card.
# tscn) - PanelContainer fits EVERY child to the same content rect
# independently, rather than laying siblings out one after another, so
# ordering is what decides draw order (later siblings draw on top), not
# position. Always visible (unlike art_texture's own hide-when-null
# toggle - see _update_art_texture()'s own doc) - a card with no art
# still shows its card_type's own color; the texture is what layers ON
# TOP of it once one exists, never a replacement for it.
@onready var art_type_fill: ColorRect = $Visual/Frame/Zones/ArtSlot/ArtTypeFill
@onready var art_texture: TextureRect = $Visual/Frame/Zones/ArtSlot/ArtTexture
# A plain Control, no visual of its own (no stylebox, no children) - see
# art_description_gap_extra_px's own doc for why this exists at all.
# Sits between ArtSlot and DescriptionPanel in Zones' tree order so its
# own custom_minimum_size.y (see _apply_layout()) becomes real vertical
# space specifically at THAT boundary, not the Name-Art one.
@onready var art_description_gap_spacer: Control = $Visual/Frame/Zones/ArtDescriptionGapSpacer

# The description overflow fix (2026-08-25 - see this file's own class-
# level "Card face structure" note), both halves of it living on THIS
# node specifically:
#
# 1. Protects Zones' own layout math. A plain Control, not a Container,
#    so its reported minimum size to Zones is always its own custom_
#    minimum_size (never set - stays (0,0)) regardless of what Description
#    Panel/DescriptionLabel inside it actually want. Zones only ever asks
#    THIS node for a minimum size and only ever assigns THIS node a rect
#    (via size_flags_stretch_ratio - see _apply_layout(), which now sets
#    that ratio here instead of on description_panel) - a long
#    description growing DescriptionLabel's own fit_content-driven
#    minimum size (Retaliation, today) can no longer be seen by Zones at
#    all, so it can never steal ratio-space from ArtSlot above it.
#
# 2. clip_contents = true (set in card.tscn, not here - a static
#    property, not something _apply_layout() ever needs to touch per-
#    scale) actually crops the overflow. This has to live HERE, not on
#    description_panel below, for a real reason verified by hand, not
#    assumed: a Control's ACTUAL size can never drop below its own
#    combined minimum size, even when anchored to "fill" a smaller
#    parent - description_panel, still a PanelContainer reporting
#    DescriptionLabel's inflated minimum upward, still visibly grows past
#    THIS node's own stable rect for a long description (confirmed:
#    Retaliation measured 8px taller than its allotted space, symmetric
#    top+bottom, matching Godot's own "expand from center when forced
#    above minimum" behavior) - clip_contents on description_panel itself
#    would only crop at THAT already-grown size, not at the actually-
#    stable size this node guarantees. This node's own size is the one
#    guarantee nothing below it can inflate, so it's the one place
#    "clip, not expand" can actually be enforced.
@onready var description_clip: Control = $Visual/Frame/Zones/DescriptionClip
@onready var description_panel: PanelContainer = $Visual/Frame/Zones/DescriptionClip/DescriptionPanel
# Free to grow internally to fit DescriptionLabel's own fit_content-driven
# size (unchanged behavior, still centers short text via SHRINK_CENTER
# exactly as before this fix) - description_clip's own clip_contents
# above is what keeps that growth from ever being seen on screen or by
# Zones' layout, not anything set on this node.
# RichTextLabel, not Label - see card_text_styles.gd for why (inline
# BBCode + a small named-style layer on top of it).
#
# Renders on Godot's built-in default font, no override anywhere on
# this node or in _apply_layout() below - unlike name_label, which now
# gets an explicit Spectral override (see name_font's own doc). That's
# NOT a deliberate "description is system-voice sans" choice, just the
# absence of one: nothing in this file or card.tscn has ever assigned
# it a font. The two-register split this pass builds (world-voice serif
# name vs. system-voice sans everything else) currently rests on that
# default happening to already be sans, not on an actual decision - a
# real system font (weight, family) for this half of the split is still
# open, flagged here rather than picked silently.
@onready var description_label: RichTextLabel = $Visual/Frame/Zones/DescriptionClip/DescriptionPanel/DescriptionLabel
@onready var cost_badge: Panel = $Visual/CostBadge
@onready var cost_label: Label = $Visual/CostBadge/CostLabel
@onready var cost_pip: TextureRect = $Visual/CostPip
@onready var cost_pip_scene_container: Control = $Visual/CostPipScene

var _cost_pip_scene_instance: Control = null
# The currently-instanced hand-drawn pip scene (see cost_pip_scenes'/
# _update_cost_display()'s own doc), if any - tracked so a cost change
# (or a card reused for a different cost) can free the OLD instance
# before adding a new one, rather than stacking instances inside
# cost_pip_scene_container forever. null whenever the current cost has
# no scene entry (texture or fallback path instead).
@onready var attack_hp_drain_badge: Panel = $Visual/AttackHpDrainBadge
@onready var attack_hp_drain_label: Label = $Visual/AttackHpDrainBadge/AttackHpDrainLabel

# Holds whichever hover animation is currently playing, so a new hover
# event can stop an old, still-running one instead of fighting it. Starts
# empty (null) since nothing is animating yet. Also driven by set_armed()
# below - armed and hover share this ONE tween/var rather than each
# animating visual.position/.scale independently, which is exactly what
# would let them fight over those same two properties.
var _hover_tween: Tween

# Whether the card is currently "armed," waiting for battle.gd to
# resolve a target against it (see set_armed()) - not the same thing as
# hover (mouse-position-driven, transient); a card can be armed while
# the mouse is somewhere else entirely, e.g. hovering the enemy the
# player's about to click.
var _armed: bool = false

# True while the mouse is actually over this card right now - tracked
# explicitly (rather than inferred) so set_armed(false) knows whether to
# settle back to the resting pose or the hovered one.
var _is_hovered: bool = false

# True from place_at_draw_origin() until _finish_draw_arrival() (a
# natural finish OR a battle.gd-forced skip_draw_arrival()) - see that
# section's own doc, near set_fan_transform() below. set_fan_transform()
# reads this alongside _armed/_is_hovered so a LATER card's own arrival
# (which recomputes the WHOLE hand's fan - see battle.gd's _update_hand_
# fan()) can't stomp a card that's still mid-flight with a nonsensical
# snap-to-local-offset while its `visual` is top_level (an absolute
# screen point, not a hand-relative one).
var _is_dealing: bool = false
var _arrival_tween: Tween

# True from a genuine LEFT-button press on this card until either its
# matching release (a real click - see _gui_input()) or the mouse leaving
# before release (a drag-off, cancelled - see _on_mouse_exited()). This
# is what makes a click require press-AND-release on the same card,
# rather than firing on press alone - which used to also fire on a mouse-
# wheel scroll tick (InputEventMouseButton with pressed briefly true on
# button_index WHEEL_UP/DOWN, not an actual click) whenever the cursor
# happened to be over a card while scrolling a container full of them
# (see deck_viewer.gd's card grid) - the bug this whole guard exists to
# close.
var _press_started_on_card: bool = false

# Same idea, for the refusal shake below.
var _shake_tween: Tween

# Whether THIS card is currently an eligible Closer in a live chain
# (see battle.gd's chain_empowered/_refresh_chain_indicators()) - only
# ever true for a CLOSER-role card, and only while Battle says so. This
# card doesn't decide chain rules any more than it decides energy
# affordability (see set_affordable() above) - Battle just tells it the
# answer via set_chain_available() below, and chain_glow (see card.tscn)
# is the only thing that turns it into something visible. Purely a
# visual toggle now, not text - see _chain_role_suffix()'s own note for
# why the closer's card face carries no chain state in words anymore.
var _chain_available: bool = false
var _condition_active: bool = false
# Read by _refresh_description_text() (see card_text_styles.gd's own
# expand_conditional()) every time it rebuilds this card's text - set by
# set_condition_active() below, never written directly anywhere else.

# Same idea as _hover_tween/_shake_tween above - holds the pulse so a
# re-trigger (this card losing and regaining chain-available status
# quickly) can kill the old loop instead of stacking a second one.
var _chain_pulse_tween: Tween

# How much bigger than design_size this instance currently renders at -
# see set_scale_factor(). Applied inside _apply_layout(), which is what
# actually turns this number into real pixel values on the nodes above.
var _scale_factor: float = 1.0

# This card's own resting tilt (radians) and vertical arc offset (px) -
# 0/0 unless something calls set_fan_transform() (battle.gd's hand fan is
# the only caller today; every other context - deck viewer, reward
# screen, shop - never calls it, so those cards stay perfectly upright
# and unshifted, same as always). Stored separately from visual.rotation/
# position because the hover/armed tween below needs to know what to
# return TO on exit - see _play_hover_tween()'s own note.
var _fan_rotation: float = 0.0
var _fan_vertical_offset: float = 0.0

# card.tscn's three zone panels each carry their own StyleBoxFlat -
# shared resources straight out of the .tscn file, same as Visual's
# rarity-border stylebox (see _update_rarity_border()). Duplicated here,
# ONCE, into per-instance copies before _apply_layout() ever mutates
# their content_margin - otherwise resizing one card's padding would
# resize the padding on every OTHER card sharing that same resource.
var _name_banner_style: StyleBoxFlat
var _art_slot_style: StyleBoxFlat
var _description_panel_style: StyleBoxFlat
var _cost_badge_style: StyleBoxFlat
var _attack_hp_drain_style: StyleBoxFlat
var _chain_glow_style: StyleBoxFlat
# Visual's own body stylebox - duplicated the same way as the four
# above so card_body_color (see "Card Colors" group) can be applied
# per-instance without mutating the shared .tscn resource every other
# Card also starts from. _update_rarity_border() (called once card_data
# is set) duplicates THIS instance's already-colored copy again just to
# set border_color - the two never fight over the same field.
var _visual_style: StyleBoxFlat
var _condition_frame_style: StyleBoxFlat
# Same duplicate-before-mutating shape as every style above - condition_
# frame starts from a plain Panel default (no baked stylebox override in
# card.tscn, same "starts from Panel's own default theme" pattern block_
# badge.gd's own panel/vitals_bar.gd's own BarBorder already use), so
# this is what gives it a real border at all, not just what makes it
# per-instance-safe.

func _ready() -> void:
	# Every Control automatically fires "mouse_entered" and "mouse_exited"
	# the instant the cursor crosses into or out of its rectangle — Godot
	# checks this for us every frame, we don't have to poll for it. We just
	# connect our own functions to react, the same way battle.gd connects
	# to the Draw button's "pressed" signal.
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_own_zone_styles()
	_apply_layout()
	# COVER, not CONTAIN: card art isn't guaranteed to match the art slot's
	# own aspect ratio (see art_zone_stretch), and a contained image would
	# leave empty bars around it that read as a mistake, not intentional
	# framing - genre convention (this reads closer to how trading-card art
	# actually gets cropped) is to fill the slot edge-to-edge and let the
	# crop lose whatever doesn't fit, not letterbox. EXPAND_IGNORE_SIZE so
	# this never fights ArtSlot's own PanelContainer sizing with a minimum
	# size derived from the texture itself.
	art_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED

func _own_zone_styles() -> void:
	_name_banner_style = name_banner.get_theme_stylebox("panel").duplicate()
	_art_slot_style = art_slot.get_theme_stylebox("panel").duplicate()
	_description_panel_style = description_panel.get_theme_stylebox("panel").duplicate()
	_cost_badge_style = cost_badge.get_theme_stylebox("panel").duplicate()
	_attack_hp_drain_style = attack_hp_drain_badge.get_theme_stylebox("panel").duplicate()
	_chain_glow_style = chain_glow.get_theme_stylebox("panel").duplicate()
	_visual_style = visual.get_theme_stylebox("panel").duplicate()
	_condition_frame_style = condition_frame.get_theme_stylebox("panel").duplicate()
	_condition_frame_style.bg_color = Color(0, 0, 0, 0) # Border only, never a fill - see condition_frame's own doc.
	# Fixed border widths - see visual_border_width_px/art_slot_rarity_
	# border_width_px's own doc for why these are set once here and never
	# touched again in _apply_layout().
	var visual_border := roundi(visual_border_width_px)
	_visual_style.border_width_left = visual_border
	_visual_style.border_width_top = visual_border
	_visual_style.border_width_right = visual_border
	_visual_style.border_width_bottom = visual_border
	var art_slot_border := roundi(art_slot_rarity_border_width_px)
	_art_slot_style.border_width_left = art_slot_border
	_art_slot_style.border_width_top = art_slot_border
	_art_slot_style.border_width_right = art_slot_border
	_art_slot_style.border_width_bottom = art_slot_border
	# Fixed corner radii - see visual_corner_radius_px/art_slot_corner_
	# radius_px's own doc for why these are set once here, alongside the
	# border widths above, and never touched again in _apply_layout().
	var visual_radius := roundi(visual_corner_radius_px)
	_visual_style.corner_radius_top_left = visual_radius
	_visual_style.corner_radius_top_right = visual_radius
	_visual_style.corner_radius_bottom_right = visual_radius
	_visual_style.corner_radius_bottom_left = visual_radius
	var art_slot_radius := roundi(art_slot_corner_radius_px)
	_art_slot_style.corner_radius_top_left = art_slot_radius
	_art_slot_style.corner_radius_top_right = art_slot_radius
	_art_slot_style.corner_radius_bottom_right = art_slot_radius
	_art_slot_style.corner_radius_bottom_left = art_slot_radius
	name_banner.add_theme_stylebox_override("panel", _name_banner_style)
	art_slot.add_theme_stylebox_override("panel", _art_slot_style)
	description_panel.add_theme_stylebox_override("panel", _description_panel_style)
	cost_badge.add_theme_stylebox_override("panel", _cost_badge_style)
	attack_hp_drain_badge.add_theme_stylebox_override("panel", _attack_hp_drain_style)
	chain_glow.add_theme_stylebox_override("panel", _chain_glow_style)
	visual.add_theme_stylebox_override("panel", _visual_style)
	condition_frame.add_theme_stylebox_override("panel", _condition_frame_style)

# Rescales the whole card face to `factor` x design_size (1.0 = a hand
# card) - call once, right after instancing, before set_card_data().
# Every real caller today (reward_screen.gd, shop_window.gd, deck_
# viewer.gd) uses a factor in roughly the 1.0-1.6 range; hand cards
# never call this at all and simply render at their design_size,
# factor 1.0.
#
# BREAKS BELOW ROUGHLY f = 0.4 (2026-08-27, diagnosed via the NPC card
# offer's own proportions bug - see DESIGN.md's NPCs section for the
# full writeup) - NOT fixed here, since every other caller depends on
# this exact behavior at its own scale and this function's job is
# strictly re-layout, not border rendering. The root cause: every
# border width on the card face (the outer rarity border, and the
# name-banner/art-slot/description-panel borders) is a FIXED constant
# baked into card.tscn's own StyleBoxFlat resources - _apply_layout()
# below scales fonts, margins, badge sizes, and corner radii by `f`,
# but never touches border_width_*, so those borders stay the exact
# same pixel width regardless of `factor`. At f=1.0 a 4px outer border
# against a 10px margin is a thin, proportionate accent; below f≈0.4,
# outer_margin_px * f drops under that fixed 4px border - the margin
# can no longer even clear it, a structural inversion, not just "things
# got small." Fonts round to single-digit pixel sizes around the same
# range, independently illegible well before the border math fails.
# A caller needing a SMALLER card than this floor allows should render
# at factor 1.0 (full proportions intact) and apply a plain uniform
# transform scale on a wrapper OUTSIDE this Control instead - see
# field_room.gd's own npc_offer_card_scale for exactly that pattern,
# and why it can't go on `visual` itself (hover/armed already tween
# visual.scale to absolute targets, which would fight a baseline
# transform living on the same node).
func set_scale_factor(factor: float) -> void:
	_scale_factor = factor
	_apply_layout()

# The one place every exported layout value actually lands on a node -
# both _ready() and set_scale_factor() funnel through here, so editing
# an @export in the Inspector and calling set_scale_factor() always
# agree on what the card should look like; neither path can drift from
# the other.
func _apply_layout() -> void:
	var f := _scale_factor
	custom_minimum_size = design_size * f
	visual.pivot_offset = design_size * f / 2.0

	var margin := roundi(outer_margin_px * f)
	frame.add_theme_constant_override("margin_left", margin)
	frame.add_theme_constant_override("margin_top", margin)
	frame.add_theme_constant_override("margin_right", margin)
	frame.add_theme_constant_override("margin_bottom", margin)

	zones.add_theme_constant_override("separation", roundi(zone_separation_px * f))
	# NameBanner is a FIXED height now, not part of ArtSlot/DescriptionPanel's
	# stretch pool (see name_zone_height_px's own doc) - size_flags_vertical
	# is already 0 (no EXPAND) on the .tscn node itself, so VBoxContainer
	# gives it exactly this custom_minimum_size and nothing more.
	name_banner.custom_minimum_size.y = name_zone_height_px * f
	art_slot.size_flags_stretch_ratio = art_zone_stretch
	# description_clip, not description_panel - see description_clip's own
	# onready var doc for why the stretch ratio has to land on the plain-
	# Control wrapper now, not the PanelContainer it wraps.
	description_clip.size_flags_stretch_ratio = description_zone_stretch
	# Also fixed, also not part of the stretch pool - see its own onready
	# var doc for why it exists between these two specific zones.
	art_description_gap_spacer.custom_minimum_size.y = art_description_gap_extra_px * f

	for style in [_name_banner_style, _art_slot_style, _description_panel_style]:
		style.content_margin_left = zone_content_margin_px * f
		style.content_margin_top = zone_content_margin_px * f
		style.content_margin_right = zone_content_margin_px * f
		style.content_margin_bottom = zone_content_margin_px * f

	# Panel colors (see "Card Colors" export group) - not scale-dependent
	# at all, but applied here anyway rather than a separate function, so
	# _apply_layout() stays the one place every exported card-face value
	# lands on a node (same reasoning name_font_color/cost_font_color
	# already follow in "Card Fonts" above).
	_visual_style.bg_color = card_body_color
	_name_banner_style.bg_color = name_banner_color
	_name_banner_style.border_color = name_banner_border_color
	_art_slot_style.bg_color = art_slot_color
	_art_slot_style.border_color = art_slot_border_color
	_description_panel_style.bg_color = description_panel_color
	_description_panel_style.border_color = description_panel_border_color

	var badge_size := cost_badge_diameter_px * f
	var badge_margin := cost_badge_margin_px * f
	cost_badge.offset_left = badge_margin
	cost_badge.offset_top = badge_margin
	cost_badge.offset_right = badge_margin + badge_size
	cost_badge.offset_bottom = badge_margin + badge_size
	# corner_radius_* is an int property on StyleBoxFlat (unlike
	# content_margin_*, which is a float) - rounded here so a perfect
	# circle doesn't get quietly truncated at odd scale factors.
	var badge_radius := roundi(badge_size / 2.0)
	_cost_badge_style.corner_radius_top_left = badge_radius
	_cost_badge_style.corner_radius_top_right = badge_radius
	_cost_badge_style.corner_radius_bottom_right = badge_radius
	_cost_badge_style.corner_radius_bottom_left = badge_radius

	# CostPip occupies the SAME top-left corner slot as CostBadge above -
	# same badge_margin (shared, not a separate export - see cost_pip_
	# size_px's own doc for why only size is independently tunable), own
	# size from cost_pip_size_px (defaults equal to cost_badge_diameter_px
	# so nothing shifts today). Visibility/texture is data-driven, not
	# scale-driven, so it's decided in _update_cost_display() (called from
	# _update_display() when card_data changes), not here - this only
	# ever sets WHERE the pip would sit if visible, same split every
	# other zone's style-vs-layout code in this function already follows.
	var pip_size := cost_pip_size_px * f
	cost_pip.offset_left = badge_margin
	cost_pip.offset_top = badge_margin
	cost_pip.offset_right = badge_margin + pip_size
	cost_pip.offset_bottom = badge_margin + pip_size
	# CostPipScene occupies the exact same slot as CostPip above - same
	# badge_margin, same pip_size, just a Control that can host an
	# instanced hand-drawn scene instead of a plain texture (see cost_
	# pip_scenes' own doc). Re-fitting the LIVE instance (if any) is
	# handled below, alongside the description-text scale-reapply this
	# function already does for the same "scale changed after set_card_
	# data() already ran once" reason.
	cost_pip_scene_container.offset_left = badge_margin
	cost_pip_scene_container.offset_top = badge_margin
	cost_pip_scene_container.offset_right = badge_margin + pip_size
	cost_pip_scene_container.offset_bottom = badge_margin + pip_size

	# The easy placement nudge - see cost_pip_offset_px's own doc for why
	# this applies to all three nodes together, not just whichever is
	# currently visible.
	for node in [cost_badge, cost_pip, cost_pip_scene_container]:
		node.offset_left += cost_pip_offset_px.x * f
		node.offset_right += cost_pip_offset_px.x * f
		node.offset_top += cost_pip_offset_px.y * f
		node.offset_bottom += cost_pip_offset_px.y * f

	# DEFAULT POSITION: directly to the right of CostBadge (2026-08-28,
	# drain-badge-placement pass - REPLACES the old top-right-corner
	# anchoring, which used to mirror CostBadge into the opposite corner
	# rather than sitting beside it). Anchored to the LEFT edge now
	# (anchor_left/right both 0.0 in card.tscn, matching CostBadge's own
	# un-anchored style) - offsets count outward from CostBadge's own
	# right edge, not inward from the card's right edge. drain_gap reuses
	# badge_margin as the gap between the two badges, same "reuse
	# CostBadge's own value instead of a second number to keep matched"
	# reasoning attack_hp_drain_scale_relative_to_cost's own doc already
	# gives for size. Vertically CENTERED on CostBadge's own vertical
	# middle, not top-aligned - drain_size is usually smaller than
	# badge_size (see that export's 0.65 default), and matching tops
	# would read as misaligned sitting next to the taller cost badge.
	var drain_size := badge_size * attack_hp_drain_scale_relative_to_cost
	var drain_gap := badge_margin
	attack_hp_drain_badge.offset_left = badge_margin + badge_size + drain_gap
	attack_hp_drain_badge.offset_right = attack_hp_drain_badge.offset_left + drain_size
	var cost_badge_center_y := badge_margin + badge_size / 2.0
	attack_hp_drain_badge.offset_top = cost_badge_center_y - drain_size / 2.0
	attack_hp_drain_badge.offset_bottom = attack_hp_drain_badge.offset_top + drain_size
	# The easy placement nudge - see attack_hp_drain_offset_px's own doc.
	# Added AFTER the derived beside-cost-badge position above, not
	# folded into drain_gap - this is a plain positional offset, unrelated
	# to the badge's own size/gap math, and shouldn't have to be threaded
	# through that formula to work.
	attack_hp_drain_badge.offset_left += attack_hp_drain_offset_px.x * f
	attack_hp_drain_badge.offset_right += attack_hp_drain_offset_px.x * f
	attack_hp_drain_badge.offset_top += attack_hp_drain_offset_px.y * f
	attack_hp_drain_badge.offset_bottom += attack_hp_drain_offset_px.y * f
	var drain_radius := roundi(drain_size / 2.0)
	_attack_hp_drain_style.corner_radius_top_left = drain_radius
	_attack_hp_drain_style.corner_radius_top_right = drain_radius
	_attack_hp_drain_style.corner_radius_bottom_right = drain_radius
	_attack_hp_drain_style.corner_radius_bottom_left = drain_radius
	_attack_hp_drain_style.bg_color = attack_hp_drain_plate_color
	_attack_hp_drain_style.border_color = attack_hp_drain_border_color
	_attack_hp_drain_style.border_width_left = roundi(attack_hp_drain_border_width_px)
	_attack_hp_drain_style.border_width_top = roundi(attack_hp_drain_border_width_px)
	_attack_hp_drain_style.border_width_right = roundi(attack_hp_drain_border_width_px)
	_attack_hp_drain_style.border_width_bottom = roundi(attack_hp_drain_border_width_px)
	attack_hp_drain_label.add_theme_color_override("font_color", attack_hp_drain_number_color)
	# Same ratio as the badge's own size above, applied to cost_font_
	# size_px instead of cost_badge_diameter_px - the number inside scales
	# with the plate around it, both tracking CostBadge by the same one
	# knob rather than the plate and its own glyph drifting apart.
	attack_hp_drain_label.add_theme_font_size_override("font_size", roundi(cost_font_size_px * attack_hp_drain_scale_relative_to_cost * f))

	# ChainGlow now matches Visual's own rect exactly (see card.tscn) -
	# no more manual oversize/offset math, since a StyleBoxFlat shadow
	# already blurs OUTWARD from its box's own edge on its own. Corner
	# radius mirrors Visual's own 10px (scaled) so the glow's silhouette
	# stays concentric with the card's actual rounded corners.
	var glow_radius := roundi(10 * f)
	_chain_glow_style.corner_radius_top_left = glow_radius
	_chain_glow_style.corner_radius_top_right = glow_radius
	_chain_glow_style.corner_radius_bottom_right = glow_radius
	_chain_glow_style.corner_radius_bottom_left = glow_radius
	_chain_glow_style.shadow_size = roundi(chain_glow_spread_px * f)
	_chain_glow_style.shadow_color = Color(chain_glow_color.r, chain_glow_color.g, chain_glow_color.b, chain_glow_intensity)

	# condition_frame - a border only (bg_color stays transparent, set
	# once in _own_zone_styles()), same concentric corner radius as
	# ChainGlow above for the same reason. Border width is the one thing
	# actually scaled here; color/intensity are static per-instance
	# exports, reapplied every call since a scale change is the only
	# reason this function re-runs, not because they're expected to
	# change on their own.
	_condition_frame_style.corner_radius_top_left = glow_radius
	_condition_frame_style.corner_radius_top_right = glow_radius
	_condition_frame_style.corner_radius_bottom_right = glow_radius
	_condition_frame_style.corner_radius_bottom_left = glow_radius
	var frame_border := roundi(condition_frame_width_px * f)
	_condition_frame_style.border_width_left = frame_border
	_condition_frame_style.border_width_top = frame_border
	_condition_frame_style.border_width_right = frame_border
	_condition_frame_style.border_width_bottom = frame_border
	_condition_frame_style.border_color = Color(condition_frame_color.r, condition_frame_color.g, condition_frame_color.b, condition_frame_intensity)
	# Pushes condition_frame's own RECT outward past Visual's edge (see
	# condition_frame_expand_px's own doc for the overlap bug this fixes)
	# - a Control property, not a StyleBoxFlat one, so it's set on the
	# node directly rather than on _condition_frame_style above.
	var frame_expand := condition_frame_expand_px * f
	condition_frame.offset_left = -frame_expand
	condition_frame.offset_top = -frame_expand
	condition_frame.offset_right = frame_expand
	condition_frame.offset_bottom = frame_expand

	name_label.add_theme_font_size_override("font_size", roundi(name_font_size_px * f))
	name_label.add_theme_font_override("font", name_font)
	name_label.add_theme_color_override("font_color", name_font_color)
	# "normal_font_size," not "font_size" - RichTextLabel's theme size
	# properties are named per font variant (normal/bold/italics/mono),
	# unlike Label's single "font_size."
	description_label.add_theme_font_size_override("normal_font_size", roundi(description_font_size_px * f))
	# "default_color," RichTextLabel's own name for the same role Label's
	# "font_color" plays - the color inline BBCode (card_text_styles.gd's
	# [keyword]/[modified]/etc.) overrides locally, everywhere else falls
	# back to.
	description_label.add_theme_color_override("default_color", HudPalette.SYSTEM_TEXT)
	cost_label.add_theme_font_size_override("font_size", roundi(cost_font_size_px * f))
	cost_label.add_theme_color_override("font_color", cost_font_color)
	# The chain-role suffix's AND the removal-scope suffix's font sizes
	# are both baked directly into description_label's own TEXT (see
	# _chain_role_suffix()/_removal_scope_suffix()), not a theme override
	# this loop could otherwise just reapply the normal way - so if scale
	# changes AFTER set_card_data() already ran once, this is what keeps
	# both in sync rather than left stale at the old scale's size. Guarded:
	# _apply_layout() itself runs once in _ready(), before set_card_data()
	# has ever given this card real data to read chain_role/removal_scope
	# from.
	if card_data != null:
		_refresh_description_text()
	# Same "scale changed after set_card_data() already ran once" reason
	# as the description-text reapply just above - a live scene-cost-pip
	# instance's own fit (see _fit_cost_pip_scene()) is sized in real
	# pixels against cost_pip_size_px * _scale_factor, so it goes stale at
	# the OLD scale otherwise. Guarded on the instance existing, not on
	# card_data - the instance itself is only ever created by _update_
	# cost_display() (which already requires card_data), so its presence
	# already implies card_data != null.
	if _cost_pip_scene_instance != null:
		_fit_cost_pip_scene(_cost_pip_scene_instance, cost_pip_size_px * f)

# The public entry point for giving this card something to display.
# Anyone who creates a Card (like Battle, when it draws a card) calls
# this instead of touching the labels directly.
func set_card_data(data: CardData) -> void:
	card_data = data
	_update_display()

func _update_display() -> void:
	if card_data == null:
		return
	name_label.text = card_data.card_name
	_update_cost_display()
	_refresh_description_text()
	_update_type_border()
	_update_art_texture()
	_update_art_type_fill()

# The cost pip's three-way fallback (2026-08-29, texture-cost-pip pass;
# EXTENDED 2026-08-29, scene-cost-pip pass - REPLACES the old bare
# `cost_label.text = str(card_data.energy_cost)` line in _update_
# display() above). cost_label's text is set UNCONDITIONALLY, not just
# in the fallback branch - it's the ONLY thing CostBadge shows when
# neither a scene nor a texture exists for this cost, so it has to
# already be correct the instant CostBadge becomes visible, not updated
# separately later. Priority order: cost_pip_scenes (hand-drawn vector
# art, the most finished option) beats cost_pip_textures (a placeholder
# raster texture) beats CostBadge (the procedural circle+numeral, always
# available). Same "toggle visibility based on whether an asset exists"
# shape _update_art_texture() already uses for card art - a cost with no
# entry anywhere falls back all the way to the procedural badge rather
# than rendering nothing, so an unauthored cost value stays fully
# playable.
# display_cost is card_data.energy_cost + card_data.marked_cost_modifier
# (2026-08-29, Leviathan mark attack) - the ONLY read of energy_cost in
# this function now goes through that sum, not the raw field, same "the
# number shown is what lands" rule this project already applies to
# combat elsewhere (see enemy_intent.gd's own WIND_UP doc, or battle.gd's
# _escalated_intent_value()). marked_cost_modifier is 0 for every card
# that was never marked, so this is byte-identical to before that field
# existed for the overwhelming majority of cards - see that field's own
# doc on card_data.gd. Both the cost-pip DICTIONARY LOOKUPS below use the
# same display_cost, not just the label text - a marked card showing a
# hand-drawn "1" pip while actually costing 2 would be exactly the kind
# of display/reality mismatch this whole function exists to prevent.
func _update_cost_display() -> void:
	var display_cost := card_data.energy_cost + card_data.marked_cost_modifier
	cost_label.text = str(display_cost)
	var scene: PackedScene = cost_pip_scenes.get(display_cost)
	if scene != null:
		_show_cost_pip_scene(scene)
		return
	_clear_cost_pip_scene()
	cost_pip_scene_container.visible = false
	var texture: Texture2D = cost_pip_textures.get(display_cost)
	cost_pip.texture = texture
	cost_pip.visible = texture != null
	cost_badge.visible = texture == null

# Instances `scene` into cost_pip_scene_container and fits it (see
# _fit_cost_pip_scene() below) - the scene-cost-pip branch of _update_
# cost_display() above. Frees any PREVIOUS instance first (see _clear_
# cost_pip_scene() below) - a card can have its data reassigned (deck
# viewer's own card-reuse pattern, if it has one; battle hand cards don't
# today, but this function has to stay correct regardless of caller),
# and stacking a second instance under the first rather than replacing
# it would leave the old one visible underneath, or double the cost.
func _show_cost_pip_scene(scene: PackedScene) -> void:
	_clear_cost_pip_scene()
	var instance: Control = scene.instantiate()
	cost_pip_scene_container.add_child(instance)
	_cost_pip_scene_instance = instance
	_fit_cost_pip_scene(instance, cost_pip_size_px * _scale_factor)
	cost_pip_scene_container.visible = true
	cost_pip.visible = false
	cost_badge.visible = false

# Caller-driven cost-pip suppression (2026-09-03, heap water-display-card
# pass) - for a display-only "card" that isn't a real deck card and has
# no energy cost to show at all (see field_heap.gd's own water reveal),
# unlike every REAL card, which _update_cost_display() above always
# renders SOME representation for (scene, texture, or the procedural
# badge - never nothing). Doesn't touch _update_cost_display() itself,
# which still runs unconditionally from set_card_data() and stays
# correct for every real card everywhere else in the game - this just
# forces all three of its possible outputs off AFTERWARD, one call, same
# "caller tells Card what to show, Card just renders it" split set_
# affordable()/set_chain_available() already follow. Must be called
# after set_card_data(), not before - _update_display() would otherwise
# turn one of the three back on and undo this.
func hide_cost() -> void:
	cost_badge.visible = false
	cost_pip.visible = false
	cost_pip_scene_container.visible = false

func _clear_cost_pip_scene() -> void:
	if _cost_pip_scene_instance != null:
		_cost_pip_scene_instance.queue_free()
		_cost_pip_scene_instance = null

# Scales+centers `instance`'s own Visual/CoinIcon so its MEASURED bounds
# (VisualBounds.compute(), not assumed - the same "measure a hand-drawn
# shape's real extents instead of guessing its authored coordinate
# scale" technique enemy.gd's own silhouette bounds already use) land
# exactly inside a target_size x target_size box - a direct port of
# pip.gd's own _apply_geometry()/_fit_coin_icon(), generalized to operate
# on an arbitrary instanced scene rather than that script's own fixed
# @onready refs, since this needs to work for whichever scene cost_pip_
# scenes handed it (the "1" variant today, 2/3/4 later). Fits by the
# LARGER of the two raw dimensions, so a non-square bounding box still
# fits fully inside the square target without clipping on its taller or
# wider axis - see pip.gd's own _fit_coin_icon() for the identical
# reasoning, unchanged here.
func _fit_cost_pip_scene(instance: Control, target_size: float) -> void:
	var visual: Node2D = instance.get_node("Visual")
	var coin_icon: Node2D = visual.get_node("CoinIcon")
	var bounds: Rect2 = VisualBounds.compute(coin_icon)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	visual.position = Vector2(target_size, target_size) / 2.0
	var raw_span: float = maxf(bounds.size.x, bounds.size.y)
	var fit_scale: float = target_size / raw_span
	coin_icon.scale = Vector2.ONE * fit_scale
	var raw_center: Vector2 = bounds.position + bounds.size / 2.0
	coin_icon.position = -raw_center * fit_scale

# --- Persistent description overrides (2026-08-28, override-survives-
# refresh pass) ---
#
# THE fix for a real, reproduced bug: show_status_value_preview() used to
# build a one-shot modified string and hand it to _refresh_description_
# text() as override_source below - which worked for exactly one rebuild,
# then got silently discarded the instant ANYTHING ELSE called _refresh_
# description_text() plain (no override), which set_condition_active()
# does UNCONDITIONALLY, from THREE separate call sites in battle.gd
# including _set_player_hp() - meaning Selfeater's own drain, on every
# taxed attack, wiped its own card's preview text. Traced and confirmed
# live in this pass's own investigation (see its report): show_status_
# value_preview(6, 5) produces the correct amber text, then a bare set_
# condition_active(false) call reverts it straight back to "3"/"2".
#
# The fix: the CARD owns this state now, not whichever caller last wrote
# it. A list of active number substitutions, persisted here and
# REAPPLIED by _refresh_description_text() below every time it rebuilds
# from card_data.description (not just the one time a setter happened to
# call it) - so ANY refresh, from ANY source, present or future, is safe
# by construction. set_condition_active() doesn't know this array exists
# and doesn't need to: it just calls _refresh_description_text() as
# always, and whatever's active here comes along for free.
#
# Each entry: {"base": int, "substitute": int, "tag": String, "source":
# String}. "source" is a caller-chosen label (today: "status_preview" -
# show_status_value_preview() below; "outgoing_damage" - show_modified_
# outgoing_damage() below) used ONLY by _clear_overrides_from() to let
# each setter replace just its OWN previous entries on every call,
# without one setter's fresh rebuild clobbering another's - Selfeater's
# own card (APPLY_STATUS) and an attack card (DAMAGE) never coexist on
# the same CardData today, but a future card combining both shouldn't
# silently break this the way a blind full-list .clear() would.
#
# Deliberately does NOT participate when an explicit override_source IS
# given (see below) - that path is show_modified_damage()'s own hover-
# triggered escape-falloff preview, an entirely separate, PRE-EXISTING
# mechanism this pass doesn't touch. The two could in principle want to
# combine (hovering an attack card against Outbound while Selfeater is
# also active) - out of scope here; while hovering, the hover preview
# wins outright and the persistent override is transiently not shown,
# reverting the instant the hover preview itself reverts (restore_
# description() below reapplies this array again, same as any refresh).
var _description_overrides: Array[Dictionary] = []

# Removes only the entries a given setter previously added (matched by
# their own "source" tag) - called at the START of show_status_value_
# preview()/show_modified_outgoing_damage() below, before each rebuilds
# its own fresh set, so two independent override sources can coexist on
# one card without one wiping the other's still-current entries.
func _clear_overrides_from(source: String) -> void:
	_description_overrides = _description_overrides.filter(func(entry): return entry["source"] != source)

# Applies every entry in _description_overrides to `source`, two-phase
# (base numbers to placeholder tokens FIRST, then placeholders to the
# real [tag]N[/tag] text) - the same technique show_status_value_
# preview()'s own history required (see its doc): a direct chained
# .replace() straight from a base number to final digit-bearing text can
# corrupt itself the instant one substitution's OWN output contains a
# digit a LATER substitution is also searching for. Placeholders here use
# LETTERS, not the entry's numeric index - a digit-based placeholder
# would reintroduce the exact same collision risk one level up (entry 1's
# placeholder containing "1" could be re-matched by entry 11's own base-
# number search). Letters can never collide with str(int) output, so
# ordering/count no longer matters at all.
func _apply_number_overrides(source: String) -> String:
	if _description_overrides.is_empty():
		return source
	var result := source
	for i in _description_overrides.size():
		var base: int = _description_overrides[i]["base"]
		result = result.replace(str(base), _override_placeholder(i))
	for i in _description_overrides.size():
		var entry: Dictionary = _description_overrides[i]
		var tag: String = entry["tag"]
		result = result.replace(_override_placeholder(i), "[%s]%d[/%s]" % [tag, entry["substitute"], tag])
	return result

func _override_placeholder(index: int) -> String:
	return "%s" % char(65 + index) # A control-character-wrapped letter (index 0 -> SOH+A+SOH) - cannot appear in normal card text.

# Split out from _update_display() so _apply_layout() can also call it
# (guarded there on card_data != null) - the chain-role suffix's font
# size (see _chain_role_suffix()) is baked into this RichTextLabel's own
# TEXT rather than a theme override, so a scale change after set_card_
# data() has to rebuild this text to actually pick up the new size.
#
# override_source, if non-empty, replaces card_data.description as the
# text being rendered AND skips _description_overrides entirely (see that
# array's own doc for why) - see show_modified_damage() below, which
# passes an already-substituted copy through here rather than duplicating
# the expand()/chain-suffix/center-wrap tail a second time. Every OTHER
# caller (set_card_data(), _apply_layout(), restore_description(), set_
# condition_active()) passes nothing, which now means "rebuild from
# card_data.description, reapplying whatever's currently in _description_
# overrides" - restore_description() calling this plain is what makes it
# safe to call from anywhere without erasing a persistent override; see
# clear_description_overrides() below for the actual explicit-clear path.
func _refresh_description_text(override_source: String = "") -> void:
	# expand() rewrites any [modified]/[keyword]/[entity]/[reduced]
	# semantic tags into real BBCode (see card_text_styles.gd) - raw
	# BBCode already in the description ([b], [color=...], etc.) passes
	# through untouched, and plain text with no tags at all comes back
	# byte-for-byte unchanged. [center]...[/center] reproduces Label's old
	# horizontal_alignment = 1 - RichTextLabel has no such property of
	# its own, only this BBCode tag, so centering has to be applied here
	# rather than as a node setting in card.tscn. Nests fine with
	# whatever's already inside (a card's own [left]/[right], if any,
	# still wins for that span).
	var source := override_source if override_source != "" else card_data.description
	if override_source == "":
		source = _apply_number_overrides(source)
	var text := CardTextStyles.expand(source)
	# [cond_active]/[cond_inactive] (2026-08-27, condition-indicator pass -
	# see condition_active_value_color's own "Condition Indicator" export
	# group note) - a SECOND pass, separate from expand() above, since
	# these two tags need live state (_condition_active), not a fixed
	# lookup table. Runs on every rebuild, including override_source calls
	# (show_modified_damage()) - a card showing a damage preview still has
	# whatever conditional structure its own description authored, and
	# should still re-weight it the same way.
	text = CardTextStyles.expand_conditional(text, _condition_active, condition_active_value_color, Color(HudPalette.SYSTEM_TEXT.r, HudPalette.SYSTEM_TEXT.g, HudPalette.SYSTEM_TEXT.b, condition_inactive_value_dim_alpha))
	# _removal_scope_suffix() runs on EVERY rebuild, unconditionally, same
	# as _chain_role_suffix() right below it (2026-08-28, badge-removal
	# pass - REPLACES the old _update_removal_marker(), a separate call
	# _update_display() used to make after this function returned). That
	# used to be a second, independent write path - fine for a corner
	# badge with its own node, but the whole point of moving this into
	# rules text is composing safely with _apply_number_overrides() above:
	# since both suffixes are appended to `text` AFTER expand_conditional()
	# rather than mixed into `source` before it, neither can ever be seen
	# or touched by the override substitution, so a Selfeater preview's
	# amber values and this card's own Spent/Consumed line can never
	# duplicate or clobber each other - they're just two independently-
	# generated tails on the same rebuild, every single time it runs.
	text += _removal_scope_suffix()
	text += _chain_role_suffix()
	text += _marked_suffix()
	description_label.text = "[center]%s[/center]" % text

# --- Damage preview (see battle.gd's "Damage preview seam" note) ---
#
# Public entry point for the escape-falloff readout (2026-08-24) - moved
# here from a separate enemy-side label (see DesignDoc's Outbound entry)
# specifically because Outbound is guaranteed solo: a player-side
# modifier always resolves to one number regardless of target and
# belongs on the card face unconditionally; a target-side modifier is
# normally ambiguous with more than one enemy on screen and belongs on
# the target instead (see enemy.gd's DamagePreviewLabel, left in place
# for exactly that future case - a target-side modifier that can't
# collapse to a single card-face number). Escape falloff is target-side
# but gets the card-face treatment ONLY because there's never more than
# one enemy to be ambiguous about; that's a deliberate exception for
# this one mechanic, not a reversal of the general rule.
#
# Only CardEffect.EffectType.DAMAGE entries are substituted (not TOLL_
# DAMAGE - its value is unused/meaningless, see card_effect.gd's own
# doc, and Reckoning's own printed text was deliberately written with no
# literal number for exactly that reason, so there's nothing here to
# replace). Matches on str(effect.value) against the raw authored text -
# works cleanly for every card today (a card with several same-valued
# DAMAGE entries would update them all together in one pass) but is a
# plain text substitution, not a structural one: a hypothetical future
# card whose OTHER effect happened to print the exact same number as its
# damage value (e.g. "Deal 6 damage. Draw 6 cards.") would have both
# recolored. No card today has that shape.
func show_modified_damage(scalar: float) -> void:
	if card_data == null:
		return
	var modified_description := card_data.description
	for effect in card_data.effects:
		if effect.effect_type == CardEffect.EffectType.DAMAGE:
			var adjusted := roundi(effect.value * scalar)
			modified_description = modified_description.replace(str(effect.value), "[reduced]%d[/reduced]" % adjusted)
	_refresh_description_text(modified_description)

# Reverts to whatever this card's TRUE current text actually is - called
# on hover exit, and anywhere else that means "no hover-specific override
# to show right now" (see battle.gd's own call sites). NOT "revert to
# raw card_data.description" any more (2026-08-28, override-survives-
# refresh pass) - a named wrapper for _refresh_description_text() with no
# override, which now means "rebuild from card_data.description,
# reapplying whatever's in _description_overrides" (see that array's own
# doc). This is exactly right for hover-exit: a Slash card showing a
# live Selfeater-boosted "9" should keep showing 9 after the mouse
# leaves, not drop back to a stale "6" - there's nothing left to actually
# revert here now that the persistent state IS the truth. To genuinely
# clear that persistent state (the status was removed, or this card is
# leaving hand for good), call clear_description_overrides() below
# instead - restore_description() deliberately never does that itself.
func restore_description() -> void:
	_refresh_description_text()

# The explicit clear (2026-08-28, override-survives-refresh pass) - the
# ONLY thing that erases _description_overrides. Called by battle.gd
# specifically at "this card is leaving hand for good" moments (played,
# discarded) - see its own call sites - never as a side effect of an
# unrelated refresh, which is the exact failure mode this whole pass
# exists to fix. Safe to call on a card with nothing active (a no-op
# clear, then a rebuild that was already going to show the same thing).
func clear_description_overrides() -> void:
	_description_overrides.clear()
	_refresh_description_text()

const STATUS_PREVIEW_SOURCE := "status_preview"
const OUTGOING_DAMAGE_SOURCE := "outgoing_damage"
# The two _description_overrides "source" tags this file actually writes
# today (see that array's own doc) - named consts rather than bare string
# literals repeated at each call site, so the two setters below and
# _clear_overrides_from() always agree on the exact spelling.

# The "what would THIS copy actually do if played right now" preview for
# a card with an APPLY_STATUS effect (2026-08-28, Selfeater rules-text
# pass) - called by battle.gd's _update_status_card_preview(), which
# computes damage_bonus/hp_cost from the same formulas the real
# resolution paths use (never independently here - this function only
# ever renders numbers it's handed, the same "battle.gd decides WHAT,
# card.gd renders it" split set_stance_tint()/set_attack_hp_drain()
# already follow).
#
# REWORKED (2026-08-28, override-survives-refresh pass) to populate
# _description_overrides instead of building and handing off a one-shot
# string - see that array's own doc for why: the old version worked for
# exactly one rebuild, then got silently erased by the next unrelated
# refresh (set_condition_active(), called from _update_hand_affordability()
# on every card in hand, from three call sites including _set_player_hp()
# - traced and confirmed live in this pass's own investigation). Clears
# only ITS OWN previous entries first (STATUS_PREVIEW_SOURCE), not the
# whole array, so show_modified_outgoing_damage() below can hold its own
# entries on the same card without either wiping the other's (no card
# combines both today, but this stays correct if one ever does).
#
# Uses [modified], not [reduced] like show_modified_damage() - Selfeater's
# numbers only ever GROW when stacking, never shrink, and STYLES' own doc
# is explicit that those two tags mean opposite things (amber "this got
# bigger" vs. rust "this got smaller"); reusing [reduced] here would
# teach the wrong lesson.
#
# Decides INTERNALLY whether either number actually differs from the
# status's own base value and only adds an override for the ones that do
# - a card in hand while nothing's active yet previews stack 1, which IS
# the base value, so nothing should highlight at all; this is what makes
# "base values, unhighlighted, when no stack is active" true without
# battle.gd needing to pre-check that itself.
func show_status_value_preview(damage_bonus: int, hp_cost: int) -> void:
	if card_data == null:
		return
	_clear_overrides_from(STATUS_PREVIEW_SOURCE)
	for effect in card_data.effects:
		if effect.effect_type != CardEffect.EffectType.APPLY_STATUS or effect.status_data == null:
			continue
		var status_data: StatusEffectData = effect.status_data
		if status_data.category == StatusEffectData.Category.MODIFIER and damage_bonus != status_data.default_magnitude:
			_description_overrides.append({"base": status_data.default_magnitude, "substitute": damage_bonus, "tag": "modified", "source": STATUS_PREVIEW_SOURCE})
		var carries_drain := status_data.attack_hp_drain_base > 0 or status_data.attack_hp_drain_increment > 0
		if carries_drain and hp_cost != status_data.attack_hp_drain_base:
			_description_overrides.append({"base": status_data.attack_hp_drain_base, "substitute": hp_cost, "tag": "modified", "source": STATUS_PREVIEW_SOURCE})
	_refresh_description_text()

# The live "what will this attack actually deal" preview (2026-08-28,
# generic-damage-preview pass - Part 2 of the same brief as the fix
# above) - called by battle.gd's _update_hand_outgoing_damage_preview()
# for EVERY card in hand, not just ones with an APPLY_STATUS effect (see
# that function's own doc). `overrides` is an already-computed list of
# {"base": int, "substitute": int} pairs, one per hit-type CardEffect
# whose _apply_status_modifiers()-derived value differs from its own
# authored effect.value - battle.gd decides WHICH effects qualify and
# what they're actually worth; this only ever renders what it's handed,
# same split every other setter in this section already follows.
#
# Same [modified] tag as show_status_value_preview() above (amber, "this
# got bigger" - an active MODIFIER status boosting outgoing damage is
# the only thing this is wired to today, per this pass's own scope) and
# the same persistent-override storage, tagged OUTGOING_DAMAGE_SOURCE so
# it can coexist with (and never gets clobbered by, or itself clobbers)
# a status-preview override on the same card.
func show_modified_outgoing_damage(overrides: Array[Dictionary]) -> void:
	if card_data == null:
		return
	_clear_overrides_from(OUTGOING_DAMAGE_SOURCE)
	for entry in overrides:
		_description_overrides.append({"base": entry["base"], "substitute": entry["substitute"], "tag": "modified", "source": OUTGOING_DAMAGE_SOURCE})
	_refresh_description_text()

# DISCONNECTED from _update_display() (2026-08-29, inner-border-removal
# pass) - NOT deleted, per this pass's own brief: rarity is coming back
# later as a symbol rather than a frame, so the color-per-rarity mapping
# (RARITY_BORDER_COLORS) and this function's own logic stay intact and
# ready to be repointed at whatever draws that symbol, rather than
# forcing that future work to reconstruct a rarity->color lookup from
# scratch. Display removal only - card_data.rarity itself, RARITY_
# BORDER_COLORS, and this function's own body are all untouched; the
# ONLY change is that _update_display() no longer calls this, so ArtSlot's
# border now just sits at its own static art_slot_border_color (set in
# _apply_layout(), never overridden) for every rarity alike - the flat,
# non-rarity edge this pass's brief asks the art panel to keep instead
# of a colored ring. If this is called again later, it still works
# exactly as before; nothing here needs to change for that to be true.
#
# ORIGINAL COMMENT, still accurate for the logic itself (2026-08-27,
# border swap) - used to duplicate Visual's own stylebox a SECOND time
# just for this (Visual wasn't yet a per-instance duplicate when this
# was first written). Now targets ArtSlot's border instead of Visual's
# outer one (see RARITY_BORDER_COLORS' own doc for why), and _art_slot_
# style is already this instance's own private copy (made once in _own_
# zone_styles()), so this is a direct mutation - no second duplicate
# needed, same as every other zone style on this face.
func _update_rarity_border() -> void:
	_art_slot_style.border_color = RARITY_BORDER_COLORS.get(card_data.rarity, RARITY_BORDER_COLORS[CardData.Rarity.COMMON])

# Visual's own OUTER border, as of the same border swap above - this
# used to be rarity's spot (see _update_rarity_border()'s own doc).
# _visual_style is already this instance's private copy, already
# mutated for card_body_color (bg) elsewhere - this just adds the
# border_color half of that same stylebox, same "static bg + dynamic
# border coexisting on one style" shape ArtSlot's own style now has too.
func _update_type_border() -> void:
	_visual_style.border_color = card_type_border_colors[card_data.card_type]

# Hidden entirely (not just an empty/blank texture) when card_data.art_
# texture is unset, so a card with no art renders exactly as it always
# has - ArtSlot's own plain framed background, nothing missing or broken
# about it. ArtSlot (a PanelContainer) sizes/positions this to fill its
# content area on its own; nothing here needs to touch position or size.
func _update_art_texture() -> void:
	art_texture.texture = card_data.art_texture
	art_texture.visible = card_data.art_texture != null

# Derived from card_data.card_type again (2026-09-07, low-chroma-
# restore pass - see art_placeholder_color_attack's own doc above for
# why), same as every other type-driven face element (outer border,
# rarity accent) - still called identically everywhere card.tscn is
# instanced (hand, deck viewer, reward screen, rare drop reveal, shop
# preview, plus the field's Keeper/chest offer cards, which instance
# this same scene) with no per-context wiring. A match, not a dict
# lookup, since these are three separate exports now rather than one
# Dictionary - CardType has three values today and each needs its own
# branch here with no fallback, the same "whoever adds a FOURTH CardType
# must add its own case" shape the old dict enforced.
func _update_art_type_fill() -> void:
	match card_data.card_type:
		CardData.CardType.ATTACK:
			art_type_fill.color = art_placeholder_color_attack
		CardData.CardType.SKILL:
			art_type_fill.color = art_placeholder_color_skill
		CardData.CardType.STANCE:
			art_type_fill.color = art_placeholder_color_stance

# The generated Spent/Consumed rules-text line (2026-08-28, badge-removal
# pass - REPLACES the old corner-badge RemovalMarker/RemovalLabel and
# _update_removal_marker() entirely, called from _update_display()'s own
# _refresh_description_text()/_update_removal_marker() pair back then).
# Called from _refresh_description_text() now instead, same shape and
# same reason as _chain_role_suffix() right below it: generated from
# card_data.removal_scope fresh on every rebuild rather than authored,
# so it can never be forgotten on a card or disagree with the enum, and
# can never duplicate or go stale across a refresh the way a one-shot
# write from a separate call site could. NONE returns "" - a raw dict
# lookup, same "no fallback, add the entry or it breaks" shape _update_
# art_type_fill() uses, guarded so that lookup is never actually reached
# for the one value REMOVAL_SCOPE_KEYWORD_TEXT has no entry for.
func _removal_scope_suffix() -> String:
	if not REMOVAL_SCOPE_KEYWORD_TEXT.has(card_data.removal_scope):
		return ""
	# Deliberately its OWN smaller, unbolded style - NOT the shared
	# [keyword] tag card_text_styles.gd defines, same reasoning _chain_
	# role_suffix() gives for Opener/Closer right below: this is a
	# secondary annotation below the card's primary rules text, not
	# another instruction, and should read with the SAME weight Opener/
	# Closer already do rather than a second "secondary annotation"
	# language. Independent exports (removal_scope_font_size_px/_gap_px/
	# _text_color), not literally chain_role_font_size_px/_gap_px reused -
	# see those exports' own doc for why they stay separately tunable
	# even though they start identical.
	var keyword: String = REMOVAL_SCOPE_KEYWORD_TEXT[card_data.removal_scope]
	var size := roundi(removal_scope_font_size_px * _scale_factor)
	# Same blank [font_size=gap]\n[/font_size] spacer technique as _chain_
	# role_suffix() below - see that function's own note for why a blank
	# line at a controlled size is the standard BBCode way to get a real
	# gap here, RichTextLabel having no "space before this line" property.
	var gap := roundi(removal_scope_gap_px * _scale_factor)
	return "\n[font_size=%d]\n[/font_size][font_size=%d][color=#%s]%s[/color][/font_size]" % [gap, size, removal_scope_text_color.to_html(false), keyword]

# The generated "Marked" rules-text line (2026-08-29, Leviathan mark
# attack) - same shape as _removal_scope_suffix() just above, generated
# fresh from card_data.marked_cost_modifier on every rebuild rather than
# a separate corner-badge node, for the exact same reason that pass
# already established: a corner badge was deliberately removed from this
# scene (see _removal_scope_suffix()'s own "badge-removal pass" note) in
# favor of composing extra card-face state as more rules-text tails, and
# this is one more instance of that same state, not a new pattern.
# Reuses removal_scope_font_size_px/_gap_px/_text_color directly rather
# than its own trio of exports - both are the same kind of thing (a
# secondary annotation below the card's primary rules text) and this
# feature's own brief is explicitly "one field for one effect," not a
# reason to add three more tunable knobs for a single line of text.
#
# "" (every card whose marked_cost_modifier is 0 - i.e. every card that
# was never marked) means nothing renders - a marked card is the only
# one that ever sees this line at all, and it clears itself the instant
# the card is unmarked (played, or combat ending - see that field's own
# doc), so there's no separate cleanup this function needs to do.
func _marked_suffix() -> String:
	if card_data.marked_cost_modifier == 0:
		return ""
	var size := roundi(removal_scope_font_size_px * _scale_factor)
	var gap := roundi(removal_scope_gap_px * _scale_factor)
	return "\n[font_size=%d]\n[/font_size][font_size=%d][color=#%s]Marked[/color][/font_size]" % [gap, size, removal_scope_text_color.to_html(false)]

# --- Attack HP drain indicator (2026-08-28, Selfeater stacking pass) ---
#
# Called by battle.gd whenever a drain-carrying status's presence or
# stack count could have changed - a card entering the hand fresh (see
# _add_card_to_hand_display()) or player_statuses itself changing (see
# _update_hand_stance_indicators()). `amount` is always the SAME number
# _apply_attack_hp_drain() would actually charge right now (see battle.
# gd's _total_attack_hp_drain(), the one place this is computed - this
# function never recomputes it, only displays it).
#
# Gated on card_type == ATTACK HERE, inside this function, not by every
# call site remembering to check first - Selfeater's own card is STANCE
# and must never show this regardless of what battle.gd passes in, even
# though ITS OWN status is very likely what's driving a nonzero amount
# for every OTHER card in hand at that exact moment. Dereferences
# card_data directly (same "assumes set_card_data() already ran" stance
# set_condition_active() above takes, not set_affordable()'s "nothing to
# read" one) - safe under the same established call-order convention
# every hand card already follows.
func set_attack_hp_drain(amount: int) -> void:
	var show := card_data.card_type == CardData.CardType.ATTACK and amount > 0
	attack_hp_drain_badge.visible = show
	if show:
		attack_hp_drain_label.text = "-%d" % amount

# --- Chaining (see card_data.gd's own note - minimum viable prototype) ---
#
# Battle calls this whenever chain state changes (an Opener gets played,
# a Closer consumes the chain, or end-of-turn lets it expire unused) for
# every CLOSER-role card currently in hand - see battle.gd's _refresh_
# chain_indicators(). NONE/OPENER-role cards never get called with
# active=true. Purely a visual toggle - see chain_glow's own export-
# group note above for why a glow, not text, carries this now. The
# pulse (see that same note) starts/stops here too, so a card can never
# be left mid-breathe after its chain state actually changed.
func set_chain_available(active: bool) -> void:
	_chain_available = active
	chain_glow.visible = active
	if _chain_pulse_tween:
		_chain_pulse_tween.kill()
	if active:
		chain_glow.modulate.a = 1.0
		_chain_pulse_tween = create_tween()
		_chain_pulse_tween.set_loops() # 0 = infinite - runs until the next set_chain_available(false) kills it.
		_chain_pulse_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_chain_pulse_tween.tween_property(chain_glow, "modulate:a", 1.0 - CHAIN_GLOW_PULSE_DIP, chain_glow_pulse_period_sec)
		_chain_pulse_tween.tween_property(chain_glow, "modulate:a", 1.0, chain_glow_pulse_period_sec)
	else:
		chain_glow.modulate.a = 1.0

# Called by battle.gd (see its own _card_condition_active()/_update_hand_
# affordability() and _add_card_to_hand_display()) - one bool, no motion,
# no tween (contrast set_chain_available() above: "quiet" is this pass's
# own brief, point 4 - chain-liveness pulses on purpose, condition-active
# deliberately does not, so the two never compete for the eye the same
# way). Both halves of this pass's own indicator update from here:
# condition_frame's own visibility, and the rules text's re-weighting
# (via _refresh_description_text(), which reads _condition_active fresh
# every time it rebuilds - see that var's own doc). Guarded on card_data
# != null - unlike set_affordable() (a one-line modulate swap with
# nothing to read), _refresh_description_text() dereferences card_data.
# description directly, so calling this before set_card_data() would
# crash rather than just no-op quietly.
func set_condition_active(active: bool) -> void:
	_condition_active = active
	condition_frame.visible = active
	if card_data != null:
		_refresh_description_text()

# The one place a card's rules text states its chain role (see card_
# data.gd's ChainRole) - appended after the author-written description
# rather than baked into it, so the description itself never needs to
# change if a card's role changes. Both OPENER and CLOSER print their
# role name as a static keyword this way - this is a permanent "what
# this card IS" label, separate from chain_glow above, which is the
# separate, dynamic "a chain is live right now" signal a Closer also
# carries. The empowered NUMBER used to be spelled out here for Closers
# instead of a role label; removed (see battle.gd's chain-payoff note)
# because it read as a card being buffed rather than a chain
# completing - a Closer's own printed damage never changes regardless
# of chain state, so nothing about that removal is undone by adding the
# plain "Closer" label back.
func _chain_role_suffix() -> String:
	match card_data.chain_role:
		CardData.ChainRole.OPENER, CardData.ChainRole.CLOSER:
			# Deliberately its OWN smaller, unbolded style - NOT the shared
			# [keyword] tag rules terms use (see card_text_styles.gd) -
			# _removal_scope_suffix() below follows this same convention
			# for exactly the same reason, rather than that one. The
			# effect text above is a card's
			# primary information; this is a secondary annotation and
			# should read as clearly less important than it, not equal to
			# or bigger. Built directly here (not routed through Card
			# TextStyles' STYLES dict) because the size has to scale with
			# THIS card instance's own _scale_factor - STYLES has no
			# notion of that, it only ever emits fixed color/bold/italic.
			var role_name := "Opener" if card_data.chain_role == CardData.ChainRole.OPENER else "Closer"
			var size := roundi(chain_role_font_size_px * _scale_factor)
			# The blank [font_size=gap]\n[/font_size] line below is a
			# spacer, not a typo - RichTextLabel has no "space before this
			# line" property of its own, so a blank line rendered at a
			# controlled font_size (see chain_role_gap_px's own doc) is the
			# standard BBCode way to get a real, tunable vertical gap
			# between the rules text above and this tag, rather than the
			# tag reading as just another (smaller) line of it.
			var gap := roundi(chain_role_gap_px * _scale_factor)
			return "\n[font_size=%d]\n[/font_size][font_size=%d][color=#%s]%s[/color][/font_size]" % [gap, size, HudPalette.SYSTEM_TEXT.to_html(false), role_name]
		_:
			return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()
		return
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_started_on_card = true
		return
	# A real click needs the matching release too - a mouse-wheel scroll
	# tick is ALSO an InputEventMouseButton with pressed briefly true
	# (button_index WHEEL_UP/WHEEL_DOWN), which the button_index check
	# above already excludes, but this press/release pairing is the actual
	# "click, not drag" guarantee: only fires if the button that went down
	# on this card is the one coming back up, not some unrelated release.
	if _press_started_on_card:
		_press_started_on_card = false
		if card_data != null:
			# emit() sends the signal out. "card_clicked.emit(card_data)"
			# is the announcement — see Battle's script for who's listening.
			card_clicked.emit(card_data)

# --- Hand fan (see battle.gd's fan_max_tilt_deg/arc_rise_px for the
# whole feature's own doc) ---
#
# This card doesn't know it's in a fanned hand, what its own position in
# that hand is, or how big the hand currently is - same "Battle owns the
# context, Card only renders what it's told" split every other per-
# instance knob here already follows (set_affordable(), set_chain_
# available(), etc.). battle.gd computes the actual angle and vertical
# offset from hand size and index; this just stores and applies both.
#
# ONE call, not two separate setters (2026-08-25, arc pass) - rotation
# and vertical offset are always set together by _update_hand_fan()'s
# own per-card loop, so there's no real "just the rotation changed"
# case that would justify keeping them as independent entry points.
#
# radians/px, matching Control.rotation/position's own units - battle.gd
# converts from its own degree-and-pixel exports before calling this, so
# nowhere in THIS file needs deg_to_rad() scattered through it.
func set_fan_transform(rotation_radians: float, vertical_offset_px: float) -> void:
	_fan_rotation = rotation_radians
	_fan_vertical_offset = vertical_offset_px
	# Only snaps the visual immediately while genuinely at rest - a card
	# currently raised (hovered or armed) is deliberately straightened/
	# lifted past this (see _play_hover_tween()'s own note) and must STAY
	# that way through whatever triggered this call (e.g. a card drawn
	# mid-hover); the new fan transform still takes effect the moment it
	# next returns to rest, since every _play_hover_tween() call site
	# reads _fan_rotation/_fan_position() fresh. _is_dealing is the same
	# kind of exclusion, for the same reason - see that var's own doc.
	if not _is_hovered and not _armed and not _is_dealing:
		visual.rotation = _fan_rotation
		visual.position = _fan_position()

# The rest-state target for visual.position - Vector2.ZERO with no arc
# (every non-hand context), or shifted vertically by this card's own
# arc offset when one's been set. A named function (not just inlining
# Vector2(0, _fan_vertical_offset) at each of its three call sites below)
# so "what does resting actually mean now" has exactly one definition.
func _fan_position() -> Vector2:
	return Vector2(0, _fan_vertical_offset)

# --- Draw arrival (see battle.gd's draw_arrival_stagger_sec/draw_
# arrival_travel_sec, and _draw_cards()'s own doc for the full sequence
# this is one piece of) ---
#
# A freshly-drawn card visually starts at the draw pile's own screen
# anchor and travels to its real hand slot. `self` (this root Control)
# never moves - HandContainer still owns its slot exactly like every
# other hand card - only `visual` does, via the SAME top_level trick set_
# armed()'s own un-arm branch already uses to convert an absolute screen
# point into a tween that lands exactly on this card's real LOCAL resting
# transform (_fan_position()/_fan_rotation - both already correct by the
# time this runs, set by set_fan_transform() just before it - see battle.
# gd's own call order in _draw_cards()).
#
# Two separate steps, not one - battle.gd needs a process_frame to pass
# between them (HandContainer's own HBoxContainer sort is DEFERRED, so
# THIS card's global_position - read by begin_draw_arrival() below - is
# stale garbage the instant it's created; place_at_draw_origin() doesn't
# have that problem, since the ORIGIN it's given is an already-settled,
# unrelated node's position, not this card's own).

# Step 1 of 2 - instantly (no tween) snaps `visual` to the draw pile's
# own screen point, already at this card's FINAL resting tilt (no
# rotation flourish, per this feature's own brief - only position
# travels, never rotation or scale). Called the same frame this card is
# created, before anything ever renders, so there's no flash-at-rest-
# then-jump-to-origin. mouse_filter drops to IGNORE for the same reason
# reward_screen.gd's own static card reveal uses it - a card mid-flight
# has no business responding to hover, and without this, the mouse
# simply resting over the hand while cards fly UP into it would fire
# _on_mouse_entered() mid-tween, fighting _arrival_tween for the same
# visual.position.
func place_at_draw_origin(from_global_position: Vector2) -> void:
	_is_dealing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Same elevated-z_index dance _on_mouse_entered()/set_armed() already
	# use, and for the same reason: a card mid-flight has to render ABOVE
	# whichever already-resting neighbors it crosses over on its way to
	# its own slot, not slide visually underneath them. Mirrored onto
	# `visual` too, not just self - see set_armed()'s own note on why
	# top_level makes `visual` its own z-root, ignoring self's z_index
	# entirely for actual draw order.
	z_index = _NEXT_ELEVATED_Z_INDEX
	_NEXT_ELEVATED_Z_INDEX += 1
	visual.z_index = z_index
	visual.top_level = true
	visual.rotation = _fan_rotation
	visual.scale = Vector2.ONE
	visual.position = from_global_position - visual.pivot_offset

# Step 2 of 2 - begins the actual travel from wherever place_at_draw_
# origin() left `visual` to this card's real hand slot. Position is the
# ONLY thing tweened (restrained per this feature's own brief: no
# rotation flourish, no scale-punch on landing) - TRANS_SINE/EASE_OUT
# matches every other Card tween's own easing (_play_hover_tween(), the
# shake, ...), a slight ease-out, never a bounce.
func begin_draw_arrival(travel_duration: float) -> void:
	var target_screen_position: Vector2 = global_position + _fan_position()
	if _arrival_tween:
		_arrival_tween.kill()
	_arrival_tween = create_tween()
	_arrival_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_arrival_tween.tween_property(visual, "position", target_screen_position, travel_duration)
	_arrival_tween.finished.connect(_finish_draw_arrival)

# Instantly completes the arrival regardless of progress - the natural
# end of a full travel (via _arrival_tween's own finished signal above)
# AND the forced end when battle.gd's global deal-skip fires (see skip_
# draw_arrival() below, its own public entry point for that second case).
# Re-reads _fan_position()/_fan_rotation FRESH rather than trusting
# whatever begin_draw_arrival() originally aimed at - if a LATER card's
# own arrival caused _update_hand_fan() to recompute this card's own
# target while it was still traveling (guarded from actually SNAPPING
# mid-flight by set_fan_transform()'s own _is_dealing check above, but
# the stored _fan_rotation/_fan_vertical_offset values still update),
# this is what corrects the very last bit of drift instead of settling
# on a now-stale point.
func _finish_draw_arrival() -> void:
	_is_dealing = false
	visual.top_level = false
	visual.position = _fan_position()
	visual.rotation = _fan_rotation
	# Unconditional, unlike _on_mouse_exited()'s own conditional reset -
	# this card can never be hovered/armed while _is_dealing (mouse_
	# filter is IGNORE the whole time above), so there's no raised state
	# to preserve on the way out, only ever this one to clear.
	visual.z_index = 0
	z_index = 0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_arrival_tween = null

# battle.gd's own public entry point for a global deal-skip - kills
# whatever's still in flight (place_at_draw_origin() may have run with no
# begin_draw_arrival() yet, or a travel tween may be genuinely mid-
# flight) and jumps straight to _finish_draw_arrival()'s own final state
# either way. Safe to call on a card that was never dealt at all
# (_is_dealing already false, _arrival_tween already null) - a harmless
# no-op landing on the same resting values it's already at.
func skip_draw_arrival() -> void:
	if _arrival_tween:
		_arrival_tween.kill()
	_finish_draw_arrival()

# --- Affordability + refusal ---
#
# This card doesn't know what energy is, how much the player has, or
# whether it can currently be played — Battle owns all of that (see
# battle.gd's `energy` state and _update_hand_affordability()). Battle
# just tells this card the answer via these two functions, and this
# script only handles what that answer *looks like*. That split keeps all
# the actual resource logic in one place, so if a future character uses a
# different resource system, only battle.gd's rules need to change — not
# every card.

# Battle calls this whenever energy or the hand changes, so a card's dim
# state always matches whether it's currently playable.
func set_affordable(is_affordable: bool) -> void:
	modulate = AFFORDABLE_MODULATE if is_affordable else UNAFFORDABLE_MODULATE

# Battle calls this when the player clicks this card but doesn't have
# enough energy to play it — a quick shake so the click clearly
# registered without anything actually happening.
func play_refused() -> void:
	if _shake_tween:
		_shake_tween.kill()
	_shake_tween = create_tween()
	# Rocks visual right, then left (twice as far, to swing through
	# center), then back to rest. This animates "rotation," a different
	# property than the hover tween's "position"/"scale," so a shake and
	# a hover can play at the same time without fighting over the same
	# value.
	#
	# Shakes AROUND whatever rotation is already current (2026-08-25,
	# hand-fan pass), not literal 0 - a fanned card sitting at rest is
	# tilted (visual.rotation == _fan_rotation, not 0), and refusing a
	# click there should rock around ITS OWN tilt, not snap upright mid-
	# shake and back. Reads correctly for a raised/straightened card too
	# (base_rotation is just 0 there), so this needs no separate case for
	# fanned-vs-hovered.
	var base_rotation := visual.rotation
	_shake_tween.tween_property(visual, "rotation", base_rotation + SHAKE_ROTATION, SHAKE_LEG_DURATION)
	_shake_tween.tween_property(visual, "rotation", base_rotation - SHAKE_ROTATION, SHAKE_LEG_DURATION * 2)
	_shake_tween.tween_property(visual, "rotation", base_rotation, SHAKE_LEG_DURATION)

# --- Hover animation ---
#
# When hand cards overlap, Godot draws (and hit-tests clicks against)
# overlapping nodes in "z_index" order: whichever one has the highest
# z_index wins, regardless of where it sits in the scene tree. Every Card
# starts at the default z_index of 0, so with several overlapping, the
# one added most recently just happens to end up on top. Bumping this
# card's z_index while hovered guarantees it's the one drawn on top *and*
# the one that receives the click — that's what stops a click from
# "falling through" to the card behind it.
#
# We deliberately do NOT reorder this node among its HandContainer
# siblings (there's a move_to_front() that does that) to achieve the same
# thing, because HBoxContainer uses sibling order to decide left-to-right
# position — reordering would yank the card sideways to the end of the
# hand instead of just lifting it in place.
#
# FIXED (2026-08-25, hand-fan pass) - elevated z_index used to be a
# single shared constant (1) for every raised card, which was only ever
# safe because raised cards essentially never overlapped EACH OTHER. A
# fanned hand (see set_fan_rotation() below) and any hand tight enough to
# force negative separation (_update_hand_spacing()) both make that
# false: quickly moving the mouse from card A to card B can leave A still
# mid-way through its return tween (see _on_mouse_exited()'s own note on
# why z_index isn't dropped until that tween finishes) at the exact
# moment B raises - both would be pinned to the SAME z_index (1), and the
# tie-break (scene order) has no reason to favor whichever one the mouse
# is ACTUALLY over right now. _NEXT_ELEVATED_Z_INDEX (a static counter,
# shared across every Card) hands out a strictly increasing value each
# time a card raises for any reason (hover or armed) - the most recently
# raised card is always unambiguously on top of every other raised card,
# not just tied with them, while every resting card stays at the fixed 0
# below (its comment above still explains why resting ties, unlike this
# one, are fine as-is: they only ever need to lose to a raised card, and
# resting-vs-resting order already matches the fan's own left-behind-
# right stacking for free).
static var _NEXT_ELEVATED_Z_INDEX: int = 1

func _on_mouse_entered() -> void:
	_is_hovered = true
	z_index = _NEXT_ELEVATED_Z_INDEX
	_NEXT_ELEVATED_Z_INDEX += 1
	card_hover_changed.emit(card_data, true)
	if not _armed:
		_play_hover_tween(hover_offset, hover_scale, 0.0)

func _on_mouse_exited() -> void:
	_is_hovered = false
	_press_started_on_card = false # A drag-off cancels the pending click - press and release must both land on this card.
	card_hover_changed.emit(card_data, false)
	if _armed:
		return # Armed holds its raised pose regardless of the mouse - see set_armed().
	var tween := _play_hover_tween(_fan_position(), Vector2.ONE, _fan_rotation)
	# Only drop back below neighboring cards once the return animation has
	# actually finished, so it doesn't visually duck behind a neighbor
	# while it's still mid-shrink.
	tween.finished.connect(func(): z_index = 0)

# --- Targeting (armed state) ---
#
# Battle calls this when this card is the one waiting for a target click
# (see battle.gd's _begin_targeting()/_cancel_targeting()) - REWORKED
# (2026-08-25, center-slot pass) from "raised in place, wherever this
# card's hand slot happens to be" to a fixed on-screen point shared by
# every card regardless of slot (Slay the Spire's own selected-card
# pattern - see battle.gd's armed_card_center_y_px). A right-side hand
# card's old raised-in-place pose sat over the enemy sprite/HP bar/
# flavor text; a left-side one didn't - narrowing the hand couldn't fix
# this on its own because the CARD, not the hand, was too big for that
# spot. One shared destination fixes it for every slot at once.
#
# The trick: `visual` (not this root Control - see get_targeting_
# anchor_position()'s own note on why the split matters) goes top_level
# = true for the whole armed duration, including both transit
# animations. A top_level CanvasItem's position/rotation/scale ARE its
# effective screen transform directly, with no parent transform
# composed in - which is exactly what makes ONE target position
# meaningful no matter which hand slot this card's root Control actually
# sits in. That root never moves and is never removed from HandContainer
# - the slot stays reserved and the rest of the hand never reflows, for
# free, just by leaving that node alone entirely.
#
# Reuses _play_hover_tween() - the SAME tween/properties hover already
# animates, just fed an absolute screen point instead of a hand-relative
# one - rather than a second competing tween. _on_mouse_entered()/_on_
# mouse_exited() both stand down while armed so real hover can't fight
# the held pose, same as before this rework.
func set_armed(active: bool, target_global_position: Vector2 = Vector2.ZERO) -> void:
	_armed = active
	if active:
		z_index = _NEXT_ELEVATED_Z_INDEX
		_NEXT_ELEVATED_Z_INDEX += 1
		modulate = ARMED_MODULATE
		# Capture where `visual` is actually rendering RIGHT NOW (hand
		# slot's own rest/hover pose) before flipping top_level - then
		# immediately re-set position to that same screen point under the
		# new interpretation, so the flip itself produces zero visible
		# jump (verified headlessly - see this feature's own commit).
		# Only THEN does the tween below start moving it toward the real
		# target, so it visibly departs from wherever it actually was,
		# hovered or not.
		var current_screen_position: Vector2 = visual.global_position
		visual.top_level = true
		visual.z_index = z_index
		# MIRRORED onto visual, not just left on self (2026-08-26, armed-
		# z-order fix) - top_level makes a CanvasItem its own z-root
		# (Godot computes its effective z-index from ITS OWN z_index alone,
		# ignoring z_as_relative accumulation through a parent it no longer
		# has for rendering purposes). self's elevated z_index above did
		# nothing for what's actually on screen the instant top_level
		# engages, since `visual` - the node that's actually moving and
		# rendering - stopped inheriting it right here. This is the actual
		# cause of the reported bug (an armed card drawing BEHIND enemy
		# sprites) - self's counter value was always being set, just on a
		# node that had already stopped mattering for draw order.
		visual.position = current_screen_position
		# `position` is visual's PIVOT-RELATIVE ORIGIN, not its center -
		# under Control's transform order (translate(position) *
		# translate(pivot) * rotate * scale * translate(-pivot)), the
		# point that lands exactly on `position` is the pivot's own
		# ORIGIN corner, while the pivot itself (the card's true visual
		# center, which is what "centered in the window" actually means)
		# sits at position + pivot_offset, unaffected by scale/rotation.
		# target_global_position is battle.gd's intended CENTER point, so
		# the origin has to aim short of it by pivot_offset, or the
		# rendered card ends up offset right-and-down by ~pivot_offset
		# instead of centered (caught live - see this fix's own commit).
		_play_hover_tween(target_global_position - visual.pivot_offset, armed_scale, 0.0)
		return
	# Un-arming is only ever reached from an affordable card (see battle.
	# gd's _on_card_clicked()) - AFFORDABLE_MODULATE is always the right
	# color to return to, never UNAFFORDABLE_MODULATE.
	modulate = AFFORDABLE_MODULATE
	var target_local_position := hover_offset if _is_hovered else _fan_position()
	var target_scale := hover_scale if _is_hovered else Vector2.ONE
	var target_rotation := 0.0 if _is_hovered else _fan_rotation
	# `visual` is still top_level right now (mid this exact call) - its
	# "position" still means an absolute screen point, not the hand-
	# relative one above, until the tween below actually arrives and this
	# root's own finished callback flips it back. This root Control never
	# rotates or scales (only `visual` ever does - set_fan_transform()/
	# _play_hover_tween()), so its own global_position plus that local
	# target is exactly the screen point the local target would resolve
	# to once top_level comes back off - letting the whole return trip
	# happen in the same screen space the armed animation used, with no
	# separate "local" tween branch needed.
	var target_screen_position: Vector2 = global_position + target_local_position
	var tween := _play_hover_tween(target_screen_position, target_scale, target_rotation)
	tween.finished.connect(func():
		visual.top_level = false
		visual.position = target_local_position
		visual.z_index = 0
		# ALWAYS cleared here, unlike self's own z_index just below (which
		# only resets when not hovered) - visual's mirrored elevation (see
		# set_armed()'s arm branch above) only ever existed to survive
		# top_level severing it from self's z_index; the moment top_level
		# goes false again, right here, normal z_as_relative inheritance
		# from self takes back over. Leaving visual's own z_index at its
		# stale armed value would ADD to self's (elevated or not) instead
		# of just deferring to it - harmless in direction but wrong in
		# magnitude, and pointless self.z_index still carries whatever
		# elevation is actually needed post-hover on its own.
		if not _is_hovered:
			z_index = 0
	)

# The on-screen point the target line (see target_line.gd) should
# originate from while this card is armed. NOT this Control's own
# get_global_rect() - arming (see set_armed() above) tweens `visual`'s
# position/scale, never this root Control's, so this root's own rect
# always reports the resting slot position/size regardless of how far
# `visual` has actually lifted and grown - or, since the center-slot
# rework, flown clear across the screen under top_level. get_global_
# transform() (not get_global_rect(), which Control deliberately leaves
# rotation/scale out of) is what makes this correct mid-tween too, not
# just once one settles, and needed NO change for the top_level rework -
# it always reports a CanvasItem's true screen transform regardless of
# top_level, same as everywhere else in Godot (verified headlessly
# against this exact node - see this feature's own commit) - top-center
# of `visual`'s own local rect, carried through whatever position/scale/
# rotation it currently has.
func get_targeting_anchor_position() -> Vector2:
	return visual.get_global_transform() * Vector2(visual.size.x / 2.0, 0.0)

# A Tween animates a property smoothly from its current value to a target
# value over time, instead of it jumping there instantly. This one
# animates the Visual node's position, scale, AND rotation at the same
# time (set_parallel(true)) so the card rises, grows, and straightens (or
# settles back into its own arc position/tilt) together.
#
# target_rotation is an explicit parameter (2026-08-25, arc pass) rather
# than inferred from target_position - it used to check "target_position
# == Vector2.ZERO" to mean "this is the resting case," which broke the
# moment resting stopped meaning literally Vector2.ZERO (see
# set_fan_transform()'s own arc-offset doc). Every call site already
# knows which case it's in, so it's more robust to just have it say so.
func _play_hover_tween(target_position: Vector2, target_scale: Vector2, target_rotation: float) -> Tween:
	if _hover_tween:
		# Stop whatever hover animation is already in progress first, so
		# quickly wiggling the mouse in and out doesn't queue up competing
		# animations. kill() stops it immediately without firing its
		# "finished" signal.
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_parallel(true)
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_property(visual, "position", target_position, hover_duration)
	_hover_tween.tween_property(visual, "scale", target_scale, hover_duration)
	_hover_tween.tween_property(visual, "rotation", target_rotation, hover_duration)
	return _hover_tween

# --- Skill commit-and-exit (see this section's own export doc above) ---

# Pushes the card forward and scales it up slightly - see skill_commit_
# offset/skill_commit_scale's own doc. Kills _hover_tween too, not just
# _skill_tween - a card can be clicked while still mid-hover-raise, and
# both tweens fighting over the same visual.position/scale every frame
# would read as a stutter, not a clean commit. Returns the Tween so
# battle.gd can `await tween.finished` for just this phase - see play_
# exit() below for why the rest of the sequence is deliberately NOT
# returned/awaited the same way.
func play_commit() -> Tween:
	if _hover_tween:
		_hover_tween.kill()
	if _skill_tween:
		_skill_tween.kill()
	_skill_tween = create_tween()
	_skill_tween.set_parallel(true)
	_skill_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_skill_tween.tween_property(visual, "position", skill_commit_offset, skill_commit_duration_sec)
	_skill_tween.tween_property(visual, "scale", skill_commit_scale, skill_commit_duration_sec)
	return _skill_tween

# Slides the card the rest of the way out and fades it, then frees this
# whole Card instance once that finishes. Fire-and-forget BY DESIGN -
# battle.gd's own _play_card() never awaits this call (see its own doc):
# every bit of that function's bookkeeping (energy/hand/pile state,
# chain triggers, label refreshes) is already complete by the time this
# runs, and playing a SECOND card while this exit is still animating has
# to work immediately, with no queueing - which holds automatically here
# since nothing outside this Tween's own callback is waiting on it.
func play_exit() -> void:
	if _skill_tween:
		_skill_tween.kill()
	_skill_tween = create_tween()
	_skill_tween.set_parallel(true)
	_skill_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_skill_tween.tween_property(visual, "position", skill_exit_offset, skill_exit_duration_sec)
	_skill_tween.tween_property(visual, "modulate:a", 0.0, skill_exit_duration_sec)
	_skill_tween.finished.connect(queue_free)
