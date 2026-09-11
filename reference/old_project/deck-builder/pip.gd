extends Control
class_name Pip
# The default pip visual for ResourceDisplay's PIP mode (see resource_
# display.gd's own header) - extracted (2026-08-26) so pip appearance can
# be swapped independently of the display that arranges them, the same
# "script/scene owns its own look, the thing driving it only calls a
# small API" split EnemyData.visual_scene already establishes for enemy
# silhouettes. resource_display.gd only ever calls configure() and set_
# filled() below - it never reaches into this scene's own nodes, doesn't
# build polygons, and doesn't know coin_icon exists.
#
# A custom pip does NOT need to extend this class - resource_display.gd
# stores its pip instances untyped and calls these two methods by name
# (duck typing), specifically so a texture-based or differently-built
# custom pip (no CoinIcon, no Polygon2D at all) is a real option, not just
# a reskin of this one. This script is simply the concrete DEFAULT
# implementation, not an abstract base something else must inherit from.
#
# SWAPPED (2026-08-26) from a plain diamond (a Border/Fill Polygon2D pair,
# both procedurally built here via _diamond_points()) to a hand-drawn
# coin icon (see pip.tscn's own CoinIcon group) - the diamond's own two
# shapes are gone from the scene entirely, replaced by CoinIcon's five
# (Coin/CoinLight/CoinDark/Sigil/SigilMid).

@export_group("Pip Animation")
@export var spend_pulse_sec: float = 0.15
@export var refill_duration_sec: float = 0.12
# MOVED here from resource_display.gd's own "Pip Animation" export group
# (spend_pulse_sec/refill_pip_duration_sec) - same reasoning border_width
# used to carry before the coin swap: HOW an individual pip animates its
# own state change is this pip's own business, not the display's. refill_
# stagger_sec stays on resource_display.gd - staggering WHEN each pip's
# animation starts is inherently a multi-pip, display-level fact; a
# single pip has no way to know it's one of several, let alone which one.

const SIZE_MULTIPLIER := 1.27
# How much bigger than _pip_size (what the old diamond's own span used to
# exactly equal) the coin icon renders - "roughly the size of current
# diamonds, maybe slightly larger" per this feature's own original brief.
# 1.0 would exactly match the old diamond's footprint. Was 1.15; bumped
# ~10% further (2026-08-26 follow-up - "increase pip size slightly by
# maybe 10%") to 1.27 (1.15 * 1.10 ≈ 1.265, rounded).

var _pip_size: float = 32.0
var _dim_color: Color = Color(0.22, 0.21, 0.19, 1)
# No _lit_color counterpart (REMOVED 2026-08-27, true-color pass) - a
# pip is either full color or empty, never a third tint in between, so
# "lit" isn't a color choice at all, just "no tint" (Color.WHITE, used
# directly in _apply_geometry()/set_filled() below). It used to be an
# exported near-neutral tone (0.88, 0.87, 0.83), which quietly dulled
# every lit pip below its own pip.tscn-authored color for no measurable
# contrast benefit - dim_color's own much lower luminance already
# carries the lit/dim contrast on its own; a lit pip doesn't need to
# also fall short of true white to read as "the bright one."
var _filled: bool = false

@onready var visual: Node2D = $Visual
@onready var coin_icon: Node2D = $Visual/CoinIcon
@onready var coin_dark: Polygon2D = $Visual/CoinIcon/CoinDark
@onready var coin_light: Polygon2D = $Visual/CoinIcon/CoinLight
@onready var sigil: Polygon2D = $Visual/CoinIcon/Sigil
@onready var sigil_mid: Polygon2D = $Visual/CoinIcon/SigilMid

var _tween: Tween

var _coin_dark_base_color: Color = Color(0.237, 0.212, 0.177, 1.0)
# CoinDark's own hand-drawn shading tone, cached ONCE in _ready() from the
# node itself (see below) so _apply_geometry() can always restore it -
# .color is otherwise left alone (no retint - a border-color multiply was
# tried and reverted here, 2026-08-26: multiplying two already-dark colors
# component-wise compounds the darkness rather than tinting it, crushing
# this toward near-black regardless of the .tscn's actual authored brown).

var _coin_raw_bounds: Rect2 = Rect2()
# CoinIcon's own hand-drawn bounding box, in ITS OWN local space (before
# any scale/position this script applies) - measured ONCE here via
# VisualBounds.compute(), the exact same "measure a hand-drawn shape's
# real bounds instead of assuming one" technique enemy.gd already uses
# for silhouettes (see its own _silhouette_bounds). Cached rather than
# re-measured on every configure() call: the coin's own authored polygon
# data never changes at runtime, only how big/where it's SCALED to does
# - re-measuring AFTER scaling would just measure the scaled result back
# out, corrupting the next scale calculation.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_dark_base_color = coin_dark.color
	_coin_raw_bounds = VisualBounds.compute(coin_icon)
	_apply_geometry()

# The one setup call resource_display.gd makes right after instantiating
# and add_child()-ing this pip, before the first set_filled() - static
# per-pip configuration (what this pip's own size/palette IS) as opposed
# to set_filled() below, which is the ongoing STATE the display drives.
# Recomputes this pip's own custom_minimum_size too (previously pip_size
# + border_width, now pip_size * SIZE_MULTIPLIER - see its own doc) - the
# display never needs to know this pip's real footprint, it just lays
# out whatever custom_minimum_size each pip reports, same as any other
# HBoxContainer child.
func configure(pip_size: float, dim_color: Color) -> void:
	_pip_size = pip_size
	_dim_color = dim_color
	_apply_geometry()

func _apply_geometry() -> void:
	var total_size := _pip_size * SIZE_MULTIPLIER
	custom_minimum_size = Vector2(total_size, total_size)
	visual.position = Vector2(total_size / 2.0, total_size / 2.0)
	_fit_coin_icon(total_size)
	coin_dark.color = _coin_dark_base_color
	coin_icon.modulate = Color.WHITE if _filled else _dim_color
	_apply_fill_state()

# Scales+centers CoinIcon so its own measured bounds land exactly inside
# a target_size x target_size box, regardless of whatever raw coordinate
# scale it was hand-drawn at or how far off-origin its pieces happen to
# sit (see CoinDark/Coin/CoinLight's own authored position/scale in
# pip.tscn, none of which were tuned against a target pip footprint).
# Fits by the LARGER of the two raw dimensions (max, not e.g. width
# alone), so a non-square bounding box still fits fully inside the
# square target without clipping on its taller/wider axis.
func _fit_coin_icon(target_size: float) -> void:
	if _coin_raw_bounds.size.x <= 0.0 or _coin_raw_bounds.size.y <= 0.0:
		return
	var raw_span: float = maxf(_coin_raw_bounds.size.x, _coin_raw_bounds.size.y)
	var fit_scale: float = target_size / raw_span
	coin_icon.scale = Vector2.ONE * fit_scale
	var raw_center: Vector2 = _coin_raw_bounds.position + _coin_raw_bounds.size / 2.0
	coin_icon.position = -raw_center * fit_scale

# Available and spent must differ in KIND, not just brightness (feedback:
# a pure modulate swap "differs by ~2.7x luminance and that already
# fails to read at pip size... a larger multiplier is the same approach
# with a bigger number"). CoinLight (the shine) and Sigil/SigilMid (the
# engraved mark) drop out entirely when spent, leaving a flat, markless
# disc - Coin (base) and CoinDark (rim/shadow) stay present in both
# states so a spent pip still reads as "a coin", just an empty one,
# rather than vanishing or looking broken. Uses the existing polygon
# pieces already in pip.tscn - no new art.
func _apply_fill_state() -> void:
	coin_light.visible = _filled
	sigil.visible = _filled
	sigil_mid.visible = _filled

# The one state resource_display.gd drives - lit (filled) or dim (empty).
# animated=false (the initial snap, or a max_value change - see resource_
# display.gd's own _snap_pips()) jumps straight to the target look with
# no tween, killing whatever animation might already be mid-flight - a
# hard reset, not a soft one. animated=true plays this pip's own
# transition instead: a plain modulate fade when becoming filled
# (refill), or a modulate fade plus a quick squash-then-pop scale pulse
# when becoming empty (spend) - exactly the two animations resource_
# display.gd used to build inline against its own _pip_fills/_pip_
# visuals arrays, just decided here now instead of there. Modulates
# CoinIcon as a whole (2026-08-26, coin swap), same as always, but
# (2026-08-26, contrast fix) also calls _apply_fill_state() to show/hide
# CoinLight and Sigil/SigilMid - the shape itself changes, not just the
# tint. Toggled immediately rather than tweened: it lands mid-pulse for
# spend (the coin already squashes/fades at the same moment) and mid-fade
# for refill, both of which read fine without a dedicated transition of
# their own.
func set_filled(filled: bool, animated: bool = false) -> void:
	_filled = filled
	_apply_fill_state()
	if _tween:
		_tween.kill()
		_tween = null
	var target_color := Color.WHITE if filled else _dim_color
	if not animated:
		coin_icon.modulate = target_color
		visual.scale = Vector2.ONE
		return
	_tween = create_tween()
	if filled:
		_tween.tween_property(coin_icon, "modulate", target_color, refill_duration_sec)
	else:
		_tween.set_parallel(true)
		_tween.tween_property(coin_icon, "modulate", target_color, spend_pulse_sec)
		_tween.tween_property(visual, "scale", Vector2(0.7, 0.7), spend_pulse_sec * 0.4)
		_tween.tween_property(visual, "scale", Vector2.ONE, spend_pulse_sec * 0.6).set_delay(spend_pulse_sec * 0.4)
