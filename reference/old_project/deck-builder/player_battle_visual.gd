extends Control
class_name PlayerBattleVisual
# The player's presence in battle - a silhouette, standing on the left,
# with its own compact vitals cluster beneath it. The battle-side sibling
# of Enemy (see enemy.gd) - same bottom-anchored positioning convention
# (silhouette's feet a fixed gap above the bar, computed from the
# silhouette's real rendered bounds via VisualBounds.compute(), not
# assumed), same VitalsBar-width-clamping trick, same public update_hp()/
# update_block() surface Battle calls. Deliberately NOT sharing code with
# Enemy's version: Enemy's layout math is interleaved with name/intent/
# flavor logic this side has no equivalent of, and this pass is required
# to leave enemy behavior untouched - separating out just the shared
# formula would mean restructuring existing, working code for a fairly
# small amount of duplication. No hover, no name introduction, no
# intent - none of those apply to the player.
#
# The battle-only silhouette (2026-08-27) - wanderer_battle_visual.tscn,
# a plain Node2D wrapping a single Sprite2D (assets/characters/wanderer/
# wanderer_battle.png), same "wrapper node, real content is in its
# children" shape an enemy_visual_*.tscn already uses (see VisualBounds.
# compute()'s own note on why bounds are read from children, never the
# wrapper itself). Deliberately NOT player_visual.gd/player_visual.tscn
# (the walking rig field_room.tscn's own Player/Visual node uses) - that
# script's idle/walk cycle is a field-only concern (it animates off a
# CharacterBody2D parent's velocity, which nothing in battle has), and
# battle now has its own dedicated art instead of a static "idling" pose
# borrowed from the field rig. field_room.gd's own use of player_visual.
# gd/.tscn is completely untouched by this - the two contexts no longer
# share a visual at all, only the same VisualBounds-driven layout math.

const PLAYER_VISUAL_SCENE := preload("res://wanderer_battle_visual.tscn")

@export_group("Vitals Cluster Layout")
@export var cluster_width_px: float = 440.0
@export var silhouette_scale: float = 0.3
# wanderer_battle.png is a large source image (1355x1161px) - nowhere
# near player_visual.gd's old small field-scale rig (~61px tall at scale
# 1.0, hence that version's own much bigger 4.5 default), so this scales
# DOWN rather than up. Matches battle.tscn's own existing PlayerBattleVisual
# override (also 0.3 - tuned for this same image already, not a stale
# leftover). A first guess, not a measured match to any specific enemy -
# tune by eye, same as before.
@export var bar_top_px: float = 420.0
# MUST match Enemy's own bar_top_px (see its comment) - both clusters'
# bars land at the same on-screen height when EnemyZone and this share
# the same outer offset_top in battle.tscn, so left/right reads as
# genuinely level, not just "both somewhere near the top." This is the
# mechanism behind the Battle Layout tuning pass's "shared horizontal
# baseline" ask - retune this value only in lockstep with Enemy's.
@export var bar_gap_px: float = 15.0
@export var bar_width_px: float = 220.0
@export var bottom_margin_px: float = 25.0
# No toll_row_gap_px any more (REMOVED 2026-08-25, resource-cluster
# pass) - TollDisplay no longer lives here at all; it moved into
# player_resource_cluster.tscn, grouped with the energy pips instead of
# sitting below this cluster's own HP bar. See DESIGN.md's Toll entry
# ("Promoted into a real player-resource cluster") for the full history.

@onready var vitals_bar: VitalsBar = $VitalsBar
@onready var visual_container: Node2D = $VisualRoot
@onready var grounding: Grounding = $Grounding

# Set by _setup_visual() - the silhouette's real rendered bounds, in its
# own pre-scale local space (see VisualBounds.compute()). Same role as
# Enemy's _silhouette_bounds; kept separate rather than shared since
# there's exactly one of these per PlayerBattleVisual, never re-rolled.
var _silhouette_bounds: Rect2 = Rect2()

# Set by _apply_layout() - see its own note. Read by play_attack_nudge().
var _rest_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_setup_visual()
	_apply_layout()
	# Contact shadow (2026-09-01, battle grounding pass, ordering fix) -
	# AFTER _apply_layout(), not from inside _setup_visual() any more: the
	# shadow's own position is baked ONCE, at call time, from visual_
	# container's CURRENT transform (see EntityShadow.attach()'s own doc) -
	# calling it before _apply_layout() has set visual_container.position
	# captured the scene's pre-layout identity transform instead, landing
	# the shadow nowhere near the actual character (2026-09-01 investigation
	# report). _apply_layout() has exactly one call site (this one) and
	# there is only ever one PlayerBattleVisual instance per battle, so this
	# runs exactly once - no re-layout path exists that would need this
	# idempotent.
	grounding.apply_contact_shadow(self, visual_container)
	# Off until a stance actually goes active (see set_stance_tint() below) -
	# without this, _process() would run from frame one and immediately hit
	# _stance_tint_glow while it's still null (nothing has created it yet).
	set_process(false)
	# Initial snap, then a live subscription (2026-09-05, HP-signal pass) -
	# same "_snap() once, then connect()" shape gold_display.gd's own
	# _ready() already establishes, and run_hud.gd/field_interior.gd's own
	# matching subscriptions now use too. battle.gd's own _update_player_
	# panel() no longer pushes HP (see its own doc) - RunState.player_hp_
	# changed does that job now, at whatever frequency battle actually
	# changes HP, with no change to update_hp()'s own tween behavior.
	vitals_bar.refresh_from_run_state()
	RunState.player_hp_changed.connect(_on_player_hp_changed)

func _setup_visual() -> void:
	var visual: Node2D = PLAYER_VISUAL_SCENE.instantiate()
	# Same mechanism as enemy.gd's own _setup_visual(): scale the
	# instanced root directly, right after instancing. Safe here for the
	# same reason it's safe there - wanderer_battle_visual.tscn's own root
	# is a plain, script-less Node2D wrapper (see PLAYER_VISUAL_SCENE's
	# own note) that never touches its own scale, so this assignment is
	# never fought over or silently overwritten.
	visual.scale = Vector2(silhouette_scale, silhouette_scale)
	visual_container.add_child(visual)
	_silhouette_bounds = VisualBounds.compute(visual)

# One pass, not two like Enemy's _apply_bar_layout()/_apply_creature_
# layout() split - Enemy needs that split because its creature gets
# swapped AFTER _ready() (see set_enemy_data()); the player silhouette
# never changes, so everything can run together here in _ready().
func _apply_layout() -> void:
	# Both custom_minimum_size.x and size.x, same reason vitals_bar.gd/
	# block_badge.gd/enemy.gd all do this - Control.size is clamped to
	# never go BELOW custom_minimum_size, but lowering the minimum
	# doesn't retroactively shrink an already-larger size, so both need
	# setting explicitly for cluster_width_px to actually take effect if
	# ever tuned down from whatever's baked in player_battle_visual.tscn.
	custom_minimum_size.x = cluster_width_px
	size.x = cluster_width_px

	vitals_bar.position = Vector2((cluster_width_px - bar_width_px) / 2.0, bar_top_px)
	vitals_bar.custom_minimum_size.x = bar_width_px
	vitals_bar.size.x = bar_width_px

	# Solves for visual_container's position such that the silhouette's
	# ACTUAL bottom edge (_silhouette_bounds.end.y, whatever that number
	# is - the player figure is centered on its own origin, not
	# feet-at-origin like an enemy silhouette, and this formula doesn't
	# care either way) lands exactly at feet_y.
	var feet_y := bar_top_px - bar_gap_px
	var scaled_bottom := _silhouette_bounds.end.y * silhouette_scale
	visual_container.position = Vector2(cluster_width_px / 2.0, feet_y - scaled_bottom)
	_rest_position = visual_container.position
	# The attack-nudge baseline (see play_attack_nudge() below) - cached
	# here, once, as the true anchor it needs to return to. Nothing else
	# in this file ever touches visual_container's own position (only its
	# scale/modulate - see play_hp_cost_flinch()), so this never has
	# another animation to reconcile with the way enemy.gd's own _rest_
	# position does against recession/lunge/flinch all sharing one node.

	custom_minimum_size = Vector2(cluster_width_px, bar_top_px + vitals_bar.size.y + bottom_margin_px)

func update_hp(current: int, max_hp: int) -> void:
	vitals_bar.update_hp(current, max_hp)

func _on_player_hp_changed(new_hp: int, new_max_hp: int) -> void:
	update_hp(new_hp, new_max_hp)

func update_block(amount: int) -> void:
	vitals_bar.update_block(amount)

func update_absorb(amount: int) -> void:
	vitals_bar.update_absorb(amount)

func update_rally_pool(current: int, pool: int) -> void:
	vitals_bar.update_rally_pool(current, pool)

func drain_rally_pool(current: int) -> void:
	vitals_bar.drain_rally_pool(current)

func reset_rally_pool() -> void:
	vitals_bar.reset_rally_pool()

func update_statuses(statuses: Array[ActiveStatus]) -> void:
	vitals_bar.update_statuses(statuses)

# Battle.gd's floating damage/heal numbers anchor to this instead of
# reaching into vitals_bar directly - global_position (not position),
# since vitals_bar sits two levels deep (PlayerBattleVisual -> VitalsBar)
# and battle.gd's floating-number Label is parented under UI, a sibling
# of this whole cluster, not a descendant of it.
func get_floating_number_anchor() -> Vector2:
	return vitals_bar.global_position

# --- Attack nudge (see DESIGN.md's Combat Telegraphing note) ---
#
# A small forward jerk toward the enemy when an ATTACK card is played -
# the player-side mirror of enemy.gd's own play_attack_lunge(), same
# "brief, fast jerk... enough motion to sell 'this thing just hit me'"
# instinct, just aimed the other way and reading as "about to hit," not
# "just got hit." +X here, not -X - the player always stands on the
# LEFT (see enemy.gd's own note on why -X is always "toward the player"
# for an enemy; toward the ENEMY from here is the opposite direction).
# Deliberately smaller/subtler than the enemy's own lunge (22px vs 30px)
# - "nothing major, just enough to give a bit of weight," not a full
# attack animation; a SKILL card (Guard, Paid in Pain, Retaliation - see
# CardData.CardType) never calls this, only an ATTACK does, the same
# card_type check _card_matches_scope()'s own ALL_ATTACKS scope already
# uses in battle.gd. Called from battle.gd's _play_card(), fired the
# instant the card is confirmed played (alongside its own sfx), not
# awaited - the swing motion and the effect resolving happen in
# parallel, same "fire-and-forget cosmetic reaction" shape every other
# non-blocking animation in this codebase already follows.
@export_group("Attack Nudge")
@export var attack_nudge_distance_px: float = 22.0
@export var attack_nudge_out_sec: float = 0.08
@export var attack_nudge_return_sec: float = 0.15

var _nudge_tween: Tween

func play_attack_nudge() -> void:
	if _nudge_tween:
		_nudge_tween.kill()
	var rest_x := _rest_position.x
	_nudge_tween = create_tween()
	_nudge_tween.tween_property(visual_container, "position:x", rest_x + attack_nudge_distance_px, attack_nudge_out_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_nudge_tween.tween_property(visual_container, "position:x", rest_x, attack_nudge_return_sec).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

# --- HP-cost/chain-refund character reactions (see DESIGN.md's
# Wanderer entry) ---
#
# Built for Bite Down originally; its own chain-refund payoff was
# removed 2026-08-26 (see DESIGN.md's "Bite Down's chain payoff:
# REVERSED"), so play_chain_refund_aura() below has no live caller
# today - play_hp_cost_flinch() still fires for every SELF_DAMAGE
# effect, Bite Down's included, since that cost is unconditional now.
# Both functions are generic over the MECHANIC, not Bite-Down-
# specific code, and stay fully intact for whatever uses them next -
# see card_data.gd's own chain_followup_effect note.
#
# Two character-centered reactions to HP moving because of a CARD, not
# a hit landing - deliberately built to never look alike despite both
# being red/blood-toned, since they mean opposite things: the cost
# pulls the character inward and darkens (blood draining OUT), the
# refund's aura pulses outward and brightens AROUND the character
# (blood staying in/returning to the body). Different MOTION (inward
# vs. outward), different WEIGHT (a plain tint vs. a whole extra glow
# shape only the refund gets), not just two different colors on the
# same animation - see battle.gd's own _deal_self_damage()/_heal_player()
# for where each is called from.

@export_group("HP Cost Flinch")
@export var hp_cost_flinch_color: Color = Color(0.3, 0.05, 0.05, 1)
@export var hp_cost_flinch_scale: float = 0.9
@export var hp_cost_flinch_duration_sec: float = 0.35

@export_group("Chain Refund Aura")
@export var chain_refund_aura_color: Color = Color(0.85, 0.1, 0.1, 0.5)
@export var chain_refund_aura_radius_px: float = 140.0
# Sized to comfortably envelop the rendered figure (~275px tall at this
# scene's own silhouette_scale, per player_visual.gd's ~61px base height
# - see this script's own silhouette_scale note above), not the tiny
# pre-scale figure size - tune by eye once visible, this is a reasoned
# starting point, not a measured one.
@export var chain_refund_pulse_period_sec: float = 0.35
@export var chain_refund_pulse_count: int = 3
@export var chain_refund_aura_min_scale: float = 0.8
@export var chain_refund_aura_max_scale: float = 1.2

# The HP-cost "flinch" - no lunge, no knockback the way an enemy's
# attack gets (see enemy.gd's play_attack_lunge() note on why DEFEND
# stays visually calm instead - same "different kind of event, different
# treatment" instinct here): the character briefly pulls inward and
# darkens in place, reading as blood draining out rather than a hit
# landing. Called from battle.gd's _deal_self_damage() for every
# SELF_DAMAGE effect, not just Bite Down specifically - generic over
# the mechanic, the same "don't special-case one card in shared code"
# rule the chain payoff system itself already follows.
func play_hp_cost_flinch() -> void:
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(visual_container, "scale", Vector2.ONE * hp_cost_flinch_scale, hp_cost_flinch_duration_sec * 0.4).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(visual_container, "modulate", hp_cost_flinch_color, hp_cost_flinch_duration_sec * 0.4)
	tween.chain().tween_property(visual_container, "scale", Vector2.ONE, hp_cost_flinch_duration_sec * 0.6).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(visual_container, "modulate", Color.WHITE, hp_cost_flinch_duration_sec * 0.6)

# The chain refund's own aura - a red glow pulsing AROUND the character
# (not a burst near the HP bar, which read as a UI effect rather than
# something happening to the character - see battle.gd's _heal_player()
# own note), brightening and expanding a few times before fading,
# reading as blood staying in/returning to the body. Called only when
# chain_payoff is true - an ordinary heal card like Kept Warmth never
# triggers this. No card sets a HEAL-type chain_followup_effect today
# (Bite Down's own refund was removed 2026-08-26 - see DESIGN.md's
# Wanderer entry), so this has no live caller right now, but stays
# ready for whatever uses that shape next.
func play_chain_refund_aura() -> void:
	var aura := Polygon2D.new()
	aura.polygon = _circle_points(chain_refund_aura_radius_px, 32)
	aura.color = chain_refund_aura_color
	aura.modulate.a = 0.0
	visual_container.add_child(aura)

	var tween := create_tween()
	for i in chain_refund_pulse_count:
		tween.tween_property(aura, "scale", Vector2.ONE * chain_refund_aura_max_scale, chain_refund_pulse_period_sec / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(aura, "modulate:a", 1.0, chain_refund_pulse_period_sec / 2.0)
		tween.tween_property(aura, "scale", Vector2.ONE * chain_refund_aura_min_scale, chain_refund_pulse_period_sec / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(aura, "modulate:a", 0.4, chain_refund_pulse_period_sec / 2.0)
	tween.tween_property(aura, "modulate:a", 0.0, chain_refund_pulse_period_sec / 2.0)
	tween.finished.connect(aura.queue_free)

# --- Stance tint (placeholder - see DESIGN.md/battle.gd's own Selfeater
# note) ---
#
# The one visual hook a STANCE status needs (2026-08-28, Selfeater pass):
# a persistent glow, intensity scaling with stack count, for as long as
# the status is active. Isolated behind set_stance_tint() below so the
# real art/shader treatment can replace everything in this section
# without battle.gd (its only caller) needing to change at all - it only
# ever passes a stack count in, never touches these nodes/tweens
# directly. PLACEHOLDER - do not invest further here; a flat-colored
# Polygon2D glow, not a shader, same "small hand-drawn shape" language
# every other placeholder combat visual in this project already uses.
@export_group("Stance Tint (placeholder)")
@export var stance_tint_color: Color = Color(0.5, 0.42, 0.68, 1)
# MATCHES card.gd's CARD_TYPE_ART_COLORS[CardData.CardType.STANCE] exactly
# (2026-08-28, glow-legibility pass) - was a separate, more red-leaning
# violet (0.42, 0.3, 0.55) picked independently for this placeholder glow.
# Investigated live (see this pass's own report) whether the glow reading
# pink against Sunken Works' backdrop was a hue shift in the gradient
# itself - it isn't (there was no gradient before this pass; a flat single
# color can't shift hue across its own shape). It's ordinary alpha
# compositing: this glow sits at LOW alpha over a warm tan/gray ground
# (sampled directly from SunkenWorks1.png, not eyeballed - average ~
# (0.57, 0.54, 0.51)), and blending a translucent violet over a warm
# background pulls the *result* toward magenta/pink the lower the alpha
# is, regardless of which violet you start from. Measured composite hue
# (Color.h) for THIS color over that exact ground: ~0.79 (pinkish-mauve)
# at alpha 0.3, settling to ~0.72-0.76 (clearly violet) only once alpha
# clears roughly 0.4. That's what stance_tint_alpha_per_stack/_max below
# are now sized around, not just "make it more visible."
@export var stance_tint_alpha_per_stack: float = 0.42
# RAISED from 0.3 (2026-08-28, glow-legibility pass) - 0.3 sat right at
# the edge of the pink-vs-violet threshold above (see stance_tint_color's
# own doc), so stack 1, the common case and the first thing a player
# sees, read borderline pink rather than violet. 0.42 clears that
# threshold with margin even at the pulse's own trough (baseline minus
# stance_tint_pulse_amplitude below).
@export var stance_tint_alpha_max: float = 0.85
# RAISED from 0.55 (2026-08-28, glow-legibility pass) - two independent
# reasons pushed this up together, not one: (1) stack 2's raw baseline
# (0.42*2=0.84) needs headroom above it to still read as an escalation
# over stack 1, not clamp flat immediately; (2) the higher per-stack
# floor above only fixes the pink-read AT that floor - the cap has to
# clear the same ~0.4 hue-threshold too, or a heavily-stacked glow would
# get clamped back down into pink range by its own ceiling. 0.85 clears
# both with room to spare for the pulse's own swing on top.
@export var stance_tint_radius_px: float = 140.0
@export var stance_tint_falloff_start: float = 0.25
# Normalized fraction of the radius (0=center, 1=outer edge) where the
# gradient STARTS fading from full alpha toward zero (2026-08-28,
# soft-edge pass) - see _build_stance_tint_texture() below, the tunable
# this pass's own brief asked to be exposed if it wasn't already (it
# wasn't - the old Polygon2D had no gradient at all, just one flat alpha
# across the whole disc, which is exactly why it read as a hard-edged
# disc sitting on the ground rather than light). LOW on purpose (a
# quarter of the radius) - the fade spans nearly the whole shape rather
# than staying solid until the last moment, which is what actually kills
# the perceptible boundary the brief calls out. Raise this toward 1.0 for
# a smaller, thinner fade ring instead; 0.0 fades from the very center.
@export var stance_tint_pulse_period_sec: float = 3.0
# Seconds per full breathe cycle (2026-08-28, pulse pass) - slow on
# purpose, per this pass's own brief ("a few seconds per cycle"): this
# has to read as something ongoing and alive in the background, not as
# an alert competing for attention. EYEBALLED, retune by eye like every
# other number in this section.
@export var stance_tint_pulse_amplitude: float = 0.08
# How far alpha swings above/below its stack-derived baseline at the
# peak/trough of each cycle - small on purpose, so stack count (see
# stance_tint_alpha_per_stack/_max) stays the thing that actually reads
# as "how strong is this," with the pulse riding on top as texture, not
# competing with it for meaning. RAISED slightly from 0.06 (2026-08-28,
# glow-legibility pass) alongside the baseline raise above - the old
# swing read as imperceptible partly because alpha alone is a weak
# channel on a soft shape (see stance_tint_pulse_radius_amplitude_px
# below, the other, bigger fix for that) and partly because it was
# happening on top of a low, pink-tinted baseline that was already hard
# to see clearly at all.
@export var stance_tint_pulse_radius_amplitude_px: float = 12.0
# How many pixels the glow's radius swings above/below stance_tint_
# radius_px at the peak/trough of each cycle (2026-08-28, pulse-
# perceptibility pass) - a moving edge on a soft-edged shape reads far
# more clearly than a brightness change alone, which is the whole reason
# this exists alongside stance_tint_pulse_amplitude rather than instead
# of it. Uses the SAME phase (see _process() below) as the alpha pulse,
# so the two are locked in phase on the same period by construction, not
# by two independently-tuned timers that could drift apart. Small
# relative to stance_tint_radius_px on purpose - a breath, not a throb.
@export var stance_tint_offset: Vector2 = Vector2(-75.0, 25.0)
# Where the glow's own center sits, in visual_container's local space,
# relative to visual_container's origin (0,0) - NOT the same point as
# the character's visual mass (see below). Left and slightly down from
# Vector2.ZERO (2026-08-28, glow-adjustment pass) - EYEBALLED, not
# measured, a starting point to retune by eye, not a precise value.
#
# WHY an offset is needed at all: wanderer_battle_visual.tscn's Sprite2D
# (assets/characters/wanderer/wanderer_battle.png, 1355x1161px) is
# `centered = true` with no `offset` override, so it renders centered
# exactly on visual_container's origin - and _stance_tint_glow, with no
# position of its own, rendered there too. Opening the actual PNG shows
# why that reads wrong: the hooded figure's own mass (cloak, torso, legs)
# occupies roughly the left half to two-thirds of the canvas, while the
# extended sword arm reaches into the right third, leaving that whole
# right region mostly transparent. The image's own geometric center
# lands in that gap between the body and the blade, not on the figure -
# confirmed visually, not assumed. This offset is authored in visual_
# container's local space, which is silhouette_scale (0.3) applied
# ALREADY - it does NOT need dividing by that scale itself, since it's
# added directly to _stance_tint_glow.position below, a sibling-space
# offset, not a child of the scaled `visual` node.

var _stance_tint_glow: Sprite2D = null
# Created once, on first real use, then reused/updated in place - unlike
# play_chain_refund_aura()'s own aura (a one-shot pulse-then-queue_free),
# this needs to persist and be re-intensified as stacks grow, not replay
# from scratch each time. Sprite2D, not the old Polygon2D (2026-08-28,
# soft-edge pass) - a real per-pixel gradient falloff is the whole point
# of that pass, and a flat-fill Polygon2D has no way to paint one without
# a shader, which this file's own placeholder philosophy explicitly
# avoids (see the "Stance Tint (placeholder)" export group's own header).
# GradientTexture2D (built once in _build_stance_tint_texture() below) is
# a plain built-in Godot resource, not a shader - it just gets sampled by
# an ordinary Sprite2D like any other texture.

const STANCE_TINT_TEXTURE_SIZE := 256
# Fixed pixel size of the generated gradient texture (2026-08-28, soft-
# edge pass) - big enough that the radial gradient has no visible
# banding at anything this glow is actually scaled to on screen, small
# enough to build instantly and cheaply. The glow's actual on-screen
# radius is controlled entirely by _stance_tint_glow.scale (see
# set_stance_tint()/_process() below), never by resizing this texture -
# at scale 1.0 the gradient's own edge (fill_to, see _build_stance_tint_
# texture()) lands exactly at half this size, i.e. stance_tint_radius_px
# read as "128px" would need scale 1.0; any other value is just scale =
# radius / (STANCE_TINT_TEXTURE_SIZE / 2.0).

var _stance_tint_pulse_time: float = 0.0
# A free-running accumulator (2026-08-28, pulse pass), NOT a Tween -
# advanced every frame in _process() below, unconditionally, regardless
# of anything else happening to the glow (a stack count change, play_hp_
# cost_flinch()'s own tween on visual_container - a COMPLETELY DIFFERENT
# node/property, see that flinch-isolation note below). Nothing but this
# field and _process() ever touches it - "the pulse must survive flinch
# without being reset or desynchronised" holds structurally, not because
# some call site remembered to leave it alone.

var _stance_tint_baseline: float = 0.0
# The stack-derived alpha set_stance_tint() below last computed - the
# pulse's own CENTER, recomputed once per stack change and then held
# steady while _process() oscillates the actual rendered alpha around it
# every frame. Its own field, not re-derived from modulate.a (which
# _process() is itself constantly overwriting) - that split is what
# keeps "stack intensity remains the baseline" exactly true instead of
# the pulse's own output slowly bleeding into what the next frame treats
# as the baseline.

# A SEPARATE overlay node, not a modulate change on visual_container
# itself, deliberately: visual_container.modulate is already owned by
# play_hp_cost_flinch()'s transient flinch tween, which ENDS by resetting
# it to Color.WHITE - Selfeater's own drain (once wired) calls that same
# flinch on every attack it taxes, so a persistent tint parked on visual_
# container.modulate would get silently erased by the very next attack's
# flinch. Mirrors play_chain_refund_aura()'s own "a Polygon2D glow, not a
# body-color hack" shape instead, sidestepping that conflict entirely.
# stack_count <= 0 hides it (the "no Selfeater active" case) rather than
# freeing it - same "empty means unaffected, cheap to leave around" shape
# every other optional visual state in this file already follows.
func set_stance_tint(stack_count: int) -> void:
	if stack_count <= 0:
		if _stance_tint_glow != null:
			_stance_tint_glow.visible = false
		# Stops the pulse cleanly (2026-08-28, pulse pass) - _process()
		# below simply never runs while this is off, rather than running
		# and no-oping every frame. _stance_tint_pulse_time is deliberately
		# NOT reset here - if the stance goes active again later this same
		# battle, the pulse resumes mid-cycle rather than restarting from
		# a fresh breath, which reads as more continuous, not that it was
		# ever meaningfully "off." (Not reachable via Selfeater today -
		# its own status never expires or gets removed mid-battle - but
		# this function has to stay correct for stack_count reaching 0 by
		# any future path, not just the ones that exist right now.)
		set_process(false)
		return
	if _stance_tint_glow == null:
		_stance_tint_glow = Sprite2D.new()
		_stance_tint_glow.texture = _build_stance_tint_texture()
		_stance_tint_glow.position = stance_tint_offset
		visual_container.add_child(_stance_tint_glow)
		# Behind the character silhouette, not painted over it - index 0
		# is first-drawn regardless of sibling order, same "glow reads as
		# coming FROM the character" intent play_chain_refund_aura() shares.
		visual_container.move_child(_stance_tint_glow, 0)
	_stance_tint_glow.visible = true
	# Only the BASELINE updates here - the actual rendered alpha (modulate.
	# a) is _process()'s job now, every frame, oscillating around whatever
	# this is currently set to. Stack intensity change and pulse motion are
	# two separate concerns on purpose (see this pass's own brief: "stack
	# intensity remains the baseline; the pulse modulates around it rather
	# than replacing it") - this line owns the first, _process() owns the
	# second, and neither touches the other's job.
	_stance_tint_baseline = min(stance_tint_alpha_per_stack * stack_count, stance_tint_alpha_max)
	set_process(true)

# Advances the breathe cycle every frame, unconditionally, for as long as
# this is enabled (see set_stance_tint() above for the only two places
# that flip it) - a raw sine, not a Tween: sin()'s own derivative (cos())
# is zero at both the peak and the trough, which is exactly "eases at
# both extremes rather than reversing sharply" for free, with no easing
# curve layered on top needed. A linear triangle wave would instead hold
# constant slope right up to an abrupt direction change at each extreme -
# the "throb"/"alert" read this pass's own brief explicitly doesn't want.
#
# Runs completely independently of play_hp_cost_flinch()'s own tween,
# which animates visual_container.modulate - a different node
# (visual_container, not _stance_tint_glow) and a different property
# path entirely. There is no shared state between the two to fight over;
# this is what "survives flinch without being reset or desynchronised"
# actually rests on, not a guard checked here.
func _process(delta: float) -> void:
	_stance_tint_pulse_time += delta
	# The CENTER is capped, not the final result (2026-08-28, pulse pass) -
	# clamping the result AFTER adding the swing is what would visibly
	# flat-top the peak at high stack counts (see this pass's own brief):
	# once _stance_tint_baseline alone already sits at stance_tint_alpha_
	# max (stack 2+ today - see that export's own doc), any positive swing
	# added on top would get chopped to the exact same value every single
	# cycle, reading as a held plateau, not a peak. Pulling the CENTER down
	# by amplitude instead keeps the full sine shape intact - the peak just
	# touches the cap rather than clipping through it - at the cost of the
	# visible center sitting very slightly below the raw stack baseline,
	# ONLY once that baseline is already within one amplitude of the cap.
	# At low stacks (the common case) center == baseline, untouched.
	var center: float = min(_stance_tint_baseline, stance_tint_alpha_max - stance_tint_pulse_amplitude)
	var phase := TAU * _stance_tint_pulse_time / stance_tint_pulse_period_sec
	var alpha := center + stance_tint_pulse_amplitude * sin(phase)
	# Defensive floor/ceiling on the FINAL value, on top of the center cap
	# above - belt-and-suspenders, not the primary mechanism: with the
	# small amplitudes this is tuned for, center's own cap already keeps
	# this a no-op in every real case, but a future large amplitude
	# shouldn't be able to push this negative or past the cap either.
	_stance_tint_glow.modulate.a = clamp(alpha, 0.0, stance_tint_alpha_max)
	# Radius rides the SAME `phase` the alpha swing above just computed
	# (2026-08-28, pulse-perceptibility pass) - not a second sin() with its
	# own time/period, which could drift out of sync with the alpha pulse
	# over a long fight. In phase, same period, by construction. No center-
	# capping equivalent needed here the way alpha has one: stance_tint_
	# radius_px is a fixed constant, never stack-scaled (see that export's
	# own doc), so there's no baseline-approaching-a-ceiling case for this
	# swing to clip against.
	var current_radius_px := stance_tint_radius_px + stance_tint_pulse_radius_amplitude_px * sin(phase)
	_stance_tint_glow.scale = Vector2.ONE * (current_radius_px / (STANCE_TINT_TEXTURE_SIZE / 2.0))

# Builds the radial-gradient texture _stance_tint_glow above samples -
# called once, when the glow is first created (2026-08-28, soft-edge
# pass). A GradientTexture2D, not a shader (see _stance_tint_glow's own
# doc on why that boundary matters here) - Gradient's own CUBIC
# interpolation between stops does the actual easing work, the same
# "smooth at both extremes" requirement the alpha/radius pulse already
# follow via sin(), applied here to the SPATIAL falloff instead of a
# value over time.
#
# Three stops, not a plain 0-to-1 fade: alpha stays at full from the
# center out to stance_tint_falloff_start, THEN eases down to zero by
# the outer edge. A gradient that starts fading at the very center reads
# as dim and washed-out throughout; holding full alpha through the
# middle and concentrating the entire fade into the outer band is what
# actually produces "light around the character" instead of "dim disc."
# fill_from/fill_to set a RADIAL fill from the texture's own center out
# to its right edge (both in the texture's normalized 0..1 UV space,
# independent of stance_tint_radius_px - the SPRITE's scale is what maps
# this fixed gradient onto an actual on-screen radius, see _process()).
# Baked with stance_tint_color's full RGB at every stop and only alpha
# varying, so nothing here can introduce a hue shift across the shape -
# see stance_tint_color's own doc for why that specifically was checked
# and ruled out as the source of the pink/violet issue.
func _build_stance_tint_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	var full: Color = stance_tint_color
	var transparent := Color(stance_tint_color.r, stance_tint_color.g, stance_tint_color.b, 0.0)
	gradient.offsets = PackedFloat32Array([0.0, stance_tint_falloff_start, 1.0])
	gradient.colors = PackedColorArray([full, full, transparent])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = STANCE_TINT_TEXTURE_SIZE
	texture.height = STANCE_TINT_TEXTURE_SIZE
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

# Same geometry trick as enemy.gd's own _circle_points() - Polygon2D has no
# built-in "draw a circle" shape, so this fakes one with a many-sided
# polygon (32 segments - a bit rounder than the 24-segment enemy-side
# version, since these shapes sit larger on screen and a coarser circle
# would be more visible at that size). Still used by play_chain_refund_
# aura() above - the stance-tint glow's own Polygon2D use of this was
# replaced by _build_stance_tint_texture() (2026-08-28, soft-edge pass),
# but this function itself stays for that other, unrelated caller.
func _circle_points(radius: float, segments: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in segments:
		var angle := TAU * i / segments
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
