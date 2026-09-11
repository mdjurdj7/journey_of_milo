extends Node
# Registered as a scene autoload (hud_palette.tscn, see project.godot's
# [autoload] section) - same reasoning SunkenWorksPalette already gives
# for itself: @export only shows up in the Inspector when the autoload
# has a scene to attach to, and these values are meant to be eyeballed
# and retuned from there, not baked constants a retune would mean
# editing this file's own source for.
#
# The HUD's own shared palette (2026-08-27, VitalsBar palette pass) -
# deliberately BIOME-INDEPENDENT, unlike SunkenWorksPalette: HUD elements
# are system-voice and have to read against ANY biome backdrop, not just
# the Sunken Works' own sky/ground tones, so nothing in here may
# reference or derive from a biome palette. Seeded with VitalsBar's own
# colors only this pass (trough/border/fill) - other HUD elements
# (Toll, energy pips, StatusBadgeRow, etc.) are NOT migrated here yet,
# on purpose; each still owns its own colors until a future pass decides
# to move them too.
#
# First non-HUD consumer: SYSTEM_TEXT below (2026-08-27, card-legibility
# pass) - card.gd's rules text isn't a HUD element, but it's the same
# KIND of thing this file exists for: system-voice text that has to read
# as recessive-but-legible regardless of which biome/screen it's on top
# of. "Biome-independent" turned out to be the right scope test, not
# "is this literally part of the HUD."
#
# No RALLY entry, deliberately - the Rally slice's color is DERIVED from
# whichever fill is currently active (see vitals_bar.gd's own
# _apply_bar_color()), not a fixed constant. A fixed entry here would be
# read by nothing (misleading - it would get "tuned" later with zero
# effect), and was rejected for the same reason it'd be wrong at
# runtime: a fixed color is only ever safe against ONE fill state, not
# every one that exists (HudPalette.FILL, low_hp_color, and whatever
# gets added later).
#
# Direct-read consumer pattern, same as SunkenWorksPalette's own one
# consumer (battle_background.gd): read HudPalette.FILL/TROUGH straight
# at the point of use, no local @export mirroring them on the
# consumer's own script - that's what makes a retune here a genuine
# one-place edit.
#
# No dedicated BORDER entry either (removed 2026-08-27, border-weight
# pass) - vitals_bar.gd's own bar_border_color @export now defaults to
# TROUGH's exact value directly (one frame tone, border continuous with
# the trough, rather than two independently-chosen darks), so a separate
# BORDER entry would be read by nothing - same "an entry nothing reads
# is misleading" reasoning that already removed RALLY from here.
# bar_border_color stays a real per-instance @export regardless (not a
# direct read like FILL/TROUGH) - the border specifically needs to
# lighten per-context against some backdrops, which is a per-instance
# override, not a palette-wide change.
#
# ALL_CAPS var names, matching SunkenWorksPalette's own convention -
# these read as named constants from every consumer's perspective, just
# Inspector-editable ones rather than baked ones. Functionally a plain
# @export var either way; the naming is cosmetic.

@export var TROUGH: Color = Color(0.117647, 0.109804, 0.101961, 1) # #1E1C1A
# The bar's own dark, opaque background/trough - the contrast frame
# every fill color reads against, so the fill only ever has to contrast
# with THIS, never with whatever's behind the whole HUD element.

@export var FILL: Color = Color8(77, 76, 72) # #4D4C48
# The HP bar's own DEFAULT normal fill now (2026-09-07, dark-fill-
# contrast pass) - NO LONGER read directly at the point of use in
# vitals_bar.gd; that script now has its own fill_color @export
# (defaulting to this same constant) so the player's own bar can
# override it to a dark red while every enemy - and the field HUD's own
# bar, which never overrides fill_color either - keeps reading THIS
# value unchanged. See vitals_bar.gd's fill_color doc for the full
# split. Still read directly by block_badge.gd (own fill) and absorb_
# badge.gd (own fill, .lightened(0.3) of this) - deliberately NOT
# switched to vitals_bar.gd's new per-instance export, so both badges
# stay on this neutral value regardless of which bar (player's now-red
# one included) they're attached to.
#
# DARKENED (2026-09-07, dark-fill-contrast pass) from #74736E (116, 115,
# 110, the previous muted-mid-tone pass) - live-measured at 0.41 luma
# against a 0.48 ground directly behind the bars, a 0.07 gap that read
# as effectively invisible; matching the palette instead of separating
# from it was backwards for a bar that has to read as an object ON TOP
# of the scene, the same dark-on-pale register the figures themselves
# use. New value: standard luma 0.22 (was 0.45), +4 R-B (was +6) - a
# real value drop well below the ground, still near-neutral rather than
# reading as any particular hue. Rally (see vitals_bar.gd's own _apply_
# bar_color()/rally_pool_saturation_scale/rally_value_scale docs) is
# derived from whichever fill_color is active per-instance now, not
# from this constant directly - still re-picks up whatever base it's
# handed automatically, no code change needed on its side.
#
# RAISED again (2026-09-07, follow-up) from #393835 (57, 56, 53, luma
# 0.22) to #4D4C48 (77, 76, 72, luma ~0.30) - R-B ~5 (was 4), essentially
# unchanged: this moves Value only, not hue/chroma. Block/Absorb badges
# (block_badge.gd/absorb_badge.gd) still read this directly, so both
# lighten by the same step - see their own callers for the resulting
# luminance.

@export var SYSTEM_TEXT: Color = Color(0.22, 0.24, 0.29, 1) # #383D4A
# The muted-but-legible floor for system-voice text - recessive relative
# to a title/name element sitting near it, never illegible on its own.
# First consumers: card.gd's rules text (DescriptionLabel) and its
# Opener/Closer chain-role tag (_chain_role_suffix()), both of which read
# this directly with no local @export mirroring it - see card.gd's own
# "Card Fonts" note for why a per-card override was checked for and
# found unnecessary.
#
# MOVED here from two separate card.gd exports (2026-08-27, HudPalette
# migration) - description_font_color and chain_role_color used to be
# independently @export'd, and only matched by COINCIDENCE (chain_role_
# color's own old doc even said so: "this value is description_font_
# color's own exact tone"). That coincidence is exactly what let a real
# bug ship silently: the 2026-08-25 warm-paper repaint changed card.gd's
# description_panel_color (the background this text sits on) without
# anyone re-checking either text color against the new background, since
# nothing structurally linked them. One shared value, read directly by
# every consumer, makes that class of drift impossible - there's no
# second copy left to forget.
#
# DARKENED from (0.3, 0.32, 0.37) in the same pass, for the same
# underlying reason: measured (WCAG relative luminance) against card.gd's
# CURRENT description_panel_color (0.82, 0.78, 0.68 - the warm-paper
# value), the old color landed at only ~4.68:1, barely clearing the
# 4.5:1 "normal text" AA floor with almost no headroom - not what its own
# now-stale doc claimed (~5.0:1, measured against the PRE-repaint
# background, 0.78/0.81/0.87, which no longer exists anywhere in card.gd).
# This value measures ~6.4:1 against the same current background -
# clearly darker and more confident without going near-black (nowhere
# close to it - this is still a soft cool slate, not ink). Same hue
# family/channel spacing as the value it replaces, just proportionally
# darker.
#
# This contrast figure describes card.gd's description_panel_color
# SPECIFICALLY - re-check it (same WCAG relative-luminance method) if
# that panel color, or any other background this color is read against,
# ever changes. That re-check is the whole reason this now lives in ONE
# place instead of two.

@export var WORLD_TEXT: Color = Color(0.2, 0.17, 0.13, 1)
# The world-voice register's own color (2026-08-30, field-palette-retune
# color fix) - Spectral serif, full-color/authored voice, the counterpart
# to SYSTEM_TEXT above rather than a variant of it: the two-register
# split is still font + treatment (serif/full-color vs. sans/muted), this
# is just that first register's own color living in one shared place
# instead of four independently-drifting per-file copies (field_npc.gd/
# field_heap.gd/field_curio.gd/field_chest.gd's own prompt labels, all
# read this directly now, no local @export mirrors).
#
# DARK, not pale (2026-08-30 palette retune) - the field/battle palette
# retune moved this region to dark figures and dark text against a pale
# ground, the same direction SYSTEM_TEXT's own card-panel background
# already reads against; the old pale-cream value this replaces was
# authored for a dark background that no longer exists anywhere in the
# region. See field_room.gd's own background_plane_luminance_floor/
# background_detail_luminance_floor doc for that retune's own floors -
# this is a text color, not a background one, so it isn't checked by
# _validate_background_contrast() itself, but it has to read against the
# SAME pale ground that validator enforces.

@export var MAP_CURRENT: Color = Color(0.85, 0.75, 0.2, 1)
# The run map's "you are here" highlight - map_screen.gd's own is_current
# check. MOVED here from a local CURRENT_COLOR const (2026-08-28, map-
# legibility pass) - same value, unchanged, just relocated: the map is
# system-voice chrome that has to read against whatever room type/biome
# happens to be selected, the same "biome-independent" test SYSTEM_TEXT's
# own doc above already applies. First non-VitalsBar/non-text consumer.

@export var MAP_REACHABLE: Color = Color(0.3, 0.75, 0.4, 1)
# The run map's live-choice highlight (map_screen.gd's is_reachable check)
# - the "you can go here" full-weight state, same value as the old local
# REACHABLE_COLOR const it replaces (2026-08-28, map-legibility pass).
#
# No MAP_VISITED entry - VISITED (map_screen.gd's "behind" state) is
# still DERIVED from TROUGH above (already this palette's designated
# recessive/background dark), blended toward map_screen.gd's own
# background color via its own visited_blend_amount export - "how much
# to blend" is a per-consumer feel decision the same way FILL/TROUGH's
# own DIRECT reads already are, not a second baked color this palette
# would need to keep in sync with TROUGH by hand if it were ever retuned.
# ALWAYS full alpha, never transparent, so the map's connection lines
# never show through a dimmed node (see map_screen.gd's own _node_color()
# for the 2026-08-28 opacity-fix pass that established this).

@export var MAP_UNREACHABLE: Color = Color(0.4, 0.4, 0.46, 1)
# UNREACHABLE (map_screen.gd's "future, not yet reachable" state) does
# NOT derive from TROUGH (2026-08-28, widen-the-gap pass) - it used to,
# blended toward the background exactly like VISITED, and the two were
# reported as near-indistinguishable: measured, TROUGH (0.118, 0.110,
# 0.102) and map_screen.gd's own background color (0.13, 0.13, 0.16) are
# only ~0.06 apart in raw RGB distance, so EVERY color reachable by
# blending between them - the entire old VISITED/UNREACHABLE range - was
# confined to that same tiny slice near-black. No blend_amount retune
# could have fixed that; the base itself needed to move. This is a real,
# distinctly lighter neutral gray - "present but inactive," not "almost
# gone" - blended toward the SAME background color via map_screen.gd's
# own unreachable_blend_amount, at a much smaller blend amount than
# VISITED's, since this state doesn't need to fade much to already read
# as clearly less prominent than REACHABLE's saturated green.
#
# DELIBERATE HEADROOM (2026-08-28) - a fifth state is coming: nodes that
# were once reachable but got foreclosed by the path actually taken.
# This value was picked to leave clear room BELOW it (toward TROUGH/the
# background) for that state to slot into, rather than maximizing
# distance from the background outright - see map_screen.gd's own
# _node_color() doc for the measured gap this leaves. A reasonable
# starting point for that future color, not yet added: roughly the OLD
# pre-migration flat UNREACHABLE_COLOR, ~(0.22, 0.22, 0.26) - sitting
# comfortably between the background and this value.
