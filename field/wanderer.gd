extends CharacterBody3D
class_name Wanderer

const IDLE_SCENE_PATH := "res://assets/models/wanderer/wanderer_idle.fbx"
const WALK_SCENE_PATH := "res://assets/models/wanderer/wanderer_walking.fbx"
const BATTLE_IDLE_SCENE_PATH := "res://assets/models/wanderer/wanderer_battle_idle.fbx"
const DRAW_SWORD_SCENE_PATH := "res://assets/models/wanderer/wanderer_battle_start_draw_sword.fbx"
const ALBEDO_TEXTURE_PATH := "res://assets/models/wanderer/wanderer_albedo.png"
const FLAT_SHADER_PATH := "res://field/wanderer_flat.gdshader"

@export var move_speed: float = 4.5
@export var acceleration: float = 14.0
@export var rotation_speed: float = 10.0
@export var gravity: float = 12.0
@export var dash_distance: float = 6.0
@export var dash_duration: float = 0.2
@export var dash_cooldown: float = 1.0
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

var _model: Node3D = null
var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _camera: Camera3D
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

# Cached once by _find_grounding_bones() so _apply_continuous_foot_
# grounding() never does a name lookup or a skeleton scan - just two
# pose reads by index, every physics frame.
var _grounding_skeleton: Skeleton3D = null
var _grounding_bone_indices: Array[int] = []

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

# One shared material for the whole model, applied via material_override
# on every MeshInstance3D under it. Which material depends on shading_
# mode (see that export's own doc); TEXTURED/POSTERIZED both fall back to
# the flat charcoal material if their own asset (texture and/or shader)
# fails to load (each guarded and push_warning'd separately below), so a
# missing/not-yet-imported asset degrades to a solid color instead of an
# invisible or shaderless model. Re-run whenever shading_mode's setter
# fires, so this always reflects the current mode - not just at _ready().
func _apply_model_material(model: Node3D) -> void:
	var material: Material = null
	match shading_mode:
		ShadingMode.TEXTURED:
			material = _build_textured_material()
		ShadingMode.POSTERIZED:
			material = _build_posterized_material()
		ShadingMode.FLAT:
			material = null
	if material == null:
		material = _build_flat_material()
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = material

# Meshy's own painted colors, no posterizing - same "roughness 1,
# specular 0" shape every other Wanderer/FieldEnemy material already uses.
func _build_textured_material() -> StandardMaterial3D:
	var texture := load(ALBEDO_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("Wanderer: albedo texture failed to load (%s); using the flat charcoal fallback material." % ALBEDO_TEXTURE_PATH)
		return null
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.roughness = 1.0
	material.metallic_specular = 0.0
	return material

func _build_posterized_material() -> ShaderMaterial:
	var texture := load(ALBEDO_TEXTURE_PATH) as Texture2D
	if texture == null:
		push_warning("Wanderer: albedo texture failed to load (%s); using the flat charcoal fallback material." % ALBEDO_TEXTURE_PATH)
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
	print("Wanderer: applied posterized material - texture=%s tone_count=%d tone_dark=%s tone_mid=%s tone_light=%s" % [ALBEDO_TEXTURE_PATH, tone_count, tone_dark, tone_mid, tone_light])
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

# Called by region_field.gd once the battle overlay resolves (win, lose,
# or escape) - blends back from BattleIdle to the normal field Idle.
# _physics_process's own Idle/Walk switching only fires on movement input,
# which won't happen until the player takes a first step post-fight - this
# is what makes standing still right after a battle read as "back to
# normal" immediately instead of staying frozen on BattleIdle's last pose.
func exit_battle_stance() -> void:
	if _animation_player:
		_animation_player.play("Idle", animation_blend_time)

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

	move_and_slide()

	if move_direction.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, _angle_from_direction(move_direction), rotation_speed * delta)

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if use_animation_tree:
		if _animation_tree:
			_animation_tree.set("parameters/blend_position", clampf(planar_speed, 0.0, move_speed))
	elif _animation_player:
		var next_animation := "Walk" if planar_speed > walk_speed_threshold else "Idle"
		if _animation_player.current_animation != next_animation:
			_animation_player.play(next_animation, animation_blend_time)
