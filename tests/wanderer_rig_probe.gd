extends SceneTree

# Headless regression probe for the Wanderer's rig (wanderer.gd: MODEL_
# SCENE_PATH, _scale_and_ground_model(), _merge_clips()/_transfer_clip(),
# the sword's mounts and their frames). Loads the real region scene on
# floor 1 and checks, in order:
#
#   model  - the body is wanderer_v3.glb, target_height tall (get_head_
#            height()), toes ahead of the heels (he faces his forward)
#   clips  - Idle, Walk, Run, BattleIdle, DrawSword, Slash and Brace are
#            merged, with their loop modes; every bone track resolves to
#            a bone on the model's skeleton; BattleIdle is the glb's own
#            battle_idle_breathe and Slash its slash (their tracks,
#            unconverted); Slash is 32 frames, lands on its contact frame
#            (get_clip_contact_time(), Blender frame 10) and ends on
#            BattleIdle's first pose, so the blend back is seamless
#   lunge  - the glb's Slash steps his model slash_lunge_distance ahead,
#            arriving on the contact frame, holds there through the
#            hit-stop, and is home again after
#   stop   - Slash's contact (card_impact) stops his clip for
#            slash_hitstop_time, then it plays on; an enemy held for it
#            (FieldEnemy.hold_for()) keeps a recoil started inside it
#            still until it ends
#   poses  - each clip but BattleIdle, sampled through its length, stands
#            him up (head over hips over toes) on the new rig's own bone
#            lengths
#   ground - with his processing off, as the battle freeze leaves it,
#            BattleIdle after Idle still grounds him: his lower toe joint
#            settles model_ground_offset over the sand under him
#   sword  - on his back in Idle and in his right hand's frame in
#            BattleIdle, sword_length long and uniformly scaled (the hand
#            frame strips any bone scale in the pose); in BattleIdle its
#            point is above the sand under his feet - nothing about which
#            way it points, so any battle pose passes
#   fight  - in a real fight with floor 1's Sputter (HP raised so nothing
#            dies), through BattleController.request_play()/confirm_
#            target(): a Slash plays to its last frame through the status
#            change its own resolution ends with, then BattleIdle takes
#            over; a second Slash confirmed 0.45 s after the first waits
#            for the first to reach slash_cancel_time before its play
#            starts (not before 0.75 s), and lands on its own contact
#            frame from there
#
# Until the fight, the Wanderer's own _physics_process is held off
# (process_mode disabled, as the battle freeze does) so it doesn't put
# Idle back; the model under him keeps playing, as it does in a fight.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/wanderer_rig_probe.gd
#
# Exit code 0 = every check passed. Untyped against the project's own
# classes (get()/call() only), for the autoload reason kill_order_probe.
# gd's own header gives.

const REGION_SCENE_PATH := "res://field/region_field.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const MODEL_SCENE_PATH := "res://assets/models/wanderer/wanderer_v3.glb"
const SPUTTER_PATH := "res://battle/rules/enemies/sputter.tres"
const FIGHT_HP := 999
# The fight's second Slash is confirmed this long after the first (real
# seconds), and must not start before CANCEL_S.
const SECOND_PLAY_AT_S := 0.45
const CANCEL_S := 0.75
# Frame slack on the fight's timings (seconds).
const FIGHT_SLACK_S := 0.05
# A card that swings Slash (battle_animation), for the lunge.
const SLASH_CARD_PATH := "res://cards/data/slash.tres"
const SAFETY_SECONDS := 120.0
const LOAD_FRAMES := 30
const POSE_FRAMES := 4
const HEIGHT_LIMIT_M := 0.01
const SWORD_LIMIT_M := 0.01
const BONE_LENGTH_LIMIT_M := 0.002
# How long grounding gets to ease onto a new clip, and how close the toe
# joint must then sit to model_ground_offset over the sand (metres).
const GROUND_SETTLE_SECONDS := 1.0
const GROUND_LIMIT_M := 0.005
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
# The glb's slash: its contact frame, Blender frame 10 at 24 fps; its
# last pose against BattleIdle's first (degrees, worst bone); the lunge's
# reach at contact and its home after (metres).
const SLASH_CONTACT_S := 10.0 / 24.0
const SLASH_LENGTH_S := 32.0 / 24.0
# How still "still" is through a hit-stop: the clip's playhead (seconds)
# and an enemy's position (metres).
const STOP_STILL_S := 0.0001
const STOP_STILL_M := 0.0001
const SLASH_SEAM_LIMIT_DEG := 1.0
const LUNGE_REACH_LIMIT_M := 0.03
const LUNGE_HOME_LIMIT_M := 0.001
const LOOPING: Array[String] = ["Idle", "Walk", "Run", "BattleIdle"]
const ONE_SHOTS: Array[String] = ["DrawSword", "Slash", "Brace"]
const POSED: Array[String] = ["Idle", "Walk", "Run", "DrawSword", "Slash", "Brace"]
# Bones whose rest length a carried clip must keep (parent -> child), by
# name after the rig's prefix (_bone()).
const LENGTH_BONES: Array[String] = ["RightForeArm", "RightHand", "LeftLeg", "LeftFoot", "Head"]

var _failures: int = 0
var _field: Node3D = null
var _wanderer: Node3D = null
var _skeleton: Skeleton3D = null
var _player: AnimationPlayer = null
# The fight's spies, written by signal handlers (lambdas capture locals by
# value, so these are members): status changes seen mid-Slash; each
# card_played and card_impact's real time (ms) and Slash's playhead at
# it; the playhead the poll saw last.
var _status_mid_slash: int = 0
var _played_ms: Array[int] = []
var _played_from: Array[float] = []
var _impact_ms: Array[int] = []
var _impact_at: Array[float] = []
var _last_slash_pos: float = -1.0

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
		var heel: Vector3 = _bone_world("%sFoot" % side)
		var toe: Vector3 = _bone_world("%sToeBase" % side)
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
	# and added to: its battle_idle_breathe, key for key, is what BattleIdle
	# plays, looping, and its slash is Slash; battle_idle (held) stays
	# beside them as the fallback.
	var fresh := ResourceLoader.load(MODEL_SCENE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE_DEEP) as PackedScene
	var source: Node = fresh.instantiate()
	var source_player := source.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	var own_names: Array[String] = []
	var own: Animation = null
	var own_slash: Animation = null
	for library_name in source_player.get_animation_library_list():
		var library := source_player.get_animation_library(library_name)
		for animation_name in library.get_animation_list():
			own_names.append(String(animation_name))
			if animation_name == &"battle_idle_breathe":
				own = library.get_animation(animation_name)
			elif animation_name == &"slash":
				own_slash = library.get_animation(animation_name)
	source.free()
	own_names.sort()
	_check(own_names == ["battle_idle", "battle_idle_breathe", "slash"], "the glb carries battle_idle, battle_idle_breathe and slash (%s)" % [own_names])
	if own != null and _player.has_animation("BattleIdle"):
		_check(_clip_text(_player.get_animation("BattleIdle")) == _clip_text(own), "BattleIdle is battle_idle_breathe, track for track and key for key")
	if own_slash != null and _player.has_animation("Slash"):
		_check(_clip_text(_player.get_animation("Slash")) == _clip_text(own_slash), "Slash is the glb's slash, track for track and key for key")
	if _player.has_animation("Slash"):
		var slash_length: float = _player.get_animation("Slash").length
		_check(absf(slash_length - SLASH_LENGTH_S) <= 0.001, "Slash is 32 frames, %.4f s (%.4f s)" % [slash_length, SLASH_LENGTH_S])
	var contact: float = float(_wanderer.call("get_clip_contact_time", &"Slash"))
	_check(absf(contact - SLASH_CONTACT_S) <= 0.001, "Slash lands on its contact frame, %.4f s in (frame 10 = %.4f s)" % [contact, SLASH_CONTACT_S])
	if _player.has_animation("Slash") and _player.has_animation("BattleIdle"):
		await _pose("BattleIdle", 0.0)
		var idle_pose: Array[Quaternion] = _bone_rotations()
		await _pose("Slash", _player.get_animation("Slash").length)
		var slash_end: Array[Quaternion] = _bone_rotations()
		var worst_deg := 0.0
		for bone in idle_pose.size():
			worst_deg = maxf(worst_deg, rad_to_deg(idle_pose[bone].angle_to(slash_end[bone])))
		_check(worst_deg <= SLASH_SEAM_LIMIT_DEG, "Slash ends on BattleIdle's first pose (worst bone %.3f deg)" % worst_deg)

	print("\n=== lunge")
	await _pose("BattleIdle", 0.0)
	forward = -_wanderer.global_transform.basis.z
	var home: Vector3 = model.global_position
	var lunge_card: Resource = load(SLASH_CARD_PATH)
	_wanderer.call("_on_card_played", lunge_card, null)
	await create_timer(contact).timeout
	var reach: Vector3 = model.global_position - home
	var distance: float = float(_wanderer.get("slash_lunge_distance"))
	_check(absf(reach.dot(forward) - distance) <= LUNGE_REACH_LIMIT_M and Vector2(reach.x, reach.z).length() <= distance + LUNGE_REACH_LIMIT_M, "on the contact frame his model is %.3f m ahead (slash_lunge_distance %.2f)" % [reach.dot(forward), distance])
	var stop: float = float(_wanderer.get("slash_hitstop_time"))
	await create_timer(stop * 0.5).timeout
	var held: Vector3 = model.global_position - home
	_check(absf(held.dot(forward) - distance) <= LUNGE_REACH_LIMIT_M, "halfway through the hit-stop it is still %.3f m ahead" % held.dot(forward))
	await create_timer(stop * 0.5 + float(_wanderer.get("slash_lunge_return_time")) + 0.2).timeout
	var back: Vector3 = model.global_position - home
	_check(Vector2(back.x, back.z).length() <= LUNGE_HOME_LIMIT_M, "and home after (%.4f m off)" % Vector2(back.x, back.z).length())

	print("\n=== stop")
	_check(absf(stop - 0.07) <= 0.0001, "slash_hitstop_time is %.3f s in region_field.tscn (0.07)" % stop)
	_check(absf(float(_wanderer.call("get_card_hitstop_time", lunge_card)) - stop) <= 0.0001, "the Slash card's blow holds for slash_hitstop_time")
	_player.play("Slash", 0.0)
	_player.seek(contact, true)
	await process_frame
	var speed: float = _player.speed_scale
	_wanderer.call("_on_card_impact", lunge_card)
	var at_contact: float = _player.current_animation_position
	await create_timer(stop * 0.5).timeout
	_check(absf(_player.current_animation_position - at_contact) <= STOP_STILL_S, "his clip holds on contact (%.4f s -> %.4f s)" % [at_contact, _player.current_animation_position])
	await create_timer(stop * 0.5 + 0.1).timeout
	_check(_player.speed_scale == speed and _player.current_animation_position > at_contact + 0.05, "and plays on after (speed %.2f, at %.4f s)" % [_player.speed_scale, _player.current_animation_position])
	var enemy: Node3D = get_nodes_in_group("enemies")[0] as Node3D
	var enemy_home: Vector3 = enemy.global_position
	enemy.call("hold_for", stop)
	enemy.call("play_hit_recoil", -forward, 0.3, 0.0, 0.08, 0.25)
	await create_timer(stop * 0.5).timeout
	_check(enemy.global_position.distance_to(enemy_home) <= STOP_STILL_M, "an enemy held for it keeps its recoil still through the stop (%.4f m)" % enemy.global_position.distance_to(enemy_home))
	await create_timer(stop * 0.5 + 0.06).timeout
	_check(enemy.global_position.distance_to(enemy_home) > 0.05, "and recoils after (%.3f m)" % enemy.global_position.distance_to(enemy_home))
	await create_timer(0.4).timeout

	print("\n=== poses")
	for clip in POSED:
		if not _player.has_animation(clip):
			continue
		var length: float = _player.get_animation(clip).length
		var upright := true
		var head_floor: float = BRACE_HEAD_OVER_HIPS_M if clip == "Brace" else UPRIGHT_HEAD_OVER_HIPS_M
		var hips_floor: float = BRACE_HIPS_OVER_TOE_M if clip == "Brace" else UPRIGHT_HIPS_OVER_TOE_M
		var worst_length := 0.0
		for s in SAMPLES:
			await _pose(clip, length * float(s) / float(SAMPLES))
			var head: Vector3 = _bone_world("Head")
			var hips: Vector3 = _bone_world("Hips")
			var toe_y: float = minf(_bone_world("LeftToeBase").y, _bone_world("RightToeBase").y)
			if head.y - hips.y < head_floor or hips.y - toe_y < hips_floor:
				upright = false
			for bone_name in LENGTH_BONES:
				var bone: int = _bone(bone_name)
				var parent: int = _skeleton.get_bone_parent(bone)
				var posed: float = (_skeleton.get_bone_global_pose(bone).origin - _skeleton.get_bone_global_pose(parent).origin).length()
				var rest: float = (_skeleton.get_bone_global_rest(bone).origin - _skeleton.get_bone_global_rest(parent).origin).length()
				worst_length = maxf(worst_length, absf(posed - rest) * float(_wanderer.get("_skeleton_scale_factor")))
		_check(upright, "%s stands him up through its length" % clip)
		_check(worst_length <= BONE_LENGTH_LIMIT_M, "%s keeps the rig's bone lengths (worst %.4f m)" % [clip, worst_length])

	print("\n=== ground")
	await _pose("Idle", 0.0)
	await _pose("BattleIdle", 0.0)
	await create_timer(GROUND_SETTLE_SECONDS).timeout
	var offset: float = float(_wanderer.get("model_ground_offset"))
	var toe_lift: float = minf(_bone_world("LeftToeBase").y, _bone_world("RightToeBase").y) - _wanderer.global_position.y
	_check(absf(toe_lift - offset) <= GROUND_LIMIT_M, "in BattleIdle with his processing off, his lower toe joint sits %.4f m over the sand (model_ground_offset %.3f)" % [toe_lift, offset])

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
	var raw: AABB = _wanderer.get("_sword_raw_aabb")
	var axis: int = 0
	for a in 3:
		if raw.size[a] > raw.size[axis]:
			axis = a
	var tip_local: Vector3 = raw.position + raw.size * 0.5
	tip_local[axis] = raw.position[axis] if bool(_wanderer.get("grip_axis_flip")) else raw.end[axis]
	var tip: Vector3 = (sword.get_node("SwordMesh") as Node3D).global_transform * tip_local
	# The sand under him is his body origin; his toe joints ride
	# model_ground_offset above it, inside the boots.
	var ground_y: float = _wanderer.global_position.y
	print("sword: grip %s, tip %s" % [sword.global_position, tip])
	_check(tip.y > ground_y, "its point is above the sand (%.3f m over it)" % (tip.y - ground_y))

	print("\n=== fight")
	_wanderer.process_mode = Node.PROCESS_MODE_INHERIT
	for node in get_nodes_in_group("enemies"):
		(node as Node).process_mode = Node.PROCESS_MODE_INHERIT
	var controller: Node = await _start_fight()
	if controller != null:
		await _check_slash_plays_out(controller)
		await _check_cancel_window(controller)

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

# A fight with floor 1's Sputter, started through RegionField's contact
# handler (as armored_contact_probe does), every enemy at FIGHT_HP and the
# hand empty; null (a failure) if none starts.
func _start_fight() -> Node:
	var target: Node3D = _fight_enemy()
	if target == null:
		_check(false, "floor 1 has a Sputter to fight")
		return null
	_wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	_check(overlay != null, "a fight starts")
	if overlay == null:
		return null
	var controller: Node = overlay.get("battle_controller")
	for combatant: Object in (controller.get("_combatants") as Dictionary).values():
		combatant.set("max_hp", FIGHT_HP)
		combatant.set("hp", FIGHT_HP)
	controller.get("deck").call("discard_hand")
	controller.connect("status_changed", func() -> void:
		if _player.current_animation == "Slash":
			_status_mid_slash += 1)
	controller.connect("card_played", func(_card: Resource, _target: Node) -> void:
		_played_ms.append(Time.get_ticks_msec())
		_played_from.append(_last_slash_pos))
	controller.connect("card_impact", func(_card: Resource) -> void:
		_impact_ms.append(Time.get_ticks_msec())
		_impact_at.append(_player.current_animation_position if _player.current_animation == "Slash" else -1.0))
	# The fight's opening (DrawSword, the camera) settles first.
	await create_timer(1.5).timeout
	return controller

func _fight_enemy() -> Node3D:
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == SPUTTER_PATH:
			return node as Node3D
	return null

# One Slash, alone: its resolution's status change comes while it is still
# swinging, and it plays to its last frame before BattleIdle takes over.
func _check_slash_plays_out(controller: Node) -> void:
	var view: Object = await _deal(controller)
	(controller.get("player") as Object).set("energy", 3)
	_status_mid_slash = 0
	controller.call("request_play", view)
	controller.call("confirm_target", _fight_enemy())
	var length: float = _player.get_animation("Slash").length
	var furthest: float = -1.0
	var start: int = Time.get_ticks_msec()
	while _player.current_animation != "Slash" and Time.get_ticks_msec() - start < 1000:
		await process_frame
	while _player.current_animation == "Slash" and Time.get_ticks_msec() - start < 4000:
		furthest = maxf(furthest, _player.current_animation_position)
		await process_frame
	_check(_status_mid_slash > 0, "its resolution's status change comes mid-Slash (%d)" % _status_mid_slash)
	_check(furthest >= length - FIGHT_SLACK_S, "a lone Slash plays to its last frame through it (%.3f of %.3f s)" % [furthest, length])
	_check(_player.current_animation == "BattleIdle", "then BattleIdle takes over (%s)" % _player.current_animation)
	await _settle(controller)

# Two Slashes, the second confirmed SECOND_PLAY_AT_S after the first: it
# waits for the first's cancel point, then lands on its own contact frame.
func _check_cancel_window(controller: Node) -> void:
	var first: Object = await _deal(controller)
	var second: Object = await _deal(controller)
	(controller.get("player") as Object).set("energy", 3)
	_played_ms.clear()
	_played_from.clear()
	_impact_ms.clear()
	_impact_at.clear()
	_last_slash_pos = -1.0
	var enemy: Node3D = _fight_enemy()
	controller.call("request_play", first)
	controller.call("confirm_target", enemy)
	var start: int = Time.get_ticks_msec()
	var asked: bool = false
	var queued: bool = false
	while (_played_ms.size() < 2 or _impact_ms.size() < 2) and Time.get_ticks_msec() - start < 4000:
		_last_slash_pos = _player.current_animation_position if _player.current_animation == "Slash" else -1.0
		if not asked and Time.get_ticks_msec() - start >= int(SECOND_PLAY_AT_S * 1000.0):
			asked = true
			controller.call("request_play", second)
			controller.call("confirm_target", enemy)
			queued = bool(controller.get("_play_queued"))
		await process_frame
	var cancel: float = float(_wanderer.get("slash_cancel_time"))
	var contact: float = float(_wanderer.call("get_clip_contact_time", &"Slash"))
	_check(absf(cancel - CANCEL_S) <= 0.0001, "slash_cancel_time is %.3f s in region_field.tscn (0.75)" % cancel)
	_check(queued, "a second Slash confirmed %.2f s in is taken and waits" % SECOND_PLAY_AT_S)
	_check(_played_ms.size() == 2 and _impact_ms.size() == 2, "both Slashes play and land (%d played, %d impacts)" % [_played_ms.size(), _impact_ms.size()])
	if _played_ms.size() < 2 or _impact_ms.size() < 2:
		return
	var second_at: float = (_played_ms[1] - _played_ms[0]) / 1000.0
	_check(second_at >= CANCEL_S, "the second starts %.3f s after the first, not before %.2f s" % [second_at, CANCEL_S])
	_check(_played_from[1] >= cancel - FIGHT_SLACK_S, "the first swing had reached its cancel point (%.3f s, slash_cancel_time %.3f)" % [_played_from[1], cancel])
	var second_impact: float = (_impact_ms[1] - _played_ms[1]) / 1000.0
	_check(absf(second_impact - contact) <= FIGHT_SLACK_S, "its hit lands %.3f s after its own start (contact %.4f s)" % [second_impact, contact])
	_check(absf(_impact_at[1] - contact) <= FIGHT_SLACK_S, "on its own frame 10: Slash is %.3f s in at the hit" % _impact_at[1])
	await _settle(controller)

# A fresh Slash card drawn into the hand; its view.
func _deal(controller: Node) -> Object:
	var card: Resource = (load(SLASH_CARD_PATH) as Resource).duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	for view: Object in controller.get("_hand_container").call("_card_views"):
		if view.get("card_data") == card:
			return view
	return null

# The play resolved, the swing over and BattleIdle back.
func _settle(controller: Node) -> void:
	var start: int = Time.get_ticks_msec()
	while (bool(controller.get("_input_locked")) or bool(controller.get("_play_queued")) or _player.current_animation != "BattleIdle") and Time.get_ticks_msec() - start < 4000:
		await process_frame
	await create_timer(0.3).timeout

# Every bone's posed rotation, in bone order.
func _bone_rotations() -> Array[Quaternion]:
	var rotations: Array[Quaternion] = []
	for bone in _skeleton.get_bone_count():
		rotations.append(_skeleton.get_bone_pose_rotation(bone))
	return rotations

# Every track's path and every key, as text - two clips with the same text
# play the same.
func _clip_text(animation: Animation) -> String:
	var text := "%d tracks %.4f s;" % [animation.get_track_count(), animation.length]
	for track in animation.get_track_count():
		text += str(animation.track_get_path(track))
		for key in animation.track_get_key_count(track):
			text += str(animation.track_get_key_value(track, key))
	return text

# The model's bone named name after the rig's prefix (mixamorig_,
# smartrig_ ...), -1 if none.
func _bone(name: String) -> int:
	for bone in _skeleton.get_bone_count():
		if _skeleton.get_bone_name(bone).ends_with("_" + name):
			return bone
	return -1

func _bone_world(name: String) -> Vector3:
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_bone(name)).origin

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
