extends Control
class_name BattleIntent

# The enemy's next action, above its head in the battle frame: a line
# glyph for the type (attack / defend - the only types EnemyIntent has;
# buff/debuff get theirs when they exist) beside a numeral for
# the magnitude - "N x M" for a multi-hit attack (hits x per-hit damage,
# the MODIFIED per-hit number, see EnemyTurn.preview_intent()). Styled as
# the same chip EnemyStatus's HP numbers sit on: the theme's own font,
# text_color ink with EnemyStatus's 1px panel_color outline, on a
# panel_color backing at its alpha/corner radius/padding - only bigger
# (chip_text_scale x its battle text size). The numeral is never smaller
# than the glyph - it's the fairness contract, the glyph is only its
# category. If the shown damage would reach the Wanderer's current HP
# through block, the numeral gets one emphasis - a thin underline - and
# nothing else.
#
# One per enemy, created by BattleOverlay for the fight (its child, so it
# dies with the overlay - nothing of this exists on the field). Anchored
# the way EnemyStatus is: repositioned every physics tick at priority 1
# (after CameraRig/FieldEnemy have moved this tick), unprojected from the
# enemy's own head + head_margin, whole pixels, scaled by camera distance
# (DistanceScale) so it keeps its size through the battle camera swing.
# EnemyStatus's own bar hangs under the enemy's feet (bar_offset points
# down), so the two never share the head band and nothing stacks.
#
# Shown by BattleOverlay once the battle frame has settled (the camera's
# battle_transition_time), updated on every enemy_intent_changed, hidden
# on enemy_acting while the enemy resolves.

# The chip's bottom edge sits head_margin metres above the enemy's own
# head - FieldEnemy.get_head_height(), its model's scaled bbox height
# (0.58m for the Sputter) - with fallback_head_height (BattleOverlay's
# humanoid-guess enemy_head_height) only if the enemy reports 0.
@export var head_margin: float = 0.1
@export var fallback_head_height: float = 1.8
# The chip, matched to EnemyStatus's Battle Style: its battle text size
# (18) x chip_text_scale for the numeral, the same 1.3 line height, the
# same backing alpha/corner radius/padding, the same 1px outline. The
# glyph is sized to the numeral's cap height and stroked heavier to
# match its weight; it's clamped to never exceed the numeral.
@export var chip_text_size_px: int = 18
@export var chip_text_scale: float = 1.6
@export var chip_line_height_scale: float = 1.3
@export_range(0.0, 1.0) var backing_alpha: float = 0.45
@export var backing_corner_radius: int = 6
@export var backing_padding: Vector2 = Vector2(6.0, 3.0)
@export var outline_size_px: int = 1
@export var glyph_cap_scale: float = 0.7
@export var glyph_numeral_gap_px: float = 6.0
@export var glyph_line_width_px: float = 3.5
# The lethal emphasis: a line this thick under the numeral, this far
# below the text's line box.
@export var lethal_underline_px: float = 2.0
@export var lethal_underline_drop_px: float = 1.0

@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0

var target: FieldEnemy = null
var _backing: Panel = null
var _label: Label = null
# Content geometry from _apply_layout(), for _draw().
var _glyph_size: float = 0.0
var _glyph_centre: Vector2 = Vector2.ZERO
var _text_rect: Rect2 = Rect2()
var _type: int = EnemyIntent.IntentType.ATTACK
var _has_intent: bool = false
var _lethal: bool = false
# "Revealed" is the overlay's say (frame settled, not acting); the display
# is only visible when revealed AND it has something to show.
var _revealed: bool = false
var _ready_done: bool = false

func _ready() -> void:
	_ready_done = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_backing = Panel.new()
	_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_backing)
	# The theme's own font, like EnemyStatus's numbers - no override.
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(_label)

	refresh_style()
	_apply_layout()
	_update_visibility()

func set_target(enemy: FieldEnemy) -> void:
	target = enemy

# The chip's colours, from the theme's CardFace tokens exactly as
# EnemyStatus reads them: text_color ink with a panel_color outline on
# the numbers, panel_color at backing_alpha behind - so the display
# inverts with the on-pale/on-dark switch alongside the HP chip.
func refresh_style() -> void:
	if _label == null:
		return
	_label.add_theme_color_override("font_color", get_theme_color("text_color", "CardFace"))
	_label.add_theme_color_override("font_outline_color", get_theme_color("panel_color", "CardFace"))
	_label.add_theme_constant_override("outline_size", outline_size_px)

	var backing_color: Color = get_theme_color("panel_color", "CardFace")
	backing_color.a = backing_alpha
	var style := StyleBoxFlat.new()
	style.bg_color = backing_color
	style.corner_radius_top_left = backing_corner_radius
	style.corner_radius_top_right = backing_corner_radius
	style.corner_radius_bottom_right = backing_corner_radius
	style.corner_radius_bottom_left = backing_corner_radius
	style.shadow_size = 0
	_backing.add_theme_stylebox_override("panel", style)
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
	_apply_layout()
	_update_visibility()

func set_revealed(revealed: bool) -> void:
	_revealed = revealed
	_update_visibility()

func _update_visibility() -> void:
	visible = _revealed and _has_intent

# Glyph on the left, numeral on the right, on one line inside the chip
# backing; this control's size IS the chip, measured from the rendered
# text width (EnemyStatus's own _text_width() approach, not the label's
# lazily-updated minimum size) so the unproject can centre it exactly.
func _apply_layout() -> void:
	if not _ready_done:
		return
	var numeral_size: int = maxi(roundi(float(chip_text_size_px) * chip_text_scale), 1)
	_label.add_theme_font_size_override("font_size", numeral_size)
	var line_height: float = float(numeral_size) * chip_line_height_scale
	_glyph_size = minf(float(numeral_size) * glyph_cap_scale, float(numeral_size))
	var text_width: float = _text_width(numeral_size)
	var content_width: float = _glyph_size + glyph_numeral_gap_px + text_width
	var content_height: float = line_height

	size = Vector2(content_width + backing_padding.x * 2.0, content_height + backing_padding.y * 2.0)
	pivot_offset = size / 2.0
	_backing.position = Vector2.ZERO
	_backing.size = size

	_glyph_centre = Vector2(backing_padding.x + _glyph_size * 0.5, backing_padding.y + content_height * 0.5)
	_text_rect = Rect2(backing_padding.x + _glyph_size + glyph_numeral_gap_px, backing_padding.y, text_width, line_height)
	_label.position = _text_rect.position
	_label.size = _text_rect.size
	queue_redraw()

func _text_width(font_size: int) -> float:
	var font: Font = _label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# The glyph and the lethal underline, in the same ink/outline as the
# numeral: each stroke is drawn twice, outline colour wide underneath,
# ink colour on top - the line equivalent of the label's outline. A
# directional glyph (the attack chevron) points toward the Wanderer:
# _glyph_points() is built pointing screen-right and mirrored about the
# glyph's centre when the Wanderer is to the left (see _points_left()).
# The shield is symmetric and never flips.
func _draw() -> void:
	if not _has_intent:
		return
	var ink: Color = get_theme_color("text_color", "CardFace")
	var outline: Color = get_theme_color("panel_color", "CardFace")
	var glyph_centre: Vector2 = _glyph_centre
	var points: PackedVector2Array = _glyph_points(glyph_centre, _glyph_size * 0.5)
	if _type == EnemyIntent.IntentType.ATTACK and _points_left():
		for i in points.size():
			points[i] = Vector2(2.0 * glyph_centre.x - points[i].x, points[i].y)
	if points.size() >= 2:
		draw_polyline(points, outline, glyph_line_width_px + float(outline_size_px) * 2.0, true)
		draw_polyline(points, ink, glyph_line_width_px, true)

	if _lethal:
		var y: float = _text_rect.end.y + lethal_underline_drop_px
		var from := Vector2(_text_rect.position.x, y)
		var to := Vector2(_text_rect.end.x, y)
		draw_line(from, to, outline, lethal_underline_px + float(outline_size_px) * 2.0, true)
		draw_line(from, to, ink, lethal_underline_px, true)

# ATTACK: a chevron pointing right with a short shaft - an arrow, the
# action coming at you. DEFEND: an open shield - flat top, sides, a point
# at the bottom, closed. Both fit a square of half-size r about centre.
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
	return Vector3(0.0, head + head_margin, 0.0)

# Same loop as EnemyStatus._physics_process(): unproject, whole pixels,
# camera-distance scale. Also re-evaluates the chevron's direction, since
# the framing can swap sides during the battle transition.
var _pointing_left: bool = false

func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor: Vector3 = target.global_position + _anchor_offset()
	var screen_pos: Vector2 = camera.unproject_position(anchor)
	# Centred on the enemy in X, bottom edge on the anchor in Y - the chip
	# sits just above the silhouette rather than straddling the anchor.
	position = (screen_pos - Vector2(size.x / 2.0, size.y)).round()
	var distance: float = camera.global_position.distance_to(anchor)
	scale = Vector2.ONE * DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	var left: bool = _points_left()
	if left != _pointing_left:
		_pointing_left = left
		queue_redraw()
