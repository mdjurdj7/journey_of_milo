extends Label
class_name FloatingNumber

# A rising number over the body it happened to - BattleOverlay spawns one
# for each damage_dealt, combat_text (heal, Block), a hit a block took
# whole; RegionField one for the keepsake's win heal. (A Toll gain shows
# at its own readout - HPBar.update_toll().)
# `kind` (KIND_*) says which, and what it reads as (text_for()).
#
# Its life (show_value()): it pops in at pop_scale about its own centre and
# settles to 1 over pop_time_sec - shown in the frame its hit's stop
# starts, the stop's own beat - holds still and fully legible for
# hold_sec, then rises rise_px as it fades out over fade_sec, and frees
# itself. A heavy hit's (BattleFeedback.is_heavy_hit()) pops at
# heavy_pop_scale, holds heavy_hold_sec and rises and fades over
# heavy_fade_sec - it lingers. Each one lands up to jitter_px to either side of where it was
# put, at random, and keeps the offset it drew (`jitter`) for whoever
# needs the spot it was put at.
#
# Its look is the battle readouts' ink: Spectral in the theme's ink token
# (Battle/ink - charcoal on a pale world, bone on a dark one), over a soft
# halo in the theme's bone token (Battle/bone) - halo_steps outline passes
# out to halo_px, each faint, so it falls off like a blur - which keeps
# the ink legible where it crosses a dark body. The kind reads by its
# mark, not its colour: a minus for HP lost (smaller for his own cost), a
# plus for a heal, a shield glyph before Block's value,
# "Blocked" in Spectral's small caps. Two kinds take a tint on the numeral
# alone, the halo staying bone: his own HP cost in the theme's "self_loss"
# token, a heal in its "heal" token (BattleTheme's Combat Number Tints);
# an enemy's damage to him stays ink.
#
# The Label measures and places it; _draw() draws it - halo first, ink
# over, the halo reaching past the rect - so the Label's own glyphs are
# left transparent.

const FONT_PATH := "res://assets/fonts/Spectral-SemiBold.ttf"

# Damage dealt to an enemy; HP an enemy's hit (or a tick) took from the
# Wanderer; HP his own effect took; HP back; Block gained; a hit a block
# took whole.
const KIND_DAMAGE := "damage"
const KIND_HP_LOST := "hp_lost"
const KIND_SELF := "self"
const KIND_HEAL := "heal"
const KIND_BLOCK := "block"
const KIND_BLOCKED := "blocked"

@export_group("Motion")
@export var pop_scale: float = 1.5
@export var pop_time_sec: float = 0.1
@export var hold_sec: float = 0.5
@export var rise_px: float = 40.0
@export var fade_sec: float = 0.4
# A heavy hit's number: its pop, its hold and its rise and fade.
@export var heavy_pop_scale: float = 1.7
@export var heavy_hold_sec: float = 0.9
@export var heavy_fade_sec: float = 0.6
# The most it lands to either side of where it was put, in pixels.
@export var jitter_px: float = 14.0

@export_group("Type")
@export var font_size_px: int = 40
@export var self_size: float = 0.75
@export var block_size: float = 0.8
@export var blocked_size: float = 0.7

@export_group("Halo")
# How far the halo reaches past the ink, in pixels at size 1, over how
# many passes, and its alpha where they all overlap (at the ink's edge).
@export var halo_px: float = 9.0
@export var halo_steps: int = 5
@export_range(0.0, 1.0) var halo_alpha: float = 0.35


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
var _font: Font = null
var _font_size: int = 40

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sized to its text, so left is its own centre - and Block's value
	# starts past its shield (the stylebox's margin).
	horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_theme_color_override("font_color", Color(0.0, 0.0, 0.0, 0.0))

# What a number of `kind` reads as for `value`.
static func text_for(number_kind: String, value: int) -> String:
	match number_kind:
		KIND_HP_LOST, KIND_SELF:
			return "−%d" % value
		KIND_HEAL:
			return "+%d" % value
		KIND_BLOCKED:
			return "Blocked"
	return str(value)

# Pop, hold and fade - the whole time it shows; a heavy hit's longer.
func life_seconds(heavy: bool = false) -> float:
	return legible_seconds(heavy) + maxf(heavy_fade_sec if heavy else fade_sec, 0.0)

# Until it starts to fade: the pop and the hold.
func legible_seconds(heavy: bool = false) -> float:
	return maxf(pop_time_sec, 0.0) + maxf(heavy_hold_sec if heavy else hold_sec, 0.0)

# The size it will show `value` at - for placing it before it shows.
func measure(number_kind: String, value: int, size_multiplier: float = 1.0) -> Vector2:
	_apply_kind(number_kind, value, size_multiplier)
	reset_size()
	return size

# `size_multiplier` grows the numeral from font_size_px - a big hit's
# (BattleFeedback.number_scale()) - on top of its kind's own size.
# `jitter_x`: the sideways offset to land at; NAN draws one from jitter_px.
# `heavy`: a heavy hit's number, its heavy_* pop, hold and fade.
func show_value(number_kind: String, value: int, screen_pos: Vector2, size_multiplier: float = 1.0, jitter_x: float = NAN, heavy: bool = false) -> void:
	_apply_kind(number_kind, value, size_multiplier)
	reset_size()
	jitter = Vector2(randf_range(-jitter_px, jitter_px) if is_nan(jitter_x) else jitter_x, 0.0)
	position = screen_pos + jitter
	pivot_offset = size / 2.0
	scale = Vector2.ONE * (heavy_pop_scale if heavy else pop_scale)
	var fade: float = maxf(heavy_fade_sec if heavy else fade_sec, 0.0)

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, maxf(pop_time_sec, 0.0)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(maxf(heavy_hold_sec if heavy else hold_sec, 0.0))
	tween.tween_property(self, "position:y", position.y - rise_px, fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(self, "modulate:a", 0.0, fade).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _apply_kind(number_kind: String, value: int, size_multiplier: float) -> void:
	kind = number_kind
	_size_multiplier = size_multiplier * _kind_size(number_kind)
	text = text_for(number_kind, value)
	_font = load(FONT_PATH)
	if _font != null and number_kind == KIND_BLOCKED:
		var small_caps := FontVariation.new()
		small_caps.base_font = _font
		small_caps.opentype_features = {TextServerManager.get_primary_interface().name_to_tag("smcp"): 1}
		_font = small_caps
	if _font != null:
		add_theme_font_override("font", _font)
	_font_size = roundi(float(font_size_px) * _size_multiplier)
	add_theme_font_size_override("font_size", _font_size)
	# Room for the shield before Block's value. The halo draws past the
	# rect, so it never moves where the number is placed.
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
	return 1.0

func _ink() -> Color:
	var ink: Color = get_theme_color("ink", "Battle")
	match kind:
		KIND_HEAL:
			return _token("heal", ink)
		KIND_SELF:
			return _token("self_loss", ink)
	return ink

# A "Battle" theme colour, or `fallback` where the theme has none.
func _token(token: String, fallback: Color) -> Color:
	return get_theme_color(token, "Battle") if has_theme_color(token, "Battle") else fallback

func _draw() -> void:
	if _font == null:
		return
	var ink: Color = _ink()
	var bone: Color = get_theme_color("bone", "Battle")
	var halo_reach: float = maxf(halo_px, 0.0) * _size_multiplier
	var steps: int = maxi(halo_steps, 1)
	var step_alpha: float = halo_alpha / float(steps)
	var room: StyleBox = get_theme_stylebox("normal")
	var origin := Vector2(room.content_margin_left, room.content_margin_top + _font.get_ascent(_font_size))

	# The shield: its halo, then its ink.
	var shield := PackedVector2Array()
	var stroke: float = shield_line_width_px * _size_multiplier
	if kind == KIND_BLOCK:
		var r: float = shield_size_px * 0.5 * _size_multiplier
		var centre := Vector2(r, size.y * 0.5)
		shield = PackedVector2Array([
			centre + Vector2(-r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, -r * 0.9), centre + Vector2(r * 0.8, r * 0.1),
			centre + Vector2(0.0, r * 0.95), centre + Vector2(-r * 0.8, r * 0.1), centre + Vector2(-r * 0.8, -r * 0.9),
		])

	# The halo: passes from widest to narrowest, each faint, so it builds to
	# halo_alpha at the ink's edge and falls off outward.
	for i in steps:
		var reach: float = halo_reach * float(steps - i) / float(steps)
		var color: Color = Color(bone, bone.a * step_alpha)
		draw_string_outline(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, maxi(roundi(reach * 2.0), 1), color)
		if not shield.is_empty():
			draw_polyline(shield, color, stroke + reach * 2.0, true)

	if not shield.is_empty():
		draw_polyline(shield, ink, stroke, true)
	draw_string(_font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, ink)
