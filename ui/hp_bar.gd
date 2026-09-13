extends Control
class_name HPBar

# The player's own HP readout - a bar with current/max beneath it,
# floating just under the Wanderer's feet in both field and battle (one
# persistent instance, living in FieldHUD - see region_field.gd's own
# set_target() call). Repositioned every physics tick via unproject, the
# same shape EnemyStatus already uses for enemies (see that script's own
# doc) - the anchor point is the Wanderer's own ground position plus
# ground_offset, not head height, so the offset points DOWN by default.
# Also scaled by camera distance each tick (see DistanceScale) so it
# reads the same relative size in the field's wide framing and battle's
# close one.
#
# Two style sets, blended over the battle transition time rather than
# snapped: field (bare bar, no backing - see the Bar group's exports) and
# battle (bigger bar, bigger numbers, a soft backing plate behind the
# numbers/Toll so they read against any ground - see the Battle Style
# group's exports). See enter_battle()/exit_battle() and _battle_blend's
# own doc.
#
# Reads RunState.player_hp/player_max_hp directly and updates on RunState.
# player_hp_changed - the only source this bar ever reads, in field or
# battle alike. In battle, BattleOverlay.enter_battle() also calls show_
# toll()/update_toll() to show a Toll reading beside the bar, on the same
# baseline as the numbers (this panel has no live Toll source of its own -
# Toll is battle-scoped, not part of RunState) and hide_toll() when the
# battle ends.
#
# Field visibility (see HoverFadeVisibility): hidden by default, fades in
# on mouse hover over the Wanderer or on any HP change (held briefly, then
# faded back out), stays visible below low_hp_fraction, and is always
# fully visible in battle (see enter_battle()/exit_battle(), called by
# BattleOverlay alongside show_toll()/hide_toll()).

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

@export_group("Toll")
@export var toll_font_size_px: int = 13
@export var toll_label_prefix: String = "Toll "
@export var toll_gap: float = 10.0

@export_group("Battle Style")
@export var battle_bar_size: Vector2 = Vector2(180.0, 8.0)
@export var battle_numbers_font_size_px: int = 18
@export var battle_toll_font_size_px: int = 16
@export_range(0.0, 1.0) var backing_alpha: float = 0.45
@export var backing_corner_radius: int = 6
@export var backing_padding: Vector2 = Vector2(6.0, 3.0)

@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0

@onready var _numbers_backing: Panel = $NumbersBacking
@onready var _bar_background: Panel = $BarBackground
@onready var _bar_fill: Panel = $BarBackground/BarFill
@onready var _numbers_label: Label = $NumbersLabel
@onready var _toll_label: Label = $TollLabel

var _wanderer: Wanderer = null
var _current_fraction: float = 1.0
var _displayed_fraction: float = 1.0
var _fraction_tween: Tween = null
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null

# 0 = field style, 1 = battle style. Tweened by enter_battle()/exit_battle()
# over the battle transition time (passed in by BattleOverlay, which reads
# it off CameraRig - see BattleOverlay.enter_battle()'s own doc), not
# snapped, so the bar's own resize reads as part of the same transition as
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
	_toll_label.visible = false

	_visibility = HoverFadeVisibility.new(self, fade_time, hp_change_hold_time)

	RunState.player_hp_changed.connect(_on_player_hp_changed)
	_current_fraction = _hp_fraction(RunState.player_hp, RunState.player_max_hp)
	_displayed_fraction = _current_fraction
	_refresh_numbers(RunState.player_hp, RunState.player_max_hp)

	_apply_layout()
	refresh_style()

# Current field/battle-blended bar size/font sizes - see _battle_blend's
# own doc.
func _blended_bar_size() -> Vector2:
	return bar_size.lerp(battle_bar_size, _battle_blend)

func _blended_numbers_font_size() -> int:
	return roundi(lerpf(float(numbers_font_size_px), float(battle_numbers_font_size_px), _battle_blend))

func _blended_toll_font_size() -> int:
	return roundi(lerpf(float(toll_font_size_px), float(battle_toll_font_size_px), _battle_blend))

# Bar+numbers only - Toll (when shown) and the numbers backing plate both
# overflow past this Control's own size without affecting it, so the bar
# never shifts when Toll appears/disappears. pivot_offset centers scale
# (see DistanceScale) on the bar's own middle rather than its top-left
# corner. Re-run on every _battle_blend/_displayed_fraction tween step
# (see their own doc), not just once - every size in here can be
# mid-transition at any given moment.
func _apply_layout() -> void:
	var current_bar_size: Vector2 = _blended_bar_size()
	var numbers_size: int = _blended_numbers_font_size()
	var toll_size: int = _blended_toll_font_size()
	var numbers_line_height: float = numbers_size * 1.3

	var content_size := Vector2(current_bar_size.x, current_bar_size.y + row_gap + numbers_line_height)
	size = content_size
	pivot_offset = content_size / 2.0

	_bar_background.position = Vector2.ZERO
	_bar_background.size = current_bar_size
	_bar_background.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bar_fill.position = Vector2.ZERO
	_bar_fill.size = Vector2(current_bar_size.x * _displayed_fraction, current_bar_size.y)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var numbers_top: float = current_bar_size.y + row_gap
	_numbers_label.position = Vector2(0.0, numbers_top)
	_numbers_label.size = Vector2(current_bar_size.x, numbers_line_height)
	_numbers_label.add_theme_font_size_override("font_size", numbers_size)
	_numbers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_numbers_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_numbers_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Same baseline as the numbers (same y), to the right of the bar's own
	# right edge - not the numbers' own (narrower, centered) box.
	_toll_label.position = Vector2(current_bar_size.x + toll_gap, numbers_top)
	_toll_label.size = Vector2(200.0, numbers_line_height)
	_toll_label.add_theme_font_size_override("font_size", toll_size)
	_toll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_toll_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toll_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	_update_backing(current_bar_size, numbers_size, toll_size, numbers_top, numbers_line_height)

# Sized to the union of the rendered numbers/Toll text (not a fixed box -
# both change length as HP/Toll change), plus backing_padding on every
# side. Alpha scales with _battle_blend directly (0 in the field, backing_
# alpha in battle) rather than being a separate visible toggle, so it
# fades in/out with the rest of the battle-style transition.
func _update_backing(current_bar_size: Vector2, numbers_size: int, toll_size: int, numbers_top: float, numbers_line_height: float) -> void:
	var numbers_width: float = _text_width(_numbers_label, numbers_size)
	var backing_left: float = (current_bar_size.x - numbers_width) / 2.0
	var backing_right: float = backing_left + numbers_width

	if _toll_label.visible:
		var toll_width: float = _text_width(_toll_label, toll_size)
		var toll_left: float = current_bar_size.x + toll_gap
		backing_right = maxf(backing_right, toll_left + toll_width)

	_numbers_backing.position = Vector2(backing_left - backing_padding.x, numbers_top - backing_padding.y)
	_numbers_backing.size = Vector2(backing_right - backing_left + backing_padding.x * 2.0, numbers_line_height + backing_padding.y * 2.0)
	_numbers_backing.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var backing_color: Color = get_theme_color("panel_color", "CardFace")
	backing_color.a = backing_alpha * _battle_blend
	var style := StyleBoxFlat.new()
	style.bg_color = backing_color
	style.corner_radius_top_left = backing_corner_radius
	style.corner_radius_top_right = backing_corner_radius
	style.corner_radius_bottom_right = backing_corner_radius
	style.corner_radius_bottom_left = backing_corner_radius
	style.shadow_size = 0
	_numbers_backing.add_theme_stylebox_override("panel", style)

func _text_width(label: Label, font_size: int) -> float:
	var font: Font = label.get_theme_font("font")
	if font == null:
		return 0.0
	return font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x

# Called once by region_field.gd - the Wanderer this bar tracks. Safe to
# call before or after _ready(); _physics_process() below just no-ops
# until it's set.
func set_target(wanderer: Wanderer) -> void:
	_wanderer = wanderer

# Re-reads this panel's theme colors - called by RegionField right after
# it applies the region's on-pale/on-dark value set to the shared
# BattleTheme resource, same "cached once, refreshed on demand" shape
# EnemyStatus/DeckPanel/CardView already use rather than tracking the
# theme resource live. Colors only - font sizes/backing geometry are
# _apply_layout()'s job (see its own doc), since those are blend-driven
# and this isn't.
func refresh_style() -> void:
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var track_color: Color = panel_light_color
	track_color.a = track_alpha
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var outline_color: Color = get_theme_color("panel_color", "CardFace")

	_bar_background.add_theme_stylebox_override("panel", _build_bar_style(track_color))
	_bar_fill.add_theme_stylebox_override("panel", _build_bar_style(text_color))

	for label: Label in [_numbers_label, _toll_label]:
		label.add_theme_color_override("font_color", text_color)
		label.add_theme_color_override("font_outline_color", outline_color)
		label.add_theme_constant_override("outline_size", outline_size)

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
	position = (screen_pos - size / 2.0).round()

	var distance: float = camera.global_position.distance_to(target_position)
	scale = Vector2.ONE * DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), _wanderer)
	var low_hp: bool = _current_fraction <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)

func _hp_fraction(current: int, max_hp: int) -> float:
	if max_hp <= 0:
		return 0.0
	return clampf(float(current) / float(max_hp), 0.0, 1.0)

func _on_player_hp_changed(current: int, max_hp: int) -> void:
	_refresh_numbers(current, max_hp)
	_current_fraction = _hp_fraction(current, max_hp)
	_tween_bar_to(_current_fraction)
	_visibility.notify_hp_changed()

func _refresh_numbers(current: int, max_hp: int) -> void:
	_numbers_label.text = "%d/%d" % [current, max_hp]

# Animates _displayed_fraction (not _bar_fill.size.x directly - see that
# var's own doc) toward `fraction` over bar_tween_time; _apply_layout(),
# called every step, is what actually applies it to the fill's width.
func _tween_bar_to(fraction: float) -> void:
	if _fraction_tween != null:
		_fraction_tween.kill()
	_fraction_tween = create_tween()
	_fraction_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fraction_tween.tween_method(_set_displayed_fraction, _displayed_fraction, fraction, bar_tween_time)

func _set_displayed_fraction(value: float) -> void:
	_displayed_fraction = value
	_apply_layout()

# Called by BattleOverlay.enter_battle()/_finish_battle() alongside show_
# toll()/hide_toll() - bypasses the field hover/hold/low-hp visibility
# rules entirely while true (see HoverFadeVisibility.update()), and
# tweens _battle_blend to/from 1 over `duration` (BattleOverlay's own
# camera_rig.battle_transition_time - see its own doc) so the bar's style
# change reads as part of the same transition as the camera swing.
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

# Called by BattleOverlay.enter_battle() - shows a Toll reading beside the
# bar. initial_toll is shown immediately; BattleController.setup() emits
# the real value synchronously right after this call returns (see Battle
# Overlay.enter_battle()'s own connect-then-setup order), so there's no
# visible stale-number frame.
func show_toll(initial_toll: int) -> void:
	_toll_label.text = toll_label_prefix + str(initial_toll)
	_toll_label.visible = true
	_apply_layout()

func update_toll(new_toll: int) -> void:
	if not _toll_label.visible:
		return
	_toll_label.text = toll_label_prefix + str(new_toll)
	_apply_layout()

func hide_toll() -> void:
	_toll_label.visible = false
	_apply_layout()
