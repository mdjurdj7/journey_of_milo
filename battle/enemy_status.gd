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

@export_group("Block Readout")
# While block is up, the card's open-shield glyph sits to the LEFT of the
# HP numeral with the block value centred on it: the value in Spectral at
# the HP numeral's own size, full ink, over a pale halo that breaks the
# shield's line wherever a digit crosses it - and free to spill past the
# shield's edges. The group's right edge stays block_hp_gap_px from the
# HP numeral; a wider value spills leftward. The readout grows leftward
# for it - the HP block stays put on the anchor.
#
# The shield's size: its height is ~1.85 x half of this, ~26 px at 28 -
# the digits' own height at 22 px (Spectral's reported line height, 35 at
# 22, is mostly descent).
@export var block_glyph_size_px: float = 28.0:
	set(value):
		block_glyph_size_px = value
		_relayout_block()
# The intent glyphs' stroke (BattleIntent.glyph_line_width_px).
@export var block_glyph_line_width_px: float = 3.5:
	set(value):
		block_glyph_line_width_px = value
		_relayout_block()
# The shield's centre sits this fraction of the HP numeral's size above
# the HP baseline - level with the numeral's cap centre.
@export var block_glyph_baseline_lift: float = 0.33:
	set(value):
		block_glyph_baseline_lift = value
		_relayout_block()
# The value's size; 0 = the HP numeral's (battle_numeral_size_px).
@export var block_value_size_px: int = 0:
	set(value):
		block_value_size_px = value
		_relayout_block()
# Two digits or more: the value at this fraction of its size - the rest
# spills past the shield.
@export_range(0.5, 1.0) var block_multi_digit_scale: float = 0.92:
	set(value):
		block_multi_digit_scale = value
		_relayout_block()
# The value's baseline sits this fraction of its size below the shield's
# centre, which centres its cap height on the shield.
@export var block_value_baseline_drop: float = 0.33:
	set(value):
		block_value_baseline_drop = value
		_relayout_block()
# The halo under the value's ink: this many px each side, in this colour
# (the bone of the screens' text) - drawn over the shield, under the ink.
@export var block_halo_px: float = 2.0:
	set(value):
		block_halo_px = value
		_relayout_block()
@export var block_halo_color: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		block_halo_color = value
		_relayout_block()
# The shield's ink alpha; the value is always full ink.
@export_range(0.0, 1.0) var block_readout_alpha: float = 0.7:
	set(value):
		block_readout_alpha = value
		_relayout_block()
@export var block_hp_gap_px: float = 16.0:
	set(value):
		block_hp_gap_px = value
		_relayout_block()
# A changed value crossfades from the old over this long.
@export var block_crossfade_time: float = 0.12

@export_group("Status Row")
# The enemy's statuses (Braced, Come Due ×3), left to right under the bar
# in battle - the same row the player's HPBar draws under its own, in the
# same type, handed ready-made labels (Status.label()). Drawn below the
# readout without growing it, so the bar never moves on the enemy when a
# status comes or goes. Nothing at all when empty.
@export var status_row_font_size_px: int = 10
@export_range(0.0, 1.0) var status_row_tracking_em: float = 0.16
@export_range(0.0, 1.0) var status_row_alpha: float = 0.7
@export var status_row_gap_px: float = 6.0
@export var status_row_item_gap_px: float = 14.0

@export_group("HP Mark")
# The one status shown beside the HP numeral instead of in the row
# (StatusData.shows_beside_hp - Coiled), set by BattleOverlay through set_
# hp_mark(): its mark, then its magnitude, hp_mark_gap_px after the " /
# max" run, on the numeral's baseline. The coil is BattleIntent's (coil_
# shapes()), hp_mark_glyph_size_px tall, centred on the numeral's cap
# centre the way the block shield is (block_glyph_baseline_lift), in the
# tapered pen: hp_mark_stroke_px, fining to hp_mark_taper, ink over a
# hp_mark_outline_px bone outline, hp_mark_edge_px of antialiased edge.
@export var hp_mark_gap_px: float = 10.0:
	set(value):
		hp_mark_gap_px = value
		queue_redraw()
@export var hp_mark_glyph_size_px: float = 16.0:
	set(value):
		hp_mark_glyph_size_px = value
		queue_redraw()
@export var hp_mark_value_gap_px: float = 3.0:
	set(value):
		hp_mark_value_gap_px = value
		queue_redraw()
@export var hp_mark_stroke_px: float = 2.4:
	set(value):
		hp_mark_stroke_px = value
		queue_redraw()
@export_range(0.0, 1.0) var hp_mark_taper: float = 0.15:
	set(value):
		hp_mark_taper = value
		queue_redraw()
@export var hp_mark_outline_px: float = 1.0:
	set(value):
		hp_mark_outline_px = value
		queue_redraw()
@export var hp_mark_edge_px: float = 1.0:
	set(value):
		hp_mark_edge_px = value
		queue_redraw()

@export_group("Status Reveal")
# Hovering the readout - name, numerals, bar and status row - in battle
# shows what each status does, one entry each, this far under the status
# row (or the bar, with no row) and wrapped at battle_width, fading in and
# out over reveal_fade_time, ink at reveal_line_alpha, in the card's rules
# type at reveal_font_size_px (the faces are StatusReveal's - see the
# "StatusReveal" child's doc).
@export var reveal_gap_px: float = 6.0:
	set(value):
		reveal_gap_px = value
		if _is_ready:
			_apply_layout()
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
# Line pitch in ems, as CardView.keyword_reveal_line_height.
@export var reveal_line_height: float = 1.28:
	set(value):
		reveal_line_height = value
		if _reveal != null:
			_reveal.set_line_height(value)
# Extra space between two statuses' entries, on top of the line pitch.
@export var reveal_entry_gap_px: float = 4.0:
	set(value):
		reveal_entry_gap_px = value
		if _reveal != null:
			_reveal.set_entry_gap_px(value)

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
# The value fading out under a crossfade (0: none), and how far the new
# one has faded in (1: done) - see set_block().
var _block_prev: int = 0
var _block_fade: float = 1.0
var _block_tween: Tween = null
var _in_battle: bool = false
var _visibility: HoverFadeVisibility = null
# Cached theme ink (see refresh_style()).
var _ink: Color = Color.BLACK
var _name_font_tracked: Font = null
var _status_font_tracked: Font = null
# The status row's labels - see set_status_row().
var _status_texts: PackedStringArray = PackedStringArray()
# The mark beside the HP and its number - see set_hp_mark(); &"" = none.
var _hp_mark_glyph: StringName = &""
var _hp_mark_value: int = 0
# What the statuses do, shown on hover - see set_reveal_lines().
var _reveal: StatusReveal = null

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
	_reveal = StatusReveal.new()
	_reveal.name = "StatusReveal"
	_reveal.set_fade_time(reveal_fade_time)
	_reveal.set_line_alpha(reveal_line_alpha)
	_reveal.set_font_size_px(reveal_font_size_px)
	_reveal.set_line_height(reveal_line_height)
	_reveal.set_entry_gap_px(reveal_entry_gap_px)
	add_child(_reveal)

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

# The block readout's width including its gap to the HP numeral - the
# HP block's own left edge; 0 while no block is up.
func _block_readout_width() -> float:
	if _block <= 0:
		return 0.0
	return _block_group_width() + block_hp_gap_px

# The group's own width: the shield's box, or the value with its halo when
# that is wider - the fading-out value's too while a crossfade runs, so
# neither ever reaches toward the HP numeral.
func _block_group_width() -> float:
	var width: float = maxf(block_glyph_size_px, _block_value_width(_block))
	if _block_prev > 0 and _block_fade < 1.0:
		width = maxf(width, _block_value_width(_block_prev))
	return width

# The value's size: the HP numeral's (or block_value_size_px), held to
# block_multi_digit_scale of it from two digits up.
func _block_value_size(value: int) -> int:
	var base: int = block_value_size_px if block_value_size_px > 0 else battle_numeral_size_px
	if str(value).length() >= 2:
		return maxi(roundi(float(base) * block_multi_digit_scale), 1)
	return base

func _block_value_width(value: int) -> float:
	return InkType.width(numeral_font, str(value), _block_value_size(value)) + maxf(block_halo_px, 0.0) * 2.0

# Shield glyph (the card's guard glyph, CardView._draw_glyph()) centred in
# the group, level with the HP numeral's cap centre, at block_readout_
# alpha; the value centred on it - the one fading out under the new one
# while a crossfade runs.
func _draw_block_readout(baseline: float, ink: Color) -> void:
	if _block <= 0:
		return
	var color: Color = ink
	color.a *= block_readout_alpha
	var r: float = block_glyph_size_px * 0.5
	var centre := Vector2(_block_group_width() * 0.5, baseline - float(battle_numeral_size_px) * block_glyph_baseline_lift)
	var shield := PackedVector2Array([
		centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
		centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
	])
	draw_polyline(shield, color, block_glyph_line_width_px, true)
	if _block_prev > 0 and _block_fade < 1.0:
		_draw_block_value(_block_prev, centre, ink, 1.0 - _block_fade)
	_draw_block_value(_block, centre, ink, _block_fade)

# One value on the shield: its halo first (over the shield's line, under
# the ink), then the ink, both at `alpha`.
func _draw_block_value(value: int, centre: Vector2, ink: Color, alpha: float) -> void:
	if alpha <= 0.0:
		return
	var text: String = str(value)
	var size_px: int = _block_value_size(value)
	var width: float = InkType.width(numeral_font, text, size_px)
	var origin := Vector2(centre.x - width * 0.5, centre.y + float(size_px) * block_value_baseline_drop)
	if block_halo_px > 0.0 and numeral_font != null:
		var halo: Color = block_halo_color
		halo.a *= alpha
		draw_string_outline(numeral_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, roundi(block_halo_px * 2.0), halo)
	var fill: Color = ink
	fill.a *= alpha
	InkType.draw_run(self, numeral_font, text, origin, size_px, fill)

func _relayout_block() -> void:
	if is_node_ready():
		_apply_layout()

func _battle_content_size() -> Vector2:
	return Vector2(_block_readout_width() + battle_width, _numeral_ascent() + _numeral_descent() + battle_row_gap + battle_bar_height)

# The point of this control that sits on the unprojected anchor (and
# that DistanceScale scales about): the field layout's centre, or the HP
# block's centre in battle - the block readout hangs off to its left,
# never shifting the bar off the enemy.
func _anchor_offset() -> Vector2:
	var field_offset: Vector2 = _field_content_size() / 2.0
	var battle_offset := Vector2(_block_readout_width() + battle_width / 2.0, _battle_content_size().y / 2.0)
	return field_offset.lerp(battle_offset, _battle_blend)

# This control's size eases between the two layouts' sizes with the
# blend (see the class doc) - pivot_offset centres scale (see
# DistanceScale) on the content's own middle rather than its top-left
# corner. Re-run on every _battle_blend tween step and every real HP
# change, not just once.
func _apply_layout() -> void:
	var content_size: Vector2 = _field_content_size().lerp(_battle_content_size(), _battle_blend)
	size = content_size
	pivot_offset = _anchor_offset()

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

	if _reveal != null:
		_reveal.position = Vector2(_block_readout_width(), _status_row_bottom() + reveal_gap_px)
		_reveal.set_wrap_width(battle_width)

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
	_draw_block_readout(baseline, ink)
	var left: float = _block_readout_width()
	var x: float = left + InkType.draw_run(self, numeral_font, str(maxi(_current_hp, 0)), Vector2(left, baseline), battle_numeral_size_px, ink)
	x += InkType.draw_run(self, numeral_font, battle_max_prefix + str(_max_hp), Vector2(x, baseline), battle_max_size_px, secondary)
	_draw_hp_mark(x, baseline, ink)

	var name_text: String = _enemy_name()
	if _name_font_tracked != null and not name_text.is_empty():
		var name_width: float = InkType.width(_name_font_tracked, name_text, battle_name_size_px)
		InkType.draw_run(self, _name_font_tracked, name_text, Vector2(left + battle_width - name_width, baseline), battle_name_size_px, secondary)

	var bar_top: float = baseline + _numeral_descent() + battle_row_gap
	draw_rect(Rect2(left, bar_top, battle_width, battle_bar_height), track)
	draw_rect(Rect2(left, bar_top, battle_width * _current_hp_fraction(), battle_bar_height), ink)

	if _block > 0 and _max_hp > 0:
		var length: float = maxf(battle_width * clampf(float(_block) / float(_max_hp), 0.0, 1.0), block_min_length_px)
		var block_top: float = bar_top - block_gap_px - block_thickness_px
		draw_rect(Rect2(left, block_top, length, block_thickness_px), ink)

	_draw_status_row(bar_top + battle_bar_height + status_row_gap_px, left)

# The mark beside the HP (see the HP Mark group), from `x` - the end of
# the " / max" run - on the numeral's baseline: the coil, then the value
# in the numeral's type at the max's size.
func _draw_hp_mark(x: float, baseline: float, ink: Color) -> void:
	if _hp_mark_glyph != &"coil":
		return
	var r: float = hp_mark_glyph_size_px * 0.5
	var centre := Vector2(x + hp_mark_gap_px + r, baseline - float(battle_numeral_size_px) * block_glyph_baseline_lift)
	InkPen.draw_ink(self, BattleIntent.coil_shapes(centre, r, hp_mark_stroke_px, hp_mark_taper), _ink, get_theme_color("bone", "Battle"), hp_mark_outline_px, hp_mark_edge_px, ink.a)
	InkType.draw_run(self, numeral_font, str(_hp_mark_value), Vector2(centre.x + r + hp_mark_value_gap_px, baseline), battle_max_size_px, ink)

func _draw_status_row(top: float, left: float) -> void:
	if _status_texts.is_empty() or _status_font_tracked == null:
		return
	var color: Color = _ink
	color.a = status_row_alpha * _battle_blend
	var baseline: float = top + _status_font_tracked.get_ascent(status_row_font_size_px)
	var x: float = left
	for text in _status_texts:
		x += InkType.draw_run(self, _status_font_tracked, text, Vector2(x, baseline), status_row_font_size_px, color)
		x += status_row_item_gap_px

# The bottom of the battle readout as drawn: the status row's, or the
# bar's with no row. The row hangs below this control's size (see its
# doc), so this can be past size.y.
func _status_row_bottom() -> float:
	return _status_row_bottom_for(not _status_texts.is_empty())

func _status_row_bottom_for(with_row: bool) -> float:
	var bottom: float = _numeral_ascent() + _numeral_descent() + battle_row_gap + battle_bar_height
	if with_row and _status_font_tracked != null:
		bottom += status_row_gap_px + _status_font_tracked.get_height(status_row_font_size_px)
	return bottom

# Where a status row's bottom sits in canvas pixels, whether or not one is
# up yet - for BattleOverlay's one-shot clearance print, which runs before
# any status lands.
func get_status_row_bottom_y() -> float:
	return (get_global_transform() * Vector2(0.0, _status_row_bottom_for(true))).y

# Whether the cursor is on the drawn readout, block shield to status row -
# polled, never a mouse event, so the targeting raycast underneath gets
# every click. A card or button under the cursor wins.
func _is_readout_hovered() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	return Rect2(0.0, 0.0, size.x, _status_row_bottom()).has_point(get_local_mouse_position())

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
	_status_font_tracked = InkType.tracked(InkType.text_bold_font(), status_row_font_size_px, status_row_tracking_em)
	_reveal.set_ink(_ink)
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
#
# A changed value crossfades from the old over block_crossfade_time - no
# pulse, no colour. Appearing and going (to or from 0) are immediate, and
# the HP numeral never moves for any of it (_anchor_offset()).
func set_block(block: int) -> void:
	var value: int = maxi(block, 0)
	if value == _block:
		return
	if _block_tween != null and _block_tween.is_valid():
		_block_tween.kill()
	var crossfade: bool = _block > 0 and value > 0 and block_crossfade_time > 0.0
	_block_prev = _block if crossfade else 0
	_block = value
	if crossfade:
		_block_fade = 0.0
		_block_tween = create_tween()
		_block_tween.tween_method(_set_block_fade, 0.0, 1.0, block_crossfade_time)
	else:
		_block_fade = 1.0
	_apply_layout()

func _set_block_fade(value: float) -> void:
	_block_fade = value
	if _block_fade >= 1.0:
		_block_prev = 0
	_apply_layout()

# Called by BattleOverlay alongside set_block(), with every active status's
# label in the order the rules hold them (empty clears the row) - battle-
# only, like the block.
func set_status_row(texts: PackedStringArray) -> void:
	_status_texts = texts
	# The row's height places the reveal under it.
	if _is_ready:
		_apply_layout()

# Called by BattleOverlay alongside set_status_row(): the status shown
# beside the HP - its mark (&"coil") and magnitude - or &"" for none.
func set_hp_mark(glyph: StringName, value: int) -> void:
	if glyph == _hp_mark_glyph and value == _hp_mark_value:
		return
	_hp_mark_glyph = glyph
	_hp_mark_value = value
	queue_redraw()

# What set_hp_mark() last put beside the HP - {"glyph", "value"}, the
# glyph &"" when nothing is there. For probes.
func get_hp_mark() -> Dictionary:
	return {"glyph": _hp_mark_glyph, "value": _hp_mark_value}

# Called by BattleOverlay alongside set_status_row(): each status's name
# and what it does now (Status.describe()), same order - the hover reveal.
func set_reveal_lines(names: PackedStringArray, lines: PackedStringArray) -> void:
	if _reveal != null:
		_reveal.set_lines(names, lines)

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
	_block_prev = 0
	_block_fade = 1.0
	_status_texts = PackedStringArray()
	if _reveal != null:
		_reveal.clear()
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

	# Under the model, wherever it stands or hovers (FieldEnemy.get_body_
	# lift()) - the body itself never leaves the sand.
	var target_position: Vector3 = target.global_position + bar_offset + Vector3.UP * target.get_body_lift()
	var screen_pos: Vector2 = camera.unproject_position(target_position)
	# Whole pixels only - a fractional Control position on a bare bar (no
	# panel background to visually absorb it) reads as shimmer/jitter on
	# thin edges, most visibly on the 1px label outline.
	position = (screen_pos - _anchor_offset()).round()

	var distance: float = camera.global_position.distance_to(target_position)
	var field_scale: float = DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	scale = Vector2.ONE * lerpf(field_scale, battle_scale, _battle_blend)

	var hovered: bool = not _in_battle and HoverRaycast.is_hovering(get_viewport(), target)
	var low_hp: bool = _current_hp_fraction() <= low_hp_fraction
	_visibility.update(delta, hovered, low_hp, _in_battle)

	# Only once the battle style is fully in - never mid-transition.
	_reveal.set_revealed(_in_battle and _battle_blend >= 1.0 and _is_readout_hovered())
