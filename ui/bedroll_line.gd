extends InkLine
class_name BedrollLine

# The field HUD's Bedroll, an action bottom-right - things you use live
# there (see HudRowStyle's Bedroll group for every size): its label
# (BedrollData.hud_label, "BEDROLL") in the row's faint caps, under it the
# bedroll's line glyph (InkGlyph BEDROLL) framed by four corner ticks, no
# box, and under that "REST" in full-ink caps over the faint hairline
# that says it can be hovered - each centred on the frame. Its right
# edge is as far in from the screen's as DECK's left edge is from the
# left, its bottom level with the row's. Hidden while none is carried
# (RunState.has_bedroll).
#
# Hovering it shows what a rest does - "Rest: restore 30% of your max
# HP. One use." (BedrollData.hover_name / describe()) - in the battle
# readouts' StatusReveal, just above it, right-aligned (below, with no
# room above). The hover is polled, never a mouse event, as KeepsakeLine's
# is. A left click anywhere on it - label, frame or REST - asks to rest
# (RegionField checks is_point_over() before the click can be a move -
# see open_bedroll_rest()).
#
# RegionField creates it in _setup_field_hud() and sits it on DECK
# (sit_beside() - it follows DECK's margin and goes with the row for a
# fight), hands it the Bedroll's data (bedroll); RunState.bedroll_changed
# keeps it current.

# The hover's sentence: its wrap width, size and the gap to the row.
@export var hover_wrap_px: float = 260.0:
	set(value):
		hover_wrap_px = value
		_sync_reveal()
@export var hover_size_px: int = 15:
	set(value):
		hover_size_px = value
		_sync_reveal()
@export var hover_gap_px: float = 10.0:
	set(value):
		hover_gap_px = value
		_place_reveal()

# Set by RegionField before the line enters the tree.
var bedroll: BedrollData = null

var _held: bool = false
# set_held_off().
var _held_off: bool = false
var _reveal: StatusReveal = null

func _ready() -> void:
	super()
	get_viewport().size_changed.connect(_follow)
	_reveal = StatusReveal.new()
	_reveal.name = "Reveal"
	add_child(_reveal)
	_sync_reveal()
	RunState.bedroll_changed.connect(set_held)
	set_held(RunState.has_bedroll)

func set_held(held: bool) -> void:
	_held = held
	label_text = bedroll.hud_label if bedroll != null else "BEDROLL"
	_relayout()

func is_held() -> bool:
	return _held

# Held off while a screen covers its corner - the collector's, whose
# LEAVE sits there: hidden whatever is carried (a Bedroll bought there
# included), back on release.
func set_held_off(on: bool) -> void:
	if _held_off == on:
		return
	_held_off = on
	_relayout()

func _is_shown() -> bool:
	return _held and not _held_off

# Bottom-right: as far in from the screen's right edge as DECK is from its
# left, bottoms level with the row.
func _position_by(anchor: Control) -> Vector2:
	var screen_width: float = get_viewport_rect().size.x
	return Vector2(screen_width - anchor.position.x - size.x, anchor.position.y + anchor.size.y - size.y)

func _caps_width(text: String) -> float:
	return InkType.width(style.label_font_tracked(), text, style.hud_label_size_px)

func _content_width() -> float:
	return maxf(style.hud_bedroll_frame_px, maxf(_caps_width(label_text), _caps_width(style.hud_bedroll_action_text)))

func _label_baseline() -> float:
	return roundf(style.label_font_tracked().get_ascent(style.hud_label_size_px))

func _frame_rect() -> Rect2:
	var side: float = style.hud_bedroll_frame_px
	var top: float = _label_baseline() + style.hud_bedroll_label_gap_px
	return Rect2(roundf((_content_width() - side) / 2.0), top, side, side)

func _action_baseline() -> float:
	return _frame_rect().end.y + style.hud_bedroll_label_gap_px + _label_baseline()

func _content_height() -> float:
	return _action_baseline() + style.hud_keepsake_hairline_gap_px + style.hud_keepsake_hairline_px

# Whether a screen point is over it - label, frame or REST.
func is_point_over(screen_point: Vector2) -> bool:
	return is_visible_in_tree() and get_global_rect().has_point(screen_point)

# The hover's lines, for probes and the reveal itself.
func get_hover_text() -> String:
	if bedroll == null:
		return ""
	return "%s: %s" % [bedroll.hover_name, bedroll.describe()]

func refresh_style() -> void:
	super()
	if _reveal != null:
		_reveal.set_ink(_ink)

func _sync_reveal() -> void:
	if _reveal == null:
		return
	_reveal.set_ink(_ink)
	_reveal.set_font_size_px(hover_size_px)
	_reveal.set_wrap_width(hover_wrap_px)
	if bedroll != null:
		_reveal.set_lines(PackedStringArray([bedroll.hover_name]), PackedStringArray([bedroll.describe()]))
	_place_reveal()

func _process(_delta: float) -> void:
	if _reveal == null:
		return
	_reveal.set_revealed(is_visible_in_tree() and _is_hovered())
	_place_reveal()

func _is_hovered() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())

# Above it, right edges level - it stands at the screen's right; below
# with no room above.
func _place_reveal() -> void:
	if _reveal == null:
		return
	var above: float = -_reveal.size.y - hover_gap_px
	if is_inside_tree() and get_global_rect().position.y + above < 0.0:
		above = size.y + hover_gap_px
	_reveal.position = Vector2(roundf(size.x - _reveal.size.x), roundf(above))

func _draw() -> void:
	if not _held:
		return
	var font: Font = style.label_font_tracked()
	var size_px: int = style.hud_label_size_px
	var width: float = size.x
	# BEDROLL, faint, centred.
	var label_origin := Vector2(roundf((width - _caps_width(label_text)) / 2.0), _label_baseline())
	style.draw_halo_run(self, font, label_text, label_origin, size_px)
	InkType.draw_run(self, font, label_text, label_origin, size_px, Color(_ink, _ink.a * style.hud_label_alpha))
	# The glyph in its ticks.
	var frame: Rect2 = _frame_rect()
	var glyph_side: float = style.hud_bedroll_glyph_px
	var glyph_rect := Rect2(frame.get_center() - Vector2(glyph_side, glyph_side) / 2.0, Vector2(glyph_side, glyph_side))
	InkGlyph.draw(self, InkGlyph.Kind.BEDROLL, glyph_rect, style.hud_glyph_stroke_px, _ink)
	HudRowStyle.draw_corner_ticks(self, frame, style.hud_bedroll_tick_px, style.hud_slot_tick_stroke_px, _ink)
	# REST, full ink, over the hover hairline.
	var action: String = style.hud_bedroll_action_text
	var action_width: float = _caps_width(action)
	var action_origin := Vector2(roundf((width - action_width) / 2.0), _action_baseline())
	style.draw_halo_run(self, font, action, action_origin, size_px)
	InkType.draw_run(self, font, action, action_origin, size_px, _ink)
	var hairline_top: float = action_origin.y + style.hud_keepsake_hairline_gap_px
	draw_rect(Rect2(action_origin.x, hairline_top, action_width, style.hud_keepsake_hairline_px), Color(_ink, _ink.a * style.hud_keepsake_hairline_alpha))
