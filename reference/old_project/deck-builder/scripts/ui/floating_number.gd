extends Label
class_name FloatingNumber
# Single shared "floating combat text" component - replaces the two
# near-identical from-scratch Labels enemy.gd (_spawn_floating_damage())
# and battle.gd (_spawn_player_floating_number()) used to build
# independently. extends Label (a Control) rather than a bare Control or
# Node2D: Label already gives us text rendering plus the font/outline/
# shadow theme overrides this needs, and Control's own position/rotation/
# scale/modulate cover every motion property below - wrapping a Label
# inside a separate Control container would just add a node for nothing.
# Both old versions already parented a plain Label straight into a
# Control-based tree (Enemy is a Control; battle.gd's UI children are
# Controls too), so this fits the exact same slot they did.
#
# Deliberately separate from OverlayStyle (see overlay_style.gd) - that
# autoload's outline treatment serves HP numbers/badges/flavor text and
# must keep its own tuned default (4px). This component's outline scales
# with its own font size instead (see _configure() below), which would
# fight OverlayStyle's single shared knob if it reused that path.

enum Kind {
	DEAL,
	TAKE_ENEMY,
	TAKE_SELF,
	TAKE_STATUS,
	HEAL,
	CHAIN_REFUND,
	DEAL_WEAPON_REFLECT,
	DEAL_RETALIATION,
}

const FONT_PATH := "res://assets/fonts/Spectral-ExtraBold.ttf"

# Kinds that launch/arc away from an attacker (a landed hit). Every other
# Kind drifts straight up instead - see _start_motion() below.
const ARCING_KINDS: Array[Kind] = [Kind.DEAL, Kind.TAKE_ENEMY, Kind.DEAL_WEAPON_REFLECT, Kind.DEAL_RETALIATION]
# Of the arcing kinds, which ones launch RIGHTWARD (away from the player,
# who is always screen-left). The one arcing kind NOT in this list,
# TAKE_ENEMY, launches left instead (away from the enemy, screen-right).
const RIGHTWARD_KINDS: Array[Kind] = [Kind.DEAL, Kind.DEAL_WEAPON_REFLECT, Kind.DEAL_RETALIATION]
# Kinds whose size never scales with magnitude - self-damage/status ticks/
# heals/chain-refund are never meant to read as a big impact the way a
# landed hit is.
const FIXED_SIZE_KINDS: Array[Kind] = [Kind.TAKE_SELF, Kind.TAKE_STATUS, Kind.HEAL, Kind.CHAIN_REFUND]
const PREFIX_PLUS_KINDS: Array[Kind] = [Kind.HEAL, Kind.CHAIN_REFUND]

const FILL_COLORS := {
	Kind.DEAL: Color("ece5d3"),
	Kind.TAKE_ENEMY: Color("8e2a22"),
	Kind.TAKE_SELF: Color("1e1b19"),
	Kind.TAKE_STATUS: Color("4a5a52"),
	Kind.HEAL: Color("6f8a73"),
	Kind.CHAIN_REFUND: Color("b08a3c"),
	# Pale cold grey-blue (The Creditor's weapon-reflect hit) and dull
	# brass (a Retaliation payoff) - both read as "a hit landed" first via
	# DEAL's shared cream-family weight/motion, "a special hit" second via
	# just the tint. Brass intentionally matches CHAIN_REFUND: both are
	# payoffs the player set up rather than damage they aimed (2026-09-06,
	# user call - see floating-number redesign conversation).
	Kind.DEAL_WEAPON_REFLECT: Color("8fa3a8"),
	Kind.DEAL_RETALIATION: Color("b08a3c"),
}

const OUTLINE_COLORS := {
	Kind.DEAL: Color("1e1b19"),
	Kind.TAKE_ENEMY: Color("ece5d3"),
	Kind.TAKE_SELF: Color("ece5d3"),
	Kind.TAKE_STATUS: Color("ece5d3"),
	Kind.HEAL: Color("1e1b19"),
	Kind.CHAIN_REFUND: Color("1e1b19"),
	Kind.DEAL_WEAPON_REFLECT: Color("1e1b19"),
	Kind.DEAL_RETALIATION: Color("1e1b19"),
}

const SHADOW_COLOR := Color("1e1b19", 0.55)
const SHADOW_OFFSET_X_RATIO := 0.06
const SHADOW_OFFSET_Y_RATIO := 0.08

const MIN_FONT_SIZE := 44
const MAX_FONT_SIZE := 88
const MAX_FONT_SIZE_AMOUNT := 30.0

const OUTLINE_RATIO_SMALL := 0.14
const OUTLINE_RATIO_LARGE := 0.18
const OUTLINE_SIZE_BREAKPOINT := 60

const SCALE_START := Vector2(1.7, 1.7)
const SCALE_IN_DURATION := 0.16
const TOTAL_LIFETIME_SEC := 1.1
const ALPHA_HOLD_UNTIL_SEC := 0.72

const ARC_HORIZONTAL_SPEED_MIN := 150.0
const ARC_HORIZONTAL_SPEED_MAX := 230.0
const ARC_VERTICAL_SPEED_MIN := 430.0
const ARC_VERTICAL_SPEED_MAX := 540.0
const ARC_GRAVITY := 950.0
const ARC_ROTATION_MIN_DEG := 4.0
const ARC_ROTATION_MAX_DEG := 9.0
const ARC_SPAWN_JITTER_X := 14.0
const ARC_SPAWN_JITTER_Y := 10.0

# Total rise over the drifting profile's whole lifetime - close to the
# old fixed-Label implementations' own 67px rise (see enemy.gd's old
# DAMAGE_NUMBER_RISE / battle.gd's old inline 67.0).
const DRIFT_RISE_PX := 67.0

var _velocity := Vector2.ZERO
var _gravity := 0.0

# spawn_position is in `parent`'s own local coordinate space (same
# convention PlayerBattleVisual.get_floating_number_anchor()/Enemy.
# get_floating_number_anchor() already return - a global_position/
# to_global() point that lands correctly once handed to a node that's
# only ever nested under ONE CanvasLayer, same as every caller here).
static func spawn(parent: Node, spawn_position: Vector2, amount: int, kind: Kind) -> void:
	var number := new()
	number._configure(spawn_position, amount, kind)
	parent.add_child(number)
	number._start_motion(kind)

func _configure(spawn_position: Vector2, amount: int, kind: Kind) -> void:
	text = ("+%d" if kind in PREFIX_PLUS_KINDS else "-%d") % amount

	var font_size := MIN_FONT_SIZE
	if not (kind in FIXED_SIZE_KINDS):
		var t := clampf(float(amount) / MAX_FONT_SIZE_AMOUNT, 0.0, 1.0)
		font_size = roundi(lerpf(float(MIN_FONT_SIZE), float(MAX_FONT_SIZE), t))
	add_theme_font_size_override("font_size", font_size)

	# Load failure (missing/renamed asset) falls back to no font override -
	# i.e. whatever font this Label would otherwise resolve - rather than
	# erroring, same "degrade, don't crash a hit" instinct the rest of
	# this component's callers depend on.
	var font := load(FONT_PATH) as Font
	if font:
		add_theme_font_override("font", font)

	add_theme_color_override("font_color", FILL_COLORS[kind])
	add_theme_color_override("font_outline_color", OUTLINE_COLORS[kind])
	# ExtraBold's counters are tight enough that a heavy outline at small
	# sizes closes them up - a bigger number can afford a proportionally
	# thicker one.
	var outline_ratio := OUTLINE_RATIO_LARGE if font_size >= OUTLINE_SIZE_BREAKPOINT else OUTLINE_RATIO_SMALL
	add_theme_constant_override("outline_size", roundi(font_size * outline_ratio))

	add_theme_color_override("font_shadow_color", SHADOW_COLOR)
	add_theme_constant_override("shadow_offset_x", roundi(font_size * SHADOW_OFFSET_X_RATIO))
	add_theme_constant_override("shadow_offset_y", roundi(font_size * SHADOW_OFFSET_Y_RATIO))

	var jitter := Vector2.ZERO
	if kind in ARCING_KINDS:
		jitter = Vector2(randf_range(-ARC_SPAWN_JITTER_X, ARC_SPAWN_JITTER_X), randf_range(-ARC_SPAWN_JITTER_Y, ARC_SPAWN_JITTER_Y))
	position = spawn_position + jitter
	scale = SCALE_START

func _start_motion(kind: Kind) -> void:
	if kind in ARCING_KINDS:
		var direction := 1.0 if kind in RIGHTWARD_KINDS else -1.0
		_velocity = Vector2(
			direction * randf_range(ARC_HORIZONTAL_SPEED_MIN, ARC_HORIZONTAL_SPEED_MAX),
			-randf_range(ARC_VERTICAL_SPEED_MIN, ARC_VERTICAL_SPEED_MAX)
		)
		_gravity = ARC_GRAVITY
		rotation_degrees = direction * randf_range(ARC_ROTATION_MIN_DEG, ARC_ROTATION_MAX_DEG)
	else:
		_velocity = Vector2(0.0, -DRIFT_RISE_PX / TOTAL_LIFETIME_SEC)
		_gravity = 0.0

	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE, SCALE_IN_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(ALPHA_HOLD_UNTIL_SEC - SCALE_IN_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, TOTAL_LIFETIME_SEC - ALPHA_HOLD_UNTIL_SEC)
	tween.tween_callback(queue_free)

# Position itself is driven by _process rather than a tween, for both
# motion profiles - the arcing profile needs continuous velocity/gravity
# integration (a Tween can't express a parabola), and the drifting
# profile reuses the exact same per-frame integration with gravity at
# zero rather than forking a second, tween-based path for one straight
# line.
func _process(delta: float) -> void:
	_velocity.y += _gravity * delta
	position += _velocity * delta
