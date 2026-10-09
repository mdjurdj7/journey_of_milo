extends SceneTree

# Headless probe for Devour - the Wanderer's once-per-turn battle action
# (BattleController.devour()): one hand card eaten for 2 HP, Spent for the
# fight and back the next, never played - no energy, no effect, no Toll,
# no HP cost. Both routes: a card armed first (a playable enemy-target
# card, or one that can't be played, armed for Devour alone), or Devour
# first (the pick, then the card). Once a turn, again the next; the heal
# capped at max HP; a Consumed card eaten - or taken by Deny - stays in
# the run. The button under the energy readout: grey, or ink while it is
# a target, in one column with the readout and clear of the hand, resting
# or hovered.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/devour_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
#
# Fight cases load the real region scene and fight floor 1's first enemy
# through RegionField's contact handler, as deny_probe does, driving
# BattleController.request_play() / devour() / confirm_target() /
# cancel_target() / end_turn(), and the overlay's _finish_battle() to
# leave. Untyped against anything that names the RunState autoload.

const CASES := 14
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const RECKONING_PATH := "res://cards/data/reckoning.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const BLOOD_ARC_PATH := "res://cards/data/blood_arc.tres"
const DENY_PATH := "res://cards/data/deny.tres"
const SAMPHIRE_PATH := "res://cards/neutral/samphire.tres"
# Where the log case writes its run, when run_probes.sh hands over no
# folder of this process's own (RunLogger.dir_override()).
const LOG_DIR := "user://devour_probe"
const ENEMY_HP := 999
const MAX_HP := 70
const START_HP := 50
const HEAL := 2
const ESCAPE := 2
const SAFETY_SECONDS := 400.0
# The layout case hovers each card whose resting left edge is within this
# of the bottom-left stack's right edge (a hovered card grows sideways
# too), and waits this long for the hover to settle.
const HOVER_REACH_PX := 60.0
const HOVER_SETTLE_SECONDS := 0.3

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0
var _plays: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")

	await _check_armed_playable()
	await _check_unaffordable_arms()
	await _check_used_blocks_arming()
	await _check_heal_caps()
	await _check_second_devour()
	await _check_next_turn()
	await _check_pick_route()
	await _check_pick_cancel()
	await _check_untargeted_still_plays()
	await _check_deny_pick_unmarked()
	await _check_back_next_fight()
	await _check_deny_samphire()
	await _check_button_states()
	await _check_layout()

	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("devour_probe: PASSED")
		quit(0)
	else:
		print("devour_probe: %d FAILED" % _failures)
		quit(1)

# Armed first, a playable card (Bite Down - a hit and an HP cost): Devour
# lights; eating it heals 2, Spends it unplayed and spends nothing else.
# The run log has the devour line and a heal from "devour".
func _check_armed_playable() -> void:
	var log_dir: String = _open_log()
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var bite: CardData = await _deal(controller, BITE_DOWN_PATH)
		var enemy: Combatant = _enemy_combatant(controller)
		var toll_before: int = player.toll
		controller.call("request_play", _view(controller, bite))
		_expect(bool(controller.call("is_awaiting_target")), "A playable enemy card arms as before")
		_expect(not bool(controller.call("is_armed_for_devour_only")), "...for its enemies, not Devour alone")
		_expect(bool(controller.call("is_devour_lit")), "...and Devour lights as a target")
		controller.call("devour")
		await _settle(controller)
		_expect_eq(player.hp, START_HP + HEAL, "Devoured: 2 HP back")
		_expect_eq(int(_run_state.get("player_hp")), START_HP + HEAL, "...on the run's HP too")
		_expect(not (deck.get("hand") as Array).has(bite), "...out of the hand")
		_expect((deck.get("exhaust_pile") as Array).has(bite), "...into the Spent pile")
		_expect((deck.get("spent_unplayed") as Array).has(bite), "...as Spent unplayed")
		_expect_eq(player.energy, 3, "...no energy spent")
		_expect_eq(enemy.hp, ENEMY_HP, "...no damage dealt")
		_expect_eq(player.toll, toll_before, "...no Toll")
		_expect_eq(int(controller.get("cards_played_this_turn")), 0, "...not counted as played")
		_expect_eq(_plays, 0, "...card_played never fired")
		_expect(not bool(controller.call("is_awaiting_target")), "...nothing armed after")
		_expect(bool(controller.call("is_devour_used")), "...and this turn's Devour is used")
		var devour_line: Dictionary = _log_line(log_dir, "devour", "")
		_expect_eq(str(devour_line.get("card")), "Bite Down", "The run log's devour line names the card")
		_expect_eq(devour_line.get("playable"), true, "...playable")
		_expect_eq(str(devour_line.get("route")), "armed", "...the armed route")
		_expect_eq(int(devour_line.get("hp_before", -1)), START_HP, "...HP before")
		_expect_eq(int(devour_line.get("hp_after", -1)), START_HP + HEAL, "...HP after")
		var heal_line: Dictionary = _log_line(log_dir, "heal", "devour")
		_expect_eq(int(heal_line.get("amount", -1)), HEAL, "...and a heal of 2 from devour")
	RunLogger.set_output_dir("")
	await _teardown()
	_completed += 1

# At 0 energy an unaffordable card arms, dimmed, Devour its only target:
# no enemy is a target, clicking one does nothing, and Devour eats it.
func _check_unaffordable_arms() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		player.energy = 0
		controller.emit_signal("energy_changed", 0)
		await process_frame
		var view: CardView = _view(controller, reckoning)
		controller.call("request_play", view)
		_expect(bool(controller.call("is_awaiting_target")), "At 0 energy, an unaffordable card arms")
		_expect(bool(controller.call("is_armed_for_devour_only")), "...for Devour alone")
		_expect(bool(controller.call("is_devour_lit")), "...Devour lit")
		_expect(is_equal_approx(view.modulate.a, view.unplayable_alpha), "...kept dimmed")
		for i in 3:
			await physics_frame
		_expect((controller.get("_enemy_rects") as Dictionary).is_empty(), "...no enemy is a target")
		_expect(controller.call("get_hovered_enemy") == null, "...none lit")
		controller.call("confirm_target", _field_enemy(controller))
		await process_frame
		_expect(bool(controller.call("is_awaiting_target")), "...clicking an enemy does nothing")
		_expect_eq(_enemy_combatant(controller).hp, ENEMY_HP, "...and hits nothing")
		controller.call("devour")
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(reckoning), "Devoured: Reckoning Spent")
		_expect_eq(player.hp, START_HP + HEAL, "...2 HP back")
		_expect_eq(player.energy, 0, "...at 0 energy still")
	await _teardown()
	_completed += 1

# With Devour used this turn, an unaffordable card can't be armed.
func _check_used_blocks_arming() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var bite: CardData = await _deal(controller, BITE_DOWN_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		controller.call("request_play", _view(controller, bite))
		controller.call("devour")
		await _settle(controller)
		player.energy = 0
		controller.emit_signal("energy_changed", 0)
		await process_frame
		controller.call("request_play", _view(controller, reckoning))
		_expect(not bool(controller.call("is_awaiting_target")), "Devour used: an unaffordable card doesn't arm")
		_expect(not bool(controller.call("is_devour_lit")), "...Devour stays dark")
	await _teardown()
	_completed += 1

# The heal is capped at max HP.
func _check_heal_caps() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		_set_hp(controller, MAX_HP - 1)
		controller.call("request_play", _view(controller, slash))
		controller.call("devour")
		await _settle(controller)
		_expect_eq(player.hp, MAX_HP, "One short of max: the heal stops at max")
		_expect_eq(int(_run_state.get("player_hp")), MAX_HP, "...on the run's HP too")
	await _teardown()
	_completed += 1

# A second Devour in the same turn does nothing: the armed card stays
# armed, in the hand, and no HP comes back.
func _check_second_devour() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var bite: CardData = await _deal(controller, BITE_DOWN_PATH)
		var slash: CardData = await _deal(controller, SLASH_PATH)
		controller.call("request_play", _view(controller, bite))
		controller.call("devour")
		await _settle(controller)
		controller.call("request_play", _view(controller, slash))
		_expect(bool(controller.call("is_awaiting_target")), "After a Devour, a playable card still arms")
		_expect(not bool(controller.call("is_devour_lit")), "...but Devour isn't a target")
		controller.call("devour")
		await _settle(controller)
		_expect((deck.get("hand") as Array).has(slash), "A second Devour: the card stays in the hand")
		_expect(bool(controller.call("is_awaiting_target")), "...still armed")
		_expect_eq(player.hp, START_HP + HEAL, "...no more HP")
		controller.call("devour")
		_expect(not bool(controller.call("is_devour_picking")), "...and with nothing armed, no pick opens")
		controller.call("cancel_target")
	await _teardown()
	_completed += 1

# Devour is back at the next turn's start.
func _check_next_turn() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		var bite: CardData = await _deal(controller, BITE_DOWN_PATH)
		controller.call("request_play", _view(controller, bite))
		controller.call("devour")
		await _settle(controller)
		await _end_turn(controller)
		_expect(bool(controller.call("is_devour_available")), "Next turn: Devour available again")
		_expect(not bool(controller.call("is_devour_used")), "...not used")
		var deck: Object = controller.get("deck")
		var hand: Array = deck.get("hand")
		if hand.is_empty():
			_fail("no hand drawn on the next turn")
		else:
			var card: CardData = hand[0]
			var hp_before: int = player.hp
			controller.call("devour")
			controller.call("request_play", _view(controller, card))
			await _settle(controller)
			_expect((deck.get("exhaust_pile") as Array).has(card), "...and it eats again")
			_expect_eq(player.hp, mini(hp_before + HEAL, player.max_hp), "...for 2 HP")
	await _teardown()
	_completed += 1

# Devour first: the pick lights it and greys End Turn; the card clicked -
# a playable untargeted one (Blood Arc, which would cost 2 HP) or a dimmed
# one - is eaten, never played.
func _check_pick_route() -> void:
	var log_dir: String = _open_log()
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var overlay: Node = _overlay()
		var arc: CardData = await _deal(controller, BLOOD_ARC_PATH)
		controller.call("devour")
		_expect(bool(controller.call("is_devour_picking")), "Devour with nothing armed: the pick opens")
		_expect(bool(controller.call("is_devour_lit")), "...lit")
		_expect(not bool(controller.call("is_awaiting_target")), "...nothing armed, no enemy targeting")
		_expect((overlay.get("end_turn_button") as Button).disabled, "...End Turn greyed")
		controller.call("request_play", _view(controller, arc))
		_expect(not (overlay.get("end_turn_button") as Button).disabled or bool(controller.get("_input_locked")), "...End Turn back once the pick closes")
		await _settle(controller)
		_expect(not (overlay.get("end_turn_button") as Button).disabled, "...and enabled after")
		_expect((deck.get("exhaust_pile") as Array).has(arc), "Picked: Blood Arc devoured")
		_expect_eq(player.hp, START_HP + HEAL, "...2 HP back, its HP cost unpaid")
		_expect_eq(player.energy, 3, "...no energy")
		_expect_eq(_plays, 0, "...never played")
		_expect(not bool(controller.call("is_devour_picking")), "...the pick closed")
		var line: Dictionary = _log_line(log_dir, "devour", "")
		_expect_eq(str(line.get("route")), "pick", "The run log: the pick route")
	RunLogger.set_output_dir("")
	await _teardown()
	# A dimmed card through the pick.
	controller = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		player.energy = 0
		controller.emit_signal("energy_changed", 0)
		await process_frame
		controller.call("devour")
		controller.call("request_play", _view(controller, reckoning))
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(reckoning), "Picked at 0 energy: a dimmed card devoured")
		_expect_eq(player.hp, START_HP + HEAL, "...2 HP back")
	await _teardown()
	_completed += 1

# The pick cancels on Devour again, right-click and Esc, nothing eaten.
func _check_pick_cancel() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var player: Combatant = controller.get("player")
		await _deal(controller, SLASH_PATH)
		controller.call("devour")
		controller.call("devour")
		_expect(not bool(controller.call("is_devour_picking")), "Devour again cancels the pick")
		controller.call("devour")
		var right := InputEventMouseButton.new()
		right.button_index = MOUSE_BUTTON_RIGHT
		right.pressed = true
		controller.call("_unhandled_input", right)
		_expect(not bool(controller.call("is_devour_picking")), "...right-click cancels it")
		controller.call("devour")
		var escape := InputEventKey.new()
		escape.keycode = KEY_ESCAPE
		escape.pressed = true
		controller.call("_unhandled_input", escape)
		_expect(not bool(controller.call("is_devour_picking")), "...Esc cancels it")
		_expect(bool(controller.call("is_devour_available")), "...Devour still unused")
		_expect_eq(player.hp, START_HP, "...nothing eaten")
	await _teardown()
	_completed += 1

# Nothing plays differently: an untargeted playable card still plays on
# one click with Devour available, and a playable enemy card still lands
# on its enemy.
func _check_untargeted_still_plays() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var player: Combatant = controller.get("player")
		var arc: CardData = await _deal(controller, BLOOD_ARC_PATH)
		var slash: CardData = await _deal(controller, SLASH_PATH)
		controller.call("request_play", _view(controller, arc))
		_expect(not bool(controller.call("is_awaiting_target")), "Blood Arc with Devour available: no arming")
		await _settle(controller)
		_expect_eq(_plays, 1, "...played on one click")
		_expect_eq(player.energy, 1, "...for its 2 energy")
		_expect((deck.get("discard_pile") as Array).has(arc) or (deck.get("exhaust_pile") as Array).has(arc), "...to its pile")
		controller.call("request_play", _view(controller, slash))
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect(_enemy_combatant(controller).hp < ENEMY_HP, "Slash armed and aimed still lands")
		_expect(bool(controller.call("is_devour_available")), "...Devour untouched")
	await _teardown()
	_completed += 1

# Deny armed with its pick marked, then devoured: the pick unmarked and
# kept, no one Denied.
func _check_deny_pick_unmarked() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var deck: Object = controller.get("deck")
		var deny: CardData = await _deal(controller, DENY_PATH)
		var reckoning: CardData = await _deal(controller, RECKONING_PATH)
		await _deal(controller, SLASH_PATH)
		controller.call("request_play", _view(controller, deny))
		_expect(_view(controller, reckoning).is_marked(), "Deny armed: Reckoning marked as its pick")
		controller.call("devour")
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(deny), "Deny devoured")
		_expect((deck.get("hand") as Array).has(reckoning), "...Reckoning stays in the hand")
		_expect(not _view(controller, reckoning).is_marked(), "...unmarked")
		_expect(not EnemyTurn.is_denied(_enemy_combatant(controller)), "...no one Denied")
	await _teardown()
	_completed += 1

# A devoured card is back in the deck for the next fight - one from the
# run's deck, and a Consumed one (Samphire) too; a Samphire played still
# leaves the run.
func _check_back_next_fight() -> void:
	var controller: Node = await _start_fight()
	var devoured: CardData = null
	var samphire: CardData = null
	var played: CardData = null
	if controller != null:
		var deck: Object = controller.get("deck")
		var hand: Array = deck.get("hand")
		devoured = hand[0] if not hand.is_empty() else null
		_expect(devoured != null and (_run_state.get("deck") as Array).has(devoured), "The opening hand's first card is the run's own")
		if devoured != null:
			controller.call("devour")
			controller.call("request_play", _view(controller, devoured))
			await _settle(controller)
		await _end_turn(controller)
		samphire = _run_state.call("add_card", load(SAMPHIRE_PATH))
		deck.call("add", samphire)
		played = _run_state.call("add_card", load(SAMPHIRE_PATH))
		deck.call("add", played)
		await process_frame
		controller.call("devour")
		controller.call("request_play", _view(controller, samphire))
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(samphire), "A Samphire devoured")
		controller.call("request_play", _view(controller, played))
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(played), "...another played, Consumed")
		_overlay().call("_finish_battle", ESCAPE)
		await process_frame
	var run_deck: Array = _run_state.get("deck")
	_expect(devoured != null and run_deck.has(devoured), "After the fight the devoured card is in the run's deck")
	_expect(samphire != null and run_deck.has(samphire), "...the devoured Samphire too")
	_expect(played != null and not run_deck.has(played), "...the played Samphire is gone")
	await _teardown()
	controller = await _start_fight(false)
	if controller != null:
		var deck: Object = controller.get("deck")
		var all: Array = []
		all.append_array(deck.get("draw_pile"))
		all.append_array(deck.get("hand"))
		_expect(devoured != null and all.has(devoured), "Next fight: the devoured card is in the deck")
		_expect(samphire != null and all.has(samphire), "...and the devoured Samphire")
	await _teardown()
	_completed += 1

# Deny taking a Samphire Spends it for the fight; the run keeps it.
func _check_deny_samphire() -> void:
	var controller: Node = await _start_fight()
	var samphire: CardData = null
	if controller != null:
		var deck: Object = controller.get("deck")
		var deny: CardData = await _deal(controller, DENY_PATH)
		samphire = _run_state.call("add_card", load(SAMPHIRE_PATH))
		deck.call("add", samphire)
		await process_frame
		controller.call("request_play", _view(controller, deny))
		_expect(_view(controller, samphire).is_marked(), "Deny's pick: the Samphire")
		controller.call("confirm_target", _field_enemy(controller))
		await _settle(controller)
		_expect((deck.get("exhaust_pile") as Array).has(samphire), "...taken to the Spent pile")
		_overlay().call("_finish_battle", ESCAPE)
		await process_frame
	_expect(samphire != null and (_run_state.get("deck") as Array).has(samphire), "After the fight the Samphire Deny took is still in the run's deck")
	await _teardown()
	_completed += 1

# The button: grey with nothing armed, ink while a card is armed and it is
# available, grey with USED once used.
func _check_button_states() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var button: Control = _overlay().get("_devour_button")
		var slash: CardData = await _deal(controller, SLASH_PATH)
		await create_timer(0.4).timeout
		_expect(not bool(button.call("is_lit")), "Nothing armed: the button isn't lit")
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), float(button.get("grey_alpha"))), "...grey")
		controller.call("request_play", _view(controller, slash))
		await create_timer(0.4).timeout
		_expect(bool(button.call("is_lit")), "A card armed: lit")
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), 1.0), "...in full ink")
		controller.call("cancel_target")
		await create_timer(0.4).timeout
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), float(button.get("grey_alpha"))), "Cancelled: grey again")
		controller.call("devour")
		await create_timer(0.4).timeout
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), 1.0), "The pick open: ink")
		controller.call("request_play", _view(controller, slash))
		await _settle(controller)
		_expect(not bool(button.call("is_lit")), "Used: not lit")
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), float(button.get("grey_alpha"))), "...grey")
		_expect(bool(button.get("_used")), "...USED shown")
		var bite: CardData = await _deal(controller, BITE_DOWN_PATH)
		controller.call("request_play", _view(controller, bite))
		await create_timer(0.4).timeout
		_expect(is_equal_approx(float(button.call("get_glyph_alpha")), float(button.get("grey_alpha"))), "Used, a card armed: still grey")
		controller.call("cancel_target")
	await _teardown()
	_completed += 1

# One column with the energy readout - the same left edge, under its pips
# - and clear of every hand card from 5 to 10 in hand, resting or hovered.
func _check_layout() -> void:
	var controller: Node = await _start_fight()
	if controller != null:
		var overlay: Node = _overlay()
		var button: Control = overlay.get("_devour_button")
		var resources: Control = overlay.get("_resources")
		await create_timer(0.4).timeout
		_expect(is_equal_approx(button.global_position.x, resources.global_position.x), "Devour's left edge on the energy readout's (%.1f, %.1f)" % [button.global_position.x, resources.global_position.x])
		_expect(button.global_position.y >= resources.global_position.y + resources.size.y, "...under it")
		var rect: Rect2 = button.get_global_rect()
		print("Devour rect: ", rect)
		await _deal(controller, SLASH_PATH)
		for count in range(1, 11):
			var hand: Array = (controller.get("deck") as Object).get("hand")
			while hand.size() < count:
				await _deal(controller, SLASH_PATH)
				hand = (controller.get("deck") as Object).get("hand")
			await create_timer(0.5).timeout
			if count < 5:
				continue
			var worst: float = INF
			for view: CardView in controller.get("_hand_container").call("_card_views"):
				var card_rect: Rect2 = _rendered_rect(view)
				worst = minf(worst, card_rect.position.y - rect.end.y if card_rect.position.x < rect.end.x else INF)
				_expect(not card_rect.intersects(rect), "%d in hand: a resting card %s clear of Devour %s" % [count, card_rect, rect])
			print("%d in hand: nearest card top under Devour's column is %s px below it" % [count, str(worst)])
			# Hovered too - lifted and grown about its bottom centre - each
			# card that comes near the column: clear of Devour and the
			# energy readout over it.
			var stack: Rect2 = rect.merge(resources.get_global_rect())
			var worst_hovered: float = INF
			for view: CardView in controller.get("_hand_container").call("_card_views"):
				if _rendered_rect(view).position.x > stack.end.x + HOVER_REACH_PX:
					continue
				view.set_hovered(true)
				await create_timer(HOVER_SETTLE_SECONDS).timeout
				var hovered_rect: Rect2 = _rendered_rect(view)
				worst_hovered = minf(worst_hovered, hovered_rect.position.y - rect.end.y)
				_expect(not hovered_rect.intersects(stack), "%d in hand: a hovered card %s clear of Devour and the energy readout %s" % [count, hovered_rect, stack])
				view.set_hovered(false)
				await create_timer(HOVER_SETTLE_SECONDS).timeout
			print("%d in hand: nearest hovered card top under Devour's column is %s px below it" % [count, str(worst_hovered)])
	await _teardown()
	_completed += 1

# --- Helpers ---

func _start_fight(new_run: bool = true) -> Node:
	if new_run:
		_run_state.call("new_run", load(CHARACTER_PATH))
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	if target == null:
		_fail("no enemy on floor 1")
		return null
	var wanderer: Node3D = _field.get_node("Wanderer") as Node3D
	wanderer.global_position = target.global_position + Vector3(1.5, 0.0, 0.0)
	await physics_frame
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var overlay: Node = _overlay()
	if overlay == null:
		_fail("no fight started")
		return null
	var controller: Node = overlay.get("battle_controller")
	for enemy: Combatant in (controller.get("_combatants") as Dictionary).values():
		enemy.max_hp = ENEMY_HP
		enemy.hp = ENEMY_HP
	_set_hp(controller, START_HP)
	var player: Combatant = controller.get("player")
	player.energy = 3
	controller.emit_signal("energy_changed", 3)
	_plays = 0
	controller.connect("card_played", func(_card: CardData, _target: Node) -> void: _plays += 1)
	await process_frame
	return controller

# The fight's HP and the run's, MAX_HP max.
func _set_hp(controller: Node, hp: int) -> void:
	var player: Combatant = controller.get("player")
	player.max_hp = MAX_HP
	player.hp = hp
	_run_state.set("player_max_hp", MAX_HP)
	_run_state.set("player_hp", hp)

func _overlay() -> Node:
	if _field == null or not is_instance_valid(_field):
		return null
	var layer: Node = _field.get_node("BattleLayer")
	return layer.get_child(0) if layer.get_child_count() > 0 else null

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

# A fresh copy of the card at `path`, drawn into the hand - the first
# call of a case discards the opening hand.
func _deal(controller: Node, path: String) -> CardData:
	var deck: Object = controller.get("deck")
	if not bool(controller.get_meta("probe_dealt", false)):
		controller.set_meta("probe_dealt", true)
		deck.call("discard_hand")
		await process_frame
	var card: CardData = (load(path) as CardData).duplicate()
	(deck.get("draw_pile") as Array).append(card)
	deck.call("draw", 1)
	await process_frame
	return card

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in controller.get("_hand_container").call("_card_views"):
		if view.card_data == card:
			return view
	return null

func _field_enemy(controller: Node) -> Node:
	return (controller.get("_combatants") as Dictionary).keys()[0]

func _enemy_combatant(controller: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).values()[0]

# A card's rendered bounds on screen, through its own transform (it is
# scaled about its bottom centre and tilted on the fan).
func _rendered_rect(view: CardView) -> Rect2:
	var xform: Transform2D = view.get_global_transform()
	var rect := Rect2(xform * Vector2.ZERO, Vector2.ZERO)
	for corner in [Vector2(view.size.x, 0.0), Vector2(0.0, view.size.y), view.size]:
		rect = rect.expand(xform * (corner as Vector2))
	return rect

# Until the play or devour has resolved, and a margin after.
func _settle(controller: Node) -> void:
	for i in 600:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(0.5).timeout

func _end_turn(controller: Node) -> void:
	controller.call("end_turn")
	for i in 3000:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	for i in 3:
		await process_frame

# The run log into this process's folder - run_probes.sh's, else
# LOG_DIR - cleared first, so the next run's file is the only one.
func _open_log() -> String:
	var dir: String = RunLogger.dir_override() if not RunLogger.dir_override().is_empty() else LOG_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	for file_name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file_name))
	RunLogger.set_output_dir(dir)
	RunLogger.enabled = true
	return dir

# The last line of event `ev` in the folder's run logs - with `source`
# when one is given (a heal's).
func _log_line(dir: String, ev: String, source: String) -> Dictionary:
	var found: Dictionary = {}
	for file_name in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".jsonl"):
			continue
		for raw in FileAccess.get_file_as_string(dir.path_join(file_name)).split("\n", false):
			var parsed: Variant = JSON.parse_string(raw)
			if not parsed is Dictionary:
				continue
			var line: Dictionary = parsed
			if str(line.get("ev")) == ev and (source.is_empty() or str(line.get("source")) == source):
				found = line
	if found.is_empty():
		_fail("no %s line%s in the run log at %s" % [ev, "" if source.is_empty() else " from " + source, ProjectSettings.globalize_path(dir)])
	return found

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)

func _expect_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [message, actual, expected])

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
