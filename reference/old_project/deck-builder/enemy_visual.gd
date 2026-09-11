extends Node2D
class_name EnemyVisual
# Shared behavior for every enemy silhouette scene (see
# enemy_visual_thicket_stalker.tscn / enemy_visual_glasswing.tscn) - each
# one is a Node2D with this same script attached, whose children are
# hand-authored Polygon2D pieces (the actual shape, unique per enemy,
# original vector art - not an imported sprite). This script never draws
# anything itself; it just applies the exported color to whatever
# Polygon2D children exist and runs the idle animation - same "script
# owns behavior, scene owns shape" split as field_blob.gd/.tscn, and the
# same overall pattern as the player figure (see player_visual.gd) -
# just shared across multiple scenes instead of one, since there's more
# than one enemy silhouette.
#
# No facing/flip (enemies don't have a "which way am I walking" the way
# the player does) and no walk cycle or attack animation - out of scope
# for this pass on purpose.

@export var color: Color = Color(0.6, 0.6, 0.6, 1)

# No exported "how tall is this creature" number - that would go stale
# the moment a shape changes, or fail to mean anything once real art
# (a Sprite2D/AnimatedSprite2D) replaces a hand-drawn Polygon2D here.
# enemy.gd/field_blob.gd instead compute this creature's actual
# rendered bounds at runtime via VisualBounds.compute() (see
# visual_bounds.gd), which works identically no matter what kind of
# node ends up drawing the shape. See DESIGN.md's enemy silhouettes
# note for the authoring convention this depends on: every silhouette's
# shapes are drawn with the creature's FEET at this node's origin
# (y <= 0, extending upward to the head) - VisualBounds computes the
# ACTUAL bottom edge regardless, so a shape that's slightly off this
# convention still positions correctly; the convention just keeps
# authoring predictable.

@export var accent_node_names: Array[String] = []
# Polygon2D children whose OWN authored color should NOT be overridden by
# `color` above - for a small contrasting detail that needs to read as a
# different material/object from the creature's body, not just a lighter
# shade of the same silhouette (the Wardling's harness/collar - see
# enemy_visual_wardling.tscn - is the first thing that needed this;
# Thicket Stalker/Glasswing leave this empty and are completely
# unaffected, every Polygon2D child still gets the uniform `color`).

@export_group("Idle motion")
@export var idle_bob_enabled: bool = true
@export var idle_bob_amount_px: float = 2.0
@export var idle_bob_period_sec: float = 2.0
# Tuned per instance (see each enemy's own .tscn) - slower/bigger reads
# heavier, quicker/smaller reads lighter. Same technique as
# player_visual.gd's idle bob, just parameterized per enemy instead of
# hardcoded, since "reuse the player's idle pattern, tuned per enemy" is
# exactly what this export group is for.

@export_group("Uneven idle motion")
# A second vertical wave, layered on top of the main bob at a
# DIFFERENT, non-harmonic period, so the two beat against each other
# instead of summing into one clean cycle - reads as unsteady/labored
# rather than the other enemies' smooth single-sine bob. Optional slow
# rotational sway on top does the same for "barely holding itself up."
# All default off/zero - existing enemies are unaffected unless they
# opt in.
@export var idle_second_wave_enabled: bool = false
@export var idle_second_wave_amount_px: float = 0.0
@export var idle_second_wave_period_sec: float = 1.0
@export var idle_sway_enabled: bool = false
@export var idle_sway_degrees: float = 0.0
@export var idle_sway_period_sec: float = 1.0

@export_group("Idle horizontal sway")
# A slow, subtle side-to-side DRIFT (position.x), distinct from idle_
# sway above (rotation) - for a creature that should read as gently
# adrift rather than bobbing/rocking in place. 0.0 amount (every enemy's
# default) is a no-op, same "empty means unused" shape every other idle-
# motion knob here already follows - no separate enabled bool needed,
# since zero amplitude already produces zero visible motion on its own.
@export var idle_horizontal_amount_px: float = 0.0
@export var idle_horizontal_period_sec: float = 4.0

@export_group("Hit reaction")
# A small, opt-in reaction on specific child pieces when this creature
# is hit (see play_hit_reaction() below, called from enemy.gd's own
# flash_damage() - the same "every hit" moment the whole-body color
# flash already plays on, layered on top of it rather than replacing
# it). Empty (every enemy before Tideworn) is a no-op, same "opt in per
# instance via a node-name list" shape accent_node_names above already
# established - this isn't Tideworn-specific code, just the first
# creature to configure it.
@export var hit_dip_node_names: Array[String] = []
@export var hit_dip_amount_px: float = 4.0
@export var hit_dip_duration_sec: float = 0.14

@export_group("Growth sprite stages")
# Per-stage texture swap for a GROWTH-track enemy (see enemy_data.gd's
# growth_stage_track_length doc) - the Mushroom's own turn-by-turn "how
# close to bursting" readout, communicated through the art itself, not
# just the numeric countdown (show_growth_countdown()). Layers WITH the
# existing growth-scale ramp (EnemyData.min_growth_scale/max_growth_
# scale, a whole-body size increase, the primitive stand-in animation
# from before this sprite art existed) rather than replacing it - a
# still-swelling body wearing a progressively worse-looking sprite, not
# an either/or (see EnemyData.min_growth_scale's own doc for the brief
# 2026-08-29 removal-then-restore). index 0 = the FIRST stage shown
# (growth_stage 0, the full countdown), the
# LAST entry = the stage shown the turn before eruption. Empty (every
# enemy without this configured) is a complete no-op - set_growth_
# sprite_stage() below returns
# immediately, same "empty means unaffected" shape hit_dip_node_names
# above already uses. Swaps $Sprite's own texture directly - the
# established single-sprite-child name every sprite-based enemy visual
# (Gun/Supply/Beachwrack/Boss) already uses, not a second configurable
# node-name list, since nothing has needed more than one sprite child
# yet.
@export var growth_stage_textures: Array[Texture2D] = []

# Called by enemy.gd's own set_growth_sprite_stage() (mirrors set_
# growth_scale()'s own two call sites - spawn and every stage advance),
# itself called from battle.gd's _spawn_enemies()/_advance_growth_
# stage(). Clamped, not wrapped or asserted - an out-of-range stage
# (track_length authored longer than the sprite array) just holds on the
# last available texture rather than erroring or going blank.
func set_growth_sprite_stage(stage: int) -> void:
	if growth_stage_textures.is_empty():
		return
	var sprite := get_node_or_null("Sprite") as Sprite2D
	if sprite == null:
		return
	var index := clampi(stage, 0, growth_stage_textures.size() - 1)
	sprite.texture = growth_stage_textures[index]

var _hit_dip_tween: Tween

var _bob_time: float = 0.0
var _base_position_x: float = 0.0
var _base_position_y: float = 0.0
# Whatever position.y already holds the instant _ready() runs - in
# BATTLE that's always 0 (enemy.gd never sets visual.position, only its
# wrapper's - see enemy.gd's own comment), but in the FIELD, field_
# blob.gd's _build_member_visual() sets this node's position.y to a real
# non-zero anchor (foot placement + scale + the global/per-enemy drop
# offsets) BEFORE add_child() ever triggers this _ready(). The bob below
# used to overwrite position.y with JUST the sine wave every frame,
# silently discarding that anchor back to ~0 the instant idle motion
# started - invisible for most enemies (their computed anchor happened
# to already be close to 0) but very visible once a large offset (like
# all_enemies_field_drop_px) was added. Capturing the anchor here and
# adding bob AROUND it (not replacing it) fixes both.

func _ready() -> void:
	_base_position_x = position.x
	_base_position_y = position.y
	for child in get_children():
		if child is Polygon2D and child.name not in accent_node_names:
			child.color = color

func _process(delta: float) -> void:
	if not idle_bob_enabled:
		return
	_bob_time += delta
	var y := sin(_bob_time * TAU / idle_bob_period_sec) * idle_bob_amount_px
	if idle_second_wave_enabled:
		y += sin(_bob_time * TAU / idle_second_wave_period_sec) * idle_second_wave_amount_px
	position.y = _base_position_y + y
	position.x = _base_position_x + sin(_bob_time * TAU / idle_horizontal_period_sec) * idle_horizontal_amount_px
	if idle_sway_enabled:
		rotation = deg_to_rad(idle_sway_degrees) * sin(_bob_time * TAU / idle_sway_period_sec)

# Called by enemy.gd's flash_damage() on every hit this creature takes -
# a quick out-and-back dip on whichever named children hit_dip_node_
# names lists (Tideworn's own L_Eyestalk/R_Eyestalk today), independent
# of the idle bob above: idle motion only ever touches THIS node's own
# position (see _process()), never a child's, so the two compose
# cleanly - a dipping eyestalk still rides along with the whole
# creature's own idle bob, on top of its own local dip. No-op if this
# instance hasn't configured any (every enemy before Tideworn).
func play_hit_reaction() -> void:
	if hit_dip_node_names.is_empty():
		return
	var nodes: Array[Node2D] = []
	for node_name in hit_dip_node_names:
		var node := get_node_or_null(NodePath(node_name)) as Node2D
		if node != null:
			nodes.append(node)
	if nodes.is_empty():
		return

	if _hit_dip_tween:
		_hit_dip_tween.kill()
	_hit_dip_tween = create_tween()
	_hit_dip_tween.set_parallel(true)
	var dip_out_duration := hit_dip_duration_sec * 0.4
	var dip_back_duration := hit_dip_duration_sec * 0.6
	for node in nodes:
		# Each node's own CURRENT position.y, not a cached "resting"
		# value - a kill()'d tween can leave a node mid-dip if a second
		# hit lands before the first one finished, and reading its
		# actual current value here is what makes the new dip start from
		# wherever it really is instead of snapping back first.
		var base_y := node.position.y
		_hit_dip_tween.tween_property(node, "position:y", base_y + hit_dip_amount_px, dip_out_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		_hit_dip_tween.tween_property(node, "position:y", base_y, dip_back_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN).set_delay(dip_out_duration)
