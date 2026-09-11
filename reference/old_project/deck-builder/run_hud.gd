extends VBoxContainer
class_name RunHUD
# The run-context half of what used to be field_room.tscn's own inline
# UI/HUD block, extracted (2026-08-26) so the card reward screen can show
# the same HP/room context the field already does - every Toll card
# keys off HP (Paid in Pain's below-half clause, Retaliation asking the
# player to eat a hit), so a reward choice made with no visible HP was a
# real information gap, not just a cosmetic one.
#
# Deliberately does NOT include battle-scoped state (Toll, energy, block,
# hand/draw/discard counts) - those are meaningless outside combat, and
# battle.gd's own HUD stays a separate, unrelated implementation. This is
# specifically "what's true about the RUN right now," nothing that only
# means something mid-fight.
#
# No gold display any more (2026-09-05, gold-removal pass) - GoldDisplay
# used to sit here as a second child, grouped with the HP bar in a
# VitalsStrip HBoxContainer in compact mode (see _apply_compact_styling()'s
# own history for what that used to build). Removed outright, node and
# code both, not just hidden - this HUD context reads HP only now.
#
# Fully self-sufficient - every label sets its own text from RunState/
# RoomState here in _ready(), rather than requiring whatever scene owns
# this to remember to push values in (field_room.gd used to do exactly
# that; see its own history for the lines this replaced). The one
# exception is player_hp_bar, exposed as a public field below - ShopWindow
# needs the actual VitalsBar node to push live HP updates into when the
# player rests, which can't be done through this scene's own labels alone.

@onready var player_hp_bar: VitalsBar = $PlayerHPBar
@onready var room_label: Label = $RoomLabel
@onready var room_type_label: Label = $RoomTypeLabel

const ROOM_NAME_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# Same world-voice serif field_heap.gd/field_npc.gd/field_curio.gd/
# field_chest.gd's own OFFER_FONT/PROMPT_FONT constants already preload
# (2026-09-05, room-label pass) - RoomTypeLabel was previously font-
# isolated (no font override anywhere, plain project-default sans, shared
# with nothing else), so pointing it at Spectral here is a fully local
# change with no other consumer to affect.

# --- Compact styling (Field HUD quieting pass, 2026-08-27) ---
#
# false (this scene's own baked default, matching every property below -
# see each export's own doc) keeps this scene rendering exactly as it
# always has, byte-identical. true is set as an INSTANCE override on
# field_room.tscn's and reward_screen.tscn's own HUD nodes (both contexts
# that actually use RunHUD) - a branch, not a second copy of this scene,
# specifically so the two contexts can diverge further later without
# unpicking a bake. Nothing in combat reads this at all (RunHUD isn't
# used there - the player's own combat HP bar is player_battle_visual.gd's
# own separate VitalsBar instance, untouched by any of this).
@export var compact: bool = false
@export var compact_vitals_bar_width_px: float = 200.0
# vitals_bar.tscn's own baked default is 380px - wider than even
# player_battle_visual.gd's own COMBAT bar (bar_width_px = 220). Only .x
# is ever touched (see _apply_compact_styling()'s own note) - the same
# "external override, .y stays whatever bar_height_px computes" pattern
# enemy.gd/player_battle_visual.gd already use on this exact scene
# elsewhere.
@export var compact_vitals_bar_height_px: float = 11.0
# HALVED from 22 (2026-09-05, gold-removal pass - the bar's own explicit
# ask, independent of gold going away). 22 itself was already DOWN from
# vitals_bar.gd's own default of 42 (2026-08-27, vitals-strip pass) - the
# old height was sized for combat's own bar and read as a slab against an
# otherwise empty field screen. See VitalsBar.apply_compact_value_style()'s
# own doc for everything this actually has to recompute once bar_height_px
# changes out from under it post-_ready().
@export var compact_value_font_size_px: int = 12
# Small enough to read as a quiet metadata number, not resized alongside
# compact_vitals_bar_height_px's own halving - the numeral sits OUTSIDE
# the bar now (see apply_compact_value_style()'s own doc, 2026-09-05), so
# its size no longer has to fit inside the bar's own shrunk height at all.
@export var compact_value_bold_strength: float = 0.25
# Semibold, not bold (2026-09-05, explicit ask) - REPLACES the old plain
# remove_theme_font_override("font") call below, which fully undid vitals_
# bar.gd's own shared _ready()-time FontVariation (value_bold_strength,
# that export's own default 0.5) rather than dialing it back to a lighter
# weight. Applied the same way _apply_bold() itself does (a fresh
# FontVariation wrapping the label's current base font, variation_embolden
# set to this value) - see _apply_compact_styling() below. Untested
# against an actual "semibold" reference; 0.25 (half of vitals_bar.gd's
# own 0.5 "bold") is a starting guess, revisit by eye.
@export var compact_value_left_inset_px: float = 6.0
# Now the gap from the bar's own right edge to the numeral's left edge
# (2026-09-05, numeral-outside-bar pass), not an inset from the bar's OWN
# left edge the way it read before - see VitalsBar.apply_compact_value_
# style()'s own doc for the anchor math this feeds. Left at its old value
# (tuned for a much tighter, inside-the-bar placement) rather than
# retuned for this new, larger-gap context - revisit by eye if 6px reads
# too tight now that the numeral is a separate element outside the bar.
@export var compact_value_vertical_offset_px: float = 0.0
# Tunable knob (2026-09-05, tunable-knobs pass) for nudging the numeral
# up (negative) or down (positive) independent of everything else -
# shifts the WHOLE anchored box VitalsBar.apply_compact_value_style()
# builds, without touching its height, vertical_alignment (still BOTTOM -
# see that function's own doc), or any other export here. 0.0 reproduces
# today's position exactly (the box's own top/bottom offsets, both 0
# before this pass existed).
@export var compact_value_width_px: float = 80.0
# Tunable knob for the numeral's own box width, past compact_value_left_
# inset_px's gap - see VitalsBar.COMPACT_VALUE_LABEL_WIDTH_PX's own doc
# for why the exact number rarely matters (Label doesn't clip its own
# text to its rect). Matches that const's own default value; only needs
# changing if a future retune makes the numeral wide enough to matter for
# some OTHER reason (e.g. right-aligning something else against its own
# known edge).
@export var compact_vitals_bar_border_width_px: int = 1
# Down from vitals_bar.gd's own default of 3 - paired with HudPalette.
# SYSTEM_TEXT below (lighter than TROUGH, the shared default's own
# color) rather than dropping the border to 0 entirely: a hairline still
# anchors the bar against a busier room (several blobs on screen), just
# without reading as a heavy frame against flat sky.
@export var compact_room_name_font_size: int = 16
# RoomLabel's own "Room: %d" no longer shows in this mode at all (2026-
# 09-05, room-label pass - REPLACES compact_room_number_font_size/
# compact_room_type_font_size, a pair sized for two side-by-side labels
# that no longer both render). RoomTypeLabel alone carries this row now,
# promoted from 13 (metadata, subordinate to the vitals strip) to 16 -
# still well under RoomLabel/RoomTypeLabel's own baked non-compact
# default of 22, but a bare place name in Spectral/world-voice register
# (see _apply_compact_styling() below) reads as underweight at the old
# metadata size. Not pushed further (e.g. to field_heap.gd's own 24px
# OFFER_FONT default) - that's a fuller hierarchy/alignment pass this
# one doesn't attempt.
# compact_meta_row_separation_px is GONE (2026-09-05, room-label pass) -
# that gap only ever meant something between TWO side-by-side labels;
# RoomTypeLabel is the row's only content now, so there's nothing left
# for it to separate.

func _ready() -> void:
	room_label.text = "Room: %d" % RunState.room_number
	room_type_label.text = _room_type_display_name(RoomState.current_room_type)
	# Initial snap, then a live subscription (2026-09-05, HP-signal pass) -
	# same "_snap() once, then connect()" shape gold_display.gd's own
	# _ready() already establishes for gold. REPLACES the old one-time-pull
	# stance (a plain refresh_from_run_state() call, with field_room.gd/
	# shop_window.gd/pay_window.gd each separately pushing into this bar
	# whenever something changed player_hp mid-room) - RunState.player_hp_
	# changed now does that job for every context, so this bar (and every
	# other player-owned VitalsBar - see player_battle_visual.gd/field_
	# interior.gd's own matching subscriptions) never goes stale again
	# without a caller needing to remember to push into it.
	player_hp_bar.refresh_from_run_state()
	RunState.player_hp_changed.connect(_on_player_hp_changed)
	if compact:
		_apply_compact_styling()

func _on_player_hp_changed(new_hp: int, new_max_hp: int) -> void:
	player_hp_bar.update_hp(new_hp, new_max_hp)

# Everything below only ever runs when compact is true (see its own
# doc) - every property touched here has a real, documented reason it
# can't just be a second set of baked values in the .tscn (the whole
# point of a branch over a second bake - see compact's own doc), so this
# function is where that reasoning actually lives, not scattered across
# each export's own comment.
func _apply_compact_styling() -> void:
	# HP bar width - see compact_vitals_bar_width_px's own doc for why
	# only .x is touched. size_flags_horizontal also has to change here,
	# not just custom_minimum_size/size: RunHUD's own VBoxContainer
	# stretches a FILL (Godot's own default, and this scene's baked one -
	# confirmed live, even the UNCHANGED bar actually renders at RunHUD's
	# own 400px width today, not its baked 380 custom_minimum_size) child
	# to fill whatever cross-axis space it's given, which would silently
	# re-widen this right back out. SHRINK_BEGIN stops that - VitalsBar's
	# OWN internal HPBar/BarBorder children fill to ITS width, so this is
	# the one property that actually controls what renders, not just what's
	# reserved.
	player_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	player_hp_bar.custom_minimum_size.x = compact_vitals_bar_width_px
	player_hp_bar.size.x = compact_vitals_bar_width_px

	# HP bar height + value label position/color - all one call (2026-08-27,
	# vitals-strip pass; label moved OUTSIDE the bar, 2026-09-05 - see
	# vitals_bar.gd's own doc on both) because bar_height_px is, like
	# bar_border_color before it, only ever READ once inside VitalsBar's
	# own _ready() - already run by the time this function gets a chance
	# to touch it.
	player_hp_bar.apply_compact_value_style(
		compact_vitals_bar_height_px,
		compact_value_font_size_px,
		compact_value_left_inset_px,
		HudPalette.SYSTEM_TEXT,
		Color(1, 1, 1, 1),
		compact_value_vertical_offset_px,
		compact_value_width_px,
	)
	# Semibold, not bold (2026-08-27, value-weight pass; retuned 2026-09-05,
	# explicit ask) - vitals_bar.gd's shared _ready() wraps ValueLabel's
	# font in a bold FontVariation (value_bold_strength, default 0.5)
	# unconditionally, for every instance including this one, which read
	# as too heavy for a HUD meant to stay quiet. Rather than remove the
	# override outright (this pass's own predecessor - see git history),
	# this installs a SECOND FontVariation at a lighter embolden strength
	# (compact_value_bold_strength) - first removing the old one so the
	# new one wraps the label's true base font, not vitals_bar.gd's own
	# already-bold FontVariation (nesting the two would compound, not
	# replace, the emboldening). No vitals_bar.gd change needed for this -
	# value_label is already a public field, and a theme font override
	# (unlike bar_height_px/bar_border_color) has no _ready()-only timing
	# problem to work around; it takes effect the instant it's called, no
	# matter when.
	player_hp_bar.value_label.remove_theme_font_override("font")
	var semibold_font := FontVariation.new()
	semibold_font.base_font = player_hp_bar.value_label.get_theme_font("font")
	semibold_font.variation_embolden = compact_value_bold_strength
	player_hp_bar.value_label.add_theme_font_override("font", semibold_font)

	# HP bar border - bar_border_color/bar_border_width_px ARE real per-
	# instance exports on VitalsBar (see vitals_bar.gd's own doc), but
	# they're only ever READ once, inside VitalsBar's own _ready() -
	# which has already run by the time this function does (children
	# ready before their parent). override_border() (2026-08-27, purely
	# additive - see vitals_bar.gd's own doc on it) re-applies them live;
	# nothing else about vitals_bar.gd changed, so every OTHER instance
	# of that scene (every combat bar, Enemy's own included) renders
	# byte-identical to before this pass.
	player_hp_bar.override_border(HudPalette.SYSTEM_TEXT, compact_vitals_bar_border_width_px)

	# RoomLabel's own "Room: %d" prefix/index is DROPPED from the field HUD
	# (2026-09-05, room-label pass) - hidden outright, not reparented or
	# text-cleared: room_label.text is still set in _ready() above for the
	# OTHER context this same scene serves (the reward screen, non-compact,
	# untouched by this pass), and a hidden Container child reserves no
	# layout space, so RoomTypeLabel below settles into this row's own slot
	# with nothing left to make room for - no meta_row wrapper needed any
	# more now that there's only one thing left to place.
	room_label.visible = false
	# RoomTypeLabel promoted to world-voice register (2026-09-05, room-
	# label pass) - a bare place name ("Dunes") is world content by this
	# project's own two-register convention (see HudPalette.WORLD_TEXT's
	# own doc: "the two-register split is still font + treatment"), not
	# the muted system-voice metadata tone this row used while it sat
	# alongside a number. Spectral + WORLD_TEXT + OverlayStyle's outline
	# match every other world-voice label in the game (field_heap.gd/
	# field_npc.gd/field_curio.gd/field_chest.gd's own prompt labels, all
	# reading HudPalette.WORLD_TEXT directly the same way) rather than
	# inventing a new treatment for this one.
	room_type_label.add_theme_font_size_override("font_size", compact_room_name_font_size)
	room_type_label.add_theme_font_override("font", ROOM_NAME_FONT)
	room_type_label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(room_type_label, true)

	# No VitalsStrip wrapper any more (2026-09-05, gold-removal pass -
	# REMOVES the HBoxContainer the 2026-08-27 vitals-strip pass built here
	# specifically to sit the HP bar and GoldDisplay side by side). With
	# gold gone, player_hp_bar just stays exactly where field_room.tscn/
	# reward_screen.tscn's own baked child order already places it - one
	# VBox row, no grouping wrapper needed for a row of one.

	# No meta_row any more (2026-09-05, room-label pass - REMOVES the old
	# HBoxContainer this section used to build to sit room_label and room_
	# type_label side by side) - room_label is hidden now (see its own doc
	# above), so room_type_label just stays exactly where the VBox already
	# places it, one child below player_hp_bar, with the VBox's own baked
	# separation (12px) as the gap - no wrapper needed for a row of one.

# Moved here from field_room.gd (2026-08-26) - this is purely "how does a
# RoomType.Kind read as a label," which belongs with the label now
# showing it, not with field-room-specific logic.
#
# Thin wrapper around RoomType.display_name() (2026-08-31, label-
# unification pass - REPLACES this function's own former match statement
# and its per-kind " Room"/" Heap" suffix). RoomTypeLabel's text is now
# the FULL label on its own ("Standing Water", not "Elite Room") - see
# RoomType.DISPLAY_NAMES's own doc for why a suffix no longer applies
# uniformly (HEAP's old "Wreckage Heap" already broke the "+ Room"
# pattern before this pass; the new names are place names, not type
# descriptions, so none of them want a generic suffix appended).
func _room_type_display_name(room_type: RoomType.Kind) -> String:
	return RoomType.display_name(room_type)
