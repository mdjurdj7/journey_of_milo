extends Control
class_name EnemyStatus

# One per FieldEnemy, owned and created by FieldEnemy itself (see its own
# _ready()) and parented under RegionField.field_hud - persistent for the
# enemy's whole life, in field and battle alike, not just created/freed
# per fight the way this used to work. Repositioned every physics tick
# under the enemy's feet via unproject and, in the field, scaled by
# camera distance (see DistanceScale) - same shape HPBar uses for the
# player; in battle that scale eases to battle_scale (1.0) so the Battle
# Style's pixel sizes are what actually lands on screen.
#
# Two styles, blended over the battle transition time rather than
# snapped: field (the Bar group - a bare bar with current/max centred
# beneath it, drawn by the child Panels/Label) and battle (the Battle
# Style group - ink on the world, drawn by _draw() below: a Spectral
# numeral row with " / max" and the enemy's name on one baseline, a 3px
# ink bar beneath over an ink track, and a thin ink segment above the
# bar's left end for block, nothing boxed). The two cross-fade: the field
# children fade out as the battle drawing fades in, and this control's
# own size eases between the two layouts' sizes so the centring never
# jumps. See enter_battle()/exit_battle() and _battle_blend's own doc -
# same mechanism as HPBar.
#
# In battle, BattleOverlay reuses this same instance (via FieldEnemy.
# enemy_status - see its own doc) rather than creating a fresh one, wires
# it to BattleController's own enemy_hp_changed signal, pushes block on
# status_changed (see set_block()), and calls enter_battle()/exit_battle()
# alongside the same calls it makes on HPBar.

# Points down from the enemy's own ground position, same idea as HPBar.
# ground_offset - retune per enemy live (Remote tab) once a taller/
# shorter creature needs a different offset.
@export var bar_offset: Vector3 = Vector3(0.0, -0.45, 0.0)
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
@export var battle_width: float = 160.0
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

@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0

@onready var bar_background: Panel = $BarBackground
@onready var bar_fill: Panel = $BarBackground/BarFill
@onready var hp_label: Label = $NumbersLabel

var target: FieldEnemy
var _current_hp: int = -1
var _max_hp: int = 1
var _block: int = 0
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null
# Cached theme ink (see refresh_style()).
var _ink: Color = Color.BLACK
var _name_font_tracked: Font = null

# 0 = field style, 1 = battle style - see HPBar._battle_blend's own doc,
# same mechanism.
var _battle_blend: float = 0.0
var _blend_tween: Tween = null

# update_hp()/refresh_style() below can both be called before this node's
# own _ready() has run (FieldEnemy._spawn_enemy_status() calls update_hp()
# right after creating this instance, and RegionField._setup_field_hud()
# can call refresh_style() the same way - add_child()'s own _ready() call
# isn't guaranteed to have already resolved bar_background/bar_fill/
# hp_label by that point). _is_ready is set explicitly as the very first
# line of _ready() below, rather than trusting Node.is_node_ready()'s own
# timing relative to that same call - not worth the risk of guessing wrong
# about whether the engine's own flag is already true DURING _ready()'s
# body vs. only after it returns.
var _is_ready: bool = false

# See update_hp()'s own doc on why this exists. -1 is "nothing pending" (a
# real max_hp of 0 or less never happens - see EnemyData.max_hp's own
# default).
var _pending_current: int = -1
var _pending_max: int = -1

func _ready() -> void:
	_is_ready = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	# CameraRig has no explicit priority of its own (default 0), and neither
	# does FieldEnemy - this only has to beat that default to guarantee both
	# have already moved/repositioned the camera THIS physics tick before
	# _physics_process() below reads either one; without it, whichever of
	# the three happened to run first each tick was a coin flip, and a bar
	# reading a not-yet-updated camera is exactly what read as jitter.
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)

	_apply_layout()
	refresh_style()

	if _pending_max != -1:
		_apply_hp(_pending_current, _pending_max)

func _current_hp_fraction() -> float:
	if _max_hp <= 0:
		return 0.0
	return clampf(float(_current_hp) / float(_max_hp), 0.0, 1.0)

# --- Field layout (the child nodes) ---

func _field_content_size() -> Vector2:
	var numbers_line_height: float = numbers_font_size_px * 1.3
	return Vector2(bar_size.x, bar_size.y + row_gap + numbers_line_height)

# --- Battle layout (drawn) ---

func _numeral_ascent() -> float:
	return numeral_font.get_ascent(battle_numeral_size_px) if numeral_font != null else float(battle_numeral_size_px)

func _numeral_descent() -> float:
	return numeral_font.get_descent(battle_numeral_size_px) if numeral_font != null else 0.0

func _battle_content_size() -> Vector2:
	return Vector2(battle_width, _numeral_ascent() + _numeral_descent() + battle_row_gap + battle_bar_height)

# This control's size eases between the two layouts' sizes with the
# blend (see the class doc) - pivot_offset centres scale (see
# DistanceScale) on the content's own middle rather than its top-left
# corner. Re-run on every _battle_blend tween step and every real HP
# change, not just once.
func _apply_layout() -> void:
	var content_size: Vector2 = _field_content_size().lerp(_battle_content_size(), _battle_blend)
	size = content_size
	pivot_offset = content_size / 2.0

	var field_alpha: float = 1.0 - _battle_blend
	var numbers_line_height: float = numbers_font_size_px * 1.3

	bar_background.position = Vector2.ZERO
	bar_background.size = bar_size
	bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_background.modulate.a = field_alpha

	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(bar_size.x * _current_hp_fraction(), bar_size.y)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var numbers_top: float = bar_size.y + row_gap
	hp_label.position = Vector2(0.0, numbers_top)
	hp_label.size = Vector2(bar_size.x, numbers_line_height)
	hp_label.add_theme_font_size_override("font_size", numbers_font_size_px)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp_label.modulate.a = field_alpha

	queue_redraw()

# The battle readout, at _battle_blend alpha over the fading field nodes -
# see HPBar._draw(), same layout at this readout's own width.
func _draw() -> void:
	if _battle_blend <= 0.0 or numeral_font == null:
		return
	var ink: Color = _ink
	ink.a = _battle_blend
	var secondary: Color = _ink
	secondary.a = battle_secondary_alpha * _battle_blend
	var track: Color = _ink
	track.a = battle_track_alpha * _battle_blend

	var baseline: float = _numeral_ascent()
	var x: float = InkType.draw_run(self, numeral_font, str(maxi(_current_hp, 0)), Vector2(0.0, baseline), battle_numeral_size_px, ink)
	InkType.draw_run(self, numeral_font, battle_max_prefix + str(_max_hp), Vector2(x, baseline), battle_max_size_px, secondary)

	var name_text: String = _enemy_name()
	if _name_font_tracked != null and not name_text.is_empty():
		var name_width: float = InkType.width(_name_font_tracked, name_text, battle_name_size_px)
		InkType.draw_run(self, _name_font_tracked, name_text, Vector2(battle_width - name_width, baseline), battle_name_size_px, secondary)

	var bar_top: float = baseline + _numeral_descent() + battle_row_gap
	draw_rect(Rect2(0.0, bar_top, battle_width, battle_bar_height), track)
	draw_rect(Rect2(0.0, bar_top, battle_width * _current_hp_fraction(), battle_bar_height), ink)

	if _block > 0 and _max_hp > 0:
		var length: float = maxf(battle_width * clampf(float(_block) / float(_max_hp), 0.0, 1.0), block_min_length_px)
		var block_top: float = bar_top - block_gap_px - block_thickness_px
		draw_rect(Rect2(0.0, block_top, length, block_thickness_px), ink)

func _enemy_name() -> String:
	if target == null or not is_instance_valid(target) or target.enemy_data == null:
		return ""
	return target.enemy_data.enemy_name.to_upper()

# Re-reads this panel's theme colours - called once here at _ready() and
# again by RegionField.add_enemy_status()'s own caller (_setup_field_hud())
# once the shared BattleTheme resource's value set is actually applied,
# since this node is very likely created (see FieldEnemy._spawn_enemy_
# status()) before that ever runs - and by BattleOverlay's F2 flip. Same
# "cached once, refreshed on demand" shape HPBar/DeckPanel/CardView
# already use. A no-op if called before _ready() (bar_background/bar_fill
# still null) - safe to skip, since _ready() calls this itself once it
# actually runs. The field style keeps its CardFace tokens; the battle
# style draws with the Battle ink token.
func refresh_style() -> void:
	if not _is_ready:
		return
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var track_color: Color = panel_light_color
	track_color.a = track_alpha
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var outline_color: Color = get_theme_color("panel_color", "CardFace")

	bar_background.add_theme_stylebox_override("panel", _build_bar_style(track_color))
	bar_fill.add_theme_stylebox_override("panel", _build_bar_style(text_color))

	hp_label.add_theme_color_override("font_color", text_color)
	hp_label.add_theme_color_override("font_outline_color", outline_color)
	hp_label.add_theme_constant_override("outline_size", outline_size)

	_ink = get_theme_color("ink", "Battle")
	_name_font_tracked = InkType.tracked(name_font, battle_name_size_px, battle_name_tracking_em)
	queue_redraw()

func _build_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = bar_corner_radius
	style.corner_radius_top_right = bar_corner_radius
	style.corner_radius_bottom_right = bar_corner_radius
	style.corner_radius_bottom_left = bar_corner_radius
	style.shadow_size = 0
	return style

func set_target(field_enemy: FieldEnemy) -> void:
	target = field_enemy

# Safe to call before this node has entered the tree (see _pending_
# current/_pending_max's own doc) - defers to _ready() in that case rather
# than touching hp_label/bar_background/bar_fill while they're still null.
func update_hp(current: int, max_hp: int) -> void:
	if not _is_ready:
		_pending_current = current
		_pending_max = max_hp
		return
	_apply_hp(current, max_hp)

# _current_hp starts at the -1 sentinel ("never set") - the very first
# real call (FieldEnemy's own field-mode seed at spawn, or battle setup()'s
# own initial full-HP emit right after) never counts as a "change" worth
# revealing the bar for, only a real move away from whatever it was
# already showing does.
func _apply_hp(current: int, max_hp: int) -> void:
	var changed: bool = _current_hp != -1 and current != _current_hp
	_current_hp = current
	_max_hp = max_hp

	hp_label.text = "%d/%d" % [current, max_hp]
	_apply_layout()

	if changed:
		_visibility.notify_hp_changed()

# Called by BattleOverlay on the controller's status_changed with this
# enemy's current block (0 clears the segment) - battle-only; the field
# style never shows it.
func set_block(block: int) -> void:
	_block = maxi(block, 0)
	queue_redraw()

# Called by BattleOverlay when this enemy's fight starts/ends (see its own
# _create_enemy_statuses()/_finish_battle()) - bypasses the field hover/
# hold/low-hp visibility rules entirely while true (see HoverFadeVisibility
# .update()), and tweens _battle_blend to/from 1 over `duration`
# (BattleOverlay's own camera_rig.battle_transition_time) so the bar's
# style change reads as part of the same transition as the camera swing.
func enter_battle(duration: float) -> void:
	_in_battle = true
	_tween_battle_blend(1.0, duration)

func exit_battle(duration: float) -> void:
	_in_battle = false
	_block = 0
	_tween_battle_blend(0.0, duration)

func _tween_battle_blend(target_blend: float, duration: float) -> void:
	if _blend_tween != null:
		_blend_tween.kill()
	if duration <= 0.0:
		_set_battle_blend(target_blend)
		return
	_blend_tween = create_tween()
	_blend_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_blend_tween.tween_method(_set_battle_blend, _battle_blend, target_blend, duration)

func _set_battle_blend(value: float) -> void:
	_battle_blend = value
	_apply_layout()

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var target_position: Vector3 = target.global_position + bar_offset
	var screen_pos: Vector2 = camera.unproject_position(target_position)
	# Whole pixels only - a fractional Control position on a bare bar (no
	# panel background to visually absorb it) reads as shimmer/jitter on
	# thin edges, most visibly on the 1px label outline.
	position = (screen_pos - size / 2.0).round()

	var distance: float = camera.global_position.distance_to(target_position)
	var field_scale: float = DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	scale = Vector2.ONE * lerpf(field_scale, battle_scale, _battle_blend)

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), target)
	var low_hp: bool = _current_hp_fraction() <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)
