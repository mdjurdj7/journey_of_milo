extends InkLine
class_name KeepsakeLine

# The field HUD row's keepsake: its name alone, in Spectral at
# hud_keepsake_size_px, full ink over the bone halo, with a faint ink
# hairline under it that says it can be hovered - set apart at the end of
# the row by hud_keepsake_gap_px, after GOLD and GLASSBONE (see InkLine
# for the following, HudRowStyle for every size). No label, no icon, no
# rarity colour. Hidden while the slot is empty.
#
# Hovering the name shows what the keepsake does - TrinketData.describe()
# alone, no name repeated - just above it, in the keepsake offer screen's
# face (Alegreya Sans Regular, ink) over the halo, no backing; it fades
# out on mouse-out. The hover is polled, never a mouse event, so the click
# under it still moves the Wanderer; a Control under the cursor wins, as
# on HPBar.
#
# RegionField creates it in _setup_field_hud() and hands it the
# GLASSBONE line (sit_beside() - beside GOLD while GLASSBONE is hidden);
# RunState.keepsake_changed keeps it current.

var _keepsake: TrinketData = null
var _description: TextParagraph = null
# The description's share of full ink, 0..1, eased toward the hover.
var _reveal_alpha: float = 0.0

func _ready() -> void:
	super()
	RunState.keepsake_changed.connect(set_keepsake)
	set_keepsake(RunState.keepsake)

func set_keepsake(keepsake: TrinketData) -> void:
	_keepsake = keepsake
	set_value_text(keepsake.display_name if keepsake != null else "")

func _is_shown() -> bool:
	return _keepsake != null

func _gap_before() -> float:
	return style.hud_keepsake_gap_px

func _content_width() -> float:
	return InkType.width(style.hud_keepsake_font, _value_text, style.hud_keepsake_size_px)

func _relayout() -> void:
	_description = null
	super()

# Built lazily (it wraps to the style's width in its font), dropped on
# any relayout - a new keepsake or a style edit.
func _description_paragraph() -> TextParagraph:
	if _description == null and _keepsake != null:
		_description = TextParagraph.new()
		_description.width = style.hud_description_wrap_px
		_description.add_string(_keepsake.describe(), style.hud_description_font, style.hud_description_size_px)
	return _description

func _process(delta: float) -> void:
	var target: float = 1.0 if is_visible_in_tree() and _is_hovered() else 0.0
	if is_equal_approx(_reveal_alpha, target):
		return
	var fade: float = style.hud_description_fade_sec
	_reveal_alpha = target if fade <= 0.0 else move_toward(_reveal_alpha, target, delta / fade)
	queue_redraw()

func _is_hovered() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())

func _draw() -> void:
	if _value_text.is_empty():
		return
	var baseline: float = style.row_baseline()
	var name_font: Font = style.hud_keepsake_font
	var name_size: int = style.hud_keepsake_size_px
	var width: float = _content_width()
	var hairline_top: float = baseline + style.hud_keepsake_hairline_gap_px
	var halo: float = maxf(style.hud_halo_px, 0.0)
	if halo > 0.0:
		style.draw_halo_run(self, name_font, _value_text, Vector2(0.0, baseline), name_size)
		draw_rect(Rect2(-halo, hairline_top - halo, width + halo * 2.0, style.hud_keepsake_hairline_px + halo * 2.0), Color(style.hud_halo_color, style.hud_halo_color.a * style.hud_keepsake_hairline_alpha))
	InkType.draw_run(self, name_font, _value_text, Vector2(0.0, baseline), name_size, _ink)
	draw_rect(Rect2(0.0, hairline_top, width, style.hud_keepsake_hairline_px), Color(_ink, _ink.a * style.hud_keepsake_hairline_alpha))
	if _reveal_alpha > 0.0:
		_draw_description(baseline - name_font.get_ascent(name_size) - style.hud_description_gap_px)

# The description's lines, left-aligned with the name, its last line's
# descent at `bottom`: the halo under every line first, then the ink.
func _draw_description(bottom: float) -> void:
	var paragraph: TextParagraph = _description_paragraph()
	if paragraph == null:
		return
	var pitch: float = roundf(float(style.hud_description_size_px) * style.hud_description_line_height)
	var count: int = paragraph.get_line_count()
	var last_descent: float = paragraph.get_line_descent(count - 1) if count > 0 else 0.0
	var first_baseline: float = bottom - last_descent - pitch * float(count - 1)
	var halo_size: int = roundi(maxf(style.hud_halo_px, 0.0) * 2.0)
	var halo_color := Color(style.hud_halo_color, style.hud_halo_color.a * _reveal_alpha)
	var ink := Color(_ink, _ink.a * _reveal_alpha)
	for pass_index in 2:
		if pass_index == 0 and halo_size <= 0:
			continue
		for line_index in count:
			var top_left := Vector2(0.0, first_baseline + pitch * float(line_index) - paragraph.get_line_ascent(line_index))
			if pass_index == 0:
				paragraph.draw_line_outline(get_canvas_item(), top_left, line_index, halo_size, halo_color)
			else:
				paragraph.draw_line(get_canvas_item(), top_left, line_index, ink)
