extends Panel
class_name CardView

# "Ink on bone": a pale card with dark type and edges, never a dark slab.
# The name is world voice (Spectral), the rules text is system voice
# (Alegreya Sans); dark reads as ink and lines - the 1px frame, the
# glyph, the footer rule - not as fill. The one colour on the card is a
# 2px keyline inside the top edge, by type (strike / guard / toll), and
# a matching tonal field behind the glyph. Cards never invert with the
# theme's on-pale/on-dark switch: every colour here is this script's
# own export, and nothing reads the theme's CardFace tokens any more -
# those belong to the chips and buttons.
#
# Layout at 1x is 200 x 280 (5:7); HandContainer/DeckView scale the
# whole card, so every size below is a 1x pixel. Top to bottom: keyline;
# name (top-left, up to two lines) beside the cost numeral (top-right,
# with a "-N HP" line under it when the card costs HP); the tonal field
# with the type glyph, which flexes; the rules text; a hairline footer
# rule and the small-caps type label. See _apply_layout() for how the
# field gives way to a longer rules text.

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

# Card type from the rules' point of view (strike / guard / toll), derived
# in _derive_keyline_type() - see DESIGN.md's note on why this isn't
# CardData.CardType yet.
enum KeylineType { STRIKE, GUARD, TOLL }

# Rules-text words set in bold. Whole-word, case-sensitive.
const KEYWORDS: Array[String] = ["Toll", "Rally"]

@export var card_size: Vector2 = Vector2(200.0, 280.0)

@export_group("Colours")
@export var field_color: Color = Color(0.94, 0.91, 0.86)
@export var ink_color: Color = Color(0.165, 0.165, 0.18)
@export_range(0.0, 1.0) var frame_alpha: float = 0.72
@export var corner_radius: int = 5
@export var keyline_strike: Color = Color(0.62, 0.56, 0.49)
@export var keyline_guard: Color = Color(0.49, 0.56, 0.59)
@export var keyline_toll: Color = Color(0.54, 0.50, 0.58)
@export var art_field_strike: Color = Color(0.886, 0.863, 0.796)
@export var art_field_guard: Color = Color(0.875, 0.878, 0.855)
@export var art_field_toll: Color = Color(0.878, 0.863, 0.886)
@export var art_field_radius: int = 3
# The two shadows: a hairline (1px down, 18%) and a soft spread (8px,
# 12%). Both deepen on hover (see Hover).
@export_range(0.0, 1.0) var shadow_hairline_alpha: float = 0.18
@export var shadow_soft_size_px: int = 8
@export_range(0.0, 1.0) var shadow_soft_alpha: float = 0.12

@export_group("Type")
@export var name_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")
@export var rules_font: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf")
@export var rules_font_bold: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
@export var name_font_size_px: int = 18
@export var cost_font_size_px: int = 23
@export var hp_cost_font_size_px: int = 9
@export_range(0.0, 1.0) var hp_cost_letter_spacing_em: float = 0.08
@export_range(0.0, 1.0) var hp_cost_alpha: float = 0.72
@export var rules_font_size_px: int = 15
@export var rules_font_size_tight_px: int = 13
@export var rules_line_height: float = 1.35
@export_range(0.0, 1.0) var rules_alpha: float = 0.92
# At this many lines the rules text drops to rules_font_size_tight_px and
# the field holds its minimum; one more and _warn_overlong() fires so the
# card can be rewritten.
@export var rules_max_comfortable_lines: int = 3
@export var rules_max_lines: int = 4
@export var type_label_font_size_px: int = 9
@export_range(0.0, 1.0) var type_label_letter_spacing_em: float = 0.16
@export_range(0.0, 1.0) var type_label_alpha: float = 0.62
@export_range(0.0, 1.0) var footer_rule_alpha: float = 0.25

@export_group("Layout")
@export var outer_margin: float = 12.0
@export var keyline_height: float = 2.0
@export var name_cost_gap: float = 8.0
@export var header_field_gap: float = 8.0
@export var field_min_height: float = 56.0
@export var field_rules_gap: float = 8.0
@export var rules_footer_gap: float = 8.0
@export var footer_rule_gap: float = 6.0
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
@export var hover_frame_width_px: int = 2
@export_range(0.0, 1.0) var hover_shadow_hairline_alpha: float = 0.28
@export var hover_shadow_soft_size_px: int = 12
@export_range(0.0, 1.0) var hover_shadow_soft_alpha: float = 0.2
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
@onready var keyline: ColorRect = $Keyline
@onready var name_label: Label = $NameLabel
@onready var cost_label: Label = $CostLabel
@onready var hp_cost_label: Label = $HpCostLabel
@onready var art_field: Panel = $ArtField
@onready var glyph: Control = $ArtField/Glyph
@onready var rules_text: RichTextLabel = $RulesText
@onready var footer_rule: ColorRect = $FooterRule
@onready var type_label: Label = $TypeLabel

var card_data: CardData
var _armed: bool = false
var _armed_at_msec: int = 0
var _playable: bool = true
var _keyline_type: KeylineType = KeylineType.STRIKE
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
	_apply_style()
	_apply_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func set_card_data(data: CardData) -> void:
	card_data = data
	name_label.text = data.card_name
	cost_label.text = str(data.cost)
	_keyline_type = _derive_keyline_type(data)
	_hp_cost = _derive_hp_cost(data)
	hp_cost_label.text = "−%d HP" % _hp_cost if _hp_cost > 0 else ""
	hp_cost_label.visible = _hp_cost > 0
	rules_text.text = _format_rules(data.description)
	type_label.text = _type_label_text(_keyline_type)
	_apply_type_style()
	_apply_layout()

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

# Strike / guard / toll from what the card does: any Toll-mechanic effect
# makes it a toll card, otherwise SKILL is guard and ATTACK is strike.
# Interim - see DESIGN.md: CardType should grow TOLL and rename SKILL to
# GUARD, at which point this becomes a straight read of card_type.
static func _derive_keyline_type(data: CardData) -> KeylineType:
	for effect in data.effects:
		if effect == null:
			continue
		match effect.effect_type:
			CardEffect.EffectType.TOLL_DAMAGE, CardEffect.EffectType.TOLL_BLOCK, CardEffect.EffectType.TOLL_RETALIATE, \
			CardEffect.EffectType.SELF_DAMAGE_TOLL, CardEffect.EffectType.TOLL_THRESHOLD_DAMAGE, CardEffect.EffectType.TOLL_FRACTION_DAMAGE_ALL:
				return KeylineType.TOLL
	if data.card_type == CardData.CardType.SKILL:
		return KeylineType.GUARD
	return KeylineType.STRIKE

# The HP the card costs to play: the sum of its self-scoped SELF_DAMAGE /
# SELF_DAMAGE_TOLL effect values. CardData.cost is energy only.
static func _derive_hp_cost(data: CardData) -> int:
	var total: int = 0
	for effect in data.effects:
		if effect == null:
			continue
		if effect.effect_type == CardEffect.EffectType.SELF_DAMAGE or effect.effect_type == CardEffect.EffectType.SELF_DAMAGE_TOLL:
			total += effect.value
	return total

static func _type_label_text(keyline_type: KeylineType) -> String:
	match keyline_type:
		KeylineType.GUARD:
			return "GUARD"
		KeylineType.TOLL:
			return "TOLL"
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
		_:
			return keyline_strike

func _art_field_color() -> Color:
	match _keyline_type:
		KeylineType.GUARD:
			return art_field_guard
		KeylineType.TOLL:
			return art_field_toll
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

# A Bold variation with letter spacing in em (FontVariation.spacing_glyph
# is whole pixels, so this rounds at the given size).
func _spaced_bold(font_size: int, spacing_em: float) -> Font:
	var variation := FontVariation.new()
	variation.base_font = rules_font_bold
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
	shadow_soft.add_theme_stylebox_override("panel", soft)
	_apply_shadows(false)

	name_label.add_theme_color_override("font_color", ink_color)
	name_label.add_theme_font_size_override("font_size", name_font_size_px)
	if name_font != null:
		name_label.add_theme_font_override("font", name_font)

	cost_label.add_theme_color_override("font_color", ink_color)
	cost_label.add_theme_font_size_override("font_size", cost_font_size_px)
	if name_font != null:
		cost_label.add_theme_font_override("font", name_font)

	var hp_ink: Color = ink_color
	hp_ink.a = hp_cost_alpha
	hp_cost_label.add_theme_color_override("font_color", hp_ink)
	hp_cost_label.add_theme_font_size_override("font_size", hp_cost_font_size_px)
	if rules_font_bold != null:
		hp_cost_label.add_theme_font_override("font", _spaced_bold(hp_cost_font_size_px, hp_cost_letter_spacing_em))

	art_field.add_theme_stylebox_override("panel", _rounded_style(_art_field_color(), art_field_radius))

	rules_text.bbcode_enabled = true
	rules_text.scroll_active = false
	rules_text.fit_content = false
	rules_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rules_ink: Color = ink_color
	rules_ink.a = rules_alpha
	rules_text.add_theme_color_override("default_color", rules_ink)
	if rules_font != null:
		rules_text.add_theme_font_override("normal_font", rules_font)
	if rules_font_bold != null:
		rules_text.add_theme_font_override("bold_font", rules_font_bold)
	_apply_rules_font_size(rules_font_size_px)

	var rule_ink: Color = ink_color
	rule_ink.a = footer_rule_alpha
	footer_rule.color = rule_ink

	var type_ink: Color = ink_color
	type_ink.a = type_label_alpha
	type_label.add_theme_color_override("font_color", type_ink)
	type_label.add_theme_font_size_override("font_size", type_label_font_size_px)
	if rules_font_bold != null:
		type_label.add_theme_font_override("font", _spaced_bold(type_label_font_size_px, type_label_letter_spacing_em))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func _apply_rules_font_size(font_size: int) -> void:
	rules_text.add_theme_font_size_override("normal_font_size", font_size)
	rules_text.add_theme_font_size_override("bold_font_size", font_size)
	# line_separation is the EXTRA pixels between lines; the font's own
	# line is ~1.0 em, so this puts the total near rules_line_height em.
	rules_text.add_theme_constant_override("line_separation", roundi(float(font_size) * (rules_line_height - 1.0)))

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

func _set_lifted_look(lifted_look: bool) -> void:
	_apply_frame(lifted_look)
	_apply_shadows(lifted_look)

# Type-dependent colour: the keyline and the tonal field. Re-run every
# set_card_data() call.
func _apply_type_style() -> void:
	if card_data == null:
		return
	keyline.color = _keyline_color()
	art_field.add_theme_stylebox_override("panel", _rounded_style(_art_field_color(), art_field_radius))
	glyph.queue_redraw()

# --- Layout ---

# Vertical stack at 1x. The name may wrap to two lines beside the cost;
# the field flexes between the header and the rules text; the rules text
# takes as many lines as it needs up to rules_max_comfortable_lines at
# full size, then the tight size at rules_max_lines with the field held
# at field_min_height. Beyond that, _warn_overlong().
func _apply_layout() -> void:
	shadow_soft.position = Vector2.ZERO
	shadow_soft.size = card_size
	shadow_hairline.position = Vector2.ZERO
	shadow_hairline.size = card_size

	# Keyline inside the frame, inset past the corner radius so it never
	# pokes out of the rounded corners.
	keyline.position = Vector2(float(corner_radius) + 1.0, 1.0)
	keyline.size = Vector2(card_size.x - 2.0 * (float(corner_radius) + 1.0), keyline_height)

	# Cost numeral top-right; the name gets the rest of the header width.
	# Every Label is sized from its font's real line height (Font.get_
	# height()), never an em guess: a Label whose height is under one line
	# draws NO lines at all - Spectral's line box is ~1.4em, so 1.2em of
	# name label rendered nothing.
	var cost_width: float = _string_width(cost_label, cost_font_size_px)
	var cost_height: float = _line_height(cost_label, cost_font_size_px)
	cost_label.position = Vector2(card_size.x - outer_margin - cost_width, outer_margin)
	cost_label.size = Vector2(cost_width, cost_height)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP

	var hp_height: float = 0.0
	if hp_cost_label.visible:
		var hp_width: float = _string_width(hp_cost_label, hp_cost_font_size_px)
		hp_height = _line_height(hp_cost_label, hp_cost_font_size_px)
		hp_cost_label.position = Vector2(card_size.x - outer_margin - hp_width, outer_margin + cost_height)
		hp_cost_label.size = Vector2(hp_width, hp_height)
		hp_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var name_width: float = card_size.x - outer_margin * 2.0 - cost_width - name_cost_gap
	var name_line: float = _line_height(name_label, name_font_size_px)
	var name_lines: int = clampi(_wrapped_line_count(name_label, name_font_size_px, name_width), 1, 2)
	var name_height: float = name_line * float(name_lines)
	name_label.position = Vector2(outer_margin, outer_margin)
	name_label.size = Vector2(name_width, name_height)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true

	var header_bottom: float = outer_margin + maxf(name_height, cost_height + hp_height)

	# Footer: type label at the bottom, the rule above it.
	var type_height: float = _line_height(type_label, type_label_font_size_px)
	type_label.position = Vector2(outer_margin, card_size.y - outer_margin - type_height)
	type_label.size = Vector2(card_size.x - outer_margin * 2.0, type_height)
	footer_rule.position = Vector2(outer_margin, type_label.position.y - footer_rule_gap - 1.0)
	footer_rule.size = Vector2(card_size.x - outer_margin * 2.0, 1.0)
	var footer_top: float = footer_rule.position.y

	# Rules text: how many lines at full size?
	var rules_width: float = card_size.x - outer_margin * 2.0
	var font_size: int = rules_font_size_px
	var lines: int = _rules_line_count(font_size, rules_width)
	if lines > rules_max_comfortable_lines:
		font_size = rules_font_size_tight_px
		lines = _rules_line_count(font_size, rules_width)
		if lines > rules_max_lines:
			_warn_overlong(lines)
	_apply_rules_font_size(font_size)
	var rules_height: float = float(lines) * float(font_size) * rules_line_height

	# The field takes what's left, never less than its minimum - if the
	# text needs more than that leaves, the text wins the space and the
	# field holds at minimum (the rules are the card).
	var field_top: float = header_bottom + header_field_gap
	var available: float = footer_top - rules_footer_gap - field_rules_gap - field_top
	var field_height: float = maxf(available - rules_height, field_min_height)
	art_field.position = Vector2(outer_margin, field_top)
	art_field.size = Vector2(card_size.x - outer_margin * 2.0, field_height)
	glyph.position = Vector2.ZERO
	glyph.size = art_field.size
	glyph.queue_redraw()

	rules_text.position = Vector2(outer_margin, field_top + field_height + field_rules_gap)
	rules_text.size = Vector2(rules_width, maxf(footer_top - rules_footer_gap - rules_text.position.y, rules_height))

func _string_width(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

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

# Measured on the plain description with the regular face (bold runs are
# a touch wider; a card that wraps only because of that is one line from
# the limit anyway).
func _rules_line_count(font_size: int, width: float) -> int:
	if card_data == null or rules_font == null or card_data.description.is_empty():
		return 1
	var line_height: float = rules_font.get_height(font_size)
	var total: float = rules_font.get_multiline_string_size(card_data.description, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, -1, TextServer.BREAK_WORD_BOUND | TextServer.BREAK_MANDATORY).y
	return maxi(roundi(total / maxf(line_height, 1.0)), 1)

func _warn_overlong(lines: int) -> void:
	var card_name: String = card_data.card_name if card_data != null else name
	push_warning("CardView: '%s' rules text runs to %d lines at %dpx - rewrite it shorter." % [card_name, lines, rules_font_size_tight_px])

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
		KeylineType.TOLL:
			glyph.draw_line(centre + Vector2(-r * 0.8, r * 0.9), centre + Vector2(r * 0.8, r * 0.9), faint, w, true)
			glyph.draw_line(centre + Vector2(0.0, r * 0.6), centre + Vector2(0.0, -r * 0.9), ink_color, w, true)
			var head := PackedVector2Array([centre + Vector2(-r * 0.55, -r * 0.35), centre + Vector2(0.0, -r * 0.9), centre + Vector2(r * 0.55, -r * 0.35)])
			glyph.draw_polyline(head, ink_color, w, true)
