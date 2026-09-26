extends Control
class_name BattleIntent

# The enemy's next action, above its head in the battle frame: a line
# glyph for the type (attack / defend - the only types EnemyIntent has;
# buff/debuff get theirs when they exist) beside a numeral for
# the magnitude - "N x M" for a multi-hit attack (hits x per-hit damage,
# the MODIFIED per-hit number, see EnemyTurn.preview_intent()). Ink on the
# world, like the rest of the battle UI: the numeral in Spectral SemiBold
# in the theme's ink with a 1px bone outline for legibility over the
# world, the glyph stroked the same way, and a hairline (ink at
# hairline_alpha) beneath the pair - no backing. The numeral is never
# smaller than the glyph - it's the fairness contract, the glyph is only
# its category. If the shown damage would reach the Wanderer's current HP
# through block, the hairline becomes a full-ink rule, lethal_rule_px
# thick - the one emphasis, nothing else.
#
# An interruptible attack (EnemyIntent.interrupt_threshold, the Siltjaw's
# charge) adds a second row under the hairline: the damage still to deal
# this turn, counting down as cards land, inside a thin ink ring with a
# gap in it - a break waiting to be made, not a second number coming at
# you. Met, it reads 0, the ring closes (or fills, closed_ring_filled)
# and the attack pair dims to hairline ink - it won't land. The whole
# stack still ends at the anchor, so the attack line sits a ring higher.
# A BURROW (buried - it does nothing this turn) is its glyph alone: there
# is no number coming.
#
# One per enemy, created by BattleOverlay for the fight (its child, so it
# dies with the overlay - nothing of this exists on the field). Anchored
# the way EnemyStatus is: repositioned every physics tick at priority 1
# (after CameraRig/FieldEnemy have moved this tick), unprojected from the
# enemy's own head + head_margin, whole pixels. Not distance-scaled: it
# only shows once the battle frame has settled, and its sizes are the
# on-screen pixel sizes. EnemyStatus's own bar hangs under the enemy's
# feet (bar_offset points down), so the two never share the head band and
# nothing stacks.
#
# Shown by BattleOverlay once the battle frame has settled (the camera's
# battle_transition_time), updated on every enemy_intent_changed, hidden
# on enemy_acting while the enemy resolves.

# The display's bottom edge (the hairline) sits head_margin metres above
# the enemy's own head - FieldEnemy.get_head_height(), its model's scaled
# bbox height (0.75m for the Sputter) - with fallback_head_height
# (BattleOverlay's humanoid-guess enemy_head_height) only if the enemy
# reports 0.
@export var head_margin: float = 0.1
@export var fallback_head_height: float = 1.8
@export var numeral_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")
@export var numeral_size_px: int = 34
@export var outline_size_px: int = 1
# The glyph is sized to the numeral's cap height and stroked heavier to
# match its weight; it's clamped to never exceed the numeral.
@export var glyph_cap_scale: float = 0.7
@export var glyph_numeral_gap_px: float = 6.0
@export var glyph_line_width_px: float = 3.5
# The hairline under glyph + numeral: this wide, centred, this far under
# the numeral's line box, ink at hairline_alpha.
@export var hairline_width_px: float = 52.0
@export var hairline_thickness_px: float = 1.0
@export_range(0.0, 1.0) var hairline_alpha: float = 0.45
@export var hairline_drop_px: float = 4.0
# The lethal emphasis: the hairline becomes a full-ink rule this thick.
@export var lethal_rule_px: float = 2.0

# The threshold ring, under the hairline (see the header). Its numeral is
# never smaller than the HP readout's (EnemyStatus.battle_numeral_size_px,
# 22) - it has to read at the battle frame's scale.
@export_group("Threshold Ring")
@export var threshold_numeral_size_px: int = 22:
	set(value):
		threshold_numeral_size_px = value
		_apply_layout()
@export var ring_diameter_px: float = 40.0:
	set(value):
		ring_diameter_px = value
		_apply_layout()
@export var ring_stroke_px: float = 2.0:
	set(value):
		ring_stroke_px = value
		queue_redraw()
# The break in the ring, degrees of arc, and where its middle faces
# (degrees, screen space: 0 = right, -90 = up).
@export_range(0.0, 180.0) var ring_gap_degrees: float = 50.0:
	set(value):
		ring_gap_degrees = value
		queue_redraw()
@export var ring_gap_facing_degrees: float = -60.0:
	set(value):
		ring_gap_facing_degrees = value
		queue_redraw()
# Between the hairline's underside and the ring's top.
@export var ring_top_gap_px: float = 5.0:
	set(value):
		ring_top_gap_px = value
		_apply_layout()
# Met: the ring closes as a line (false) or fills solid ink with the 0 in
# bone (true).
@export var closed_ring_filled: bool = false:
	set(value):
		closed_ring_filled = value
		refresh_style()
@export_group("")

var target: FieldEnemy = null
var _label: Label = null
# Content geometry from _apply_layout(), for _draw().
var _glyph_size: float = 0.0
var _glyph_centre: Vector2 = Vector2.ZERO
var _text_rect: Rect2 = Rect2()
var _type: int = EnemyIntent.IntentType.ATTACK
var _has_intent: bool = false
var _lethal: bool = false
# The threshold ring (see the header): shown, met, where it sits, and
# the hairline's top now that it no longer ends the control.
var _threshold_label: Label = null
var _has_threshold: bool = false
var _interrupted: bool = false
var _ring_centre: Vector2 = Vector2.ZERO
var _rule_top: float = 0.0
# "Revealed" is the overlay's say (frame settled, not acting); the display
# is only visible when revealed AND it has something to show.
var _revealed: bool = false
var _ready_done: bool = false

func _ready() -> void:
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if numeral_font != null:
		_label.add_theme_font_override("font", numeral_font)
	add_child(_label)

	_threshold_label = Label.new()
	_threshold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_threshold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_threshold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if numeral_font != null:
		_threshold_label.add_theme_font_override("font", numeral_font)
	add_child(_threshold_label)

	refresh_style()
	_apply_layout()
	_update_visibility()

func set_target(enemy: FieldEnemy) -> void:
	target = enemy

# The display's colours, from the theme's Battle tokens: ink on the
# numeral with a bone outline - so it inverts with the on-pale/on-dark
# switch alongside the HP readouts. Re-read on BattleOverlay's F2 flip.
func refresh_style() -> void:
	if _label == null:
		return
	var ink: Color = get_theme_color("ink", "Battle")
	var bone: Color = get_theme_color("bone", "Battle")
	for label: Label in [_label, _threshold_label]:
		label.add_theme_color_override("font_color", ink)
		label.add_theme_color_override("font_outline_color", bone)
		label.add_theme_constant_override("outline_size", outline_size_px)
	# A filled, closed ring is ink: its 0 turns bone to read on it.
	if closed_ring_filled and _interrupted:
		_threshold_label.add_theme_color_override("font_color", bone)
		_threshold_label.add_theme_color_override("font_outline_color", ink)
	queue_redraw()

# preview is EnemyTurn.preview_intent()'s dictionary (empty = nothing).
func show_intent(preview: Dictionary) -> void:
	_has_intent = not preview.is_empty()
	if _has_intent:
		_type = int(preview["type"])
		_lethal = bool(preview.get("lethal", false))
		var hits: int = int(preview.get("hits", 1))
		var per_hit: int = int(preview.get("per_hit", 0))
		_label.text = ("%d×%d" % [hits, per_hit]) if hits > 1 else str(per_hit)
		if _type == EnemyIntent.IntentType.BURROW:
			_label.text = ""
		_has_threshold = preview.has("threshold")
		_interrupted = bool(preview.get("interrupted", false))
		_threshold_label.text = str(int(preview.get("threshold_left", 0))) if _has_threshold else ""
	refresh_style()
	_apply_layout()
	_update_visibility()

func set_revealed(revealed: bool) -> void:
	_revealed = revealed
	_update_visibility()

func _update_visibility() -> void:
	visible = _revealed and _has_intent

# Glyph on the left, numeral on the right, on one line; the hairline
# centred beneath. This control's width is the wider of the pair and the
# hairline, measured from the rendered text width (EnemyStatus's own
# approach, not the label's lazily-updated minimum size) so the unproject
# can centre it exactly; its bottom edge is the rule's underside - or,
# with a threshold, the ring's, which hangs centred under the rule.
func _apply_layout() -> void:
	if not _ready_done:
		return
	_label.add_theme_font_size_override("font_size", numeral_size_px)
	var font: Font = _label.get_theme_font("font")
	var line_height: float = font.get_height(numeral_size_px) if font != null else float(numeral_size_px)
	_glyph_size = minf(float(numeral_size_px) * glyph_cap_scale, float(numeral_size_px))
	_threshold_label.add_theme_font_size_override("font_size", threshold_numeral_size_px)
	var text_width: float = _text_width(_label, numeral_size_px)
	# A glyph with no numeral (BURROW) is the glyph alone, no gap.
	var pair_width: float = _glyph_size
	if text_width > 0.0:
		pair_width += glyph_numeral_gap_px + text_width
	var rule_thickness: float = lethal_rule_px if _lethal else hairline_thickness_px
	var ring_box: float = ring_diameter_px + ring_stroke_px + float(outline_size_px) * 2.0
	var content_width: float = maxf(pair_width, hairline_width_px)
	var content_height: float = line_height + hairline_drop_px + rule_thickness
	if _has_threshold:
		content_width = maxf(content_width, ring_box)
		content_height += ring_top_gap_px + ring_box

	size = Vector2(content_width, content_height)
	pivot_offset = size / 2.0

	var pair_left: float = (content_width - pair_width) * 0.5
	_glyph_centre = Vector2(pair_left + _glyph_size * 0.5, line_height * 0.5)
	_text_rect = Rect2(pair_left + _glyph_size + glyph_numeral_gap_px, 0.0, text_width, line_height)
	_label.position = _text_rect.position
	_label.size = _text_rect.size
	_label.visible = text_width > 0.0
	_label.modulate.a = hairline_alpha if _interrupted else 1.0
	_rule_top = line_height + hairline_drop_px

	# The ring's numeral fills the ring's box, centred both ways.
	var ring_top: float = _rule_top + rule_thickness + ring_top_gap_px
	_ring_centre = Vector2(content_width * 0.5, ring_top + ring_box * 0.5)
	_threshold_label.position = _ring_centre - Vector2(ring_box, ring_box) * 0.5
	_threshold_label.size = Vector2(ring_box, ring_box)
	_threshold_label.visible = _has_threshold
	queue_redraw()

func _text_width(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null or label.text.is_empty():
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# The glyph in the same ink/outline as the numeral: each stroke is drawn
# twice, outline colour wide underneath, ink colour on top - the line
# equivalent of the label's outline. A directional glyph (the attack
# chevron) points toward the Wanderer: _glyph_points() is built pointing
# screen-right and mirrored about the glyph's centre when the Wanderer is
# to the left (see _points_left()). The shield is symmetric and never
# flips. Beneath both, the hairline - or the lethal rule in its place.
func _draw() -> void:
	if not _has_intent:
		return
	var ink: Color = get_theme_color("ink", "Battle")
	var glyph_centre: Vector2 = _glyph_centre
	var points: PackedVector2Array = _glyph_points(glyph_centre, _glyph_size * 0.5)
	if _type == EnemyIntent.IntentType.ATTACK and _points_left():
		for i in points.size():
			points[i] = Vector2(2.0 * glyph_centre.x - points[i].x, points[i].y)
	_stroke(points, hairline_alpha if _interrupted else 1.0)
	if _has_threshold:
		_draw_ring()

	var rule_thickness: float = lethal_rule_px if _lethal else hairline_thickness_px
	var rule_color: Color = ink
	if not _lethal:
		rule_color.a = hairline_alpha
	var rule_left: float = (size.x - hairline_width_px) * 0.5
	draw_rect(Rect2(rule_left, _rule_top, hairline_width_px, rule_thickness), rule_color)

# The threshold ring: bone under ink, like every stroke here, broken by
# ring_gap_degrees around ring_gap_facing_degrees - sealed once met, or
# filled solid (closed_ring_filled), the 0 then drawn in bone by
# refresh_style().
func _draw_ring() -> void:
	var ink: Color = get_theme_color("ink", "Battle")
	var outline: Color = get_theme_color("bone", "Battle")
	var radius: float = ring_diameter_px * 0.5
	if _interrupted and closed_ring_filled:
		draw_circle(_ring_centre, radius + ring_stroke_px * 0.5 + float(outline_size_px), outline, true, -1.0, true)
		draw_circle(_ring_centre, radius + ring_stroke_px * 0.5, ink, true, -1.0, true)
		return
	var gap: float = 0.0 if _interrupted else deg_to_rad(clampf(ring_gap_degrees, 0.0, 180.0))
	var facing: float = deg_to_rad(ring_gap_facing_degrees)
	var start: float = facing + gap * 0.5
	var end: float = facing + TAU - gap * 0.5
	var segments: int = 64
	draw_arc(_ring_centre, radius, start, end, segments, outline, ring_stroke_px + float(outline_size_px) * 2.0, true)
	draw_arc(_ring_centre, radius, start, end, segments, ink, ring_stroke_px, true)

# One glyph stroke in the numeral's ink over its bone outline, at alpha.
func _stroke(points: PackedVector2Array, alpha: float) -> void:
	if points.size() < 2:
		return
	var ink: Color = get_theme_color("ink", "Battle")
	var outline: Color = get_theme_color("bone", "Battle")
	ink.a *= alpha
	outline.a *= alpha
	draw_polyline(points, outline, glyph_line_width_px + float(outline_size_px) * 2.0, true)
	draw_polyline(points, ink, glyph_line_width_px, true)

# ATTACK: a chevron pointing right with a short shaft - an arrow, the
# action coming at you. DEFEND: an open shield - flat top, sides, a point
# at the bottom, closed. BURROW: a mound on a ground line - the swell it
# pushes up under the sand. All fit a square of half-size r about centre.
func _glyph_points(centre: Vector2, r: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	match _type:
		EnemyIntent.IntentType.ATTACK:
			points.append(centre + Vector2(-r, 0.0))
			points.append(centre + Vector2(r * 0.7, 0.0))
			points.append(centre + Vector2(0.0, -r * 0.7))
			points.append(centre + Vector2(r * 0.7, 0.0))
			points.append(centre + Vector2(0.0, r * 0.7))
		EnemyIntent.IntentType.DEFEND:
			points.append(centre + Vector2(-r * 0.8, -r * 0.9))
			points.append(centre + Vector2(r * 0.8, -r * 0.9))
			points.append(centre + Vector2(r * 0.8, r * 0.1))
			points.append(centre + Vector2(0.0, r * 0.95))
			points.append(centre + Vector2(-r * 0.8, r * 0.1))
			points.append(centre + Vector2(-r * 0.8, -r * 0.9))
		EnemyIntent.IntentType.BURROW:
			points.append(centre + Vector2(-r, r * 0.45))
			var arc_steps: int = 8
			for step in arc_steps + 1:
				var angle: float = PI - PI * float(step) / float(arc_steps)
				points.append(centre + Vector2(cos(angle) * r * 0.6, r * 0.45 - sin(angle) * r * 0.7))
			points.append(centre + Vector2(r, r * 0.45))
	return points

# Whether the Wanderer is to the screen-left of the enemy right now -
# compared in screen X at draw time, so the chevron follows the battle
# framing whichever side the camera put each of them on.
func _points_left() -> bool:
	if target == null or not is_instance_valid(target):
		return false
	var wanderers: Array[Node] = get_tree().get_nodes_in_group("wanderer")
	if wanderers.is_empty():
		return false
	var wanderer := wanderers[0] as Node3D
	var camera := get_viewport().get_camera_3d()
	if wanderer == null or camera == null:
		return false
	return camera.unproject_position(wanderer.global_position).x < camera.unproject_position(target.global_position).x

# The anchor: the enemy's own head plus head_margin.
func _anchor_offset() -> Vector3:
	var head: float = target.get_head_height() if target != null else 0.0
	if head <= 0.0:
		head = fallback_head_height
	# The bob on top: the head's own height already carries the hover.
	var bob: float = target.get_bob_offset() if target != null else 0.0
	return Vector3(0.0, head + head_margin + bob, 0.0)

# Same loop as EnemyStatus._physics_process(): unproject, whole pixels.
# Also re-evaluates the chevron's direction, since the framing can swap
# sides during the battle transition.
var _pointing_left: bool = false

func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor: Vector3 = target.global_position + _anchor_offset()
	var screen_pos: Vector2 = camera.unproject_position(anchor)
	# Centred on the enemy in X, bottom edge on the anchor in Y - the
	# display sits just above the silhouette rather than straddling the
	# anchor.
	position = (screen_pos - Vector2(size.x / 2.0, size.y)).round()
	var left: bool = _points_left()
	if left != _pointing_left:
		_pointing_left = left
		queue_redraw()
