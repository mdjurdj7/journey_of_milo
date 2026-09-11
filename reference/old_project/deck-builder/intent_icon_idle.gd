extends Node2D
class_name IntentIconIdle
# The IDLE intent's own icon (see intent_display.gd's ICON_SCENES) - three
# dots in a horizontal row, an ellipsis. Reads as "this slot was evaluated
# and there's nothing in it," not an action or a status - the enemy took
# no action this turn, distinct from both a real intent (attack/defend)
# and from show_interrupted()'s blank state (an intent that WAS going to
# happen but got cancelled). Replaces an earlier hollow-ring treatment
# (2026-08-26, ellipsis pass) that read as a missing asset rather than a
# deliberate state - an ellipsis carries no directional/threatening
# implication in any context and reads as "waiting" on sight.
#
# Deliberately NOT a copy of another icon's shape rendered unfilled -
# that grammar (hollow_icon.gd, deleted - see git history) was retired
# for the WIND_UP case specifically because it collided with pip.gd's
# own hollow-vs-filled meaning spent-vs-available (see enemy_intent.gd's
# WIND_UP doc). Three dots share no silhouette with any other icon on
# screen, so it doesn't reopen that collision - it's its own primitive,
# meaning only "no intent," nowhere else.
#
# Built as filled Polygon2D circles (2026-08-26, ellipsis pass) - matches
# ATTACK/DEFEND's own shape TYPE (see intent_icon_attack.tscn/intent_icon_
# defend.tscn, both hand-baked Polygon2D, no script) rather than the old
# Line2D stroke. Still script-built rather than hand-baked, unlike those
# two - dot_radius/dot_spacing below need to stay live-tunable, which a
# scriptless hand-baked scene can't offer; matching ATTACK/DEFEND's
# silhouette LANGUAGE (filled shapes) won out over matching their exact
# construction method.
#
# ONE flat color, no shadow/highlight pair - ATTACK/DEFEND each got a
# two-layer treatment (a darker shadow shape under a lighter fill, see
# their own .tscn) in the same pass that muted their colors, but that's a
# depth effect for a HUED icon. IDLE is meant to read as colorless/quiet
# (see DOT_COLOR's own doc) - a second tint layer would just be a second
# color, working against that.

@export var dot_radius: float = 1.8:
	set(value):
		dot_radius = value
		_rebuild()
# Tuned so DOT_COUNT dots at this radius/dot_spacing occupy a total_width()
# (18.0 - see that function) matching ATTACK's own current raw bounding
# width (measured via VisualBounds.compute() against intent_icon_attack.
# tscn - see this pass's own investigation) - "not wider, not noticeably
# smaller" than the attack mark, per this feature's own brief. Height
# necessarily comes out much shorter than ATTACK's own (a row of small
# circles is inherently squatter than a chevron) - that's an accepted
# consequence of matching WIDTH/footprint, not a separate target.

@export var dot_spacing: float = 3.6:
	set(value):
		dot_spacing = value
		_rebuild()
# Gap between adjacent dots' EDGES (not center-to-center - see _rebuild()
# below for the distinction). Set to 2x dot_radius by default - an even,
# classic ellipsis rhythm (gap equals dot diameter), not derived from
# anything else; free to retune independently of dot_radius.

const DOT_COLOR := Color(0.053889446, 0.10078993, 0.14605513, 1)
# Sampled directly from intent_icon_defend.tscn's own ShieldDark layer,
# not invented (per this pass's own brief - "no color" means no NEW hue,
# not literally colorless, since a Polygon2D still needs an actual color
# value). DEFEND's dark layer picked over ATTACK's own ChevronShadow
# (a saturated dark red, less neutral-reading) as the closer of the two
# to "colorless" at a glance - both are near-black at this luminance, so
# the choice is low-stakes; swap to ChevronShadow's value here directly
# if this reads wrong live.

const DOT_COUNT := 3

const SEGMENTS := 16
# Coarser than the old ring's 32 (this pass) - each dot is far smaller
# than the old full-size ring circle, so fewer vertices still reads as
# perfectly round at this scale, closer to ATTACK/DEFEND's own low-
# vertex-count hand-plotted silhouettes than an needlessly smooth curve
# would be. A resolution knob, not a look tunable, so it stays a const.

var _dots: Array[Polygon2D] = []

# Derived from dot_radius/dot_spacing, not its own @export (DECIDED -
# three independent knobs would be over-determined for three evenly
# spaced circles; dot_radius+dot_spacing alone fully define this). Call
# this instead of hand-computing IDLE's own footprint elsewhere.
func total_width() -> float:
	return DOT_COUNT * dot_radius * 2.0 + (DOT_COUNT - 1) * dot_spacing

func _init() -> void:
	_rebuild()

func _rebuild() -> void:
	for dot in _dots:
		dot.free()
	_dots.clear()
	var step := dot_radius * 2.0 + dot_spacing # center-to-center distance
	var start_x := -step * float(DOT_COUNT - 1) / 2.0
	for i in DOT_COUNT:
		var dot := Polygon2D.new()
		dot.polygon = _circle_points(dot_radius)
		dot.color = DOT_COLOR
		dot.antialiased = true
		dot.position = Vector2(start_x + step * i, 0.0)
		add_child(dot)
		_dots.append(dot)

func _circle_points(radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in SEGMENTS:
		var angle := TAU * float(i) / float(SEGMENTS)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
