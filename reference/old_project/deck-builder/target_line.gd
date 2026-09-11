extends Node2D
class_name TargetLine
# Drawn while a targeted card is armed (see battle.gd's _begin_targeting()/
# _cancel_targeting()) - a line from the armed card to the mouse cursor,
# redrawn every frame so it tracks the cursor anywhere on screen, including
# empty space and invalid targets. A plain Node2D, not a Control - it never
# receives mouse input at all (no mouse_filter to fight with), so it can
# sit visually on top of every clickable card/enemy in UI without ever
# intercepting a click meant for them.
#
# Being battle.tscn's last child under UI (see that file) draws this over
# every ORDINARY (z_index 0) sibling by tree-order tie-breaking alone, but
# that stopped being enough the instant anything else in this canvas layer
# gets a non-zero z_index of its own (2026-08-26, armed-card z-order fix -
# card.gd's set_armed() now elevates an armed card's z_index well past 0
# specifically so it draws OVER enemy sprites/HUD). z_index tie-breaks by
# COMPARING VALUES first, tree order only as a last resort among equal
# values - so without its own explicit bump, this would start losing to
# any armed card the instant that fix shipped, hiding the exact line it
# exists to show. Set once here, not dynamically per-targeting-session,
# since this is only ever actually drawing anything DURING that same
# window anyway (visible = false otherwise) - matches enemy.gd's own
# SNAP_HIGHLIGHT_Z_INDEX (same value, same "safely above card.gd's
# realistic range" reasoning - see that constant's own doc).
#
# Deliberately a dumb display node: Battle is the one that decides WHEN a
# card is armed and WHETHER the cursor is currently over a valid,
# hysteresis-snapped target (see start()/set_target()/clear_target() below
# and battle.gd's own _update_snap_target()); Card and Enemy each own
# WHERE their own end of the line should attach (get_targeting_anchor_
# position()/get_target_anchor_position()) - this node only knows how to
# draw a curve between two points in two states, the same "decides nothing
# itself" split every other visual piece in this project already follows
# (card.gd, enemy.gd, ...). Built so a later pass can layer more visual
# states on top (chain/lethality styling - explicitly out of scope here)
# without changing this split: another setter, another _draw() branch.

# --- Default (inactive) state - a UI overlay, not a lit object in the
# scene. Must NOT share the warm gold used elsewhere for "this is
# selected/available" (card.gd's ARMED_MODULATE) - that color already
# means something specific (card selection); reusing it here would make
# two unrelated things speak in the same voice. A cool, pale grey
# instead: reads as UI chrome, leaves headroom for the valid-target state
# below to be the thing that actually stands out.
# "Not faint" (2026-08-26 weight pass) - alpha/width both raised from the
# previous revision so the line reads as a deliberate UI element even at
# rest, not something that has to turn gold to be visible at all. ---
@export_group("Default State")
@export var line_color: Color = Color(0.8, 0.83, 0.87, 0.5)
@export var line_width_card_end: float = 3.5
# Wider at the card end, narrower at the target end (see _build_ribbon()'s
# taper math) - a uniform hairline reads as debug geometry. Sampled along
# the arced curve below (see arc_height_px), not just the two raw
# endpoints, so the taper reads correctly along the whole bow, not just
# in a straight line between them.
@export var line_width_target_end: float = 1.5

@export var arc_height_px: float = 28.0
# How far the curve's peak bows upward (screen-space up, i.e. toward
# smaller Y - NOT perpendicular to the card-to-target direction, so it
# reads as "arcing skyward" consistently regardless of the line's own
# angle) away from a straight chord between the two endpoints. Sampled
# into ARC_SEGMENTS straight segments (see _build_ribbon() below) rather
# than drawn as a true curve primitive - CanvasItem has no built-in
# "draw a filled tapered bezier" call, and Godot 4 doesn't expose a bulk
# quadratic-bezier sampler on Vector2 the way it does for cubic
# (bezier_interpolate() takes two control points, not one) - manual
# per-point quadratic math is simpler than reshaping this into a cubic
# just to use that. Kept subtle per this feature's own brief ("not a
# lob") - a small default relative to the card-to-enemy distance this
# line typically spans.

# --- Shadow/outline pass - drawn once, behind the real line, offset
# down-right (same convention overlay_style.gd's own text-outline
# treatment already uses across every other combat overlay element - see
# its own header comment) so a pale line stays legible crossing both
# bright sky and darker ground instead of washing out over the sky half.
# NOT routed through OverlayStyle itself - that helper is built for
# Label font-outline/Polygon2D icon-shadow consumers specifically (see
# its own apply_to_label()/make_icon_shadow()), neither of which fits an
# immediate-mode _draw() polygon; this is the same idea, reimplemented
# for this node's own drawing primitives. ---
@export_group("Shadow")
@export var shadow_color: Color = Color(0.05, 0.05, 0.06, 0.4)
@export var shadow_offset: Vector2 = Vector2(2.0, 3.0)

# --- Valid-target state - THE primary readability signal (replaces a
# constant-loud line). Reads as "brightening/warming," not a hue swap
# into the same shared gold: saturation kept low, pushed toward a pale
# warm neutral (parchment/bone) well short of pip.gd's saturated
# (0.95, 0.85, 0.3) gold, plus a real jump in alpha/width - the
# brightening itself is most of the signal, color a secondary nudge
# alongside it. ---
@export_group("Valid Target State")
@export var valid_line_color: Color = Color(0.96, 0.93, 0.86, 0.78)
@export var valid_line_width_card_end: float = 5.0
@export var valid_line_width_target_end: float = 2.0
# Alpha lowered from 0.95 (2026-08-26, opacity pass) - 0.95 read as
# functionally solid, not translucent; this is a direct request for
# "slight opacity," not a walk-back of the OTHER export group's own
# "not faint" note above (that one is about line_color/line_width_
# card_end specifically, at rest with no target snapped, and is
# untouched here - this line only reads this color once a target is
# already snapped, a separate, brighter moment that can afford to give
# some of that brightness back to translucency without going faint).

# --- Endpoint dot (re-added 2026-08-26, opacity/dot pass). A PRIOR pass
# on this same file (see git history) deliberately removed an endpoint
# marker from the state above, reasoning that a symbol at the line's tip
# read as FPS aim-reticle grammar ("aim precisely") for a mechanic
# that's actually "commit," and that it competed with the enemy's own
# rim highlight for "this is your target" duty. That reasoning was sound
# at the time; this is a direct, current request to bring it back, most
# likely because enemy_rim_highlight.gdshader's OWN very next pass
# quieted that rim down substantially (thinner, softer-edged, lower
# alpha) - with that signal weaker, a dedicated endpoint marker again
# earns its keep. Kept as its own toggle (dot_enabled) specifically so
# this can be flipped off from the Inspector with no code edit if it
# turns out to reintroduce the original complaint. Given its own color/
# alpha (not reusing line_color/valid_line_color) rather than matching
# the line's now-more-transparent stroke - the whole point of a dot here
# is a clear, legible anchor point, which a translucent dot atop an
# already-translucent line would undercut. ---
@export_group("Endpoint Dot")
@export var dot_enabled: bool = true
@export var dot_radius: float = 4.5
@export var dot_color: Color = Color(0.96, 0.93, 0.86, 0.9)

const ARC_SEGMENTS := 20
# Straight sub-segments the curve is sampled into (see _build_ribbon()
# below) - a technical sampling-density knob, not a "look" tunable, so
# it stays a const rather than exported alongside arc_height_px.

var _source_card: Card = null
var _has_target: bool = false
var _target_anchor: Vector2 = Vector2.ZERO

const ELEVATED_Z_INDEX := 4000

func _ready() -> void:
	visible = false
	set_process(false)
	z_index = ELEVATED_Z_INDEX

# Called once, the instant a targeted card is armed (see battle.gd's
# _begin_targeting()). `source` is the armed Card itself, read fresh
# every frame in _draw() below (via get_targeting_anchor_position(), not
# a point cached here once) - see that method's own doc for why a raw
# Control rect isn't enough on its own (arming lifts/scales a CHILD node,
# not the Card's own root rect).
func start(source: Card) -> void:
	_source_card = source
	_has_target = false
	visible = true
	set_process(true)
	queue_redraw()

# Called on every cancellation path AND on a successful play (see
# battle.gd's _cancel_targeting()) - the line disappears immediately
# either way.
func stop() -> void:
	_source_card = null
	_has_target = false
	visible = false
	set_process(false)
	queue_redraw()

# Battle calls this every frame the cursor is snapped to a target (see
# its own _update_snap_target()), passing that enemy's OWN anchor point
# (enemy.gd's get_target_anchor_position()) - the line's endpoint SNAPS
# there instead of continuing to track the raw cursor, which is what
# makes the connection read as deliberate rather than the line just
# happening to end wherever the mouse currently sits.
func set_target(anchor_position: Vector2) -> void:
	_has_target = true
	_target_anchor = anchor_position
	queue_redraw()

# Battle calls this every frame nothing is currently snapped - the
# endpoint goes back to tracking the raw cursor (see _draw() below).
func clear_target() -> void:
	if not _has_target:
		return
	_has_target = false
	queue_redraw()

func _process(_delta: float) -> void:
	# The cursor itself moves every frame even when nothing else has
	# changed - the unsnapped-state endpoint needs a fresh redraw for
	# that alone. (The snapped-state endpoint is a fixed anchor and
	# technically wouldn't need this, but redrawing unconditionally here
	# is simpler than tracking which case is currently active.)
	queue_redraw()

func _draw() -> void:
	if _source_card == null or not is_instance_valid(_source_card):
		return
	var from := _source_card.get_targeting_anchor_position()
	var to := _target_anchor if _has_target else get_viewport().get_mouse_position()
	var color := valid_line_color if _has_target else line_color
	var width_start := valid_line_width_card_end if _has_target else line_width_card_end
	var width_end := valid_line_width_target_end if _has_target else line_width_target_end
	var ribbon := _build_ribbon(from, to, width_start, width_end)
	# Shadow first (behind), then the real line on top - see shadow_
	# color/shadow_offset's own doc.
	draw_colored_polygon(_offset_points(ribbon, shadow_offset), shadow_color)
	draw_colored_polygon(ribbon, color)
	if dot_enabled:
		# Same shadow-then-real ordering as the ribbon above, reusing the
		# same shadow_color/shadow_offset rather than adding a dedicated
		# dot-shadow export - keeps the dot legible over both sky and
		# ground without introducing a second shadow convention.
		draw_circle(to + shadow_offset, dot_radius, shadow_color)
		draw_circle(to, dot_radius, dot_color)

# Builds a tapered ribbon polygon (a list of points ready for
# draw_colored_polygon()) along a quadratic-bezier bow from `from` to
# `to`, peaking arc_height_px above the straight chord's midpoint (see
# arc_height_px's own doc). Sampled into ARC_SEGMENTS straight sub-
# segments - each sample point gets its own perpendicular (the curve's
# local tangent, not the overall from-to direction) and its own
# interpolated half-width, so the taper reads correctly along the whole
# curve rather than just between the two raw endpoints. Returns an empty
# array (nothing drawn) on the one-frame edge case where `from` and `to`
# land on exactly the same point - there's no direction to build a
# ribbon along.
func _build_ribbon(from: Vector2, to: Vector2, width_start: float, width_end: float) -> PackedVector2Array:
	if from.distance_squared_to(to) < 0.0001:
		return PackedVector2Array()
	var control := (from + to) / 2.0 + Vector2(0.0, -arc_height_px)
	var left_points := PackedVector2Array()
	var right_points := PackedVector2Array()
	for i in range(ARC_SEGMENTS + 1):
		var t := float(i) / float(ARC_SEGMENTS)
		var one_minus_t := 1.0 - t
		var point := from * (one_minus_t * one_minus_t) + control * (2.0 * one_minus_t * t) + to * (t * t)
		var tangent := (control - from) * (2.0 * one_minus_t) + (to - control) * (2.0 * t)
		if tangent.length_squared() < 0.0001:
			tangent = to - from
		var perpendicular := tangent.normalized().orthogonal()
		var half_width := lerpf(width_start, width_end, t) / 2.0
		left_points.append(point + perpendicular * half_width)
		right_points.append(point - perpendicular * half_width)
	right_points.reverse()
	var ribbon := PackedVector2Array()
	ribbon.append_array(left_points)
	ribbon.append_array(right_points)
	return ribbon

func _offset_points(points: PackedVector2Array, offset: Vector2) -> PackedVector2Array:
	var offset_points := PackedVector2Array()
	offset_points.resize(points.size())
	for i in range(points.size()):
		offset_points[i] = points[i] + offset
	return offset_points
