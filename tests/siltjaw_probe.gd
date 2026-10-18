extends SceneTree

# Headless probe for the Siltjaw: dug in from the fight's opening (Enemy
# Data.opens_dug_in), then its Snap -> Charge -> Dig loop (the Charge a
# plain hit, nothing to break); the Dig's three mounds, each a target of
# 12 HP, under one drawn at random; under the sand one move - the Erupt,
# 14, landing as a strike back (no Brace or Garnish may target it; Block
# still takes its share) - surfacing on its own; the intent preview
# the Erupt from turn 1, never a mound. A mound broken: a wrong one gone
# and nothing more; its own brings it up Exposed (50% more) through the
# player's next turn, the overkill carried in raw, and a broken mound is
# no kill. A card at every enemy hits every mound; a status aimed at a
# mound lands on the Siltjaw. Denied under the sand: no eruption, up at
# its mound, not Exposed. A Denied Dig lost. Its Dug in readout (the
# eruption's 14 in its hover) from each dig until it surfaces. The rules
# cases drive EnemyTurn and EffectResolver on the real .tres and cards;
# the fight cases load floor 2 and play real cards through
# BattleController - the fight opening on its row, the body never up and
# its own mound flat, the mounds in a row with the body's node at the
# middle one whichever it is under, a plate of 12 on each, a rect for
# each and none for the body; Slashes at a wrong mound wearing it down and breaking it, nothing
# back; Bite Downs breaking its own, the overkill landing raw and the
# Siltjaw up Exposed at that mound; a Carve on every mound; and the
# eruption coming up at its mound.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/siltjaw_probe.gd
#
# Exit code 0 = every check passed, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload, as
# blackback_probe.gd's header explains.

const CASES := 15
const SILTJAW_PATH := "res://battle/rules/enemies/siltjaw.tres"
const EXPOSED_PATH := "res://battle/rules/statuses/exposed_surfaced.tres"
const BRACED_PATH := "res://battle/rules/statuses/braced.tres"
const DUG_IN_PATH := "res://battle/rules/statuses/dug_in.tres"
const DUG_IN_LABEL := "Dug in"
const DENIED_PATH := "res://battle/rules/statuses/denied.tres"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTER_PATH := "res://run/data/wanderer.tres"
const SLASH_PATH := "res://cards/data/slash.tres"
const CARVE_PATH := "res://cards/data/carve.tres"
const BITE_DOWN_PATH := "res://cards/data/bite_down.tres"
const BRACE_PATH := "res://cards/data/brace.tres"
const GARNISH_PATH := "res://cards/data/garnish.tres"
const SENTENCE_PATH := "res://cards/data/sentence.tres"
const SENTENCE_STATUS_PATH := "res://battle/rules/statuses/sentence.tres"
const FLOOR_2 := 1
const HP := 44
const SNAP := 6
const CHARGE := 14
const ERUPT := 14
const MOUNDS := 3
const MOUND_HP := 12
const SLASH := 6
const CARVE := 6
const BITE_DOWN := 8
const DIG_INDEX := 2
const PLAYER_HP := 999
# The least the mounds' screen centres stand apart across the screen.
const MIN_SCREEN_GAP_PX := 40.0
const SAFETY_SECONDS := 400.0

var _run_state: Node = null
var _field: Node = null
var _failures: int = 0
var _completed: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	_check_data()
	_check_never_found()
	_check_preview()
	_check_eruption_refuses_brace()
	_check_break_wrong()
	_check_break_own()
	_check_every_mound()
	_check_status_at_mound()
	_check_denied_under()
	_check_denied_dig()
	await _check_fight_dig()
	await _check_fight_wrong()
	await _check_fight_own()
	await _check_fight_carve()
	await _check_fight_erupt()
	if _completed != CASES:
		_fail("%d of %d cases ran to their end" % [_completed, CASES])
	if _failures == 0:
		print("siltjaw_probe: PASSED")
		quit(0)
	else:
		print("siltjaw_probe: %d FAILED" % _failures)
		quit(1)

# --- Rules ---

func _check_data() -> void:
	var data: EnemyData = _siltjaw()
	_expect_eq(data.max_hp, HP, "The Siltjaw has %d HP" % HP)
	_expect(data.opens_dug_in, "...opens dug in")
	_expect(not data.erratic_intent_selection, "...a fixed loop")
	_expect_eq(data.intents.size(), 3, "...of three moves")
	if data.intents.size() == 3:
		var snap: EnemyIntent = data.intents[0]
		var charge: EnemyIntent = data.intents[1]
		var dig: EnemyIntent = data.intents[2]
		_expect(snap.intent_name == "Snap" and snap.type == EnemyIntent.IntentType.ATTACK and snap.value == SNAP, "Snap first, %d" % SNAP)
		_expect(charge.intent_name == "Charge" and charge.value == CHARGE and charge.interrupt_threshold == 0 and charge.on_interrupt == null, "...then Charge %d, nothing to break" % CHARGE)
		_expect(dig.intent_name == "Dig" and dig.type == EnemyIntent.IntentType.DIG and dig.mound_count == MOUNDS and dig.mound_hp == MOUND_HP, "...then Dig, %d mounds of %d HP" % [MOUNDS, MOUND_HP])
		_expect(dig.under_moves.size() == 1 and dig.under_moves[0].intent_name == "Erupt" and dig.under_moves[0].value == ERUPT and dig.under_moves[0].lands_as_strike_back, "...under the sand one move, Erupt %d, landing as a strike back" % ERUPT)
		_expect(dig.found_status != null and dig.found_status.resource_path == EXPOSED_PATH and dig.found_status.default_duration_turns == 2, "...found, Exposed for two of its turns")
	_completed += 1

# Nothing played: dug in from the start, three mounds of 12 - Erupt 14 and
# up - then Snap 6, Charge 14, Dig (nothing), and the Erupt again - under
# one of its mounds while down, the opening's and the Dig's alike.
func _check_never_found() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(enemy.dug_in and enemy.mounds.size() == MOUNDS and enemy.true_mound >= 0 and enemy.true_mound < MOUNDS, "Opens dug in: %d mounds, under number %d" % [enemy.mounds.size(), enemy.true_mound])
	var guards_ok: bool = enemy.mound_guards.size() == MOUNDS
	for index in enemy.mound_guards.size():
		var guard: Combatant = enemy.mound_guards[index]
		guards_ok = guards_ok and guard.hp == MOUND_HP and guard.max_hp == MOUND_HP and guard.mound_owner == enemy and guard.mound_index == index
	_expect(guards_ok, "...each mound its own target of %d HP" % MOUND_HP)
	_expect(_has(enemy, DUG_IN_PATH), "...its readout Dug in")
	var dug_in: Status = Status.find_in(enemy.statuses, load(DUG_IN_PATH) as StatusData)
	_expect(dug_in != null and dug_in.label() == DUG_IN_LABEL and dug_in.describe().contains("erupts for %d" % ERUPT), "...reading \"%s\", its hover the eruption's %d (%s)" % [DUG_IN_LABEL, ERUPT, dug_in.describe() if dug_in != null else ""])
	var lost: Array[int] = []
	var dug: Array[bool] = []
	var readout: Array[bool] = []
	for turn in 5:
		var before: int = player.hp
		EnemyTurn.take_turn(enemy, data, player)
		lost.append(before - player.hp)
		dug.append(enemy.dug_in)
		readout.append(_has(enemy, DUG_IN_PATH))
		if turn == 3:
			_expect(enemy.mounds.size() == MOUNDS and enemy.mound_guards.size() == MOUNDS and enemy.true_mound >= 0 and enemy.true_mound < MOUNDS, "Dug: %d mounds, under number %d" % [enemy.mounds.size(), enemy.true_mound])
	_expect_eq(lost, [ERUPT, SNAP, CHARGE, 0, ERUPT] as Array[int], "Erupt, Snap, Charge, Dig, Erupt")
	_expect_eq(dug, [false, false, false, true, false] as Array[bool], "...under the sand until the Erupt, and from the Dig to the next")
	_expect_eq(readout, dug, "...Dug in on its readout exactly while under")
	var seen: Dictionary = {}
	var dug_seen: Dictionary = {}
	for trial in 60:
		seen[_enemy(data).true_mound] = true
		var other: Combatant = _surfaced(data)
		EnemyTurn.take_turn(other, data, player)
		dug_seen[other.true_mound] = true
	_expect_eq(seen.size(), MOUNDS, "Across 60 openings it is under each mound in turn (%d seen)" % seen.size())
	_expect_eq(dug_seen.size(), MOUNDS, "...and across 60 digs (%d seen)" % dug_seen.size())
	_completed += 1

# Under the sand from turn 1, the preview shows the Erupt and nothing that
# names a mound; up, the Snap and the Charge have no threshold.
func _check_preview() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var preview: Dictionary = EnemyTurn.preview_intent(enemy, data, player)
	_expect_eq([int(preview["per_hit"]), int(preview.get("dig_stage", -1)), int(preview.get("dig_stages", -1))], [ERUPT, 0, 1], "Turn 1: Erupt %d, its one turn under" % ERUPT)
	for key: String in preview:
		_expect(not key.contains("mound"), "...nothing in it names a mound (%s)" % key)
	EnemyTurn.take_turn(enemy, data, player)
	preview = EnemyTurn.preview_intent(enemy, data, player)
	_expect(int(preview["per_hit"]) == SNAP and not preview.has("threshold") and not preview.has("dig_stage"), "Up: the Snap, no threshold, no pips")
	EnemyTurn.take_turn(enemy, data, player)
	_expect(not EnemyTurn.preview_intent(enemy, data, player).has("threshold"), "...nor the Charge")
	_completed += 1

# Dug in, its Erupt lands as a strike back: no Brace or Garnish may
# target it (EnemyTurn.MarkRefusal.ONLY_BLOCK), it previews and lands its
# whole 14, and Block 5 still takes 5 of it.
func _check_eruption_refuses_brace() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	_expect(not EffectResolver.can_target(load(BRACE_PATH) as CardData, enemy), "Dug in: a Brace can't target the Erupt")
	_expect(not EffectResolver.can_target(load(GARNISH_PATH) as CardData, enemy), "...nor a Garnish")
	_expect_eq(EnemyTurn.mark_refusal(enemy, data, load(BRACED_PATH) as StatusData), EnemyTurn.MarkRefusal.ONLY_BLOCK, "...only Block reduces it")
	_expect_eq(int(EnemyTurn.preview_intent(enemy, data, player)["per_hit"]), ERUPT, "The Erupt previews %d" % ERUPT)
	player.block = 5
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, ERUPT - 5, "...and lands %d past Block 5" % (ERUPT - 5))
	_completed += 1

# A wrong mound brought to 0: gone, the Siltjaw untouched and still under,
# the card's target gone with it, no kill; the other mounds stand.
func _check_break_wrong() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var wrong: int = (enemy.true_mound + 1) % MOUNDS
	var guard: Combatant = enemy.mound_guards[wrong]
	var ctx: EffectContext = _ctx(enemy, guard)
	var broken: Array = []
	ctx.on_mound_broken = func(owner: Combatant, mound: int, own: bool) -> void:
		broken.append([owner, mound, own])
	_hit(ctx, guard, MOUND_HP + 5)
	_expect_eq(broken, [[enemy, wrong, false]], "A wrong mound brought to 0 breaks, not its own")
	_expect(enemy.dug_in and enemy.mounds.size() == MOUNDS - 1 and not enemy.mounds.has(wrong), "...gone, %d left, the Siltjaw still under" % enemy.mounds.size())
	_expect_eq(enemy.hp, HP, "...nothing carried into it")
	_expect(ctx.target == null and ctx.landing_for(guard) == null, "...the card's target gone with it")
	_expect(not ctx.killed_this_card, "...and no kill")
	_completed += 1

# Its own mound brought to 0 by 20: up, Exposed, the 8 past the mound
# carried in raw (not 12), the card's target now the Siltjaw; Exposed
# through its next move and gone after the one after.
func _check_break_own() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	var guard: Combatant = enemy.mound_guards[enemy.true_mound]
	var ctx: EffectContext = _ctx(enemy, guard)
	var broken: Array = []
	ctx.on_mound_broken = func(_owner: Combatant, mound: int, own: bool) -> void:
		broken.append([mound, own])
	_hit(ctx, guard, 20)
	_expect_eq(broken, [[enemy.true_mound, true]], "Its own mound brought to 0 breaks")
	_expect(not enemy.dug_in and enemy.mounds.is_empty() and not _has(enemy, DUG_IN_PATH), "...up out of the sand, no longer Dug in")
	_expect(_has(enemy, EXPOSED_PATH), "...Exposed")
	_expect_eq(HP - enemy.hp, 20 - MOUND_HP, "...the overkill carried in raw, %d" % (20 - MOUND_HP))
	_expect(ctx.target == enemy, "...the rest of the card landing on it")
	_expect(not ctx.killed_this_card, "...no kill")
	_expect_eq(Status.apply_modifiers(10, enemy.statuses, StatusData.ModifierTarget.INCOMING_DAMAGE), 15, "...10 lands 15")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Snap", "...the Snap next, no eruption")
	var before: int = player.hp
	EnemyTurn.take_turn(enemy, data, player)
	_expect_eq(before - player.hp, SNAP, "The Snap lands %d" % SNAP)
	_expect(_has(enemy, EXPOSED_PATH), "...still Exposed through the player's next turn")
	EnemyTurn.take_turn(enemy, data, player)
	_expect(not _has(enemy, EXPOSED_PATH), "...gone with the Charge after")
	_completed += 1

# A Carve (6 to every enemy) through the real resolver: every mound takes
# 6, the Siltjaw nothing, still under.
func _check_every_mound() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var ctx: EffectContext = _ctx(enemy, null)
	EffectResolver.new().resolve_card(load(CARVE_PATH) as CardData, ctx)
	var left: Array[int] = []
	for guard in enemy.mound_guards:
		left.append(guard.hp)
	_expect_eq(left, [MOUND_HP - CARVE, MOUND_HP - CARVE, MOUND_HP - CARVE] as Array[int], "A Carve hits every mound for %d" % CARVE)
	_expect(enemy.hp == HP and enemy.dug_in, "...the Siltjaw untouched, still under")
	_completed += 1

# A Sentence at a mound: on the Siltjaw, the mound untouched.
func _check_status_at_mound() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var guard: Combatant = enemy.mound_guards[0]
	var ctx: EffectContext = _ctx(enemy, guard)
	EffectResolver.new().resolve_card(load(SENTENCE_PATH) as CardData, ctx)
	_expect(_has(enemy, SENTENCE_STATUS_PATH), "A Sentence at a mound lands on the Siltjaw")
	_expect(guard.statuses.is_empty() and guard.hp == MOUND_HP and enemy.mounds.size() == MOUNDS, "...the mound untouched, nothing broken")
	_completed += 1

# Denied under the sand: no eruption - up at its mound, not Exposed, the
# Snap next.
func _check_denied_under() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _enemy(data)
	var player: Combatant = _player()
	Status.apply_to(enemy.statuses, load(DENIED_PATH) as StatusData)
	var before: int = player.hp
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, player)
	_expect(bool(result["denied"]) and before == player.hp, "Denied under the sand: no eruption")
	_expect(bool(result["erupted"]) and not enemy.dug_in, "...up at its mound all the same")
	_expect(not _has(enemy, EXPOSED_PATH), "...not Exposed")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Snap", "...the Snap next")
	_completed += 1

# A Denied Dig is lost: nothing digs, the Snap is next.
func _check_denied_dig() -> void:
	var data: EnemyData = _siltjaw()
	var enemy: Combatant = _surfaced(data)
	Status.apply_to(enemy.statuses, load(DENIED_PATH) as StatusData)
	var result: Dictionary = EnemyTurn.take_turn(enemy, data, _player())
	_expect(bool(result["denied"]) and not enemy.dug_in, "A Denied Dig digs nothing")
	_expect_eq(EnemyTurn.current_intent(enemy, data).intent_name, "Snap", "...the Snap next")
	_completed += 1

# --- Fights ---

# The fight opens dug in: three mounds in a row, left to right on screen
# and each its own click; the body never up, its own mound flat; its node
# at the middle one whichever it is under; a rect for each mound and none
# for the body; the intent's Erupt.
func _check_fight_dig() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _opened(controller, siltjaw)
		_expect(bool(siltjaw.call("is_dug_in")) and combatant.dug_in, "The fight opens dug in")
		_expect(not (siltjaw.get("_model") as Node3D).visible, "...the body never up")
		var own: Node = siltjaw.get("_mound")
		_expect(own != null and float(own.call("get_rise")) == 0.0, "...its own mound flat under the row")
		var at: Vector3 = siltjaw.global_position
		var middle: Vector3 = siltjaw.call("get_mound_position", 1)
		_expect(Vector2(at.x - middle.x, at.z - middle.z).length() < 0.05, "...its node at the middle mound, under number %d" % combatant.true_mound)
		_expect_eq(_plate_hps(), [MOUND_HP, MOUND_HP, MOUND_HP] as Array[int], "...a plate on each mound, %d HP" % MOUND_HP)
		await _arm(controller)
		controller.call("_refresh_enemy_rects")
		var rects: Array = controller.get("_mound_rects")
		_expect_eq(rects.size(), MOUNDS, "Armed: a rect for each mound")
		_expect(not (controller.get("_enemy_rects") as Dictionary).has(siltjaw), "...none for the body")
		# Each its own click: no mound's rect holds another's centre.
		for entry: Dictionary in rects:
			for other: Dictionary in rects:
				if entry != other and (entry["rect"] as Rect2).has_point((other["rect"] as Rect2).get_center()):
					_fail("Mound %d's rect covers mound %d's centre" % [int(entry["mound"]), int(other["mound"])])
		var xs: Array[float] = []
		for entry: Dictionary in rects:
			xs.append((entry["rect"] as Rect2).get_center().x)
		xs.sort()
		_expect(xs.size() == MOUNDS and xs[1] - xs[0] > MIN_SCREEN_GAP_PX and xs[2] - xs[1] > MIN_SCREEN_GAP_PX, "...left to right on screen (%s)" % str(xs))
		var preview: Dictionary = controller.call("get_intent_preview", siltjaw)
		_expect_eq(int(preview.get("per_hit", -1)), ERUPT, "...its intent the Erupt %d" % ERUPT)
		controller.call("cancel_target")
	await _teardown()
	_completed += 1

# Slashes at a wrong mound: the first takes 6 off it, the Siltjaw
# untouched and nothing back; the second breaks it - gone, still under,
# still nothing back.
func _check_fight_wrong() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		var player: Combatant = controller.get("player")
		await _opened(controller, siltjaw)
		var before: int = player.hp
		var wrong: int = (combatant.true_mound + 1) % MOUNDS
		var hits: Array = []
		controller.connect("mound_damaged", func(_enemy: Node, mound: int, amount: int, hp: int, _max_hp: int) -> void:
			hits.append([mound, amount, hp]))
		await _play_at(controller, siltjaw, wrong)
		_expect_eq(hits, [[wrong, SLASH, MOUND_HP - SLASH]], "A Slash at a wrong mound: %d off it, reported on it" % SLASH)
		_expect(combatant.hp == HP and combatant.mounds.size() == MOUNDS, "...the Siltjaw untouched, every mound standing")
		_expect(_plate_hps().has(MOUND_HP - SLASH), "...its plate down to %d" % (MOUND_HP - SLASH))
		await _play_at(controller, siltjaw, wrong)
		_expect(combatant.dug_in and combatant.mounds.size() == MOUNDS - 1 and not combatant.mounds.has(wrong), "A second breaks it: %d left, still under" % combatant.mounds.size())
		_expect_eq(combatant.hp, HP, "...the Siltjaw untouched")
		_expect_eq(before - player.hp, 0, "...and nothing comes back")
		_expect_eq(_plate_hps().size(), MOUNDS - 1, "...its plate gone with it")
	await _teardown()
	_completed += 1

# Bite Downs at its own mound: 8, then 8 more breaks it - the 4 past it
# carried in raw, the Siltjaw up at that mound, Exposed, no longer Dug in.
func _check_fight_own() -> void:
	var controller: Node = await _start_fight(BITE_DOWN_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _opened(controller, siltjaw)
		var own: int = combatant.true_mound
		var spot: Vector3 = siltjaw.call("get_mound_position", own)
		var broken: Array = []
		controller.connect("mound_broken", func(_enemy: Node, mound: int, is_own: bool) -> void:
			broken.append([mound, is_own]))
		await _play_at(controller, siltjaw, own)
		_expect(combatant.dug_in and combatant.mound_guards[own].hp == MOUND_HP - BITE_DOWN, "A Bite Down at its own mound: %d off it, still under" % BITE_DOWN)
		await _play_at(controller, siltjaw, own)
		_expect_eq(broken, [[own, true]], "A second breaks it - its own")
		_expect(not combatant.dug_in and not bool(siltjaw.call("is_dug_in")), "...up")
		_expect(not _readout_has(controller, siltjaw, DUG_IN_LABEL), "...its readout no longer Dug in")
		_expect(_has(combatant, EXPOSED_PATH), "...Exposed")
		_expect_eq(HP - combatant.hp, 2 * BITE_DOWN - MOUND_HP, "...the overkill carried in raw, %d" % (2 * BITE_DOWN - MOUND_HP))
		_expect(_plate_hps().is_empty(), "...every mound's plate gone")
		var at: Vector3 = siltjaw.global_position
		_expect(Vector2(at.x - spot.x, at.z - spot.z).length() < 0.05, "...up at that mound")
	await _teardown()
	_completed += 1

# A Carve hits every mound for 6: the Siltjaw untouched, still under.
func _check_fight_carve() -> void:
	var controller: Node = await _start_fight(CARVE_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		await _opened(controller, siltjaw)
		var hits: Dictionary = {}
		controller.connect("mound_damaged", func(_enemy: Node, mound: int, amount: int, _hp: int, _max_hp: int) -> void:
			hits[mound] = amount)
		await _play_first(controller)
		_expect_eq(hits, {0: CARVE, 1: CARVE, 2: CARVE}, "A Carve hits every mound for %d" % CARVE)
		_expect(combatant.dug_in and combatant.hp == HP, "...the Siltjaw untouched, still under")
	await _teardown()
	_completed += 1

# Never found: the Erupt - up at its own mound, 14.
func _check_fight_erupt() -> void:
	var controller: Node = await _start_fight(SLASH_PATH)
	if controller != null:
		var siltjaw: Node = (controller.get("enemies") as Array)[0]
		var combatant: Combatant = _combatant(controller, siltjaw)
		var player: Combatant = controller.get("player")
		await _opened(controller, siltjaw)
		_expect(_readout_has(controller, siltjaw, DUG_IN_LABEL), "Opened dug in: its readout Dug in")
		var spot: Vector3 = siltjaw.call("get_mound_position", combatant.true_mound)
		var before: int = player.hp
		await _end_turn(controller)
		_expect_eq(before - player.hp, ERUPT, "Unbroken: the Erupt, %d" % ERUPT)
		_expect(not combatant.dug_in and not bool(siltjaw.call("is_dug_in")), "...and it is up")
		_expect(not _readout_has(controller, siltjaw, DUG_IN_LABEL), "...its readout no longer Dug in")
		var at: Vector3 = siltjaw.global_position
		_expect(Vector2(at.x - spot.x, at.z - spot.z).length() < 0.05, "...at its own mound")
	await _teardown()
	_completed += 1

# --- Helpers ---

func _siltjaw() -> EnemyData:
	return load(SILTJAW_PATH) as EnemyData

func _enemy(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	enemy.enemy_data = data
	EnemyTurn.pick_initial_intent(enemy, data)
	return enemy

# Up out of the sand, its Dig queued - the loop's own, past the opening.
func _surfaced(data: EnemyData) -> Combatant:
	var enemy := Combatant.new(data.max_hp)
	enemy.current_intent_index = DIG_INDEX
	return enemy

func _player() -> Combatant:
	return Combatant.new(500)

# A card's context against a dug-in `enemy`: its standing mounds the
# enemies in reach, `target` the card's target.
func _ctx(enemy: Combatant, target: Combatant) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = _player()
	ctx.target = target
	for guard in enemy.mound_guards:
		ctx.enemies.append(guard)
	ctx.mound_data[enemy] = _siltjaw()
	return ctx

# One hit of `amount` on `guard`, as a card's damage lands it.
func _hit(ctx: EffectContext, guard: Combatant, amount: int) -> void:
	var result: Dictionary = DamagePipeline.resolve(amount, guard)
	ctx.report_damage(guard, int(result["damage_to_hp"]), "card")

func _has(combatant: Combatant, path: String) -> bool:
	for active: Status in combatant.statuses:
		if active.data != null and active.data.resource_path == path:
			return true
	return false

# A new run on floor 2, the fight started on its Siltjaw with a deck of
# `card_path` alone. The controller, or null (a FAIL is recorded).
func _start_fight(card_path: String) -> Node:
	_run_state.call("new_run", load(CHARACTER_PATH))
	var cards: Array[CardData] = []
	for i in 10:
		cards.append((load(card_path) as CardData).duplicate() as CardData)
	_run_state.set("deck", cards)
	_run_state.set("player_max_hp", PLAYER_HP)
	_run_state.set("player_hp", PLAYER_HP)
	_run_state.set("current_floor_index", FLOOR_2)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	# Its slot can roll empty: stood here.
	var forced: Dictionary[StringName, StringName] = {&"siltjaw": &"siltjaw"}
	_field.set("force_options", forced)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		var data: Resource = node.get("enemy_data")
		if data != null and data.resource_path == SILTJAW_PATH:
			target = node as Node3D
	if target == null:
		_fail("no Siltjaw on floor 2")
		return null
	_field.call_deferred("_on_enemy_contacted", target)
	for i in 10:
		await physics_frame
	var layer: Node = _field.get_node("BattleLayer")
	var overlay: Node = layer.get_child(0) if layer.get_child_count() > 0 else null
	if overlay == null:
		_fail("no fight started on floor 2")
		return null
	await ProbePlay.settle_fight(self, _field, overlay.get("battle_controller"))
	var controller: Node = overlay.get("battle_controller")
	var members: Array = controller.get("enemies")
	_expect(members.size() == 1 and members[0] == target, "The fight is the Siltjaw alone")
	return controller

# The opening's row up: every mound at full height, the body's node at
# the middle one, and the fight ready to play.
func _opened(controller: Node, siltjaw: Node) -> void:
	var row_up: Callable = func() -> bool:
		if not bool(siltjaw.call("is_dug_in")):
			return false
		for mound in MOUNDS:
			var sand: Node = siltjaw.call("_dig_sand", mound)
			if sand == null or float(sand.call("get_rise")) < 0.99:
				return false
		var at: Vector3 = (siltjaw as Node3D).global_position
		var middle: Vector3 = siltjaw.call("get_mound_position", 1)
		return Vector2(at.x - middle.x, at.z - middle.z).length() < 0.05
	var up: bool = await ProbePlay.wait_until(self, row_up, 5.0)
	_expect(up, "The opening's row comes up")
	await ProbePlay.wait_until(self, func() -> bool: return ProbePlay.fight_ready(controller), 8.0)

func _end_turn(controller: Node) -> void:
	await controller.call("end_turn")
	await create_timer(0.8).timeout

# The first card in hand armed, Energy topped up.
func _arm(controller: Node) -> void:
	var player: Combatant = controller.get("player")
	player.energy = 99
	var views: Array = controller.get("_hand_container").call("_card_views")
	if views.is_empty():
		_fail("no card in hand to play")
		return
	controller.call("request_play", views[0])
	await process_frame

# The first card in hand at mound `mound`, waited out.
func _play_at(controller: Node, siltjaw: Node, mound: int) -> void:
	await _arm(controller)
	controller.call("confirm_target", siltjaw, mound)
	await _settle(controller)

# The first card in hand, at no one (a Carve).
func _play_first(controller: Node) -> void:
	await _arm(controller)
	await _settle(controller)

func _settle(controller: Node) -> void:
	for i in 180:
		await process_frame
		if not bool(controller.get("_input_locked")):
			break
	await create_timer(1.0).timeout

# Whether `member`'s readout shows `label` (BattleController.get_enemy_
# status_labels()).
func _readout_has(controller: Node, member: Node, label: String) -> bool:
	return Array(controller.call("get_enemy_status_labels", member)).has(label)

# The mound plates showing (BattleOverlay._mound_plates), each one's HP,
# in mound order.
func _plate_hps() -> Array[int]:
	var hps: Array[int] = []
	var overlay: Node = _field.get_node("BattleLayer").get_child(0)
	var plates: Dictionary = overlay.get("_mound_plates")
	var keys: Array = plates.keys()
	keys.sort()
	for key in keys:
		var plate: Node = plates[key]
		if is_instance_valid(plate) and not plate.is_queued_for_deletion():
			hps.append(int(plate.get("_current_hp")))
	return hps

func _combatant(controller: Node, member: Node) -> Combatant:
	return (controller.get("_combatants") as Dictionary).get(member)

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	for i in 5:
		await process_frame

func _fail(label: String) -> void:
	_failures += 1
	print("FAIL: " + label)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		_fail(label)

func _expect_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual != expected:
		_fail("%s (got %s, expected %s)" % [label, str(actual), str(expected)])
