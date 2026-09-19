extends Control
class_name HPBar

# The player's own HP readout, floating just under the Wanderer's feet in
# both field and battle (one persistent instance, living in FieldHUD -
# see region_field.gd's own set_target() call). Repositioned every physics
# tick via unproject, the same shape EnemyStatus already uses for enemies
# (see that script's own doc) - the anchor point is the Wanderer's own
# ground position plus ground_offset, not head height, so the offset
# points DOWN by default. In the field it's also scaled by camera distance
# each tick (see DistanceScale) so it reads the same relative size across
# the field's framing; in battle that scale eases to battle_scale (1.0)
# so the Battle Style's pixel sizes are what actually lands on screen.
#
# Two styles, blended over the battle transition time rather than
# snapped: field (the Bar group - a bare bar with current/max centred
# beneath it, drawn by the child Panels/Label) and battle (the Battle
# Style group - ink on the world, drawn by _draw() below: a Spectral
# numeral row with " / max" and the character's name on one baseline, a
# 3px ink bar beneath over an ink track, a thin ink segment above the
# bar's left end for block, and - while show_toll() has it on - a Toll
# block off the bar's right end: a Spectral numeral with "TOLL" beside it
# on one baseline and a rule in the toll keyline colour beneath, sitting
# on the HP bar's own rows; nothing boxed). The two cross-fade: the field
# children fade out as the battle drawing fades in, and this control's
# own size eases between the two layouts' sizes; the HP block stays
# centred on the anchor in both, with Toll hanging off to the right (see
# _anchor_offset()). See enter_battle()/exit_battle() and _battle_blend's
# own doc.
#
# Reads RunState.player_hp/player_max_hp directly and updates on RunState.
# player_hp_changed - the only HP source this bar ever reads, in field or
# battle alike. Block is battle-only, pushed by BattleOverlay on the
# controller's status_changed (see set_block()); so is Toll, shown by
# show_toll()/update_toll() and taken off by hide_toll() (BattleOverlay's
# enter/finish), with a short pop of the numeral on every change.
#
# Field visibility (see HoverFadeVisibility): hidden by default, fades in
# on mouse hover over the Wanderer or on any HP change (held briefly, then
# faded back out), stays visible below low_hp_fraction, and is always
# fully visible in battle (see enter_battle()/exit_battle()).

@export var ground_offset: Vector3 = Vector3(0.0, -0.45, 0.0)
@export var bar_tween_time: float = 0.25
@export var fade_time: float = 0.15
@export var hp_change_hold_time: float = 1.5
@export_range(0.0, 1.0) var low_hp_fraction: float = 0.3

@export_group("Bar")
@export var bar_size: Vector2 = Vector2(110.0, 5.0)
@export var bar_corner_radius: int = 2
@export_range(0.0, 1.0) var track_alpha: float = 0.6
@export var row_gap: float = 4.0
@export var numbers_font_size_px: int = 13
@export var outline_size: int = 1

@export_group("Battle Style")
# The readout's width - numeral row and bar alike.
@export var battle_width: float = 190.0
@export var numeral_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")
@export var name_font: Font = load("res://assets/fonts/AlegreyaSans-Bold.ttf")
@export var battle_numeral_size_px: int = 22
@export var battle_max_size_px: int = 14
@export var battle_name_size_px: int = 10
@export var battle_name_tracking_em: float = 0.16
# " / max" and the name, ink at this alpha; the numeral is full ink.
@export_range(0.0, 1.0) var battle_secondary_alpha: float = 0.6
@export var battle_max_prefix: String = " / "
# Row gap between the numeral row's descent and the bar's top - the block
# segment lives inside it (see block_thickness_px/block_gap_px).
@export var battle_row_gap: float = 6.0
@export var battle_bar_height: float = 3.0
@export_range(0.0, 1.0) var battle_track_alpha: float = 0.22
# Block: a segment this thick, this far above the bar's top, from the
# bar's left end, block/max_hp of the bar's width (never shorter than
# block_min_length_px while any block is up).
@export var block_thickness_px: float = 2.0
@export var block_gap_px: float = 2.0
@export var block_min_length_px: float = 6.0
@export var battle_scale: float = 1.0

@export_group("Block Readout")
# While block is up, the card's open-shield glyph with the block value
# centred inside it sits to the LEFT of the HP numeral, both ink at
# block_readout_alpha, block_hp_gap_px before the numeral. The readout
# grows leftward for it - the HP block stays put on the anchor.
@export var block_glyph_size_px: float = 24.0
@export var block_glyph_line_width_px: float = 1.5
# The shield's centre sits this fraction of the HP numeral's size above
# the HP baseline - level with the numeral's cap centre.
@export var block_glyph_baseline_lift: float = 0.33
@export var block_value_size_px: int = 13
# The value's baseline sits this fraction of its size below the shield's
# centre, which centres its cap height on the shield.
@export var block_value_baseline_drop: float = 0.33
@export_range(0.0, 1.0) var block_readout_alpha: float = 0.7
@export var block_hp_gap_px: float = 16.0

@export_group("Toll")
@export var toll_label_text: String = "TOLL"
@export var toll_numeral_size_px: int = 30
@export var toll_label_size_px: int = 10
@export var toll_label_tracking_em: float = 0.16
# Space between the HP bar's right end and the block, between numeral and
# label, and between the numeral's baseline and the rule's top. The rule
# is toll_rule_px thick and sits on the HP bar's own rows (same top).
@export var toll_gap_px: float = 22.0
@export var toll_label_gap_px: float = 6.0
@export var toll_rule_gap_px: float = 4.0
@export var toll_rule_px: float = 3.0
@export var toll_pop_scale: float = 1.15
@export var toll_pop_time: float = 0.22

@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0

@onready var _bar_background: Panel = $BarBackground
@onready var _bar_fill: Panel = $BarBackground/BarFill
@onready var _numbers_label: Label = $NumbersLabel

var _wanderer: Wanderer = null
var _current_hp: int = 0
var _max_hp: int = 1
var _block: int = 0
var _toll: int = 0
var _toll_visible: bool = false
var _toll_pop: float = 1.0
var _pop_tween: Tween = null
var _toll_rule_color: Color = Color.WHITE
var _toll_label_tracked: Font = null
var _current_fraction: float = 1.0
var _displayed_fraction: float = 1.0
var _fraction_tween: Tween = null
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null
# Cached theme ink/bone (see refresh_style()).
var _ink: Color = Color.BLACK
var _name_font_tracked: Font = null

# 0 = field style, 1 = battle style. Tweened by enter_battle()/exit_battle()
# over the battle transition time (passed in by BattleOverlay, which reads
# it off CameraRig - see BattleOverlay.enter_battle()'s own doc), not
# snapped, so the style change reads as part of the same transition as
# the camera swing and the Wanderer's stance step rather than a separate,
# independent pop. Every relayout (_apply_layout()) reads this fresh, so
# a mid-transition HP change (its own independent _displayed_fraction
# tween - see that var's own doc) composes correctly instead of the two
# tweens fighting over the fill's width.
var _battle_blend: float = 0.0
var _blend_tween: Tween = null

func _ready() -> void:
	# FieldHUD (this panel's parent) already sets PROCESS_MODE_ALWAYS, so
	# this is inherited already - set explicitly anyway so _physics_process()
	# below is guaranteed to keep tracking the Wanderer through RegionField's
	# own battle-contact freeze (including the stance-tween-in step)
	# regardless of where this node ever ends up parented.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# CameraRig has no explicit priority of its own (default 0), and neither
	# does Wanderer - this only has to beat that default to guarantee both
	# have already moved/repositioned the camera THIS physics tick before
	# _physics_process() below reads either one; without it, whichever of
	# the three happened to run first each tick was a coin flip, and a bar
	# reading a not-yet-updated camera is exactly what read as jitter.
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)

	RunState.player_hp_changed.connect(_on_player_hp_changed)
	_current_hp = RunState.player_hp
	_max_hp = RunState.player_max_hp
	_current_fraction = _hp_fraction(_current_hp, _max_hp)
	_displayed_fraction = _current_fraction
	_refresh_numbers(_current_hp, _max_hp)

	_apply_layout()
	refresh_style()

# --- Field layout (the child nodes) ---

func _field_content_size() -> Vector2:
	var numbers_line_height: float = numbers_font_size_px * 1.3
	return Vector2(bar_size.x, bar_size.y + row_gap + numbers_line_height)

# --- Battle layout (drawn) ---

func _numeral_ascent() -> float:
	return numeral_font.get_ascent(battle_numeral_size_px) if numeral_font != null else float(battle_numeral_size_px)

func _numeral_descent() -> float:
	return numeral_font.get_descent(battle_numeral_size_px) if numeral_font != null else 0.0

func _toll_ascent() -> float:
	return numeral_font.get_ascent(toll_numeral_size_px) if numeral_font != null else float(toll_numeral_size_px)

func _toll_block_width() -> float:
	return InkType.width(numeral_font, str(_toll), toll_numeral_size_px) + toll_label_gap_px + InkType.width(_toll_label_tracked, toll_label_text, toll_label_size_px)

# The Toll numeral is taller than the HP row above the bar; whatever it
# needs beyond that pushes the whole battle drawing down by this much so
# nothing pokes above the control.
func _battle_top_pad() -> float:
	if not _toll_visible:
		return 0.0
	var hp_rows: float = _numeral_ascent() + _numeral_descent() + battle_row_gap
	return maxf(0.0, _toll_ascent() + toll_rule_gap_px - hp_rows)

func _battle_bar_top() -> float:
	return _battle_top_pad() + _numeral_ascent() + _numeral_descent() + battle_row_gap

# The block readout's width including its gap to the HP numeral - the
# HP block's own left edge; 0 while no block is up.
func _block_readout_width() -> float:
	if _block <= 0:
		return 0.0
	return block_glyph_size_px + block_hp_gap_px

# Shield glyph (the card's guard glyph, CardView._draw_glyph()) with the
# value centred inside it, level with the HP numeral's cap centre.
func _draw_block_readout(baseline: float, ink: Color) -> void:
	if _block <= 0:
		return
	var color: Color = ink
	color.a *= block_readout_alpha
	var r: float = block_glyph_size_px * 0.5
	var centre := Vector2(r, baseline - float(battle_numeral_size_px) * block_glyph_baseline_lift)
	var shield := PackedVector2Array([
		centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
		centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
	])
	draw_polyline(shield, color, block_glyph_line_width_px, true)
	var value_text: String = str(_block)
	var value_width: float = InkType.width(numeral_font, value_text, block_value_size_px)
	var value_origin := Vector2(centre.x - value_width * 0.5, centre.y + float(block_value_size_px) * block_value_baseline_drop)
	InkType.draw_run(self, numeral_font, value_text, value_origin, block_value_size_px, color)

func _battle_content_size() -> Vector2:
	var width: float = _block_readout_width() + battle_width
	if _toll_visible:
		width += toll_gap_px + _toll_block_width()
	return Vector2(width, _battle_bar_top() + battle_bar_height)

# The point of this control that sits on the unprojected anchor (and
# that DistanceScale scales about): the field layout's centre, or the HP
# block's centre in battle - Toll hangs off to the right of it, never
# shifting the bar off the Wanderer.
func _anchor_offset() -> Vector2:
	var field_offset: Vector2 = _field_content_size() / 2.0
	var battle_offset := Vector2(_block_readout_width() + battle_width / 2.0, _battle_content_size().y / 2.0)
	return field_offset.lerp(battle_offset, _battle_blend)

# This control's size eases between the two layouts' sizes with the
# blend (see the class doc) - pivot_offset centres scale (see
# DistanceScale) on the content's own middle rather than its top-left
# corner. Re-run on every _battle_blend/_displayed_fraction tween step
# (see their own doc), not just once.
func _apply_layout() -> void:
	var content_size: Vector2 = _field_content_size().lerp(_battle_content_size(), _battle_blend)
	size = content_size
	pivot_offset = _anchor_offset()

	var field_alpha: float = 1.0 - _battle_blend
	var numbers_line_height: float = numbers_font_size_px * 1.3

	_bar_background.position = Vector2.ZERO
	_bar_background.size = bar_size
	_bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_background.modulate.a = field_alpha

	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(bar_size.x * _displayed_fraction, bar_size.y)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var numbers_top: float = bar_size.y + row_gap
	_numbers_label.position = Vector2(0.0, numbers_top)
	_numbers_label.size = Vector2(bar_size.x, numbers_line_height)
	_numbers_label.add_theme_font_size_override("font_size", numbers_font_size_px)
	_numbers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numbers_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numbers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_numbers_label.modulate.a = field_alpha

	queue_redraw()

# The battle readout, at _battle_blend alpha over the fading field nodes.
# One baseline for the row: numeral, then " / max" run on at its smaller
# size, the name right-aligned at the readout's width. The bar sits
# battle_row_gap under the numeral's descent; block is the thin segment
# in that gap, off the bar's left end.
func _draw() -> void:
	if _battle_blend <= 0.0 or numeral_font == null:
		return
	var ink: Color = _ink
	ink.a = _battle_blend
	var secondary: Color = _ink
	secondary.a = battle_secondary_alpha * _battle_blend
	var track: Color = _ink
	track.a = battle_track_alpha * _battle_blend

	var baseline: float = _battle_top_pad() + _numeral_ascent()
	_draw_block_readout(baseline, ink)
	var left: float = _block_readout_width()
	var x: float = left + InkType.draw_run(self, numeral_font, str(_current_hp), Vector2(left, baseline), battle_numeral_size_px, ink)
	InkType.draw_run(self, numeral_font, battle_max_prefix + str(_max_hp), Vector2(x, baseline), battle_max_size_px, secondary)

	var name_text: String = _character_name()
	if _name_font_tracked != null and not name_text.is_empty():
		var name_width: float = InkType.width(_name_font_tracked, name_text, battle_name_size_px)
		InkType.draw_run(self, _name_font_tracked, name_text, Vector2(left + battle_width - name_width, baseline), battle_name_size_px, secondary)

	var bar_top: float = _battle_bar_top()
	draw_rect(Rect2(left, bar_top, battle_width, battle_bar_height), track)
	draw_rect(Rect2(left, bar_top, battle_width * _displayed_fraction, battle_bar_height), ink)

	if _block > 0 and _max_hp > 0:
		var length: float = maxf(battle_width * clampf(float(_block) / float(_max_hp), 0.0, 1.0), block_min_length_px)
		var block_top: float = bar_top - block_gap_px - block_thickness_px
		draw_rect(Rect2(left, block_top, length, block_thickness_px), ink)

	if _toll_visible:
		_draw_toll(bar_top, ink)

# The Toll block, off the bar's right end: numeral and "TOLL" on one
# baseline toll_rule_gap_px above the rule, the rule on the bar's rows,
# as wide as the block. The numeral pops about its baseline-left corner
# on a change so the label and rule hold still.
func _draw_toll(bar_top: float, ink: Color) -> void:
	var left: float = _block_readout_width() + battle_width + toll_gap_px
	var baseline: float = bar_top - toll_rule_gap_px
	var numeral_text: String = str(_toll)
	var numeral_width: float = InkType.width(numeral_font, numeral_text, toll_numeral_size_px)
	if _toll_pop != 1.0:
		draw_set_transform(Vector2(left, baseline), 0.0, Vector2.ONE * _toll_pop)
		InkType.draw_run(self, numeral_font, numeral_text, Vector2.ZERO, toll_numeral_size_px, ink)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		InkType.draw_run(self, numeral_font, numeral_text, Vector2(left, baseline), toll_numeral_size_px, ink)
	InkType.draw_run(self, _toll_label_tracked, toll_label_text, Vector2(left + numeral_width + toll_label_gap_px, baseline), toll_label_size_px, ink)
	var rule_color: Color = _toll_rule_color
	rule_color.a = _battle_blend
	draw_rect(Rect2(left, bar_top, _toll_block_width(), toll_rule_px), rule_color)

func _character_name() -> String:
	if RunState.character == null:
		return ""
	return RunState.character.character_name.to_upper()

# Called once by region_field.gd - the Wanderer this bar tracks. Safe to
# call before or after _ready(); _physics_process() below just no-ops
# until it's set.
func set_target(wanderer: Wanderer) -> void:
	_wanderer = wanderer

# Re-reads this panel's theme colours - called by RegionField right after
# it applies the region's on-pale/on-dark value set to the shared
# BattleTheme resource (and by BattleOverlay's F2 flip), same "cached
# once, refreshed on demand" shape EnemyStatus/DeckPanel/CardView already
# use rather than tracking the theme resource live. The field style keeps
# its CardFace tokens; the battle style draws with the Battle ink token.
func refresh_style() -> void:
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var track_color: Color = panel_light_color
	track_color.a = track_alpha
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var outline_color: Color = get_theme_color("panel_color", "CardFace")

	_bar_background.add_theme_stylebox_override("panel", _build_bar_style(track_color))
	_bar_fill.add_theme_stylebox_override("panel", _build_bar_style(text_color))

	_numbers_label.add_theme_color_override("font_color", text_color)
	_numbers_label.add_theme_color_override("font_outline_color", outline_color)
	_numbers_label.add_theme_constant_override("outline_size", outline_size)

	_ink = get_theme_color("ink", "Battle")
	_toll_rule_color = get_theme_color("toll_rule", "Battle")
	_name_font_tracked = InkType.tracked(name_font, battle_name_size_px, battle_name_tracking_em)
	_toll_label_tracked = InkType.tracked(name_font, toll_label_size_px, toll_label_tracking_em)
	_apply_layout()

func _build_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = bar_corner_radius
	style.corner_radius_top_right = bar_corner_radius
	style.corner_radius_bottom_right = bar_corner_radius
	style.corner_radius_bottom_left = bar_corner_radius
	style.shadow_size = 0
	return style

func _physics_process(delta: float) -> void:
	if _wanderer == null or not is_instance_valid(_wanderer):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var target_position: Vector3 = _wanderer.global_position + ground_offset
	var screen_pos: Vector2 = camera.unproject_position(target_position)
	# Whole pixels only - a fractional Control position on a bare bar (no
	# panel background to visually absorb it) reads as shimmer/jitter on
	# thin edges, most visibly on the 1px label outline.
	position = (screen_pos - _anchor_offset()).round()

	var distance: float = camera.global_position.distance_to(target_position)
	var field_scale: float = DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	scale = Vector2.ONE * lerpf(field_scale, battle_scale, _battle_blend)

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), _wanderer)
	var low_hp: bool = _current_fraction <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)

func _hp_fraction(current: int, max_hp: int) -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(current) / float(max_hp), 0.0, 1.0)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	_current_hp = current
	_max_hp = max_hp
	_refresh_numbers(current, max_hp)
	_current_fraction = _hp_fraction(current, max_hp)
	_tween_bar_to(_current_fraction)
	_visibility.notify_hp_changed()

func _refresh_numbers(current: int, max_hp: int) -> void:
	_numbers_label.text = "%d/%d" % [current, max_hp]
	queue_redraw()

# Animates _displayed_fraction (not the fill's width directly - see that
# var's own doc) toward `fraction` over bar_tween_time; _apply_layout(),
# called every step, is what actually applies it to both bars' fills.
func _tween_bar_to(fraction: float) -> void:
	if _fraction_tween != null:
		_fraction_tween.kill()
	_fraction_tween = create_tween()
	_fraction_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fraction_tween.tween_method(_set_displayed_fraction, _displayed_fraction, fraction, bar_tween_time)

func _set_displayed_fraction(value: float) -> void:
	_displayed_fraction = value
	_apply_layout()

# Called by BattleOverlay on the controller's status_changed with the
# player's current block (0 clears the segment) - battle-only; the field
# style never shows it.
func set_block(block: int) -> void:
	_block = maxi(block, 0)
	_apply_layout()

# Called by BattleOverlay.enter_battle()/_finish_battle() - bypasses the
# field hover/hold/low-hp visibility rules entirely while true (see
# HoverFadeVisibility.update()), and tweens _battle_blend to/from 1 over
# `duration` (BattleOverlay's own camera_rig.battle_transition_time - see
# its own doc) so the style change reads as part of the same transition
# as the camera swing.
func enter_battle(duration: float) -> void:
	_in_battle = true
	_tween_battle_blend(1.0, duration)

func exit_battle(duration: float) -> void:
	_in_battle = false
	_block = 0
	_tween_battle_blend(0.0, duration)

# Called by BattleOverlay.enter_battle() - puts the Toll block on. The
# initial value shows immediately; BattleController.setup() emits the
# real one synchronously right after (see BattleOverlay.enter_battle()'s
# own connect-then-setup order), so there's no stale-number frame.
func show_toll(initial_toll: int) -> void:
	_toll = maxi(initial_toll, 0)
	_toll_visible = true
	_apply_layout()

func update_toll(new_toll: int) -> void:
	if not _toll_visible:
		return
	var changed: bool = new_toll != _toll
	_toll = maxi(new_toll, 0)
	if changed:
		_pop_toll()
	_apply_layout()

func hide_toll() -> void:
	_toll_visible = false
	if _pop_tween != null:
		_pop_tween.kill()
	_toll_pop = 1.0
	_apply_layout()

func _pop_toll() -> void:
	if _pop_tween != null:
		_pop_tween.kill()
	_pop_tween = create_tween()
	_pop_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_pop_tween.tween_method(_set_toll_pop, 1.0, toll_pop_scale, toll_pop_time * 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_pop_tween.tween_method(_set_toll_pop, toll_pop_scale, 1.0, toll_pop_time * 0.6).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func _set_toll_pop(value: float) -> void:
	_toll_pop = value
	queue_redraw()

func _tween_battle_blend(target: float, duration: float) -> void:
	if _blend_tween != null:
		_blend_tween.kill()
	if duration <= 0.0:
		_set_battle_blend(target)
		return
	_blend_tween = create_tween()
	_blend_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_blend_tween.tween_method(_set_battle_blend, _battle_blend, target, duration)

func _set_battle_blend(value: float) -> void:
	_battle_blend = value
	_apply_layout()
