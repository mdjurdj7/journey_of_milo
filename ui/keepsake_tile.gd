extends Control
class_name KeepsakeTile

# One keepsake, shown the one way it is shown everywhere: a bone tile on
# the card's paper (card_paper_material) with a thin charcoal frame and a
# soft shadow - no cost, no type keyline, no rarity. Top to bottom:
#   the object   TrinketData.art in a square window - or, with no art, a
#                flat tone panel with the name's initial: a placeholder,
#                and plainly one
#   its name     Spectral SemiBold, centred
#   what it does TrinketData.describe(), Alegreya Sans, centred, stepped
#                down through rules_sizes_px until everything fits
#   its lore     TrinketData.flavor_text in a slanted Spectral, grey, under
#                a hairline - both left out when it has none
#
# Drawn at tile_scale, not scaled: every size and gap is multiplied out
# and the text set at its scaled size, so a 2x tile (the examine view) is
# as crisp as a 1x one. size follows tile_size x tile_scale. The hosts -
# the HUD hover, KeepsakeExamine, KeepsakeOffer, BelongingsScreen, the
# Keeper's WorldKeepsake, the battle row's hover - place it and decide
# what a click on it does; the tile itself ignores the mouse.

const PAPER_MATERIAL_PATH := "res://battle/card_paper_material.tres"
const LORE_FONT_PATH := "res://assets/fonts/Spectral-Light.ttf"

@export var tile_size: Vector2 = Vector2(240.0, 260.0):
	set(value):
		tile_size = value
		_relayout()
@export var tile_scale: float = 1.0:
	set(value):
		tile_scale = maxf(value, 0.1)
		_relayout()

@export_group("Look")
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_redraw()
@export var corner_radius_px: int = 6:
	set(value):
		corner_radius_px = value
		_relayout()
@export_range(0.0, 1.0) var frame_alpha: float = 0.85:
	set(value):
		frame_alpha = value
		_redraw()
@export var shadow_size_px: int = 12:
	set(value):
		shadow_size_px = value
		_relayout()
@export_range(0.0, 1.0) var shadow_alpha: float = 0.2:
	set(value):
		shadow_alpha = value
		_relayout()
@export var shadow_offset_px: float = 4.0:
	set(value):
		shadow_offset_px = value
		_relayout()
@export var padding_px: float = 14.0:
	set(value):
		padding_px = value
		_relayout()
@export_range(0.0, 1.0) var hairline_alpha: float = 0.35:
	set(value):
		hairline_alpha = value
		_redraw()
@export_group("")

@export_group("Art")
@export var art_size_px: float = 96.0:
	set(value):
		art_size_px = value
		_relayout()
# The placeholder: this tone, and the name's initial on it at
# placeholder_initial_alpha of ink.
@export var placeholder_color: Color = Color(0.80, 0.77, 0.71, 1.0):
	set(value):
		placeholder_color = value
		_redraw()
@export var placeholder_initial_size_px: int = 48:
	set(value):
		placeholder_initial_size_px = value
		_redraw()
@export_range(0.0, 1.0) var placeholder_initial_alpha: float = 0.45:
	set(value):
		placeholder_initial_alpha = value
		_redraw()
@export_group("")

@export_group("Text")
@export var name_size_px: int = 19:
	set(value):
		name_size_px = value
		_relayout()
@export var name_gap_px: float = 10.0:
	set(value):
		name_gap_px = value
		_relayout()
# Tried largest first; the first that fits the tile wins.
@export var rules_sizes_px: PackedInt32Array = PackedInt32Array([14, 13, 12, 11]):
	set(value):
		rules_sizes_px = value
		_relayout()
@export var rules_gap_px: float = 8.0:
	set(value):
		rules_gap_px = value
		_relayout()
@export var lore_size_px: int = 13:
	set(value):
		lore_size_px = value
		_relayout()
@export_range(0.0, 1.0) var lore_alpha: float = 0.6:
	set(value):
		lore_alpha = value
		_redraw()
@export var lore_slant: float = 0.18:
	set(value):
		lore_slant = value
		_lore_font = null
		_relayout()
# Between the rules and the hairline, and the hairline and the lore.
@export var lore_gap_px: float = 8.0:
	set(value):
		lore_gap_px = value
		_relayout()
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_relayout()
@export_group("")

var _keepsake: TrinketData = null
var _shadow: Panel = null
var _paper: Control = null
var _face: Control = null
var _paper_seed: float = 0.0
var _lore_font: Font = null
# Held: a TextParagraph keeps only its fonts' RIDs, and a font nothing
# else holds is freed before the paragraph shapes.
var _rules_font: Font = null
# Laid out, in scaled pixels.
var _art_rect: Rect2 = Rect2()
var _name_baseline: float = 0.0
var _rules: TextParagraph = null
var _rules_size: int = 14
var _rules_top: float = 0.0
var _lore: TextParagraph = null
var _hairline_y: float = 0.0
var _lore_top: float = 0.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow = Panel.new()
	_shadow.name = "Shadow"
	_shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shadow)
	_paper = Control.new()
	_paper.name = "Paper"
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paper.material = load(PAPER_MATERIAL_PATH) as Material
	_paper.draw.connect(_draw_paper)
	add_child(_paper)
	_face = Control.new()
	_face.name = "Face"
	_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The art is drawn well under its size, like a card's.
	_face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_face.draw.connect(_draw_face)
	add_child(_face)

func _ready() -> void:
	_relayout()

func set_keepsake(keepsake: TrinketData) -> void:
	_keepsake = keepsake
	# The paper's grain from the keepsake's id: the same tile wherever it
	# is shown, and no draw on the global generator a run's shuffles use.
	_paper_seed = float(absi(hash(keepsake.id)) % 1000) / 1000.0 if keepsake != null else 0.0
	_relayout()

func get_keepsake() -> TrinketData:
	return _keepsake

# The tile's size on screen: tile_size at tile_scale.
func get_tile_size() -> Vector2:
	return (tile_size * tile_scale).round()

# The rules size the text settled on (for probes and the fit check).
func get_rules_size_px() -> int:
	return _rules_size

# Whether everything fits inside the tile at the size it settled on.
func fits() -> bool:
	return _content_bottom() <= get_tile_size().y - padding_px * tile_scale + 0.5

func uses_placeholder() -> bool:
	return _keepsake != null and _keepsake.art == null

# --- Layout ---

func _px(value: float) -> float:
	return value * tile_scale

func _font_px(value: int) -> int:
	return maxi(roundi(float(value) * tile_scale), 1)

func _pitch(font_px: int) -> float:
	return roundf(float(font_px) * line_pitch_em)

func _relayout() -> void:
	if _face == null:
		return
	var tile: Vector2 = get_tile_size()
	size = tile
	custom_minimum_size = tile
	for child: Control in [_shadow, _paper, _face]:
		child.position = Vector2.ZERO
		child.size = tile
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.94, 0.91, 0.86, 0.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	style.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	style.shadow_size = roundi(_px(shadow_size_px))
	style.shadow_offset = Vector2(0.0, _px(shadow_offset_px))
	_shadow.add_theme_stylebox_override("panel", style)
	if _rules_font == null:
		_rules_font = InkType.text_font()
	if _lore_font == null:
		var slanted := FontVariation.new()
		slanted.base_font = load(LORE_FONT_PATH) as Font
		# x_axis.y is the slant (FontVariation.variation_transform's doc).
		slanted.variation_transform = Transform2D(Vector2(1.0, lore_slant), Vector2(0.0, 1.0), Vector2.ZERO)
		_lore_font = slanted
	var art: float = roundf(_px(art_size_px))
	_art_rect = Rect2(roundf((tile.x - art) / 2.0), roundf(_px(padding_px)), art, art)
	var name_px: int = _font_px(name_size_px)
	_name_baseline = roundf(_art_rect.end.y + _px(name_gap_px) + InkType.numeral_font().get_ascent(name_px))
	_rules_top = _name_baseline + InkType.numeral_font().get_descent(name_px) + _px(rules_gap_px)
	var text_width: float = tile.x - _px(padding_px) * 2.0
	_lore = null
	if _keepsake != null and not _keepsake.flavor_text.is_empty():
		_lore = TextParagraph.new()
		_lore.width = text_width
		_lore.add_string(_keepsake.flavor_text, _lore_font, _font_px(lore_size_px))
	# The largest rules size at which everything fits; the smallest if none.
	var sizes: PackedInt32Array = rules_sizes_px if not rules_sizes_px.is_empty() else PackedInt32Array([14])
	for i in sizes.size():
		_rules_size = sizes[i]
		_rules = TextParagraph.new()
		_rules.width = text_width
		_rules.add_string(_keepsake.describe() if _keepsake != null else "", _rules_font, _font_px(_rules_size))
		_place_lore()
		if fits():
			break
	queue_redraw()
	_redraw()

func _place_lore() -> void:
	var rules_bottom: float = _rules_top + _pitch(_font_px(_rules_size)) * float(_rules.get_line_count())
	_hairline_y = roundf(rules_bottom + _px(lore_gap_px))
	_lore_top = _hairline_y + _px(lore_gap_px)

func _content_bottom() -> float:
	if _rules == null:
		return 0.0
	if _lore == null:
		return _rules_top + _pitch(_font_px(_rules_size)) * float(_rules.get_line_count())
	return _lore_top + _pitch(_font_px(lore_size_px)) * float(_lore.get_line_count())

# --- Draw ---

func _redraw() -> void:
	if _paper != null:
		_paper.queue_redraw()
	if _face != null:
		_face.queue_redraw()

func _draw_paper() -> void:
	# The card's own trick: the paper shader reads its seed from red.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(_paper_seed, 0.0, 0.0, 1.0)
	style.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_paper.draw_style_box(style, Rect2(Vector2.ZERO, get_tile_size()))

func _draw_face() -> void:
	var tile: Vector2 = get_tile_size()
	var frame := StyleBoxFlat.new()
	frame.draw_center = false
	frame.set_border_width_all(maxi(roundi(tile_scale), 1))
	frame.border_color = Color(ink, frame_alpha)
	frame.set_corner_radius_all(roundi(_px(corner_radius_px)))
	_face.draw_style_box(frame, Rect2(Vector2.ZERO, tile))
	if _keepsake == null:
		return
	if _keepsake.art != null:
		_face.draw_texture_rect(_keepsake.art, _art_rect, false)
	else:
		_face.draw_rect(_art_rect, placeholder_color)
		var initial: String = _keepsake.display_name.left(1).to_upper()
		var initial_px: int = _font_px(placeholder_initial_size_px)
		var font: Font = InkType.numeral_font()
		var width: float = InkType.width(font, initial, initial_px)
		var baseline: float = _art_rect.get_center().y + (font.get_ascent(initial_px) - font.get_descent(initial_px)) * 0.5
		InkType.draw_run(_face, font, initial, Vector2(roundf(_art_rect.get_center().x - width / 2.0), roundf(baseline)), initial_px, Color(ink, placeholder_initial_alpha))
	var name_px: int = _font_px(name_size_px)
	var name_width: float = InkType.width(InkType.numeral_font(), _keepsake.display_name, name_px)
	InkType.draw_run(_face, InkType.numeral_font(), _keepsake.display_name, Vector2(roundf((tile.x - name_width) / 2.0), _name_baseline), name_px, ink)
	_draw_paragraph(_rules, _rules_top, _pitch(_font_px(_rules_size)), ink)
	if _lore != null:
		var hairline_width: float = roundf(tile.x * 0.3)
		_face.draw_rect(Rect2(roundf((tile.x - hairline_width) / 2.0), _hairline_y, hairline_width, maxf(roundf(tile_scale), 1.0)), Color(ink, hairline_alpha))
		_draw_paragraph(_lore, _lore_top, _pitch(_font_px(lore_size_px)), Color(ink, lore_alpha))

# A paragraph line by line at a fixed pitch, each line centred in the
# tile's text width.
func _draw_paragraph(paragraph: TextParagraph, top: float, pitch: float, color: Color) -> void:
	if paragraph == null:
		return
	var left: float = _px(padding_px)
	var y: float = top
	for line in paragraph.get_line_count():
		var line_left: float = left + roundf((paragraph.width - paragraph.get_line_width(line)) / 2.0)
		var baseline_shift: float = pitch - paragraph.get_line_ascent(line) - paragraph.get_line_descent(line)
		paragraph.draw_line(_face.get_canvas_item(), Vector2(line_left, roundf(y + baseline_shift * 0.5)), line, color)
		y += pitch
