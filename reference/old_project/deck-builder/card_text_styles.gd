extends RefCounted
class_name CardTextStyles
# A small reusable helper, same shape as WeightedRandom (see
# weighted_random.gd) - a static utility, no state, no instantiation.
#
# The problem this solves: card descriptions can already contain raw
# BBCode (card.gd's DescriptionLabel is a RichTextLabel with
# bbcode_enabled = true - [b]bold[/b], [color=...]...[/color], etc. all
# just work, typed directly into a .tres file's description string). But
# raw color codes scattered across dozens of card files means redefining
# "what a modified value looks like" later is a find-and-replace across
# every card that used it - exactly the kind of scattered-styling problem
# this project avoids everywhere else (AudioManager's one sound-name
# dictionary, RARITY_BORDER_COLORS in card.gd, etc.).
#
# STYLES below is that one place instead: a card author writes a NAMED
# semantic tag - [modified]18[/modified], [keyword]Consumed[/keyword] -
# and expand() (called once, from card.gd's _update_display(), before the
# text ever reaches the RichTextLabel) rewrites it into the real BBCode
# STYLES currently says that name means. Redefining "modified" everywhere
# is a one-line edit here; no card file ever changes.
#
# Deliberately NOT applied to any existing card by this change - every
# card's description today is plain text (or, going forward, raw BBCode
# an author typed by hand), and expand() only ever touches text that
# actually contains one of the names below. A description with no
# semantic tags in it passes through byte-for-byte unchanged.
#
# --- Adding a new tag later ---
# Add one entry to STYLES (a color, and optionally bold/italic true) -
# nothing else in this file, card.gd, or card.tscn needs to change. The
# new tag is immediately usable in any card's description string as
# [your_new_name]...[/your_new_name].
const STYLES := {
	# A number or word that's been changed from its "base" value - an
	# escalated intent, a buffed cost, anything the player should notice
	# ISN'T the plain default number. Warm/amber so it reads as "this
	# moved," distinct from keyword's cool blue below.
	"modified": {"color": Color(0.645, 0.419, 0.082, 1.0), "bold": true},
	# A mechanic/rules term - "Consumed," "Exhaust," a future status name.
	# Cool blue, bold - meant to catch the eye as "this word means
	# something specific," the same instinct RARE's border color (card.gd's
	# RARITY_BORDER_COLORS) already uses blue for "this is a defined
	# category," not just a decoration.
	"keyword": {"color": Color(0.087, 0.376, 0.518, 1.0), "bold": true},
	# A proper noun - a creature or place named in flavor text (e.g. "the
	# Wardling"). Soft gold-tan and italic, not bold - a name should read
	# as part of the sentence's voice, not shout like a mechanic term.
	"entity": {"color": Color(0.85, 0.75, 0.55, 1), "italic": true},
	# A number that's been reduced from its base value - the escape-
	# falloff readout's own opposite (see battle.gd's _update_damage_
	# preview()/card.gd's show_modified_damage()), first real use
	# 2026-08-24. Deliberately NOT "modified" - that tag already means
	# BOOSTED (see its own note above); reusing it for a reduction would
	# teach the wrong lesson to a player who's learned amber = "this got
	# bigger." Muted rust instead, matching Enemy's own (now largely
	# retired for this path, but still real) DamagePreviewLabel color -
	# one vocabulary for "this number went down" regardless of which
	# surface shows it.
	"reduced": {"color": Color(0.85, 0.5, 0.4, 0.95), "bold": true},
}

# The only entry point card.gd calls for the tags above. Walks every
# name in STYLES and swaps [name]/[/name] for the real BBCode that name
# currently means - any OTHER BBCode already in `text` ([b], [color=...],
# a tag not listed in STYLES, etc.) is left completely alone, so raw
# BBCode and semantic tags can mix freely in the same description.
static func expand(text: String) -> String:
	var result := text
	for tag_name in STYLES:
		var style: Dictionary = STYLES[tag_name]
		result = result.replace("[%s]" % tag_name, _open_tag(style))
		result = result.replace("[/%s]" % tag_name, _close_tag(style))
	return result

# A SECOND, separate entry point (2026-08-27, condition-indicator pass) -
# NOT folded into STYLES/expand() above, because those four tags each
# mean one fixed, context-free color regardless of anything happening in
# the game right now. [cond_active]/[cond_inactive] are the opposite: the
# same card renders them differently depending on live battle state (see
# battle.gd's _card_condition_active()), so their BBCode can't be a
# static table lookup - it has to be computed fresh, per card, per
# refresh, from whatever card.gd currently believes that card's condition
# state is. Called separately from expand() in card.gd's own _refresh_
# description_text() - order doesn't matter between the two, since they
# touch disjoint tag names and neither's replacement text can contain the
# other's tag literally.
#
# A card's description authors these around a WHOLE CLAUSE, not just the
# number inside it (CORRECTED 2026-08-27 - see this fix's own report:
# wrapping only the numeral read as "typographic noise," two live-looking
# numbers on the same card, rather than a state change) - e.g. Compound:
# "[cond_inactive]Deal 6 damage.[/cond_inactive]\n[cond_active]If Toll is
# 15 or more, deal 16 damage instead.[/cond_active]" - the two CLAUSES
# that already exist in the sentence, marked so this function knows which
# one to emphasize once told whether the condition is currently true.
#
# INACTIVE: both tags strip to nothing, no BBCode inserted at all - the
# plain sentence renders in whatever color DescriptionLabel's own
# default_color already is (HudPalette.SYSTEM_TEXT), identical to every
# other word in the description. This is what makes "normal styling
# throughout, no dimming" (this pass's own brief, point 3) free: there's
# no color/weight override to remove, just nothing added in the first
# place.
#
# ACTIVE: [cond_active] gets bold + active_color across its ENTIRE
# wrapped clause (the one that's CURRENTLY live - Compound's threshold
# line once Toll clears 15). [cond_inactive] gets inactive_color alone,
# no bold, across ITS entire clause - the one that no longer applies,
# present so the player can still see the card's full conditional
# structure (this pass's own DESIGN note: never replace the text, only
# re-weight it). Size never changes either way - "only weight and
# color," per the brief, is enforced by construction: neither style dict
# below ever sets a font_size.
static func expand_conditional(text: String, condition_active: bool, active_color: Color, inactive_color: Color) -> String:
	if not condition_active:
		return text.replace("[cond_active]", "").replace("[/cond_active]", "").replace("[cond_inactive]", "").replace("[/cond_inactive]", "")
	var active_style := {"color": active_color, "bold": true}
	var inactive_style := {"color": inactive_color}
	var result := text
	result = result.replace("[cond_active]", _open_tag(active_style)).replace("[/cond_active]", _close_tag(active_style))
	result = result.replace("[cond_inactive]", _open_tag(inactive_style)).replace("[/cond_inactive]", _close_tag(inactive_style))
	return result

# Opens color first, then bold/italic inside it - _close_tag() below
# closes in the exact reverse order, so a style using more than one of
# these (today, every entry in STYLES does) still nests correctly instead
# of producing mismatched BBCode.
static func _open_tag(style: Dictionary) -> String:
	var open := ""
	if style.has("color"):
		open += "[color=#%s]" % (style["color"] as Color).to_html(false)
	if style.get("bold", false):
		open += "[b]"
	if style.get("italic", false):
		open += "[i]"
	return open

static func _close_tag(style: Dictionary) -> String:
	var close := ""
	if style.get("italic", false):
		close += "[/i]"
	if style.get("bold", false):
		close += "[/b]"
	if style.has("color"):
		close += "[/color]"
	return close
