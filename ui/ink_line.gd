extends Control
class_name InkLine

# One item of the field HUD row, after the DeckPanel's DECK: a glyph, a
# numeral in Spectral at full ink, an optional secondary run and a small
# caps label, over a bone halo - the shape and every size, gap and alpha
# come from the row's shared HudRowStyle (see its own doc). Drawn, not
# boxed; sized to its own content. The base of HPLine, TollLine,
# GoldLine, GlassboneLine and KeepsakeLine - the row's order after DECK,
# the keepsake set apart at the end; a subclass sets its glyph and label
# and feeds its value through set_value_text().
#
# RegionField creates each in _setup_field_hud(), hands it the row's
# style (set_style()) and the item to sit beside (sit_beside()). It
# follows that item's rect and its visibility, so it goes when
# BattleOverlay hides the field row for a fight and comes back with it -
# and a subclass can keep itself hidden on top of that (_is_shown()).
#
# Reads the theme's Battle/ink token, so it inverts with the on-pale/
# on-dark value set (see BattleTheme) - re-read via refresh_style().

# This line has just re-followed the line it sits beside - so a line
# sitting beside THIS one re-follows too, even when nothing about this one
# changed (a hidden GLASSBONE staying hidden as the row goes for a fight).
signal followed()

@export var label_text: String = "":
	set(value):
		label_text = value
		_relayout()
@export var glyph: InkGlyph.Kind = InkGlyph.Kind.NONE:
	set(value):
		glyph = value
		_relayout()

# The row's shared style - a default of its own until RegionField hands
# over the row's (set_style()).
var style: HudRowStyle = HudRowStyle.new()

var _value_text: String = ""
var _secondary_text: String = ""
var _ink: Color = Color.BLACK
var _beside: Control = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not style.changed.is_connected(_relayout):
		style.changed.connect(_relayout)
	refresh_style()

func set_style(row_style: HudRowStyle) -> void:
	if style.changed.is_connected(_relayout):
		style.changed.disconnect(_relayout)
	style = row_style
	style.changed.connect(_relayout)
	_relayout()

func set_value_text(text: String) -> void:
	_value_text = text
	_relayout()

# Sits this line to the right of `line`, bottoms (and so baselines) level,
# and keeps it there as that line resizes or moves - and shown only while
# it is.
func sit_beside(line: Control) -> void:
	if _beside != null:
		_beside.item_rect_changed.disconnect(_follow)
		_beside.visibility_changed.disconnect(_follow)
		if _beside is InkLine:
			(_beside as InkLine).followed.disconnect(_follow)
	_beside = line
	_beside.item_rect_changed.connect(_follow)
	_beside.visibility_changed.connect(_follow)
	if _beside is InkLine:
		(_beside as InkLine).followed.connect(_follow)
	_follow()

# Re-reads the theme's ink - called at _ready() and by RegionField right
# after it applies this region's value set to the shared BattleTheme.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_relayout()

# Whether this line has anything to show, beside its line's own
# visibility. Always, unless a subclass says otherwise.
func _is_shown() -> bool:
	return true

# The space between the item this one sits beside and this one.
func _gap_before() -> float:
	return style.hud_item_gap_px

func _content_width() -> float:
	return style.item_width(glyph, _value_text, _secondary_text, label_text)

func _relayout() -> void:
	if not is_inside_tree():
		return
	size = Vector2(_content_width(), style.row_height())
	_follow()
	queue_redraw()

func _follow() -> void:
	if _beside == null or not is_instance_valid(_beside):
		return
	# A line that has hidden itself (_is_shown() false - GLASSBONE before
	# the first piece, KEEPSAKE with an empty slot) gives up its place:
	# this one sits where it would have, beside whatever it sits beside.
	# A line hidden with the whole field row for a fight still takes this
	# one with it.
	var anchor: Control = _beside
	while anchor is InkLine and not (anchor as InkLine)._is_shown():
		var next: Control = (anchor as InkLine)._beside
		if next == null or not is_instance_valid(next):
			break
		anchor = next
	visible = anchor.visible and _is_shown()
	# Every row item is style.row_height() tall with its baseline at the
	# same depth, so level bottoms are level baselines.
	position = Vector2(anchor.position.x + anchor.size.x + _gap_before(), anchor.position.y + anchor.size.y - size.y)
	followed.emit()

func _draw() -> void:
	style.draw_item(self, _ink, glyph, _value_text, _secondary_text, label_text)
