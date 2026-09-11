extends CharacterBody3D
class_name Wanderer

const IDLE_SCENE_PATH := "res://assets/models/wanderer_placeholder_idle.fbx"
const WALK_SCENE_PATH := "res://assets/models/wanderer_placeholder_walking.fbx"
const BATTLE_IDLE_SCENE_PATH := "res://assets/models/wanderer_placeholder_battle_idle.fbx"

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
@export var model_yaw_offset: float = 180.0
# A touch warmer than the crab's own charcoal (see FieldEnemy.model_color)
# so the two read as different things even at a glance, not just "the
# same placeholder grey twice."
@export var wanderer_color: Color = Color(0.16, 0.15, 0.14, 1)

var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _camera: Camera3D
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D

	var model := (load(IDLE_SCENE_PATH) as PackedScene).instantiate() as Node3D
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

	var players := model.find_children("*", "AnimationPlayer", true, false)
	_animation_player = players[0] as AnimationPlayer if not players.is_empty() else null
	# Same reasoning as CameraPivot's own process_mode override - belt and
	# suspenders alongside model.process_mode above, since this is also the
	# node whose own _process actually advances playback.
	if _animation_player:
		_animation_player.process_mode = Node.PROCESS_MODE_ALWAYS

	_merge_placeholder_clips(_animation_player)
	if use_animation_tree:
		_build_animation_tree()
	elif _animation_player:
		_animation_player.play("Idle")

# One shared flat material for the whole placeholder model - same "one
# StandardMaterial3D, roughness 1, specular 0" shape FieldEnemy._spawn_
# model() already uses for the crab, so both placeholders read as the
# same kind of flat-shaded figure while wanderer_color keeps them
# visually distinct from each other.
func _apply_model_material(model: Node3D) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = wanderer_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = material

# Placeholder-only: idle and walk currently ship as two separate Mixamo FBX
# files, each importing with a single clip whose name Godot's FBX importer
# assigns (not "mixamo.com" — don't assume a specific name). This finds
# each player's one clip by count, not by name, and merges them into one
# AnimationPlayer library as "Idle"/"Walk". Remove this once the real model
# ships both clips in one animation file — nothing else should depend on
# how the clips arrived.
func _merge_placeholder_clips(anim_player: AnimationPlayer) -> void:
	if anim_player == null:
		push_error("Wanderer: idle model has no AnimationPlayer; cannot merge placeholder clips.")
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
		push_error("Wanderer: walking placeholder has no AnimationPlayer; Walk clip not merged.")
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
		push_error("Wanderer: merged Walk animation has no tracks; placeholder merge is broken.")
		return

	var anim_root := anim_player.get_node_or_null(anim_player.root_node)
	var track_node_path := NodePath(walk_animation.track_get_path(0).get_concatenated_names())
	var resolved := anim_root.get_node_or_null(track_node_path) if anim_root else null
	if not (resolved is Skeleton3D):
		push_error("Wanderer: Walk animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; placeholder merge is broken." % str(track_node_path))
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
		push_error("Wanderer: battle-idle placeholder has no AnimationPlayer; BattleIdle clip not merged.")
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
		push_error("Wanderer: merged BattleIdle animation has no tracks; placeholder merge is broken.")
		return

	var battle_idle_track_node_path := NodePath(battle_idle_animation.track_get_path(0).get_concatenated_names())
	var battle_idle_resolved := anim_root.get_node_or_null(battle_idle_track_node_path) if anim_root else null
	if not (battle_idle_resolved is Skeleton3D):
		push_error("Wanderer: BattleIdle animation's first track path '%s' does not resolve to a Skeleton3D on the idle model; placeholder merge is broken." % str(battle_idle_track_node_path))
		return

# Freezes a Walk clip's Hips position track to its first key's X/Z, leaving
# Y (vertical bob) untouched, so the placeholder plays in place even if the
# Mixamo export carried forward locomotion into the root bone.
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
# blends the AnimationPlayer to BattleIdle — independent of _physics_process
# (and its own dash/move-input handling), which RegionField's contact
# freeze has already stopped by the time this runs.
func enter_battle_stance(target: Node3D, spacing: float, duration: float) -> void:
	if target == null:
		return

	var away_from_target := _flatten_normalized(global_position - target.global_position)
	if away_from_target == Vector3.ZERO:
		away_from_target = _forward_from_angle(rotation.y)

	var stance_position := target.global_position + away_from_target * spacing
	stance_position.y = global_position.y

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
		_animation_player.play("BattleIdle", animation_blend_time)

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
