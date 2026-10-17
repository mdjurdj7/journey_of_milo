extends InkLine
class_name BedrollLine

# The field HUD row's Bedroll: its label alone (BedrollData.hud_label,
# "BEDROLL") in the row's tracked caps at full ink, with the keepsake
# name's faint hairline under it that says it can be hovered - after
# GLASSBONE, the last of the resources, before the keepsake's wider gap
# (see InkLine for the following). Hidden while none is carried
# (RunState.has_bedroll); the keepsake then sits beside GLASSBONE, or
# GOLD, as before.
#
# Hovering it shows what a rest does - "Rest: restore 30% of your max
# HP. One use." (BedrollData.hover_name / describe()) - in the battle
# readouts' StatusReveal, just above the row (below, with no room above).
# The hover is polled, never a mouse event, as KeepsakeLine's is. A left
# click on it asks to rest (RegionField checks is_point_over() before the
# click can be a move - see open_bedroll_rest()).
#
# RegionField creates it in _setup_field_hud() and hands it the
# GLASSBONE line (sit_beside()) and the Bedroll's data (bedroll);
# RunState.bedroll_changed keeps it current.

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
var _reveal: StatusReveal = null

func _ready() -> void:
	super()
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

func _is_shown() -> bool:
	return _held

# The label at full ink - it is the item, not a numeral's caption.
func _content_width() -> float:
	return InkType.width(style.label_font_tracked(), label_text, style.hud_label_size_px)

# Whether a screen point is over the label.
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

# Above the row, left-aligned with the label; below with no room above.
func _place_reveal() -> void:
	if _reveal == null:
		return
	var above: float = -_reveal.size.y - hover_gap_px
	if is_inside_tree() and get_global_rect().position.y + above < 0.0:
		above = size.y + hover_gap_px
	_reveal.position = Vector2(0.0, roundf(above))

func _draw() -> void:
	if not _held:
		return
	var font: Font = style.label_font_tracked()
	var size_px: int = style.hud_label_size_px
	var baseline: float = style.row_baseline()
	var width: float = InkType.width(font, label_text, size_px)
	var hairline_top: float = baseline + style.hud_keepsake_hairline_gap_px
	var halo: float = maxf(style.hud_halo_px, 0.0)
	if halo > 0.0:
		style.draw_halo_run(self, font, label_text, Vector2(0.0, baseline), size_px)
	InkType.draw_run(self, font, label_text, Vector2(0.0, baseline), size_px, _ink)
	draw_rect(Rect2(0.0, hairline_top, width, style.hud_keepsake_hairline_px), Color(_ink, _ink.a * style.hud_keepsake_hairline_alpha))
