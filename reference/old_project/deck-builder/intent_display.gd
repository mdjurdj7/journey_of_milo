extends Control
class_name IntentDisplay
# Replaces the old "Intends: Attack 6" text label with an icon: a small
# original Polygon2D shape (same hand-drawn silhouette language as every
# enemy/player visual - see enemy_visual.gd) tells the player the intent
# TYPE, sitting next to the actual number. The number is the fairness
# contract of the whole combat system (see DESIGN.md's Combat
# Telegraphing note) - it is always shown, always accurate, and never
# smaller/dimmer than the icon.
#
# Icon+number only - no flavor line here anymore. It used to live in
# this scene as an optional third row, but that reserved vertical space
# even when empty, which pushed the icon+number away from a fixed
# offset above the creature's head for any enemy without flavor text
# (see DESIGN.md's optional-UI-elements convention). Flavor is now
# Enemy's own FlavorLabel, positioned directly above this node instead
# (2026-08-27: moved again, from beneath the HP bar to above the head,
# sharing NameLabel's own band - see enemy.gd's _apply_creature_layout())
# - see enemy.gd's show_intent()/_update_flavor_label().
#
# Same "component with one update-ish entry point, caller doesn't touch
# how it looks" split as ResourceDisplay/VitalsBar (see DESIGN.md's
# First Playable/Resource display note) - Enemy just calls show_intent()
# or clear() and never touches a Label directly.
#
# A Panel+StyleBoxFlat frame behind icon+number was tried here (2026-08-26,
# intent-frame pass) and reverted the same day - it read as a sticker
# pasted in front of the scene rather than something belonging to the
# creature. Legibility goes back to OverlayStyle's icon drop-shadow plus a
# text outline on the number (see _set_icon()/_ready() below) - the same
# "borrow contrast from the backdrop" approach this component always used.

@onready var icon_root: Node2D = $IconRoot
@onready var value_label: Label = $ValueLabel

@export var icon_scale: float = 1.0
@export var icon_value_gap: float = 0.0
@export var value_font_size: int = 18
# DROPPED from 38 (2026-08-26, intent-frame pass) - 38 was tuned to read
# as visually dominant against HP's own number back when this component
# had no frame of its own and had to win a size contest to stay legible.
# Every OTHER numeral in the HUD (vitals_bar.gd's HP value, block_badge.
# gd's block value) reads at 18 - a number more than twice that size next
# to them is what made this component read as oversized. Kept at 18 after
# the frame itself was reverted (2026-08-26) - the size fix and the frame
# were two separate problems; only the frame turned out to be wrong.

@export var value_bold_strength: float = 1.0
@export var value_outline_width: int = -1
# -1 means "use OverlayStyle's own shared outline_width" (see _ready()'s
# OverlayStyle.apply_to_label() call below, which only passes this
# through when it's been set) - the intent number is the one overlay
# element allowed to go past the shared width (see enemy.tscn's own
# instance override), since it's meant to read as the dominant number
# in the enemy cluster, not just legible like everything else.
# Fake-bold via FontVariation.variation_embolden (see vitals_bar.gd's/
# block_badge.gd's own _apply_bold(), the same technique) - at the SAME
# reference strength those two already use for "bold," while vitals_bar.
# gd's own default was pulled back below this one (see its note) so
# intent reads as the stronger of the two numbers, not just an
# independently bold one sitting next to an equally bold HP number.

@export_range(0.0, 1.0, 0.01) var pending_icon_opacity: float = 0.3
@export_range(0.0, 1.0, 0.01) var pending_value_opacity: float = 0.5
# WIND_UP's recessive treatment (2026-08-26, pending-opacity pass;
# retuned same day - a single 0.55 shared by both read as "a slightly
# lighter active intent," not "clearly not-yet-live" on its own, without
# an active intent alongside it to compare against). TWO separate knobs,
# not one - a uniform alpha multiplier doesn't fade the icon and the
# number equally in PERCEIVED terms: the icon is saturated red against a
# pale sky backdrop, which stays visually loud even at reduced alpha,
# while the number's pale/white fill (see value_color) drops off much
# faster at the same alpha. icon_opacity is pushed lower than value_
# opacity specifically to compensate for that gap, so the pair reads as
# EVENLY faded - one recessive unit - rather than a strong icon sitting
# next to a weak number. Applied to icon_root/value_label respectively
# (see _apply_pending_state() below), never to this whole Control's own
# modulate, which enemy.gd's refresh_intent()/show_intent_interrupt()
# already own for the turn-transition crossfade (tweening THAT modulate
# between 0 and 1 - a second, independent write here would fight it).
# They multiply together instead: mid-crossfade, a WIND_UP still lands
# at these dimmed rest values once the fade-in finishes, not full
# strength. Both must stay legible enough to read at a glance - the
# whole point of a two-turns-out preview is planning against it - so
# don't push either lower without re-checking that on both a pale sky
# backdrop and a darker enemy sprite (the two real backdrops this can
# render over).

@export var center_offset_x: float = 0.0
# A manual nudge on top of center_within()'s automatic centering below -
# the icon/number group is centered by TOTAL WIDTH (icon diameter + gap +
# VALUE_LABEL_WIDTH), which assumes the icon shape and the number glyphs
# each visually "fill" their own measured width evenly. They don't
# exactly (an off-center Polygon2D shape, or a 1-digit number sitting in
# a box sized for up to 3 digits, both shift where the group actually
# LOOKS centered vs. where the math says it is) - this exists to correct
# for that by eye by feel, without changing icon_scale/icon_value_gap and
# throwing off the actual spacing between them. Positive shifts the whole
# group right, negative left.

# Every shape drawn at roughly this radius (see intent_icon_attack.tscn/
# intent_icon_defend.tscn) - only used to place value_label next to
# whatever icon is currently showing, not to draw anything itself.
const ICON_RADIUS := 20.0

# Matches ValueLabel's baked width in intent_display.tscn (340 - 240) -
# generous for 1-3 digit numbers. A known constant here rather than read
# from value_label.size.x, same reason enemy.gd hardcodes INTENT_DISPLAY_
# HEIGHT instead of reading this scene's height at runtime.
const VALUE_LABEL_WIDTH := 100.0

# The one place "intent type -> shape" is decided. Adding a new
# IntentType later (buff/debuff/special - see enemy_intent.gd) means
# authoring one more icon scene in the same shape+color language and
# adding one line here - nothing below this dictionary needs to change.
const ICON_SCENES: Dictionary = {
	EnemyIntent.IntentType.ATTACK: preload("res://intent_icon_attack.tscn"),
	EnemyIntent.IntentType.DEFEND: preload("res://intent_icon_defend.tscn"),
	EnemyIntent.IntentType.IDLE: preload("res://intent_icon_idle.tscn"),
	# A hollow ring (intent_icon_idle.gd) rather than nothing at all (see
	# show_intent() below, and IDLE's own doc in enemy_intent.gd) - an
	# enemy that isn't acting should read as "evaluated, nothing there,"
	# not as a missing icon. Muted/low-contrast by its own resting color
	# (see that script's ring_color doc), not via _apply_pending_state()
	# below - that mechanism dims a REAL intent into a recessive preview,
	# which isn't what's happening here.
	EnemyIntent.IntentType.WIND_UP: preload("res://intent_icon_attack.tscn"),
	# WIND_UP reuses ATTACK's own scene directly (2026-08-26, pending-
	# opacity pass) - previously a HollowIcon (hollow_icon.gd, now
	# deleted) that rebuilt this same shape as an unfilled outline at
	# runtime. That grammar collided with pip.gd's own hollow-vs-filled
	# now meaning spent-vs-available on the energy pips (see this
	# feature's own brief: "reusing it here would make two unrelated
	# things share a visual grammar") - WIND_UP needed a DIFFERENT
	# recessive treatment. Still the exact same shape as ATTACK, still
	# guaranteed to never visually drift from it (same preload, not a
	# second copy), just dimmed via _apply_pending_state() below instead
	# of unfilled.
	EnemyIntent.IntentType.CHARGE_ATTACK: preload("res://intent_icon_attack.tscn"),
	# CHARGE_ATTACK reuses ATTACK's own scene directly (see enemy_intent.gd's
	# own doc) - unlike WIND_UP's reuse of this same scene, it's shown at
	# full opacity (see show_intent() below, which only dims for WIND_UP),
	# since a charge-window attack is a real hit landing this turn, not a
	# preview of one still to come.
	EnemyIntent.IntentType.MARK: preload("res://intent_icon_mark.tscn"),
	# A dedicated shape (2026-08-29, "The Holdfast" icon pass) - previously
	# reused ATTACK's own chevron as a placeholder, which read as "another
	# attack" even though MARK deals no damage of its own (see enemy_
	# intent.gd's own MARK doc). A faceted open bracket/shackle instead -
	# same low-poly two-layer (Shadow+fill) construction ATTACK/DEFEND
	# already use, just a violet/plum fill rather than either's red or
	# blue, so it reads as its own distinct category (a debuff/restraint,
	# not damage or block) at a glance. Full opacity, same "real hostile
	# action" reasoning CHARGE_ATTACK's own reuse above gives - MARK is a
	# turn that actually resolves, not a preview. No number ever shows for
	# it though (see show_intent()'s own no_number gate below) - there's
	# no damage value for this intent to preview.
	EnemyIntent.IntentType.GROWTH: preload("res://intent_icon_growth.tscn"),
	# The Mushroom's own countdown icon (see enemy_intent.gd's own GROWTH
	# doc) - a placeholder sprout shape, muted/desaturated on purpose
	# (see GROWTH_VALUE_COLOR below) rather than the full-color treatment
	# ATTACK/DEFEND use. A deliberate two-register distinction (DESIGN.
	# md's system-voice/world-voice principle), not an oversight to fix
	# later: growth isn't a declared attack and shouldn't read with an
	# attack's visual weight even though it shares the same icon+number
	# mechanism.
}

# NOT keyed into ICON_SCENES above (2026-09-02, status-telegraph pass) -
# unlike every entry in that dictionary, whether this shows is decided by
# EnemyIntent.status_data, completely orthogonal to `type` (see enemy_
# intent.gd's own doc: a status can ride on ANY intent type, including
# one that also deals damage). See show_intent()'s own doc below for the
# two ways this actually gets used: as the WHOLE telegraph (an IDLE/MARK-
# shaped intent with nothing else to show, the Saltdarner's poison spray
# today) or as a small secondary badge alongside a real damage telegraph
# (no enemy does this yet, but the display must not hide the damage
# number if one ever does). Placeholder art, same "simple distinct
# glyph, final art later" register every icon here started at - a
# muted, desaturated droplet, deliberately less saturated than ATTACK's
# red/DEFEND's blue/MARK's violet (system-voice per this pass's own
# brief: "no color flourish").
const STATUS_ICON_SCENE: PackedScene = preload("res://intent_icon_status.tscn")

# GROWTH's own number color (2026-08-26, Mushroom pass) - every other
# intent type's number is Label's plain default white (see _ready()
# below, which never overrides font_color for them). GROWTH is the one
# exception: a muted, desaturated tone matching its own icon, so the
# countdown reads as quiet system information rather than a declared
# threat. Applied/reset per call in show_intent() below, not baked into
# _ready(), since the same value_label has to switch back to plain white
# for every other type an enemy might show later in the same fight.
const GROWTH_VALUE_COLOR := Color(0.72, 0.76, 0.7, 1)

var _current_icon: Node2D = null

# The secondary "also applies a status" badge (2026-09-02, status-
# telegraph pass) - unlike _current_icon above, this is never swapped
# per-call: it's always the same STATUS_ICON_SCENE shape, just shown or
# hidden (see show_intent() below). Built once here rather than
# instantiate/free per call the way _set_icon() churns _current_icon -
# there's only ever one possible badge shape, so there's nothing to
# swap. Parented under icon_root (a sibling of _current_icon, not a
# child of it) so it inherits icon_root's own icon_scale automatically,
# then nudged toward the primary icon's lower-right corner and scaled
# down further, so it reads as a small satellite mark riding alongside a
# real damage icon, never as a second full-size icon competing with it.
var _status_badge: Node2D

const STATUS_BADGE_SCALE := 0.55
const STATUS_BADGE_OFFSET := Vector2(ICON_RADIUS * 0.7, ICON_RADIUS * 0.7)

func _ready() -> void:
	value_label.add_theme_font_size_override("font_size", value_font_size)
	_apply_bold(value_label, value_bold_strength)
	OverlayStyle.apply_to_label(value_label, false, value_outline_width)
	icon_root.scale = Vector2(icon_scale, icon_scale)
	_status_badge = STATUS_ICON_SCENE.instantiate()
	_status_badge.scale = Vector2(STATUS_BADGE_SCALE, STATUS_BADGE_SCALE)
	_status_badge.position = STATUS_BADGE_OFFSET
	_status_badge.visible = false
	icon_root.add_child(_status_badge)

# Sets which width the icon+number group centers within, in this
# control's own local space (caller is expected to have already placed
# this control at local x=0 relative to whatever it's being centered
# within - see enemy.gd's _apply_creature_layout()). Takes the width as
# a parameter rather than reading size.x because this control's own
# anchors don't reliably track the creature's current width (see
# enemy.tscn's IntentDisplay instance override), and because a Control's
# size isn't guaranteed settled yet if this ran from _ready() - the
# caller always knows the real number by the time it's done laying out
# the creature. Only STORES the width - the actual positioning math
# happens in _recenter() below, since that depends on whatever content
# is currently showing (an icon+number, or an icon alone), which this
# function is called once per creature and has no way to know yet (it
# runs before the first show_intent() ever does).
var _center_width: float = 0.0

func center_within(width: float) -> void:
	_center_width = width
	_recenter(false)

# The actual centering math, re-run every time show_intent()/clear()/
# show_pain() changes what's showing - NOT just once at creature setup.
# has_number matters because the group's total width is different for
# an icon+number (ATTACK/DEFEND) vs. an icon alone (WIND_UP): centering
# on the icon+number width while only an icon is actually showing left
# the icon sitting off to one side, reserving empty space for a number
# that was never going to appear (see DESIGN.md's Bestiary: the
# Beachwrack, Wind-up icon note) - the cluster has to center on what it
# ACTUALLY contains, not on the widest thing it could ever contain.
func _recenter(has_number: bool) -> void:
	var icon_diameter := ICON_RADIUS * 2.0 * icon_scale
	var total_width := icon_diameter
	if has_number:
		total_width += icon_value_gap + VALUE_LABEL_WIDTH
	var group_left := (_center_width - total_width) / 2.0 + center_offset_x
	icon_root.position.x = group_left + ICON_RADIUS * icon_scale
	value_label.position.x = icon_root.position.x + ICON_RADIUS * icon_scale + icon_value_gap

# The public entry point - Enemy.show_intent() calls this once it knows
# the type/value for whichever intent is now current. IDLE (see enemy_
# intent.gd) shows its own hollow-ring icon (ICON_SCENES above) but no
# number - showing "0" would read as a display bug, not a deliberate
# "nothing happening" beat.
#
# WIND_UP (2026-08-26, pending-opacity pass) now shows the SAME icon+
# number pair as ATTACK/DEFEND, just recessive (_apply_pending_state()
# below) - reversing an earlier "hide the number" decision (see git
# history/DESIGN.md) made back when the icon alone had to carry
# "something big is coming." That's no longer the only telegraphing job
# this display has: WIND_UP is a real two-turns-out preview now, and the
# player needs the actual number to plan against it, not just the fact
# that a hit is coming (see this feature's own brief). Showing the same
# icon+number layout as a real intent, only dimmer, is also what fixes
# WIND_UP's old off-center position for free.
#
# _recenter(true) unconditionally, even for IDLE (2026-08-26, idle-icon
# pass) - IDLE used to pass has_number=false here, which centers on a
# narrower total_width than every other intent (the exact off-center bug
# WIND_UP's own fix above just eliminated for itself). IDLE's blank
# value_label.text still means nothing visibly occupies the number slot
# - has_number here only reserves LAYOUT width, it doesn't require
# actual text - so every intent type, IDLE included, now lands its icon
# at the identical position.
#
# status_magnitude (2026-09-02, status-telegraph pass) - 0 (every call
# site before the Saltdarner) means "this intent applies no status,"
# same "zero means unaffected" idiom every other opt-in param on this
# call chain already uses - see enemy_intent.gd's EnemyIntent.status_data
# for where a caller derives this (its default_magnitude when set, 0
# otherwise). Two different things happen depending on whether `type`
# ALSO has a number of its own:
#   - type has none (IDLE/MARK, e.g. the Saltdarner's poison spray) -
#     there's nothing to combine WITH, so the status telegraph simply
#     REPLACES what this type would otherwise show: STATUS_ICON_SCENE
#     instead of IDLE's dots/MARK's shackle, status_magnitude instead of
#     a blank number. This is the one case any enemy exercises today.
#   - type has a real number (ATTACK/DEFEND/WIND_UP/CHARGE_ATTACK) - the
#     normal icon+damage telegraph is untouched, and _status_badge (see
#     its own doc above _ready()) shows as a small satellite mark next
#     to it instead - "the display must not hide the damage" per this
#     pass's own brief. No enemy combines a real intent with a status
#     yet, so this branch has no live content to verify against, only
#     the code path itself.
func show_intent(type: EnemyIntent.IntentType, value: int, value_suffix: String = "", status_magnitude: int = 0) -> void:
	# MARK (2026-08-29, Leviathan mark attack) joins IDLE here - same "no
	# damage value to preview, showing one would read as a display bug"
	# reasoning IDLE's own doc gives, see enemy_intent.gd's own MARK doc.
	var no_number := type == EnemyIntent.IntentType.IDLE or type == EnemyIntent.IntentType.MARK
	var status_is_primary := status_magnitude > 0 and no_number
	if status_is_primary:
		_set_icon_scene(STATUS_ICON_SCENE)
	else:
		_set_icon(type)
	_status_badge.visible = status_magnitude > 0 and not status_is_primary
	if status_is_primary:
		value_label.text = str(status_magnitude)
	else:
		value_label.text = "" if no_number else str(value) + value_suffix
	# value_suffix (2026-08-29, "x2" finishing-hit indicator pass) -
	# appended straight onto the number, not a separate label/slot -
	# "" (every intent besides Leviathan's Charged-buff finishing turn)
	# leaves this byte-identical to before the param existed, same
	# "empty means unaffected" shape every other opt-in param on this
	# call chain already uses. Still renders inside VALUE_LABEL_WIDTH's
	# existing fixed reservation - no layout change needed for a few
	# extra characters (see that const's own doc); a genuinely wider
	# suffix some future status wants would need revisiting this, not a
	# case this pass needs to solve for.
	_recenter(true)
	_apply_pending_state(type == EnemyIntent.IntentType.WIND_UP)
	_apply_value_color(type)

# Enemy.show_intent() calls this instead when the enemy has no intents
# at all (defensive - not something any real enemy hits today).
func clear() -> void:
	_set_icon(-1)
	_status_badge.visible = false
	value_label.text = "—"
	_recenter(true) # "—" still occupies the number slot - keep the icon+number layout, same as ATTACK/DEFEND.
	_apply_pending_state(false)
	_apply_value_color(-1)

# Enemy.show_intent_interrupt() calls this whenever an intent gets
# cancelled - the Wardling's own pain turn (see enemy_data.gd's pain_
# turn_hp_threshold and DESIGN.md's Bestiary: the Wardling) or a chain
# payoff stun (see card_effect.gd's STUN) - no icon (nothing is about to
# happen) and no number (no damage lands), unlike clear()'s "—"
# placeholder above: this isn't a defensive fallback for missing data,
# it's a deliberate beat with nothing to show here at all. FlavorLabel
# carries the whole moment on its own - see Enemy.show_intent_interrupt().
func show_interrupted() -> void:
	_set_icon(-1)
	_status_badge.visible = false
	value_label.text = ""
	_recenter(false) # Nothing shows at all here - doesn't matter visually, but stays consistent with "center on what's actually there."
	_apply_pending_state(false)
	_apply_value_color(-1)

# WIND_UP's whole recessive look - see pending_icon_opacity/pending_
# value_opacity's own doc for why these are two separate values (set in
# the same call, so they always change together even though they land
# at different numbers) rather than this Control's own modulate. Reset
# to full strength (1.0/1.0) by every other caller above - a WIND_UP's
# dim state must never bleed into whatever this display shows next.
func _apply_pending_state(is_pending: bool) -> void:
	icon_root.modulate.a = pending_icon_opacity if is_pending else 1.0
	value_label.modulate.a = pending_value_opacity if is_pending else 1.0

# GROWTH's own muted number treatment - see GROWTH_VALUE_COLOR's own doc.
# remove_theme_color_override(), not a hardcoded white override, for
# every other type - that's what lets Label's own plain default keep
# being the source of truth for "ordinary" intents, exactly as it always
# was, rather than this file quietly taking over ownership of a color it
# never used to set.
func _apply_value_color(type) -> void:
	if type == EnemyIntent.IntentType.GROWTH:
		value_label.add_theme_color_override("font_color", GROWTH_VALUE_COLOR)
	else:
		value_label.remove_theme_color_override("font_color")

func _set_icon(type) -> void:
	_set_icon_scene(ICON_SCENES.get(type))

# Split out from _set_icon() above (2026-09-02, status-telegraph pass) -
# show_intent()'s status_is_primary branch needs to swap in STATUS_ICON_
# SCENE directly, bypassing the type-keyed ICON_SCENES lookup entirely
# (status_data is orthogonal to type - see STATUS_ICON_SCENE's own doc),
# without duplicating the actual instantiate/free mechanics below. Every
# existing call to _set_icon(type) behaves byte-identically to before
# this split - it's now a one-line wrapper around this.
func _set_icon_scene(scene: PackedScene) -> void:
	if _current_icon != null:
		_current_icon.queue_free()
		_current_icon = null
	if scene == null:
		return
	# No drop-shadow (2026-08-26, shadow-removal pass) - the icon's .tscn
	# is now the whole visual, nothing generated at runtime on top of it.
	# OverlayStyle.make_icon_shadow() is untouched (still used elsewhere -
	# see that file's own consumer list); this just stops calling it here.
	_current_icon = scene.instantiate() as Node2D
	icon_root.add_child(_current_icon)

# Wraps whatever font the label already resolves in a FontVariation that
# fakes bold via glyph embolden - no separate bold font asset to manage.
# Same technique as vitals_bar.gd's/block_badge.gd's own _apply_bold().
func _apply_bold(label: Label, strength: float) -> void:
	var variation := FontVariation.new()
	variation.base_font = label.get_theme_font("font")
	variation.variation_embolden = strength
	label.add_theme_font_override("font", variation)
