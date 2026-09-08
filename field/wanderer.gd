extends CharacterBody3D

const IDLE_SCENE_PATH := "res://assets/models/wanderer_placeholder_idle.fbx"
const WALK_SCENE_PATH := "res://assets/models/wanderer_placeholder_walking.fbx"

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

var _animation_player: AnimationPlayer
var _animation_tree: AnimationTree
var _camera: Camera3D
var _dash_timer: float = 0.0
var _dash_cooldown_timer: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO

func _ready() -> void:
	_camera = get_node_or_null(camera_path) as Camera3D

	var model := (load(IDLE_SCENE_PATH) as PackedScene).instantiate()
	add_child(model)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	_animation_player = players[0] as AnimationPlayer if not players.is_empty() else null

	_merge_placeholder_clips(_animation_player)
	if use_animation_tree:
		_build_animation_tree()
	elif _animation_player:
		_animation_player.play("Idle")

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

func _physics_process(delta: float) -> void:
	_dash_cooldown_timer = maxf(_dash_cooldown_timer - delta, 0.0)

	var move_dir: Vector3

	if _dash_timer > 0.0:
		# Ignore movement input entirely for the dash's duration; velocity is
		# fixed to the direction captured when the dash started.
		_dash_timer -= delta
		move_dir = _dash_direction
		var dash_speed := dash_distance / dash_duration
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
	else:
		var input_dir := Vector2(
			Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
			Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
		)
		if input_dir.length() > 1.0:
			input_dir = input_dir.normalized()

		move_dir = Vector3(input_dir.x, 0.0, -input_dir.y)
		if _camera:
			var camera_basis := _camera.global_transform.basis
			var camera_forward := _flatten_normalized(-camera_basis.z)
			var camera_right := _flatten_normalized(camera_basis.x)
			# input_dir.y is +1 on W (forward - back), so it must be negated here: W has to add camera_forward, not subtract it.
			move_dir = camera_right * input_dir.x + camera_forward * -input_dir.y
			if move_dir.length() > 1.0:
				move_dir = move_dir.normalized()

		if Input.is_action_just_pressed("dash") and _dash_cooldown_timer <= 0.0:
			# Dash in the direction the Wanderer is currently facing, not the
			# raw input, so it always matches what's on screen.
			_dash_direction = Vector3(sin(rotation.y), 0.0, -cos(rotation.y))
			_dash_timer = dash_duration
			_dash_cooldown_timer = dash_cooldown
			move_dir = _dash_direction
			var dash_speed := dash_distance / dash_duration
			velocity.x = _dash_direction.x * dash_speed
			velocity.z = _dash_direction.z * dash_speed
		else:
			var target_velocity := move_dir * move_speed
			velocity.x = move_toward(velocity.x, target_velocity.x, acceleration * delta)
			velocity.z = move_toward(velocity.z, target_velocity.z, acceleration * delta)

	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0.0

	move_and_slide()

	if move_dir.length() > 0.01:
		var target_angle := atan2(move_dir.x, -move_dir.z)
		rotation.y = lerp_angle(rotation.y, target_angle, rotation_speed * delta)

	var planar_speed := Vector2(velocity.x, velocity.z).length()
	if use_animation_tree:
		if _animation_tree:
			_animation_tree.set("parameters/blend_position", clampf(planar_speed, 0.0, move_speed))
	elif _animation_player:
		var next_animation := "Walk" if planar_speed > walk_speed_threshold else "Idle"
		if _animation_player.current_animation != next_animation:
			_animation_player.play(next_animation, animation_blend_time)
