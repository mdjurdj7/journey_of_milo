extends RefCounted
class_name InkType

# The battle UI's type, shared by every ink-on-the-world readout (HPBar/
# EnemyStatus's battle style, BattleResources, EndTurnButton, DeckPanel):
# the same vendored faces the cards use, and the one thing Godot's Label/
# draw_string can't express on their own - letter-spacing. A caps label
# ("ENERGY", "TOLL", "DECK", "END TURN") is Alegreya Sans Bold tracked by
# tracking_em of its size; FontVariation.spacing_glyph is whole pixels,
# so 0.16 em rounds to 2 px from 10 px up to 15 px.

const NUMERAL_FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"
const TEXT_FONT_PATH := "res://assets/fonts/AlegreyaSans-Regular.ttf"
const TEXT_BOLD_FONT_PATH := "res://assets/fonts/AlegreyaSans-Bold.ttf"

static func numeral_font() -> Font:
	return load(NUMERAL_FONT_PATH) as Font

static func text_font() -> Font:
	return load(TEXT_FONT_PATH) as Font

static func text_bold_font() -> Font:
	return load(TEXT_BOLD_FONT_PATH) as Font

# A tracked copy of `base` for text drawn at size_px: extra glyph spacing
# of tracking_em x size_px, rounded to whole pixels.
static func tracked(base: Font, size_px: int, tracking_em: float) -> Font:
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.spacing_glyph = roundi(float(size_px) * tracking_em)
	return variation

# Baseline-anchored single-line draw, left-aligned at `origin` (x = left
# edge, y = baseline). Returns the advance width so callers can run text
# on along one baseline.
static func draw_run(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	canvas.draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x

static func width(font: Font, text: String, size_px: int) -> float:
	if font == null or text.is_empty():
		return 0.0
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px).x
