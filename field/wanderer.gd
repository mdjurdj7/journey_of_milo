extends CharacterBody3D
class_name Wanderer

const IDLE_SCENE_PATH := "res://assets/models/wanderer/wanderer_idle.fbx"
const WALK_SCENE_PATH := "res://assets/models/wanderer/wanderer_walking.fbx"
const RUN_SCENE_PATH := "res://assets/models/wanderer/wanderer_running.fbx"
const BATTLE_IDLE_SCENE_PATH := "res://assets/models/wanderer/wanderer_battle_idle.fbx"
const DRAW_SWORD_SCENE_PATH := "res://assets/models/wanderer/wanderer_battle_start_draw_sword.fbx"
const SLASH_SCENE_PATH := "res://assets/models/wanderer/wanderer_slash.fbx"
const BRACE_SCENE_PATH := "res://assets/models/wanderer/wanderer_brace.fbx"
const ALBEDO_TEXTURE_PATH := "res://assets/models/wanderer/wanderer_albedo.png"
const FLAT_SHADER_PATH := "res://field/wanderer_flat.gdshader"
# sword.glb (glTF, unlike the earlier sword_albedo.fbx) imports with its
# own embedded textures correctly extracted (sword_0/1/2.jpg) and a real
# material built from them - see _apply_model_material()'s
# keep_imported_material_when_textured, which leaves that material alone
# in TEXTURED mode. SWORD_ALBEDO_TEXTURE_PATH below still has no file at
# it; POSTERIZED mode still falls back to flat charcoal (with a
# push_warning) until a real texture exists there.
const SWORD_SCENE_PATH := "res://assets/models/wanderer/sword.glb"
const SWORD_ALBEDO_TEXTURE_PATH := "res://assets/models/wanderer/sword_albedo.png"

@export var move_speed: float = 4.5
@export var acceleration: float = 14.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 12.0
@export var dash_distance: float = 6.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0

@export_group("Point To Move")
# A click on the field (see RegionField._unhandled_input()) sets a move
# target; the Wanderer walks toward it at move_speed, facing the way he
# walks, and the target clears within arrive_radius of it, the moment
# any WASD input arrives, or after stuck_time of standing still against
# something (a hull, a wall) with the target still ahead - no
# pathfinding, he stops where he's blocked. An enemy target (see
# set_move_target_enemy()) is followed live until contact starts the
# fight, which clears it (see enter_battle_stance()).
@export var arrive_radius: float = 0.25
@export var stuck_time: float = 0.4

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
@export var use_animation_tree: bool = false
@export var walk_speed_threshold: float = 0.1
@export var animation_blend_time: float = 0.2
@export var remove_walk_root_motion: bool = true
@export var camera_path: NodePath = ^"../CameraPivot/Camera3D"
@export var ground_path: NodePath = ^"../Ground"
@export var model_yaw_offset: float = 180.0
# A touch warmer than the crab's own charcoal (see FieldEnemy.model_color)
# so the two read as different things even at a glance, not just "the
# same placeholder grey twice." Used only as the fallback flat material -
# see _build_flat_material() - when wanderer_flat.gdshader can't be built
# (ALBEDO_TEXTURE_PATH failed to load).
@export var wanderer_color: Color = Color(0.16, 0.15, 0.14, 1)

# The real model ships at whatever scale its source file happens to use
# (verified at 0.019m tall before this export existed) - this is the
# actual size the Wanderer renders at, in meters, measured by AABB height
# right after instancing. model_scale_override below can bypass this.
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
# corrects for that continuously, every physics frame, using whichever
# clip is actually playing. This is the target body-local Y its lowest
# foot/toe bone is driven toward, not a one-time nudge.
@export var model_ground_offset: float = 0.0
# How fast _apply_continuous_foot_grounding() eases the model toward its
# target Y (exponential, per second) - high enough that normal per-frame
# foot movement during Idle/Walk tracks essentially instantly, low enough
# that a clip transition's own hips-height jump (e.g. into BattleIdle)
# eases in over a few frames instead of popping.
@export var foot_grounding_smoothing_speed: float = 12.0

# The Mixamo rig's own A-pose rest pose bakes in a wider leg stance than
# the model should stand at. Corrected continuously via a
# LegSpreadCorrectionModifier (a SkeletonModifier3D added under the
# skeleton by _setup_leg_spread_correction()) rather than a one-time pose
# edit, so it stacks with every clip (Idle, Walk, BattleIdle, DrawSword)
# instead of needing separate correction per clip.
@export var leg_spread_correction_degrees: float = 6.0:
	set(value):
		leg_spread_correction_degrees = value
		if _leg_spread_modifier:
			_leg_spread_modifier.correction_degrees = value

# Widens BattleIdle's own square-on stance into a fencer's ready stance -
# see BattleStanceModifier's own doc for the mechanics (which bone rotates
# which way, the influence-based blend enter_battle_stance()/exit_battle_
# stance() drive). Forwarded live into _battle_stance_modifier, same
# shape as leg_spread_correction_degrees above.
@export_group("Battle Stance")
@export var battle_back_leg_degrees: float = 12.0:
	set(value):
		battle_back_leg_degrees = value
		if _battle_stance_modifier:
			_battle_stance_modifier.battle_back_leg_degrees = value
@export var battle_front_leg_degrees: float = 4.0:
	set(value):
		battle_front_leg_degrees = value
		if _battle_stance_modifier:
			_battle_stance_modifier.battle_front_leg_degrees = value
@export var battle_pelvis_yaw_degrees: float = 6.0:
	set(value):
		battle_pelvis_yaw_degrees = value
		if _battle_stance_modifier:
			_battle_stance_modifier.battle_pelvis_yaw_degrees = value
# Default true: he squares up with the sword in his right hand (see hand_
# mount_bone_suffix below), so the left leg trails as the back leg.
@export var battle_back_leg_is_left: bool = true:
	set(value):
		battle_back_leg_is_left = value
		if _battle_stance_modifier:
			_battle_stance_modifier.back_leg_is_left = value

enum ShadingMode { TEXTURED, POSTERIZED, FLAT }

@export_group("Shading")
# TEXTURED: a plain StandardMaterial3D reading the albedo texture as-
# painted (Meshy's own colors, roughness 1, specular 0) - no posterizing.
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
			_apply_model_material(_sword_root, SWORD_ALBEDO_TEXTURE_PATH, true, false)

# Mirrors wanderer_flat.gdshader's own uniforms one-to-one - see that
# file's own doc for what each does. Only used when shading_mode is
# POSTERIZED. Not live-updating on their own (same "set once" shape
# wanderer_color's flat fallback already has) - changing shading_mode
# itself always re-reads the current values, so toggling it is also how
# to pick up an edit made here.
@export_range(2, 8) var tone_count: int = 3
@export var tone_dark: Color = Color(0.125, 0.12, 0.115, 1)
@export var tone_mid: Color = Color(0.205, 0.195, 0.185, 1)
@export var tone_light: Color = Color(0.31, 0.295, 0.28, 1)

@export_group("Sword")
# Audited: every sword export below carries an explicit get (returns the
# backing field directly - no implicit-getter ambiguity) alongside its
# set, and every setter that touches a node (_sword_root/_sword_mesh_
# holder) guards on that node being non-null, which is only true once
# _setup_sword() has run in _ready() - so a setter firing during scene
# deserialization (before _ready()) is always a plain no-op on the
# backing field, never a reset of anything else. _setup_sword() and
# _switch_sword_mount() never read a constant or a cached copy of any of
# these - every read below is the live export at call time, so a scene-
# file override is exactly what ends up applied at _ready() and at every
# enter_battle_stance()/exit_battle_stance() mount switch after it.

# Uniform scale is derived from this / the sword model's own raw AABB
# longest axis (see _setup_sword()) - same "measure raw, then derive a
# factor" approach _scale_and_ground_model() uses for the body.
@export var sword_length: float = 1.3

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

# Bone names may be sanitized on import (see LegSpreadCorrectionModifier's
# own doc) - resolved by suffix match against the skeleton, same as
# everywhere else in this project that reads Mixamo bone names.
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
# bone space - the source model is ~0.019m tall, so a raw 0.14 offset
# there would place the sword ~13m away): _world_offset_to_local() divides
# by _model_scale_factor before writing _sword_root.position. Rotations
# are unaffected by that scale, so they're applied as given.
@export var back_mount_position: Vector3 = Vector3(0.0, 0.15, -0.18):
	get:
		return back_mount_position
	set(value):
		back_mount_position = value
		if _sword_root != null and _sword_root.get_parent() == _back_attachment:
			_sword_root.position = _world_offset_to_local(value)
@export var back_mount_rotation_degrees: Vector3 = Vector3(15.0, -100.0, 80.0):
	get:
		return back_mount_rotation_degrees
	set(value):
		back_mount_rotation_degrees = value
		if _sword_root != null and _sword_root.get_parent() == _back_attachment:
			_sword_root.rotation_degrees = value
@export var hand_mount_position: Vector3 = Vector3(0.0, 0.0, 0.0):
	get:
		return hand_mount_position
	set(value):
		hand_mount_position = value
		if _sword_root != null and _sword_root.get_parent() == _hand_attachment:
			_sword_root.position = _world_offset_to_local(value)
@export var hand_mount_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0):
	get:
		return hand_mount_rotation_degrees
	set(value):
		hand_mount_rotation_degrees = value
		if _sword_root != null and _sword_root.get_parent() == _hand_attachment:
			_sword_root.rotation_degrees = value

var _model: Node3D = null
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _camera: Camera3D
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

var _has_move_target: bool = false
var _move_target: Vector3 = Vector3.ZERO
var _move_target_enemy: FieldEnemy = null
var _stuck_timer: float = 0.0

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
var _leg_spread_modifier: LegSpreadCorrectionModifier = null
var _battle_stance_modifier: BattleStanceModifier = null

# The uniform scale _scale_and_ground_model() applied to the model, set
# once there - _setup_sword() has to divide its own scale factor by this,
# since the sword sits under a BoneAttachment3D that's a descendant of
# the (hugely up-scaled) model and inherits its scale on top of whatever
# the sword's own node.scale is set to.
var _model_scale_factor: float = 1.0

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
var _back_attachment: BoneAttachment3D = null
var _hand_attachment: BoneAttachment3D = null

# The body's own currently-applied material (set by _apply_model_material()
# for is_body calls only, never for the sword's) - play_hit_flash() tweens
# this directly rather than re-deriving it, since re-deriving would mean
# re-walking the model's MeshInstance3D children and, worse, building a
# second material instance no MeshInstance3D actually has assigned.
var _active_material: Material = null
var _ground: Ground = null
var _attack_audio: AttackAudio = null

# Set by bind_to_battle(), cleared by unbind_battle() - see both for why
# region_field.gd is the only caller of either.
var _battle_controller: BattleController = null

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D

	var model := (load(IDLE_SCENE_PATH) as PackedScene).instantiate() as Node3D
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
	_apply_model_material(model)
	_scale_and_ground_model(model)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	_animation_player = players[0] as AnimationPlayer if not players.is_empty() else null
	# Same reasoning as CameraPivot's own process_mode override - belt and
	# suspenders alongside model.process_mode above, since this is also the
	# node whose own _process actually advances playback.
	if _animation_player:
		_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS

	_merge_clips(_animation_player)
	if use_animation_tree:
		_build_animation_tree()
	elif _animation_player:
		_animation_player.play("Idle")

	_find_grounding_bones(model)
	_setup_leg_spread_correction(model)
	_setup_battle_stance_modifier(model)
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
	footprint_spawner.setup(model, self, ground)

	var footstep_audio := FootstepAudio.new()
	footstep_audio.name = "FootstepAudio"
	add_child(footstep_audio)
	footstep_audio.setup(footprint_spawner, ground)

	_attack_audio = AttackAudio.new()
	_attack_audio.name = "AttackAudio"
	add_child(_attack_audio)
	_attack_audio.setup()

# One shared material for the whole model, applied via material_override
# on every MeshInstance3D under it. Which material depends on shading_
# mode (see that export's own doc); TEXTURED/POSTERIZED both fall back to
# the flat charcoal material if their own asset (texture and/or shader)
# fails to load (each guarded and push_warning'd separately below), so a
# missing/not-yet-imported asset degrades to a solid color instead of an
# invisible or shaderless model. Re-run whenever shading_mode's setter
# fires, so this always reflects the current mode - not just at _ready().
# texture_path defaults to the body's own albedo; _setup_sword() and the
# shading_mode setter both pass SWORD_ALBEDO_TEXTURE_PATH explicitly to
# apply the same mode to the sword.
# keep_imported_material_when_textured is for the sword only: Meshy
# embedded the sword's texture directly in the FBX and the importer
# already built a correct material from it, so in TEXTURED mode
# material_override is left null (clearing any override from a previous
# POSTERIZED/FLAT mode) rather than replaced with a StandardMaterial3D
# built from SWORD_ALBEDO_TEXTURE_PATH, which likely doesn't exist as a
# standalone file. The body has no such imported material (its FBX ships
# untextured geometry) so it always keeps the override path.
func _apply_model_material(model: Node3D, texture_path: String = ALBEDO_TEXTURE_PATH, keep_imported_material_when_textured: bool = false, is_body: bool = true) -> void:
	if shading_mode == ShadingMode.TEXTURED and keep_imported_material_when_textured:
		for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh_instance as MeshInstance3D
			mi.material_override = null
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		return

	var material: Material = null
	match shading_mode:
		ShadingMode.TEXTURED:
			material = _build_textured_material(texture_path)
		ShadingMode.POSTERIZED:
			material = _build_posterized_material(texture_path)
		ShadingMode.FLAT:
			material = null
	if material == null:
		material = _build_flat_material()
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# The sword's own material_override is never what play_hit_flash()
	# should be lerping (only the body should flash) - is_body is false
	# for both of _setup_sword()'s own calls, so this only ever tracks the
	# body's material regardless of which shading_mode built it.
	if is_body:
		_active_material = material

# Meshy's own painted colors, no posterizing - same "roughness 1,
# specular 0" shape every other Wanderer/FieldEnemy material already uses.
func _build_textured_material(texture_path: String) -> StandardMaterial3D:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("Wanderer: albedo texture failed to load (%s); using the flat charcoal fallback material." % texture_path)
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material

func _build_posterized_material(texture_path: String) -> ShaderMaterial:
	var texture := load(texture_path) as Texture2D
	if texture == null:
		push_warning("Wanderer: albedo texture failed to load (%s); using the flat charcoal fallback material." % texture_path)
		return null
	var shader := load(FLAT_SHADER_PATH) as Shader
	if shader == null:
		push_warning("Wanderer: wanderer_flat shader failed to load (%s); using the flat charcoal fallback material." % FLAT_SHADER_PATH)
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("tone_count", tone_count)
	material.set_shader_parameter("tone_dark", tone_dark)
	material.set_shader_parameter("tone_mid", tone_mid)
	material.set_shader_parameter("tone_light", tone_light)
	print("Wanderer: applied posterized material - texture=%s tone_count=%d tone_dark=%s tone_mid=%s tone_light=%s" % [texture_path, tone_count, tone_dark, tone_mid, tone_light])
	return material

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
func _scale_and_ground_model(model: Node3D) -> void:
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_transform_in_model: Transform3D = model.global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_model: AABB = mi_transform_in_model * mi.get_aabb()
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

# Finds the skeleton and the lowest-contact bone indices once, at
# startup - cached into _grounding_skeleton/_grounding_bone_indices so the
# continuous per-physics-frame correction below never does a name lookup
# or a skeleton scan, just two pose reads by index.
#
# Prefers toe bones (mixamorig_LeftToeBase/RightToeBase) since those sit
# at the actual ground contact point; falls back to
# mixamorig_LeftFoot/RightFoot if no toe bone is present on this rig.
func _find_grounding_bones(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_grounding_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if _grounding_skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; continuous foot grounding disabled.")
		return

	var toe_bone_names := ["mixamorig_LeftToeBase", "mixamorig_RightToeBase"]
	var foot_bone_names := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
	var toe_present := false
	for bone_name in toe_bone_names:
		if _grounding_skeleton.find_bone(bone_name) != -1:
			toe_present = true
			break
	var bone_names: Array = toe_bone_names if toe_present else foot_bone_names

	_grounding_bone_indices.clear()
	for bone_name in bone_names:
		var bone_idx := _grounding_skeleton.find_bone(bone_name)
		if bone_idx != -1:
			_grounding_bone_indices.append(bone_idx)

	if _grounding_bone_indices.is_empty():
		push_warning("Wanderer: none of the expected foot/toe bones were found on the skeleton; continuous foot grounding disabled.")
		_grounding_skeleton = null

# Does its own Skeleton3D lookup rather than reusing _grounding_skeleton:
# _find_grounding_bones() above nulls that out when foot/toe bones aren't
# found, which is a completely unrelated failure mode from the leg-spread
# bones this needs - leg spread correction shouldn't fail just because
# the foot-bone names didn't match on some other rig.
func _setup_leg_spread_correction(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var skeleton := skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; leg spread correction disabled.")
		return

	_leg_spread_modifier = LegSpreadCorrectionModifier.new()
	_leg_spread_modifier.name = "LegSpreadCorrection"
	_leg_spread_modifier.correction_degrees = leg_spread_correction_degrees
	skeleton.add_child(_leg_spread_modifier)

# Same skeleton lookup as _setup_leg_spread_correction() above, duplicated
# rather than shared since each already has its own reason to fail
# independently of the other (see that function's own doc on why it
# doesn't reuse _grounding_skeleton either). animation_player is handed
# over directly since BattleStanceModifier has no other way to reach it -
# see its own doc. influence starts at 0: this should be completely inert
# on the field, only ever raised by enter_battle_stance()'s own tween.
func _setup_battle_stance_modifier(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	var skeleton := skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; battle stance widening disabled.")
		return

	_battle_stance_modifier = BattleStanceModifier.new()
	_battle_stance_modifier.name = "BattleStanceModifier"
	_battle_stance_modifier.animation_player = _animation_player
	_battle_stance_modifier.battle_back_leg_degrees = battle_back_leg_degrees
	_battle_stance_modifier.battle_front_leg_degrees = battle_front_leg_degrees
	_battle_stance_modifier.battle_pelvis_yaw_degrees = battle_pelvis_yaw_degrees
	_battle_stance_modifier.back_leg_is_left = battle_back_leg_is_left
	_battle_stance_modifier.influence = 0.0
	skeleton.add_child(_battle_stance_modifier)

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
# local space, which is the model's unscaled bone space (inheriting the
# model's own up-scale via _model_scale_factor) - dividing converts a
# world-metre offset into that local space.
func _world_offset_to_local(world_offset: Vector3) -> Vector3:
	if _model_scale_factor <= 0.0001:
		return world_offset
	return world_offset / _model_scale_factor

# Builds two BoneAttachment3D children of the skeleton (one per mount),
# loads and scales the sword once, and parks it on the back mount to
# start. enter_battle_stance()/exit_battle_stance() move it between the
# two via _switch_sword_mount() - the attachments themselves never move
# once created; only which one currently parents _sword_root changes.
func _setup_sword(model: Node3D) -> void:
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	_sword_skeleton = skeletons[0] as Skeleton3D if not skeletons.is_empty() else null
	if _sword_skeleton == null:
		push_warning("Wanderer: no Skeleton3D found under model; sword mount disabled.")
		return

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

	var sword_scene := load(SWORD_SCENE_PATH) as PackedScene
	if sword_scene == null:
		push_warning("Wanderer: sword scene failed to load (%s); sword mount disabled." % SWORD_SCENE_PATH)
		return
	var sword_mesh_holder := sword_scene.instantiate() as Node3D
	if sword_mesh_holder == null:
		push_warning("Wanderer: sword scene root (%s) is not a Node3D; sword mount disabled." % SWORD_SCENE_PATH)
		return

	# _sword_root is the node mounts actually position/scale/rotate - its
	# origin is the grip (see _apply_grip_offset()), not wherever the
	# loaded scene's own origin happens to be. _sword_mesh_holder is the
	# loaded scene itself, offset inside _sword_root so the grip point
	# lands at _sword_root's origin regardless of _sword_root's own scale.
	_sword_root = Node3D.new()
	_sword_root.name = "SwordRoot"
	_back_attachment.add_child(_sword_root)

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

	var axis := _longest_axis_index(combined_aabb.size)
	var longest_axis: float = combined_aabb.size[axis]
	var local_scale_factor := 1.0
	if longest_axis <= 0.0001:
		push_warning("Wanderer: sword AABB longest axis is ~0 (%f); leaving scale at 1.0." % longest_axis)
	else:
		local_scale_factor = sword_length / longest_axis

	# _sword_root sits under _back_attachment, a child of the model's own
	# Skeleton3D - it inherits the model's whole up-scale (model_scale_
	# factor, easily 50-100x since the source model ships at ~0.019m tall)
	# on top of whatever _sword_root.scale is set to here. Dividing it back
	# out is what makes the sword's actual WORLD length come out to
	# sword_length instead of sword_length * model_scale_factor.
	var world_scale_factor := local_scale_factor
	if _model_scale_factor > 0.0001:
		world_scale_factor = local_scale_factor / _model_scale_factor
	else:
		push_warning("Wanderer: _model_scale_factor is ~0 (%f); sword scale not compensated." % _model_scale_factor)
	_sword_root.scale = Vector3.ONE * world_scale_factor

	_apply_model_material(_sword_root, SWORD_ALBEDO_TEXTURE_PATH, true, false)

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
# end. No-op until _setup_sword() has populated _sword_mesh_holder/
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

# Reparents _sword_root onto target_attachment (a no-op if it's already
# there) and tweens its local position/rotation to the target mount's
# offsets over duration, so the switch reads as the sword sliding into
# place rather than popping - matches enter_battle_stance's own movement
# tween shape (parallel, sine in-out) so both read as one motion.
# target_position_world is in world metres (see back_mount_position's own
# doc) - converted to _sword_root's local space before the tween.
func _switch_sword_mount(target_attachment: BoneAttachment3D, target_position_world: Vector3, target_rotation_degrees: Vector3, duration: float) -> void:
	if _sword_root == null or target_attachment == null:
		return

	var current_parent := _sword_root.get_parent()
	if current_parent != target_attachment:
		if current_parent != null:
			current_parent.remove_child(_sword_root)
		target_attachment.add_child(_sword_root)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_sword_root, "position", _world_offset_to_local(target_position_world), duration)
	tween.tween_property(_sword_root, "rotation_degrees", target_rotation_degrees, duration)

# The float this replaces was per-clip: grounding measured once, on
# Idle, doesn't hold once a battle clip (a different hips height) takes
# over. Every physics frame instead: read the lowest cached foot/toe bone
# Y in body space (to_local() already accounts for the model's current
# position, so this reflects whatever offset is already applied), derive
# the model.position.y that would put it exactly at model_ground_offset,
# and ease toward that rather than snapping, so a clip transition's own
# hips-height jump doesn't pop the model - it eases in over a few frames.
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

# Idle/Walk/BattleIdle/DrawSword ship as four separate Mixamo FBX files,
# each importing with a single clip whose name Godot's FBX importer
# assigns (not "mixamo.com" — don't assume a specific name). This finds
# each player's one clip by count, not by name, and merges them into one
# AnimationPlayer library as "Idle"/"Walk"/"BattleIdle"/"DrawSword" - this
# is the real model, not a stand-in; the merge exists because of how the
# four clips currently ship as separate files, not because anything here
# is temporary.
func _merge_clips(anim_player: AnimationPlayer) -> void:
	if anim_player == null:
		push_error("Wanderer: idle model has no AnimationPlayer; cannot merge clips.")
		return

	var idle_entry := _find_single_animation(anim_player, "idle AnimationPlayer")
	if idle_entry.is_empty():
		return
	var idle_library := anim_player.get_animation_library(idle_entry["library"])
	idle_library.rename_animation(idle_entry["name"], "Idle")
	# Mixamo/FBX imports default to LOOP_NONE - play() would run this once
	# and hold on the last frame instead of looping, which reads as "idle
	# froze" the moment the clip's own (short) duration elapses. Applies
	# whether Idle is playing standalone or re-triggered by enter_battle_
	# stance()'s own play("Idle") call.
	var idle_animation: Animation = idle_entry["animation"]
	idle_animation.loop_mode = Animation.LOOP_LINEAR

	var walk_scene := load(WALK_SCENE_PATH) as PackedScene
	var walk_instance := walk_scene.instantiate()
	var walk_players := walk_instance.find_children("*", "AnimationPlayer", true, false)
	if walk_players.is_empty():
		push_error("Wanderer: walking model has no AnimationPlayer; Walk clip not merged.")
		walk_instance.free()
		return

	var walk_player := walk_players[0] as AnimationPlayer
	var walk_entry := _find_single_animation(walk_player, "walking AnimationPlayer")
	if walk_entry.is_empty():
		walk_instance.free()
		return

	var walk_animation: Animation = walk_entry["animation"]
	walk_animation.loop_mode = Animation.LOOP_LINEAR
	idle_library.add_animation("Walk", walk_animation)
	walk_instance.free()

	if walk_animation.get_track_count() == 0:
		push_error("Wanderer: merged Walk animation has no tracks; clip merge is broken.")
		return

	var anim_root := anim_player.get_node_or_null(anim_player.root_node)
	var track_node_path := NodePath(walk_animation.track_get_path(0).get_concatenated_names())
	var resolved := anim_root.get_node_or_null(track_node_path) if anim_root else null
	if not (resolved is Skeleton3D):
		push_error("Wanderer: Walk animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(track_node_path))
		return

	if remove_walk_root_motion:
		_remove_walk_root_motion(walk_animation)

	# Run - same shape as the Walk merge above (load, find its one real
	# clip by keyframe count, loop it, merge into the same idle_library),
	# reusing remove_walk_root_motion/_remove_walk_root_motion() since it's
	# the same Mixamo locomotion-root quirk, just a different clip. Played
	# during a dash in place of Walk/Idle - see _physics_process().
	var run_scene := load(RUN_SCENE_PATH) as PackedScene
	var run_instance := run_scene.instantiate()
	var run_players := run_instance.find_children("*", "AnimationPlayer", true, false)
	if run_players.is_empty():
		push_error("Wanderer: running model has no AnimationPlayer; Run clip not merged.")
		run_instance.free()
		return

	var run_player := run_players[0] as AnimationPlayer
	var run_entry := _find_single_animation(run_player, "running AnimationPlayer")
	if run_entry.is_empty():
		run_instance.free()
		return

	var run_animation: Animation = run_entry["animation"]
	run_animation.loop_mode = Animation.LOOP_LINEAR
	idle_library.add_animation("Run", run_animation)
	run_instance.free()

	if run_animation.get_track_count() == 0:
		push_error("Wanderer: merged Run animation has no tracks; clip merge is broken.")
		return

	var run_track_node_path := NodePath(run_animation.track_get_path(0).get_concatenated_names())
	var run_resolved := anim_root.get_node_or_null(run_track_node_path) if anim_root else null
	if not (run_resolved is Skeleton3D):
		push_error("Wanderer: Run animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(run_track_node_path))
		return

	if remove_walk_root_motion:
		_remove_walk_root_motion(run_animation)

	# BattleIdle - same shape as the Walk merge above (load, find its one
	# real clip by keyframe count, loop it, merge into the same idle_
	# library, then the same post-merge checks) - see enter_battle_stance()/
	# exit_battle_stance() for where this actually gets played.
	var battle_idle_scene := load(BATTLE_IDLE_SCENE_PATH) as PackedScene
	var battle_idle_instance := battle_idle_scene.instantiate()
	var battle_idle_players := battle_idle_instance.find_children("*", "AnimationPlayer", true, false)
	if battle_idle_players.is_empty():
		push_error("Wanderer: battle-idle model has no AnimationPlayer; BattleIdle clip not merged.")
		battle_idle_instance.free()
		return

	var battle_idle_player := battle_idle_players[0] as AnimationPlayer
	var battle_idle_entry := _find_single_animation(battle_idle_player, "battle-idle AnimationPlayer")
	if battle_idle_entry.is_empty():
		battle_idle_instance.free()
		return

	var battle_idle_animation: Animation = battle_idle_entry["animation"]
	battle_idle_animation.loop_mode = Animation.LOOP_LINEAR
	idle_library.add_animation("BattleIdle", battle_idle_animation)
	battle_idle_instance.free()

	if battle_idle_animation.get_track_count() == 0:
		push_error("Wanderer: merged BattleIdle animation has no tracks; clip merge is broken.")
		return

	var battle_idle_track_node_path := NodePath(battle_idle_animation.track_get_path(0).get_concatenated_names())
	var battle_idle_resolved := anim_root.get_node_or_null(battle_idle_track_node_path) if anim_root else null
	if not (battle_idle_resolved is Skeleton3D):
		push_error("Wanderer: BattleIdle animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(battle_idle_track_node_path))
		return

	# DrawSword - same load/find/merge/check shape as BattleIdle above,
	# with one difference: this is a one-shot combat-start transition, not
	# a loop, so its own loop_mode is set to LOOP_NONE explicitly (rather
	# than trusting whatever the FBX import happened to default to) -
	# enter_battle_stance() relies on it actually finishing so the queued
	# BattleIdle that follows can start.
	var draw_sword_scene := load(DRAW_SWORD_SCENE_PATH) as PackedScene
	var draw_sword_instance := draw_sword_scene.instantiate()
	var draw_sword_players := draw_sword_instance.find_children("*", "AnimationPlayer", true, false)
	if draw_sword_players.is_empty():
		push_error("Wanderer: draw-sword model has no AnimationPlayer; DrawSword clip not merged.")
		draw_sword_instance.free()
		return

	var draw_sword_player := draw_sword_players[0] as AnimationPlayer
	var draw_sword_entry := _find_single_animation(draw_sword_player, "draw-sword AnimationPlayer")
	if draw_sword_entry.is_empty():
		draw_sword_instance.free()
		return

	var draw_sword_animation: Animation = draw_sword_entry["animation"]
	draw_sword_animation.loop_mode = Animation.LOOP_NONE
	idle_library.add_animation("DrawSword", draw_sword_animation)
	draw_sword_instance.free()

	if draw_sword_animation.get_track_count() == 0:
		push_error("Wanderer: merged DrawSword animation has no tracks; clip merge is broken.")
		return

	var draw_sword_track_node_path := NodePath(draw_sword_animation.track_get_path(0).get_concatenated_names())
	var draw_sword_resolved := anim_root.get_node_or_null(draw_sword_track_node_path) if anim_root else null
	if not (draw_sword_resolved is Skeleton3D):
		push_error("Wanderer: DrawSword animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(draw_sword_track_node_path))
		return

	# Slash - same load/find/merge/check shape as DrawSword above: a one-
	# shot attack swing (LOOP_NONE), not a loop. Triggered by CardData.
	# battle_animation (see _on_card_played()), not anything here.
	var slash_scene := load(SLASH_SCENE_PATH) as PackedScene
	var slash_instance := slash_scene.instantiate()
	var slash_players := slash_instance.find_children("*", "AnimationPlayer", true, false)
	if slash_players.is_empty():
		push_error("Wanderer: slash model has no AnimationPlayer; Slash clip not merged.")
		slash_instance.free()
		return

	var slash_player := slash_players[0] as AnimationPlayer
	var slash_entry := _find_single_animation(slash_player, "slash AnimationPlayer")
	if slash_entry.is_empty():
		slash_instance.free()
		return

	var slash_animation: Animation = slash_entry["animation"]
	slash_animation.loop_mode = Animation.LOOP_NONE
	idle_library.add_animation("Slash", slash_animation)
	slash_instance.free()

	if slash_animation.get_track_count() == 0:
		push_error("Wanderer: merged Slash animation has no tracks; clip merge is broken.")
		return

	var slash_track_node_path := NodePath(slash_animation.track_get_path(0).get_concatenated_names())
	var slash_resolved := anim_root.get_node_or_null(slash_track_node_path) if anim_root else null
	if not (slash_resolved is Skeleton3D):
		push_error("Wanderer: Slash animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(slash_track_node_path))
		return

	# Brace - same shape again, but LOOP_LINEAR: a held stance rather than
	# a one-shot, played for as long as the Braced status (or any other
	# status carrying a StatusData.battle_animation) stays active on the
	# player. See _on_status_changed().
	var brace_scene := load(BRACE_SCENE_PATH) as PackedScene
	var brace_instance := brace_scene.instantiate()
	var brace_players := brace_instance.find_children("*", "AnimationPlayer", true, false)
	if brace_players.is_empty():
		push_error("Wanderer: brace model has no AnimationPlayer; Brace clip not merged.")
		brace_instance.free()
		return

	var brace_player := brace_players[0] as AnimationPlayer
	var brace_entry := _find_single_animation(brace_player, "brace AnimationPlayer")
	if brace_entry.is_empty():
		brace_instance.free()
		return

	var brace_animation: Animation = brace_entry["animation"]
	brace_animation.loop_mode = Animation.LOOP_LINEAR
	idle_library.add_animation("Brace", brace_animation)
	brace_instance.free()

	if brace_animation.get_track_count() == 0:
		push_error("Wanderer: merged Brace animation has no tracks; clip merge is broken.")
		return

	var brace_track_node_path := NodePath(brace_animation.track_get_path(0).get_concatenated_names())
	var brace_resolved := anim_root.get_node_or_null(brace_track_node_path) if anim_root else null
	if not (brace_resolved is Skeleton3D):
		push_error("Wanderer: Brace animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; clip merge is broken." % str(brace_track_node_path))
		return

# Freezes a Walk clip's Hips position track to its first key's X/Z, leaving
# Y (vertical bob) untouched, so it plays in place even if the Mixamo
# export carried forward locomotion into the root bone.
func _remove_walk_root_motion(walk_animation: Animation) -> void:
	for track_idx in walk_animation.get_track_count():
		if walk_animation.track_get_type(track_idx) != Animation.TYPE_POSITION_3D:
			continue

		var path := walk_animation.track_get_path(track_idx)
		if path.get_subname_count() == 0:
			continue
		var bone_name := String(path.get_subname(path.get_subname_count() - 1))
		if not bone_name.to_lower().contains("hips"):
			continue

		var key_count := walk_animation.track_get_key_count(track_idx)
		if key_count == 0:
			continue
		var base_value: Vector3 = walk_animation.track_get_key_value(track_idx, 0)
		for key_idx in key_count:
			var value: Vector3 = walk_animation.track_get_key_value(track_idx, key_idx)
			walk_animation.track_set_key_value(track_idx, key_idx, Vector3(base_value.x, value.y, base_value.z))

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

# Walks at the enemy's live position until its own contact area starts
# the fight.
func set_move_target_enemy(enemy: FieldEnemy) -> void:
	_move_target_enemy = enemy
	_move_target = enemy.global_position
	_has_move_target = true
	_stuck_timer = 0.0

func clear_move_target() -> void:
	_has_move_target = false
	_move_target_enemy = null
	_stuck_timer = 0.0

func has_move_target() -> bool:
	return _has_move_target

# This frame's walking direction toward the target, or ZERO once it's
# reached (which also clears it) or its enemy is gone.
func _move_target_direction() -> Vector3:
	if not _has_move_target:
		return Vector3.ZERO
	if _move_target_enemy != null:
		if not is_instance_valid(_move_target_enemy):
			clear_move_target()
			return Vector3.ZERO
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

# Called by BattleFeedback once BattleController reports a card hit
# landing on the player. _active_material may be a plain StandardMaterial3D
# (TEXTURED/FLAT) or wanderer_flat.gdshader's ShaderMaterial (POSTERIZED) -
# each needs a different property tweened to read as the same "lerp to
# near-white bone, then back" flash, so this only dispatches; the two
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
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", recoil_position, out_time)
	tween.parallel().tween_property(self, "rotation:x", recoil_tilt, out_time)
	tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", base_position, return_time)
	tween.parallel().tween_property(self, "rotation:x", base_tilt, return_time)

# Same mechanism as FieldEnemy.spawn_sand_puff() (see its own doc),
# duplicated for the same reason play_hit_recoil() above is.
func spawn_sand_puff(particle_count: int, lifetime: float, velocity: float, spread_degrees: float) -> void:
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
	quad_mesh.size = Vector2(0.12, 0.12)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _ground.ground_color
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
	particles.global_position = global_position
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(particles.queue_free)

func play_swing_audio() -> void:
	if _attack_audio != null:
		_attack_audio.play_swing()

# Called by region_field.gd on enemy contact. Tweens into a fixed spacing
# from target along the target->Wanderer ground line, facing target, and
# blends the AnimationPlayer into DrawSword, queuing BattleIdle to follow
# the instant DrawSword's own one-shot playback finishes (AnimationPlayer.
# queue() - not a signal/await, since play() already clears any pending
# queue on its own, which is exactly what makes exit_battle_stance()'s own
# play("Idle") safe to call even mid-DrawSword) — independent of
# _physics_process (and its own dash/move-input handling), which
# RegionField's contact freeze has already stopped by the time this runs.
func enter_battle_stance(target: Node3D, spacing: float, duration: float) -> void:
	if target == null:
		return
	# Contact is where a walk-to-enemy target ends; nothing resumes after.
	clear_move_target()

	var away_from_target := _flatten_normalized(global_position - target.global_position)
	if away_from_target == Vector3.ZERO:
		away_from_target = _forward_from_angle(rotation.y)

	var stance_position := target.global_position + away_from_target * spacing

	# get_height_at() is defined in Ground's own local frame - to_local()
	# converts explicitly rather than assuming Ground sits at the world
	# origin (true today, but not guaranteed). stance_position.x/z here are
	# global (built from target.global_position above, itself always
	# global regardless of parenting), which is what "sampling must use
	# global XZ" requires; to_local() is what turns that into whatever
	# frame get_height_at() actually needs.
	var ground := get_node_or_null(ground_path) as Ground
	var ground_resolved := ground != null
	var terrain_height: float = global_position.y
	if ground_resolved:
		var local_xz: Vector3 = ground.to_local(Vector3(stance_position.x, 0.0, stance_position.z))
		terrain_height = ground.get_height_at(Vector2(local_xz.x, local_xz.z))

	# Same "feet at body floor" convention _apply_continuous_foot_grounding()
	# already establishes for this body: the model's feet sit at body-local
	# Y = model_ground_offset, not body-local Y = 0 - so the body's own
	# global Y has to be the terrain height MINUS that offset for the feet
	# (not the body origin) to actually land on the ground. Same fix
	# region_field.gd already applies to FieldEnemy's spawn placement.
	stance_position.y = terrain_height - model_ground_offset

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

	if _animation_player:
		_animation_player.play("DrawSword", animation_blend_time)
		_animation_player.queue("BattleIdle")

	_switch_sword_mount(_hand_attachment, hand_mount_position, hand_mount_rotation_degrees, duration)

	if _battle_stance_modifier:
		var stance_tween := create_tween()
		stance_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		stance_tween.tween_property(_battle_stance_modifier, "influence", 1.0, duration)

# Called by region_field.gd once the battle overlay resolves (win, lose,
# or escape) - blends back from BattleIdle to the normal field Idle.
# _physics_process's own Idle/Walk switching only fires on movement input,
# which won't happen until the player takes a first step post-fight - this
# is what makes standing still right after a battle read as "back to
# normal" immediately instead of staying frozen on BattleIdle's last pose.
func exit_battle_stance() -> void:
	if _animation_player:
		_animation_player.play("Idle", animation_blend_time)

	_switch_sword_mount(_back_attachment, back_mount_position, back_mount_rotation_degrees, animation_blend_time)

	if _battle_stance_modifier:
		var stance_tween := create_tween()
		stance_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		stance_tween.tween_property(_battle_stance_modifier, "influence", 0.0, animation_blend_time)

# Called by region_field.gd right after BattleOverlay.enter_battle() (the
# only point battle_controller exists to hand over - it's created inside
# that call, not before). Connects the two battle-animation triggers so
# this Wanderer's own swings/held stances react to the actual fight -
# torn down by unbind_battle() at battle end.
func bind_to_battle(controller: BattleController) -> void:
	_battle_controller = controller
	controller.card_played.connect(_on_card_played)
	controller.card_swing.connect(_on_card_swing)
	controller.status_changed.connect(_on_status_changed)

func unbind_battle() -> void:
	if _battle_controller == null:
		return
	if _battle_controller.card_played.is_connected(_on_card_played):
		_battle_controller.card_played.disconnect(_on_card_played)
	if _battle_controller.card_swing.is_connected(_on_card_swing):
		_battle_controller.card_swing.disconnect(_on_card_swing)
	if _battle_controller.status_changed.is_connected(_on_status_changed):
		_battle_controller.status_changed.disconnect(_on_status_changed)
	_battle_controller = null

# BattleController.card_swing fires swing_lead_seconds before the card's
# impact, only for a card with a battle_animation - the blade's whoosh
# (AttackAudio). The impact itself sounds from the enemy (its contact
# sound, on the hit frame - see BattleFeedback._react_to_card_hit()).
func _on_card_swing(_card: CardData) -> void:
	play_swing_audio()

# See CardData.battle_animation's own doc - empty means this card has no
# swing. Queues _resting_battle_animation() rather than a bare "BattleIdle"
# so a card played while a held stance (e.g. Brace) is still active on the
# player doesn't permanently cancel that stance once the swing finishes.
func _on_card_played(card: CardData, _target: FieldEnemy) -> void:
	if card.battle_animation == &"" or _animation_player == null:
		return
	_animation_player.play(card.battle_animation, animation_blend_time)
	_animation_player.queue(_resting_battle_animation())

# See StatusData.battle_animation's own doc. Re-evaluates on every status
# change (a status being applied, ticked, or cleared - e.g. Braced clearing
# via Status.consume_triggered() the instant the player is hit) rather than
# reacting to any one specific status by name.
func _on_status_changed() -> void:
	if _animation_player == null or _battle_controller == null:
		return
	var target := _resting_battle_animation()
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
		if is_on_floor():
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

	if not is_on_floor():
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
	_apply_continuous_foot_grounding(delta)

	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	if _dash_timer <= 0.0 and Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
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

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	_apply_step_up_and_down(delta)

	move_and_slide()

	if move_direction.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, _angle_from_direction(move_direction), rotation_speed * delta)

	var planar_speed := Vector2(velocity.x, velocity.z).length()
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
