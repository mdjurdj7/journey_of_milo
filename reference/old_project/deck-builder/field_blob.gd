extends Area2D
# A field encounter - one of the run's battles, reached by walking into
# it rather than clicking a button. Area2D is a "detection zone" rather
# than a solid body like the walls (StaticBody2D) - the player can walk
# straight through it without being physically stopped; it just fires a
# signal when something enters. That's exactly the behavior an encounter
# needs (walking INTO it is what triggers the fight) and exactly what a
# wall must NOT do (a wall should block, not just notify).
#
# Instanced dynamically by field_room.gd - see its _spawn_blob() - from
# RoomState.room_layout, which decides how many blobs exist, where, their
# ids, AND which enemy each one represents (see room_state.gd's
# _generate_combat_layout()) once per room, not by hand in the room's
# scene file. Deciding the enemy at room-generation time (rather than
# when the fight actually starts, like it used to work) is what makes
# the field silhouette honest - see enemy_data below.

@export var blob_id: String = ""
# Which entry of RoomState.blob_defeated this specific blob is tracked
# under. Every blob in a room shares this same script; this is what
# makes each instance independent of the others - field_room.gd assigns
# a unique id to each one right after spawning it.

var enemy_data: EnemyData
# Which enemy this blob represents - set by field_room.gd right after
# instantiating, before add_child(). Drives which silhouette shows (see
# _setup_visual()) and, once touched, which enemy battle.gd actually
# fights (see RoomState.pending_enemy_data) - the field preview and the
# fight are guaranteed to be the same creature, never a bait-and-switch.
# Ignored (left null) when encounter_enemies below is set instead.

var encounter_enemies: Array[EnemyData] = []
# When this is non-empty (set by field_room.gd, from an EncounterData -
# see encounter_data.gd and DESIGN.md's Bestiary: Authored encounters/
# ELITE Rooms), this blob represents a deliberately composed encounter
# rather than a single random EnemyData - even a 1-entry array (a solo
# elite, e.g. the Wardling) goes through this path, not enemy_data above.
# This is the REAL roster, and ONLY the real roster - see _on_body_
# entered()'s own RoomState.pending_encounter_enemies handoff below,
# which reads this directly. Never touched by the field_preview_enemies
# mechanism (see field_display_enemies below) - that's what keeps "the
# field icon can simplify, but the fight never does" true structurally,
# not just by convention.

var field_display_enemies: Array[EnemyData] = []
# What _setup_multi_visual() actually RENDERS - set by field_room.gd
# from EncounterData.field_preview() (see its own doc), separate from
# encounter_enemies above on purpose. For every encounter before Mushroom
# Patch, field_preview() already resolves to the same array encounter_
# enemies holds, so this changes nothing for Twin Glasswings/Wardling
# Solo. Falls back to encounter_enemies itself if somehow left unset
# (defensive - field_room.gd is the only real caller today, but every
# member of an encounter blob having SOME silhouette beats a blank icon).
# Every member gets its own silhouette (see _setup_multi_visual(), shown
# side by side if there's more than one) - the same "field preview and
# fight are the same" honesty enemy_data above already guarantees for an
# ordinary blob: the player should be able to see exactly what they're
# walking into, never discover it only once battle starts. Mushroom
# Patch is the deliberate, first exception to that for the ICON
# specifically (see field_preview_enemies' own doc) - the FIGHT itself
# never diverges from what encounter_enemies says.

@export var all_enemies_field_drop_px: float = 50.0
# The GLOBAL version of EnemyData.field_foot_offset_px - shifts EVERY
# enemy's field silhouette vertically by the same amount, all at once,
# rather than one enemy at a time. Already in real field pixels (post-
# scale), unlike field_foot_offset_px (which is in each shape's own raw
# authored units and scales WITH that creature) - a flat +50 here moves
# every enemy down 50px on screen regardless of size. This is a script
# default, not per-enemy data, so there's exactly one number to change
# to move every creature at once: edit the default value above directly
# (simplest - no scene/resource to open), or override it on field_blob.
# tscn's root node in the Inspector if you'd rather tune it there.
# Positive moves everyone DOWN, negative moves everyone UP.

const FIELD_VISUAL_SCALE := 2.25
# How big the shared enemy silhouette renders here vs. in battle - see
# enemy.gd's exported silhouette_scale for the other end of "same asset,
# different scale per context, not two separate assets." Originally
# tuned (see DESIGN.md's field movement redesign: composition & scale
# pass) so a creature with EnemyData.field_visual_scale left at its 1.0
# default reads at roughly the player's own field height - each
# authored enemy's own multiplier (see enemy_data.gd) adjusts up or down
# from there for its specific silhouette direction (the Wardling taller
# and looming, the Tideworn/Thicket Stalker deliberately low and wide,
# etc).
#
# RE-DERIVED, not re-tuned (2026-08-30, field entity scale re-tune) -
# RoomState.player_visual_scale dropped 0.2 -> 0.075, a factor of
# 0.375; every entity hand-tuned against the OLD player height (this
# one included) was uniformly oversized by that exact factor. 3.0 *
# 0.375 = 1.125 preserves the existing tuned relationship to the player
# and to every per-enemy field_visual_scale multiplier rather than
# re-deriving it from scratch.
#
# RE-DERIVED A SECOND TIME (2026-08-30, second scale pass) -
# player_visual_scale went back up, 0.075 -> 0.15 (a factor of 2.0,
# correcting the first pass's own over-correction - see its own doc).
# 1.125 * 2.0 = 2.25, same "apply the same factor project-wide, don't
# re-derive from scratch" approach as the first re-derivation, keeping
# this value's relationship to the player and to every per-enemy field_
# visual_scale multiplier intact through both passes.
#
# STAYS const, not @export (2026-08-30, same-day revert) - briefly
# promoted to @export in this same pass, which broke the build:
# field_width()/encounter_field_width() below are static funcs, callable
# at room-layout time (load_room(), inside room_state.gd) before any
# FieldBlob instance exists to read an @export from - that's the whole
# reason they're static in the first place (see their own header
# comment). A static func can't read an instance @export, so making
# this one broke them. This value is not meant to be Inspector-tunable
# for that reason, not by oversight.
const ENCOUNTER_VISUAL_SCALE := 1.702
# Shrunk further than FIELD_VISUAL_SCALE alone for a multi-enemy blob -
# same reasoning as enemy.gd's two/three_enemy_scale_factor: a group only
# reads as ONE cohesive encounter if it doesn't just look like several
# full-size creatures overlapping. Keeps the same ratio to FIELD_VISUAL_
# SCALE (~0.756) the previous 0.68/0.9 pair had, just scaled up together
# with the new baseline.
#
# RE-DERIVED alongside FIELD_VISUAL_SCALE above (2026-08-30, field
# entity scale re-tune) - same 0.375 factor from the player_visual_scale
# change, 2.27 * 0.375 = 0.851, preserving the same ~0.756 ratio to
# FIELD_VISUAL_SCALE this value has always held.
#
# RE-DERIVED A SECOND TIME alongside FIELD_VISUAL_SCALE above (2026-08-
# 30, second scale pass) - same 2.0 factor from player_visual_scale's
# 0.075 -> 0.15 correction, 0.851 * 2.0 = 1.702, holding the same ~0.756
# ratio to FIELD_VISUAL_SCALE through both re-derivations.
#
# STAYS const, not @export - same reason as FIELD_VISUAL_SCALE's own
# doc above: encounter_field_width() below is also static and callable
# before any FieldBlob instance exists, and can't read an instance
# @export.
const ENCOUNTER_VISUAL_GAP := 46.0
# Horizontal spacing between adjacent creatures in an encounter blob.

const FALLBACK_VISUAL_SIZE := Vector2(80.0, 80.0)
# fallback_visual's own baked polygon span (see field_blob.tscn) - VisualBounds
# can't measure a bare Polygon2D's OWN polygon (it only reads a root's
# CHILDREN - see visual_bounds.gd), so _resize_triggers() falls back to
# this known constant for the one case that isn't a built visual_scene
# instance or wrapper.

# --- Field width measurement (placement-time, no live blob needed) ---
#
# UNUSED as of the blob-overlap fix (2026-08-27, see room_state.gd's own
# _place_content_positions() doc) - that function replaced per-blob-width
# placement math with one flat min_separation_px for every content type,
# so nothing calls field_width()/encounter_field_width() below today.
# Kept, not deleted: room_state.gd's own doc explicitly flags real per-
# type separation sizing as a real future direction if a flat floor ever
# proves too loose or too tight for a specific content type, and these
# already solve the hard part of that (measuring a blob's real rendered
# field width BEFORE any FieldBlob exists to measure it directly - room
# layout is generated up front, at load_room() time, well before field_
# room.gd ever spawns a single blob). Reuses the exact same scale/
# measurement math _build_member_visual()/_setup_multi_visual() already
# use at runtime (VisualBounds off the same visual_scene, scaled by
# FIELD_VISUAL_SCALE/ENCOUNTER_VISUAL_SCALE and each enemy's own field_
# visual_scale), so it can't quietly drift out of sync with what actually
# renders even after sitting unused for a while.

# One enemy's local (unscaled) left/right silhouette edges, as x, in the
# authored shape's own units - the same Rect2 VisualBounds.compute()
# already returns for _build_member_visual()'s foot-anchor math, just
# read here for width instead. A bare Node2D never gets added to the
# tree (VisualBounds only reads child transforms/shapes, never global
# position or viewport state - see visual_bounds.gd's own header), so
# this is safe to call at layout-generation time, long before field_
# room.tscn exists.
static func _member_bounds_x(data: EnemyData) -> Vector2:
	if data.visual_scene == null:
		return Vector2(-FALLBACK_VISUAL_SIZE.x / 2.0, FALLBACK_VISUAL_SIZE.x / 2.0)
	var visual: Node2D = data.visual_scene.instantiate() as Node2D
	var bounds := VisualBounds.compute(visual)
	visual.free()
	return Vector2(bounds.position.x, bounds.end.x)

# A single-enemy blob's real rendered field width, in field pixels -
# same FIELD_VISUAL_SCALE * data.field_visual_scale chain _build_member_
# visual() applies for an ordinary (non-encounter) blob.
static func field_width(data: EnemyData) -> float:
	var scale: float = FIELD_VISUAL_SCALE * data.field_visual_scale
	var x := _member_bounds_x(data)
	return (x.y - x.x) * scale

# A multi-enemy encounter blob's full rendered span, in field pixels -
# mirrors _setup_multi_visual()'s exact positioning (start_x + i *
# ENCOUNTER_VISUAL_GAP per member, each at ENCOUNTER_VISUAL_SCALE) so
# this measures the real group footprint, not just one member's width.
# A 1-member encounter (a solo elite) renders at FIELD_VISUAL_SCALE, not
# ENCOUNTER_VISUAL_SCALE - see _setup_multi_visual()'s own note - so that
# case is delegated straight to field_width() above rather than
# duplicating the "which scale" branch here.
static func encounter_field_width(enemies: Array[EnemyData]) -> float:
	if enemies.is_empty():
		return 0.0
	if enemies.size() == 1:
		return field_width(enemies[0])
	var start_x := -(enemies.size() - 1) * ENCOUNTER_VISUAL_GAP / 2.0
	var left := INF
	var right := -INF
	for i in enemies.size():
		var scale: float = ENCOUNTER_VISUAL_SCALE * enemies[i].field_visual_scale
		var x := _member_bounds_x(enemies[i])
		var center: float = start_x + i * ENCOUNTER_VISUAL_GAP
		left = min(left, center + x.x * scale)
		right = max(right, center + x.y * scale)
	return right - left

# NoticeZone is a second, larger Area2D (see field_blob.tscn) purely for
# "the encounter notices you" anticipation - no aggro, no chasing, just a
# looping pulse while the player is inside this bigger radius. Separate
# from the main body (the fight-trigger hitbox - see the trigger-sizing
# group below) so the two detection ranges can differ without one
# interfering with the other's collision shape.
const NOTICE_SCALE_MULTIPLIER := 1.15
const NOTICE_PULSE_DURATION := 0.35
const NOTICE_COLOR_SHIFT := Color(1.25, 1.15, 1.15, 1) # A brighter, hotter tint, via modulate.

# --- Trigger sizing (DECIDED - see DESIGN.md's field movement redesign)
# ---
#
# field_blob.tscn used to bake the hitbox (80x80) and NoticeZone radius
# (140) as FIXED sub-resource shapes, sized against the old, much
# smaller field scale - once per-enemy scale (see enemy_data.gd's
# field_visual_scale) made creatures range from the Tideworn's small,
# low silhouette to the Wardling looming well over the player, a fixed
# trigger size stopped meaning anything: a small enemy's real footprint
# sat well inside its own oversized-relative hitbox (trivially easy to
# "walk into" from any angle), while a large enemy's hitbox was tiny
# relative to its own visual (requiring walking almost through it).
# Both shapes are now resized per-blob by _resize_triggers(), from
# visual_root's own real rendered width/height (measured via VisualBounds,
# the same utility the foot-anchor math already uses - see _build_member_
# visual()) - called once visual_root is finalized, and again any time
# it's rebuilt (see _on_enemy_data_changed()), so retuning field_visual_
# scale live keeps the trigger proportional too, not just the art.
@export_group("Trigger sizing")
@export var hitbox_size_factor: float = 0.7
# Multiplies the creature's own rendered footprint to size the actual
# fight-trigger hitbox - under 1.0 on purpose, so the player doesn't
# need to overlap art that extends past the creature's "body" (a
# wingtip, a trailing limb) to trigger, while still requiring a real
# approach proportional to its size.
@export var notice_radius_factor: float = 1.1
# Multiplies the larger of the creature's rendered width/height for
# NoticeZone's radius - bigger than the hitbox factor above on purpose
# (the "I've noticed you" pulse should read before actual contact), and
# still scales WITH the creature instead of every enemy sharing one
# fixed approach radius regardless of size.
@export var min_hitbox_size: Vector2 = Vector2(50.0, 50.0)
@export var min_notice_radius: float = 70.0
# Floors so a very small/low creature (the Tideworn) still gets a
# sensible, genuinely clickable hitbox and a real notice radius, rather
# than shrinking below the player's own ~50px collision footprint.

@export_group("Idle wander")
@export var wander_enabled: bool = false
# Set by field_room.gd's _spawn_blob() from RoomState.room_layout's own
# "wander" key (see room_state.gd's _generate_combat_layout()) - today,
# only ever true for the first combat room's authored spawn. Left false
# for every other blob so ordinary combat rooms stay exactly as static as
# they've always been.
@export var wander_amplitude_px: float = 40.0
@export var wander_speed: float = 0.6
# Radians/sec - a full left-right-left cycle takes TAU/wander_speed
# seconds (~10.5s at the 0.6 default). Small amplitude + slow speed is
# the point: this should read as a creature shifting where it sits, not
# patrolling.

var _wander_time: float = 0.0
var _wander_origin_x: float = 0.0

@onready var fallback_visual: Polygon2D = $Polygon2D
@onready var notice_zone: Area2D = $NoticeZone
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var notice_collision_shape: CollisionShape2D = $NoticeZone/CollisionShape2D

var visual_root: Node2D
# Whichever node is actually showing right now - either enemy_data's own
# silhouette (see _setup_visual()) or fallback_visual, the plain colored
# square every enemy used to show before silhouettes existed. The notice
# pulse below animates whatever this points at rather than caring which
# case it is - a Polygon2D and an EnemyVisual instance are both plain
# Node2Ds and both support .scale/.modulate, so nothing here needs to
# special-case which one it got.
var _visual_base_scale: Vector2 = Vector2.ONE
var _notice_tween: Tween

var _shadow: Sprite2D = null
# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
# gd's own doc. Tracked separately from visual_root because visual_root
# is destroyed and rebuilt on an EnemyData change (see _on_enemy_data_
# changed()) - the shadow is REBUILT alongside it (not kept alive across
# the rebuild) via _update_shadow() below, called at the end of _setup_
# visual() for every path that function takes, so it's never stale
# against whatever visual_root currently is.

func _ready() -> void:
	# Gone for good once beaten (blob_defeated already true from earlier
	# in this room's lifetime), or gone because THIS is the blob that was
	# just fought and won (see reward_screen.gd/field_room.gd for how
	# that gets signaled back here). Either way, mark it permanently
	# defeated and don't exist - "the defeated blob is gone."
	#
	# blob_defeated now means RESOLVED, not KILLED (2026-08-23, see
	# battle.gd's _on_battle_escaped()): last_encountered_blob_id gets set
	# the instant the player TOUCHES a blob, before the fight's outcome is
	# known, and this check has never distinguished win from escape - a
	# fight the player escaped from marks its blob defeated and vanishes
	# here exactly like a win does, deliberately (see DESIGN.md's escape
	# note: the encounter is consumed either way, the player just leaves
	# with no reward). The field name itself is unchanged this pass.
	if RoomState.blob_defeated.get(blob_id, false) or blob_id == RoomState.last_encountered_blob_id:
		RoomState.blob_defeated[blob_id] = true
		queue_free()
		return
	body_entered.connect(_on_body_entered)
	notice_zone.body_entered.connect(_on_notice_entered)
	notice_zone.body_exited.connect(_on_notice_exited)
	_setup_visual()
	# EnemyData.field_visual_scale's own setter (see enemy_data.gd) emits
	# Resource's built-in `changed` signal whenever it's edited - listening
	# here is what makes tweaking it on a LIVE blob (via a running game's
	# Remote inspector - see player_visual.gd's foot_offset_px for the
	# same pattern) actually rescale the creature immediately, instead of
	# only taking effect the next time this room loads fresh.
	if enemy_data != null:
		enemy_data.changed.connect(_on_enemy_data_changed)
	for member_data in encounter_enemies:
		member_data.changed.connect(_on_enemy_data_changed)
	_wander_origin_x = position.x
	set_process(wander_enabled)

# Idle wander (2026-09-06, "authored first fight" pass) - a slow left-right
# sine drift around the spawn point, only while wander_enabled is true.
# set_process(false) in _ready() keeps every other blob (wander_enabled
# left at its default false) skipping this entirely, same as before this
# existed. _on_body_entered() below disables processing the instant the
# fight actually starts, so the drift can never continue once combat has
# begun.
func _process(delta: float) -> void:
	_wander_time += delta
	position.x = _wander_origin_x + sin(_wander_time * wander_speed) * wander_amplitude_px

# Full rebuild rather than an in-place rescale - _build_member_visual()'s
# scale affects BOTH the figure's size and its feet-anchoring Y offset
# (see its own comment), and _setup_multi_visual() also respaces members
# horizontally by scale - simpler and less error-prone to tear down and
# redo the same setup that already gets all of that right at spawn time,
# rather than a second, parallel "just resize this in place" code path.
func _on_enemy_data_changed() -> void:
	if _notice_tween:
		_notice_tween.kill()
		_notice_tween = null
	if visual_root != null and visual_root != fallback_visual:
		visual_root.queue_free()
	visual_root = null
	_setup_visual()

# Enemy has an authored silhouette -> show it, scaled down for the field,
# hiding the plain fallback square. No silhouette yet -> the fallback
# square stays exactly as it always looked - "unarted enemies still
# work" (see enemy_data.gd's visual_scene comment). A multi-enemy blob
# (encounter_enemies set - see its own comment above) skips this
# entirely and builds a side-by-side group instead.
func _setup_visual() -> void:
	if not encounter_enemies.is_empty():
		_setup_multi_visual()
		_resize_triggers()
		_update_shadow()
		return
	if enemy_data != null and enemy_data.visual_scene != null:
		var visual := _build_member_visual(enemy_data, FIELD_VISUAL_SCALE)
		add_child(visual)
		fallback_visual.visible = false
		visual_root = visual
	else:
		visual_root = fallback_visual
	_visual_base_scale = visual_root.scale
	_resize_triggers()
	_update_shadow()

# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.gd's
# own doc. Called at the end of EVERY _setup_visual() path (single visual,
# fallback square, and multi-enemy wrapper alike) - visual_root is
# guaranteed final by the time this runs, whichever of those three it
# ended up being. Frees any shadow from a PREVIOUS visual_root first
# (reachable via _on_enemy_data_changed()'s rebuild) rather than trying to
# reposition/rescale one in place - EntityShadow.attach() is creation-only
# by design (see its own doc: this project's one deliberate exception to
# "duplicate, don't share" is scoped to exactly that), so a rebuild just
# calls it again.
func _update_shadow() -> void:
	if _shadow != null:
		_shadow.queue_free()
		_shadow = null
	_shadow = EntityShadow.attach(self, visual_root)

# No shadow_y_offset override here (2026-08-30, shadow-tuning pass) -
# deliberately left on RoomState.entity_shadow_y_offset's own -18
# default, unlike chest/curio/heap/marker/npc/player. Those five were
# each individually measured against their own known-exact geometry or
# alpha content; auditing whether -18 is right for every enemy's own
# silhouette (each with its own field_foot_offset_px already tuned per
# enemy_data.gd - see _build_member_visual()'s own doc) is a separate,
# larger undertaking than this pass - flag if a SPECIFIC enemy's shadow
# reads wrong live, and retune that enemy's field_foot_offset_px first
# (the mechanism already built for exactly this), not this shared
# function.

# One creature's field silhouette, scaled and vertically offset the same
# way regardless of whether it's the blob's only occupant or one member
# of an encounter group - shared by _setup_visual() and
# _setup_multi_visual() so there's one definition of "how a creature sits
# on the field," not two copies that could drift apart. No visual_scene
# -> a plain fallback square, matching fallback_visual's own look
# (color/shape), so an unarted enemy inside an encounter still shows
# SOMETHING instead of a gap in the group.
#
# `base_scale` is whichever shared baseline the caller passed in (FIELD_
# VISUAL_SCALE or ENCOUNTER_VISUAL_SCALE) - data.field_visual_scale (see
# enemy_data.gd) multiplies on top of it, applied to BOTH branches below,
# so a creature's intended relative size holds even before real art
# exists for it.
func _build_member_visual(data: EnemyData, base_scale: float) -> Node2D:
	var scale: float = base_scale * data.field_visual_scale
	if data.visual_scene == null:
		var fallback := Polygon2D.new()
		fallback.polygon = fallback_visual.polygon
		fallback.color = fallback_visual.color
		fallback.scale = Vector2(scale, scale)
		fallback.position.y = data.field_foot_offset_px * scale + all_enemies_field_drop_px
		return fallback
	var visual: Node2D = data.visual_scene.instantiate() as Node2D
	visual.scale = Vector2(scale, scale)
	# Every enemy_visual_*.tscn draws its shapes with the origin at the
	# creature's FEET (see DESIGN.md's enemy silhouettes note), so left
	# alone (position.y = 0) the feet already land exactly on this blob's
	# spawn point - the same feet-at-a-point behavior enemy.gd's battle
	# layout relies on directly, with no offset of its own. Field used to
	# shift this to a CENTER-anchor instead (half the creature above the
	# spawn point, half below) - a leftover from the room's old top-down
	# layout, where the spawn point was just "the middle of the creature
	# icon," not literally a floor line. Now that the field is a strict
	# side-scroller with a real floor line (see DESIGN.md's field
	# movement redesign), field and battle both want the SAME feet-at-a-
	# point anchor, so this computes the shape's own bottom edge via
	# VisualBounds (see visual_bounds.gd) and shifts by however far short
	# of true y=0 it actually falls - a no-op for a perfectly-authored
	# shape, a small correction for one that's slightly off, same
	# robustness principle DESIGN.md's silhouette-authoring note already
	# describes for the battle side. data.field_foot_offset_px (see its
	# own comment) adds a manual nudge on top - both terms are in the
	# shape's own raw authored units, then scaled together at the end, so
	# the offset stays proportional if field_visual_scale is retuned too.
	var bounds := VisualBounds.compute(visual)
	visual.position.y = (data.field_foot_offset_px - bounds.end.y) * scale + all_enemies_field_drop_px
	return visual

# A wrapper Node2D holding one silhouette per encounter member, spaced
# evenly around this blob's own center - the SAME node the notice pulse
# below animates (.scale/.modulate cascade to every child regardless of
# how many there are), so nothing about the pulse itself needs to know
# whether it's pulsing one creature or several. A 1-member encounter (a
# solo elite - see DESIGN.md's ELITE Rooms section) renders at the same
# FIELD_VISUAL_SCALE an ordinary single-enemy blob would, not shrunk -
# ENCOUNTER_VISUAL_SCALE is specifically for making a GROUP read as one
# cohesive unit, which doesn't apply with only one member; the centering
# math below already places a single member dead center regardless.
func _setup_multi_visual() -> void:
	fallback_visual.visible = false
	var wrapper := Node2D.new()
	add_child(wrapper)
	# field_display_enemies, not encounter_enemies - see field_display_
	# enemies' own doc for why the two can diverge (Mushroom Patch) and
	# why encounter_enemies itself must never be read here.
	var display: Array[EnemyData] = field_display_enemies if not field_display_enemies.is_empty() else encounter_enemies
	var count := display.size()
	var scale: float = FIELD_VISUAL_SCALE if count == 1 else ENCOUNTER_VISUAL_SCALE
	var start_x := -(count - 1) * ENCOUNTER_VISUAL_GAP / 2.0
	for i in count:
		var member := _build_member_visual(display[i], scale)
		member.position.x = start_x + i * ENCOUNTER_VISUAL_GAP
		wrapper.add_child(member)
	visual_root = wrapper
	_visual_base_scale = visual_root.scale

# Resizes the fight-trigger hitbox and NoticeZone radius (see the
# "Trigger sizing" export group's own comment) from visual_root's real
# rendered footprint - a bare fallback square (no children to measure -
# see FALLBACK_VISUAL_SIZE's own comment) uses that known constant
# times its own scale; anything else (a real silhouette, or the multi-
# member wrapper) gets measured directly via VisualBounds, the same
# utility _build_member_visual() already uses for foot-anchoring.
#
# Both collision_shape.shape and notice_collision_shape.shape start out
# SHARED sub-resources (every FieldBlob instance references the SAME
# RectangleShape2D/CircleShape2D from field_blob.tscn) - duplicated
# before mutating, same "never resize a shared shape resource in place"
# precaution field_wall.gd's own configure() already takes.
func _resize_triggers() -> void:
	var reference_size: Vector2
	if visual_root == fallback_visual:
		reference_size = FALLBACK_VISUAL_SIZE * visual_root.scale
	else:
		reference_size = VisualBounds.compute(visual_root).size * visual_root.scale

	var hitbox_shape: RectangleShape2D = (collision_shape.shape as RectangleShape2D).duplicate()
	hitbox_shape.size = Vector2(
		max(reference_size.x * hitbox_size_factor, min_hitbox_size.x),
		max(reference_size.y * hitbox_size_factor, min_hitbox_size.y),
	)
	collision_shape.shape = hitbox_shape

	var notice_shape: CircleShape2D = (notice_collision_shape.shape as CircleShape2D).duplicate()
	var reference_radius: float = max(reference_size.x, reference_size.y) / 2.0
	notice_shape.radius = max(reference_radius * notice_radius_factor, min_notice_radius)
	notice_collision_shape.shape = notice_shape

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		# Stop drifting and hold the current position the instant the fight
		# actually starts - SceneTransition.go_to() below tears this room
		# down shortly after, but freezing here (rather than trusting that
		# teardown alone) is what guarantees no further drift is possible
		# once combat has begun, per this feature's own brief.
		set_process(false)
		position.x = _wander_origin_x
		# Remember which blob this was and where the player was standing,
		# so the field room can restore both when Victory sends us back
		# here (see RoomState and reward_screen.gd). pending_enemy_data/
		# pending_encounter_enemies are what make the fight battle.gd
		# starts match the silhouette(s) the player just saw - see room_
		# state.gd's comments on those two fields. Exactly one of the pair
		# gets set here (the other explicitly cleared), since a previous
		# blob touched earlier in this same room visit may have left the
		# other one populated - reset_room() only runs between ROOMS.
		RoomState.in_field_encounter = true
		RoomState.last_encountered_blob_id = blob_id
		if not encounter_enemies.is_empty():
			RoomState.pending_encounter_enemies = encounter_enemies
			RoomState.pending_enemy_data = null
		else:
			RoomState.pending_enemy_data = enemy_data
			RoomState.pending_encounter_enemies = []
		RoomState.player_position = body.global_position
		RoomState.has_saved_position = true
		SceneTransition.go_to("res://battle.tscn")

# --- Notice pulse (visual only - see field_blob.tscn's NoticeZone) ---

func _on_notice_entered(body: Node2D) -> void:
	if body is Player:
		_start_notice_pulse()

func _on_notice_exited(body: Node2D) -> void:
	if body is Player:
		_stop_notice_pulse()

func _start_notice_pulse() -> void:
	if _notice_tween:
		_notice_tween.kill()
	visual_root.modulate = NOTICE_COLOR_SHIFT
	_notice_tween = create_tween()
	_notice_tween.set_loops() # 0 = infinite - runs until _stop_notice_pulse() kills it.
	_notice_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_notice_tween.tween_property(visual_root, "scale", _visual_base_scale * NOTICE_SCALE_MULTIPLIER, NOTICE_PULSE_DURATION)
	_notice_tween.tween_property(visual_root, "scale", _visual_base_scale, NOTICE_PULSE_DURATION)

func _stop_notice_pulse() -> void:
	if _notice_tween:
		_notice_tween.kill()
		_notice_tween = null
	visual_root.scale = _visual_base_scale
	visual_root.modulate = Color(1, 1, 1, 1)
