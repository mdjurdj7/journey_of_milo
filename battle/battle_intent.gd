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
# this turn, counting down as cards land, inside a ring gauge - a faint
# track that fills clockwise in ink from ring_start_degrees with what has
# been dealt this turn. Empty at the start of the turn, full when the
# threshold is met: a full ring is the stopped state, the numeral reads 0
# and the attack pair dims to hairline ink - it won't land. The whole
# stack still ends at the anchor, so the attack line sits a ring higher.
# A BURROW (buried - it does nothing this turn) is its glyph alone: there
# is no number coming - and so is a SETTLE (the Underfoot's Rebury), a
# down-arrow onto a ground line. A HEAL_ALLY (the Nipper's Forage) is a plus beside
# the HP its packmates will heal. A multi-hit attack whose hits differ (a
# status on the player the first hit consumes - No Further's 0) reads hit
# by hit, "0 + 4", not "N x M".
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
# A Denied move's strike-through: this thick, this far past the pair at
# each end, at this fraction of the numeral's line box from its top.
@export var denied_rule_px: float = 1.0:
	set(value):
		denied_rule_px = value
		queue_redraw()
@export var denied_rule_overhang_px: float = 3.0:
	set(value):
		denied_rule_overhang_px = value
		queue_redraw()
@export_range(0.0, 1.0) var denied_rule_y_fraction: float = 0.55:
	set(value):
		denied_rule_y_fraction = value
		queue_redraw()
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
# Stroke weight of the track and the fill alike.
@export var ring_stroke_px: float = 2.0:
	set(value):
		ring_stroke_px = value
		queue_redraw()
# How far inside the track's centreline the fill runs, px. 0 = the fill
# rides on the track; more draws it as an inner ring within it.
@export var ring_fill_inset_px: float = 0.0:
	set(value):
		ring_fill_inset_px = value
		queue_redraw()
# Where the fill starts, degrees in screen space (0 = right, -90 = up);
# it grows clockwise from here.
@export var ring_start_degrees: float = -90.0:
	set(value):
		ring_start_degrees = value
		queue_redraw()
# Between the hairline's underside and the ring's top.
@export var ring_top_gap_px: float = 5.0:
	set(value):
		ring_top_gap_px = value
		_apply_layout()
@export_group("")

# An escalating enemy's stage (the preview's escalation_stage/_stages):
# one small square per stage in a row under everything else, the stages
# reached filled in ink, the rest a hairline outline. Only for an enemy
# that escalates - no pips, no space for them.
@export_group("Escalation Pips")
@export var pip_size_px: float = 5.0:
	set(value):
		pip_size_px = value
		_apply_layout()
@export var pip_gap_px: float = 4.0:
	set(value):
		pip_gap_px = value
		_apply_layout()
@export var pip_top_gap_px: float = 6.0:
	set(value):
		pip_top_gap_px = value
		_apply_layout()
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
# Denied (Deny): the move keeps its number, dimmed like an interrupted
# one, with denied_rule_px of ink struck through the glyph and numeral.
var _denied: bool = false
var _pair_rect: Rect2 = Rect2()
# How much of the ring is filled, 0..1: dealt this turn over the threshold.
var _ring_fill: float = 0.0
var _ring_centre: Vector2 = Vector2.ZERO
var _rule_top: float = 0.0
# The escalation pips: how many, how many filled, where the row's top is.
var _pip_count: int = 0
var _pip_filled: int = 0
var _pip_top: float = 0.0
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
	for label: Label in [_label, _threshold_label]:
		label.add_theme_color_override("font_color", get_theme_color("ink", "Battle"))
		label.add_theme_color_override("font_outline_color", get_theme_color("bone", "Battle"))
		label.add_theme_constant_override("outline_size", outline_size_px)
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
		var hit_amounts: Array = preview.get("hit_amounts", [])
		if hits > 1 and hit_amounts.size() == hits and hit_amounts.count(hit_amounts[0]) != hits:
			var parts := PackedStringArray()
			for amount: Variant in hit_amounts:
				parts.append(str(int(amount)))
			_label.text = " + ".join(parts)
		if _type == EnemyIntent.IntentType.BURROW or _type == EnemyIntent.IntentType.WATCH or _type == EnemyIntent.IntentType.SETTLE:
			_label.text = ""
		_has_threshold = preview.has("threshold")
		# A pain turn's cancelled action reads as interrupted, with no
		# number: it won't land at all.
		var pain_turn: bool = bool(preview.get("pain_turn", false))
		if pain_turn:
			_label.text = ""
		_denied = bool(preview.get("denied", false))
		_interrupted = pain_turn or _denied or bool(preview.get("interrupted", false))
		# The numeral counts down to 0 and stays; the gauge fills with
		# what has been dealt, full once the threshold is met.
		var threshold: int = int(preview.get("threshold", 0))
		var left: int = int(preview.get("threshold_left", 0))
		_threshold_label.text = str(left) if _has_threshold else ""
		_pip_count = int(preview.get("escalation_stages", 0))
		_pip_filled = mini(int(preview.get("escalation_stage", 0)) + 1, _pip_count)
		_ring_fill = 1.0 if _interrupted else (clampf(float(threshold - left) / float(threshold), 0.0, 1.0) if threshold > 0 else 0.0)
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
	if _pip_count > 0:
		content_width = maxf(content_width, _pips_width())
		_pip_top = content_height + pip_top_gap_px
		content_height = _pip_top + pip_size_px

	size = Vector2(content_width, content_height)
	pivot_offset = size / 2.0

	var pair_left: float = (content_width - pair_width) * 0.5
	_pair_rect = Rect2(pair_left, 0.0, pair_width, line_height)
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
	_threshold_label.visible = _has_threshold and not _threshold_label.text.is_empty()
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
	if _type == EnemyIntent.IntentType.WATCH:
		_draw_pupil(glyph_centre, _glyph_size * 0.5, hairline_alpha if _interrupted else 1.0)
	if _type == EnemyIntent.IntentType.SETTLE:
		_stroke(_settle_arrow_points(glyph_centre, _glyph_size * 0.5), hairline_alpha if _interrupted else 1.0)
	if _has_threshold:
		_draw_ring()
	if _pip_count > 0:
		_draw_pips(ink)

	# Denied: one ink rule through the pair - no glow, colour or icon.
	if _denied:
		var strike_y: float = roundf(_pair_rect.position.y + _pair_rect.size.y * denied_rule_y_fraction)
		draw_rect(Rect2(_pair_rect.position.x - denied_rule_overhang_px, strike_y, _pair_rect.size.x + denied_rule_overhang_px * 2.0, denied_rule_px), ink)

	var rule_thickness: float = lethal_rule_px if _lethal else hairline_thickness_px
	var rule_color: Color = ink
	if not _lethal:
		rule_color.a = hairline_alpha
	var rule_left: float = (size.x - hairline_width_px) * 0.5
	draw_rect(Rect2(rule_left, _rule_top, hairline_width_px, rule_thickness), rule_color)

func _pips_width() -> float:
	return float(_pip_count) * pip_size_px + float(maxi(_pip_count - 1, 0)) * pip_gap_px

# The pips, centred: the reached stages filled in ink, the rest outlined
# in ink at hairline_alpha - one hairline wide, like the rule.
func _draw_pips(ink: Color) -> void:
	var left: float = roundf((size.x - _pips_width()) * 0.5)
	var faint: Color = ink
	faint.a = hairline_alpha
	for i in _pip_count:
		var rect := Rect2(left + float(i) * (pip_size_px + pip_gap_px), _pip_top, pip_size_px, pip_size_px)
		if i < _pip_filled:
			draw_rect(rect, ink)
		else:
			draw_rect(rect, faint, false, hairline_thickness_px)

# The threshold gauge: the whole track at hairline ink, then the fill in
# full ink from ring_start_degrees clockwise (screen angles grow
# clockwise, y being down) over _ring_fill of the turn - bone under ink,
# like every stroke here.
func _draw_ring() -> void:
	var ink: Color = get_theme_color("ink", "Battle")
	var outline: Color = get_theme_color("bone", "Battle")
	var radius: float = ring_diameter_px * 0.5
	var outline_width: float = ring_stroke_px + float(outline_size_px) * 2.0
	var segments: int = 64
	var track_ink: Color = ink
	track_ink.a *= hairline_alpha
	var track_outline: Color = outline
	track_outline.a *= hairline_alpha
	draw_arc(_ring_centre, radius, 0.0, TAU, segments, track_outline, outline_width, true)
	draw_arc(_ring_centre, radius, 0.0, TAU, segments, track_ink, ring_stroke_px, true)
	if _ring_fill <= 0.0:
		return
	var fill_radius: float = maxf(radius - ring_fill_inset_px, 0.0)
	var start: float = deg_to_rad(ring_start_degrees)
	var end: float = start + TAU * _ring_fill
	var fill_segments: int = maxi(ceili(segments * _ring_fill), 2)
	draw_arc(_ring_centre, fill_radius, start, end, fill_segments, outline, outline_width, true)
	draw_arc(_ring_centre, fill_radius, start, end, fill_segments, ink, ring_stroke_px, true)

# WATCH's pupil: a filled dot in the eye, ink over its bone outline like
# a stroke.
func _draw_pupil(centre: Vector2, r: float, alpha: float) -> void:
	var ink: Color = get_theme_color("ink", "Battle")
	var outline: Color = get_theme_color("bone", "Battle")
	ink.a *= alpha
	outline.a *= alpha
	var radius: float = r * 0.24
	draw_circle(centre, radius + float(outline_size_px), outline, true, -1.0, true)
	draw_circle(centre, radius, ink, true, -1.0, true)

# SETTLE's arrow, the glyph's second stroke over its ground line: a short
# shaft coming down, its head stopping just short of the line - settling
# onto it, not under it (BURROW's mound is the one that goes under). Out
# along the shaft and back across the head, one polyline like the
# chevron's.
func _settle_arrow_points(centre: Vector2, r: float) -> PackedVector2Array:
	var tip: Vector2 = centre + Vector2(0.0, r * 0.3)
	var points := PackedVector2Array()
	points.append(centre + Vector2(0.0, -r * 0.85))
	points.append(tip)
	points.append(centre + Vector2(-r * 0.4, -r * 0.1))
	points.append(tip)
	points.append(centre + Vector2(r * 0.4, -r * 0.1))
	return points

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
# pushes up under the sand. HEAL_ALLY: a plus - one stroke, out along
# the bar and back to cross it. WATCH: an open eye - an almond, upper lid
# and lower, closed at the corners, its pupil a dot (_draw_pupil()).
# SETTLE: a flat ground line, its down-arrow drawn as a second stroke
# (_settle_arrow_points()). All fit a square of half-size r about centre.
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
		EnemyIntent.IntentType.HEAL_ALLY:
			points.append(centre + Vector2(-r * 0.8, 0.0))
			points.append(centre + Vector2(r * 0.8, 0.0))
			points.append(centre)
			points.append(centre + Vector2(0.0, -r * 0.8))
			points.append(centre + Vector2(0.0, r * 0.8))
		EnemyIntent.IntentType.WATCH:
			var lid_steps: int = 10
			for step in lid_steps + 1:
				var t: float = float(step) / float(lid_steps)
				points.append(centre + Vector2(lerpf(-r, r, t), -sin(t * PI) * r * 0.55))
			for step in range(1, lid_steps + 1):
				var t: float = float(step) / float(lid_steps)
				points.append(centre + Vector2(lerpf(r, -r, t), sin(t * PI) * r * 0.55))
		EnemyIntent.IntentType.SETTLE:
			points.append(centre + Vector2(-r * 0.8, r * 0.6))
			points.append(centre + Vector2(r * 0.8, r * 0.6))
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

# The world height of this readout's bottom edge - its anchor, which it
# sits on. INF with no target. Read by a play effect that has to stay
# under the readouts (BrushStrokeEffect, through BattleOverlay).
func anchor_height() -> float:
	if target == null or not is_instance_valid(target):
		return INF
	return target.global_position.y + _anchor_offset().y

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
