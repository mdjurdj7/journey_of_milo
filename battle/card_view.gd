extends Panel
class_name CardView

# "Ink on bone": a pale card with dark type and edges, never a dark slab.
# The name is world voice (Spectral), the rules text is system voice
# (Alegreya Sans); dark reads as ink and lines - the 1px frame and the
# faint rule inset inside it (a double printed rule), the glyph - not as
# fill. Type colour is only the tonal field behind the glyph; rarity is
# only the rule round the art field. Cards never invert with the
# theme's on-pale/on-dark switch: every colour here is this script's
# own export, and nothing reads the theme's CardFace tokens any more -
# those belong to the chips and buttons.
#
# Layout at 1x is 200 x 280 (5:7); HandContainer/DeckView scale the
# whole card, so every size below is a 1x pixel. Top to bottom: name
# (top-left, one line) beside the cost numeral (top-right, with a ledger
# rule and a "-N HP" line under it when the card costs HP); the tonal
# field with the type glyph or the card's art, a fixed rect on every
# card; the rules text, centred in the space left and stepping its size
# down to fit; the small-caps type label just inside the inset rule. See
# _apply_layout().

signal clicked(card_data: CardData)
# Fired whenever this card visually lifts out of the hand for any reason -
# hover OR armed (lift_and_hold()) - and again once it settles back down.
# HandContainer listens for these to straighten the card's own fan
# rotation to 0 and raise it above its neighbors while lifted, then
# restore both on lowered - this script only knows about its own
# position.y lift (see _tween_to()); it has no idea it's sitting in a fan
# at all, let alone what angle/z_index to return to.
signal lifted
signal lowered
# Armed (lift_and_hold()) / disarmed (release()) - distinct from hover:
# HandContainer moves an armed card's slot to armed_position and closes
# the hand under it, and reopens/returns it on disarmed.
signal armed
signal disarmed

# Card type from the rules' point of view (strike / guard / toll /
# utility), derived in _derive_keyline_type() - see DESIGN.md's note on
# why this isn't CardData.CardType yet. Appended rather than inserted, as
# a habit: nothing serialises this today (it's derived every time a card
# is shown, never authored), but the enum sits next to CardEffect's own,
# where an inserted value silently rewrites existing .tres data.
enum KeylineType { STRIKE, GUARD, TOLL, UTILITY, STANCE, POWER }

# Rules-text words set in bold. Whole-word, case-sensitive.
const KEYWORDS: Array[String] = ["Toll", "Grace", "Critical", "Drain"]

# Numbers a card's text can defer to its own effects, so the face shows
# what the card will ACTUALLY do rather than what it did when it was
# authored. "Deal {damage} damage." on Slash reads "Deal 6 damage."
# normally and "Deal 12 damage." under two stacks of Self-Eater.
#
# Only for text whose number IS an effect value. Reckoning's "damage
# equal to the amount consumed" has no fixed number to substitute and
# stays prose - a token there would have to invent one.
#
# {hp_cost} is the exception that reads across effects rather than from
# one: it's the same sum the "-N HP" line shows (see _derive_hp_cost()),
# stance included - all but a cost replacement's HP (Collateral), which
# the line adds and the text doesn't: the text says what the card does,
# and Collateral's price isn't the card's own ("Lose 2 HP" on Blood Arc
# stays 2 while its line reads -7).
const TOKEN_DAMAGE := "{damage}"
const TOKEN_BLOCK := "{block}"
# The number a conditional clause is FOR (CardBonus.bonus_value(): the
# replacement on a REPLACE, the extra on an ADD) - resolved on the same
# path as {damage}/{block}, stance included, so both halves of a face
# move together. Two spellings for the same thing, so a clause reads as
# authored: "deal {alt_damage}" on a replace, "{bonus_block} more" on an
# add.
const TOKEN_ALT_DAMAGE := "{alt_damage}"
const TOKEN_BONUS_DAMAGE := "{bonus_damage}"
const TOKEN_ALT_BLOCK := "{alt_block}"
const TOKEN_BONUS_BLOCK := "{bonus_block}"
# The conditional clause, and the base text a REPLACE supersedes - see
# _style_bonus_clauses(). Stripped on render; in a battle hand the two
# are inked by CardBonus.state(): the half that applies in ink, the
# other in bonus_dormant_ink.
const MARK_IF_OPEN := "{if}"
const MARK_IF_CLOSE := "{/if}"
const MARK_ELSE_OPEN := "{else}"
const MARK_ELSE_CLOSE := "{/else}"
const TOKEN_DRAW := "{draw}"
const TOKEN_HP_COST := "{hp_cost}"
# The effect types {damage}/{alt_damage} and {block}/{alt_block} read.
const DAMAGE_EFFECT_TYPES: Array = [CardEffect.EffectType.DAMAGE, CardEffect.EffectType.FIRST_CARD_DAMAGE,
	CardEffect.EffectType.DAMAGE_ALL, CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE]
const BLOCK_EFFECT_TYPES: Array = [CardEffect.EffectType.BLOCK, CardEffect.EffectType.UNDAMAGED_BLOCK,
	CardEffect.EffectType.TOLL_BLOCK]
# The player's Toll right now - 0 outside a battle, which is also what a
# card in the deck view shows. Reckoning spends all of it, so its printed
# damage IS this number.
const TOKEN_TOLL := "{toll}"
# What a TOLL_HEAL would heal for at that Toll: half of whatever it can
# actually spend, capped. Debt Forgiven's own preview.
const TOKEN_TOLL_HEAL := "{toll_heal}"
# The blank border Godot's glyph rasteriser puts round every glyph
# bitmap - an engine fact, not a tunable. See _cap_top().
const GLYPH_RECT_MARGIN_PX := 1.0

@export var card_size: Vector2 = Vector2(200.0, 280.0)

@export_group("Colours")
@export var field_color: Color = Color(0.94, 0.91, 0.86)
@export var ink_color: Color = Color(0.165, 0.165, 0.18)
@export_range(0.0, 1.0) var frame_alpha: float = 0.88
@export var corner_radius: int = 6
# The second printed rule: neutral ink, inset from the frame, its corners
# concentric with the card's (corner_radius - inset). Drawn by Keyline,
# under the type, with the card-stock edges below.
@export var inner_keyline_inset_px: int = 4
@export var inner_keyline_width_px: int = 1
@export_range(0.0, 1.0) var inner_keyline_alpha: float = 0.25
# Card stock: a 1px light just inside the top edge and a 1px shade just
# inside the bottom one, both between the rounded corners.
@export var top_highlight_color: Color = Color(1.0, 1.0, 1.0, 0.3)
@export_range(0.0, 1.0) var bottom_shade_alpha: float = 0.08
@export var keyline_strike: Color = Color(0.62, 0.56, 0.49)
@export var keyline_guard: Color = Color(0.49, 0.56, 0.59)
@export var keyline_toll: Color = Color(0.54, 0.50, 0.58)
# Grey-neutral on purpose: utility is the type that isn't about damage or
# defence, so it reads as the absence of a hue rather than a fourth one.
@export var keyline_utility: Color = Color(0.58, 0.58, 0.60)
# Warmer and darker than the rest: a stance is the one card type that
# stays with you after it is played, and it should not read as cool or
# incidental.
@export var keyline_stance: Color = Color(0.52, 0.45, 0.44)
# A dim amber: a power also stays after it is played, like a stance, but
# sits beside it rather than being the one mode you fight in - kin to the
# stance's warmth, lighter and yellower so the two never read as one.
@export var keyline_power: Color = Color(0.60, 0.53, 0.40)
# A conditional's half that does NOT apply right now (see set_bonus_
# context()): the utility grey, legible on bone but clearly not the ink.
# Neutral cards (no battle context) never use it.
@export var bonus_dormant_ink: Color = Color(0.58, 0.58, 0.60)
@export var art_field_strike: Color = Color(0.886, 0.863, 0.796)
@export var art_field_guard: Color = Color(0.875, 0.878, 0.855)
@export var art_field_toll: Color = Color(0.878, 0.863, 0.886)
@export var art_field_utility: Color = Color(0.87, 0.87, 0.85)
@export var art_field_stance: Color = Color(0.886, 0.856, 0.846)
@export var art_field_power: Color = Color(0.890, 0.868, 0.820)
@export var art_field_radius: int = 2
# The art's tint and contrast pull (battle/card_art.gdshader). One
# material SHARED by every card, not a copy each: its art_tint and
# art_contrast are the game-wide card-art values, and editing them on
# that resource moves every face at once, live.
@export_file("*.tres") var art_material_path: String = "res://battle/card_art_material.tres"
# The paper under everything on the face (battle/card_paper.gdshader):
# one material SHARED by every card, like the art's. Its two strengths,
# paper_grain_strength and paper_tonal_variation_strength, are the whole
# game's card stock; both 0 is flat bone.
@export_file("*.tres") var paper_material_path: String = "res://battle/card_paper_material.tres"
# The two shadows, lit from above: a contact hairline (1px down, 18%) and
# a soft shadow thrown down the page (10px, 14%, 3px down). A lifted card
# (see Hover) throws the soft one further and lighter, and the contact
# line fades - it has left the table.
@export_range(0.0, 1.0) var shadow_hairline_alpha: float = 0.18
@export var shadow_soft_size_px: int = 10
@export_range(0.0, 1.0) var shadow_soft_alpha: float = 0.14
@export var shadow_soft_offset_px: float = 3.0

@export_group("Type")
@export var name_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")
@export var rules_font: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
@export var rules_font_bold: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
# The numeral is the Light cut, larger than the name: the name leads by
# weight, the cost anchors by size, and the two never match.
@export var cost_font: Font = load("res://assets/fonts/Spectral-Light.ttf")
@export var name_font_size_px: int = 19
@export var cost_font_size_px: int = 26
@export var hp_cost_font_size_px: int = 10
@export_range(0.0, 1.0) var hp_cost_letter_spacing_em: float = 0.16
@export_range(0.0, 1.0) var hp_cost_alpha: float = 0.72
# The ledger rule between the numeral and the "-N HP" line - only on a
# card that costs HP - as wide as the wider of the two, right-aligned.
@export var cost_rule_y_px: float = 33.0
@export_range(0.0, 1.0) var cost_rule_alpha: float = 0.3
# The rules text's sizes at 1x, largest first: each is tried in turn
# until the text fits the space under the art field. The last is the
# floor - text that still doesn't fit there wraps on and the card grows
# downward rather than shrinking further (_warn_overlong() says so). A
# card that lands below the first size is saying too much.
@export var rules_font_sizes: Array[int] = [15, 14, 13, 12]
@export var rules_line_height: float = 1.28
# Extra space between the description's authored lines ("Deal 8 damage."
# / "Lose 2 HP."), on top of the line spacing, so clauses read apart
# from mere wrapping.
@export var rules_paragraph_gap_px: int = 4
# The rules block is centred in its space, this much above true centre.
@export var rules_optical_lift_px: float = 2.0
# A size is taken only if it leaves at least this much of the space
# spare (split above and below the centred block) and no authored line
# wraps to a lone last word ("26."); otherwise the next size is tried.
# If no size is that clean, the first that fits at all is used.
@export var rules_min_air_px: float = 4.0
@export_range(0.0, 1.0) var rules_alpha: float = 0.92
@export var type_label_font_size_px: int = 9
@export_range(0.0, 1.0) var type_label_letter_spacing_em: float = 0.16
@export_range(0.0, 1.0) var type_label_alpha: float = 0.55
# Off: the inset rule already bounds the footer. On, it is the hairline
# over the type label that the card had before.
@export var footer_rule_enabled: bool = false
@export_range(0.0, 1.0) var footer_rule_alpha: float = 0.25

@export_group("Bonus Corner")
# The one mark of a LIVE conditional besides the ink: a filled ink
# right-triangle folded into the top-right corner, legs bonus_corner_px
# along the top and right edges, inset from the card's edge by
# corner_radius so its right angle sits inside the rounded corner and
# clear of the border at every frame weight. It grows from nothing over
# bonus_in_seconds (ease-out) on LIVE and shrinks away over bonus_out_
# seconds on anything else; nothing else on the face moves. Drawn in
# the card's own coordinates, so it scales with the card at hover, armed
# and inspect. Never shown without a battle context (see _bonus_context).
@export var bonus_corner_px: float = 14.0
@export var bonus_in_seconds: float = 0.2
@export var bonus_out_seconds: float = 0.15

@export_group("Art Rule")
# An ink rule round the art field, drawn over the image's outermost
# pixels so it sits tight to it - the field's rect and radius, not a
# pixel bigger. On every card, art or glyph: it frames the panel, not
# the picture.
@export var art_rule_width_px: int = 1
@export var art_rule_color: Color = Color(0.165, 0.165, 0.18)
# Set into the page: 1px just inside the ink rule, a shade along the top
# and a light along the bottom, between the corners. Transparent = off.
@export var art_inset_shade: Color = Color(0.165, 0.165, 0.18, 0.15)
@export var art_inset_light: Color = Color(1.0, 1.0, 1.0, 0.12)
# A second rule outside the first, in the card's keyline colour, for
# trying the panel with a double edge. art_outer_rule_inset_px is the
# gap between the two rules; the outer one's corners stay concentric
# with the field's.
@export var art_outer_rule_enabled: bool = false
@export var art_outer_rule_inset_px: int = 3
@export var art_outer_rule_width_px: int = 1
# The card's rarity (CardData.rarity), as a rule directly outside the ink
# rule - on the card's bone, never over the art - its corners concentric
# with the field's. Muted on purpose: noticeable when three reward cards
# sit side by side, quiet in a hand. Common and UNSET draw nothing, so
# most cards look as they always have; a transparent colour or a width
# of 0 turns a tier off.
@export var rarity_rule_uncommon: Color = Color(0.52, 0.58, 0.64)
@export var rarity_rule_rare: Color = Color(0.70, 0.57, 0.33)
@export var rarity_rule_ultra_rare: Color = Color(0.86, 0.78, 0.58)
@export var rarity_rule_width_px: int = 2
@export var rarity_rule_ultra_rare_width_px: int = 3

@export_group("Layout")
@export var outer_margin: float = 12.0
@export var name_cost_gap: float = 8.0
# The header: one height on every card. Its labels are placed by
# BASELINE, not stacked by line box - Spectral's box is ~1.5em with room
# below for descenders a numeral never uses, so stacked boxes waste a
# row. The name and the cost numeral share header_baseline_px; the
# ledger rule (cost_rule_y_px) and the "-N HP" line (hp_cost_baseline_px)
# sit right under the numeral, in the header's height and the gap below
# it rather than adding a row.
@export var header_height: float = 42.0
@export var header_baseline_px: float = 29.0
@export var hp_cost_baseline_px: float = 42.0
@export var header_field_gap: float = 6.0
# The art field: one rect on every card, whatever its name, HP cost or
# rules text - art is painted for this window, so it never gives way.
# Its top is header_height + header_field_gap.
@export var art_field_size: Vector2 = Vector2(176.0, 146.0)
@export var field_rules_gap: float = 8.0
@export var rules_footer_gap: float = 6.0
# The footer is placed by INK, like the header: the type label's
# baseline sits footer_bottom_ink_px above the face's bottom edge (its
# small caps have no descenders, so that is the ink's bottom; 9 leaves
# 4px clear of the inset rule), and the rules text ends rules_footer_gap
# above the caps' tops (_cap_top()) - or above the footer rule, if on,
# whose lower edge is footer_rule_ink_gap_px above them. Both rounded to
# a whole pixel.
@export var footer_rule_ink_gap_px: float = 4.0
@export var footer_bottom_ink_px: float = 9.0
@export var glyph_size_px: float = 36.0
@export var glyph_line_width_px: float = 3.5
# The glyph's faint secondary stroke (the second chevron, the shield's
# centre line, the arrow's base) at this fraction of ink.
@export_range(0.0, 1.0) var glyph_faint_alpha: float = 0.35

@export_group("Hover")
# Off for DeckView's browsing grid (set right after instantiate(), same
# pre-add_child() timing HandContainer already uses for card_size) -
# GridContainer re-asserts each child's position on its own schedule, not
# every frame, so a hover tween nudging position.y there would fight it
# and can visually shove a card up into the row above. Hand row use
# (HandContainer/CardView's own default) is unaffected.
@export var hover_enabled: bool = true
# Measured from rest (see _rest_offset_y below), in 1x card pixels -
# scaled by this card's base scale in _tween_to(), so a hand card at 0.85
# lifts 22px on screen, not 26. Hover also grows the card by hover_scale
# in place, about its bottom centre (pivot_offset), over its neighbours.
@export var hover_lift: float = 26.0
@export var hover_scale: float = 1.15
@export var hover_duration_sec: float = 0.12
# Armed: the card leaves the fan for armed_position - viewport centre,
# bottom edge at armed_bottom_y_fraction of the viewport height (0.86 =
# y 928 at 1080p, ~70px into the resting hand's top, so the card sits ON
# the hand rather than floating above it) - at armed_scale (a multiple
# of 1x, not of the hand's scale), over armed_duration_sec, ease-out.
# HandContainer does the moving (it owns the slot); this card only
# scales.
@export var armed_scale: float = 1.2
@export_range(0.0, 1.0) var armed_bottom_y_fraction: float = 0.86
@export var armed_duration_sec: float = 0.18
# Lifted (hover or armed), the frame goes to full ink at this width - 1:
# the lift is said by the shadow, not by a heavier edge.
@export var hover_frame_width_px: int = 1
@export_range(0.0, 1.0) var hover_shadow_hairline_alpha: float = 0.08
@export var hover_shadow_soft_size_px: int = 16
@export_range(0.0, 1.0) var hover_shadow_soft_alpha: float = 0.16
@export var hover_shadow_soft_offset_px: float = 7.0
# An armed (selected) card holds its lifted pose at least this long
# before release() may lower it, so a quick cancel still reads.
@export var selected_hold_sec: float = 0.5
# Unplayable (can't afford): the whole card fades to this - ink and bone
# alike, no grey overlay.
@export_range(0.0, 1.0) var unplayable_alpha: float = 0.42

@export_group("Edge Override")
# Every card gets the 1px ink frame by default. This is an escape hatch
# for a caller that wants a DIFFERENT, fixed edge instead (DeckView's own
# "one step darker than the bone" treatment - see its own use_card_edge
# export): set right after instantiate(), same pre-add_child() timing as
# hover_enabled above.
@export var edge_color_override_enabled: bool = false
@export var edge_color: Color = Color(1.0, 1.0, 1.0, 1.0)
@export var edge_width_px: float = 1.0

@onready var shadow_soft: Panel = $ShadowSoft
@onready var shadow_hairline: Panel = $ShadowHairline
@onready var paper: Control = $Paper
@onready var keyline: Control = $Keyline
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel
@onready var hp_cost_label: Label = $HpCostLabel
@onready var cost_rule: ColorRect = $CostRule
@onready var art_field: Panel = $ArtField
@onready var art_rect: TextureRect = $ArtField/Art
@onready var glyph: Control = $ArtField/Glyph
@onready var rules_text: RichTextLabel = $RulesText
@onready var footer_rule: ColorRect = $FooterRule
@onready var type_label: Label = $TypeLabel

var card_data: CardData
var _armed: bool = false
var _armed_at_msec: int = 0
var _playable: bool = true
var _keyline_type: KeylineType = KeylineType.STRIKE
# The stance in force, for the numbers on this face - see set_stance().
var _stance: Stance = null
# The player's Grace - kept for the crossing it announces; the face's
# own reading of a Grace condition goes through the bonus context below.
var _grace: int = 0
# The player's Toll, for the cards whose numbers are made of it.
var _toll: int = 0
# The battle as it stands, for this card's conditionals (see set_bonus_
# context()) - null anywhere but a battle hand, which is what keeps a
# reward, an offer or a deck view neutral: no state, no dimming, no
# corner. And the reading taken from it: CardBonus.state().
var _bonus_context: EffectContext = null
var _bonus_state: CardBonus.State = CardBonus.State.NONE
# The corner fold's growth, 0 = nothing, 1 = legs of bonus_corner_px -
# tweened by _animate_bonus_corner(), written through _set_bonus_corner_
# blend(). Drawn by _bonus_corner, a Control over the whole face made in
# _ready() (not in the scene: it has no layout of its own).
var _bonus_corner_blend: float = 0.0
var _bonus_corner_tween: Tween = null
var _bonus_corner: Control = null
var _art_style: StyleBoxFlat = null
# Draws the art rules - a Control over the whole face made in _ready(),
# like _bonus_corner, so the rules draw above the image instead of being
# clipped into it by the field.
var _art_rule: Control = null
var _hp_cost: int = 0
var _rest_offset_y: float = 0.0
# How far down from this card's own local origin "at rest" actually sits -
# pushed down by HandContainer.hand_rest_visible_height so only part of
# the card pokes up past the screen's bottom edge. hover_lift is measured
# FROM this baseline, not from 0 - see set_rest_offset().

var _card_style: StyleBoxFlat
var _hovering: bool = false
# The scale HandContainer/DeckView assign (the hand's shrink factor) -
# hover multiplies it, armed replaces it; both return to it.
var _base_scale: float = 1.0
# HandContainer sets this while any card is armed: other cards ignore
# hover entirely (no second lift).
var _hover_suppressed: bool = false
var _scale_tween: Tween = null

func _ready() -> void:
	size = card_size
	# Scale about the bottom centre - a hovered card grows up and out over
	# its neighbours, an armed card grows from its bottom edge. Only for a
	# hand card: DeckView (hover off) scales its cards toward the top-left
	# so they stay inside their grid footprint.
	if hover_enabled:
		pivot_offset = Vector2(card_size.x / 2.0, card_size.y)
	_base_scale = scale.x
	mouse_filter = Control.MOUSE_FILTER_STOP
	for child in get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glyph.draw.connect(_draw_glyph)
	keyline.draw.connect(_draw_keyline)
	if not paper_material_path.is_empty():
		paper.material = load(paper_material_path) as Material
	paper.draw.connect(_draw_paper)
	# The card's art (CardData.art) as a centred cover crop: fills the
	# field at its own aspect, the overflow cut, never stretched. Clipped
	# to the field's own drawn shape so it keeps the rounded corners; the
	# type-coloured field still draws underneath, and is all there is for
	# a card without art. Mipmapped - it sits at a fraction of its size.
	art_field.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if not art_material_path.is_empty():
		art_rect.material = load(art_material_path) as Material
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_rect.visible = false
	_art_rule = Control.new()
	_art_rule.name = "ArtRule"
	_art_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_rule.draw.connect(_draw_art_rule)
	add_child(_art_rule)
	_bonus_corner = Control.new()
	_bonus_corner.name = "BonusCorner"
	_bonus_corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus_corner.draw.connect(_draw_bonus_corner)
	add_child(_bonus_corner)
	_apply_style()
	_apply_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func set_card_data(data: CardData) -> void:
	card_data = data
	name_label.text = data.card_name
	cost_label.text = str(_displayed_cost())
	_keyline_type = _derive_keyline_type(data)
	# Art replaces the glyph rather than sitting on it.
	art_rect.texture = data.art
	art_rect.visible = data.art != null
	glyph.visible = data.art == null
	_refresh_dynamic_text()
	type_label.text = _type_label_text(_keyline_type)
	_apply_type_style()
	_apply_layout()

# The active stance, or null. Pushed by HandContainer/DeckView on the
# controller's stance_changed - a stance changes what an Attack costs and
# deals, so the face has to be re-read, not just the rules state.
func set_grace(grace: int) -> void:
	_grace = maxi(grace, 0)

# The battle state this card's conditionals are read against - pushed
# by HandContainer on every signal that can move one (a card played, a
# turn boundary, Grace, HP, Toll), never per frame; null outside a
# battle hand. Re-reads the face: which half of a conditional is inked,
# and the panel.
func set_bonus_context(ctx: EffectContext) -> void:
	_bonus_context = ctx
	if card_data == null:
		return
	cost_label.text = str(_displayed_cost())
	_refresh_dynamic_text()
	_apply_layout()

# The Energy the fight would take for this card now (Combatant.energy_
# cost()) in a battle hand; its printed cost anywhere else.
func _displayed_cost() -> int:
	if _bonus_context != null and _bonus_context.player != null:
		return _bonus_context.player.energy_cost(card_data)
	return card_data.cost

func set_toll(toll: int) -> void:
	var value: int = maxi(toll, 0)
	if _toll == value or card_data == null:
		_toll = value
		return
	_toll = value
	_refresh_dynamic_text()
	_apply_layout()

func set_stance(stance: Stance) -> void:
	if _stance == stance:
		return
	_stance = stance
	if card_data != null:
		_refresh_dynamic_text()
		_apply_layout()

# Everything on the face whose number can move: the rules text's tokens
# and the HP cost line. Re-run whenever the card or the stance changes.
func _refresh_dynamic_text() -> void:
	_hp_cost = _derive_hp_cost(card_data)
	# The line is everything playing it costs in HP, a cost replacement's
	# included - {hp_cost} leaves that out (see TOKEN_HP_COST's doc).
	var line_hp: int = _hp_cost + _replaced_cost_hp()
	hp_cost_label.text = "−%d HP" % line_hp if line_hp > 0 else ""
	hp_cost_label.visible = line_hp > 0
	var was: CardBonus.State = _bonus_state
	# Read at the HP the card will have once its own costs are paid, so a
	# Critical clause the payment itself reaches (Self-Eater's) already shows.
	_bonus_state = CardBonus.state(card_data, _bonus_context.for_card_preview(_upfront_hp_cost())) if _bonus_context != null else CardBonus.State.NONE
	rules_text.text = _style_bonus_clauses(_format_rules(_resolve_tokens(card_data.description)))
	if _bonus_state != was:
		_animate_bonus_corner()

# Substitutes the effect-backed tokens. A token whose card has no
# matching effect is left standing rather than replaced with 0 - that way
# a mis-authored card reads as obviously wrong on its face instead of
# quietly claiming it deals nothing.
func _resolve_tokens(description: String) -> String:
	var text: String = description
	if text.contains(TOKEN_DAMAGE):
		var damage: int = _effect_value(card_data, DAMAGE_EFFECT_TYPES)
		if damage >= 0:
			# An Attack's number is what it will actually land for, its
			# attack bonus included - the same addition damage_effect.gd
			# makes, once, to the card's first damage effect. On a Critical
			# card this is the {else} half: the bonus as if NOT Critical.
			if card_data.card_type == CardData.CardType.ATTACK:
				damage += _attack_bonus_for_half(false)
			damage = _landed(damage, _damage_reaches_all(false))
			text = text.replace(TOKEN_DAMAGE, str(damage))
	if text.contains(TOKEN_ALT_DAMAGE) or text.contains(TOKEN_BONUS_DAMAGE):
		var bonus_damage: int = _bonus_effect_value(card_data, DAMAGE_EFFECT_TYPES)
		if bonus_damage >= 0:
			# The {if} half's bonus - on a Critical card, as if Critical.
			if card_data.card_type == CardData.CardType.ATTACK:
				bonus_damage += _attack_bonus_for_half(true)
			bonus_damage = _landed(bonus_damage, _damage_reaches_all(true))
			text = text.replace(TOKEN_ALT_DAMAGE, str(bonus_damage)).replace(TOKEN_BONUS_DAMAGE, str(bonus_damage))
	# Under a stance that forbids Block (Last Resort) every Block number
	# reads 0 - what EffectContext.gain_block() will actually give. The
	# card's own data is untouched.
	var no_block: bool = Stance.prevents_block_gain(_stance)
	if text.contains(TOKEN_BLOCK):
		var block: int = _effect_value(card_data, BLOCK_EFFECT_TYPES)
		if block >= 0:
			text = text.replace(TOKEN_BLOCK, str(0 if no_block else block))
	if text.contains(TOKEN_ALT_BLOCK) or text.contains(TOKEN_BONUS_BLOCK):
		var bonus_block: int = _bonus_effect_value(card_data, BLOCK_EFFECT_TYPES)
		if bonus_block >= 0:
			if no_block:
				bonus_block = 0
			text = text.replace(TOKEN_ALT_BLOCK, str(bonus_block)).replace(TOKEN_BONUS_BLOCK, str(bonus_block))
	if text.contains(TOKEN_DRAW):
		var draw: int = _effect_value(card_data, [CardEffect.EffectType.DRAW])
		if draw >= 0:
			text = text.replace(TOKEN_DRAW, str(draw))
	if text.contains(TOKEN_HP_COST):
		text = text.replace(TOKEN_HP_COST, str(_hp_cost))
	if text.contains(TOKEN_TOLL):
		text = text.replace(TOKEN_TOLL, str(_toll_token_value()))
	if text.contains(TOKEN_TOLL_HEAL):
		text = text.replace(TOKEN_TOLL_HEAL, str(_toll_heal_preview()))
	return text

# What this card's TOLL_HEAL would actually heal at the Toll now held -
# the same arithmetic toll_heal_effect.gd does, so the face can't promise
# a number the resolver won't pay. 0 with no such effect.
func _toll_heal_preview() -> int:
	for effect in card_data.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.TOLL_HEAL:
			return mini(mini(effect.toll_cost, _toll) / 2, effect.value)
	return 0

# What a blow the card adds up to `blow` (its value and attack bonus)
# lands for against the context's target - its mark bonus (Come Due)
# added, then DamageEffect.landed(), the resolvers' own call. The target
# is the one enemy of a single-enemy fight, or the enemy an armed card is
# over (BattleController.preview_context()/preview_context_against());
# none for an all-enemies effect (`all_enemies`), which reads with the
# player's own modifiers only. Outside a battle hand, `blow` as it is.
func _landed(blow: int, all_enemies: bool) -> int:
	if _bonus_context == null or _bonus_context.player == null:
		return blow
	var enemy: Combatant = null if all_enemies else _bonus_context.target
	var preview: EffectContext = _bonus_context.for_card_preview(_upfront_hp_cost())
	preview.card_is_attack = card_data.card_type == CardData.CardType.ATTACK
	return DamageEffect.landed(blow + preview.mark_bonus_for(enemy), _bonus_context.player, enemy)

# Whether the damage effect a token reads - the first one, or with
# `conditional` the first conditional one, as _effect_value() and
# _bonus_effect_value() pick them - hits every enemy.
func _damage_reaches_all(conditional: bool) -> bool:
	for effect in card_data.effects:
		if effect == null or not DAMAGE_EFFECT_TYPES.has(effect.effect_type):
			continue
		if conditional and effect.condition == CardEffect.Condition.NONE:
			continue
		return effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES
	return false

# The first matching effect's value, or -1 when the card has none - the
# REPLACEMENT value when the effect's condition is one this face can
# evaluate and it currently holds (see set_grace()). Only HAS_GRACE is
# previewed: the others read state the view isn't given, and a card whose
# number can't be previewed spells its own condition out in prose
# instead, the way Left Hand does.
# The BASE number of the first effect of one of `types` - never the
# conditional one: which half of a face applies is said with ink (see
# _style_bonus_clauses()), not by swapping the number.
func _effect_value(data: CardData, types: Array) -> int:
	for effect in data.effects:
		if effect == null or not types.has(effect.effect_type):
			continue
		return effect.value
	return -1

# The number the first conditional effect of one of `types` is FOR - see
# CardBonus.bonus_value(). -1 when the card has none, so a stray
# {alt_damage} is left standing on the face like any other unmatched
# token.
func _bonus_effect_value(data: CardData, types: Array) -> int:
	for effect in data.effects:
		if effect == null or not types.has(effect.effect_type):
			continue
		if effect.condition == CardEffect.Condition.NONE:
			continue
		return CardBonus.bonus_value(effect)
	return -1

# Whether any previewable conditional on this card is a REPLACE - the
# one mode where the base sentence itself stops applying when the
# condition holds, and so dims.
func _bonus_replaces() -> bool:
	if card_data == null:
		return false
	for effect in card_data.effects:
		if CardBonus.previewable(effect) and CardBonus.mode(effect) == CardBonus.Mode.REPLACE:
			return true
	return false

# Which half of a conditional face applies, said in ink. The {if}
# clause and the {else} base text (markers stripped either way):
#   neutral / NONE  - everything ink, as authored.
#   DORMANT         - the clause in bonus_dormant_ink, the rest ink.
#   LIVE, REPLACE   - the clause ink, the {else} text dormant.
#   LIVE, ADD/GATE  - everything ink; the base still applies.
# Runs on BBCode _format_rules() has already escaped and bolded - the
# markers carry no brackets, so they survive that, and a keyword inside
# a clause is still bold.
func _style_bonus_clauses(bbcode: String) -> String:
	var dormant: String = "[color=#%s]" % Color(bonus_dormant_ink, rules_alpha).to_html(true)
	var if_open: String = ""
	var else_open: String = ""
	match _bonus_state:
		CardBonus.State.DORMANT:
			if_open = dormant
		CardBonus.State.LIVE:
			if _bonus_replaces():
				else_open = dormant
		_:
			pass
	var text: String = bbcode
	text = text.replace(MARK_IF_OPEN, if_open).replace(MARK_IF_CLOSE, "[/color]" if not if_open.is_empty() else "")
	text = text.replace(MARK_ELSE_OPEN, else_open).replace(MARK_ELSE_CLOSE, "[/color]" if not else_open.is_empty() else "")
	return text

# The description with its markers stripped - what the face reads as
# plain text, for measuring.
static func _strip_markers(text: String) -> String:
	return text.replace(MARK_IF_OPEN, "").replace(MARK_IF_CLOSE, "").replace(MARK_ELSE_OPEN, "").replace(MARK_ELSE_CLOSE, "")

# The corner's growth on LIVE and its return on anything else - one
# tween, restarted from wherever the blend stands, so a quick flip never
# pops.
func _animate_bonus_corner() -> void:
	if _bonus_corner_tween != null and _bonus_corner_tween.is_valid():
		_bonus_corner_tween.kill()
	var live: bool = _bonus_state == CardBonus.State.LIVE
	var target: float = 1.0 if live else 0.0
	var seconds: float = bonus_in_seconds if live else bonus_out_seconds
	if seconds <= 0.0 or not is_inside_tree():
		_set_bonus_corner_blend(target)
		return
	_bonus_corner_tween = create_tween()
	_bonus_corner_tween.set_ease(Tween.EASE_OUT if live else Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	_bonus_corner_tween.tween_method(_set_bonus_corner_blend, _bonus_corner_blend, target, seconds)

func _set_bonus_corner_blend(blend: float) -> void:
	_bonus_corner_blend = clampf(blend, 0.0, 1.0)
	if _bonus_corner != null:
		_bonus_corner.queue_redraw()

# The fold: its right angle at the top-right corner inset by corner_
# radius (inside the rounded edge, and past the border at either weight,
# 1 or hover_frame_width_px), the two legs running along the top and
# right edges, bonus_corner_px long at full growth.
func _draw_bonus_corner() -> void:
	var leg: float = bonus_corner_px * _bonus_corner_blend
	if leg <= 0.0:
		return
	var inset: float = float(corner_radius)
	var right_angle := Vector2(card_size.x - inset, inset)
	var points := PackedVector2Array([
		right_angle + Vector2(-leg, 0.0),
		right_angle,
		right_angle + Vector2(0.0, leg),
	])
	_bonus_corner.draw_colored_polygon(points, ink_color)

# The inner rule on the art field's own rect and radius, drawn inward
# from its edge; the outer one art_outer_rule_inset_px beyond it, its
# radius grown by the same distance so the corners stay concentric.
func _draw_art_rule() -> void:
	var field := Rect2(art_field.position, art_field.size)
	if art_rule_width_px > 0:
		_art_rule.draw_style_box(_rule_style(art_rule_color, art_rule_width_px, art_field_radius), field)
	_draw_edge_pair(_art_rule, field.grow(-float(art_rule_width_px)), float(art_field_radius), art_inset_shade, art_inset_light)
	var rarity_color: Color = _rarity_rule_color()
	var rarity_width: int = _rarity_rule_width()
	if rarity_width > 0 and rarity_color.a > 0.0:
		_art_rule.draw_style_box(_rule_style(rarity_color, rarity_width, art_field_radius + rarity_width), field.grow(float(rarity_width)))
	if art_outer_rule_enabled and art_outer_rule_width_px > 0 and card_data != null:
		var grow: int = art_outer_rule_inset_px + art_outer_rule_width_px
		_art_rule.draw_style_box(_rule_style(_keyline_color(), art_outer_rule_width_px, art_field_radius + grow), field.grow(float(grow)))

# The face inside the frame as one rounded box for the paper shader: its
# alpha is the corner mask, its red channel this card's seed (from the
# name, so a card is always cut from the same place on the sheet).
func _draw_paper() -> void:
	var seed: float = float(absi(card_data.card_name.hash()) % 1000) / 1000.0 if card_data != null else 0.0
	var inset: float = float(_card_style.border_width_top) if _card_style != null else 1.0
	var style := _rounded_style(Color(seed, 0.0, 0.0, 1.0), maxi(corner_radius - int(inset), 0))
	paper.draw_style_box(style, Rect2(Vector2.ZERO, size).grow(-inset))

# The inset rule and the card-stock edges, under everything on the face:
# the top light and bottom shade run just inside the frame.
func _draw_keyline() -> void:
	var face := Rect2(Vector2.ZERO, size)
	var shade: Color = ink_color
	shade.a = bottom_shade_alpha
	_draw_edge_pair(keyline, face.grow(-1.0), float(corner_radius), top_highlight_color, shade)
	if inner_keyline_width_px > 0:
		var inset: int = inner_keyline_inset_px
		var rule: Color = ink_color
		rule.a = inner_keyline_alpha
		keyline.draw_style_box(_rule_style(rule, inner_keyline_width_px, maxi(corner_radius - inset, 0)), face.grow(-float(inset)))

# A 1px line along the inside top of `rect` and one along its inside
# bottom, each stopping `radius` short of the corners.
func _draw_edge_pair(canvas: Control, rect: Rect2, radius: float, top: Color, bottom: Color) -> void:
	var left: float = rect.position.x + radius
	var right: float = rect.end.x - radius
	if right <= left:
		return
	if top.a > 0.0:
		canvas.draw_line(Vector2(left, rect.position.y + 0.5), Vector2(right, rect.position.y + 0.5), top, 1.0)
	if bottom.a > 0.0:
		canvas.draw_line(Vector2(left, rect.end.y - 0.5), Vector2(right, rect.end.y - 0.5), bottom, 1.0)

# The rarity rule's colour for this card: transparent (none) for Common,
# UNSET, or no card at all.
func _rarity_rule_color() -> Color:
	if card_data == null:
		return Color(0, 0, 0, 0)
	match card_data.rarity:
		CardData.CardRarity.UNCOMMON:
			return rarity_rule_uncommon
		CardData.CardRarity.RARE:
			return rarity_rule_rare
		CardData.CardRarity.ULTRA_RARE:
			return rarity_rule_ultra_rare
	return Color(0, 0, 0, 0)

func _rarity_rule_width() -> int:
	if card_data != null and card_data.rarity == CardData.CardRarity.ULTRA_RARE:
		return rarity_rule_ultra_rare_width_px
	return rarity_rule_width_px

func _rule_style(color: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := _rounded_style(Color(0, 0, 0, 0), radius)
	style.draw_center = false
	style.border_color = color
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	return style

# The art panel's tint. One StyleBoxFlat kept, not rebuilt per call.
func _apply_panel_color() -> void:
	if _art_style == null:
		_art_style = _rounded_style(_art_field_color(), art_field_radius)
		art_field.add_theme_stylebox_override("panel", _art_style)
	_art_style.bg_color = _art_field_color()

# Whether the player can currently afford this card - HandContainer pushes
# this on every energy change. Unplayable fades the whole card.
func set_playable(playable: bool) -> void:
	_playable = playable
	modulate.a = 1.0 if playable else unplayable_alpha

# The scale this card sits at when neither hovered nor armed - set by
# HandContainer's reflow (and DeckView), never by this card itself.
func set_base_scale(base_scale: float) -> void:
	_base_scale = base_scale
	if not _armed and not (_hovering and hover_enabled and not _hover_suppressed):
		scale = Vector2.ONE * _base_scale

# HandContainer: true while any card in the hand is armed.
func set_hover_suppressed(suppressed: bool) -> void:
	_hover_suppressed = suppressed
	if suppressed and _hovering and not _armed:
		_lower_from_hover()

# The armed pose's bottom-centre point in viewport pixels, for
# HandContainer to move the slot to.
func get_armed_bottom_centre() -> Vector2:
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	return Vector2(view_size.x / 2.0, view_size.y * armed_bottom_y_fraction)

# Called once by HandContainer right after this card enters the row - sets
# where "at rest" actually is and snaps there immediately (not tweened;
# this is initial placement, not a hover transition). Safe to call before
# or after set_card_data().
func set_rest_offset(offset_y: float) -> void:
	_rest_offset_y = offset_y
	if not _armed:
		position.y = _rest_offset_y

# Held while awaiting a target for this card (see BattleController.
# request_play()) - hover in/out is ignored while armed, since the card is
# already deliberately placed and shouldn't drop just because the mouse
# passes over it. The card drops its hover lift (the slot is about to
# travel to armed_position - see HandContainer._on_card_armed()), scales
# to armed_scale, keeps the hover frame weight, and holds at least
# selected_hold_sec before release() may return it.
func lift_and_hold() -> void:
	_armed = true
	_armed_at_msec = Time.get_ticks_msec()
	_set_lifted_look(true)
	_tween_to(_rest_offset_y, armed_duration_sec)
	_tween_scale(armed_scale, armed_duration_sec)
	armed.emit()

# Cancelled: back to the fan. HandContainer returns the slot on disarmed;
# this card only returns its scale and frame. If the mouse is still over
# it, it settles as a plain hover instead of dropping fully.
func release() -> void:
	_armed = false
	var held_sec: float = float(Time.get_ticks_msec() - _armed_at_msec) / 1000.0
	var remaining: float = selected_hold_sec - held_sec
	if remaining > 0.0:
		await get_tree().create_timer(remaining).timeout
		if _armed:
			return
	disarmed.emit()
	if _hovering and hover_enabled and not _hover_suppressed:
		_raise_for_hover(armed_duration_sec)
	else:
		_set_lifted_look(false)
		_tween_to(_rest_offset_y, armed_duration_sec)
		_tween_scale(_base_scale, armed_duration_sec)

# Played: the slot is leaving the hand under HandContainer.play_card()'s
# own animation, from wherever the armed pose put it - clear the armed
# state without any return tween.
func mark_played() -> void:
	_armed = false
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()

# Hover driven from outside the mouse - a screen's keyboard focus
# (RewardScreen's card choice) - with exactly the mouse's own effect.
func set_hovered(hovered: bool) -> void:
	if hovered == _hovering:
		return
	if hovered:
		_on_mouse_entered()
	else:
		_on_mouse_exited()

func _on_mouse_entered() -> void:
	_hovering = true
	if hover_enabled and not _armed and not _hover_suppressed:
		_raise_for_hover(hover_duration_sec)

func _on_mouse_exited() -> void:
	_hovering = false
	if hover_enabled and not _armed and not _hover_suppressed:
		_lower_from_hover()

# Hover: lift in place and grow about the bottom centre, over the
# neighbours (HandContainer raises the slot's z on lifted).
func _raise_for_hover(duration: float) -> void:
	_set_lifted_look(true)
	_tween_to(_rest_offset_y - _scaled_lift(), duration)
	_tween_scale(_base_scale * hover_scale, duration)
	lifted.emit()

func _lower_from_hover() -> void:
	_set_lifted_look(false)
	_tween_to(_rest_offset_y, hover_duration_sec)
	_tween_scale(_base_scale, hover_duration_sec)
	lowered.emit()

# The lift in this card's parent's pixels: hover_lift is a 1x number.
func _scaled_lift() -> float:
	return hover_lift * _base_scale

func _tween_to(target_y: float, duration: float) -> void:
	var tween: Tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(self, "position:y", target_y, duration)

func _tween_scale(target: float, duration: float) -> void:
	if _scale_tween != null and _scale_tween.is_valid():
		_scale_tween.kill()
	_scale_tween = create_tween()
	_scale_tween.set_ease(Tween.EASE_OUT)
	_scale_tween.set_trans(Tween.TRANS_CUBIC)
	_scale_tween.tween_property(self, "scale", Vector2.ONE * target, duration)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(card_data)

# --- Derivations from CardData ---

# Strike / guard / toll / utility from what the card does. Any Toll-
# mechanic effect makes it a toll card first, whatever else it does.
# Otherwise ATTACK is strike, and SKILL splits on whether the card
# actually defends the player: raising block (BLOCK/UNDAMAGED_BLOCK),
# adding absorb, or putting a damage-reducing status on HER. Everything
# else is utility - draw, energy, anything that changes the shape of the
# turn rather than the damage in it.
#
# "Defensive status" is read off the status itself rather than listed by
# name (see _is_defensive_status), so a second Braced-like status is
# classified the day it is authored, with nothing to remember here.
#
# Interim - see DESIGN.md: CardType should grow TOLL and rename SKILL to
# GUARD, at which point the strike/guard/toll part becomes a straight
# read of card_type and only the guard/utility split stays derived.
static func _derive_keyline_type(data: CardData) -> KeylineType:
	for effect in data.effects:
		if effect == null:
			continue
		match effect.effect_type:
			CardEffect.EffectType.TOLL_DAMAGE, CardEffect.EffectType.TOLL_BLOCK, CardEffect.EffectType.TOLL_RETALIATE, \
			CardEffect.EffectType.SELF_DAMAGE_TOLL, CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE, CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL, 			CardEffect.EffectType.TOLL_HEAL, CardEffect.EffectType.SPEND_TOLL:
				return KeylineType.TOLL
	# Read off card_type, not off the effect: a stance is a stance because
	# of what it LEAVES BEHIND, and the effect that applies it is the same
	# APPLY_STANCE whatever the stance does.
	if data.card_type == CardData.CardType.STANCE:
		return KeylineType.STANCE
	if data.card_type == CardData.CardType.POWER:
		return KeylineType.POWER
	if data.card_type == CardData.CardType.SKILL:
		for effect in data.effects:
			if effect == null:
				continue
			match effect.effect_type:
				CardEffect.EffectType.BLOCK, CardEffect.EffectType.UNDAMAGED_BLOCK, CardEffect.EffectType.ABSORB:
					return KeylineType.GUARD
				CardEffect.EffectType.APPLY_STATUS:
					if _is_defensive_status(effect.status_data):
						return KeylineType.GUARD
				CardEffect.EffectType.APPLY_STATUS_TO_TARGET:
					# On the ENEMY (see apply_status_to_target_effect.gd) the
					# test turns round: cutting its OUTGOING damage is guard
					# (Brace); cutting its incoming would make it harder to
					# kill, the opposite of guard.
					if _is_disarming_status(effect.status_data):
						return KeylineType.GUARD
		return KeylineType.UTILITY
	return KeylineType.STRIKE

# A status that reduces the damage its holder takes. Both modifier
# operations reduce on a NEGATIVE magnitude - ADD adds it, MULTIPLY adds
# magnitude% of the running total (see Status.apply_modifiers()) - so the
# sign is the whole test, and it reads the same for a flat -3 as for
# Braced's -50%.
static func _is_defensive_status(status: StatusData) -> bool:
	if status == null:
		return false
	return status.category == StatusData.Category.MODIFIER \
		and status.modifier_target == StatusData.ModifierTarget.INCOMING_DAMAGE \
		and status.default_magnitude < 0

# A status that cuts the damage its holder DEALS - on an enemy, the
# player's defence (Braced). Same sign test as _is_defensive_status().
static func _is_disarming_status(status: StatusData) -> bool:
	if status == null:
		return false
	return status.category == StatusData.Category.MODIFIER \
		and status.modifier_target == StatusData.ModifierTarget.OUTGOING_DAMAGE \
		and status.default_magnitude < 0

# The HP the card costs to play: the sum of its self-scoped SELF_DAMAGE /
# SELF_DAMAGE_TOLL effect values. CardData.cost is energy only.
func _derive_hp_cost(data: CardData) -> int:
	var total: int = 0
	for effect in data.effects:
		if effect == null:
			continue
		if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
			total += effect.value
	# A stance charges for playing an ATTACK, which is a cost of this card
	# exactly as much as its own self-damage is - so it belongs on the same
	# line rather than hidden in the stance's description.
	if data.card_type == CardData.CardType.ATTACK:
		total += Stance.attack_hp_loss(_stance)
	return total

# The HP a cost replacement (Collateral) takes for this card in place of
# its Energy, as the fight would read it now (Combatant.replaced_cost_
# hp()); 0 outside a battle hand.
func _replaced_cost_hp() -> int:
	if _bonus_context == null or _bonus_context.player == null:
		return 0
	return _bonus_context.player.replaced_cost_hp(card_data)

# The HP paid before this card's first conditional or damage effect reads
# anything: a cost replacement's HP and the stance's per-Attack cost
# (both paid before any effect, see EffectResolver.resolve_card()) and
# the card's own self-damage authored ahead of it (none is, now). What
# the face judges Critical against, so it shows the number the card will
# land for, not the one it would at the HP held now. Self-damage authored after (Bite Down's, Last Wager's - the
# Wanderer's attack-then-pay convention) is paid too late to count.
func _upfront_hp_cost() -> int:
	var total: int = _replaced_cost_hp()
	if card_data.card_type == CardData.CardType.ATTACK:
		total += Stance.attack_hp_loss(_stance)
	for effect in card_data.effects:
		if effect == null:
			continue
		if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
			total += effect.value
			continue
		if effect.condition != CardEffect.Condition.NONE or DAMAGE_EFFECT_TYPES.has(effect.effect_type) \
				or effect.effect_type == CardEffect.EffectType.TOLL_DAMAGE:
			break
	return total

# The attack bonus one half of the face prints. On a card whose damage is
# conditional on Critical, each half is read in its own state - the {if}
# half as if Critical, the {else} half as if not - so neither inherits a
# bonus (Last Resort, Dying Light) that needs the other. Any other card
# prints the bonus as it stands (_attack_bonus_preview()).
func _attack_bonus_for_half(conditional_half: bool) -> int:
	if _bonus_context == null or _bonus_context.player == null:
		return _attack_bonus_preview()
	for effect in card_data.effects:
		if effect == null or not DAMAGE_EFFECT_TYPES.has(effect.effect_type):
			continue
		if effect.condition == CardEffect.Condition.CRITICAL:
			return AttackBonus.when_critical(_bonus_context.player, conditional_half)
		break
	return _attack_bonus_preview()

# What {toll} prints. On a card that spends all Toll as damage
# (Reckoning) it is that blow, as toll_damage_effect.gd will land it: the
# Toll held, plus the Toll the card's own upfront HP will make (Self-
# Eater's 2, paid first - never more than the HP there is to lose), plus
# the attack bonus, through _landed() against the target. Anywhere else,
# the Toll held.
func _toll_token_value() -> int:
	for effect in card_data.effects:
		if effect == null or effect.effect_type != CardEffect.EffectType.TOLL_DAMAGE:
			continue
		var made: int = _upfront_hp_cost()
		if _bonus_context != null and _bonus_context.player != null:
			made = mini(made, _bonus_context.player.hp)
		var bonus: int = _attack_bonus_preview() if card_data.card_type == CardData.CardType.ATTACK else 0
		return _landed(_toll + made + bonus, false)
	return _toll

# The attack bonus this Attack would get if played now - AttackBonus, the
# resolver's own sum, at the HP left after _upfront_hp_cost(). Outside a
# battle hand there is no player to read, so only the stance counts, and
# never its Critical half.
func _attack_bonus_preview() -> int:
	if _bonus_context == null or _bonus_context.player == null:
		return Stance.attack_bonus(_stance, false)
	var player: Combatant = _bonus_context.player
	return AttackBonus.for_player(player, player.hp - _upfront_hp_cost())

static func _type_label_text(keyline_type: KeylineType) -> String:
	match keyline_type:
		KeylineType.GUARD:
			return "GUARD"
		KeylineType.TOLL:
			return "TOLL"
		KeylineType.UTILITY:
			return "UTILITY"
		KeylineType.STANCE:
			return "STANCE"
		KeylineType.POWER:
			return "POWER"
		_:
			return "STRIKE"

# Escapes the description for BBCode and sets every KEYWORDS entry in
# bold, whole words only.
static func _format_rules(description: String) -> String:
	var escaped: String = description.replace("[", "[lb]")
	for keyword in KEYWORDS:
		var regex := RegEx.new()
		regex.compile("\\b%s\\b" % keyword)
		escaped = regex.sub(escaped, "[b]%s[/b]" % keyword, true)
	return escaped

# --- Style ---

func _keyline_color() -> Color:
	match _keyline_type:
		KeylineType.GUARD:
			return keyline_guard
		KeylineType.TOLL:
			return keyline_toll
		KeylineType.UTILITY:
			return keyline_utility
		KeylineType.STANCE:
			return keyline_stance
		KeylineType.POWER:
			return keyline_power
		_:
			return keyline_strike

func _art_field_color() -> Color:
	match _keyline_type:
		KeylineType.GUARD:
			return art_field_guard
		KeylineType.TOLL:
			return art_field_toll
		KeylineType.UTILITY:
			return art_field_utility
		KeylineType.STANCE:
			return art_field_stance
		KeylineType.POWER:
			return art_field_power
		_:
			return art_field_strike

func _rounded_style(bg: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_right = radius
	style.corner_radius_bottom_left = radius
	style.shadow_size = 0
	return style

# The card's text sets in MSDF copies of its fonts, so a card enlarged by
# Control.scale (inspect 2.2x, hover, armed) keeps crisp glyphs rather than
# magnifying ones rasterised at 1x. One copy per font, made on first use
# and shared by every card; the imports themselves stay hinted for the
# rest of the UI. The copy keeps the import's msdf_pixel_range (8) - card
# text has no outline, so that clears 2x the widest one. The rules fit
# (_rules_wrap(), _rules_block_height(), _cap_top()) still measures the
# hinted fonts, so every card keeps the rules size it had; at that size
# the MSDF copies break every current card's rules on the same words.
static var _msdf_fonts: Dictionary[Font, Font] = {}

static func _msdf(font: Font) -> Font:
	if not font is FontFile:
		return font
	if not _msdf_fonts.has(font):
		var copy := font.duplicate() as FontFile
		copy.multichannel_signed_distance_field = true
		_msdf_fonts[font] = copy
	return _msdf_fonts[font]

# A Bold variation with letter spacing in em (FontVariation.spacing_glyph
# is whole pixels, so this rounds at the given size).
func _spaced_bold(font_size: int, spacing_em: float) -> Font:
	var variation := FontVariation.new()
	variation.base_font = _msdf(rules_font_bold)
	variation.spacing_glyph = roundi(float(font_size) * spacing_em)
	return variation

func _apply_style() -> void:
	_card_style = _rounded_style(field_color, corner_radius)
	add_theme_stylebox_override("panel", _card_style)
	_apply_frame(false)

	# Shadows: two transparent panels behind the face, each carrying one
	# of the shadows (StyleBoxFlat has a single shadow).
	var hairline := _rounded_style(Color(0, 0, 0, 0), corner_radius)
	hairline.shadow_size = 1
	hairline.shadow_offset = Vector2(0.0, 1.0)
	shadow_hairline.add_theme_stylebox_override("panel", hairline)
	var soft := _rounded_style(Color(0, 0, 0, 0), corner_radius)
	soft.shadow_size = shadow_soft_size_px
	soft.shadow_offset = Vector2(0.0, shadow_soft_offset_px)
	shadow_soft.add_theme_stylebox_override("panel", soft)
	_apply_shadows(false)

	name_label.add_theme_color_override("font_color", ink_color)
	name_label.add_theme_font_size_override("font_size", name_font_size_px)
	if name_font != null:
		name_label.add_theme_font_override("font", _msdf(name_font))

	cost_label.add_theme_color_override("font_color", ink_color)
	cost_label.add_theme_font_size_override("font_size", cost_font_size_px)
	if cost_font != null:
		cost_label.add_theme_font_override("font", _msdf(cost_font))

	var hp_ink: Color = ink_color
	hp_ink.a = hp_cost_alpha
	hp_cost_label.add_theme_color_override("font_color", hp_ink)
	hp_cost_label.add_theme_font_size_override("font_size", hp_cost_font_size_px)
	if rules_font_bold != null:
		hp_cost_label.add_theme_font_override("font", _spaced_bold(hp_cost_font_size_px, hp_cost_letter_spacing_em))
	var ledger_ink: Color = ink_color
	ledger_ink.a = cost_rule_alpha
	cost_rule.color = ledger_ink

	_apply_panel_color()

	rules_text.bbcode_enabled = true
	rules_text.scroll_active = false
	rules_text.fit_content = false
	rules_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rules_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var rules_ink: Color = ink_color
	rules_ink.a = rules_alpha
	rules_text.add_theme_color_override("default_color", rules_ink)
	if rules_font != null:
		rules_text.add_theme_font_override("normal_font", _msdf(rules_font))
	if rules_font_bold != null:
		rules_text.add_theme_font_override("bold_font", _msdf(rules_font_bold))
	_apply_rules_font_size(rules_font_sizes[0] if not rules_font_sizes.is_empty() else 15)

	var rule_ink: Color = ink_color
	rule_ink.a = footer_rule_alpha
	footer_rule.color = rule_ink
	footer_rule.visible = footer_rule_enabled

	var type_ink: Color = ink_color
	type_ink.a = type_label_alpha
	type_label.add_theme_color_override("font_color", type_ink)
	type_label.add_theme_font_size_override("font_size", type_label_font_size_px)
	if rules_font_bold != null:
		type_label.add_theme_font_override("font", _spaced_bold(type_label_font_size_px, type_label_letter_spacing_em))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

func _apply_rules_font_size(font_size: int) -> void:
	rules_text.add_theme_font_size_override("normal_font_size", font_size)
	rules_text.add_theme_font_size_override("bold_font_size", font_size)
	# line_separation is the EXTRA pixels between lines; the font's own
	# line is ~1.0 em, so this puts the total near rules_line_height em.
	rules_text.add_theme_constant_override("line_separation", roundi(float(font_size) * (rules_line_height - 1.0)))
	rules_text.add_theme_constant_override("paragraph_separation", rules_paragraph_gap_px)

# The frame: 1px ink at frame_alpha at rest, hover_frame_width_px full
# ink lifted; or the override edge if a caller asked for one.
func _apply_frame(lifted_look: bool) -> void:
	if _card_style == null:
		return
	var color: Color = ink_color
	var width: int = 1
	if edge_color_override_enabled:
		color = edge_color
		width = int(edge_width_px)
	elif lifted_look:
		width = hover_frame_width_px
	else:
		color.a = frame_alpha
	_card_style.border_width_left = width
	_card_style.border_width_top = width
	_card_style.border_width_right = width
	_card_style.border_width_bottom = width
	_card_style.border_color = color

func _apply_shadows(lifted_look: bool) -> void:
	var hairline := shadow_hairline.get_theme_stylebox("panel") as StyleBoxFlat
	var soft := shadow_soft.get_theme_stylebox("panel") as StyleBoxFlat
	if hairline == null or soft == null:
		return
	var hairline_color: Color = ink_color
	hairline_color.a = hover_shadow_hairline_alpha if lifted_look else shadow_hairline_alpha
	hairline.shadow_color = hairline_color
	var soft_color: Color = ink_color
	soft_color.a = hover_shadow_soft_alpha if lifted_look else shadow_soft_alpha
	soft.shadow_color = soft_color
	soft.shadow_size = hover_shadow_soft_size_px if lifted_look else shadow_soft_size_px
	soft.shadow_offset = Vector2(0.0, hover_shadow_soft_offset_px if lifted_look else shadow_soft_offset_px)

func _set_lifted_look(lifted_look: bool) -> void:
	_apply_frame(lifted_look)
	_apply_shadows(lifted_look)

# Type-dependent colour: the keyline and the tonal field. Re-run every
# set_card_data() call.
func _apply_type_style() -> void:
	if card_data == null:
		return
	_apply_panel_color()
	glyph.queue_redraw()
	if _art_rule != null:
		_art_rule.queue_redraw()

# --- Layout ---

# Vertical stack at 1x. The name holds one line beside the cost (a
# longer one is clipped and warned about); the art field is the fixed
# art_field_size rect under the header; the rules text takes the space
# between it and the footer at the first of rules_font_sizes that fits.
# Past the last size the card grows downward by what the text still
# needs - the face only: its containers keep card_size, and no current
# card gets there. Decided once at 1x; hover, armed and inspect scale the
# whole card.
func _apply_layout() -> void:
	# Rules text first: the face's height depends on it.
	var rules_width: float = card_size.x - outer_margin * 2.0
	var type_height: float = _line_height(type_label, type_label_font_size_px)
	var art_top: float = header_height + header_field_gap
	var rules_top: float = art_top + art_field_size.y + field_rules_gap
	var type_baseline: float = card_size.y - footer_bottom_ink_px
	var caps_top: float = roundf(type_baseline + _cap_top(rules_font_bold, type_label_font_size_px))
	var rule_top: float = caps_top - footer_rule_ink_gap_px - 1.0
	var rules_bottom: float = (rule_top if footer_rule_enabled else caps_top) - rules_footer_gap
	var available: float = rules_bottom - rules_top
	var paragraph_gaps: float = float(_rules_paragraph_count() - 1) * float(rules_paragraph_gap_px)
	var font_size: int = rules_font_sizes[rules_font_sizes.size() - 1] if not rules_font_sizes.is_empty() else 15
	var first_fit: int = -1
	for candidate in rules_font_sizes:
		var wrapped: Array[PackedStringArray] = _rules_wrap(candidate, rules_width)
		var height: float = _rules_block_height(candidate, _line_total(wrapped)) + paragraph_gaps
		if height > available:
			continue
		if first_fit < 0:
			first_fit = candidate
		if available - height >= rules_min_air_px and not _ends_on_lone_word(wrapped):
			first_fit = candidate
			break
	if first_fit >= 0:
		font_size = first_fit
	var lines: int = _line_total(_rules_wrap(font_size, rules_width))
	var rules_height: float = _rules_block_height(font_size, lines) + paragraph_gaps
	var growth: float = maxf(ceilf(rules_height - available), 0.0)
	if growth > 0.0:
		_warn_overlong(lines, font_size)
	_apply_rules_font_size(font_size)
	var face: Vector2 = Vector2(card_size.x, card_size.y + growth)
	size = face

	shadow_soft.position = Vector2.ZERO
	shadow_soft.size = face
	shadow_hairline.position = Vector2.ZERO
	shadow_hairline.size = face
	if _bonus_corner != null:
		_bonus_corner.position = Vector2.ZERO
		_bonus_corner.size = face
		_bonus_corner.queue_redraw()
	if _art_rule != null:
		_art_rule.position = Vector2.ZERO
		_art_rule.size = face
		_art_rule.queue_redraw()

	paper.position = Vector2.ZERO
	paper.size = face
	paper.queue_redraw()
	keyline.position = Vector2.ZERO
	keyline.size = face
	keyline.queue_redraw()

	# Cost numeral top-right; the name gets the rest of the header width.
	# Every Label is sized from its font's real line height (Font.get_
	# height()), never an em guess: a Label whose height is under one line
	# draws NO lines at all - Spectral's line box is ~1.4em, so 1.2em of
	# name label rendered nothing. Each is placed so its first baseline
	# lands on the header's (_top_for_baseline()); the boxes overlap, the
	# ink doesn't.
	var cost_width: float = _string_width(cost_label, cost_font_size_px)
	var cost_height: float = _line_height(cost_label, cost_font_size_px)
	cost_label.position = Vector2(card_size.x - outer_margin - cost_width, _top_for_baseline(cost_label, cost_font_size_px, header_baseline_px))
	cost_label.size = Vector2(cost_width, cost_height)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	if hp_cost_label.visible:
		var hp_width: float = _string_width(hp_cost_label, hp_cost_font_size_px)
		hp_cost_label.position = Vector2(card_size.x - outer_margin - hp_width, _top_for_baseline(hp_cost_label, hp_cost_font_size_px, hp_cost_baseline_px))
		hp_cost_label.size = Vector2(hp_width, _line_height(hp_cost_label, hp_cost_font_size_px))
		hp_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		# The ledger rule: a whole pixel, as wide as the wider figure.
		var rule_width: float = ceilf(maxf(cost_width, hp_width))
		cost_rule.position = Vector2(card_size.x - outer_margin - rule_width, floorf(cost_rule_y_px))
		cost_rule.size = Vector2(rule_width, 1.0)
	cost_rule.visible = hp_cost_label.visible

	# One line, always: the art field sits at a fixed height below it.
	var name_width: float = card_size.x - outer_margin * 2.0 - cost_width - name_cost_gap
	if _wrapped_line_count(name_label, name_font_size_px, name_width) > 1:
		_warn_long_name()
	name_label.position = Vector2(outer_margin, _top_for_baseline(name_label, name_font_size_px, header_baseline_px))
	name_label.size = Vector2(name_width, _line_height(name_label, name_font_size_px))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.clip_text = true

	# Footer: type label at the bottom of the face, the rule above it -
	# both moved down with the face when it grows.
	type_label.position = Vector2(outer_margin, _top_for_baseline(type_label, type_label_font_size_px, type_baseline + growth))
	type_label.size = Vector2(card_size.x - outer_margin * 2.0, type_height)
	footer_rule.position = Vector2(outer_margin, rule_top + growth)
	footer_rule.size = Vector2(card_size.x - outer_margin * 2.0, 1.0)

	art_field.position = Vector2(outer_margin, art_top)
	art_field.size = art_field_size
	art_rect.position = Vector2.ZERO
	art_rect.size = art_field.size
	glyph.position = Vector2.ZERO
	glyph.size = art_field.size
	glyph.queue_redraw()

	# Centred in its space (see _apply_style()), lifted a touch above true
	# centre.
	rules_text.position = Vector2(outer_margin, rules_top - rules_optical_lift_px)
	rules_text.size = Vector2(rules_width, rules_bottom + growth - rules_top)

func _string_width(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# Where a one-line Label's top goes so its baseline sits at `baseline` -
# a Label draws its first line's baseline one font ascent below its top.
func _top_for_baseline(label: Label, font_size: int, baseline: float) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return baseline - float(font_size)
	return baseline - font.get_ascent(font_size)

# How far above the baseline `font` (hinted - see _msdf()) inks a flat capital
# (negative = up), from the glyph itself - the line box's ascent
# overstates it. An "H", not the label's own text, so every type's
# footer lands on the same pixel whatever its round letters overshoot.
# The glyph's offset is its bitmap's, which the rasteriser pads by
# GLYPH_RECT_MARGIN_PX on every side; the ink starts inside that.
func _cap_top(font: Font, font_size: int) -> float:
	if font == null:
		return -float(font_size) * 0.7
	var ts: TextServer = TextServerManager.get_primary_interface()
	var rid: RID = font.get_rids()[0]
	var glyph: int = ts.font_get_glyph_index(rid, font_size, "H".unicode_at(0), 0)
	return ts.font_get_glyph_offset(rid, Vector2i(font_size, 0), glyph).y + GLYPH_RECT_MARGIN_PX

# One line's real height for this label's font at this size, rounded up
# so the Label always fits a whole line.
func _line_height(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return float(font_size) * 1.5
	return ceilf(font.get_height(font_size))

func _wrapped_line_count(label: Label, font_size: int, width: float) -> int:
	var font: Font = label.get_theme_font("font")
	if font == null or label.text.is_empty():
		return 1
	var line_height: float = font.get_height(font_size)
	var total: float = font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY).y
	return maxi(roundi(total / maxf(line_height, 1.0)), 1)

# The rules text as the face breaks it: per authored line (paragraph),
# the lines it wraps to. Shaped with the bold face on KEYWORDS, the way
# the RichTextLabel sets them, and broken as its WORD_SMART does - a
# bold "Critical" is wide enough to move a wrap.
func _rules_wrap(font_size: int, width: float) -> Array[PackedStringArray]:
	var wrapped: Array[PackedStringArray] = []
	if card_data == null or rules_font == null or card_data.description.is_empty():
		return wrapped
	var bold: Font = rules_font_bold if rules_font_bold != null else rules_font
	var keyword := RegEx.new()
	keyword.compile("\\b(%s)\\b" % "|".join(PackedStringArray(KEYWORDS)))
	var plain: String = _strip_markers(_resolve_tokens(card_data.description)).strip_edges()
	for text in plain.split("\n"):
		var paragraph := TextParagraph.new()
		paragraph.width = width
		paragraph.break_flags = TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE
		var at: int = 0
		for found in keyword.search_all(text):
			if found.get_start() > at:
				paragraph.add_string(text.substr(at, found.get_start() - at), rules_font, font_size)
			paragraph.add_string(found.get_string(), bold, font_size)
			at = found.get_end()
		if at < text.length() or text.is_empty():
			paragraph.add_string(text.substr(at), rules_font, font_size)
		var lines := PackedStringArray()
		for i in paragraph.get_line_count():
			var span: Vector2i = paragraph.get_line_range(i)
			lines.append(text.substr(span.x, span.y - span.x).strip_edges())
		wrapped.append(lines)
	return wrapped

static func _line_total(wrapped: Array[PackedStringArray]) -> int:
	var total: int = 0
	for lines in wrapped:
		total += lines.size()
	return maxi(total, 1)

# A paragraph that wraps and leaves one word alone on its last line.
static func _ends_on_lone_word(wrapped: Array[PackedStringArray]) -> bool:
	for lines in wrapped:
		if lines.size() > 1 and not lines[lines.size() - 1].contains(" "):
			return true
	return false

# What `lines` lines of rules text actually take: the font's own line
# box each, plus the line_separation _apply_rules_font_size() sets
# between them - measured, so a block that "fits" never touches the art
# or the type label.
func _rules_block_height(font_size: int, lines: int) -> float:
	var line_box: float = rules_font.get_height(font_size) if rules_font != null else float(font_size) * 1.2
	var separation: float = float(roundi(float(font_size) * (rules_line_height - 1.0)))
	return float(lines) * line_box + float(maxi(lines - 1, 0)) * separation

# The description's authored lines - each a paragraph, set apart by
# rules_paragraph_gap_px.
func _rules_paragraph_count() -> int:
	if card_data == null or card_data.description.is_empty():
		return 1
	return card_data.description.strip_edges().split("\n").size()

# Once per card name per session: the layout re-runs on every live
# refresh, and a warning per refresh would bury the log.
static var _warned: Dictionary = {}

func _warn_overlong(lines: int, font_size: int) -> void:
	var card_name: String = card_data.card_name if card_data != null else name
	if _warned.has("rules:" + card_name):
		return
	_warned["rules:" + card_name] = true
	push_warning("CardView: '%s' rules text runs to %d lines at %dpx, past the smallest size - the card grows. Rewrite it shorter." % [card_name, lines, font_size])

func _warn_long_name() -> void:
	var card_name: String = card_data.card_name if card_data != null else name
	if _warned.has("name:" + card_name):
		return
	_warned["name:" + card_name] = true
	push_warning("CardView: '%s' doesn't fit on one line beside its cost - clipped. Shorten the name." % card_name)

# --- Glyph ---

# Centred in the field, ink, glyph_line_width_px strokes - the same hand
# as BattleIntent's glyphs. Strike: a shafted chevron pointing right with
# a faint second chevron behind it. Guard: an open shield with a faint
# centre line. Toll: an upward arrow over a base line.
func _draw_glyph() -> void:
	if card_data == null:
		return
	var centre: Vector2 = glyph.size / 2.0
	var r: float = glyph_size_px * 0.5
	var faint: Color = ink_color
	faint.a = glyph_faint_alpha
	var w: float = glyph_line_width_px
	match _keyline_type:
		KeylineType.STRIKE:
			var chevron := PackedVector2Array([centre + Vector2(-r * 0.3, -r * 0.7), centre + Vector2(r * 0.4, 0.0), centre + Vector2(-r * 0.3, r * 0.7)])
			var second := PackedVector2Array([centre + Vector2(-r * 0.9, -r * 0.7), centre + Vector2(-r * 0.2, 0.0), centre + Vector2(-r * 0.9, r * 0.7)])
			glyph.draw_polyline(second, faint, w, true)
			glyph.draw_line(centre + Vector2(-r, 0.0), centre + Vector2(r * 0.4, 0.0), ink_color, w, true)
			glyph.draw_polyline(chevron, ink_color, w, true)
		KeylineType.GUARD:
			var shield := PackedVector2Array([
				centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
				centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
			])
			glyph.draw_line(centre + Vector2(0.0, -r * 0.7), centre + Vector2(0.0, r * 0.7), faint, w, true)
			glyph.draw_polyline(shield, ink_color, w, true)
		KeylineType.UTILITY:
			# Two short parallel strokes, offset diagonally - two cards, one
			# behind the other. Same faint-behind/ink-in-front reading as the
			# strike chevron and the shield's centre line: the back card is
			# the secondary stroke, the front one carries the ink.
			var lean := Vector2(r * 0.30, r * 0.65)
			var back := centre + Vector2(-r * 0.30, -r * 0.10)
			var front := centre + Vector2(r * 0.30, r * 0.10)
			glyph.draw_line(back - lean, back + lean, faint, w, true)
			glyph.draw_line(front - lean, front + lean, ink_color, w, true)
		KeylineType.STANCE:
			# The same bitten ring the standing row draws, at card scale -
			# one mark for the thing, wherever it appears.
			var ring := PackedVector2Array()
			for i in 19:
				var t: float = 30.0 + 270.0 * float(i) / 18.0
				ring.append(centre + Vector2(cos(deg_to_rad(t)), sin(deg_to_rad(t))) * r * 0.85)
			glyph.draw_line(centre + Vector2(-r * 0.2, r * 0.2), centre + Vector2(r * 0.55, -r * 0.55), faint, w, true)
			glyph.draw_polyline(ring, ink_color, w, true)
		KeylineType.POWER:
			# The stance's ring closed, with a faint one inside - it stays
			# like a stance does, but whole: nothing is bitten out of you
			# to hold it.
			glyph.draw_arc(centre, r * 0.85, 0.0, TAU, 36, ink_color, w, true)
			glyph.draw_arc(centre, r * 0.4, 0.0, TAU, 24, faint, w, true)
		KeylineType.TOLL:
			glyph.draw_line(centre + Vector2(-r * 0.8, r * 0.9), centre + Vector2(r * 0.8, r * 0.9), faint, w, true)
			glyph.draw_line(centre + Vector2(0.0, r * 0.6), centre + Vector2(0.0, -r * 0.9), ink_color, w, true)
			var head := PackedVector2Array([centre + Vector2(-r * 0.55, -r * 0.35), centre + Vector2(0.0, -r * 0.9), centre + Vector2(r * 0.55, -r * 0.35)])
			glyph.draw_polyline(head, ink_color, w, true)
