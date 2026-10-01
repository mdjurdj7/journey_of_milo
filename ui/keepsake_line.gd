extends InkLine
class_name KeepsakeLine

# The field HUD's keepsake: "KEEPSAKE name" as a line of ink beside the
# GOLD line (see InkLine for the shape, the style and the following).
# Hidden while the slot is empty. No icon, no box, no rarity colour.
#
# Hovering it reveals what the keepsake does - TrinketData.describe(),
# through the same StatusReveal the battle readouts use, drawn above the
# line (it sits at the screen's foot). The hover is polled, never a mouse
# event, so the click under it still moves the Wanderer; a Control under
# the cursor wins, as on HPBar.
#
# RegionField creates it in _setup_field_hud() and hands it the GOLD line
# (sit_beside()); RunState.keepsake_changed keeps it current.

@export_group("Reveal")
@export var reveal_fade_time: float = 0.12:
	set(value):
		reveal_fade_time = value
		if _reveal != null:
			_reveal.set_fade_time(value)
@export_range(0.0, 1.0) var reveal_line_alpha: float = 0.92:
	set(value):
		reveal_line_alpha = value
		if _reveal != null:
			_reveal.set_line_alpha(value)
@export var reveal_font_size_px: int = 13:
	set(value):
		reveal_font_size_px = value
		if _reveal != null:
			_reveal.set_font_size_px(value)
# Line pitch in ems, as CardView.rules_line_height.
@export var reveal_line_height: float = 1.28:
	set(value):
		reveal_line_height = value
		if _reveal != null:
			_reveal.set_line_height(value)
@export var reveal_wrap_width_px: float = 240.0:
	set(value):
		reveal_wrap_width_px = value
		if _reveal != null:
			_reveal.set_wrap_width(value)
# Between the reveal's last line and the top of this line.
@export var reveal_gap_px: float = 8.0
@export_group("")

var _keepsake: TrinketData = null
var _reveal: StatusReveal = null

func _init() -> void:
	label_text = "KEEPSAKE"

func _ready() -> void:
	super()
	_reveal = StatusReveal.new()
	_reveal.name = "StatusReveal"
	_reveal.set_fade_time(reveal_fade_time)
	_reveal.set_line_alpha(reveal_line_alpha)
	_reveal.set_font_size_px(reveal_font_size_px)
	_reveal.set_line_height(reveal_line_height)
	_reveal.set_wrap_width(reveal_wrap_width_px)
	_reveal.set_ink(_ink)
	add_child(_reveal)
	RunState.keepsake_changed.connect(set_keepsake)
	set_keepsake(RunState.keepsake)

func set_keepsake(keepsake: TrinketData) -> void:
	_keepsake = keepsake
	if _reveal != null:
		if keepsake != null:
			_reveal.set_lines(PackedStringArray([keepsake.display_name]), PackedStringArray([keepsake.describe()]))
		else:
			_reveal.clear()
	set_value_text(keepsake.display_name if keepsake != null else "")

func refresh_style() -> void:
	super()
	if _reveal != null:
		_reveal.set_ink(_ink)

func _is_shown() -> bool:
	return _keepsake != null

func _process(_delta: float) -> void:
	if _reveal == null:
		return
	_reveal.position = Vector2(0.0, -_reveal.size.y - reveal_gap_px)
	_reveal.set_revealed(is_visible_in_tree() and _is_hovered())

func _is_hovered() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position())
