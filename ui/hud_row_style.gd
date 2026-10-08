extends Resource
class_name HudRowStyle

# The field HUD row's one style, shared by every item in it - the field
# DeckPanel (DeckPanel.use_row_style()) and each InkLine - so a Remote-tab
# edit to RegionField.hud_row_style re-lays the whole row at once (every
# setter emits `changed`; each item re-lays and redraws on it).
#
# An item reads, left to right: a glyph (InkGlyph, on the baseline at
# about the numeral's cap height), the numeral in Spectral at full ink, an
# optional secondary run ("/ 70", smaller and grey, as the HP readout's
# max), and a small tracked caps label - ink straight on the world, no
# halo (hud_halo_px 0; a positive value puts a bone halo under every part
# again). Every item is the same
# height (row_height()) with its baseline at row_baseline(), so items
# beside each other share a baseline whatever their content.
#
# Pixel sizes at 1080p.

@export_group("Numeral")
@export var hud_numeral_font: Font = InkType.numeral_font():
	set(value):
		hud_numeral_font = value
		emit_changed()
@export var hud_numeral_size_px: int = 20:
	set(value):
		hud_numeral_size_px = value
		emit_changed()
# The secondary run after the numeral (HP's " / max"): the HP readout's
# battle_max_size_px at its battle_secondary_alpha.
@export var hud_secondary_size_px: int = 14:
	set(value):
		hud_secondary_size_px = value
		emit_changed()
@export_range(0.0, 1.0) var hud_secondary_alpha: float = 0.6:
	set(value):
		hud_secondary_alpha = value
		emit_changed()

@export_group("Label")
@export var hud_show_labels: bool = true:
	set(value):
		hud_show_labels = value
		emit_changed()
@export var hud_label_font: Font = InkType.text_bold_font():
	set(value):
		hud_label_font = value
		_label_font_tracked = null
		emit_changed()
@export var hud_label_size_px: int = 12:
	set(value):
		hud_label_size_px = value
		_label_font_tracked = null
		emit_changed()
# One tracking value for every caps label in the battle UI - see InkType.
@export var hud_label_tracking_em: float = 0.16:
	set(value):
		hud_label_tracking_em = value
		_label_font_tracked = null
		emit_changed()
@export_range(0.0, 1.0) var hud_label_alpha: float = 0.62:
	set(value):
		hud_label_alpha = value
		emit_changed()
# Between the numeral (or its secondary run) and the label.
@export var hud_label_gap_px: float = 5.0:
	set(value):
		hud_label_gap_px = value
		emit_changed()

@export_group("Glyph")
@export var hud_glyph_size_px: float = 14.0:
	set(value):
		hud_glyph_size_px = value
		emit_changed()
@export var hud_glyph_stroke_px: float = 1.5:
	set(value):
		hud_glyph_stroke_px = value
		emit_changed()
# Between the glyph and the numeral.
@export var hud_glyph_gap_px: float = 6.0:
	set(value):
		hud_glyph_gap_px = value
		emit_changed()

@export_group("Halo")
# Px each side of every stroke and glyph, under the ink. 0 (the row's
# default) = none.
@export var hud_halo_px: float = 0.0:
	set(value):
		hud_halo_px = value
		emit_changed()
@export var hud_halo_color: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		hud_halo_color = value
		emit_changed()

@export_group("Spacing")
# Between one item's right edge and the next one's left.
@export var hud_item_gap_px: float = 22.0:
	set(value):
		hud_item_gap_px = value
		emit_changed()
# Before the keepsake, which stands apart from the resources.
@export var hud_keepsake_gap_px: float = 40.0:
	set(value):
		hud_keepsake_gap_px = value
		emit_changed()

@export_group("Keepsake")
# Spectral Regular isn't vendored (Light and SemiBold are) - SemiBold
# reads on the sand; swap here if Regular is added.
@export var hud_keepsake_font: Font = InkType.numeral_font():
	set(value):
		hud_keepsake_font = value
		emit_changed()
@export var hud_keepsake_size_px: int = 17:
	set(value):
		hud_keepsake_size_px = value
		emit_changed()
# The faint rule under the name that says it can be hovered.
@export_range(0.0, 1.0) var hud_keepsake_hairline_alpha: float = 0.35:
	set(value):
		hud_keepsake_hairline_alpha = value
		emit_changed()
@export var hud_keepsake_hairline_px: float = 1.0:
	set(value):
		hud_keepsake_hairline_px = value
		emit_changed()
# From the name's baseline down to the hairline's top.
@export var hud_keepsake_hairline_gap_px: float = 3.0:
	set(value):
		hud_keepsake_hairline_gap_px = value
		emit_changed()
# The art thumbnail before the name: this square, cropped square from
# the art (or the placeholder's tone), a thin ink edge round it, this far
# before the name.
@export var hud_keepsake_thumb_px: float = 24.0:
	set(value):
		hud_keepsake_thumb_px = value
		emit_changed()
@export var hud_keepsake_thumb_gap_px: float = 7.0:
	set(value):
		hud_keepsake_thumb_gap_px = value
		emit_changed()
@export var hud_keepsake_thumb_edge_px: float = 1.0:
	set(value):
		hud_keepsake_thumb_edge_px = value
		emit_changed()
@export var hud_keepsake_thumb_placeholder: Color = Color(0.80, 0.77, 0.71, 1.0):
	set(value):
		hud_keepsake_thumb_placeholder = value
		emit_changed()
# The hover: the KeepsakeTile at this scale, this far above the row (below
# it when there is no room above), fading in and out over this long.
@export var hud_keepsake_tile_scale: float = 1.0:
	set(value):
		hud_keepsake_tile_scale = value
		emit_changed()
@export var hud_keepsake_tile_gap_px: float = 12.0:
	set(value):
		hud_keepsake_tile_gap_px = value
		emit_changed()
@export var hud_keepsake_tile_fade_sec: float = 0.12:
	set(value):
		hud_keepsake_tile_fade_sec = value
		emit_changed()

@export_group("Count")
# Seconds for a numeral to count from its old value to a new one, one
# ease-out, either way - never on a floor load (that shows the value at
# once). An edit mid-count re-times the running count from where it
# stands.
@export var hud_count_sec: float = 0.35:
	set(value):
		hud_count_sec = value
		emit_changed()

@export_group("Backing")
# A soft ink fade behind the row, strongest at the screen's bottom-left
# corner and gone by backing_size_px's right and top - a contrast
# fallback, off by default; drawn by the field DeckPanel.
@export_range(0.0, 1.0) var hud_backing_alpha: float = 0.0:
	set(value):
		hud_backing_alpha = value
		emit_changed()
@export var hud_backing_size_px: Vector2 = Vector2(620.0, 130.0):
	set(value):
		hud_backing_size_px = value
		emit_changed()
@export_group("")

var _label_font_tracked: Font = null

func label_font_tracked() -> Font:
	if _label_font_tracked == null:
		_label_font_tracked = InkType.tracked(hud_label_font, hud_label_size_px, hud_label_tracking_em)
	return _label_font_tracked

func _halo() -> float:
	return maxf(hud_halo_px, 0.0)

func row_baseline() -> float:
	var ascent: float = hud_numeral_font.get_ascent(hud_numeral_size_px) if hud_numeral_font != null else float(hud_numeral_size_px)
	return roundf(_halo() + ascent)

func row_height() -> float:
	var descent: float = hud_numeral_font.get_descent(hud_numeral_size_px) if hud_numeral_font != null else 0.0
	return roundf(row_baseline() + descent + _halo())

# The width of one resource item: glyph (unless NONE), numeral, secondary
# run, label (unless hidden or empty).
func item_width(glyph: InkGlyph.Kind, numeral: String, secondary: String, label: String) -> float:
	var width: float = 0.0
	if glyph != InkGlyph.Kind.NONE:
		width += hud_glyph_size_px + hud_glyph_gap_px
	width += InkType.width(hud_numeral_font, numeral, hud_numeral_size_px)
	width += InkType.width(hud_numeral_font, secondary, hud_secondary_size_px)
	if hud_show_labels and not label.is_empty():
		width += hud_label_gap_px + InkType.width(label_font_tracked(), label, hud_label_size_px)
	return width

# Draws one resource item at the canvas's origin: the halo under every
# part first, then the ink - so no part's halo covers a neighbour's ink.
func draw_item(canvas: CanvasItem, ink: Color, glyph: InkGlyph.Kind, numeral: String, secondary: String, label: String) -> void:
	var baseline: float = row_baseline()
	var halo_size: int = roundi(_halo() * 2.0)
	for pass_index in 2:
		var is_halo: bool = pass_index == 0
		if is_halo and halo_size <= 0:
			continue
		var x: float = 0.0
		if glyph != InkGlyph.Kind.NONE:
			var rect := Rect2(x, baseline - hud_glyph_size_px, hud_glyph_size_px, hud_glyph_size_px)
			if is_halo:
				InkGlyph.draw(canvas, glyph, rect, hud_glyph_stroke_px + _halo() * 2.0, hud_halo_color)
			else:
				InkGlyph.draw(canvas, glyph, rect, hud_glyph_stroke_px, ink)
			x += hud_glyph_size_px + hud_glyph_gap_px
		x += _run(canvas, is_halo, halo_size, hud_numeral_font, numeral, x, baseline, hud_numeral_size_px, ink)
		x += _run(canvas, is_halo, halo_size, hud_numeral_font, secondary, x, baseline, hud_secondary_size_px, Color(ink, ink.a * hud_secondary_alpha))
		if hud_show_labels and not label.is_empty():
			x += hud_label_gap_px
			_run(canvas, is_halo, halo_size, label_font_tracked(), label, x, baseline, hud_label_size_px, Color(ink, ink.a * hud_label_alpha))

# One text run's halo alone, baseline-anchored at `origin` - for text
# outside the item shape (the keepsake's name and description).
func draw_halo_run(canvas: CanvasItem, font: Font, text: String, origin: Vector2, size_px: int) -> void:
	var halo_size: int = roundi(_halo() * 2.0)
	if font == null or text.is_empty() or halo_size <= 0:
		return
	canvas.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, halo_size, hud_halo_color)

# One text run's halo or ink; returns its advance.
func _run(canvas: CanvasItem, is_halo: bool, halo_size: int, font: Font, text: String, x: float, baseline: float, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	if is_halo:
		canvas.draw_string_outline(font, Vector2(x, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, halo_size, hud_halo_color)
		return InkType.width(font, text, size_px)
	return InkType.draw_run(canvas, font, text, Vector2(x, baseline), size_px, color)
