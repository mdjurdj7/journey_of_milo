extends CharacterBody3D
class_name Wanderer

# He has come to rest at the hold line (see the Hold Line export group) -
# once per arrival.
signal hold_line_reached
# A planned walk (set_move_path()) has stood still against something for
# stuck_time with waypoints still ahead - RegionField plans again.
signal path_stuck
# DrawSword's ground strike (draw_sword_strike_time) in a battle entry:
# the sword tip where it is on that frame, and the drawn sand under it.
# BattleFeedback raises the sand puff there; the sound is his own
# (AttackAudio.play_ground_strike()).
signal draw_strike(tip: Vector3, ground_point: Vector3)
# A battle entry's draw is past its ground strike: struck (after draw_
# strike), or cut off before it. The fight's opening hold ends on it
# (BattleController.lock_entry_input()).
signal draw_strike_passed

# The body: the cloaked Wanderer, rigged by Meshy on its Mixamo template
# (bones smartrig_*, an A-pose rest), exported as glTF in metres - 1.7 m
# tall at rest, its skeleton unscaled and unturned. Its clips are the
# battle stance: battle_idle_breathe (breathing in it) merges as
# BattleIdle, battle_idle (held) in its place if it's missing, slash as
# Slash and draw_sword as DrawSword (_merge_clips()); every other clip is
# a separate FBX carried over (_transfer_clip()). Idle, Walk and Run are
# Meshy's own clips for this rig (mixamorig_ names, its bone lengths, a
# different rest), stripped to skeleton and animation (no skin); Brace is
# still cut on the old Mixamo rig, and so are the Slash and DrawSword the
# glb's own stand in for when they're missing.
#
# Which model, and its albedo, yaw and height, are the run's character's
# (CharacterData's field model - _character()); the clips below are the
# Wanderer's rig's, merged only onto a model that has a Skeleton3D. A
# model without one (the Samurai's, for now) stands as a static body: it
# slides as he walks, with no clips, sword, footprints or footsteps.
# The glb's clips that can be BattleIdle, first found wins (_merge_clips()).
const BATTLE_IDLE_CLIPS: Array[StringName] = [&"battle_idle_breathe", &"battle_idle"]
# The glb's own swing, merged as Slash in place of the Mixamo one.
const SLASH_CLIP := &"slash"
# The glb's own draw, merged as DrawSword in place of the Mixamo one.
const DRAW_SWORD_CLIP := &"draw_sword"
# The method DrawSword's grab key calls (_merge_clips()).
const GRAB_KEY_METHOD := &"_on_draw_sword_grab_key"
# The method DrawSword's ground-strike key calls (_merge_clips()).
const STRIKE_KEY_METHOD := &"_on_draw_sword_strike_key"
const IDLE_SCENE_PATH := "res://assets/models/wanderer/wanderer_v3_idle.fbx"
const WALK_SCENE_PATH := "res://assets/models/wanderer/wanderer_v3_walk.fbx"
const RUN_SCENE_PATH := "res://assets/models/wanderer/wanderer_v3_run.fbx"
const DRAW_SWORD_SCENE_PATH := "res://assets/models/wanderer/wanderer_battle_start_draw_sword.fbx"
const SLASH_SCENE_PATH := "res://assets/models/wanderer/wanderer_slash.fbx"
const BRACE_SCENE_PATH := "res://assets/models/wanderer/wanderer_brace.fbx"
const FLAT_SHADER_PATH := "res://field/wanderer_flat.gdshader"
const PAINTED_SHADER_PATH := "res://field/wanderer_painted.gdshader"
const FOG_SHADER_PATH := "res://field/enemy_fog.gdshader"
# The sword he carries is the run's weapon's field model (WeaponData.
# field_model_path - _build_sword()); this one where it names none.
const SWORD_SCENE_PATH := "res://assets/models/wanderer/sword.glb"
# sword.glb's own albedo (sword_0.jpg) denoised and lifted to a light warm
# steel by tools/paint_texture.py --image-space. TEXTURED draws the sword
# with it through wanderer_painted.gdshader instead of the glb's imported
# material, whose metallic map and normal map made it shine. The weapon's
# field_albedo comes first; this is sword.glb's when it has none.
const SWORD_ALBEDO_TEXTURE_PATH := "res://assets/models/wanderer/sword_painted.png"
# The sword exports a weapon's fit can set (WeaponData.field_fit()).
const SWORD_FIT_PROPERTIES: Array[StringName] = [&"sword_length", &"grip_fraction", &"grip_axis_flip", &"hand_mount_position", &"hand_mount_rotation_degrees", &"back_mount_position", &"back_mount_rotation_degrees"]

@export var move_speed: float = 4.5
@export var acceleration: float = 14.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 12.0
@export var dash_distance: float = 6.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0

@export_group("Point To Move")
# A click on the field (see RegionField._unhandled_input()) is planned
# round what is in the way (RegionField.plan_path(), NavGrid) and handed
# here as waypoints (set_move_path()); he walks them in turn at move_speed,
# facing the way he walks, moving on from each within waypoint_radius, and
# the walk clears within arrive_radius of the last, the moment any WASD
# input arrives, or after stuck_time of standing still against something
# with waypoints still ahead - then path_stuck asks RegionField to plan
# again. A bare set_move_target() is still a straight walk. An enemy
# target (see set_move_target_enemy()) is followed live once its path is
# walked, until contact starts the fight, which clears it (see
# enter_battle_stance()).
@export var arrive_radius: float = 0.25
@export var waypoint_radius: float = 0.35
@export var stuck_time: float = 0.5

@export_group("Step-Up")
# How tall a ledge/curb the Wanderer can walk straight up onto, and how far
# below his feet a drop-off is still treated as a step-down snap rather than
# a fall. Field only - _apply_step_up_and_down() no-ops while a battle
# stance is bound (see _battle_controller).
@export var step_height: float = 0.35
# The forward probe (see _try_step_up()) has to clear the capsule's own
# leading edge, not just this frame's move distance from its center - a
# cast that only reaches move_distance ahead still lands the down cast on
# the ground BEFORE the obstacle (inside the capsule's own radius), never
# on top of it. This is the extra clearance added past capsule radius +
# move distance, in case the obstacle's near face isn't perfectly vertical.
@export var step_probe_margin: float = 0.1
# Draws the forward (green) and downward (red) probe casts each physics
# frame while true. Re-read live every frame rather than cached, so this
# takes effect immediately from the Remote tab like every other tunable
# here - no setter needed since there's no baked state to invalidate.
@export var debug_draw_step_casts: bool = false

@export_group("Ground Hold")
# The feet are never left below the surface as DRAWN (Ground.get_visible_
# height_at(): the relief mesh's own triangles plus the channel delta
# the shader is displacing them by). Checked last thing every physics
# frame (see _hold_above_visible_ground()): further below it than this,
# and he is put onto it with any fall cancelled. The one case this is
# built for is a draining channel - the exit gate's bar surfaces on the
# GPU over ExitGate.drain_seconds while mesh and collision only catch
# up at the end, so on the bar he would otherwise walk under the sand
# and, when the collision finally jumps up through him, fall out of the
# world.
# While it is what holds him (no collision under his feet) he counts as
# grounded everywhere is_on_floor() is read. The tolerance only has to
# clear what a resting capsule ever shows: the drawn triangles and the
# physics heightmap agree to under a millimetre on both floors (same
# grid, same diagonal - measured), and a body at rest on a slope sits
# ON the surface, never in it, so 3 cm is three times the physics
# recovery margin and still under a visible sink. On ordinary ground it
# never fires; if it ever does outside a drain it warns once per floor
# with the spot, so a bad patch of relief gets found rather than hidden.
@export var ground_penetration_tolerance_m: float = 0.03

@export_group("Hold Line")
# A LINE floor's gate (ExitGate.setup_hold_line()): while required fights
# remain he won't cross the gate line. Not a wall - nothing on the field
# stops him - he slows over the last hold_line_ease_distance metres (a
# constant deceleration, so at walking pace he comes to rest ON the line,
# and a dash is reined in the same way) and then stands there; only his
# motion INTO the line is held, so he still walks along it. At rest
# within hold_line_arrive_margin of it he emits hold_line_reached once
# (RegionField turns him to look back - see look_back_toward()), and is
# re-armed once he has walked hold_line_rearm_distance back off it. The
# look-back turn runs at hold_line_turn_speed (rotation_speed is his
# walking turn; this one is slower, a look rather than a step). All read
# live every frame.
@export var hold_line_ease_distance: float = 1.0
@export var hold_line_arrive_margin: float = 0.05
@export var hold_line_rearm_distance: float = 0.75
@export var hold_line_turn_speed: float = 4.0
@export_group("Wade Limit")
# A floor's wade limit (FloorData.wade_limit_m - RegionField hands it
# over, set_wade_limit()): he won't wade further than that past the
# nearest shoreline (Ground.get_landmass_distance()). Held as the hold
# line holds him: no wall, he eases to rest over the last wade_limit_ease_
# distance metres and slides along it, only his motion further out held -
# "out" the distance field's slope, read wade_limit_probe_m either side of
# him. Put past it (a fight's stance), he may stay there, never go further.
# No HP cost. All read live.
@export var wade_limit_ease_distance: float = 1.0
@export var wade_limit_probe_m: float = 0.25
@export_group("")
@export var use_animation_tree: bool = false
@export var walk_speed_threshold: float = 0.1
@export var animation_blend_time: float = 0.2
# Leaving a fight, BattleIdle blends into the field Idle over this
# (exit_battle_stance()) - longer than animation_blend_time, as the battle
# clips hold his right upper arm turned ~100 deg about its own axis from
# where the Mixamo field clips hold it, and a quick blend wrings it round.
# Read at each exit.
@export var battle_exit_blend: float = 0.4
@export var camera_path: NodePath = ^"../CameraPivot/Camera3D"
@export var ground_path: NodePath = ^"../Ground"
# Set from the character's field_model_yaw_degrees when the model is
# built (_ready()).
@export var model_yaw_offset: float = 180.0
# In a fight, how far his model turns toward the camera on top of facing
# the enemy - a 3/4 view instead of exactly side-on. The model turns, not
# the body: his facing, lunges and recoil tilt stay on the line between
# the fighters. Tweened in with the battle stance and out on exit; live
# while he is in one.
@export var battle_camera_turn_degrees: float = 30.0:
	set(value):
		battle_camera_turn_degrees = value
		if _battle_turned and _model != null:
			_model.rotation.y = _model_yaw()
# A touch warmer than the crab's own charcoal (see FieldEnemy.model_color)
# so the two read as different things even at a glance, not just "the
# same placeholder grey twice." Used only as the fallback flat material -
# see _build_flat_material() - when wanderer_flat.gdshader can't be built
# (the body's albedo failed to load), and in FLAT mode.
@export var wanderer_color: Color = Color(0.16, 0.15, 0.14, 1)

# The real model ships at whatever scale its source file happens to use
# (verified at 0.019m tall before this export existed) - this is the
# actual size the Wanderer renders at, in meters, measured by AABB height
# right after instancing. model_scale_override below can bypass this.
# Set from the character's field_model_height when the model is built
# (_ready()), so an edit here holds until the next floor loads.
@export var target_height: float = 1.8

# 0 (default) means "auto": derive the scale factor from target_height /
# the model's own raw AABB height. Nonzero overrides that entirely with a
# manual multiplier - useful if a future model ships close enough to
# correct that the auto-derived factor overcorrects.
@export var model_scale_override: float = 0.0

# _scale_and_ground_model() grounds off the model's bind-pose AABB, but
# every clip's own hips height sits somewhere different from the bind pose
# (Idle floated ~0.5m once it took over; BattleIdle/DrawSword each carry
# their own different hips height too) - _apply_continuous_foot_grounding()
# corrects for that continuously, on every pose the animation mixer
# applies (battle freeze included), using whichever clip is actually
# playing. This is the target body-local Y its lowest
# foot/toe bone is driven toward, not a one-time nudge: how far, in
# metres, that toe joint sits above the sand. His body origin is on the
# sand everywhere (field, battle stance, escape push), so this lifts the
# model alone. The joint sits inside the boot, about 4 cm above its sole
# in BattleIdle - the default puts BattleIdle's soles on the sand, not
# under it. Meshy's Idle and Walk keep the soles within a few mm of it;
# Run's heel strike still dips up to ~4.5 cm, and the old carried clips
# (DrawSword, Slash, Brace) pitch the foot further.
@export var model_ground_offset: float = 0.041:
	set(value):
		model_ground_offset = value
		# Grounding already reads it on every applied pose; this lands it
		# at once, eased over nothing, for an edit made while no pose is
		# being applied.
		if is_inside_tree():
			_apply_continuous_foot_grounding(1.0)
# How fast _apply_continuous_foot_grounding() eases the model toward its
# target Y (exponential, per second) - high enough that normal per-frame
# foot movement during Idle/Walk tracks essentially instantly, low enough
# that a clip transition's own hips-height jump (e.g. into BattleIdle)
# eases in over a few frames instead of popping.
@export var foot_grounding_smoothing_speed: float = 12.0

enum ShadingMode { TEXTURED, POSTERIZED, FLAT }

@export_group("Follow-Through")
# A repeated hit's own small swing (BattleController.card_repeat_swing -
# Second Swing): no clip, a short lunge at the target through the recoil
# tween turned round (play_hit_recoil()), and the whoosh again at this
# pitch. All read at each swing, so a Remote-tab edit applies from the
# next one.
@export var follow_through_distance: float = 0.18
@export var follow_through_tilt_degrees: float = 0.0
@export var follow_through_out_time: float = 0.08
@export var follow_through_return_time: float = 0.2
@export var follow_through_pitch: float = 1.08

@export_group("Slash")
# The glb's own slash (when it carries one - _merge_clips()) swings feet
# planted, so the step in comes from here: his model slides
# slash_lunge_distance toward the target over slash_lunge_out_time,
# arriving on slash_contact_time - the clip's contact frame (Blender frame
# 10 at 24 fps), where the card's hit lands too (get_clip_contact_time())
# - and back over slash_lunge_return_time. The model moves, not the body:
# his place in the fight stays where it is. On contact the hit's stop
# (BattleFeedback's Hit-Stop group) holds his clip where it is
# (hold_animation()), and his lunge with it, and each enemy it strikes
# (FieldEnemy.hold_for()) - the flash, number and sound land as it starts.
# The Mixamo fallback steps in its own clip; its hit lands at the
# card's impact_time. A next card waits for the swing to reach
# slash_cancel_time (seconds into the clip - the end of the follow-
# through's hang, Blender frame 18) before its play starts
# (BattleController, holds_next_play()) - a Slash then swings again from
# the top, its hit on its own contact frame; with none, the swing plays
# out and blends into the resting clip. All read at each swing.
@export var slash_contact_time: float = 10.0 / 24.0
@export var slash_cancel_time: float = 18.0 / 24.0
@export var slash_lunge_distance: float = 0.3
@export var slash_lunge_out_time: float = 0.25
@export var slash_lunge_return_time: float = 0.45

@export_group("Draw Sword")
# The glb's own draw_sword (when it carries one - _merge_clips()) is the
# battle entry (enter_battle_stance()): the sword stays on his back until
# draw_sword_grab_time (seconds into the clip - Blender frame 10 at 24
# fps, where his right hand is posed on the grip). There it goes into his
# hand as it stands - the back-carry angle - and over draw_sword_snap_time
# (frames 10-16) turns onto the hand mount (_set_handoff()). The turn is
# near half a circle, so its way round is set, not left to the shortest
# arc (which swings the blade across his back to his left, past the
# hood): the blade first turns, tip leading, to draw_sword_sweep_direction
# - up and back over his right shoulder - then on to the hand mount as
# his hand carries it. The direction is in his model's space: x toward
# his left, y up, z toward his front. The grab is a method key on the
# clip (_merge_clips()), so it lands on the clip's frame 10 however the
# frames fall; a fight that ends before it leaves the sword on his back
# (_on_draw_sword_grab_key()); one cut off before it by another clip
# grabs there and then (_on_draw_sword_cut()). The clip blends in from the field
# clip (Walk or Idle) over draw_sword_blend_in - longer than animation_
# blend_time, for the same upper-arm turn battle_exit_blend covers - and
# into the resting clip over animation_blend_time as it ends. The Mixamo
# fallback keeps the old entry: the sword slides to his hand over the
# step to battle spacing, and the clip cuts to BattleIdle. All read at
# each entry.
@export var draw_sword_blend_in: float = 0.35
@export var draw_sword_grab_time: float = 10.0 / 24.0
@export var draw_sword_snap_time: float = 6.0 / 24.0
@export var draw_sword_sweep_direction: Vector3 = Vector3(-0.6, 0.5, -0.6)
# The draw's ground strike: a method key on the clip at draw_sword_strike_
# time (the frame the tip meets the sand; region_field.tscn sets it), like
# the grab's, acting only while a battle entry is under way - not after a
# fight ended or a card's clip cut the draw off (_on_draw_sword_strike_
# key()). On it the sand puff of a slash hit rises, draw_strike_puff_scale
# its size and speed, on the drawn sand under the sword tip (draw_strike),
# with the ground-strike sound there, and the fight's opening hold ends
# (draw_strike_passed). Both read at each entry.
@export var draw_sword_strike_time: float = 21.0 / 24.0
@export var draw_strike_puff_scale: float = 1.0

@export_group("Shading")
# TEXTURED: wanderer_painted.gdshader - the painted albedo under a soft
# wrapped light with eased shadows (light_wrap, self_shadow_strength).
# POSTERIZED: wanderer_flat.gdshader's quantized dark/mid/light ramp.
# FLAT: the single flat charcoal material, no texture at all. Re-applies
# live via the setter below, so this can be flipped from the Remote tab
# without a re-run.
@export var shading_mode: ShadingMode = ShadingMode.TEXTURED:
	set(value):
		shading_mode = value
		if _model != null:
			_apply_model_material(_model)
		if _sword_root != null:
			_apply_model_material(_sword_root, false)

# Multiplied into the body's albedo texture in TEXTURED mode - white is
# the texture as painted, darker darkens him against the sand. Body only,
# never the sword. POSTERIZED and FLAT ignore it: their own tone colors /
# wanderer_color set how dark he is there.
@export var albedo_tint: Color = Color(1, 1, 1, 1):
	set(value):
		albedo_tint = value
		_set_textured_parameter(&"albedo_tint", value, false)
# Mirror wanderer_painted.gdshader's wrap and self_shadow_strength - see
# that file. TEXTURED only; each re-applies live to the body and sword.
@export_range(0.0, 1.0) var light_wrap: float = 0.6:
	set(value):
		light_wrap = value
		_set_textured_parameter(&"wrap", value, true)
@export_range(0.0, 1.0) var self_shadow_strength: float = 0.5:
	set(value):
		self_shadow_strength = value
		_set_textured_parameter(&"self_shadow_strength", value, true)
# His share of the depth fog in TEXTURED: wanderer_painted.gdshader is
# fog_disabled, and an enemy_fog.gdshader pass on the body and the sword
# lays it back at this much - 1 is exactly as the scene would fog him
# (RegionField pushes the fog through refresh_fog()). Live.
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 1.0:
	set(value):
		fog_factor = value
		_push_fog()

# Mirror wanderer_flat.gdshader's uniforms one-to-one - see that file
# for what each does. Only used when shading_mode is POSTERIZED; each
# re-applies live to the body's material (the cut-offs and the light step
# to the sword's as well).
@export_range(2, 8) var tone_count: int = 3:
	set(value):
		tone_count = value
		_set_posterized_parameter(&"tone_count", value, false)
@export var tone_dark: Color = Color(0.125, 0.12, 0.115, 1):
	set(value):
		tone_dark = value
		_set_posterized_parameter(&"tone_dark", value, false)
@export var tone_mid: Color = Color(0.205, 0.195, 0.185, 1):
	set(value):
		tone_mid = value
		_set_posterized_parameter(&"tone_mid", value, false)
@export var tone_light: Color = Color(0.31, 0.295, 0.28, 1):
	set(value):
		tone_light = value
		_set_posterized_parameter(&"tone_light", value, false)
@export_range(0.0, 1.0) var band_low_cutoff: float = 0.333333:
	set(value):
		band_low_cutoff = value
		_set_posterized_parameter(&"band_low_cutoff", value, true)
@export_range(0.0, 1.0) var band_high_cutoff: float = 0.666667:
	set(value):
		band_high_cutoff = value
		_set_posterized_parameter(&"band_high_cutoff", value, true)
@export_range(0.0, 1.0) var light_step_softness: float = 0.0:
	set(value):
		light_step_softness = value
		_set_posterized_parameter(&"light_step_softness", value, true)
# The sword's one flat colour in POSTERIZED (all three of its tones), lit
# through the same stepped light as the body.
@export var sword_steel_color: Color = Color(0.42, 0.44, 0.47, 1):
	set(value):
		sword_steel_color = value
		if _sword_material != null and shading_mode == ShadingMode.POSTERIZED:
			for parameter: StringName in [&"tone_dark", &"tone_mid", &"tone_light"]:
				_sword_material.set_shader_parameter(parameter, value)

@export_group("Sword")
# Audited: every sword export below carries an explicit get (returns the
# backing field directly - no implicit-getter ambiguity) alongside its
# set, and every setter that touches a node (_sword_root/_sword_mesh_
# holder) guards on that node being non-null, which is only true once
# _setup_sword() has run in _ready() - so a setter firing during scene
# deserialization (before _ready()) is always a plain no-op on the
# backing field, never a reset of anything else. _build_sword() and
# _switch_sword_mount() never read a constant or a cached copy of any of
# these - every read below is the live export at call time, so a scene-
# file override is exactly what ends up applied at _ready() and at every
# enter_battle_stance()/exit_battle_stance() mount switch after it.
# The run's weapon sets its own fit onto them (WeaponData.field_fit()) as
# _build_sword() builds it; what it leaves unset keeps the scene's value.

# Uniform scale is derived from this / the sword model's own raw AABB
# longest axis (see _apply_sword_scale()) - same "measure raw, then derive
# a factor" approach _scale_and_ground_model() uses for the body.
@export var sword_length: float = 1.3:
	get:
		return sword_length
	set(value):
		sword_length = value
		_apply_sword_scale()

# Where _sword_root's own origin sits along the blade's detected long
# axis, as a fraction from the tip - 0.82 is "just below the guard" for a
# typical sword's blade:hilt proportions. Both mounts then position this
# grip point, not the mesh's own (arbitrary) authored origin. See
# _apply_grip_offset().
@export_range(0.0, 1.0) var grip_fraction: float = 0.82:
	get:
		return grip_fraction
	set(value):
		grip_fraction = value
		_apply_grip_offset()
# Which end of the detected axis is the tip is a guess - true assumes the
# lower local coordinate is the tip, false (default) assumes the higher
# one is. Flip live if the grip lands at the wrong end (i.e. near the
# point instead of the guard).
@export var grip_axis_flip: bool = false:
	get:
		return grip_axis_flip
	set(value):
		grip_axis_flip = value
		_apply_grip_offset()

# Bone names may be sanitized on import (Mixamo's "mixamorig:RightHand"
# imports as "mixamorig_RightHand") - resolved by suffix match against the
# skeleton, same as everywhere else in this project that reads Mixamo bone
# names.
# StringName (not String): these are identifiers, not display text, and
# an empty one is a real hazard - String.ends_with("") is true for every
# bone, so an empty suffix would silently "match" bone 0 instead of
# failing to match anything. _find_bone_by_suffix() checks for and warns
# on that case explicitly rather than relying on the "-1, not found"
# warning alone. Both defaults are non-empty and must stay that way.
@export var back_mount_bone_suffix: StringName = &"Spine2":
	get:
		return back_mount_bone_suffix
	set(value):
		back_mount_bone_suffix = value
		_update_mount_bone(true)
@export var hand_mount_bone_suffix: StringName = &"RightHand":
	get:
		return hand_mount_bone_suffix
	set(value):
		hand_mount_bone_suffix = value
		_update_mount_bone(false)

# All four offsets below are untested first guesses (this project's own
# "never run the game" rule means they can't be checked here) - meant to
# be tuned live from the Remote tab against an actual running instance,
# which is exactly why each has a live-reapplying setter rather than only
# taking effect once at _ready(). The two positions are in WORLD metres
# (not the attachment's own local space, which is the model's unscaled
# bone space, scaled by however the source model ships - on v2, ~0.019 m
# tall, a raw 0.14 offset would have put the sword ~13 m away):
# _world_offset_to_local() divides by _skeleton_scale_factor before
# writing _sword_root.position. Rotations are unaffected by that scale, so
# they're applied as given.
@export var back_mount_position: Vector3 = Vector3(0.0, 0.15, -0.18):
	get:
		return back_mount_position
	set(value):
		back_mount_position = value
		if _sword_root != null and _sword_root.get_parent() == _back_frame:
			_sword_root.position = _world_offset_to_local(value)
@export var back_mount_rotation_degrees: Vector3 = Vector3(15.0, -100.0, 80.0):
	get:
		return back_mount_rotation_degrees
	set(value):
		back_mount_rotation_degrees = value
		if _sword_root != null and _sword_root.get_parent() == _back_frame:
			_sword_root.rotation_degrees = value
@export var hand_mount_position: Vector3 = Vector3(0.0, 0.0, 0.0):
	get:
		return hand_mount_position
	set(value):
		hand_mount_position = value
		if _sword_root != null and _sword_root.get_parent() == _hand_frame:
			_sword_root.position = _world_offset_to_local(value)
@export var hand_mount_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	get:
		return hand_mount_rotation_degrees
	set(value):
		hand_mount_rotation_degrees = value
		if _sword_root != null and _sword_root.get_parent() == _hand_frame:
			_sword_root.rotation_degrees = value

var _model: Node3D = null
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
# Whether his model carries battle_camera_turn_degrees (_model_yaw()) -
# set by enter_battle_stance(), cleared by exit_battle_stance().
var _battle_turned: bool = false
# Whether Slash is the glb's own (_merge_clips()), not the Mixamo fallback.
var _own_slash: bool = false
# Whether DrawSword is the glb's own (_merge_clips()), not the Mixamo
# fallback; the path its grab key calls through; whether a battle entry
# is waiting on that key (enter_battle_stance()); and the handoff's tween
# once it has fired (_grab_sword()).
var _own_draw_sword: bool = false
var _grab_key_path: NodePath = NodePath()
var _grab_pending: bool = false
# A battle entry waits on DrawSword's ground-strike key.
var _strike_pending: bool = false
var _grab_tween: Tween = null
# The handoff's turn (_begin_handoff()), in his model's space: where the
# sword stood at the grab and where it passes on the way; and its grip
# position in the hand's frame at the grab.
var _handoff_from: Quaternion = Quaternion.IDENTITY
var _handoff_via: Quaternion = Quaternion.IDENTITY
var _handoff_from_position: Vector3 = Vector3.ZERO
# The one-shot clip a card last started (_on_card_played()) - a swing,
# while it's still the one playing (_swinging()).
var _swing_clip: StringName = &""
# The Slash lunge in flight (_play_slash_lunge()), and the model's x/z it
# returns to.
var _lunge_tween: Tween = null
var _lunge_home: Vector2 = Vector2.ZERO
# The timer that ends hold_animation()'s stop (null = none), the playback
# speed it puts back and the tweens it paused (the lunge, a recoil). And
# the latest recoil, which a stop also holds.
var _anim_hold_timer: SceneTreeTimer = null
var _anim_held_speed: float = 1.0
var _anim_held_tweens: Array[Tween] = []
var _recoil_tween: Tween = null
# The mixer applying the model's poses (the AnimationTree when it's on,
# else the AnimationPlayer); foot grounding runs on its mixer_applied.
var _grounding_mixer: AnimationMixer = null
var _camera: Camera3D
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

var _has_move_target: bool = false
var _move_target: Vector3 = Vector3.ZERO
var _move_target_enemy: FieldEnemy = null
var _stuck_timer: float = 0.0
# The planned walk (set_move_path()): its waypoints, and the one he is
# walking to. Empty: a straight walk to _move_target.
var _path: PackedVector3Array = PackedVector3Array()
var _path_index: int = 0

# True while the ground hold is what he stands on - the drawn surface is
# above the collision under him (a draining channel) - see _hold_above_
# visible_ground(). Read through _is_grounded() wherever the body would
# otherwise ask is_on_floor().
var _ground_hold_active: bool = false
var _ground_hold_warned: bool = false

# The hold line (see the Hold Line export group): a point on it and the
# unit XZ direction he may not move along past it, set by set_hold_line()
# and dropped by clear_hold_line(). _hold_line_armed: hold_line_reached
# may fire on the next arrival. The look back (look_back_toward()): a
# facing he turns to while he stands at the line, dropped when he walks
# off it or the line lifts.
var _hold_line_active: bool = false
var _hold_line_point: Vector3 = Vector3.ZERO
var _hold_line_normal: Vector3 = Vector3.ZERO
var _hold_line_armed: bool = true
# The wade limit (set_wade_limit()): the ground its distance is read from,
# and the metres (below 0: none). And his distance past shore as this
# frame's move began - the most it may end at, when that is past the
# limit.
var _wade_ground: Ground = null
var _wade_limit_m: float = -1.0
var _wade_start_distance: float = 0.0
var _look_back_active: bool = false
var _look_back_direction: Vector3 = Vector3.ZERO

# Set by ZoneIntro for the zone intro, which runs this node ALWAYS
# through the field freeze: input is read as nothing - no WASD, no dash,
# any click target dropped - while everything else in _physics_process()
# (gravity, move_and_slide(), Idle) keeps running, so he stands seated on
# the sand rather than hovering where the freeze caught him. Cleared when
# the intro ends or is skipped; a key still held at that moment moves
# him then.
var input_locked: bool = false
# The arrival hold (RegionField): the movement keys and dash read as
# nothing - polled, so a key held from the last floor or pressed now moves
# nothing - while a walk already given (set_move_target()) carries on;
# the hold swallows the clicks that would give one. Cleared when the
# hold ends; a key still held then moves him.
var keys_locked: bool = false

# Debug-only line visualizations for _apply_step_up_and_down()'s two probe
# casts - built once in _ready() (top_level, so their own transform IS
# world space rather than inheriting Wanderer's) and only fed vertices/
# shown while debug_draw_step_casts is true; see _set_debug_line().
var _step_forward_line: MeshInstance3D = null
var _step_down_line: MeshInstance3D = null

# TEMPORARY - see the diagnostic note in _apply_step_up_and_down. Edge-
# triggers the debug print so it fires once per wall contact, not every
# physics frame the body stays pressed against one.
var _wall_step_logged: bool = false

# Read once from the actual CapsuleShape3D at _ready() (see _find_capsule_
# radius()) rather than exported separately - the collision shape is the
# one source of truth for it, and duplicating it as its own tunable would
# just be one more place to forget to update if the capsule is ever resized.
var _capsule_radius: float = 0.0

# Cached once by _find_grounding_bones() so _apply_continuous_foot_
# grounding() never does a name lookup or a skeleton scan - just two
# pose reads by index, every physics frame.
var _grounding_skeleton: Skeleton3D = null
var _grounding_bone_indices: Array[int] = []

# The uniform scale _scale_and_ground_model() applied to the model, set
# once there - _apply_sword_scale() has to divide its own scale factor by
# this, since the sword sits under a BoneAttachment3D that's a descendant of
# the (hugely up-scaled) model and inherits its scale on top of whatever
# the sword's own node.scale is set to.
var _model_scale_factor: float = 1.0
# The skeleton's own uniform scale in this body's space, set once by
# _setup_sword() - what the sword, under a BoneAttachment3D on that
# skeleton, actually inherits. The model's scale times any node between
# model and skeleton: equal to _model_scale_factor for the FBX rigs, whose
# skeleton sits directly under the model; a glTF rig's skeleton sits under
# an Armature node with a scale of its own.
var _skeleton_scale_factor: float = 1.0

# The model's scaled bbox height and half its larger horizontal extent,
# from _scale_and_ground_model() - same pair FieldEnemy keeps, read by
# CameraRig's battle fit. Height is target_height whenever the scale is
# auto-derived; 0 until the model has been measured.
var _model_height: float = 0.0
var _model_half_width: float = 0.0

func get_head_height() -> float:
	return _model_height

func get_half_width() -> float:
	return _model_half_width

var _sword_skeleton: Skeleton3D = null
var _sword_root: Node3D = null
var _sword_mesh_holder: Node3D = null
var _sword_raw_aabb: AABB = AABB()
# The sword's albedo as _build_sword() chose it, for shading_mode's
# rebuilds.
var _sword_albedo: Texture2D = null
# The fit exports as the scene set them (SWORD_FIT_PROPERTIES), read once
# by _setup_sword(): what a weapon's unset fit values fall back to.
var _scene_sword_fit: Dictionary = {}
# The last mount switch's tween (_switch_sword_mount()) until it ends.
var _sword_mount_tween: Tween = null
# The run's weapon changed while the sword was off his back mount: it is
# rebuilt once it rests there again (_on_sword_mount_settled()).
var _sword_rebuild_pending: bool = false
var _back_attachment: BoneAttachment3D = null
var _hand_attachment: BoneAttachment3D = null
# What the sword actually hangs from: one child of each attachment whose
# basis cancels any scale and shear in its bone's pose (_fit_mount_
# frames()), so the sword keeps sword_length and a clean turn in every
# pose. A battle_idle that keys bone scale (wanderer_v2.glb's stretched
# shoulders and upper arms 1.2-1.3x) passes it to the right hand; a bone
# with no scale in its pose, as in wanderer_v3.glb, leaves its frame at
# identity.
var _back_frame: Node3D = null
var _hand_frame: Node3D = null

# The body's own currently-applied material (set by _apply_model_material()
# for is_body calls only, never for the sword's) - play_hit_flash() tweens
# this directly rather than re-deriving it, since re-deriving would mean
# re-walking the model's MeshInstance3D children and, worse, building a
# second material instance no MeshInstance3D actually has assigned.
var _active_material: Material = null
# The body's albedo (_find_body_albedo()), kept for shading_mode's rebuilds.
var _body_albedo: Texture2D = null
# The sword's TEXTURED or POSTERIZED shader material while it has one,
# else null - for the live setters above.
var _sword_material: ShaderMaterial = null
# The TEXTURED materials' fog passes (next_pass), body and sword, while
# they have them, and the sky refresh_fog() last pushed.
var _body_fog: ShaderMaterial = null
var _sword_fog: ShaderMaterial = null
var _fog_sky: RegionSky = null
var _ground: Ground = null
var _attack_audio: AttackAudio = null
# The sound of being hit - see HitAudio; made beside _attack_audio below.
var _hit_audio: HitAudio = null

# Set by bind_to_battle(), cleared by unbind_battle() - see both for why
# region_field.gd is the only caller of either.
var _battle_controller: BattleController = null

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D

	var character: CharacterData = _character()
	var model: Node3D = _instantiate_model(character)
	if character != null:
		target_height = character.field_model_height
		model_yaw_offset = character.field_model_yaw_degrees
	_model = model
	add_child(model)
	# RegionField freezes itself (and, by inheritance, the Wanderer and
	# everything under it) on battle contact, but Idle still needs to keep
	# playing through that freeze. Overriding only the AnimationPlayer's own
	# process_mode below isn't enough: the player would keep advancing and
	# writing bone poses, but the model's own Skeleton3D still inherits the
	# freeze and gates the internal step that flushes those poses to the
	# renderer, so the mesh would visibly stay stuck mid-pose regardless.
	# Exempting the whole model subtree here (before anything below it is
	# queried) covers Skeleton3D and everything else in one shot.
	model.process_mode = Node.PROCESS_MODE_ALWAYS
	# Mixamo meshes face +Z in their own space while the body's forward is
	# -Z (see _forward_from_angle()), so the model is rotated to match.
	model.rotation.y = deg_to_rad(model_yaw_offset)
	_body_albedo = _find_body_albedo(model, character)
	_apply_model_material(model)
	_scale_and_ground_model(model)
	# No skeleton, no rig: none of the clip, grounding, sword or footprint
	# setup below has bones to find, so it's skipped rather than warned.
	var rigged: bool = not model.find_children("*", "Skeleton3D", true, false).is_empty()

	var players := model.find_children("*", "AnimationPlayer", true, false)
	_animation_player = players[0] as AnimationPlayer if not players.is_empty() else null
	# Same reasoning as CameraPivot's own process_mode override - belt and
	# suspenders alongside model.process_mode above, since this is also the
	# node whose own _process actually advances playback.
	if _animation_player:
		_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS

	if rigged:
		_merge_clips(_animation_player)
	if use_animation_tree:
		_build_animation_tree()
	elif _animation_player:
		_animation_player.play("Idle")

	if rigged:
		_find_grounding_bones(model)
	# Grounding follows each pose as the mixer lands it, not
	# _physics_process: RegionField's battle freeze stops the Wanderer's
	# own processing, but the mixer keeps playing BattleIdle, DrawSword,
	# Slash and Brace through it, and each stands its hips at its own
	# height.
	_grounding_mixer = _animation_tree if _animation_tree != null else _animation_player
	if _grounding_mixer != null:
		_grounding_mixer.mixer_applied.connect(_on_mixer_applied)
	# DrawSword cut off - another clip, or stopped - while an entry waits on
	# its grab key: the grab happens there (_on_draw_sword_cut()).
	if _animation_player != null:
		_animation_player.current_animation_changed.connect(_on_draw_sword_cut.unbind(1))
		_animation_player.mixer_applied.connect(_on_draw_sword_cut)
	if rigged:
		_setup_sword(model)
	_setup_step_debug_lines()
	_capsule_radius = _find_capsule_radius()

	var contact_shadow := ContactShadow.new()
	contact_shadow.name = "ContactShadow"
	add_child(contact_shadow)

	var ground := get_node_or_null(ground_path) as Ground
	_ground = ground

	var footprint_spawner := FootprintSpawner.new()
	footprint_spawner.name = "FootprintSpawner"
	add_child(footprint_spawner)
	if rigged:
		footprint_spawner.setup(model, self, ground)

	var footstep_audio := FootstepAudio.new()
	footstep_audio.name = "FootstepAudio"
	add_child(footstep_audio)
	footstep_audio.setup(footprint_spawner, ground)

	_attack_audio = AttackAudio.new()
	_attack_audio.name = "AttackAudio"
	add_child(_attack_audio)
	_attack_audio.setup()

	_hit_audio = HitAudio.new()
	_hit_audio.name = "HitAudio"
	add_child(_hit_audio)
	_hit_audio.setup()

# The run's character, for the model: RunState's once a run has started,
# else the one RegionField is about to start it with - the first floor's
# Wanderer is ready before RegionField._ready() calls new_run().
func _character() -> CharacterData:
	var field := get_parent() as RegionField
	if field != null:
		return field.get_run_character()
	return RunState.character

# The character's field model, instanced. An empty Node3D (and an error)
# when there is none to load, so nothing below has a null model to trip on.
func _instantiate_model(character: CharacterData) -> Node3D:
	var path: String = character.field_model_path if character != null else ""
	var scene: PackedScene = load(path) as PackedScene if not path.is_empty() else null
	if scene == null:
		push_error("Wanderer: no field model to load (%s); standing an empty body." % path)
		return Node3D.new()
	return scene.instantiate() as Node3D

# The body's albedo: the character's field_albedo, else the model's own
# imported base colour (its first mesh's first surface material).
func _find_body_albedo(model: Node3D, character: CharacterData) -> Texture2D:
	if character != null and character.field_albedo != null:
		return character.field_albedo
	return _imported_albedo(model)

# A model's own imported base colour: its first mesh's first surface
# material's albedo texture, null if it has none.
func _imported_albedo(model: Node3D) -> Texture2D:
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mesh_instance as MeshInstance3D).mesh
		if mesh == null or mesh.get_surface_count() == 0:
			continue
		var imported := mesh.surface_get_material(0) as BaseMaterial3D
		if imported != null and imported.albedo_texture != null:
			return imported.albedo_texture
	return null

# One shared material for the whole model, applied via material_override
# on every MeshInstance3D under it. Which material depends on shading_
# mode (see that export's own doc); the body's TEXTURED/POSTERIZED both
# fall back to the flat charcoal material if their own asset (texture
# and/or shader) fails to load (each guarded and push_warning'd
# separately below), so a missing/not-yet-imported asset degrades to a
# solid color instead of an invisible or shaderless model. Re-run
# whenever shading_mode's setter fires, so this always reflects the
# current mode - not just at _ready().
# The sword (is_body false) gets its own painted texture (_sword_albedo)
# in TEXTURED and flat sword_steel_color in POSTERIZED, through the same
# shaders. Neither
# ever uses a glb's imported material: wanderer_v3.glb's reads the
# unpainted source with that same image as its normal map, and sword.glb's
# is metallic with a normal map.
func _apply_model_material(model: Node3D, is_body: bool = true) -> void:
	if not is_body:
		_sword_material = null

	var material: Material = null
	match shading_mode:
		ShadingMode.TEXTURED:
			if is_body:
				material = _build_textured_material(_body_albedo, albedo_tint)
			else:
				_sword_material = _build_textured_material(_sword_albedo, Color.WHITE)
				material = _sword_material
		ShadingMode.POSTERIZED:
			if is_body:
				material = _build_posterized_material(_body_albedo)
			else:
				_sword_material = _build_sword_steel_material()
				material = _sword_material
		ShadingMode.FLAT:
			material = null
	if material == null:
		material = _build_flat_material()
	# The painted shader leaves the fog out; its pass lays it back.
	var fog: ShaderMaterial = null
	if shading_mode == ShadingMode.TEXTURED and material is ShaderMaterial:
		fog = _build_fog_pass()
		material.next_pass = fog
	if is_body:
		_body_fog = fog
	else:
		_sword_fog = fog
	_push_fog()
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The sword's own material_override is never what play_hit_flash()
	# should be lerping (only the body should flash), so this only ever
	# tracks the body's material regardless of which shading_mode built it.
	if is_body:
		_active_material = material

# The painted texture under wanderer_painted.gdshader's soft light. Null
# (the flat fallback) if the texture or the shader fails to load.
func _build_textured_material(texture: Texture2D, tint: Color) -> ShaderMaterial:
	if texture == null:
		push_warning("Wanderer: no albedo texture; using the flat charcoal fallback material.")
		return null
	var shader := load(PAINTED_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Wanderer: wanderer_painted shader failed to load (%s); using the flat charcoal fallback material." % PAINTED_SHADER_PATH)
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_tint", tint)
	material.set_shader_parameter("wrap", light_wrap)
	material.set_shader_parameter("self_shadow_strength", self_shadow_strength)
	return material

# enemy_fog.gdshader, as FieldEnemy lays it over an enemy: null if it
# fails to load (he then goes unfogged).
func _build_fog_pass() -> ShaderMaterial:
	var shader := load(FOG_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Wanderer: fog pass shader failed to load (%s); unfogged." % FOG_SHADER_PATH)
		return null
	var pass_material := ShaderMaterial.new()
	pass_material.shader = shader
	return pass_material

# The field's depth fog (RegionField._refresh_enemy_fog(), on every fog
# change) into his fog passes.
func refresh_fog(sky: RegionSky) -> void:
	_fog_sky = sky
	_push_fog()

func _push_fog() -> void:
	if _fog_sky == null:
		return
	for pass_material: ShaderMaterial in [_body_fog, _sword_fog]:
		if pass_material == null:
			continue
		pass_material.set_shader_parameter("fog_color", _fog_sky.fog_color)
		pass_material.set_shader_parameter("fog_energy", _fog_sky.fog_light_energy)
		pass_material.set_shader_parameter("fog_begin", _fog_sky.current_fog_depth_begin())
		pass_material.set_shader_parameter("fog_end", _fog_sky.current_fog_depth_end())
		pass_material.set_shader_parameter("fog_density", _fog_sky.fog_density)
		pass_material.set_shader_parameter("fog_factor", fog_factor)

# A TEXTURED setting's live edit: onto the body's shader material, and the
# sword's too when include_sword. No-op in the other modes.
func _set_textured_parameter(parameter: StringName, value: Variant, include_sword: bool) -> void:
	if shading_mode != ShadingMode.TEXTURED:
		return
	var body := _active_material as ShaderMaterial
	if body != null:
		body.set_shader_parameter(parameter, value)
	if include_sword and _sword_material != null:
		_sword_material.set_shader_parameter(parameter, value)

func _build_posterized_material(texture: Texture2D) -> ShaderMaterial:
	if texture == null:
		push_warning("Wanderer: no albedo texture; using the flat charcoal fallback material.")
		return null
	var shader := load(FLAT_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Wanderer: wanderer_flat shader failed to load (%s); using the flat charcoal fallback material." % FLAT_SHADER_PATH)
		return null
	var material := _posterized_shader_material(shader)
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("tone_count", tone_count)
	material.set_shader_parameter("tone_dark", tone_dark)
	material.set_shader_parameter("tone_mid", tone_mid)
	material.set_shader_parameter("tone_light", tone_light)
	print("Wanderer: applied posterized material - texture=%s tone_count=%d tone_dark=%s tone_mid=%s tone_light=%s" % [texture.resource_path, tone_count, tone_dark, tone_mid, tone_light])
	return material

# The sword in POSTERIZED: wanderer_flat.gdshader with no texture and all
# three tones sword_steel_color, so it is one flat colour under the same
# stepped light as the body. Null (the flat fallback) if the shader fails.
func _build_sword_steel_material() -> ShaderMaterial:
	var shader := load(FLAT_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Wanderer: wanderer_flat shader failed to load (%s); the sword uses the flat charcoal fallback material." % FLAT_SHADER_PATH)
		return null
	var material := _posterized_shader_material(shader)
	for parameter: StringName in [&"tone_dark", &"tone_mid", &"tone_light"]:
		material.set_shader_parameter(parameter, sword_steel_color)
	return material

# The shader settings the body and the sword share.
func _posterized_shader_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("band_low_cutoff", band_low_cutoff)
	material.set_shader_parameter("band_high_cutoff", band_high_cutoff)
	material.set_shader_parameter("light_step_softness", light_step_softness)
	return material

# A POSTERIZED setting's live edit: onto the body's shader material, and
# the sword's too when include_sword. No-op in the other modes.
func _set_posterized_parameter(parameter: StringName, value: Variant, include_sword: bool) -> void:
	if shading_mode != ShadingMode.POSTERIZED:
		return
	var body := _active_material as ShaderMaterial
	if body != null:
		body.set_shader_parameter(parameter, value)
	if include_sword and _sword_material != null:
		_sword_material.set_shader_parameter(parameter, value)

# The source model ships at whatever raw scale its file happens to use
# (measured at 0.019m tall before target_height existed) - this measures
# that raw AABB height right after instancing (model.scale is still 1 at
# this point, so the AABB below is in unscaled local units), derives a
# uniform scale factor from it (or takes model_scale_override directly
# when nonzero), applies that to model.scale, then grounds the model so
# its feet land at y=0 in Wanderer's local space. Same combined-AABB
# technique FieldEnemy._spawn_model() already uses.
#
# Rotation about Y (model_yaw_offset above) never changes a point's Y
# component, so the pre-scale AABB's Y extents survive that rotation
# unchanged - only the scale factor below affects them.
#
# A skinned mesh is measured as it stands at rest (_skinned_rest_aabb()),
# not through its MeshInstance3D's node transform: a skinned mesh draws
# where its skeleton puts it, and a glTF rig's mesh node can sit under an
# Armature node (scaled 0.01 and turned 90 deg) that the node-transform
# reading would wrongly fold in. For the FBX rigs the two readings are the
# same box (to float rounding), and there the node-transform one stands.
func _scale_and_ground_model(model: Node3D) -> void:
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_transform_in_model: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_model: AABB = mi_transform_in_model * mi.get_aabb()
		var skinned_aabb: AABB = _skinned_rest_aabb(model, mi)
		if skinned_aabb.size != Vector3.ZERO and not skinned_aabb.is_equal_approx(mi_aabb_in_model):
			mi_aabb_in_model = skinned_aabb
		combined_aabb = mi_aabb_in_model if not has_aabb else combined_aabb.merge(mi_aabb_in_model)
		has_aabb = true
	if not has_aabb:
		push_warning("Wanderer: model has no MeshInstance3D children; cannot scale or ground it.")
		return

	var scale_factor := model_scale_override
	if scale_factor == 0.0:
		var raw_height := combined_aabb.size.y
		if raw_height <= 0.0001:
			push_warning("Wanderer: model AABB height is ~0 (%f); leaving scale at 1.0." % raw_height)
			scale_factor = 1.0
		else:
			scale_factor = target_height / raw_height

	model.scale = Vector3.ONE * scale_factor
	model.position.y += -combined_aabb.position.y * scale_factor
	_model_scale_factor = scale_factor
	_model_height = combined_aabb.size.y * scale_factor
	_model_half_width = maxf(combined_aabb.size.x, combined_aabb.size.z) * 0.5 * scale_factor

# The box a skinned mesh fills at its skeleton's rest pose, in model's
# space: every vertex through its weighted binds (skeleton x bone global
# rest x bind pose) - where the skeleton actually draws it. An empty AABB
# when mi isn't skinned (no skin, no skeleton, no binds), for the caller's
# node-transform reading to take over.
func _skinned_rest_aabb(model: Node3D, mi: MeshInstance3D) -> AABB:
	var skeleton := mi.get_node_or_null(mi.skeleton) as Skeleton3D
	var skin: Skin = mi.skin
	if skeleton == null or skin == null or skin.get_bind_count() == 0 or mi.mesh == null:
		return AABB()
	var skeleton_in_model: Transform3D = model.global_transform.affine_inverse() * skeleton.global_transform
	var binds: Array[Transform3D] = []
	for bind_idx in skin.get_bind_count():
		var bone_idx: int = skin.get_bind_bone(bind_idx)
		if bone_idx < 0:
			bone_idx = skeleton.find_bone(skin.get_bind_name(bind_idx))
		if bone_idx < 0:
			return AABB()
		binds.append(skeleton_in_model * skeleton.get_bone_global_rest(bone_idx) * skin.get_bind_pose(bind_idx))
	var low := Vector3.INF
	var high := -Vector3.INF
	for surface_idx in mi.mesh.get_surface_count():
		var arrays: Array = mi.mesh.surface_get_arrays(surface_idx)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		if vertices.is_empty() or bones.size() != weights.size() or bones.size() % vertices.size() != 0:
			return AABB()
		var per_vertex: int = bones.size() / vertices.size()
		for vertex_idx in vertices.size():
			var point := Vector3.ZERO
			for k in per_vertex:
				var weight: float = weights[vertex_idx * per_vertex + k]
				if weight > 0.0:
					point += (binds[bones[vertex_idx * per_vertex + k]] * vertices[vertex_idx]) * weight
			low = low.min(point)
			high = high.max(point)
	if low == Vector3.INF:
		return AABB()
	return AABB(low, high - low)

# Finds the skeleton and the lowest-contact bone indices once, at
# startup - cached into _grounding_skeleton/_grounding_bone_indices so the
# continuous per-physics-frame correction below never does a name lookup
# or a skeleton scan, just two pose reads by index.
#
# Prefers toe bones (LeftToeBase/RightToeBase) since those sit at the
# actual ground contact point; falls back to LeftFoot/RightFoot if no toe
# bone is present on this rig. Found by suffix (_find_bone_by_suffix()),
# whatever the rig's prefix - mixamorig_, smartrig_.
func _find_grounding_bones(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_grounding_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if _grounding_skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; continuous foot grounding disabled.")
		return

	var toe_suffixes: Array[StringName] = [&"LeftToeBase", &"RightToeBase"]
	var foot_suffixes: Array[StringName] = [&"LeftFoot", &"RightFoot"]
	var toe_present := false
	for suffix in toe_suffixes:
		if _find_bone_by_suffix(_grounding_skeleton, suffix) != -1:
			toe_present = true
			break
	var suffixes: Array[StringName] = toe_suffixes if toe_present else foot_suffixes

	_grounding_bone_indices.clear()
	for suffix in suffixes:
		var bone_idx := _find_bone_by_suffix(_grounding_skeleton, suffix)
		if bone_idx != -1:
			_grounding_bone_indices.append(bone_idx)

	if _grounding_bone_indices.is_empty():
		push_warning("Wanderer: none of the expected foot/toe bones were found on the skeleton; continuous foot grounding disabled.")
		_grounding_skeleton = null

# Builds the two ImmediateMesh line visualizations _apply_step_up_and_down()
# draws into via _set_debug_line() - green for the forward probe, red for
# the downward one. Created once here regardless of debug_draw_step_casts's
# current value (both start hidden) so toggling the export live from the
# Remote tab has something to show/hide rather than needing its own setter.
func _setup_step_debug_lines() -> void:
	_step_forward_line = _create_debug_line_mesh(Color(0.2, 0.9, 0.3))
	_step_down_line = _create_debug_line_mesh(Color(0.9, 0.25, 0.2))

# Wanderer's own body collider is a direct CollisionShape3D child (not the
# model's - that one's under _model, unrelated to physics), so this is a
# plain top-level find rather than the model.find_children() pattern used
# everywhere else in this file. Returns 0.0 (with a warning) if the shape
# isn't a CapsuleShape3D, matching this project's "degrade loudly, don't
# crash" convention (see e.g. _build_textured_material()'s own fallback).
func _find_capsule_radius() -> float:
	for child in get_children():
		var collision_shape := child as CollisionShape3D
		if collision_shape == null:
			continue
		var capsule := collision_shape.shape as CapsuleShape3D
		if capsule != null:
			return capsule.radius
	push_warning("Wanderer: no CapsuleShape3D found on the body; step-up forward probe won't clear the collider's own radius.")
	return 0.0

# top_level = true detaches the node's own transform from Wanderer's, so
# with that transform left at its default (identity) the mesh's local
# vertex space IS world space - _set_debug_line() can feed raw world-space
# cast endpoints straight into surface_add_vertex() with no conversion.
func _create_debug_line_mesh(color: Color) -> MeshInstance3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "StepDebugLine"
	mesh_instance.mesh = ImmediateMesh.new()
	mesh_instance.material_override = material
	mesh_instance.top_level = true
	mesh_instance.visible = false
	add_child(mesh_instance)
	return mesh_instance

# suffix is a StringName (an identifier, not display text) - converted to
# String once here for ends_with(). An empty suffix is rejected outright:
# String.ends_with("") is true for every bone name, so without this check
# an empty suffix would silently match bone 0 instead of failing to match
# anything, and the caller's own "-1, not found" warning would never fire.
func _find_bone_by_suffix(skeleton: Skeleton3D, suffix: StringName) -> int:
	var suffix_text := String(suffix)
	if suffix_text.is_empty():
		push_warning("Wanderer: bone suffix is empty; no bone will match.")
		return -1
	for bone_idx in skeleton.get_bone_count():
		if skeleton.get_bone_name(bone_idx).ends_with(suffix_text):
			return bone_idx
	return -1

# back_mount_position/hand_mount_position are exported in world metres;
# _sword_root's own position is read in its parent BoneAttachment3D's
# local space, which is the skeleton's unscaled bone space (inheriting the
# skeleton's whole scale, _skeleton_scale_factor) - dividing converts a
# world-metre offset into that local space.
func _world_offset_to_local(world_offset: Vector3) -> Vector3:
	if _skeleton_scale_factor <= 0.0001:
		return world_offset
	return world_offset / _skeleton_scale_factor

# Builds two BoneAttachment3D children of the skeleton (one per mount),
# reads the scene's sword fit, and builds the run's weapon on the back
# mount to start (_build_sword()). enter_battle_stance()/exit_battle_
# stance() move it between the two via _switch_sword_mount() - the
# attachments themselves never move once created; only which one
# currently parents _sword_root changes. A new weapon (RunState.weapon_
# changed) is built in its place (_on_weapon_changed()).
func _setup_sword(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_sword_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if _sword_skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; sword mount disabled.")
		return
	_skeleton_scale_factor = _model_scale_factor * _transform_under(_sword_skeleton, model).basis.get_scale().x

	var back_bone_idx := _find_bone_by_suffix(_sword_skeleton, back_mount_bone_suffix)
	var hand_bone_idx := _find_bone_by_suffix(_sword_skeleton, hand_mount_bone_suffix)
	if back_bone_idx == -1:
		push_warning("Wanderer: no bone ending in '%s' found for back_mount; sword mount disabled." % back_mount_bone_suffix)
		return
	if hand_bone_idx == -1:
		push_warning("Wanderer: no bone ending in '%s' found for hand_mount; sword mount disabled." % hand_mount_bone_suffix)
		return

	_back_attachment = BoneAttachment3D.new()
	_back_attachment.name = "SwordBackMount"
	_sword_skeleton.add_child(_back_attachment)
	_back_attachment.bone_name = _sword_skeleton.get_bone_name(back_bone_idx)

	_hand_attachment = BoneAttachment3D.new()
	_hand_attachment.name = "SwordHandMount"
	_sword_skeleton.add_child(_hand_attachment)
	_hand_attachment.bone_name = _sword_skeleton.get_bone_name(hand_bone_idx)

	_back_frame = Node3D.new()
	_back_frame.name = "SwordBackFrame"
	_back_attachment.add_child(_back_frame)
	_hand_frame = Node3D.new()
	_hand_frame.name = "SwordHandFrame"
	_hand_attachment.add_child(_hand_frame)
	_sword_skeleton.skeleton_updated.connect(_fit_mount_frames)
	_fit_mount_frames()

	for property in SWORD_FIT_PROPERTIES:
		_scene_sword_fit[property] = get(property)
	_build_sword()
	RunState.weapon_changed.connect(_on_weapon_changed)

# The run's weapon (RunState.weapon) as the sword on his back mount, in
# place of any sword already built: its fit (WeaponData.field_fit()) over
# the scene's own (_scene_sword_fit), its field model (SWORD_SCENE_PATH
# where it names none) and its albedo (_sword_albedo).
func _build_sword() -> void:
	_sword_rebuild_pending = false
	if _sword_mount_tween != null:
		_sword_mount_tween.kill()
		_sword_mount_tween = null
	if _sword_root != null:
		if _sword_root.get_parent() != null:
			_sword_root.get_parent().remove_child(_sword_root)
		_sword_root.queue_free()
		_sword_root = null
		_sword_mesh_holder = null

	var weapon: WeaponData = RunState.weapon
	var fit: Dictionary = _scene_sword_fit.duplicate()
	if weapon != null:
		fit.merge(weapon.field_fit(), true)
	for property: StringName in fit:
		set(property, fit[property])
	var scene_path: String = SWORD_SCENE_PATH
	if weapon != null and not weapon.field_model_path.is_empty():
		scene_path = weapon.field_model_path

	var sword_scene := load(scene_path) as PackedScene
	if sword_scene == null:
		push_warning("Wanderer: sword scene failed to load (%s); sword mount disabled." % scene_path)
		return
	var sword_mesh_holder := sword_scene.instantiate() as Node3D
	if sword_mesh_holder == null:
		push_warning("Wanderer: sword scene root (%s) is not a Node3D; sword mount disabled." % scene_path)
		return
	if weapon != null and weapon.field_albedo != null:
		_sword_albedo = weapon.field_albedo
	elif scene_path == SWORD_SCENE_PATH:
		_sword_albedo = load(SWORD_ALBEDO_TEXTURE_PATH) as Texture2D
	else:
		_sword_albedo = _imported_albedo(sword_mesh_holder)

	# _sword_root is the node mounts actually position/scale/rotate - its
	# origin is the grip (see _apply_grip_offset()), not wherever the
	# loaded scene's own origin happens to be. _sword_mesh_holder is the
	# loaded scene itself, offset inside _sword_root so the grip point
	# lands at _sword_root's origin regardless of _sword_root's own scale.
	_sword_root = Node3D.new()
	_sword_root.name = "SwordRoot"
	_back_frame.add_child(_sword_root)

	_sword_mesh_holder = sword_mesh_holder
	_sword_mesh_holder.name = "SwordMesh"
	_sword_root.add_child(_sword_mesh_holder)

	# Same "add to tree at scale 1, measure via global_transform, then
	# scale" technique _scale_and_ground_model() uses for the body - the
	# AABB has to come from meshes already in the tree for global_transform
	# to be meaningful. Measured against _sword_mesh_holder (not
	# _sword_root), since _sword_root's own position/scale are about to be
	# set below and would otherwise contaminate this reading.
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in _sword_mesh_holder.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_transform_in_sword: Transform3D = _sword_mesh_holder.global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_sword: AABB = mi_transform_in_sword * mi.get_aabb()
		combined_aabb = mi_aabb_in_sword if not has_aabb else combined_aabb.merge(mi_aabb_in_sword)
		has_aabb = true
	if not has_aabb:
		push_warning("Wanderer: sword model has no MeshInstance3D children; sword mount disabled.")
		_sword_root.queue_free()
		_sword_root = null
		_sword_mesh_holder = null
		return

	print("Wanderer: sword AABB (pre-scale) = %s" % combined_aabb)
	_sword_raw_aabb = combined_aabb

	_apply_sword_scale()

	_apply_model_material(_sword_root, false)

	_apply_grip_offset()

	_sword_root.position = _world_offset_to_local(back_mount_position)
	_sword_root.rotation_degrees = back_mount_rotation_degrees

	# Final sanity check, in world space (i.e. through the whole model-
	# scale + sword-scale chain), to confirm the compensation above
	# actually landed the sword at sword_length rather than still being
	# off by model_scale_factor.
	var world_aabb: AABB
	var has_world_aabb := false
	for mesh_instance in _sword_root.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_aabb_world: AABB = mi.global_transform * mi.get_aabb()
		world_aabb = mi_aabb_world if not has_world_aabb else world_aabb.merge(mi_aabb_world)
		has_world_aabb = true
	if has_world_aabb:
		print("Wanderer: sword final world-space AABB height = %f" % world_aabb.size.y)

# Scales _sword_root so the model's longest side comes out sword_length
# long in the world. No-op until _build_sword() has measured it.
func _apply_sword_scale() -> void:
	if _sword_root == null:
		return
	var longest_axis: float = _sword_raw_aabb.size[_longest_axis_index(_sword_raw_aabb.size)]
	var local_scale_factor := 1.0
	if longest_axis <= 0.0001:
		push_warning("Wanderer: sword AABB longest axis is ~0 (%f); leaving scale at 1.0." % longest_axis)
	else:
		local_scale_factor = sword_length / longest_axis

	# _sword_root sits under _back_frame, on a bone attachment of the model's own
	# Skeleton3D - it inherits the skeleton's whole scale (_skeleton_scale_
	# factor: the model's scale to target_height - ~1.06 for wanderer_v3.
	# glb, ~95 for the old ~0.019 m sources - times any Armature scale
	# between) on top of whatever _sword_root.scale is set to here.
	# Dividing it back out is what makes the sword's actual WORLD length
	# come out to sword_length.
	var world_scale_factor := local_scale_factor
	if _skeleton_scale_factor > 0.0001:
		world_scale_factor = local_scale_factor / _skeleton_scale_factor
	else:
		push_warning("Wanderer: _skeleton_scale_factor is ~0 (%f); sword scale not compensated." % _skeleton_scale_factor)
	_sword_root.scale = Vector3.ONE * world_scale_factor

# The run's weapon changed: built now while the sword rests on his back
# mount, else once it is back there (_on_sword_mount_settled()) - never
# swapped in his hands.
func _on_weapon_changed(_weapon: WeaponData) -> void:
	if _sword_on_back():
		_build_sword()
	else:
		_sword_rebuild_pending = true

# Whether the sword rests on his back mount - there, with no mount switch
# still moving it - or there is none built.
func _sword_on_back() -> bool:
	if _sword_root == null:
		return true
	return _sword_root.get_parent() == _back_frame and _sword_mount_tween == null

# A mount switch's tween is over (`tween`, unless a later switch has
# replaced it): a weapon change that waited for the back mount is built.
func _on_sword_mount_settled(tween: Tween) -> void:
	if tween != _sword_mount_tween:
		return
	_sword_mount_tween = null
	if _sword_rebuild_pending and _sword_on_back():
		_build_sword()

func _longest_axis_index(size: Vector3) -> int:
	var axis := 0
	if size[1] > size[axis]:
		axis = 1
	if size[2] > size[axis]:
		axis = 2
	return axis

# Offsets _sword_mesh_holder inside _sword_root so the grip - at
# grip_fraction along the detected long axis, measured from the tip -
# sits at _sword_root's own origin (the point both mounts actually
# position). Off the other two axes, the pivot is centered on the AABB
# rather than at a corner. Which end of the axis IS the tip is a guess
# (grip_axis_flip) since this project's "never run the game" rule means
# it can't be checked here - flip it live if the grip lands at the wrong
# end. No-op until _build_sword() has populated _sword_mesh_holder/
# _sword_raw_aabb.
func _apply_grip_offset() -> void:
	if _sword_mesh_holder == null:
		return

	var axis := _longest_axis_index(_sword_raw_aabb.size)
	var min_val: float = _sword_raw_aabb.position[axis]
	var max_val: float = min_val + _sword_raw_aabb.size[axis]
	var tip_val: float = min_val if grip_axis_flip else max_val
	var butt_val: float = max_val if grip_axis_flip else min_val
	var grip_val: float = lerpf(tip_val, butt_val, grip_fraction)

	var grip_local: Vector3 = _sword_raw_aabb.position + _sword_raw_aabb.size * 0.5
	grip_local[axis] = grip_val

	_sword_mesh_holder.position = -grip_local

# On every skeleton update (Skeleton3D.skeleton_updated - after the clip
# and the modifiers have posed it): each mount frame's basis becomes its
# bone pose's inverse times that pose orthonormalized, so attachment x
# frame is the bone's turn alone, at the skeleton's own uniform scale.
# Read from the skeleton's pose rather than the attachment, so it doesn't
# matter which of the two updates first.
func _fit_mount_frames() -> void:
	_fit_mount_frame(_back_frame, _back_attachment)
	_fit_mount_frame(_hand_frame, _hand_attachment)

func _fit_mount_frame(frame: Node3D, attachment: BoneAttachment3D) -> void:
	if frame == null or attachment == null or _sword_skeleton == null:
		return
	var bone_idx := _sword_skeleton.find_bone(attachment.bone_name)
	if bone_idx == -1:
		return
	var pose: Basis = _sword_skeleton.get_bone_global_pose(bone_idx).basis
	frame.basis = pose.inverse() * pose.orthonormalized()

# Re-resolves one mount's bone (is_back true for back_mount_bone_suffix,
# false for hand_mount_bone_suffix) against the already-found skeleton and
# repoints that BoneAttachment3D's own bone_name - lets the suffix export
# be retuned live from the Remote tab without a re-run, same as every
# other tunable here.
func _update_mount_bone(is_back: bool) -> void:
	if _sword_skeleton == null:
		return
	var attachment: BoneAttachment3D = _back_attachment if is_back else _hand_attachment
	if attachment == null:
		return
	var suffix: StringName = back_mount_bone_suffix if is_back else hand_mount_bone_suffix
	var bone_idx := _find_bone_by_suffix(_sword_skeleton, suffix)
	if bone_idx == -1:
		push_warning("Wanderer: no bone ending in '%s' found; mount bone unchanged." % suffix)
		return
	attachment.bone_name = _sword_skeleton.get_bone_name(bone_idx)

# Reparents _sword_root onto target_frame (a no-op if it's already
# there; _back_frame or _hand_frame) and tweens its local position/rotation to the target mount's
# offsets over duration, so the switch reads as the sword sliding into
# place rather than popping - matches enter_battle_stance's own movement
# tween shape (parallel, sine in-out) so both read as one motion.
# target_position_world is in world metres (see back_mount_position's own
# doc) - converted to _sword_root's local space before the tween. A weapon
# change waiting for the back mount is built once it ends there (_on_
# sword_mount_settled()).
func _switch_sword_mount(target_frame: Node3D, target_position_world: Vector3, target_rotation_degrees: Vector3, duration: float) -> void:
	if _sword_root == null or target_frame == null:
		return

	var current_parent := _sword_root.get_parent()
	if current_parent != target_frame:
		if current_parent != null:
			current_parent.remove_child(_sword_root)
		target_frame.add_child(_sword_root)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_sword_root, "position", _world_offset_to_local(target_position_world), duration)
	tween.tween_property(_sword_root, "rotation_degrees", target_rotation_degrees, duration)
	_sword_mount_tween = tween
	tween.finished.connect(_on_sword_mount_settled.bind(tween))

# The float this replaces was per-clip: grounding measured once, on
# Idle, doesn't hold once a battle clip (a different hips height) takes
# over. On every pose the mixer applies instead (_on_mixer_applied()):
# read the lowest cached foot/toe bone
# Y in body space (to_local() already accounts for the model's current
# position, so this reflects whatever offset is already applied), derive
# the model.position.y that would put it exactly at model_ground_offset,
# and ease toward that rather than snapping, so a clip transition's own
# hips-height jump doesn't pop the model - it eases in over a few frames.
func _on_mixer_applied() -> void:
	var physics := _grounding_mixer.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_PHYSICS
	_apply_continuous_foot_grounding(get_physics_process_delta_time() if physics else get_process_delta_time())

func _apply_continuous_foot_grounding(delta: float) -> void:
	if _grounding_skeleton == null or _model == null:
		return

	var lowest_local_y := INF
	for bone_idx in _grounding_bone_indices:
		var bone_world_position: Vector3 = _grounding_skeleton.global_transform * _grounding_skeleton.get_bone_global_pose(bone_idx).origin
		lowest_local_y = minf(lowest_local_y, to_local(bone_world_position).y)
	if lowest_local_y == INF:
		return

	var target_y: float = _model.position.y - lowest_local_y + model_ground_offset
	var smoothing: float = 1.0 - exp(-foot_grounding_smoothing_speed * delta)
	_model.position.y = lerpf(_model.position.y, target_y, smoothing)

func _build_flat_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = wanderer_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material

# The clips ship as separate Mixamo FBX files, each importing with a
# single clip whose name Godot's FBX importer assigns (not "mixamo.com" -
# don't assume a specific name). This finds each player's one clip by key
# count, not by name (_find_single_animation()), and merges them into the
# model's own AnimationPlayer library under the names _merged_clips()
# gives them - this is the real model, not a stand-in; the merge exists
# because of how the clips ship as separate files, not because anything
# here is temporary.
#
# The model's own clip is renamed to BattleIdle: the first of
# BATTLE_IDLE_CLIPS the glb carries - battle_idle_breathe, his breathing in
# the stance, or the held battle_idle if that's missing - else its clip
# with the most keys. Where it plays, see enter_battle_stance()/exit_
# battle_stance(). It loops, Loop Mode Linear, set here whatever the
# import says, so it runs for the whole battle frame. The glb's slash, if
# it has one, is renamed to Slash and plays once (_on_card_played()), and
# its draw_sword to DrawSword, once (enter_battle_stance()). Every clip
# after them is carried onto the model's skeleton by _transfer_clip() -
# all but those the glb already gave: its Slash and DrawSword leave the
# Mixamo ones unloaded.
func _merge_clips(anim_player: AnimationPlayer) -> void:
	if anim_player == null:
		push_error("Wanderer: model has no AnimationPlayer; cannot merge clips.")
		return

	var battle_idle_entry := _find_named_animation(anim_player, BATTLE_IDLE_CLIPS)
	if battle_idle_entry.is_empty():
		battle_idle_entry = _find_single_animation(anim_player, "model AnimationPlayer")
	if battle_idle_entry.is_empty():
		return
	var library := anim_player.get_animation_library(battle_idle_entry["library"])
	(battle_idle_entry["animation"] as Animation).loop_mode = Animation.LOOP_LINEAR
	library.rename_animation(battle_idle_entry["name"], "BattleIdle")
	var slash_entry := _find_named_animation(anim_player, [SLASH_CLIP])
	_own_slash = not slash_entry.is_empty()
	if _own_slash:
		(slash_entry["animation"] as Animation).loop_mode = Animation.LOOP_NONE
		anim_player.get_animation_library(slash_entry["library"]).rename_animation(slash_entry["name"], "Slash")
	var anim_root := anim_player.get_node_or_null(anim_player.root_node)
	var draw_entry := _find_named_animation(anim_player, [DRAW_SWORD_CLIP])
	_own_draw_sword = not draw_entry.is_empty() and anim_root != null
	if _own_draw_sword:
		# The grab is a method key on the clip itself, so it lands on the
		# clip's own frame - the playhead crossing it, not a timer beside
		# it. A copy carries it: the imported clip may be shared with other
		# instances of the model.
		var draw := (draw_entry["animation"] as Animation).duplicate() as Animation
		draw.loop_mode = Animation.LOOP_NONE
		_grab_key_path = anim_root.get_path_to(self)
		var track := draw.add_track(Animation.TYPE_METHOD)
		draw.track_set_path(track, _grab_key_path)
		_insert_draw_keys(draw, track)
		var draw_library := anim_player.get_animation_library(draw_entry["library"])
		draw_library.remove_animation(draw_entry["name"])
		draw_library.add_animation("DrawSword", draw)
	var skeletons: Array[Node] = _model.find_children("*", "Skeleton3D", true, false) if _model != null else []
	var target_skeleton := skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	# A clip that fails is reported and the rest still merge - one broken
	# file costs its own clip, not every clip after it.
	for clip: Dictionary in _merged_clips():
		if anim_player.has_animation(String(clip["name"])):
			continue
		if not _merge_clip(library, anim_root, target_skeleton, clip):
			push_error("Wanderer: the %s clip (%s) failed to merge; merging the rest." % [clip["name"], clip["path"]])

# The clips merged after the model's own, in order: name in the library,
# source file, loop mode and a label for errors.
# - Idle: FBX imports default to LOOP_NONE - play() would run it once and
#   hold on the last frame, which reads as "idle froze" the moment the
#   clip's own (short) duration elapses - so it loops, whether playing
#   standalone or re-triggered by exit_battle_stance()'s play("Idle").
# - Walk, Run: loops; Run plays during a dash in place of Walk/Idle (see
#   _physics_process()). Both are cut in place - the Hips never move - so
#   there is no root motion to take out.
# - DrawSword: a one-shot combat-start transition, LOOP_NONE explicitly
#   (rather than trusting whatever the import defaulted to) - enter_battle_
#   stance() relies on it finishing so the queued BattleIdle can start.
#   Only merged when the glb has no draw_sword of its own (_merge_clips()).
# - Slash: a one-shot attack swing, triggered by CardData.battle_animation
#   (see _on_card_played()), not anything here. Only merged when the glb
#   has no slash of its own (_merge_clips()). Its hips step in and back
#   in the clip itself.
# - Brace: a one-shot like Slash: the Brace card plays it once (CardData.
#   battle_animation) and the Wanderer returns to rest. It used to loop as
#   a held pose while Braced sat on the player; Braced is on the enemy now,
#   so there's nothing on him to hold it for.
func _merged_clips() -> Array[Dictionary]:
	return [
		{"name": "Idle", "path": IDLE_SCENE_PATH, "loop": Animation.LOOP_LINEAR, "label": "idle"},
		{"name": "Walk", "path": WALK_SCENE_PATH, "loop": Animation.LOOP_LINEAR, "label": "walking"},
		{"name": "Run", "path": RUN_SCENE_PATH, "loop": Animation.LOOP_LINEAR, "label": "running"},
		{"name": "DrawSword", "path": DRAW_SWORD_SCENE_PATH, "loop": Animation.LOOP_NONE, "label": "draw-sword"},
		{"name": "Slash", "path": SLASH_SCENE_PATH, "loop": Animation.LOOP_NONE, "label": "slash"},
		{"name": "Brace", "path": BRACE_SCENE_PATH, "loop": Animation.LOOP_NONE, "label": "brace"},
	]

# Loads one clip file, finds its one real clip, carries it onto the
# model's skeleton (_transfer_clip()), sets its loop mode and adds it to
# library under clip["name"] - then checks the merged clip's first track
# resolves to a Skeleton3D under anim_root. False (with a push_error) when
# any step fails; _merge_clips() reports it and goes on to the next clip.
func _merge_clip(library: AnimationLibrary, anim_root: Node, target_skeleton: Skeleton3D, clip: Dictionary) -> bool:
	var clip_name: String = clip["name"]
	var label: String = clip["label"]
	var scene := load(String(clip["path"])) as PackedScene
	var instance := scene.instantiate()
	var players := instance.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		push_error("Wanderer: %s model has no AnimationPlayer; %s clip not merged." % [label, clip_name])
		instance.free()
		return false

	var entry := _find_single_animation(players[0] as AnimationPlayer, "%s AnimationPlayer" % label)
	if entry.is_empty():
		instance.free()
		return false

	var source_animation: Animation = entry["animation"]
	var source_skeletons := instance.find_children("*", "Skeleton3D", true, false)
	var source_skeleton := source_skeletons[0] as Skeleton3D if not source_skeletons.is_empty() else null
	var animation: Animation = _transfer_clip(source_animation, instance, source_skeleton, anim_root, target_skeleton)
	var loop_mode: Animation.LoopMode = clip["loop"]
	animation.loop_mode = loop_mode
	library.add_animation(clip_name, animation)
	instance.free()

	if animation.get_track_count() == 0:
		push_error("Wanderer: merged %s animation has no tracks; clip merge is broken." % clip_name)
		return false

	var track_node_path := NodePath(animation.track_get_path(0).get_concatenated_names())
	var resolved := anim_root.get_node_or_null(track_node_path) if anim_root else null
	if not (resolved is Skeleton3D):
		push_error("Wanderer: %s animation's first track path '%s' does not resolve to a Skeleton3D on the model; clip merge is broken." % [clip_name, str(track_node_path)])
		return false
	return true

# Carries a clip cut on one rig (source_skeleton, under source_root) onto
# the model's skeleton (target_skeleton, under target_root - the
# AnimationPlayer's root), by bone name (_target_bone()):
# - only rotation tracks on bones both rigs share, and the root bone's
#   position track, are kept. Every other track is dropped: one on a
#   node that isn't a shared bone (a Meshy FBX's own root node,
#   target_character, and its *_end leaf bones, which v3 hasn't got),
#   every scale track, and every other bone's position track - those
#   bones keep the target rig's rest positions, so limbs keep its own
#   lengths. The Meshy clips import with remove_immutable_tracks off
#   (their thumbs hold one fixed pose, which the importer would drop),
#   so they carry all of these;
# - every kept track is re-pointed at target_skeleton's path;
# - the root bone's rotation and position keys are carried from the
#   source skeleton's frame into the target's through the nodes above
#   each (an Armature's scale and turn included), so the hips stand and
#   face in model space as they did; its position keys are also scaled
#   by the rigs' rest leg lengths (_root_position_scale()), for rigs
#   whose bones are in different units - the Mixamo FBX clips key the
#   hips ~0.01 high, wanderer_v3.glb's bones are in metres;
# - every other bone's rotation keys stay as they are. A Mixamo clip holds
#   each bone's pose as its absolute local rotation, not as a bend from
#   rest: the running, slash and brace files carry arm rests up to 26 deg
#   off the idle rig's and have always played as-is on it. Turning keys by
#   the rest difference would add that difference to the motion.
# A clip whose skeleton path and frame are the same on both rigs comes
# back as the same Animation, unchanged and unfiltered.
# Otherwise the clip is a copy: the source is the import's own cached
# resource, which a second Wanderer would carry over again.
func _transfer_clip(animation: Animation, source_root: Node, source_skeleton: Skeleton3D, target_root: Node, target_skeleton: Skeleton3D) -> Animation:
	if source_skeleton == null or target_skeleton == null or target_root == null:
		return animation
	var source_frame: Transform3D = _transform_under(source_skeleton, source_root)
	var target_frame: Transform3D = _transform_under(target_skeleton, target_root)
	var source_path := String(source_root.get_path_to(source_skeleton))
	var target_path := String(target_root.get_path_to(target_skeleton))
	var frame_shift: Transform3D = target_frame.affine_inverse() * source_frame
	var root_scale := _root_position_scale(source_skeleton, target_skeleton, frame_shift)
	if source_frame.is_equal_approx(target_frame) and source_path == target_path and is_equal_approx(root_scale, 1.0):
		return animation

	var copy := animation.duplicate(true) as Animation
	var frame_turn: Quaternion = target_frame.basis.orthonormalized().get_rotation_quaternion().inverse() * source_frame.basis.orthonormalized().get_rotation_quaternion()
	for track_idx in range(copy.get_track_count() - 1, -1, -1):
		var bone := _track_bone(copy, track_idx, source_root, source_skeleton)
		var target_bone := _target_bone(target_skeleton, bone) if bone != "" else -1
		var track_type := copy.track_get_type(track_idx)
		var is_root: bool = target_bone != -1 and target_skeleton.get_bone_parent(target_bone) == -1
		if target_bone == -1 or track_type == Animation.TYPE_SCALE_3D or (track_type == Animation.TYPE_POSITION_3D and not is_root):
			copy.remove_track(track_idx)
			continue
		copy.track_set_path(track_idx, NodePath("%s:%s" % [target_path, target_skeleton.get_bone_name(target_bone)]))
		match track_type:
			Animation.TYPE_ROTATION_3D:
				if not is_root:
					continue
				for key_idx in copy.track_get_key_count(track_idx):
					var key: Quaternion = copy.track_get_key_value(track_idx, key_idx)
					copy.track_set_key_value(track_idx, key_idx, (frame_turn * key).normalized())
			Animation.TYPE_POSITION_3D:
				for key_idx in copy.track_get_key_count(track_idx):
					var key: Vector3 = copy.track_get_key_value(track_idx, key_idx)
					copy.track_set_key_value(track_idx, key_idx, (frame_shift * key) * root_scale)
	return copy

# How much a root position key grows from the source rig to the target,
# beyond what frame_shift (the nodes above each skeleton) already does:
# the target's rest leg (root bone to LeftFoot) over the source's, carried
# into the target's frame. 1.0 when either rig has no LeftFoot.
func _root_position_scale(source_skeleton: Skeleton3D, target_skeleton: Skeleton3D, frame_shift: Transform3D) -> float:
	var source_foot := _find_bone_by_suffix(source_skeleton, &"LeftFoot")
	var target_foot := _find_bone_by_suffix(target_skeleton, &"LeftFoot")
	if source_foot == -1 or target_foot == -1:
		return 1.0
	var source_root: int = source_skeleton.get_parentless_bones()[0]
	var target_root: int = target_skeleton.get_parentless_bones()[0]
	var source_leg: Vector3 = frame_shift.basis * (source_skeleton.get_bone_global_rest(source_foot).origin - source_skeleton.get_bone_global_rest(source_root).origin)
	var target_leg: Vector3 = target_skeleton.get_bone_global_rest(target_foot).origin - target_skeleton.get_bone_global_rest(target_root).origin
	if source_leg.length() < 0.000001:
		return 1.0
	return target_leg.length() / source_leg.length()

# source_bone's match on target_skeleton: the same name, else the bone
# with the same name after the rig's prefix - a Mixamo clip's
# mixamorig_LeftToe_End is smartrig_LeftToe_End on a Meshy rig. -1 when
# neither is there.
func _target_bone(target_skeleton: Skeleton3D, source_bone: String) -> int:
	var bone_idx := target_skeleton.find_bone(source_bone)
	var prefix_end := source_bone.find("_")
	if bone_idx == -1 and prefix_end != -1:
		bone_idx = _find_bone_by_suffix(target_skeleton, StringName(source_bone.substr(prefix_end)))
	return bone_idx

# The bone a skeleton track of animation names, when its node path is
# source_skeleton under source_root; "" for any other track.
func _track_bone(animation: Animation, track_idx: int, source_root: Node, source_skeleton: Skeleton3D) -> String:
	var path := animation.track_get_path(track_idx)
	if path.get_subname_count() == 0:
		return ""
	if source_root.get_node_or_null(NodePath(path.get_concatenated_names())) != source_skeleton:
		return ""
	return String(path.get_subname(path.get_subname_count() - 1))

# node's transform in ancestor's space: the product of the local
# transforms from node up to (not including) ancestor. Works on a tree
# that isn't in the scene tree yet (a clip file's instance).
func _transform_under(node: Node, ancestor: Node) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != ancestor:
		var current_3d := current as Node3D
		if current_3d != null:
			chain = current_3d.transform * chain
		current = current.get_parent()
	return chain

# Returns {"library": StringName, "name": StringName, "animation": Animation}
# for the animation with the most total keyframes (summed across its
# tracks) across anim_player's libraries. FBX import produces an empty
# "Take 001" default alongside the real clip; "Take 001" can have more
# tracks than the real clip while each track holds only a single static
# key, so track count alone picks the wrong one — total key count is what
# actually finds the real clip. Ties prefer whichever candidate isn't
# named "Take 001". If the best candidate has zero keys, push_errors that
# plus every library/animation name actually found (so the real imported
# naming is visible) and returns an empty Dictionary.
# The first of `names` the player carries, in any library: {library, name,
# animation}, or {} if it has none of them.
func _find_named_animation(anim_player: AnimationPlayer, names: Array[StringName]) -> Dictionary:
	for wanted in names:
		for library_name in anim_player.get_animation_library_list():
			var library := anim_player.get_animation_library(library_name)
			if library.has_animation(wanted):
				return {"library": library_name, "name": wanted, "animation": library.get_animation(wanted)}
	return {}

func _find_single_animation(anim_player: AnimationPlayer, label: String) -> Dictionary:
	var found: Array[Dictionary] = []
	for library_name in anim_player.get_animation_library_list():
		var library := anim_player.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			var animation := library.get_animation(animation_name)
			var key_count := 0
			for track_idx in animation.get_track_count():
				key_count += animation.track_get_key_count(track_idx)
			found.append({"library": library_name, "name": animation_name, "animation": animation, "key_count": key_count})

	if found.is_empty():
		push_error("Wanderer: found no animations on %s. %s" % [label, _describe_animations(anim_player)])
		return {}

	var best: Dictionary = found[0]
	for entry in found:
		var entry_key_count: int = entry["key_count"]
		var best_key_count: int = best["key_count"]
		if entry_key_count > best_key_count:
			best = entry
		elif entry_key_count == best_key_count and str(best["name"]) == "Take 001" and str(entry["name"]) != "Take 001":
			best = entry

	if best["key_count"] == 0:
		push_error("Wanderer: no animation with keyframes found on %s. %s" % [label, _describe_animations(anim_player)])
		return {}

	return best

func _describe_animations(anim_player: AnimationPlayer) -> String:
	var libraries := anim_player.get_animation_library_list()
	if libraries.is_empty():
		return "No animation libraries found."
	var parts: Array[String] = []
	for library_name in libraries:
		var library := anim_player.get_animation_library(library_name)
		var display_name := "<default>" if library_name == "" else str(library_name)
		parts.append("%s: %s" % [display_name, str(library.get_animation_list())])
	return "Libraries found - " + "; ".join(parts)

func _build_animation_tree() -> void:
	if _animation_player == null:
		return

	# Run is deliberately not a blend point here: it's a discrete state
	# tied to is_dashing (see _physics_process()'s AnimationPlayer branch),
	# not a continuous function of speed the way Idle<->Walk is, and dash
	# speed itself runs well past move_speed (this blend space's own
	# max_space). Wiring it in properly would need an
	# AnimationNodeStateMachine transition, not another blend point - out
	# of scope while use_animation_tree defaults to false and isn't the
	# path any current scene actually enables.
	var blend_space := AnimationNodeBlendSpace1D.new()
	blend_space.min_space = 0.0
	blend_space.max_space = move_speed

	var idle_node := AnimationNodeAnimation.new()
	idle_node.animation = "Idle"
	blend_space.add_blend_point(idle_node, 0.0, -1, "Idle")

	var walk_node := AnimationNodeAnimation.new()
	walk_node.animation = "Walk"
	blend_space.add_blend_point(walk_node, move_speed, -1, "Walk")

	_animation_tree = AnimationTree.new()
	_animation_tree.tree_root = blend_space
	add_child(_animation_tree)
	# When use_animation_tree is on, the AnimationTree - not the
	# AnimationPlayer - is the mixer actually blending and applying poses
	# each frame (the AnimationPlayer above just supplies the Idle/Walk
	# clips via anim_player below). Without this, _animation_player's own
	# PROCESS_MODE_ALWAYS is inert here: the tree itself would still
	# inherit RegionField's freeze and stop blending during battle.
	_animation_tree.process_mode = Node.PROCESS_MODE_ALWAYS
	_animation_tree.anim_player = _animation_tree.get_path_to(_animation_player)

	# AnimationTree.root_node defaults to "..", i.e. Wanderer — but the
	# animation tracks (e.g. "Skeleton3D:mixamorig_Hips") are relative to
	# the instanced model, not Wanderer, so they'd never resolve there.
	# Point root_node at the same node the AnimationPlayer's own root_node
	# resolves to.
	var anim_root := _animation_player.get_node(_animation_player.root_node)
	_animation_tree.root_node = _animation_tree.get_path_to(anim_root)

	_animation_tree.active = true

# Projects a direction onto the ground plane (zeroes Y) and normalizes it,
# returning ZERO instead of dividing by ~zero for a near-vertical input.
func _flatten_normalized(vector: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	return flat.normalized() if flat.length() > 0.0001 else Vector3.ZERO

# Node3D's actual forward vector at rotation.y=angle is (-sin angle, 0,
# -cos angle) — engine-verified; (sin angle, 0, -cos angle) is the wrong
# sign on X and silently mismatches turn-to-face against velocity on any
# lateral component. This and _angle_from_direction() are exact inverses
# and are the ONLY place either conversion happens.
func _forward_from_angle(angle: float) -> Vector3:
	return Vector3(-sin(angle), 0.0, -cos(angle))

func _angle_from_direction(direction: Vector3) -> float:
	return atan2(-direction.x, -direction.z)

# --- Point to move (see the Point To Move exports) ---

func set_move_target(point: Vector3) -> void:
	_move_target = point
	_move_target_enemy = null
	_has_move_target = true
	_stuck_timer = 0.0
	_path = PackedVector3Array()

# A planned walk: `points` from where he stands to the target, in order
# (RegionField.plan_path()). `keep_enemy`: an enemy target set just before
# (set_move_target_enemy()) stays the target once the path is walked.
func set_move_path(points: PackedVector3Array, keep_enemy: bool = false) -> void:
	if points.is_empty():
		clear_move_target()
		return
	if not keep_enemy:
		_move_target_enemy = null
	_path = points
	# The first point is where he stood when it was planned.
	_path_index = 1 if points.size() > 1 else 0
	_move_target = points[points.size() - 1]
	_has_move_target = true
	_stuck_timer = 0.0

# The planned walk's remaining waypoints - for the debug draw.
func get_move_path() -> PackedVector3Array:
	if not _has_move_target or _path.is_empty():
		return PackedVector3Array()
	return _path.slice(_path_index)

# The planned walk's final point, or Vector3.INF with none.
func get_move_goal() -> Vector3:
	return _move_target if _has_move_target else Vector3.INF

func get_move_target_enemy() -> FieldEnemy:
	return _move_target_enemy if _has_move_target else null

# Walks at the enemy's live position until its own contact area starts
# the fight.
func set_move_target_enemy(enemy: FieldEnemy) -> void:
	_move_target_enemy = enemy
	_move_target = enemy.global_position
	_has_move_target = true
	_stuck_timer = 0.0
	_path = PackedVector3Array()

func clear_move_target() -> void:
	_has_move_target = false
	_move_target_enemy = null
	_stuck_timer = 0.0
	_path = PackedVector3Array()

func has_move_target() -> bool:
	return _has_move_target

# Stopped where he stands, in his idle - before a freeze that should show
# him standing (a rest: BedrollRest). His model plays through the freeze,
# so a walk left playing would walk on the spot.
func stand_still() -> void:
	clear_move_target()
	velocity = Vector3.ZERO
	if use_animation_tree:
		if _animation_tree:
			_animation_tree.set("parameters/blend_position", 0.0)
	elif _animation_player != null and _animation_player.has_animation(&"Idle") and _animation_player.current_animation != "Idle":
		_animation_player.play("Idle", animation_blend_time)

# See the Hold Line export group. `point` is any point on the line,
# `normal` the direction (XZ, normalized here) he may not move past it
# along - the floor's exit direction.
func set_hold_line(point: Vector3, normal: Vector3) -> void:
	_hold_line_point = point
	_hold_line_normal = Vector3(normal.x, 0.0, normal.z).normalized()
	_hold_line_active = _hold_line_normal.length() > 0.0001
	_hold_line_armed = true

func clear_hold_line() -> void:
	_hold_line_active = false
	_look_back_active = false

func has_hold_line() -> bool:
	return _hold_line_active

# See the Wade Limit export group. `metres` below 0, or no ground: none.
func set_wade_limit(ground: Ground, metres: float) -> void:
	_wade_ground = ground
	_wade_limit_m = metres

func has_wade_limit() -> bool:
	return _wade_ground != null and is_instance_valid(_wade_ground) and _wade_limit_m >= 0.0

func _wade_distance(at: Vector3) -> float:
	return _wade_ground.get_landmass_distance(Vector2(at.x, at.z))

# The slope of the shoreline distance at `at` (XZ): the way further out,
# about a metre a metre - ZERO where it is flat (between two shores).
func _wade_slope(at: Vector3) -> Vector3:
	var h: float = maxf(wade_limit_probe_m, 0.01)
	var across := Vector3(h, 0.0, 0.0)
	var along := Vector3(0.0, 0.0, h)
	return Vector3(_wade_distance(at + across) - _wade_distance(at - across), 0.0, _wade_distance(at + along) - _wade_distance(at - along)) / (2.0 * h)

# Before move_and_slide(), with the hold line's: his velocity further out
# capped as the hold line caps it (sqrt(2 a d), d the room left to the
# limit), so he eases to rest on it - along the shore is untouched.
func _limit_velocity_at_wade_limit() -> void:
	if not has_wade_limit() or _battle_controller != null:
		return
	_wade_start_distance = _wade_distance(global_position)
	var room: float = _wade_limit_m - _wade_start_distance
	if room > wade_limit_ease_distance + 1.0:
		return
	var slope: Vector3 = _wade_slope(global_position)
	if slope.length() < 0.0001:
		return
	var out_dir: Vector3 = slope.normalized()
	var out: float = velocity.x * out_dir.x + velocity.z * out_dir.z
	if out <= 0.0:
		return
	var deceleration: float = move_speed * move_speed / (2.0 * maxf(wade_limit_ease_distance, 0.01))
	var allowed: float = sqrt(2.0 * deceleration * maxf(room, 0.0))
	if out > allowed:
		velocity.x -= out_dir.x * (out - allowed)
		velocity.z -= out_dir.z * (out - allowed)

# After move_and_slide(), with the hold line's: a step that still took him
# past the limit - or further out than he began, when he began past it -
# is put back along the slope.
func _hold_at_wade_limit() -> void:
	if not has_wade_limit() or _battle_controller != null:
		return
	var cap: float = maxf(_wade_limit_m, _wade_start_distance)
	var distance: float = _wade_distance(global_position)
	if distance <= cap:
		return
	var slope: Vector3 = _wade_slope(global_position)
	var steepness: float = slope.length()
	if steepness < 0.0001:
		return
	var back: Vector3 = slope / steepness * ((distance - cap) / steepness)
	global_position.x -= back.x
	global_position.z -= back.z

# Turn to face `point` while he stands at the hold line (hold_line_turn_
# speed) - kept until he walks off the line or it lifts. Walking along
# the line faces the way he walks, as always; coming to rest there again
# turns him back.
func look_back_toward(point: Vector3) -> void:
	var to_point := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to_point.length() < 0.0001:
		return
	_look_back_direction = to_point.normalized()
	_look_back_active = true

# Metres left before the hold line along its normal - negative past it.
func _hold_line_distance() -> float:
	return (_hold_line_point - global_position).dot(_hold_line_normal)

# Before move_and_slide(): his velocity into the line is capped at what a
# constant deceleration from move_speed over hold_line_ease_distance would
# still allow this far out (sqrt(2 a d)), so he eases to rest on it -
# along the line is untouched.
func _limit_velocity_at_hold_line() -> void:
	if not _hold_line_active or _battle_controller != null:
		return
	var into: float = velocity.x * _hold_line_normal.x + velocity.z * _hold_line_normal.z
	if into <= 0.0:
		return
	var deceleration: float = move_speed * move_speed / (2.0 * maxf(hold_line_ease_distance, 0.01))
	var allowed: float = sqrt(2.0 * deceleration * maxf(_hold_line_distance(), 0.0))
	if into > allowed:
		velocity.x -= _hold_line_normal.x * (into - allowed)
		velocity.z -= _hold_line_normal.z * (into - allowed)

# After move_and_slide(): a frame's step that still overshot is put back
# onto the line. Then the arrival (at rest, within the margin) and the
# re-arm once he is well back off it.
func _hold_at_line(planar_speed: float) -> void:
	if not _hold_line_active or _battle_controller != null:
		return
	var distance: float = _hold_line_distance()
	if distance < 0.0:
		global_position.x += _hold_line_normal.x * distance
		global_position.z += _hold_line_normal.z * distance
		distance = 0.0
	if distance > hold_line_rearm_distance:
		_hold_line_armed = true
		_look_back_active = false
	elif _hold_line_armed and distance <= hold_line_arrive_margin and planar_speed < walk_speed_threshold:
		_hold_line_armed = false
		hold_line_reached.emit()

# This frame's walking direction toward the target, or ZERO once it's
# reached (which also clears it) or its enemy is gone.
func _move_target_direction() -> Vector3:
	if not _has_move_target:
		return Vector3.ZERO
	if _move_target_enemy != null and not is_instance_valid(_move_target_enemy):
		clear_move_target()
		return Vector3.ZERO
	# The planned walk: on to each waypoint in turn, then the last one -
	# or, chasing an enemy, the enemy itself once they are all walked.
	while not _path.is_empty() and _path_index < _path.size() - 1:
		var waypoint: Vector3 = _path[_path_index]
		var to_waypoint := Vector3(waypoint.x - global_position.x, 0.0, waypoint.z - global_position.z)
		if to_waypoint.length() > waypoint_radius:
			return to_waypoint.normalized()
		_path_index += 1
	if _move_target_enemy != null and (_path.is_empty() or _path_index >= _path.size() - 1):
		_move_target = _move_target_enemy.global_position
	var to_target := Vector3(_move_target.x - global_position.x, 0.0, _move_target.z - global_position.z)
	if to_target.length() <= arrive_radius:
		clear_move_target()
		return Vector3.ZERO
	return to_target.normalized()

# Standing still against something with the target still ahead: after
# stuck_time of it, give up rather than push forever.
func _tick_stuck(delta: float, planar_speed: float) -> void:
	if not _has_move_target:
		return
	if planar_speed < walk_speed_threshold:
		_stuck_timer += delta
		if _stuck_timer >= stuck_time:
			var planned: bool = not _path.is_empty()
			if planned:
				# RegionField plans again from here (and gives up after a few).
				_stuck_timer = 0.0
				path_stuck.emit()
			else:
				clear_move_target()
	else:
		_stuck_timer = 0.0

# Public read of dash state - used by FootprintSpawner to pick a shorter
# per-foot cooldown while dashing (Run's own foot-plant cadence is faster
# than Walk's), without exposing _dash_timer itself.
func is_dashing() -> bool:
	return _dash_timer > 0.0

# Length of a merged clip, in seconds - CardData.impact_time's own clamp
# (see BattleController._impact_delay_for()) against a clip shorter than
# the authored value. 0.0 (not found/no player yet) means "don't clamp,
# use impact_time as authored" to that caller, not "instant".
func get_clip_length(anim_name: StringName) -> float:
	if _animation_player == null or not _animation_player.has_animation(anim_name):
		return 0.0
	return _animation_player.get_animation(anim_name).length

# When a merged clip's blow lands, in seconds into it, for BattleController.
# _impact_delay_for(): slash_contact_time for the glb's own Slash (held to
# its length), -1.0 for any other clip - the card's impact_time decides.
func get_clip_contact_time(anim_name: StringName) -> float:
	if anim_name != &"Slash" or not _own_slash:
		return -1.0
	return clampf(slash_contact_time, 0.0, get_clip_length(anim_name))

# Whether the swing playing now is short of its cancel point: Battle
# Controller holds a next play until it isn't (see the Slash group). Only
# the glb's own Slash has one; any other clip holds nothing.
func holds_next_play() -> bool:
	if not _own_slash or _swing_clip != &"Slash" or not _swinging():
		return false
	return _animation_player.current_animation_position < clampf(slash_cancel_time, 0.0, get_clip_length(&"Slash"))

# Whether a card's one-shot clip (_swing_clip) is still the one playing -
# held by a hit-stop included.
func _swinging() -> bool:
	return _swing_clip != &"" and _animation_player != null and _animation_player.is_playing() and _animation_player.current_animation == String(_swing_clip)

# A hit-stop on him (a contact he gives or takes - BattleFeedback): his
# clip stops where it is for `seconds` of game time, and his Slash lunge
# and recoil with it (a recoil started during the stop waits for its
# end), then all of it plays on. A stop only ever extends the one
# running. Timed by a SceneTreeTimer, so under the probes' fixed frame
# rate it lasts the same frames every run.
func hold_animation(seconds: float) -> void:
	if _animation_player == null or seconds <= 0.0:
		return
	if _anim_hold_timer != null and _anim_hold_timer.time_left >= seconds:
		return
	if _anim_hold_timer == null:
		_anim_held_speed = _animation_player.speed_scale
		_animation_player.speed_scale = 0.0
		for tween: Tween in [_lunge_tween, _recoil_tween]:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_anim_held_tweens.append(tween)
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	_anim_hold_timer = timer
	timer.timeout.connect(_end_animation_hold.bind(timer))

# Whether a hit-stop holds him now (hold_animation()).
func is_animation_held() -> bool:
	return _anim_hold_timer != null

func _end_animation_hold(timer: SceneTreeTimer) -> void:
	if timer != _anim_hold_timer:
		return
	_anim_hold_timer = null
	if _animation_player != null:
		_animation_player.speed_scale = _anim_held_speed
	for tween in _anim_held_tweens:
		if tween.is_valid():
			tween.play()
	_anim_held_tweens.clear()

# Called by BattleFeedback once BattleController reports a card hit
# landing on the player. _active_material may be the flat fallback's
# StandardMaterial3D (FLAT, or a failed load) or a ShaderMaterial
# (TEXTURED's wanderer_painted, POSTERIZED's wanderer_flat, both with
# flash_amount/flash_color) - each needs a different property tweened to
# read as the same "lerp to near-white bone, then back" flash, so this
# only dispatches; the two
# _tween_*_flash() helpers below do the actual work.
func play_hit_flash(flash_color: Color, rise_time: float, fall_time: float) -> void:
	if _active_material is StandardMaterial3D:
		_tween_standard_flash(_active_material as StandardMaterial3D, flash_color, rise_time, fall_time)
	elif _active_material is ShaderMaterial:
		_tween_shader_flash(_active_material as ShaderMaterial, flash_color, rise_time, fall_time)

func _tween_standard_flash(material: StandardMaterial3D, flash_color: Color, rise_time: float, fall_time: float) -> void:
	var base_color: Color = material.albedo_color
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(material, "albedo_color", flash_color, rise_time)
	tween.tween_property(material, "albedo_color", base_color, fall_time)

# wanderer_flat.gdshader has no single "albedo" property to lerp (its own
# ALBEDO is computed from a posterized ramp, not read back from a
# uniform) - flash_amount/flash_color are a separate pair of uniforms
# added to that shader purely for this, blended in on top of the ramp in
# its own fragment().
func _tween_shader_flash(material: ShaderMaterial, flash_color: Color, rise_time: float, fall_time: float) -> void:
	material.set_shader_parameter("flash_color", flash_color)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("flash_amount", v), 0.0, 1.0, rise_time)
	tween.tween_method(func(v: float) -> void: material.set_shader_parameter("flash_amount", v), 1.0, 0.0, fall_time)

# from_direction is the direction the hit traveled (attacker -> the
# Wanderer, not normalized) - same mechanism as FieldEnemy.play_hit_
# recoil(), duplicated rather than shared (see that method's own doc on
# why - still only the second occurrence).
func play_hit_recoil(from_direction: Vector3, distance: float, tilt_degrees: float, out_time: float, return_time: float) -> void:
	var away := Vector3(from_direction.x, 0.0, from_direction.z)
	away = away.normalized() if away.length() > 0.0001 else Vector3.BACK

	var base_position := global_position
	var base_tilt := rotation.x
	var recoil_position := base_position + away * distance
	var recoil_tilt := base_tilt + deg_to_rad(tilt_degrees)

	var tween := create_tween()
	_recoil_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", recoil_position, out_time)
	tween.parallel().tween_property(self, "rotation:x", recoil_tilt, out_time)
	tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", base_position, return_time)
	tween.parallel().tween_property(self, "rotation:x", base_tilt, return_time)
	# Struck inside a hit-stop: the recoil waits for it to end.
	if _anim_hold_timer != null:
		tween.pause()
		_anim_held_tweens.append(tween)

# Same mechanism as FieldEnemy.spawn_sand_puff() (see its own doc),
# duplicated for the same reason play_hit_recoil() above is.
func spawn_sand_puff(particle_count: int, lifetime: float, velocity: float, spread_degrees: float, tint: float = 1.0) -> void:
	spawn_sand_puff_at(global_position, particle_count, lifetime, velocity, spread_degrees, 1.0, tint)

# The same puff at `at`, its quads size_scale their size (DrawSword's
# ground strike - BattleFeedback._on_draw_strike()); `tint` multiplies the
# ground colour the grains take (BattleFeedback.sand_puff_tint).
func spawn_sand_puff_at(at: Vector3, particle_count: int, lifetime: float, velocity: float, spread_degrees: float, size_scale: float = 1.0, tint: float = 1.0) -> void:
	if _ground == null:
		return

	var particles := GPUParticles3D.new()
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = false
	particles.one_shot = true
	particles.amount = particle_count
	particles.lifetime = lifetime
	particles.explosiveness = 1.0

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.12, 0.12) * size_scale

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sand: Color = _ground.ground_color
	material.albedo_color = Color(sand.r * tint, sand.g * tint, sand.b * tint, sand.a)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mesh.material = material
	particles.draw_pass_1 = quad_mesh

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = spread_degrees
	process_material.initial_velocity_min = velocity * 0.5
	process_material.initial_velocity_max = velocity
	process_material.gravity = Vector3(0.0, -2.0, 0.0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.2
	particles.process_material = process_material

	add_child(particles)
	particles.global_position = at
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(particles.queue_free)

func play_swing_audio(pitch_multiplier: float = 1.0) -> void:
	if _attack_audio != null:
		_attack_audio.play_swing(pitch_multiplier)

# An enemy's hit landing on him - called by BattleFeedback._react_to_
# enemy_attack() with the flash and recoil (see HitAudio for what that
# does and doesn't cover).
func play_hit_audio() -> void:
	if _hit_audio != null:
		_hit_audio.play_hit()

# Called by region_field.gd on enemy contact. Tweens into a fixed spacing
# from target along the target->Wanderer ground line, facing target, and
# blends the AnimationPlayer into DrawSword, queuing BattleIdle to follow
# the instant DrawSword's own one-shot playback finishes (AnimationPlayer.
# queue() - not a signal/await, since play() already clears any pending
# queue on its own, which is exactly what makes exit_battle_stance()'s own
# play("Idle") safe to call even mid-DrawSword) — independent of
# _physics_process (and its own dash/move-input handling), which
# RegionField's contact freeze has already stopped by the time this runs.
# The glb's own DrawSword is a swing (_swing_clip) while it plays, so a
# status change queues the resting clip behind it rather than cutting it
# off; it blends into BattleIdle, and the sword leaves his back on its
# grab frame (see the Draw Sword group). The Mixamo one moves the sword
# over the whole step.
#
# direction, when given, is the way from target to where this Wanderer
# should stand (a cluster's line extended past its near end - see
# RegionField._place_cluster_line()); ZERO (the default, a lone enemy)
# keeps the target->Wanderer ground line, wherever contact happened.
func enter_battle_stance(target: Node3D, spacing: float, duration: float, direction: Vector3 = Vector3.ZERO) -> void:
	if target == null:
		return
	# Contact is where a walk-to-enemy target ends; nothing resumes after.
	clear_move_target()

	var away_from_target := _flatten_normalized(direction)
	if away_from_target == Vector3.ZERO:
		away_from_target = _flatten_normalized(global_position - target.global_position)
	if away_from_target == Vector3.ZERO:
		away_from_target = _forward_from_angle(rotation.y)

	var stance_position := target.global_position + away_from_target * spacing

	# The surface as drawn - get_walk_height_at(), what the ground hold
	# compares his feet against (_hold_above_visible_ground()) - so he
	# stands on a dune's rise rather than inside it. It takes Ground's own
	# local frame - to_local() converts explicitly rather than assuming
	# Ground sits at the world origin (true today, but not guaranteed).
	# stance_position.x/z here are global (built from target.global_
	# position above, itself always global regardless of parenting), which
	# is what "sampling must use global XZ" requires; to_local() is what
	# turns that into the frame get_walk_height_at() needs.
	var ground := get_node_or_null(ground_path) as Ground
	var ground_resolved := ground != null
	var terrain_height: float = global_position.y
	if ground_resolved:
		var local_xz: Vector3 = ground.to_local(Vector3(stance_position.x, 0.0, stance_position.z))
		terrain_height = ground.get_walk_height_at(Vector2(local_xz.x, local_xz.z))

	# The body origin on the sand, as in the field - model_ground_offset
	# lifts the model alone (see its own doc), so nothing is taken off here.
	stance_position.y = terrain_height

	var face_angle := _angle_from_direction(-away_from_target)
	# Shift face_angle to the equivalent value nearest rotation.y so the
	# linear rotation:y tween below takes the short way around, matching
	# lerp_angle's turn-to-face behavior in _physics_process.
	var target_angle := rotation.y + wrapf(face_angle - rotation.y, -PI, PI)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", stance_position, duration)
	tween.tween_property(self, "rotation:y", target_angle, duration)
	_battle_turned = true
	if _model != null:
		tween.tween_property(_model, "rotation:y", _model_yaw(), duration)

	_end_grab_wait()
	if _animation_player:
		if _own_draw_sword:
			_place_draw_keys()
		_animation_player.play("DrawSword", draw_sword_blend_in)
		if _own_draw_sword:
			# After play(): DrawSword is the current clip before the wait
			# starts, so _on_draw_sword_cut() never reads the old one.
			_grab_pending = true
			_strike_pending = true
			_swing_clip = &"DrawSword"
			_animation_player.set_blend_time(&"DrawSword", &"BattleIdle", animation_blend_time)
		_animation_player.queue("BattleIdle")

	if not _own_draw_sword or _animation_player == null:
		_switch_sword_mount(_hand_frame, hand_mount_position, hand_mount_rotation_degrees, duration)

# A stance reached round something standing between him and it (Region
# Field._stance_path_round() - the Greyshelf's rock): walked along `path`
# (world points, his own spot first, the stance last) at move_speed, the
# walk playing and each leg faced, through the battle freeze as a tween -
# then settled into the stance as enter_battle_stance() does, over
# settle_duration, from where the walk ends. Returns the walk's seconds,
# which the caller adds to the fight's opening hold.
func enter_battle_stance_along(path: PackedVector3Array, target: Node3D, spacing: float, settle_duration: float, direction: Vector3 = Vector3.ZERO) -> float:
	if target == null:
		return 0.0
	clear_move_target()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	var seconds: float = 0.0
	var angle: float = rotation.y
	for i in range(1, path.size()):
		var leg: Vector3 = path[i] - path[i - 1]
		var flat := Vector3(leg.x, 0.0, leg.z)
		if flat.length() < 0.01:
			continue
		var leg_seconds: float = flat.length() / maxf(move_speed, 0.1)
		var face: float = _angle_from_direction(flat.normalized())
		angle = angle + wrapf(face - angle, -PI, PI)
		tween.tween_property(self, "global_position", path[i], leg_seconds)
		tween.parallel().tween_property(self, "rotation:y", angle, minf(leg_seconds, 0.2))
		seconds += leg_seconds
	if seconds <= 0.0:
		tween.kill()
		enter_battle_stance(target, spacing, settle_duration, direction)
		return 0.0
	_play_stance_walk(true)
	tween.tween_callback(func() -> void:
		_play_stance_walk(false)
		enter_battle_stance(target, spacing, settle_duration, direction))
	return seconds

# The walk on or off while enter_battle_stance_along() moves him -
# _physics_process, which plays it in the field, is frozen for the fight.
func _play_stance_walk(on: bool) -> void:
	if use_animation_tree:
		if _animation_tree:
			_animation_tree.set("parameters/blend_position", move_speed if on else 0.0)
	elif _animation_player and _animation_player.has_animation(&"Walk"):
		if on:
			_animation_player.play("Walk", animation_blend_time)

# In a fight, his body turned to face `point` over duration - an enemy
# that has moved (FieldEnemy.drop_off()). The model keeps its battle turn.
func turn_toward_in_battle(point: Vector3, duration: float) -> void:
	var to_point := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to_point.length() < 0.01:
		return
	var target_angle: float = rotation.y + wrapf(_angle_from_direction(to_point.normalized()) - rotation.y, -PI, PI)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_angle, maxf(duration, 0.01))

# Whether DrawSword is the glb's own draw_sword (not the Mixamo fallback) -
# RegionField times the fight's opening input hold by it.
func has_own_draw_sword() -> bool:
	return _own_draw_sword

# DrawSword's own length (seconds), 0 when there is none - the fight's
# opening hold's latest end (RegionField._battle_input_hold_seconds()).
func get_draw_sword_length() -> float:
	if _animation_player == null or not _animation_player.has_animation(&"DrawSword"):
		return 0.0
	return _animation_player.get_animation(&"DrawSword").length

# DrawSword's grab and strike keys, set to draw_sword_grab_time and
# draw_sword_strike_time as each entry reads them.
func _place_draw_keys() -> void:
	var draw := _animation_player.get_animation(&"DrawSword")
	var track := draw.find_track(_grab_key_path, Animation.TYPE_METHOD)
	if track < 0:
		return
	while draw.track_get_key_count(track) > 0:
		draw.track_remove_key(track, 0)
	_insert_draw_keys(draw, track)

# DrawSword's two method keys - the grab and the ground strike - at their
# times as they read now.
func _insert_draw_keys(draw: Animation, track: int) -> void:
	draw.track_insert_key(track, clampf(draw_sword_grab_time, 0.0, draw.length), {"method": GRAB_KEY_METHOD, "args": []})
	draw.track_insert_key(track, clampf(draw_sword_strike_time, 0.0, draw.length), {"method": STRIKE_KEY_METHOD, "args": []})

# DrawSword's grab key. It fires wherever the clip plays - blending in
# under the walk, or blending out after a fight ended - so it only acts
# for an entry still waiting on it; exit_battle_stance() ends the wait.
func _on_draw_sword_grab_key() -> void:
	if not _grab_pending:
		return
	_grab_pending = false
	_grab_sword()

# DrawSword stopped or replaced before its grab key, the entry still
# waiting (a card's clip inside the first frames of a fight): the grab
# happens now, so the fight never goes on with the sword on his back.
# Battle exit ends the wait first (exit_battle_stance()), so it doesn't.
func _on_draw_sword_cut() -> void:
	if _animation_player.current_animation == "DrawSword":
		return
	# Its strike won't come either: the draw it belongs to is over.
	var striking: bool = _strike_pending
	_strike_pending = false
	if striking:
		draw_strike_passed.emit()
	if _grab_pending:
		_grab_pending = false
		_grab_sword()

# DrawSword's ground-strike key: the puff (BattleFeedback, off draw_strike)
# and the sound on the drawn sand under the sword tip, once per entry.
func _on_draw_sword_strike_key() -> void:
	if not _strike_pending:
		return
	_strike_pending = false
	var tip: Vector3 = _sword_tip_world()
	var ground_point: Vector3 = tip
	if _ground != null:
		var local: Vector3 = _ground.to_local(tip)
		ground_point = _ground.to_global(Vector3(local.x, _ground.get_visible_height_at(Vector2(local.x, local.z)), local.z))
	draw_strike.emit(tip, ground_point)
	if _attack_audio != null:
		_attack_audio.play_ground_strike(ground_point)
	draw_strike_passed.emit()

# The sword's tip in the world: the end of its long axis _apply_grip_
# offset() takes for the tip.
func _sword_tip_world() -> Vector3:
	if _sword_mesh_holder == null:
		return global_position
	var axis := _longest_axis_index(_sword_raw_aabb.size)
	var tip_local: Vector3 = _sword_raw_aabb.position + _sword_raw_aabb.size * 0.5
	tip_local[axis] = _sword_raw_aabb.position[axis] if grip_axis_flip else _sword_raw_aabb.end[axis]
	return _sword_mesh_holder.global_transform * tip_local

# DrawSword's grab frame: the sword goes from his back into his hand as it
# stands, then turns onto the hand mount (see the Draw Sword group).
func _grab_sword() -> void:
	_grab_tween = null
	if _sword_root == null or _hand_frame == null or _model == null:
		return
	if _sword_root.get_parent() != _hand_frame:
		var held: Transform3D = _sword_root.global_transform
		if _sword_root.get_parent() != null:
			_sword_root.get_parent().remove_child(_sword_root)
		_hand_frame.add_child(_sword_root)
		_sword_root.global_transform = held
	_begin_handoff()
	if draw_sword_snap_time <= 0.0:
		_set_handoff(1.0)
		return
	_grab_tween = create_tween()
	_grab_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_grab_tween.tween_method(_set_handoff, 0.0, 1.0, draw_sword_snap_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# The handoff's ends, read with the sword just put in his hand: where it
# stands, and the same turned so its tip points draw_sword_sweep_direction
# (the least turn that does it).
func _begin_handoff() -> void:
	_handoff_from_position = _sword_root.position
	_handoff_from = _model_basis().inverse() * _sword_root.global_basis.orthonormalized().get_rotation_quaternion()
	var tip: Vector3 = _handoff_from * _sword_tip_axis()
	var sweep: Vector3 = draw_sword_sweep_direction.normalized()
	if sweep == Vector3.ZERO:
		sweep = tip
	_handoff_via = (Quaternion(tip, sweep) * _handoff_from).normalized()

# The handoff at `t` (0 at the grab, 1 on the hand mount): the grip goes
# straight to the mount's offset; the blade turns from where it stood to
# _handoff_via, then on to the hand mount where his hand holds it now -
# each leg the short way, at one turning speed across both.
func _set_handoff(t: float) -> void:
	if _sword_root == null or _hand_frame == null or _model == null:
		return
	var hand_basis: Basis = _hand_frame.global_basis.orthonormalized()
	var mount: Quaternion = _model_basis().inverse() * hand_basis.get_rotation_quaternion() * Quaternion.from_euler(hand_mount_rotation_degrees * (PI / 180.0))
	var first: float = _handoff_from.angle_to(_handoff_via)
	var second: float = _handoff_via.angle_to(mount)
	var split: float = first / maxf(first + second, 0.0001)
	var turn: Quaternion = mount
	if t < split:
		turn = _handoff_from.slerp(_handoff_via, t / split)
	elif t < 1.0:
		turn = _handoff_via.slerp(mount, (t - split) / maxf(1.0 - split, 0.0001))
	_sword_root.position = _handoff_from_position.lerp(_world_offset_to_local(hand_mount_position), t)
	_sword_root.quaternion = (hand_basis.get_rotation_quaternion().inverse() * _model_basis() * turn).normalized()

# His model's turn in the world, without its scale.
func _model_basis() -> Quaternion:
	return _model.global_basis.orthonormalized().get_rotation_quaternion()

# The way the sword's tip points in _sword_root's own space: along the
# blade's long axis, toward the end _apply_grip_offset() takes for the tip.
func _sword_tip_axis() -> Vector3:
	var axis := Vector3.ZERO
	axis[_longest_axis_index(_sword_raw_aabb.size)] = -1.0 if grip_axis_flip else 1.0
	return axis

# A wait for DrawSword's grab frame, or the handoff after it, stops; the
# sword stays where it is.
func _end_grab_wait() -> void:
	_grab_pending = false
	_strike_pending = false
	if _grab_tween != null:
		_grab_tween.kill()
		_grab_tween = null

# His model's yaw under the body: model_yaw_offset, and in a fight
# battle_camera_turn_degrees toward the camera. CameraRig's battle frame
# always puts him screen-left facing right (_battle_ground_forward()), so
# toward the camera is always a turn to his right - a negative yaw.
func _model_yaw() -> float:
	return deg_to_rad(model_yaw_offset - (battle_camera_turn_degrees if _battle_turned else 0.0))

# Called by region_field.gd once the battle overlay resolves (win, lose,
# or escape) - blends back from BattleIdle to the normal field Idle.
# _physics_process's own Idle/Walk switching only fires on movement input,
# which won't happen until the player takes a first step post-fight - this
# is what makes standing still right after a battle read as "back to
# normal" immediately instead of staying frozen on BattleIdle's last pose.
func exit_battle_stance() -> void:
	# The grab's wait ends before Idle replaces DrawSword, so the cut
	# doesn't read as one (_on_draw_sword_cut()).
	_end_grab_wait()
	if _animation_player:
		_swing_clip = &""
		_animation_player.play("Idle", battle_exit_blend)
	_end_slash_lunge()

	_battle_turned = false
	if _model != null:
		var turn_tween := create_tween()
		turn_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		turn_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		turn_tween.tween_property(_model, "rotation:y", _model_yaw(), animation_blend_time)

	_switch_sword_mount(_back_frame, back_mount_position, back_mount_rotation_degrees, animation_blend_time)

# Called by region_field.gd right after BattleOverlay.enter_battle() (the
# only point battle_controller exists to hand over - it's created inside
# that call, not before). Connects the two battle-animation triggers so
# this Wanderer's own swings/held stances react to the actual fight -
# torn down by unbind_battle() at battle end.
func bind_to_battle(controller: BattleController) -> void:
	_battle_controller = controller
	controller.card_played.connect(_on_card_played)
	controller.card_swing.connect(_on_card_swing)
	controller.card_repeat_swing.connect(_on_card_repeat_swing)
	controller.status_changed.connect(_on_status_changed)

func unbind_battle() -> void:
	if _battle_controller == null:
		return
	if _battle_controller.card_played.is_connected(_on_card_played):
		_battle_controller.card_played.disconnect(_on_card_played)
	if _battle_controller.card_swing.is_connected(_on_card_swing):
		_battle_controller.card_swing.disconnect(_on_card_swing)
	if _battle_controller.card_repeat_swing.is_connected(_on_card_repeat_swing):
		_battle_controller.card_repeat_swing.disconnect(_on_card_repeat_swing)
	if _battle_controller.status_changed.is_connected(_on_status_changed):
		_battle_controller.status_changed.disconnect(_on_status_changed)
	_battle_controller = null

# BattleController.card_swing fires swing_lead_seconds before the card's
# impact, only for a card with a battle_animation - the blade's whoosh
# (AttackAudio). The impact itself sounds from the enemy (its contact
# sound, on the hit frame - see BattleFeedback._react_to_card_hit()).
#
# An Attack's only: a Skill with a clip of its own (Brace) is a guard, not
# a blade, and has no whoosh.
func _on_card_swing(card: CardData) -> void:
	if card.card_type != CardData.CardType.ATTACK:
		return
	play_swing_audio()

# BattleController.card_repeat_swing: the repeated hit's follow-through -
# a short lunge at `target` (the recoil tween, pointed at it) and the
# whoosh again, pitched up. An Attack's only, like the first whoosh.
func _on_card_repeat_swing(card: CardData, target: FieldEnemy) -> void:
	if card.card_type != CardData.CardType.ATTACK:
		return
	play_swing_audio(follow_through_pitch)
	if target != null and is_instance_valid(target):
		play_hit_recoil(target.global_position - global_position, follow_through_distance, follow_through_tilt_degrees, follow_through_out_time, follow_through_return_time)

# See CardData.battle_animation's own doc - empty means this card has no
# swing. Queues _resting_battle_animation() rather than a bare "BattleIdle"
# so a card played while a status holding a pose (StatusData.battle_
# animation) is active on the player doesn't permanently cancel that pose
# once the swing finishes. Brace's own clip is a one-shot like Slash.
# The glb's own Slash ends on BattleIdle's first pose and blends into the
# resting clip over animation_blend_time, with its lunge at the target.
# The same clip again (a Slash in the last one's cancel window) swings
# from the top, blending out of where the last one had got to.
func _on_card_played(card: CardData, target: FieldEnemy) -> void:
	if card.battle_animation == &"" or _animation_player == null:
		return
	var resting := _resting_battle_animation()
	var again: bool = _animation_player.current_animation == String(card.battle_animation)
	_animation_player.play(card.battle_animation, animation_blend_time)
	if again:
		_animation_player.seek(0.0, true)
	_swing_clip = card.battle_animation
	if card.battle_animation == &"Slash" and _own_slash:
		_animation_player.set_blend_time(&"Slash", resting, animation_blend_time)
		_play_slash_lunge(target)
	_animation_player.queue(resting)

# The glb's Slash's step in (see the Slash group): his model out toward
# target - straight ahead with none - arriving on the contact frame,
# held there by the hit-stop (hold_animation()), then back. A swing over one still
# in flight goes out from wherever that one has got to, toward the same
# home.
func _play_slash_lunge(target: FieldEnemy) -> void:
	if _model == null:
		return
	if _lunge_tween != null and _lunge_tween.is_valid():
		_lunge_tween.kill()
	else:
		_lunge_home = Vector2(_model.position.x, _model.position.z)
	_lunge_tween = null
	var direction := Vector3.FORWARD
	if target != null and is_instance_valid(target):
		var toward: Vector3 = global_transform.basis.orthonormalized().transposed() * (target.global_position - global_position)
		toward.y = 0.0
		if toward.length() > 0.0001:
			direction = toward.normalized()
	var reach := _lunge_home + Vector2(direction.x, direction.z) * slash_lunge_distance
	var contact: float = get_clip_contact_time(&"Slash")
	var out_time: float = clampf(slash_lunge_out_time, 0.0, contact)
	var return_time: float = maxf(slash_lunge_return_time, 0.0)

	_lunge_tween = create_tween()
	_lunge_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_lunge_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if contact - out_time > 0.0:
		_lunge_tween.tween_interval(contact - out_time)
	_lunge_tween.tween_property(_model, "position:x", reach.x, out_time)
	_lunge_tween.parallel().tween_property(_model, "position:z", reach.y, out_time)
	_lunge_tween.chain().tween_property(_model, "position:x", _lunge_home.x, return_time)
	_lunge_tween.parallel().tween_property(_model, "position:z", _lunge_home.y, return_time)

# A lunge in flight stops, and his model is back home.
func _end_slash_lunge() -> void:
	if _lunge_tween == null:
		return
	_lunge_tween.kill()
	_lunge_tween = null
	if _model != null:
		_model.position.x = _lunge_home.x
		_model.position.z = _lunge_home.y

# See StatusData.battle_animation's own doc. Re-evaluates on every status
# change (a status being applied, ticked, or cleared) rather than reacting
# to any one specific status by name. A card's swing still playing plays
# out: the resting clip waits behind it in the queue, blended in as it
# ends, instead of cutting it off (every play's resolution ends in a
# status change).
func _on_status_changed() -> void:
	if _animation_player == null or _battle_controller == null:
		return
	var target := _resting_battle_animation()
	if _swinging():
		_animation_player.clear_queue()
		_animation_player.set_blend_time(_swing_clip, target, animation_blend_time)
		_animation_player.queue(target)
		return
	if _animation_player.current_animation != target:
		_animation_player.play(target, animation_blend_time)

# What the AnimationPlayer should be resting on right now: the first
# active player status carrying its own battle_animation (see StatusData.
# battle_animation), or BattleIdle if none does. Shared by _on_status_
# changed() (its direct target) and _on_card_played() (what a one-shot
# swing queues after itself), so both stay consistent with each other.
func _resting_battle_animation() -> StringName:
	if _battle_controller != null and _battle_controller.player != null:
		for status: Status in _battle_controller.player.statuses:
			if status.data.battle_animation != &"":
				return status.data.battle_animation
	return &"BattleIdle"

# Field-only step-up/step-down, called from _physics_process right before
# move_and_slide() while velocity.x/z already holds this frame's intended
# horizontal move and velocity.y is known (zeroed if is_on_floor()). Wanderer's
# CollisionShape3D (CapsuleShape3D, radius 0.4, height 1.8) sits offset +0.9
# up in local space, so its bottom - the feet - lands exactly at local y=0;
# global_position IS the foot position, same convention _apply_continuous_
# foot_grounding() and enter_battle_stance() already rely on.
#
# Disabled during battle stance: _battle_controller is only non-null once
# bind_to_battle() runs, which is after enter_battle_stance()'s own tween
# starts - RegionField's process-mode freeze (set before either call) means
# _physics_process itself won't fire again until battle ends anyway, but the
# explicit guard below doesn't depend on that ordering to be correct.
func _apply_step_up_and_down(delta: float) -> void:
	if _battle_controller != null:
		_hide_debug_lines()
		_wall_step_logged = false
		return

	var planar_motion := Vector3(velocity.x, 0.0, velocity.z) * delta
	if planar_motion.length() <= 0.0001:
		_hide_debug_lines()
		_wall_step_logged = false
		return

	var foot_position := global_position
	var move_dir := planar_motion.normalized()
	var move_distance := planar_motion.length()

	# test_move checks the actual capsule against this frame's horizontal
	# motion without committing it (move_and_slide() hasn't run yet this
	# frame, so there's no slide-collision data to read another way). Run
	# regardless of is_on_floor() - the diagnostic below needs to see a wall
	# even on a frame where is_on_floor() is false, since that's the likely
	# way "step-up silently does nothing" actually happens.
	var collision := KinematicCollision3D.new()
	var blocked := test_move(global_transform, planar_motion, collision)

	if not blocked:
		_wall_step_logged = false
		if _is_grounded():
			_try_step_down(foot_position, move_dir, move_distance)
		else:
			_hide_debug_lines()
		return

	# Blocked, but by a walkable slope (within floor_max_angle) rather than a
	# genuine wall - move_and_slide() climbs this on its own; nothing to do.
	var wall_normal: Vector3 = collision.get_normal(0)
	var wall_angle := wall_normal.angle_to(Vector3.UP)
	if wall_angle <= floor_max_angle:
		_hide_debug_lines()
		_wall_step_logged = false
		return

	# TEMPORARY diagnostic for the spawn-slab step-up miss - print once per
	# wall contact (not every physics frame the body stays pressed against
	# it) via _wall_step_logged, reset above the moment the wall goes away.
	# Remove once the miss is diagnosed.
	var should_log := not _wall_step_logged
	_wall_step_logged = true
	if should_log:
		print("Wanderer step-up: wall detected - is_on_floor=%s wall_normal=%s wall_angle_deg=%.1f floor_max_angle_deg=%.1f" % [is_on_floor(), wall_normal, rad_to_deg(wall_angle), rad_to_deg(floor_max_angle)])

	if not _is_grounded():
		if should_log:
			print("Wanderer step-up: rejected - not on floor")
		return

	_try_step_up(foot_position, move_dir, move_distance, should_log)

# Casts from step_height above the foot, forward past the capsule's own
# leading edge (radius + this frame's move distance + step_probe_margin -
# a cast that only reached move_distance from the CENTER would still land
# short of the obstacle's far side, putting the down cast on the ground in
# FRONT of it rather than on top of it), then straight down from there to
# find the landing. Lifts the body onto it only if the landing is within
# step_height of the current foot and its normal is walkable - otherwise
# it's a wall too tall to step up, and move_and_slide() runs unmodified and
# simply blocks against it as normal.
# should_log prints each stage's result - see the TEMPORARY note in
# _apply_step_up_and_down, the only caller that ever passes true.
func _try_step_up(foot_position: Vector3, move_dir: Vector3, move_distance: float, should_log: bool = false) -> void:
	var forward_distance: float = _capsule_radius + move_distance + step_probe_margin
	var raised_start: Vector3 = foot_position + Vector3.UP * step_height
	var raised_end: Vector3 = raised_start + move_dir * forward_distance
	var forward_result: Dictionary = _cast_ray(raised_start, raised_end)
	_set_debug_line(_step_forward_line, raised_start, raised_end)

	if should_log:
		if forward_result.is_empty():
			print("Wanderer step-up: forward cast at step_height=%.3f, distance=%.3f (radius=%.3f + move=%.3f + margin=%.3f) from %s to %s - clear" % [step_height, forward_distance, _capsule_radius, move_distance, step_probe_margin, raised_start, raised_end])
		else:
			print("Wanderer step-up: forward cast at step_height=%.3f, distance=%.3f - hit %s at %s" % [step_height, forward_distance, forward_result.get("collider"), forward_result.get("position")])

	if not forward_result.is_empty():
		_set_debug_line(_step_down_line, Vector3.ZERO, Vector3.ZERO, false)
		if should_log:
			print("Wanderer step-up: rejected - forward cast blocked at step_height")
		return

	var down_start: Vector3 = raised_end
	var down_end: Vector3 = down_start - Vector3.UP * (step_height + 0.05)
	var down_result: Dictionary = _cast_ray(down_start, down_end)
	_set_debug_line(_step_down_line, down_start, down_end)

	if down_result.is_empty():
		if should_log:
			print("Wanderer step-up: rejected - down cast from %s to %s found no landing" % [down_start, down_end])
		return

	var landing_position: Vector3 = down_result["position"]
	var landing_normal: Vector3 = down_result["normal"]
	var rise: float = landing_position.y - foot_position.y
	var landing_angle_deg: float = rad_to_deg(landing_normal.angle_to(Vector3.UP))
	if should_log:
		print("Wanderer step-up: down cast landing_y=%.4f foot_y=%.4f rise=%.4f landing_normal=%s landing_angle_deg=%.1f" % [landing_position.y, foot_position.y, rise, landing_normal, landing_angle_deg])

	if rise < -0.001 or rise > step_height + 0.001:
		if should_log:
			print("Wanderer step-up: rejected - rise %.4f outside [0, step_height=%.4f]" % [rise, step_height])
		return
	if landing_angle_deg > rad_to_deg(floor_max_angle):
		if should_log:
			print("Wanderer step-up: rejected - landing_angle_deg %.1f exceeds floor_max_angle_deg %.1f" % [landing_angle_deg, rad_to_deg(floor_max_angle)])
		return

	if should_log:
		print("Wanderer step-up: accepted - lifting foot to y=%.4f (rise=%.4f)" % [landing_position.y, rise])

	global_position.y = landing_position.y
	velocity.y = 0.0

# The step-down counterpart: test_move found nothing blocking this frame's
# horizontal move, but that alone doesn't mean the ground continues at the
# same height - walking off the edge of a raised slab is also "not blocked"
# horizontally. Casts down through step_height at the destination and, if
# the drop is within range, sets the body straight down onto it rather than
# letting gravity peel it off the edge (which reads as a brief float/hitch
# before it starts actually falling).
func _try_step_down(foot_position: Vector3, move_dir: Vector3, move_distance: float) -> void:
	var destination: Vector3 = foot_position + move_dir * move_distance
	var probe_start: Vector3 = destination + Vector3.UP * step_height
	var probe_end: Vector3 = probe_start - Vector3.UP * (step_height * 2.0)
	var result: Dictionary = _cast_ray(probe_start, probe_end)
	_set_debug_line(_step_forward_line, foot_position, destination)
	_set_debug_line(_step_down_line, probe_start, probe_end)

	if result.is_empty():
		return

	var landing_position: Vector3 = result["position"]
	var landing_normal: Vector3 = result["normal"]
	var drop: float = foot_position.y - landing_position.y
	if drop <= 0.001 or drop > step_height + 0.001:
		return
	if landing_normal.angle_to(Vector3.UP) > floor_max_angle:
		return

	global_position.y = landing_position.y
	velocity.y = 0.0

# On the ground for every purpose the body has - gravity, the step
# probes, the animation state that follows planar speed alone: a real
# floor contact, or the ground hold standing in for one.
func _is_grounded() -> bool:
	return is_on_floor() or _ground_hold_active

# See ground_penetration_tolerance_m's own doc. Three outcomes against
# the drawn surface at his XZ: feet further below it than the tolerance
# - put onto it, any fall cancelled, the hold on (and a warning, once per
# floor, if no channel is draining - that is a bad spot in the relief,
# not the case this exists for); feet clearly above it - the hold off,
# so stepping off a ledge falls as it should; within the tolerance - the
# hold stays whatever it was, and a real floor contact always ends it.
func _hold_above_visible_ground() -> void:
	if _ground == null or _battle_controller != null:
		_ground_hold_active = false
		return
	var local: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	# The sand as drawn, or a RockShelf's top where he stands on one.
	var surface: float = _ground.get_walk_height_at(Vector2(local.x, local.z))
	var gap: float = global_position.y - surface
	if gap < -ground_penetration_tolerance_m:
		if not _ground_hold_active and not _ground.is_channel_draining() and not _ground_hold_warned:
			_ground_hold_warned = true
			push_warning("Wanderer: feet %.2f m under the drawn ground at XZ (%.2f, %.2f) with no channel draining - a bad spot in the relief." % [-gap, global_position.x, global_position.z])
		global_position.y = surface
		velocity.y = maxf(velocity.y, 0.0)
		_ground_hold_active = true
	elif gap > ground_penetration_tolerance_m or is_on_floor():
		_ground_hold_active = false

func _cast_ray(from: Vector3, to: Vector3) -> Dictionary:
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	return space_state.intersect_ray(query)

# show_line false is a plain hide - used when a probe was never reached
# this frame (e.g. the forward cast already found a landing/blocker so the
# other cast's line should read as "not part of this frame's result"
# instead of showing a stale segment from a previous frame).
func _set_debug_line(mesh_instance: MeshInstance3D, from: Vector3, to: Vector3, show_line: bool = true) -> void:
	if not debug_draw_step_casts or not show_line:
		mesh_instance.visible = false
		return

	var immediate_mesh: ImmediateMesh = mesh_instance.mesh as ImmediateMesh
	immediate_mesh.clear_surfaces()
	immediate_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	immediate_mesh.surface_add_vertex(from)
	immediate_mesh.surface_add_vertex(to)
	immediate_mesh.surface_end()
	mesh_instance.visible = true

func _hide_debug_lines() -> void:
	if _step_forward_line:
		_step_forward_line.visible = false
	if _step_down_line:
		_step_down_line.visible = false

func _physics_process(delta: float) -> void:
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	if not input_locked and not keys_locked and _dash_timer <= 0.0 and Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
		# Dash in the direction the Wanderer is currently facing, via the
		# same angle<->direction conversion turn-to-face uses below, so it
		# always matches what's on screen.
		_dash_direction = _forward_from_angle(rotation.y)
		_dash_timer = dash_duration
		_dash_cooldown_timer = dash_cooldown

	# The one and only move_direction for this frame: everything below
	# (velocity target, turn-to-face) reads from this, nothing re-derives
	# it separately.
	var move_direction: Vector3
	var is_dashing := _dash_timer > 0.0

	if is_dashing:
		# Ignore movement input entirely for the dash's duration; direction
		# is fixed to what was captured when the dash started.
		_dash_timer -= delta
		move_direction = _dash_direction
	else:
		var input_dir := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		)
		if input_locked:
			input_dir = Vector2.ZERO
			clear_move_target()
		elif keys_locked:
			input_dir = Vector2.ZERO
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()

		# Any key input takes over from a click target.
		if input_dir.length() > 0.0001:
			clear_move_target()

		move_direction = Vector3(input_dir.x, 0.0, -input_dir.y)
		if _camera:
			var camera_basis := _camera.global_transform.basis
			var camera_forward := _flatten_normalized(-camera_basis.z)
			var camera_right := _flatten_normalized(camera_basis.x)
			# input_dir.y is +1 on W (forward - back); camera_forward already
			# points away from the camera, so W adds it directly.
			move_direction = camera_right * input_dir.x + camera_forward * input_dir.y
			if move_direction.length() > 1.0:
				move_direction = move_direction.normalized()

		if _has_move_target:
			move_direction = _move_target_direction()

	if is_dashing:
		var dash_speed := dash_distance / dash_duration
		velocity.x = move_direction.x * dash_speed
		velocity.z = move_direction.z * dash_speed
	else:
		var target_velocity := move_direction * move_speed
		velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if not _is_grounded():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	# Before the step probes, so they test the motion he will actually make.
	_limit_velocity_at_hold_line()
	_limit_velocity_at_wade_limit()

	_apply_step_up_and_down(delta)

	move_and_slide()

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	_hold_at_line(planar_speed)
	_hold_at_wade_limit()

	# Last, after every other write to global_position this frame, so the
	# position that renders is the held one - a step-down onto lagging
	# collision earlier in the frame never shows.
	_hold_above_visible_ground()

	# At rest at the hold line he looks back (look_back_toward()) - even
	# with a key still pressing him into it; moving at all, he faces the
	# way he moves.
	if _look_back_active and planar_speed < walk_speed_threshold:
		rotation.y = lerp_angle(rotation.y, _angle_from_direction(_look_back_direction), hold_line_turn_speed * delta)
	elif move_direction.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, _angle_from_direction(move_direction), rotation_speed * delta)

	_tick_stuck(delta, planar_speed)
	if use_animation_tree:
		if _animation_tree:
			_animation_tree.set("parameters/blend_position", clampf(planar_speed, 0.0, move_speed))
	elif _animation_player:
		# Run plays for the dash's own duration - a discrete "he sprints"
		# state, not a continuous speed blend (dash_speed can be well past
		# move_speed, and it starts/stops instantly rather than ramping),
		# which is exactly why this branch (not the AnimationTree/
		# BlendSpace1D one above) is where it's wired: that blend space
		# only spans 0..move_speed and models continuous Idle<->Walk
		# blending, not a hard cut into a separate clip.
		var next_animation: String
		if is_dashing:
			next_animation = "Run"
		elif planar_speed > walk_speed_threshold:
			next_animation = "Walk"
		else:
			next_animation = "Idle"
		if _animation_player.current_animation != next_animation:
			_animation_player.play(next_animation, animation_blend_time)
