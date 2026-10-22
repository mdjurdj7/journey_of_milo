class_name ProbePlay
extends RefCounted

# The probes' wait after a real card play (BattleController.request_play()
# / confirm_target()). A play made while another is in flight, or while
# the Wanderer's Slash is short of its cancel point, is queued and not yet
# committed (BattleController._resolve_play(): _play_queued, not _input_
# locked) - so the wait is for both: the queue to commit (or give the card
# back) and that play to resolve. Untyped against BattleController, which
# names the RunState autoload.

# Whether the last play has committed and resolved: nothing queued and
# input unlocked.
static func is_settled(controller: Node) -> bool:
	return not bool(controller.get("_play_queued")) and not bool(controller.get("_input_locked"))

# Game time, ms and usec: physics steps over the tick rate - the time the
# game's own timers and tweens count. Probes run at --fixed-fps 60 (tools/
# run_probes.sh), where a frame steps 1/60 s however fast it runs, so the
# wall clock (Time.get_ticks_*) says nothing about how far the game has
# got; on the wall clock, physics steps keep real time and this agrees
# with it. One step's resolution (1/60 s).
static func game_msec() -> int:
	return game_usec() / 1000

static func game_usec() -> int:
	return int(Engine.get_physics_frames() * 1000000 / maxi(Engine.physics_ticks_per_second, 1))

# The clock a wait's cap runs on, ms: each call adds the lesser of the game
# time and the wall time since the last, so a cap is never shorter than
# either. Game time alone outruns some of the game's own holds - a kill's
# death hold (BattleController._release_deaths_when_due()) runs on the
# wall clock - and the wall clock alone falls short of game time when the
# frames run slow (two probes at once). For caps, never for a measurement:
# time what the game does with game_msec().
static var _cap_ms: int = 0
static var _cap_game_ms: int = -1
static var _cap_wall_ms: int = -1

static func cap_msec() -> int:
	var game: int = game_msec()
	var wall: int = Time.get_ticks_msec()
	if _cap_game_ms >= 0:
		_cap_ms += mini(game - _cap_game_ms, wall - _cap_wall_ms)
	_cap_game_ms = game
	_cap_wall_ms = wall
	return _cap_ms

# Waits until is_settled() - by cap_msec(), not frames, which run
# unthrottled headless - or until `stop` returns true (a fight that ends
# mid-play), then three frames more for what reacts to it.
static func settle(tree: SceneTree, controller: Node, stop: Callable = Callable(), timeout_ms: int = 10000) -> void:
	var deadline: int = cap_msec() + timeout_ms
	while cap_msec() < deadline:
		await tree.process_frame
		if (stop.is_valid() and bool(stop.call())) or not is_instance_valid(controller) or is_settled(controller):
			break
	for i in 3:
		await tree.process_frame

# Waits, a physics step at a time, until `done` returns true or
# `timeout_sec` has passed (cap_msec()); whether it came true. For a wait
# on the thing itself in place of a fixed timer - the caller still checks
# what it waited for, so a timeout fails there.
static func wait_until(tree: SceneTree, done: Callable, timeout_sec: float) -> bool:
	var deadline: int = cap_msec() + int(timeout_sec * 1000.0)
	while not bool(done.call()):
		if cap_msec() >= deadline:
			return false
		await tree.physics_frame
	return true

# A play's kills seen through: no death still held for its blow
# (BattleController.has_held_deaths() - the hold runs on the wall clock,
# so no game-time timer knows its end), and either the play settled or the
# last enemy is down (a won fight keeps input locked). Waited by
# wait_until().
static func kills_settled(controller: Node) -> bool:
	if bool(controller.call("has_held_deaths")):
		return false
	return is_settled(controller) or (controller.get("enemies") as Array).is_empty()

# Waits for a play's kills (kills_settled()), up to timeout_sec
# (cap_msec()); whether they settled.
static func settle_kills(tree: SceneTree, controller: Node, timeout_sec: float = 8.0) -> bool:
	return await wait_until(tree, func() -> bool: return kills_settled(controller), timeout_sec)

# A fight just opened, ready to play: the opening hold over, nothing in
# flight, and the opening hand landed - no drawn card waiting on its
# launch or still flying in (HandContainer._waiting_slots, _arrival_
# tweens).
static func fight_ready(controller: Node) -> bool:
	if bool(controller.call("is_entry_locked")) or not is_settled(controller):
		return false
	var hand: Node = controller.get("_hand_container")
	return hand == null or ((hand.get("_waiting_slots") as Dictionary).is_empty() and (hand.get("_arrival_tweens") as Dictionary).is_empty())

# Physics steps the battle camera must hold still for settle_frame().
const FRAME_STILL_STEPS := 6

# Waits until the battle frame has settled - the CameraRig under `field`'s
# CameraPivot blended fully in, eased to its fitted pitch, and the camera
# still for FRAME_STILL_STEPS steps running - up to timeout_sec
# (cap_msec()); whether it settled.
static func settle_frame(tree: SceneTree, field: Node, timeout_sec: float = 8.0) -> bool:
	var rig: Node = field.get_node("CameraPivot")
	var camera: Camera3D = rig.get("camera")
	var last: Array[Transform3D] = [camera.global_transform]
	var still: Array[int] = [0]
	return await wait_until(tree, func() -> bool:
		var now: Transform3D = camera.global_transform
		var moved: bool = now.origin.distance_to(last[0].origin) > 0.0005 or not now.basis.is_equal_approx(last[0].basis)
		last[0] = now
		var framed: bool = float(rig.get("_battle_blend")) >= 1.0 and is_equal_approx(float(rig.get("_battle_pitch_now")), float(rig.get("_battle_fit_pitch")))
		still[0] = 0 if moved or not framed else still[0] + 1
		return still[0] >= FRAME_STILL_STEPS, timeout_sec)

# A fight just opened, waited into: its frame settled (settle_frame())
# and the fight ready to play (fight_ready()), up to timeout_sec each
# (cap_msec()); whether both came.
static func settle_fight(tree: SceneTree, field: Node, controller: Node, timeout_sec: float = 8.0) -> bool:
	var framed: bool = await settle_frame(tree, field, timeout_sec)
	var ready: bool = await wait_until(tree, func() -> bool: return fight_ready(controller), timeout_sec)
	return framed and ready

# The cards in `controller`'s hand, as their views.
static func hand_views(controller: Node) -> Array:
	return controller.get("_hand_container").call("_card_views")

# Plays `view` as a player would, whatever it asks for: a hand choice -
# Bide's the first other card, then DONE; Twice Over's and Take In's the
# first card they may take - and a target, the first enemy it may land on
# (BattleController._can_target(), so an intent mark only on an attack
# that will land), a dug-in enemy at its first mound. Then settle(). A look
# (Collateral's) then picks the first card it may play, answered the same
# way, and settles again - or skips, when none can be. A pick of a hand
# card for the top of the draw pile (Weathered Map's) takes the first card
# it may. True once the play
# committed; false, with anything opened closed again, when the controller
# refused it or it had nothing to choose or aim at. `stop`: as settle()'s.
static func play_any(tree: SceneTree, controller: Node, view: CardView, stop: Callable = Callable()) -> bool:
	var played_before: int = int(controller.get("cards_played_this_turn"))
	controller.call("request_play", view)
	if not _answer(controller, view):
		return false
	await settle(tree, controller, stop)
	if is_instance_valid(controller) and bool(controller.call("is_looking")):
		var picked: CardData = null
		for seen: CardData in controller.call("get_look_cards"):
			if bool(controller.call("_look_can_play", seen)):
				picked = seen
				break
		if picked == null:
			controller.call("skip_look")
		else:
			controller.call("pick_look", picked)
			var armed: CardView = controller.call("get_pending_card_view")
			var choosing: CardView = controller.call("get_choosing_card_view")
			var picked_view: CardView = armed if armed != null else choosing
			if picked_view != null:
				_answer(controller, picked_view)
			await settle(tree, controller, stop)
	if is_instance_valid(controller) and bool(controller.call("is_putting_on_top")):
		for other: CardView in hand_views(controller):
			controller.call("toggle_choice", other)
			if not bool(controller.call("is_putting_on_top")):
				break
	# A play that ended the fight can take the controller with it.
	if not is_instance_valid(controller):
		return true
	return int(controller.get("cards_played_this_turn")) > played_before

# What `view`'s play, just requested, asks for: its hand choice, then its
# target. False, with anything opened closed again, when it can't be
# answered.
static func _answer(controller: Node, view: CardView) -> bool:
	var card: CardData = view.card_data
	if controller.call("get_choosing_card_view") == view:
		for other: CardView in hand_views(controller):
			if other == view:
				continue
			controller.call("toggle_choice", other)
			if controller.call("get_choosing_card_view") != view:
				break
		if controller.call("get_choosing_card_view") == view:
			controller.call("confirm_choice")
		if controller.call("get_choosing_card_view") == view:
			controller.call("cancel_choice")
			return false
	if bool(controller.call("is_awaiting_target")):
		var combatants: Dictionary = controller.get("_combatants")
		for enemy: Node in (controller.get("enemies") as Array).duplicate():
			var combatant: Combatant = combatants.get(enemy)
			if combatant == null or not bool(controller.call("_can_target", card, combatant)):
				continue
			var mound: int = combatant.mounds[0] if combatant.dug_in and not combatant.mounds.is_empty() else -1
			controller.call("confirm_target", enemy, mound)
			break
		if bool(controller.call("is_awaiting_target")):
			controller.call("cancel_target")
			return false
	return true

# Starts a fight with `target` the way its contact Area would - the
# Wanderer put just outside its contact radius first, so only this call
# starts it - and waits it ready (settle_fight()). The BattleController,
# or null when none opened.
static func start_fight(tree: SceneTree, field: Node, target: Node3D, timeout_sec: float = 8.0) -> Node:
	var wanderer: Node3D = field.get_node("Wanderer") as Node3D
	var reach: float = float(target.get("contact_radius")) + 0.6
	var away: Vector3 = wanderer.global_position - target.global_position
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3.RIGHT
	wanderer.global_position = target.global_position + away.normalized() * reach
	await tree.physics_frame
	field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await tree.physics_frame
	var layer: Node = field.get_node("BattleLayer")
	if layer.get_child_count() == 0:
		return null
	var controller: Node = layer.get_child(0).get("battle_controller")
	await settle_fight(tree, field, controller, timeout_sec)
	return controller
