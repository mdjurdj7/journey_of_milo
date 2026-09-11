extends Control
class_name GoldDisplay
# The run's gold count, with a small hand-drawn coin icon - same
# "original shapes, not sprites" visual language as ResourceDisplay's
# pips and the player/enemy silhouettes. Unlike VitalsBar (which a
# caller pushes numbers into, or pulls via refresh_from_run_state()),
# this is fully self-sufficient: it connects to RunState.gold_changed
# itself in _ready(), so dropping this node into ANY scene shows an
# always-accurate, live-updating gold count with zero wiring required
# from whatever scene owns it - see run_state.gd's add_gold(), the one
# place gold actually changes and the only thing that needs to know this
# display exists (which it doesn't - it just emits a signal).
#
# The tick-up animation is the same technique reward_screen.gd's loot
# window already uses for its own gold total: tween_method() nudging the
# DISPLAYED number up toward the real one over tick_duration_sec, rather
# than the label jumping straight to the new total.

@export var coin_color: Color = Color(0.550, 0.514, 0.429, 1)
# MUTED (2026-09-05, HUD palette-alignment pass) - REPLACES the old
# Color(0.85, 0.65, 0.15) (HSV 42.9°/82.4%/85%), which measured as the
# single most saturated color anywhere on screen (nothing else in the
# field HUD or the region's own background palette exceeds ~24%
# saturation - see field_room.gd's occluder_color, the next-highest at
# 24.1%). This value holds the same warm hue family (42.0°) at 22.0%
# saturation/55% value - in line with the region's own ceiling, still
# readable as a "gold" tone (a coin's own shape carries the rest of that
# read) rather than going fully neutral. THE single source of truth now -
# run_hud.gd's own compact_gold_color override (a second, independently-
# muted copy of this same idea) is removed; compact mode reads this value
# directly instead, and gold_label's own font_color follows it too (see
# run_hud.gd's own _apply_compact_styling() for both).
@export var coin_border_color: Color = Color(0.350, 0.327, 0.273, 1)
# Same hue/saturation family as coin_color above (42.1°/22.0%), just
# darker (35% value vs. 55%) - keeps the coin's rim reading as a distinct
# shade from its face (the same "rim vs. face" language this field's own
# doc already establishes below) without reintroducing a second,
# independently-saturated color the way the old Color(0.5, 0.35, 0.1)
# (HSV 37.5°/80%/50%) did - that value was NEVER touched by compact
# mode's own gold-muting pass, so it sat at full saturation on screen the
# entire time that pass existed, unnoticed.
@export var coin_border_width: float = 2.5
@export var coin_radius: float = 16.0

@export var tick_duration_sec: float = 0.5

@onready var coin_icon: Control = $CoinIcon
@onready var gold_label: Label = $GoldLabel

var _displayed_amount: int = 0

func _ready() -> void:
	# Every overlay this can sit behind (ShopWindow, DeckViewer,
	# MapScreen) pauses the tree while open - without this, a purchase
	# made mid-shop would still emit gold_changed and start the tick-up
	# tween below, but that tween would never advance (bound to a node
	# whose effective process mode is paused), leaving the displayed
	# number frozen at its old value until the overlay closes and the
	# tween suddenly catches up all at once. Same fix ShopWindow/
	# DeckViewer already use to stay interactive under their OWN pause
	# (see shop_window.gd's own _ready()) - this is the display-side
	# half of the same problem.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_coin()
	_snap(RunState.gold)
	RunState.gold_changed.connect(_on_gold_changed)

# An octagon reads as "circle enough" at this size - same shorthand
# already used for enemy.gd's fallback shape and player_visual.gd's
# head. Border-then-fill layering (no stroke property on Polygon2D) is
# the same trick ResourceDisplay's pips use, for a consistent look.
#
# Clears coin_icon's own children first (2026-08-27, compact-HUD pass) -
# harmless on the first call (_ready()'s own, nothing to clear yet), but
# what makes this safely re-callable from override_coin_size() below:
# without it, a second call would just ADD a second border+fill pair on
# top of the first instead of replacing it.
func _build_coin() -> void:
	for child in coin_icon.get_children():
		child.queue_free()

	var border := Polygon2D.new()
	border.polygon = _circle_points(coin_radius + coin_border_width)
	border.position = coin_icon.size / 2.0
	border.color = coin_border_color
	coin_icon.add_child(border)

	var fill := Polygon2D.new()
	fill.polygon = _circle_points(coin_radius)
	fill.position = coin_icon.size / 2.0
	fill.color = coin_color
	coin_icon.add_child(fill)

# coin_radius/coin_border_width ARE real per-instance exports, but
# _build_coin() only ever runs once, from _ready() - already run, as a
# child, before any parent's own _ready() could touch this instance (the
# same timing problem vitals_bar.gd's bar_border_color/bar_height_px had -
# see its own override_border()/apply_compact_value_style() for the
# identical shape applied there). This re-applies them live instead.
#
# Purely additive: sets the two exports, then calls the exact same
# _build_coin() _ready() already calls once - no default value changed,
# no behavior changed for any instance that never calls this (nothing
# does today except run_hud.gd's compact mode), so a plain GoldDisplay
# instance renders byte-identical to before this existed.
func override_coin_size(radius: float, border_width: float) -> void:
	coin_radius = radius
	coin_border_width = border_width
	_build_coin()

# Same purely additive, opt-in shape as override_coin_size() right above,
# kept SEPARATE from it (2026-08-27, gold-color-mute pass) rather than
# folded into one combined override - color and size are independent
# concerns a caller may want to change one without the other (this
# pass's own brief explicitly changes color only, leaving size untouched
# from the prior pass). Only coin_color (the fill) changes here -
# coin_border_color is left alone; it was already a muted brown, distinct
# from the fill on purpose (a coin's rim naturally reads as a different
# shade than its face), not part of the "icon and count match" requirement.
func override_coin_color(color: Color) -> void:
	coin_color = color
	_build_coin()

func _circle_points(radius: float, segments: int = 8) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := i * TAU / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points

func _on_gold_changed(new_amount: int) -> void:
	var tween := create_tween()
	tween.tween_method(_set_displayed_amount, float(_displayed_amount), float(new_amount), tick_duration_sec)

func _snap(amount: int) -> void:
	_displayed_amount = amount
	gold_label.text = str(amount)

func _set_displayed_amount(amount: float) -> void:
	_displayed_amount = roundi(amount)
	gold_label.text = str(_displayed_amount)
