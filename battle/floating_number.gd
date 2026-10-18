extends Label
class_name FloatingNumber

# A rising number over the body it happened to - BattleOverlay spawns one
# for each damage_dealt, combat_text (heal, Block), a hit a block took
# whole and a Toll gain; RegionField one for the keepsake's win heal.
# `kind` (KIND_*) says which, and what it reads as (text_for()).
#
# Its life (show_value()): it pops in at pop_scale about its own centre and
# settles to 1 over pop_time_sec - shown in the frame its hit's stop
# starts, the stop's own beat - holds still and fully legible for
# hold_sec, then rises rise_px as it fades out over fade_sec, and frees
# itself. Each one lands up to jitter_px to either side of where it was
# put, at random, and keeps the offset it drew (`jitter`) for whoever
# needs the spot it was put at.
#
# Its look is fixed, not the theme's: a light fill inside a heavy dark
# outline (outline_size_px), so it reads on pale sand and on a dark body
# alike. Each kind has its fill and its size (a multiple of its
# placement's own size_multiplier): damage dealt bone; HP the Wanderer
# lost muted oxblood with a minus; his own HP cost the same, smaller;
# healing muted sage with a plus; Toll gained the Toll keyline with a
# plus. Block gained and BLOCKED are the other way round - ink inside a
# bone outline: Block's value after a shield glyph (HPBar's own), BLOCKED
# in Spectral's small caps. Muted, no glow.

const FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"

# Damage dealt to an enemy; HP an enemy's hit (or a tick) took from the
# Wanderer; HP his own effect took; HP back; Block gained; a hit a block
# took whole; Toll gained.
const KIND_DAMAGE := "damage"
const KIND_HP_LOST := "hp_lost"
const KIND_SELF := "self"
const KIND_HEAL := "heal"
const KIND_BLOCK := "block"
const KIND_BLOCKED := "blocked"
const KIND_TOLL := "toll"

@export_group("Motion")
@export var pop_scale: float = 1.5
@export var pop_time_sec: float = 0.1
@export var hold_sec: float = 0.5
@export var rise_px: float = 40.0
@export var fade_sec: float = 0.4
# The most it lands to either side of where it was put, in pixels.
@export var jitter_px: float = 14.0

@export_group("Type")
@export var font_size_px: int = 40
@export var outline_size_px: int = 14
@export var self_size: float = 0.75
@export var block_size: float = 0.8
@export var blocked_size: float = 0.7
@export var toll_size: float = 0.75

@export_group("Colours")
@export var ink_color: Color = Color(0.165, 0.165, 0.18, 1.0)
@export var bone_color: Color = Color(0.94, 0.91, 0.86, 1.0)
@export var hp_lost_color: Color = Color(0.64, 0.33, 0.30, 1.0)
@export var heal_color: Color = Color(0.66, 0.74, 0.62, 1.0)
@export var toll_color: Color = Color(0.54, 0.50, 0.58, 1.0)

@export_group("Shield")
# Block's shield, before its value: its height ~1.85 x half of this, at
# the numeral's size (scaled with it); its stroke, and the gap after it.
@export var shield_size_px: float = 26.0
@export var shield_line_width_px: float = 3.5
@export var shield_gap_px: float = 6.0

# The kind it shows, set by measure()/show_value().
var kind: String = KIND_DAMAGE
# The sideways offset it drew from jitter_px, in pixels - where it shows
# less this is where it was put.
var jitter: Vector2 = Vector2.ZERO
var _size_multiplier: float = 1.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sized to its text, so left is its own centre - and Block's value
	# starts past its shield (the stylebox's margin).
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER

# What a number of `kind` reads as for `value`.
static func text_for(number_kind: String, value: int) -> String:
	match number_kind:
		KIND_HP_LOST, KIND_SELF:
			return "−%d" % value
		KIND_HEAL, KIND_TOLL:
			return "+%d" % value
		KIND_BLOCKED:
			return "Blocked"
	return str(value)

# Pop, hold and fade - the whole time it shows.
func life_seconds() -> float:
	return legible_seconds() + maxf(fade_sec, 0.0)

# Until it starts to fade: the pop and the hold.
func legible_seconds() -> float:
	return maxf(pop_time_sec, 0.0) + maxf(hold_sec, 0.0)

# The size it will show `value` at - for placing it before it shows.
func measure(number_kind: String, value: int, size_multiplier: float = 1.0) -> Vector2:
	_apply_kind(number_kind, value, size_multiplier)
	reset_size()
	return size

# `size_multiplier` grows the numeral from font_size_px - a big hit's
# (BattleFeedback.number_scale()) - on top of its kind's own size.
# `jitter_x`: the sideways offset to land at; NAN draws one from jitter_px.
func show_value(number_kind: String, value: int, screen_pos: Vector2, size_multiplier: float = 1.0, jitter_x: float = NAN) -> void:
	_apply_kind(number_kind, value, size_multiplier)
	reset_size()
	jitter = Vector2(randf_range(-jitter_px, jitter_px) if is_nan(jitter_x) else jitter_x, 0.0)
	position = screen_pos + jitter
	pivot_offset = size / 2.0
	scale = Vector2.ONE * pop_scale

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, maxf(pop_time_sec, 0.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(hold_sec, 0.0))
	tween.tween_property(self, "position:y", position.y - rise_px, maxf(fade_sec, 0.0)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, maxf(fade_sec, 0.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _apply_kind(number_kind: String, value: int, size_multiplier: float) -> void:
	kind = number_kind
	_size_multiplier = size_multiplier * _kind_size(number_kind)
	text = text_for(number_kind, value)
	var font: Font = load(FONT_PATH)
	if font != null and number_kind == KIND_BLOCKED:
		var small_caps := FontVariation.new()
		small_caps.base_font = font
		small_caps.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("smcp"): 1}
		font = small_caps
	if font != null:
		add_theme_font_override("font", font)
	add_theme_font_size_override("font_size", roundi(float(font_size_px) * _size_multiplier))
	var inverse: bool = number_kind == KIND_BLOCK or number_kind == KIND_BLOCKED
	add_theme_color_override("font_color", _fill_for(number_kind))
	add_theme_color_override("font_outline_color", bone_color if inverse else ink_color)
	add_theme_constant_override("outline_size", maxi(roundi(float(outline_size_px) * _size_multiplier), 0))
	# Room for the shield before Block's value.
	var room := StyleBoxEmpty.new()
	if number_kind == KIND_BLOCK:
		room.content_margin_left = (shield_size_px + shield_gap_px) * _size_multiplier
	add_theme_stylebox_override("normal", room)
	queue_redraw()

func _kind_size(number_kind: String) -> float:
	match number_kind:
		KIND_SELF:
			return self_size
		KIND_BLOCK:
			return block_size
		KIND_BLOCKED:
			return blocked_size
		KIND_TOLL:
			return toll_size
	return 1.0

func _fill_for(number_kind: String) -> Color:
	match number_kind:
		KIND_HP_LOST, KIND_SELF:
			return hp_lost_color
		KIND_HEAL:
			return heal_color
		KIND_TOLL:
			return toll_color
		KIND_BLOCK, KIND_BLOCKED:
			return ink_color
	return bone_color

# Block's shield, left of its value, centred on the line: a bone stroke
# under the ink one, as the numeral's outline is.
func _draw() -> void:
	if kind != KIND_BLOCK:
		return
	var r: float = shield_size_px * 0.5 * _size_multiplier
	var centre := Vector2(r, size.y * 0.5)
	var shield := PackedVector2Array([
		centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
		centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
	])
	var width: float = shield_line_width_px * _size_multiplier
	draw_polyline(shield, bone_color, width + float(outline_size_px) * _size_multiplier, true)
	draw_polyline(shield, ink_color, width, true)
