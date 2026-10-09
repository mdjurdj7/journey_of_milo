extends Control
class_name DevourButton

# Devour (BattleController.devour()) on the battle overlay, in the system
# voice of the readouts around it: directly under the energy readout, its
# left edge on the readout's (BattleOverlay._apply_energy_anchor()). A
# line-drawn open jaw on the left - upper and lower jaw, a few teeth,
# in the intent glyphs' tapered pen (InkPen) at about the energy
# numeral's cap height - and stacked to its right "DEVOUR" in tracked
# caps, "+2 HP" in the HP readout's smaller grey numeral, and "USED" in
# small grey caps once this turn's Devour is spent. No disc, ring, glow
# or divider.
#
# States, all read from the controller on devour_changed:
# - Grey (nothing armed, or used this turn): glyph and label at
#   grey_alpha. Still clickable while available - with nothing armed a
#   click opens the controller's pick (a hand card to eat).
# - Lit (a card armed, or the pick open, with Devour available): glyph and
#   label ease to full ink over lit_fade_sec, a hairline draws in under
#   the label left to right over rule_draw_sec, and the jaws part by
#   jaw_open_px each, eased, held while it stays lit. No glow, pulse or
#   colour.
# - Hovered while lit with a card armed: the hairline thickens to
#   rule_hover_px and one line names it ("Consume Slash. Heal 2 HP.");
#   while the pick is open the line reads pick_text. The line sits
#   hover_gap_px above set_hover_floor_y() - the top of the bottom-left
#   stack, where the keepsake reveal appears - left-aligned with this.
# - Back to grey (disarmed, played, devoured): eased back, the jaw closing.
#
# Left-click calls devour(); every other button passes through
# (MOUSE_FILTER_PASS, not accepted), so a right-click still cancels the
# armed card or the pick. Pixel sizes at 1080p.

@export_group("Glyph")
# The jaw's inked height, closed - near the energy numeral's cap height,
# held under it so the column clears a full hand's resting cards.
@export var glyph_height_px: float = 40.0:
	set(value):
		glyph_height_px = value
		_relayout()
@export_range(0.5, 3.0) var glyph_width_ratio: float = 1.25:
	set(value):
		glyph_width_ratio = value
		_relayout()
# The pen: a jaw's body this wide, narrowing to glyph_taper of it at its
# fine ends (InkPen.ribbon()) - BattleIntent's weights.
@export var glyph_stroke_px: float = 3.2:
	set(value):
		glyph_stroke_px = value
		queue_redraw()
@export_range(0.0, 1.0) var glyph_taper: float = 0.15:
	set(value):
		glyph_taper = value
		queue_redraw()
# A bone outline round the ink, as the intent glyphs over the world have;
# 0 = none, like the energy numeral above it.
@export var glyph_outline_px: float = 0.0:
	set(value):
		glyph_outline_px = value
		queue_redraw()
@export var glyph_edge_px: float = 1.0:
	set(value):
		glyph_edge_px = value
		queue_redraw()
# Teeth per jaw, each this long (a fraction of the glyph's half-height)
# at the hinge end, shorter toward the tip.
@export var tooth_count: int = 3:
	set(value):
		tooth_count = value
		queue_redraw()
@export_range(0.0, 1.0) var tooth_length: float = 0.3:
	set(value):
		tooth_length = value
		queue_redraw()
@export_range(0.0, 0.5) var tooth_half_width: float = 0.11:
	set(value):
		tooth_half_width = value
		queue_redraw()
# Lit, each jaw moves this far from the other, over jaw_open_sec.
@export var jaw_open_px: float = 3.0:
	set(value):
		jaw_open_px = value
		_relayout()
@export var jaw_open_sec: float = 0.18

@export_group("Text")
@export var label_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf"):
	set(value):
		label_font = value
		_restyle()
@export var label_text: String = "DEVOUR":
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
# The heal, in the HP readout's secondary run (HPBar.battle_max_size_px at
# battle_secondary_alpha).
@export var heal_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf"):
	set(value):
		heal_font = value
		_relayout()
@export var heal_format: String = "+%d HP":
	set(value):
		heal_format = value
		_relayout()
@export var heal_size_px: int = 14:
	set(value):
		heal_size_px = value
		_relayout()
@export_range(0.0, 1.0) var heal_alpha: float = 0.6:
	set(value):
		heal_alpha = value
		queue_redraw()
@export var used_text: String = "USED":
	set(value):
		used_text = value
		_relayout()
@export var used_size_px: int = 9:
	set(value):
		used_size_px = value
		_restyle()
# Between the glyph and the text, and between text rows.
@export var glyph_text_gap_px: float = 10.0:
	set(value):
		glyph_text_gap_px = value
		_relayout()
@export var row_gap_px: float = 4.0:
	set(value):
		row_gap_px = value
		_relayout()

@export_group("States")
# Grey: the ink at this alpha - glyph, label, heal and USED alike.
@export_range(0.0, 1.0) var grey_alpha: float = 0.35:
	set(value):
		grey_alpha = value
		queue_redraw()
@export var lit_fade_sec: float = 0.15
@export var rule_draw_sec: float = 0.2
# The hairline under the label: this thick, rule_hover_px hovered, this
# far under the label's baseline.
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
# The armed card's name, then the heal.
@export var hover_format: String = "Consume %s. Heal %d HP.":
	set(value):
		hover_format = value
		_refresh()
@export var pick_text: String = "Choose a card to devour.":
	set(value):
		pick_text = value
		_refresh()

# The upper jaw's spine and pen weight along it, in a box of half-extents
# 1 (x right, y down) about the glyph's centre: from the hinge, left, up
# and over to the tip, right. The lower jaw is its mirror.
const JAW_SPINE: Array[Vector2] = [Vector2(-0.95, -0.12), Vector2(-0.55, -0.5), Vector2(0.05, -0.72), Vector2(0.6, -0.62), Vector2(0.95, -0.3)]
const JAW_WEIGHTS: Array[float] = [0.35, 0.9, 1.0, 0.7, 0.0]
# The spine's furthest reach from the centre line (its crown), in that box.
const JAW_REACH: float = 0.72
# Where the teeth stand along x, first to last; the last is this much
# shorter than the first.
const TEETH_FROM_X: float = -0.35
const TEETH_TO_X: float = 0.6
const LAST_TOOTH_SCALE: float = 0.6

var _controller: BattleController = null
var _ink: Color = Color.BLACK
var _bone: Color = Color.WHITE
var _label_tracked: Font = null
var _used_tracked: Font = null
# What the controller last said (_refresh()).
var _available: bool = false
var _used: bool = false
var _picking: bool = false
var _lit_target: bool = false
var _card_name: String = ""
var _hovered: bool = false
# Each eased 0..1 toward its target in _process() - linear here, eased in
# _draw().
var _lit: float = 0.0
var _rule: float = 0.0
var _open: float = 0.0
var _rule_weight: float = 0.0
var _hover_shown: float = 0.0
# The line last shown, kept while it fades out.
var _hover_text: String = ""
# The hover line's floor, this control's local y (set_hover_floor_y()).
var _hover_floor_y: float = 0.0
# Layout from _relayout(), for _draw().
var _glyph_centre: Vector2 = Vector2.ZERO
var _text_x: float = 0.0
var _label_baseline: float = 0.0
var _rule_y: float = 0.0
var _heal_baseline: float = 0.0
var _used_baseline: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	set_process(false)
	refresh_style()

func setup(controller: BattleController) -> void:
	_controller = controller
	_controller.devour_changed.connect(func(_available_now: bool, _used_now: bool) -> void: _refresh())
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

# Whether the cursor is on Devour while it is the armed card's target -
# TargetLine ends on the jaw then (get_target_point()).
func is_target_hovered() -> bool:
	return _hovered and _lit_target and not _picking

# The jaw's centre, in the viewport's pixels.
func get_target_point() -> Vector2:
	return get_global_transform() * _glyph_centre

# Whether it reads lit now (lit_fade_sec after it was asked to) - for the
# probes.
func is_lit() -> bool:
	return _lit_target

func get_glyph_alpha() -> float:
	return lerpf(grey_alpha, 1.0, _smooth(_lit))

func _restyle() -> void:
	_label_tracked = InkType.tracked(label_font, label_size_px, label_tracking_em)
	_used_tracked = InkType.tracked(label_font, used_size_px, label_tracking_em)
	_relayout()

func _refresh() -> void:
	if _controller == null:
		return
	_available = _controller.is_devour_available()
	_used = _controller.is_devour_used()
	_picking = _controller.is_devour_picking()
	_lit_target = _controller.is_devour_lit()
	var card: CardData = _controller.get_devour_card()
	_card_name = card.card_name if card != null else ""
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _available else Control.CURSOR_ARROW
	set_process(true)
	queue_redraw()

func _heal_text() -> String:
	var amount: int = _controller.devour_heal_amount if _controller != null else 0
	return heal_format % amount

# The line to show now, or "" for none: the pick's prompt while it is
# open, the armed card's while hovered lit.
func _wanted_hover_text() -> String:
	if _picking and _lit_target:
		return pick_text
	if _hovered and _lit_target and not _card_name.is_empty():
		var amount: int = _controller.devour_heal_amount if _controller != null else 0
		return hover_format % [_card_name, amount]
	return ""

func _process(delta: float) -> void:
	var lit: float = 1.0 if _lit_target else 0.0
	var wanted: String = _wanted_hover_text()
	if not wanted.is_empty():
		_hover_text = wanted
	_lit = _step(_lit, lit, lit_fade_sec, delta)
	_rule = _step(_rule, lit, rule_draw_sec, delta)
	_open = _step(_open, lit, jaw_open_sec, delta)
	_rule_weight = _step(_rule_weight, 1.0 if _hovered and _lit_target else 0.0, lit_fade_sec, delta)
	_hover_shown = _step(_hover_shown, 0.0 if wanted.is_empty() else 1.0, hover_fade_sec, delta)
	queue_redraw()
	if _lit == lit and _rule == lit and _open == lit and _rule_weight == (1.0 if _hovered and _lit_target else 0.0) and _hover_shown == (0.0 if wanted.is_empty() else 1.0):
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
			_controller.devour()
		accept_event()

func _on_mouse_entered() -> void:
	_hovered = true
	set_process(true)

func _on_mouse_exited() -> void:
	_hovered = false
	set_process(true)

func _glyph_width() -> float:
	return glyph_height_px * glyph_width_ratio

# Glyph on the left, its box the jaws' ink at their widest; the text
# column glyph_text_gap_px right of it, centred on it, measured by ink -
# caps and figures, nothing below the baseline - so the column stays
# short: the label, its hairline's place (the hovered weight, so nothing
# moves), the heal, and USED's place - kept whether or not it shows.
func _relayout() -> void:
	if not is_inside_tree() or label_font == null or heal_font == null:
		return
	var glyph_box := Vector2(_glyph_width(), glyph_height_px + jaw_open_px * 2.0)
	var label_ascent: float = -BattleResources.figure_ink_top(label_font, label_size_px)
	var heal_ascent: float = -BattleResources.figure_ink_top(heal_font, heal_size_px)
	var used_ascent: float = -BattleResources.figure_ink_top(label_font, used_size_px)
	var rule_bottom: float = label_ascent + rule_gap_px + rule_hover_px
	var heal_baseline: float = rule_bottom + row_gap_px + heal_ascent
	var used_baseline: float = heal_baseline + row_gap_px + used_ascent
	var text_height: float = used_baseline
	var height: float = maxf(glyph_box.y, text_height)
	var text_top: float = (height - text_height) * 0.5
	_glyph_centre = Vector2(_glyph_width() * 0.5, height * 0.5)
	_text_x = _glyph_width() + glyph_text_gap_px
	_label_baseline = text_top + label_ascent
	_rule_y = text_top + label_ascent + rule_gap_px
	_heal_baseline = text_top + heal_baseline
	_used_baseline = text_top + used_baseline
	var text_width: float = maxf(InkType.width(_label_tracked, label_text, label_size_px), InkType.width(heal_font, _heal_text(), heal_size_px))
	text_width = maxf(text_width, InkType.width(_used_tracked, used_text, used_size_px))
	size = Vector2(_text_x + text_width, height)
	queue_redraw()

func _draw() -> void:
	if label_font == null or heal_font == null:
		return
	var lit: float = _smooth(_lit)
	var shapes: Array[PackedVector2Array] = _jaw_shapes(_glyph_centre, jaw_open_px * _smooth(_open))
	InkPen.draw_ink(self, shapes, _ink, _bone, glyph_outline_px, glyph_edge_px, lerpf(grey_alpha, 1.0, lit))

	var label_color: Color = _ink
	label_color.a = lerpf(grey_alpha, 1.0, lit)
	var label_width: float = InkType.draw_run(self, _label_tracked, label_text, Vector2(_text_x, _label_baseline), label_size_px, label_color)
	# The hairline draws in from the label's left edge.
	var rule_length: float = label_width * _smooth(_rule)
	if rule_length > 0.0:
		var thickness: float = lerpf(rule_px, rule_hover_px, _smooth(_rule_weight))
		draw_rect(Rect2(_text_x, _rule_y, rule_length, thickness), label_color)

	var heal_color: Color = _ink
	heal_color.a = lerpf(grey_alpha, heal_alpha, lit)
	InkType.draw_run(self, heal_font, _heal_text(), Vector2(_text_x, _heal_baseline), heal_size_px, heal_color)

	if _used:
		var used_color: Color = _ink
		used_color.a = grey_alpha
		InkType.draw_run(self, _used_tracked, used_text, Vector2(_text_x, _used_baseline), used_size_px, used_color)

	if _hover_shown > 0.0 and not _hover_text.is_empty() and hover_font != null:
		var hover_color: Color = _ink
		hover_color.a = _hover_shown
		InkType.draw_run(self, hover_font, _hover_text, Vector2(0.0, _hover_floor_y - hover_gap_px), hover_size_px, hover_color)

# The jaw as ink shapes about `centre`, the jaws `apart` px each from
# closed: the upper one a pen stroke from the hinge up and over to the
# tip (JAW_SPINE), thickest over its crown, fine at the tip; its teeth
# solid points hanging from its inner edge toward the mouth, longest at
# the hinge end. The lower jaw is the same, mirrored.
func _jaw_shapes(centre: Vector2, apart: float) -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = []
	# Scaled so the crowns' ink, stroke included, spans glyph_height_px.
	var half := Vector2(_glyph_width() * 0.5, maxf(glyph_height_px - glyph_stroke_px, 1.0) / (2.0 * JAW_REACH))
	for side: float in [-1.0, 1.0]:
		var offset := Vector2(0.0, side * apart)
		var spine := PackedVector2Array()
		var factors := PackedFloat32Array()
		for i in JAW_SPINE.size():
			var point: Vector2 = JAW_SPINE[i]
			spine.append(centre + offset + Vector2(point.x * half.x, -side * point.y * half.y))
			factors.append(JAW_WEIGHTS[i])
		shapes.append(InkPen.ribbon(spine, factors, glyph_stroke_px, glyph_taper))
		var count: int = maxi(tooth_count, 0)
		for k in count:
			var t: float = float(k) / float(maxi(count - 1, 1))
			var x: float = lerpf(TEETH_FROM_X, TEETH_TO_X, t) * half.x
			var root: Vector2 = Vector2(centre.x + x, _spine_y(spine, centre.x + x))
			var length: float = tooth_length * half.y * lerpf(1.0, LAST_TOOTH_SCALE, t)
			var width: float = tooth_half_width * half.x
			# Toward the mouth: down from the upper jaw, up from the lower.
			var inward: float = 1.0 if side < 0.0 else -1.0
			shapes.append(PackedVector2Array([
				root + Vector2(-width, 0.0),
				root + Vector2(width, 0.0),
				root + Vector2(0.0, inward * (length + glyph_stroke_px * 0.5)),
			]))
	return shapes

# The spine's y at `x`, along its segments (x runs left to right).
func _spine_y(spine: PackedVector2Array, x: float) -> float:
	for i in range(1, spine.size()):
		if x <= spine[i].x:
			var a: Vector2 = spine[i - 1]
			var b: Vector2 = spine[i]
			var t: float = clampf((x - a.x) / maxf(b.x - a.x, 0.001), 0.0, 1.0)
			return lerpf(a.y, b.y, t)
	return spine[spine.size() - 1].y
