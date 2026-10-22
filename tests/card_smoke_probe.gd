extends SceneTree

# Core probe: every card plays. Data-driven: every CardData resource under
# cards/ - tempered copies, weapon cards and cards no pool offers alike,
# once each - is dealt into a real fight's hand and played through
# BattleController as a player would (ProbePlay.play_any(): its hand
# choice, its target and a look's pick found). The Wanderer's own and the
# neutral cards in a Wanderer run, the Samurai's in hers; each on floor
# 1's first fight.
#
# A card fails when it can't be played or doesn't commit, or when its play
# leaves anything open (a target, a choice, a look) or the fight stuck. A card the
# rules block as dealt - nothing to replay, no attack on the record - is
# given the turn it needs: a basic Attack played first, then an enemy turn,
# then tried again. Values are never checked: that the game plays every
# card without a script error is the check (tools/run_probes.sh fails on
# any SCRIPT ERROR or engine ERROR).
#
# The fight is kept going: the enemies and the Wanderer at HUGE_HP,
# Energy and Toll topped up before each card.
#
#   Godot_v4.7.1.exe --headless --path . -s res://tests/card_smoke_probe.gd
#
# Exit code 0 = every card played, 1 = a failure (each printed as FAIL).
# Untyped against anything that names the RunState autoload.

const CARDS_DIR := "res://cards/"
const REGION_SCENE_PATH := "res://field/region_field.tscn"
const CHARACTERS: Array[String] = ["res://run/data/wanderer.tres", "res://run/data/samurai.tres"]
const HUGE_HP := 99999
const TOP_UP := 99
# Enemy turns a blocked card is given before a fresh fight.
const ENEMY_TURNS := 4
const SAFETY_SECONDS := 420.0

var _run_state: Node = null
var _field: Node = null
var _controller: Node = null
# The last card tried was never playable.
var _blocked: bool = false
var _failures: int = 0
var _played: int = 0

func _initialize() -> void:
	create_timer(SAFETY_SECONDS).timeout.connect(func() -> void:
		print("FAIL: safety timeout")
		quit(1)
	)
	_run_state = root.get_node("RunState")
	var cards: Array[CardData] = _all_cards()
	var total: int = 0
	for index in CHARACTERS.size():
		var character := load(CHARACTERS[index]) as CharacterData
		var own: Array[CardData] = []
		for card in cards:
			# The class check RewardPool's offers use (CardData.usable_by()),
			# the neutral cards in the first class's run only.
			if card.usable_by(character) and (card.card_class != &"" or index == 0):
				own.append(card)
		total += own.size()
		await _play_all(character, own)
	# A card no character's run deals (a class with no character) is
	# never tried.
	if total != cards.size():
		_fail("%d cards found, %d of them in a character's run" % [cards.size(), total])
	print("card_smoke_probe: %d of %d cards played" % [_played, total])
	if _played != total:
		_fail("%d of %d cards played" % [_played, total])
	if _failures == 0:
		print("card_smoke_probe: PASSED")
		quit(0)
	else:
		print("card_smoke_probe: %d FAILED" % _failures)
		quit(1)

func _play_all(character: CharacterData, cards: Array[CardData]) -> void:
	print("
=== %s: %d cards" % [character.character_name, cards.size()])
	var basic: CardData = _basic_attack(character)
	await _open_fight(character)
	for card in cards:
		if _controller == null:
			_fail("%s: no fight to play %s in" % [character.character_name, card.card_name])
			break
		var played: bool = await _play_card(card, basic)
		# Blocked by what this fight has seen (a card held to one at a
		# time): a fresh fight, and once more.
		if not played and _blocked:
			await _open_fight(character)
			if _controller != null:
				played = await _play_card(card, basic)
		if _blocked:
			_fail("%s: never playable, even after an Attack, enemy turns and a fresh fight" % card.card_name)
		if played:
			_played += 1
	await _teardown()

# A new run as `character`, its HP at HUGE_HP, on floor 1, and a fight
# with its first enemy: _controller, or null when none opened.
func _open_fight(character: CharacterData) -> void:
	await _teardown()
	_run_state.call("new_run", character)
	_run_state.call("set_max_hp", HUGE_HP)
	_run_state.set("player_hp", HUGE_HP)
	_run_state.set("current_floor_index", 0)
	_run_state.set("run_opening_pending", false)
	_run_state.set("title_pending", false)
	_field = (load(REGION_SCENE_PATH) as PackedScene).instantiate()
	_field.set("run_logging_enabled", false)
	root.add_child(_field)
	for i in 30:
		await physics_frame
	await ProbePlay.wait_until(self, func() -> bool: return not bool(_field.call("is_arrival_held")), 10.0)
	var target: Node3D = null
	for node in get_nodes_in_group("enemies"):
		target = node as Node3D
		break
	_controller = await ProbePlay.start_fight(self, _field, target) if target != null else null
	if _controller == null:
		_fail("%s: no fight opened on floor 1" % character.character_name)

# Deals `card` and plays it. Blocked as dealt, it gets a basic Attack
# played first, then up to ENEMY_TURNS enemy turns, before it is tried
# again; _blocked says it never could be. Whether it played cleanly.
func _play_card(card: CardData, basic: CardData) -> bool:
	_blocked = false
	for attempt in ENEMY_TURNS + 2:
		if not _battle_open() or not is_instance_valid(_controller):
			_fail("the fight ended before %s" % card.card_name)
			_controller = null
			return false
		var controller: Node = _controller
		_top_up(controller)
		var deck: Object = controller.get("deck")
		deck.call("discard_hand")
		await process_frame
		if attempt == 1 and basic != null:
			var first: CardData = await _deal(controller, basic)
			var first_view: CardView = _view(controller, first)
			if first_view != null and bool(controller.call("_is_playable", first)):
				await ProbePlay.play_any(self, controller, first_view, _stopped)
			_top_up(controller)
		if attempt >= 2:
			# Nothing between him and the enemy's attack, so it lands and
			# goes on his record.
			(controller.get("player") as Combatant).block = 0
			await _enemy_turn(controller)
			if not is_instance_valid(controller) or not _battle_open():
				continue
			_top_up(controller)
			deck.call("discard_hand")
			await process_frame
		# A hand card besides it, for a card that picks one (Bide, Twice
		# Over, Take In).
		if basic != null:
			await _deal(controller, basic)
		var dealt: CardData = await _deal(controller, card)
		var view: CardView = _view(controller, dealt)
		if view == null:
			_fail("%s: not dealt into the hand" % card.card_name)
			return false
		if not bool(controller.call("_is_playable", dealt)):
			continue
		var committed: bool = await ProbePlay.play_any(self, controller, view, _stopped)
		if not committed:
			_fail("%s: playable, but the play didn't commit" % card.card_name)
			return false
		if not is_instance_valid(controller) or not _battle_open():
			_fail("%s: its play ended the fight" % card.card_name)
			_controller = null
			return false
		var open: bool = bool(controller.call("is_awaiting_target")) or bool(controller.call("is_choosing")) or bool(controller.call("is_looking")) or not ProbePlay.is_settled(controller)
		if open:
			_fail("%s: its play left a target, a choice, a look or the play open" % card.card_name)
			controller.call("cancel_target")
			controller.call("cancel_choice")
			return false
		print("played: %s" % card.card_name)
		return true
	_blocked = true
	return false

# An enemy turn and back to the player's.
func _enemy_turn(controller: Node) -> void:
	var turn: int = int(controller.get("_player_turn"))
	controller.call("end_turn")
	# A keep choice (a keepsake) is confirmed with nothing kept.
	if bool(controller.get("_keep_choice_open")):
		controller.call("confirm_choice")
	var held: WeakRef = weakref(controller)
	await ProbePlay.wait_until(self, func() -> bool:
		var live: Node = held.get_ref() as Node
		return live == null or not _battle_open() or (int(live.get("_player_turn")) > turn and ProbePlay.is_settled(live)), 20.0)

# The fight kept going: every enemy and the Wanderer at HUGE_HP, Energy
# and Toll topped up.
func _top_up(controller: Node) -> void:
	var combatants: Dictionary = controller.get("_combatants")
	for combatant: Combatant in combatants.values():
		combatant.max_hp = HUGE_HP
		combatant.hp = HUGE_HP
	var player: Combatant = controller.get("player")
	player.max_hp = HUGE_HP
	player.hp = HUGE_HP
	player.energy = TOP_UP
	player.toll = TOP_UP

func _stopped() -> bool:
	return not _battle_open()

func _deal(controller: Node, card: CardData) -> CardData:
	var dealt: CardData = card.duplicate()
	var deck: Object = controller.get("deck")
	(deck.get("draw_pile") as Array).append(dealt)
	deck.call("draw", 1)
	await process_frame
	return dealt

func _view(controller: Node, card: CardData) -> CardView:
	for view: CardView in ProbePlay.hand_views(controller):
		if view.card_data == card:
			return view
	return null

# The class's basic Attack: its first starter that is an Attack at one
# enemy.
func _basic_attack(character: CharacterData) -> CardData:
	for card: CardData in character.starting_deck_counts:
		if card != null and card.card_type == CardData.CardType.ATTACK and card.target_type == CardData.TargetType.ENEMY:
			return card
	return null

# Every CardData under cards/, its folders walked - once each. (Test
# fixtures live under tests/, never here.)
func _all_cards() -> Array[CardData]:
	var found: Array[CardData] = []
	var dirs: Array[String] = [CARDS_DIR]
	while not dirs.is_empty():
		var dir_path: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(dir_path):
			dirs.append(dir_path.path_join(sub))
		for file in DirAccess.get_files_at(dir_path):
			if file.get_extension() == "tres":
				_add_card(found, load(dir_path.path_join(file)) as CardData)
	return found

func _add_card(found: Array[CardData], card: CardData) -> void:
	if card != null and not found.has(card):
		found.append(card)

func _battle_open() -> bool:
	return _field != null and is_instance_valid(_field) and bool(_field.get("_battle_open"))

func _teardown() -> void:
	if _field != null and is_instance_valid(_field):
		_field.queue_free()
	_field = null
	_controller = null
	for i in 5:
		await process_frame

func _fail(message: String) -> void:
	_failures += 1
	print("FAIL: ", message)
