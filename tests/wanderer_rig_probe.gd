extends SceneTree

# Headless regression probe for the Wanderer's rig (wanderer.gd: MODEL_
# SCENE_PATH, _scale_and_ground_model(), _merge_clips()/_transfer_clip(),
# the sword's mounts and their frames). Loads the real region scene on
# floor 1 and checks, in order:
#
#   model  - the body is wanderer_v2.glb, target_height tall (get_head_
#            height()), toes ahead of the heels (he faces his forward)
#   clips  - Idle, Walk, Run, BattleIdle, DrawSword, Slash and Brace are
#            merged, with their loop modes; every bone track resolves to
#            a bone on the model's skeleton; BattleIdle is the glb's own
#            battle_idle (its tracks, unconverted), looping
#   poses  - each carried clip, sampled through its length, stands him up
#            (head over hips over toes) on the new rig's own bone lengths
#   sword  - on his back in Idle and in his right hand's frame in
#            BattleIdle, sword_length long and uniformly scaled (the hand
#            frame strips battle_idle's bone scale); in BattleIdle its
#            point is ahead of him, below the grip, and the whole blade
#            stays above the sand under his feet
#   stance - region_field's BattleStanceModifier values are all 0, so
#            BattleIdle shows as authored
#
# The Wanderer's own _physics_process is held off (process_mode disabled,
# as the battle freeze does) so it doesn't put Idle back; the model under
# him keeps playing, as it does in a fight.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/wanderer_rig_probe.gd
#
# Exit code 0 = every check passed. Untyped against the project's own
# classes (get()/call() only), for the autoload reason kill_order_probe.
# gd's own header gives.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const MODEL_SCENE_PATH := "res://assets/models/wanderer/wanderer_v2.glb"
const SAFETY_SECONDS := 120.0
const LOAD_FRAMES := 30
const POSE_FRAMES := 4
const HEIGHT_LIMIT_M := 0.01
const SWORD_LIMIT_M := 0.01
const BONE_LENGTH_LIMIT_M := 0.002
const SAMPLES := 6
# Standing up, per sample: the head at least this far above the hips, the
# hips at least this far above the lower toe (metres).
const UPRIGHT_HEAD_OVER_HIPS_M := 0.4
const UPRIGHT_HIPS_OVER_TOE_M := 0.5
# Brace is a deep guard crouch on both rigs - measured on the old rig
# with its original clip, its lowest is 0.529 m head over hips and 0.327 m
# hips over toe - so it is held to just under that instead.
const BRACE_HEAD_OVER_HIPS_M := 0.50
const BRACE_HIPS_OVER_TOE_M := 0.30
const LOOPING: Array[String] = ["Idle", "Walk", "Run", "BattleIdle"]
const ONE_SHOTS: Array[String] = ["DrawSword", "Slash", "Brace"]
const CARRIED: Array[String] = ["Idle", "Walk", "Run", "DrawSword", "Slash", "Brace"]
# Bones whose rest length a carried clip must keep (parent -> child).
const LENGTH_BONES: Array[String] = ["mixamorig_RightForeArm", "mixamorig_RightHand", "mixamorig_LeftLeg", "mixamorig_LeftFoot", "mixamorig_Head"]

var _failures: int = 0
var _field: Node3D = null
var _wanderer: Node3D = null
var _skeleton: Skeleton3D = null
var _player: AnimationPlayer = null

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	var run_state: Node = root.get_node("RunState")
	run_state.call("new_run", load(STARTING_CHARACTER_PATH))
	run_state.set("current_floor_index", 0)
	run_state.set("run_opening_pending", false)
	run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(_field)
	for i in LOAD_FRAMES:
		await physics_frame
	_wanderer = _field.get_node("Wanderer") as Node3D
	for node in get_nodes_in_group("enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_DISABLED
	_wanderer.process_mode = Node.PROCESS_MODE_DISABLED
	var model: Node3D = _wanderer.get("_model")
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_player = _wanderer.get("_animation_player")

	print("\n=== model")
	_check(model.scene_file_path == MODEL_SCENE_PATH, "the body is %s (%s)" % [MODEL_SCENE_PATH.get_file(), model.scene_file_path])
	var height: float = float(_wanderer.call("get_head_height"))
	var target_height: float = float(_wanderer.get("target_height"))
	_check(absf(height - target_height) <= HEIGHT_LIMIT_M, "he stands %.3f m tall (target %.2f)" % [height, target_height])
	await _pose("Idle", 0.0)
	var forward: Vector3 = -_wanderer.global_transform.basis.z
	for side in ["Left", "Right"]:
		var heel: Vector3 = _bone_world("mixamorig_%sFoot" % side)
		var toe: Vector3 = _bone_world("mixamorig_%sToeBase" % side)
		_check((toe - heel).dot(forward) > 0.03, "%s toes ahead of the heel (%.3f m along his forward)" % [side.to_lower(), (toe - heel).dot(forward)])

	print("\n=== clips")
	for clip in LOOPING + ONE_SHOTS:
		_check(_player.has_animation(clip), "%s is merged" % clip)
	for clip in LOOPING:
		if _player.has_animation(clip):
			_check(_player.get_animation(clip).loop_mode == Animation.LOOP_LINEAR, "%s loops" % clip)
	for clip in ONE_SHOTS:
		if _player.has_animation(clip):
			_check(_player.get_animation(clip).loop_mode == Animation.LOOP_NONE, "%s plays once" % clip)
	var anim_root: Node = _player.get_node(_player.root_node)
	for clip in LOOPING + ONE_SHOTS:
		if not _player.has_animation(clip):
			continue
		var animation: Animation = _player.get_animation(clip)
		var unresolved: Array[String] = []
		for track in animation.get_track_count():
			var path: NodePath = animation.track_get_path(track)
			var node: Node = anim_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			var bone: String = String(path.get_subname(0)) if path.get_subname_count() > 0 else ""
			if node != _skeleton or _skeleton.find_bone(bone) == -1:
				unresolved.append(str(path))
		_check(unresolved.is_empty(), "%s: all %d tracks resolve to a bone (%s)" % [clip, animation.get_track_count(), ", ".join(unresolved.slice(0, 3))])
	# A fresh copy of the glb, past the cache the Wanderer's merge renamed
	# and added to: its one clip, key for key, is what BattleIdle plays.
	var fresh := ResourceLoader.load(MODEL_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var source: Node = fresh.instantiate()
	var source_player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var own_names: Array[String] = []
	var own: Animation = null
	for library_name in source_player.get_animation_library_list():
		var library := source_player.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			own_names.append(String(animation_name))
			own = library.get_animation(animation_name)
	source.free()
	_check(own_names == ["battle_idle"], "the glb carries one clip, battle_idle (%s)" % [own_names])
	if own != null and _player.has_animation("BattleIdle"):
		_check(_clip_text(_player.get_animation("BattleIdle")) == _clip_text(own), "BattleIdle is battle_idle, track for track and key for key")
		_check(own.loop_mode == Animation.LOOP_LINEAR, "battle_idle loops by its own import setting")

	print("\n=== poses")
	for clip in CARRIED:
		if not _player.has_animation(clip):
			continue
		var length: float = _player.get_animation(clip).length
		var upright := true
		var head_floor: float = BRACE_HEAD_OVER_HIPS_M if clip == "Brace" else UPRIGHT_HEAD_OVER_HIPS_M
		var hips_floor: float = BRACE_HIPS_OVER_TOE_M if clip == "Brace" else UPRIGHT_HIPS_OVER_TOE_M
		var worst_length := 0.0
		for s in SAMPLES:
			await _pose(clip, length * float(s) / float(SAMPLES))
			var head: Vector3 = _bone_world("mixamorig_Head")
			var hips: Vector3 = _bone_world("mixamorig_Hips")
			var toe_y: float = minf(_bone_world("mixamorig_LeftToeBase").y, _bone_world("mixamorig_RightToeBase").y)
			if head.y - hips.y < head_floor or hips.y - toe_y < hips_floor:
				upright = false
			for bone_name in LENGTH_BONES:
				var bone: int = _skeleton.find_bone(bone_name)
				var parent: int = _skeleton.get_bone_parent(bone)
				var posed: float = (_skeleton.get_bone_global_pose(bone).origin - _skeleton.get_bone_global_pose(parent).origin).length()
				var rest: float = (_skeleton.get_bone_global_rest(bone).origin - _skeleton.get_bone_global_rest(parent).origin).length()
				worst_length = maxf(worst_length, absf(posed - rest) * float(_wanderer.get("_skeleton_scale_factor")))
		_check(upright, "%s stands him up through its length" % clip)
		_check(worst_length <= BONE_LENGTH_LIMIT_M, "%s keeps the rig's bone lengths (worst %.4f m)" % [clip, worst_length])

	print("\n=== sword")
	var sword: Node3D = _wanderer.get("_sword_root")
	var sword_length: float = float(_wanderer.get("sword_length"))
	await _pose("Idle", 0.0)
	_check(sword.get_parent() == _wanderer.get("_back_frame"), "on his back in the field")
	_check_sword_size(sword, sword_length, "on his back")
	_wanderer.call("_switch_sword_mount", _wanderer.get("_hand_frame"), _wanderer.get("hand_mount_position"), _wanderer.get("hand_mount_rotation_degrees"), 0.0)
	await _pose("BattleIdle", 0.0)
	var hand_frame: Node3D = _wanderer.get("_hand_frame")
	_check(sword.get_parent() == hand_frame and String((hand_frame.get_parent() as BoneAttachment3D).bone_name).ends_with("RightHand"), "in his right hand's frame in BattleIdle")
	_check_sword_size(sword, sword_length, "in his hands")
	var grip: Vector3 = sword.global_position
	var raw: AABB = _wanderer.get("_sword_raw_aabb")
	var axis: int = 0
	for a in 3:
		if raw.size[a] > raw.size[axis]:
			axis = a
	var tip_local: Vector3 = raw.position + raw.size * 0.5
	tip_local[axis] = raw.position[axis] if bool(_wanderer.get("grip_axis_flip")) else raw.end[axis]
	var tip: Vector3 = (sword.get_node("SwordMesh") as Node3D).global_transform * tip_local
	var ground_y: float = minf(_bone_world("mixamorig_LeftToeBase").y, _bone_world("mixamorig_RightToeBase").y)
	var lowest := INF
	for mi_node in sword.find_children("*", "MeshInstance3D", true, false):
		var mi := mi_node as MeshInstance3D
		var box: AABB = mi.get_aabb()
		for c in 8:
			lowest = minf(lowest, (mi.global_transform * box.get_endpoint(c)).y)
	print("sword: grip %s, tip %s, lowest point %.3f m over the toes" % [grip, tip, lowest - ground_y])
	_check((tip - grip).dot(forward) > 0.5, "its point is ahead of him (%.2f m)" % (tip - grip).dot(forward))
	_check(tip.y < grip.y - 0.3, "its point angles down (%.2f m below the grip)" % (grip.y - tip.y))
	_check(lowest > ground_y + 0.02, "the blade stays above the sand (%.3f m)" % (lowest - ground_y))

	print("\n=== stance")
	for value in ["battle_back_leg_degrees", "battle_front_leg_degrees", "battle_pelvis_yaw_degrees"]:
		_check(is_zero_approx(float(_wanderer.get(value))), "%s is 0 (%s)" % [value, _wanderer.get(value)])

	_field.queue_free()
	for i in 5:
		await process_frame
	print("\nwanderer_rig_probe: %s" % ("PASSED" if _failures == 0 else "%d FAILURE(S)" % _failures))
	quit(0 if _failures == 0 else 1)

# Plays clip at `time` and lets the skeleton, its attachments and the
# sword's mount frames update over a few frames.
func _pose(clip: String, time: float) -> void:
	_player.play(clip, 0.0)
	_player.seek(time, true)
	for i in POSE_FRAMES:
		await process_frame
	_player.seek(time, true)
	for i in POSE_FRAMES:
		await process_frame

# Every track's path and every key, as text - two clips with the same text
# play the same.
func _clip_text(animation: Animation) -> String:
	var text := "%d tracks %.4f s;" % [animation.get_track_count(), animation.length]
	for track in animation.get_track_count():
		text += str(animation.track_get_path(track))
		for key in animation.track_get_key_count(track):
			text += str(animation.track_get_key_value(track, key))
	return text

func _bone_world(bone_name: String) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(bone_name)).origin

func _check_sword_size(sword: Node3D, expected: float, label: String) -> void:
	var scale: Vector3 = sword.global_transform.basis.get_scale()
	var raw: AABB = _wanderer.get("_sword_raw_aabb")
	var longest: float = maxf(raw.size.x, maxf(raw.size.y, raw.size.z))
	var length: float = longest * scale.x
	_check(absf(length - expected) <= SWORD_LIMIT_M, "%s: %.3f m long (sword_length %.2f)" % [label, length, expected])
	_check(absf(scale.x - scale.y) <= 0.001 * scale.x and absf(scale.x - scale.z) <= 0.001 * scale.x, "%s: uniformly scaled (%s)" % [label, scale])

func _check(ok: bool, label: String) -> void:
	print(("ok   " if ok else "FAIL ") + label)
	if not ok:
		_failures += 1
