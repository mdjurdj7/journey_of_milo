extends Control
class_name EnemyStatus

# One per FieldEnemy, owned and created by FieldEnemy itself (see its own
# _ready()) and parented under RegionField.field_hud - persistent for the
# enemy's whole life, in field and battle alike, not just created/freed
# per fight the way this used to work. A bar with current/max beneath it
# (no "HP" prefix - Toll doesn't apply here so there's nothing else on
# this row to distinguish it from), repositioned every physics tick under
# the enemy's feet via unproject and scaled by camera distance (see
# DistanceScale) - same shape HPBar uses for the player.
#
# Two style sets, blended over the battle transition time rather than
# snapped: field (bare bar, no backing) and battle (bigger bar, bigger
# numbers, a soft backing plate behind the numbers so they read against
# any ground - see the Battle Style group's exports). See enter_battle()/
# exit_battle() and _battle_blend's own doc - same mechanism as HPBar,
# just without a Toll reading (enemies don't have Toll).
#
# In battle, BattleOverlay reuses this same instance (via FieldEnemy.
# enemy_status - see its own doc) rather than creating a fresh one, wires
# it to BattleController's own enemy_hp_changed signal, and calls enter_
# battle()/exit_battle() alongside the same calls it makes on HPBar.
#
# No reserved space for a future intent icon this pass (the old panel-
# based layout's IntentSlot placeholder is gone with the panel itself) -
# revisit alongside whatever adds one.

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
@export var battle_bar_size: Vector2 = Vector2(180.0, 8.0)
@export var battle_numbers_font_size_px: int = 18
@export_range(0.0, 1.0) var backing_alpha: float = 0.45
@export var backing_corner_radius: int = 6
@export var backing_padding: Vector2 = Vector2(6.0, 3.0)

@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0

@onready var numbers_backing: Panel = $NumbersBacking
@onready var bar_background: Panel = $BarBackground
@onready var bar_fill: Panel = $BarBackground/BarFill
@onready var hp_label: Label = $NumbersLabel

var target: FieldEnemy
var _current_hp: int = -1
var _max_hp: int = 1
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null

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

func _blended_bar_size() -> Vector2:
	return bar_size.lerp(battle_bar_size, _battle_blend)

func _blended_numbers_font_size() -> int:
	return roundi(lerpf(float(numbers_font_size_px), float(battle_numbers_font_size_px), _battle_blend))

func _current_hp_fraction() -> float:
	if _max_hp <= 0:
		return 0.0
	return clampf(float(_current_hp) / float(_max_hp), 0.0, 1.0)

# Bar+numbers bounding size only, same as HPBar's own _apply_layout() -
# pivot_offset centers scale (see DistanceScale) on the bar's own middle
# rather than its top-left corner. Re-run on every _battle_blend tween
# step and every real HP change, not just once - every size in here can
# be mid-transition at any given moment.
func _apply_layout() -> void:
	var current_bar_size: Vector2 = _blended_bar_size()
	var numbers_size: int = _blended_numbers_font_size()
	var numbers_line_height: float = numbers_size * 1.3

	var content_size := Vector2(current_bar_size.x, current_bar_size.y + row_gap + numbers_line_height)
	size = content_size
	pivot_offset = content_size / 2.0

	bar_background.position = Vector2.ZERO
	bar_background.size = current_bar_size
	bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(current_bar_size.x * _current_hp_fraction(), current_bar_size.y)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var numbers_top: float = current_bar_size.y + row_gap
	hp_label.position = Vector2(0.0, numbers_top)
	hp_label.size = Vector2(current_bar_size.x, numbers_line_height)
	hp_label.add_theme_font_size_override("font_size", numbers_size)
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_update_backing(current_bar_size, numbers_size, numbers_top, numbers_line_height)

# Sized to the rendered numbers text (not a fixed box - it changes length
# as HP changes), plus backing_padding on every side. Alpha scales with
# _battle_blend directly (0 in the field, backing_alpha in battle) rather
# than being a separate visible toggle, so it fades in/out with the rest
# of the battle-style transition.
func _update_backing(current_bar_size: Vector2, numbers_size: int, numbers_top: float, numbers_line_height: float) -> void:
	var numbers_width: float = _text_width(hp_label, numbers_size)
	var backing_left: float = (current_bar_size.x - numbers_width) / 2.0

	numbers_backing.position = Vector2(backing_left - backing_padding.x, numbers_top - backing_padding.y)
	numbers_backing.size = Vector2(numbers_width + backing_padding.x * 2.0, numbers_line_height + backing_padding.y * 2.0)
	numbers_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backing_color: Color = get_theme_color("panel_color", "CardFace")
	backing_color.a = backing_alpha * _battle_blend
	var style := StyleBoxFlat.new()
	style.bg_color = backing_color
	style.corner_radius_top_left = backing_corner_radius
	style.corner_radius_top_right = backing_corner_radius
	style.corner_radius_bottom_right = backing_corner_radius
	style.corner_radius_bottom_left = backing_corner_radius
	style.shadow_size = 0
	numbers_backing.add_theme_stylebox_override("panel", style)

func _text_width(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# Re-reads this panel's theme colors - called once here at _ready() and
# again by RegionField.add_enemy_status()'s own caller (_setup_field_hud())
# once the shared BattleTheme resource's value set is actually applied,
# since this node is very likely created (see FieldEnemy._spawn_enemy_
# status()) before that ever runs - same "cached once, refreshed on
# demand" shape HPBar/DeckPanel/CardView already use. A no-op if called
# before _ready() (bar_background/bar_fill still null) - safe to skip,
# since _ready() calls this itself once it actually runs. Colors only -
# font size/backing geometry are _apply_layout()'s job (see its own doc),
# since those are blend-driven and this isn't.
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
	_tween_battle_blend(0.0, duration)

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
	scale = Vector2.ONE * DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), target)
	var low_hp: bool = _current_hp_fraction() <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)
