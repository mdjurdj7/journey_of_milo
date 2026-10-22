extends Control
class_name SheatheButton

# Sheathe (BattleController.sheathe()) on the battle overlay, in Devour's
# place and voice (DevourButton): over the energy readout, its left edge on
# the corner margin (BattleOverlay._apply_energy_anchor()). A line-drawn
# sheathed blade on the left - the scabbard rising to the right, the guard
# across it and the hilt below - in the intent glyphs' tapered pen
# (InkPen), and stacked to its right "SHEATHE" in tracked caps, detail_text
# in the HP readout's smaller grey numeral, and, while it can't be used,
# why - "USED" or "NO ENERGY" - in caps in full ink.
#
# States, all read from the controller on sheathe_changed:
# - Ink (unused this turn and its Energy in hand): glyph, label and detail
#   in full ink - through the moments a play or the enemy turn holds it,
#   so it doesn't flicker. Clickable only while available: a click opens
#   the controller's pick (a hand card to keep), a second closes it.
# - Unavailable (used this turn, or its Energy short): ink eases to
#   grey_alpha over lit_fade_sec, and the reason shows under the detail.
# - Lit (the pick open): a hairline draws in under the label over
#   rule_draw_sec, and the hilt and guard draw out of the scabbard by
#   draw_out_px, eased; the line over the stack reads pick_text.
# - Unlit (closed, or a card sheathed): eased back - on a sheathe, home
#   over sheathe_snap_sec.
#
# Left-click calls sheathe(); every other button passes through
# (MOUSE_FILTER_PASS, not accepted), so a right-click still cancels the
# pick. Pixel sizes at 1080p.

@export_group("Glyph")
# The blade's inked height - Devour's jaw's, so the slot keeps its size.
@export var glyph_height_px: float = 40.0:
	set(value):
		glyph_height_px = value
		_relayout()
@export_range(0.5, 3.0) var glyph_width_ratio: float = 1.25:
	set(value):
		glyph_width_ratio = value
		_relayout()
# The pen: the scabbard this wide, narrowing to glyph_taper of it at its
# tip (InkPen.ribbon()); the hilt hilt_stroke_ratio of it.
@export var glyph_stroke_px: float = 3.2:
	set(value):
		glyph_stroke_px = value
		queue_redraw()
@export_range(0.0, 1.0) var glyph_taper: float = 0.15:
	set(value):
		glyph_taper = value
		queue_redraw()
@export_range(0.2, 1.5) var hilt_stroke_ratio: float = 0.8:
	set(value):
		hilt_stroke_ratio = value
		queue_redraw()
@export var glyph_outline_px: float = 0.0:
	set(value):
		glyph_outline_px = value
		queue_redraw()
@export var glyph_edge_px: float = 1.0:
	set(value):
		glyph_edge_px = value
		queue_redraw()
# Lit, the hilt and guard come this far out along the blade, over
# draw_out_sec.
@export var draw_out_px: float = 4.0:
	set(value):
		draw_out_px = value
		_relayout()
@export var draw_out_sec: float = 0.18
# A card sheathed (BattleController.card_sheathed): home over this instead.
@export var sheathe_snap_sec: float = 0.08

@export_group("Text")
@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		label_font = value
		_restyle()
@export var label_text: String = "SHEATHE":
	set(value):
		label_text = value
		_relayout()
@export var label_size_px: int = 12:
	set(value):
		label_size_px = value
		_restyle()
# One tracking value for every caps label in the battle UI - see InkType.
@export var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_restyle()
# What it does, in the HP readout's secondary run, as Devour's heal is.
@export var detail_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf"):
	set(value):
		detail_font = value
		_relayout()
@export var detail_text: String = "Keep 1":
	set(value):
		detail_text = value
		_relayout()
@export var detail_size_px: int = 14:
	set(value):
		detail_size_px = value
		_relayout()
@export_range(0.0, 1.0) var detail_alpha: float = 0.6:
	set(value):
		detail_alpha = value
		queue_redraw()
@export var used_text: String = "USED":
	set(value):
		used_text = value
		_relayout()
@export var no_energy_text: String = "NO ENERGY":
	set(value):
		no_energy_text = value
		_relayout()
@export var reason_size_px: int = 10:
	set(value):
		reason_size_px = value
		_restyle()
@export var glyph_text_gap_px: float = 10.0:
	set(value):
		glyph_text_gap_px = value
		_relayout()
@export var row_gap_px: float = 4.0:
	set(value):
		row_gap_px = value
		_relayout()

@export_group("States")
@export_range(0.0, 1.0) var grey_alpha: float = 0.35:
	set(value):
		grey_alpha = value
		queue_redraw()
@export var lit_fade_sec: float = 0.15
@export var rule_draw_sec: float = 0.2
@export var rule_px: float = 1.0:
	set(value):
		rule_px = value
		_relayout()
@export var rule_hover_px: float = 2.0:
	set(value):
		rule_hover_px = value
		_relayout()
@export var rule_gap_px: float = 3.0:
	set(value):
		rule_gap_px = value
		_relayout()

@export_group("Hover Text")
@export var hover_font: Font = load("res://assets/fonts/AlegreyaSans-Regular.ttf"):
	set(value):
		hover_font = value
		queue_redraw()
@export var hover_size_px: int = 15:
	set(value):
		hover_size_px = value
		queue_redraw()
@export var hover_gap_px: float = 10.0:
	set(value):
		hover_gap_px = value
		queue_redraw()
@export var hover_fade_sec: float = 0.12
@export var pick_text: String = "Choose a card to keep for your next turn.":
	set(value):
		pick_text = value
		queue_redraw()

# The blade in a box of half-extents 1 (x right, y down) about the glyph's
# centre, rising left to right: the scabbard from its mouth to its tip,
# a touch of curve, fine at the tip; the hilt from the guard down to its
# end; the guard across the blade at the scabbard's mouth.
const SCABBARD_SPINE: Array[Vector2] = [Vector2(-0.4, 0.42), Vector2(0.25, -0.02), Vector2(0.95, -0.52)]
const SCABBARD_WEIGHTS: Array[float] = [1.0, 1.0, 0.2]
const HILT_SPINE: Array[Vector2] = [Vector2(-0.95, 0.8), Vector2(-0.52, 0.5)]
const HILT_WEIGHTS: Array[float] = [0.9, 0.9]
const GUARD_SPINE: Array[Vector2] = [Vector2(-0.62, 0.22), Vector2(-0.34, 0.66)]
const GUARD_WEIGHTS: Array[float] = [1.0, 1.0]

var _controller: BattleController = null
var _ink: Color = Color.BLACK
var _bone: Color = Color.WHITE
var _label_tracked: Font = null
var _reason_tracked: Font = null
var _available: bool = false
var _used: bool = false
# Unused this turn with its Energy in hand - drawn in full ink.
var _usable: bool = false
# Why it can't be used, shown under the detail; "" while usable.
var _reason: String = ""
var _lit_target: bool = false
var _hovered: bool = false
# Each eased 0..1 toward its target in _process().
var _lit: float = 0.0
var _ink_level: float = 0.0
var _rule: float = 0.0
var _out: float = 0.0
var _rule_weight: float = 0.0
var _hover_shown: float = 0.0
# A card was just sheathed: the hilt goes home at sheathe_snap_sec.
var _snapping: bool = false
var _hover_floor_y: float = 0.0
var _glyph_centre: Vector2 = Vector2.ZERO
var _text_x: float = 0.0
var _label_baseline: float = 0.0
var _rule_y: float = 0.0
var _detail_baseline: float = 0.0
var _reason_baseline: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_process(false)
	refresh_style()

func setup(controller: BattleController) -> void:
	_controller = controller
	_controller.sheathe_changed.connect(func(_available_now: bool, _used_now: bool) -> void: _refresh())
	_controller.card_sheathed.connect(_on_card_sheathed)
	_refresh()

# Re-reads the theme's ink - at _ready() and on BattleOverlay's F2 flip.
func refresh_style() -> void:
	_ink = get_theme_color("ink", "Battle")
	_bone = get_theme_color("bone", "Battle")
	_restyle()

# The line above the bottom-left stack sits hover_gap_px over this global y.
func set_hover_floor_y(global_y: float) -> void:
	_hover_floor_y = global_y - global_position.y
	queue_redraw()

# Whether it reads lit now - for the probes.
func is_lit() -> bool:
	return _lit_target

func get_glyph_alpha() -> float:
	return lerpf(grey_alpha, 1.0, _smooth(_ink_level))

# The reason shown for its being unavailable, "" while it can be used.
func get_reason_text() -> String:
	return _reason

func _restyle() -> void:
	_label_tracked = InkType.tracked(label_font, label_size_px, label_tracking_em)
	_reason_tracked = InkType.tracked(label_font, reason_size_px, label_tracking_em)
	_relayout()

func _refresh() -> void:
	if _controller == null:
		return
	_available = _controller.is_sheathe_available()
	_used = _controller.is_sheathe_used()
	_usable = not _used and _controller.is_sheathe_affordable()
	_reason = "" if _usable else (used_text if _used else no_energy_text)
	_lit_target = _controller.is_sheathe_lit()
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _available or _controller.is_sheathe_picking() else Control.CURSOR_ARROW
	set_process(true)
	queue_redraw()

func _on_card_sheathed(_card: CardData) -> void:
	_snapping = true
	set_process(true)

func _process(delta: float) -> void:
	var lit: float = 1.0 if _lit_target else 0.0
	var ink_level: float = 1.0 if _usable else 0.0
	var weight: float = 1.0 if _hovered and _lit_target else 0.0
	_lit = _step(_lit, lit, lit_fade_sec, delta)
	_ink_level = _step(_ink_level, ink_level, lit_fade_sec, delta)
	_rule = _step(_rule, lit, rule_draw_sec, delta)
	_out = _step(_out, lit, sheathe_snap_sec if _snapping else draw_out_sec, delta)
	if _out == 0.0:
		_snapping = false
	_rule_weight = _step(_rule_weight, weight, lit_fade_sec, delta)
	_hover_shown = _step(_hover_shown, lit, hover_fade_sec, delta)
	queue_redraw()
	if _lit == lit and _ink_level == ink_level and _rule == lit and _out == lit and _rule_weight == weight and _hover_shown == lit:
		set_process(false)

func _step(value: float, target: float, seconds: float, delta: float) -> float:
	if seconds <= 0.0:
		return target
	return move_toward(value, target, delta / seconds)

func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _controller != null:
			_controller.sheathe()
		accept_event()

func _on_mouse_entered() -> void:
	_hovered = true
	set_process(true)

func _on_mouse_exited() -> void:
	_hovered = false
	set_process(true)

func _glyph_width() -> float:
	return glyph_height_px * glyph_width_ratio

# DevourButton's layout: glyph on the left, the text column glyph_text_gap_px
# right of it, centred on it, measured by ink - the label, its hairline's
# place, the detail, and the reason's place, kept whether or not it shows.
func _relayout() -> void:
	if not is_inside_tree() or label_font == null or detail_font == null:
		return
	var glyph_box := Vector2(_glyph_width() + draw_out_px, glyph_height_px + draw_out_px)
	var label_ascent: float = -BattleResources.figure_ink_top(label_font, label_size_px)
	var detail_ascent: float = -BattleResources.figure_ink_top(detail_font, detail_size_px)
	var reason_ascent: float = -BattleResources.figure_ink_top(label_font, reason_size_px)
	var rule_bottom: float = label_ascent + rule_gap_px + rule_hover_px
	var detail_baseline: float = rule_bottom + row_gap_px + detail_ascent
	var reason_baseline: float = detail_baseline + row_gap_px + reason_ascent
	var text_height: float = reason_baseline
	var height: float = maxf(glyph_box.y, text_height)
	var text_top: float = (height - text_height) * 0.5
	_glyph_centre = Vector2(draw_out_px + _glyph_width() * 0.5, height * 0.5)
	_text_x = glyph_box.x + glyph_text_gap_px
	_label_baseline = text_top + label_ascent
	_rule_y = text_top + label_ascent + rule_gap_px
	_detail_baseline = text_top + detail_baseline
	_reason_baseline = text_top + reason_baseline
	var text_width: float = maxf(InkType.width(_label_tracked, label_text, label_size_px), InkType.width(detail_font, detail_text, detail_size_px))
	for reason: String in [used_text, no_energy_text]:
		text_width = maxf(text_width, InkType.width(_reason_tracked, reason, reason_size_px))
	size = Vector2(_text_x + text_width, height)
	queue_redraw()

func _draw() -> void:
	if label_font == null or detail_font == null:
		return
	var ink_level: float = _smooth(_ink_level)
	InkPen.draw_ink(self, _blade_shapes(_glyph_centre, draw_out_px * _smooth(_out)), _ink, _bone, glyph_outline_px, glyph_edge_px, lerpf(grey_alpha, 1.0, ink_level))

	var label_color: Color = _ink
	label_color.a = lerpf(grey_alpha, 1.0, ink_level)
	var label_width: float = InkType.draw_run(self, _label_tracked, label_text, Vector2(_text_x, _label_baseline), label_size_px, label_color)
	var rule_length: float = label_width * _smooth(_rule)
	if rule_length > 0.0:
		var thickness: float = lerpf(rule_px, rule_hover_px, _smooth(_rule_weight))
		draw_rect(Rect2(_text_x, _rule_y, rule_length, thickness), label_color)

	var detail_color: Color = _ink
	detail_color.a = lerpf(grey_alpha, detail_alpha, ink_level)
	InkType.draw_run(self, detail_font, detail_text, Vector2(_text_x, _detail_baseline), detail_size_px, detail_color)

	if not _reason.is_empty():
		InkType.draw_run(self, _reason_tracked, _reason, Vector2(_text_x, _reason_baseline), reason_size_px, _ink)

	if _hover_shown > 0.0 and hover_font != null:
		var hover_color: Color = _ink
		hover_color.a = _hover_shown
		InkType.draw_run(self, hover_font, pick_text, Vector2(0.0, _hover_floor_y - hover_gap_px), hover_size_px, hover_color)

# The blade as ink shapes about `centre`, the hilt and guard `out` px drawn
# out along it, away from the scabbard's tip.
func _blade_shapes(centre: Vector2, out: float) -> Array[PackedVector2Array]:
	var half := Vector2(_glyph_width() * 0.5, maxf(glyph_height_px - glyph_stroke_px, 1.0) * 0.5)
	var along: Vector2 = (SCABBARD_SPINE[0] - SCABBARD_SPINE[SCABBARD_SPINE.size() - 1]) * half
	var drawn: Vector2 = along.normalized() * out
	return [
		InkPen.ribbon(_spine(SCABBARD_SPINE, centre, half, Vector2.ZERO), PackedFloat32Array(SCABBARD_WEIGHTS), glyph_stroke_px, glyph_taper),
		InkPen.ribbon(_spine(HILT_SPINE, centre, half, drawn), PackedFloat32Array(HILT_WEIGHTS), glyph_stroke_px * hilt_stroke_ratio, 1.0),
		InkPen.ribbon(_spine(GUARD_SPINE, centre, half, drawn), PackedFloat32Array(GUARD_WEIGHTS), glyph_stroke_px, 1.0),
	]

func _spine(points: Array[Vector2], centre: Vector2, half: Vector2, offset: Vector2) -> PackedVector2Array:
	var spine := PackedVector2Array()
	for point: Vector2 in points:
		spine.append(centre + offset + point * half)
	return spine
