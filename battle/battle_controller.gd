extends Node
class_name BattleController

# --- View-facing input/targeting signals (unchanged from the previous pass) ---
signal card_played(card: CardData, target: FieldEnemy)
# Fires once _resolve_play()'s own impact delay has elapsed - the instant
# the swing (or, with no battle_animation, the play itself) actually
# lands - for feedback that cares about the moment of impact but not the
# damage numbers themselves (see Wanderer._on_card_impact(), the slash
# sound). damage_dealt below already fires at this same moment for
# anything that does care about the numbers.
signal card_impact(card: CardData)
# Fires swing_lead_seconds before card_impact for a card with a
# battle_animation - the moment the blade's whoosh starts (see Wanderer.
# _on_card_swing()), so the enemy's contact crack lands that far after
# the swing's onset. Clamped to the impact delay itself: a card whose
# delay is shorter than the lead swings at its play instant.
signal card_swing(card: CardData)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()
# A hand choice (see _begin_choice()) - Bide's set-aside, Deny's pick
# among cards tied for most expensive, or the keep a keepsake allows at
# the end of the turn (_begin_keep_choice()): opened with up to `cap`
# cards to mark, the verb that names what happens to them and what to
# click to confirm (the armed card's name, or END TURN), the count marked
# as it moves, and closed (confirmed, or cancelled with nothing spent).
signal hand_choice_started(confirm_label: String, cap: int, verb: String)
signal hand_choice_changed(marked: int, cap: int)
signal hand_choice_ended()

# --- Rules-facing signals - the overlay/FloatingNumber react to these only. ---
signal hp_changed(current: int, max_hp: int)
# The player's energy after anything that changes it (setup, a card
# played, a turn start) - HandContainer fades what can't be afforded.
signal energy_changed(current: int)
signal toll_changed(new_toll: int)
# Grace opened, spent or lost - the HP bar's pale segment follows this.
signal grace_changed(grace: int)
# The player's stance was taken, deepened, replaced or expired. Carries
# the live Stance (null when none) - the stance row and the card faces
# both re-read from it.
signal stance_changed(stance: Stance)
signal status_changed()
# False the moment end_turn() commits (the enemy turn is running), true
# again once the next player turn has started - BattleOverlay disables
# End Turn in between. Not emitted by setup(): the fight opens on the
# player's turn.
signal turn_phase_changed(player_turn: bool)
# The enemy actually under the cursor while a card is armed - null when
# it is over none, and when the card is played or cancelled. Never the
# default target _default_target() lights: what the armed card's face
# reads against (BattleOverlay._on_hovered_enemy_changed()).
signal hovered_enemy_changed(enemy: FieldEnemy)
signal enemy_hp_changed(enemy: FieldEnemy, current: int, max_hp: int)
# The intent display's two signals. enemy_intent_changed carries
# EnemyTurn.preview_intent()'s dictionary for that enemy's QUEUED action
# (empty = nothing to show) - emitted for every living enemy after
# setup(), after every card resolves and at each player-turn start (the
# preview depends on the player's block/statuses, which those change),
# and for one enemy right after it has resolved its action, so the
# display always shows the NEXT action. enemy_acting fires just before an
# enemy resolves, so the display can hide while it acts.
signal enemy_intent_changed(enemy: FieldEnemy, preview: Dictionary)
signal enemy_acting(enemy: FieldEnemy)
signal damage_dealt(source: Variant, target: Variant, amount: int, kind: String)
# The player's hit on `enemy` met its block, judged as the hit landed,
# before the block was spent. `absorbed`: the block took all of it - no
# damage_dealt follows. Otherwise this hit's damage_dealt comes right
# after, in the same call.
signal enemy_hit_blocked(enemy: FieldEnemy, absorbed: bool)
# source/target are each either the String "player" or a FieldEnemy node -
# whichever combatant actually dealt/received the hit.
# An enemy's HP reached 0. Fires right after that hit's own damage_dealt/
# enemy_hp_changed, and BEFORE battle_won when it was the last one - by
# then the enemy is already out of `enemies`/_combatants, so nothing here
# reads it again (its node may be freed by whoever listens). The overlay
# drops the member's displays on this; RegionField takes it off the
# field.
signal enemy_defeated(enemy: FieldEnemy)
# An enemy's pain turn has just been set (EnemyTurn.check_pain_turn()):
# its next action is cancelled. For the line and the sound; the intent's
# own change comes through enemy_intent_changed.
signal enemy_pain_turn(enemy: FieldEnemy)
# An enemy has just gained a status mid-fight - one turned into another
# by leaving its pack (the Blackback's Fed into Hungry, when the Nipper
# dies), or its phase's (the Greyshelf off its rock). For its body's tells (StorkTells' sac); the readouts take the
# change through status_changed. A fight's opening statuses aren't sent:
# they're read at its start (RegionField).
signal enemy_status_gained(enemy: FieldEnemy, status: StatusData)
signal battle_won()
signal battle_lost()

@export var turn_draw_amount: int = 5
# A Denied enemy's skipped turn holds this long (seconds), its Denied gone
# from the readout, so the skip reads - it has no lunge to wait on.
@export var denied_beat_sec: float = 0.5
# See card_swing.
@export var swing_lead_seconds: float = 0.04
@export var enemy_head_height: float = 1.8
# Where a SELF/NONE card's play tween aims, relative to the viewport's own
# center - there's no "target" to unproject for those, just somewhere up
# and away from the hand.
@export var self_play_screen_offset: Vector2 = Vector2(0.0, -250.0)
# Padding around each enemy's projected model rect for the armed-card
# target test - see _refresh_enemy_rects().
@export var target_padding_px: float = 16.0

var deck: Deck
var player: Combatant
var enemies: Array[FieldEnemy] = []
var cards_played_this_turn: int = 0

var _hand_container: HandContainer
var _pending_card_view: CardView = null
# The SET_ASIDE card armed while its choice is open, the other hand cards
# marked for it, and how many may be - see _begin_choice().
var _choosing_card_view: CardView = null
var _choice_marked: Array[CardView] = []
var _choice_cap: int = 0
# What the open choice is for: SET_ASIDE (Bide - 0 to cap, any other card)
# or CONSUME (Deny's tie - exactly cap, the tied cards only).
var _choice_kind: CardEffect.EffectType = CardEffect.EffectType.SET_ASIDE
var _choice_eligible: Array[CardView] = []
# The end-of-turn keep is open (see _begin_keep_choice()): a choice with
# no armed card, confirmed by End Turn. How many cards the held keepsake
# lets the hand keep (TrinketData.end_turn_keep), read as the fight opens.
var _keep_choice_open: bool = false
var _end_turn_keep: int = 0
# The hand card a CONSUME card (Deny) will take, picked before its target
# is: marked in the hand while the target is chosen, taken as it resolves.
var _pending_consume_view: CardView = null
var _hovered_enemy: FieldEnemy = null
# The enemy under the cursor itself, without the default - see
# hovered_enemy_changed.
var _cursor_enemy: FieldEnemy = null
var _enemy_rects: Dictionary = {} # FieldEnemy -> Rect2, see _refresh_enemy_rects()
var _combatants: Dictionary = {} # FieldEnemy -> Combatant
var _effect_resolver := EffectResolver.new()
# Read-only from here on: the Wanderer whose clip lengths _impact_delay_
# for() clamps against, and whose play_attack_snap() timing _run_enemy_
# turn() awaits. Set once, in setup().
var _wanderer: Wanderer = null
# True from the moment a card commits to playing (or a turn ends) until
# its own impact/enemy-turn delay has fully resolved - request_play() and
# end_turn() both refuse to start anything new while this is true, so a
# second card/turn can never be armed mid-swing.
var _input_locked: bool = false

func setup(hand_container: HandContainer, enemy_list: Array[FieldEnemy], wanderer: Wanderer) -> void:
	_hand_container = hand_container
	enemies = enemy_list
	_wanderer = wanderer

	player = Combatant.new(RunState.player_max_hp)
	player.hp = RunState.player_hp
	# Toll carries between fights, up to a cap - see RunState.toll.
	player.run_toll_owner = RunState
	player.has_grace = RunState.character.has_grace
	player.grace_cap_mode = RunState.character.grace_cap_mode
	player.grace_window_turns = RunState.character.grace_window_turns
	player.critical_hp_fraction = RunState.character.critical_hp_fraction
	player.energy = player.max_energy
	# Nothing lost in this fight yet (RunState.hp_lost_this_combat).
	RunState.begin_combat()
	# The keepsake's part in the fight opening (see TrinketData): its
	# status and Block on the Wanderer now, its free card and Critical-
	# entry Block armed, its extra cards in the opening draw below. The
	# first turn opens without _start_player_turn()'s Block reset, so the
	# opening Block stands until the first enemy turn is over.
	var keepsake: TrinketData = RunState.keepsake
	if keepsake != null:
		keepsake.apply_combat_start(player.statuses)
		player.block += maxi(keepsake.combat_start_block, 0)
		player.first_card_free = keepsake.first_card_free
		player.critical_entry_block = maxi(keepsake.critical_entry_block, 0)
		_end_turn_keep = maxi(keepsake.end_turn_keep, 0)
		# Opening already Critical is not entering it.
		player.critical_entry_armed = not player.is_critical()

	_combatants.clear()
	var enemy_names: Array[String] = []
	var enemy_ids: Array[String] = []
	for enemy in enemies:
		var data: EnemyData = enemy.enemy_data
		var combatant := Combatant.new(data.max_hp if data != null else 1)
		if data != null:
			EnemyTurn.pick_initial_intent(combatant, data)
			# Its passives (the Blackback's Fed), before the pack check
			# below can turn one.
			for status_data: StatusData in data.starting_statuses:
				if status_data != null:
					Status.apply_to(combatant.statuses, status_data)
			enemy_names.append(data.enemy_name)
			# Two enemies can share a name (the Dragonflies) - the file
			# tells them apart in the log.
			enemy_ids.append(data.resource_path.get_file().get_basename())
		_combatants[enemy] = combatant
	# A pack met with one member left (the rest killed in an earlier fight
	# it was escaped from) opens without its pack move.
	_mark_lone_pack_members()

	RunLogger.fight_start(RunLogger.encounter_key(enemy_names), enemy_ids, RunState.run_snapshot())
	for enemy in enemies:
		var logged: Combatant = _combatants[enemy]
		RunLogger.enemy_hp_seen(logged.get_instance_id(), logged.hp)
	if keepsake != null:
		RunLogger.block_gained(maxi(keepsake.combat_start_block, 0))
	RunLogger.turn_started(player.energy)
	# The run log's mechanic lines, off the signals the view already hears.
	if not enemy_pain_turn.is_connected(_log_pain_turn):
		enemy_pain_turn.connect(_log_pain_turn)
		enemy_status_gained.connect(_log_status_gained)
	for enemy in enemies:
		_log_threshold_queued(enemy)

	deck = Deck.new(RunState.deck)
	deck.drawn.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.drawn.connect(func(_card: CardData) -> void: RunLogger.card_drawn())
	deck.discarded.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.set_aside_changed.connect(func() -> void: hand_changed.emit())
	_hand_container.set_deck(deck)
	_hand_container.card_clicked.connect(_on_card_view_clicked)

	hp_changed.emit(player.hp, player.max_hp)
	toll_changed.emit(player.toll)
	for enemy in enemies:
		var combatant: Combatant = _combatants[enemy]
		enemy_hp_changed.emit(enemy, combatant.hp, combatant.max_hp)

	# A status the keepsake opened the fight with shows from the first frame.
	status_changed.emit()
	_push_enemy_target_available()
	energy_changed.emit(player.energy)
	var opening_bonus: int = maxi(keepsake.opening_draw_bonus, 0) if keepsake != null else 0
	_hand_container.draw_cards(turn_draw_amount + opening_bonus)
	_emit_intent_previews()
	# Each body takes the pose of what it opens on - under way through the
	# camera's swing, so a rear is held by the time the frame settles.
	for enemy in enemies:
		_pose_for_intent(enemy)

# The queued action of one enemy as the display should show it - see
# EnemyTurn.preview_intent(). Empty for a dead/unknown enemy.
func get_intent_preview(enemy: FieldEnemy) -> Dictionary:
	var combatant: Combatant = _combatants.get(enemy)
	var data: EnemyData = enemy.enemy_data if enemy != null else null
	if combatant == null or data == null or combatant.hp <= 0:
		return {}
	var preview: Dictionary = EnemyTurn.preview_intent(combatant, data, player)
	# A heal for packmates shows what it will actually heal - the same
	# call the turn makes, without applying it.
	if int(preview.get("type", -1)) == EnemyIntent.IntentType.HEAL_ALLY and not bool(preview.get("pain_turn", false)):
		preview["per_hit"] = _heal_packmates(enemy, int(preview["per_hit"]), false)
	return preview

func _emit_intent_previews() -> void:
	for enemy in enemies:
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

func is_awaiting_target() -> bool:
	return _pending_card_view != null

# The battle as it stands, for reading a card still in hand: the same
# shape resolve_card() gets, with cards_played_before_this the count
# itself (the card hasn't been played). Its target is the one enemy left
# to hit when there is only one - every card can only land there - and
# none with more. Read by CardBonus and the damage numbers on the card
# faces (see BattleOverlay._push_bonus_context()); nothing here changes.
func preview_context() -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	ctx.enemies = _hittable_enemy_combatants()
	ctx.deck = deck
	ctx.cards_played_before_this = cards_played_this_turn
	if ctx.enemies.size() == 1:
		ctx.target = ctx.enemies[0]
	return ctx

# preview_context() aimed at `enemy` - what an armed card's face reads
# while the cursor is over it.
func preview_context_against(enemy: FieldEnemy) -> EffectContext:
	var ctx: EffectContext = preview_context()
	var target: Combatant = _combatants.get(enemy)
	ctx.target = target
	return ctx

# Read-only access for TargetLine, which needs the armed card's own view
# (for its on-screen top-center) and the currently hovered enemy plus its
# screen rect (see get_hovered_enemy_rect()) but shouldn't own or
# duplicate this controller's own targeting state.
func get_pending_card_view() -> CardView:
	return _pending_card_view

func get_hovered_enemy() -> FieldEnemy:
	return _hovered_enemy

func is_choosing() -> bool:
	return _choosing_card_view != null

func get_choosing_card_view() -> CardView:
	return _choosing_card_view

func request_play(card_view: CardView) -> void:
	if _input_locked or _pending_card_view != null or _choice_open() or card_view.card_data == null:
		return
	var card: CardData = card_view.card_data
	if player.energy_cost(card) > player.energy:
		return
	# A fixed Toll the player doesn't hold (Come Due) - the hand shows it
	# faded, and this is the rule behind the fade.
	if EffectResolver.card_blocked(card, player):
		return
	# Every enemy buried - or, for Deny, every one already Denied: an
	# enemy-target card has nothing to land on.
	if card.target_type == CardData.TargetType.ENEMY and not _has_valid_target(card):
		return
	# A SET_ASIDE card (Bide) asks which cards first, unless there is
	# nothing else in the hand to choose - then it just plays.
	var cap: int = _set_aside_cap(card)
	if cap > 0:
		_begin_choice(card_view, cap, CardEffect.EffectType.SET_ASIDE)
		return
	# A CONSUME card (Deny) takes the most expensive other card: picked
	# now, or chosen first when several tie; none to take is fine.
	if _has_effect(card, CardEffect.EffectType.CONSUME):
		var others: Array[CardView] = _other_hand_views(card_view)
		var others_data: Array[CardData] = []
		for view in others:
			others_data.append(view.card_data)
		var picks: Array[int] = ConsumeEffect.candidates(others_data)
		if picks.size() > 1:
			var tied: Array[CardView] = []
			for i in picks:
				tied.append(others[i])
			_begin_choice(card_view, 1, CardEffect.EffectType.CONSUME, tied)
			return
		if picks.size() == 1:
			_pending_consume_view = others[picks[0]]
			_pending_consume_view.set_marked(true)
	_arm_or_play(card_view)

# The card goes on: an enemy-target card arms for its target (from
# wherever it is held), any other resolves now.
func _arm_or_play(card_view: CardView) -> void:
	var card: CardData = card_view.card_data
	if card.target_type == CardData.TargetType.ENEMY:
		_pending_card_view = card_view
		card_view.lift_and_hold(card_view == _choosing_card_view or _pending_consume_view != null)
		target_requested.emit(card)
	else:
		_resolve_play(card_view, null)

func _has_effect(card: CardData, type: CardEffect.EffectType) -> bool:
	for effect in card.effects:
		if effect != null and effect.effect_type == type:
			return true
	return false

# The hand's views other than `card_view`, in hand order.
func _other_hand_views(card_view: CardView) -> Array[CardView]:
	var others: Array[CardView] = []
	for view: CardView in _hand_container.call("_card_views"):
		if view != card_view and view.card_data != null:
			others.append(view)
	return others

# Whether `card` may land on `combatant` (EffectResolver.can_target() -
# not buried, and Deny not on the already Denied).
func _can_target(card: CardData, combatant: Combatant) -> bool:
	return EffectResolver.can_target(card, combatant)

func _has_valid_target(card: CardData) -> bool:
	return EffectResolver.has_target(card, _hittable_enemy_combatants())

# How many cards a SET_ASIDE card may set aside right now: its number,
# capped at the other cards in the hand. 0 for every other card.
func _set_aside_cap(card: CardData) -> int:
	var value: int = 0
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.SET_ASIDE:
			value += effect.value
	if value <= 0:
		return 0
	return mini(value, maxi(deck.hand.size() - 1, 0))

# A hand choice, opened: the card arms the way a targeting card does (the
# hand stops hovering, End Turn greys), then the cards it may take wake up
# to be clicked - each click marks or unmarks one, up to `cap`; a click
# past the cap, or on a card it may not take, does nothing. Clicking the
# armed card again, Enter or Space confirm; right-click or Esc cancel with
# nothing spent. Bide's (SET_ASIDE) takes 0 to `cap` of any other card.
# Deny's (CONSUME) takes exactly `cap` of `eligible` - the cards tied for
# most expensive - and goes on to its target once confirmed.
func _begin_choice(card_view: CardView, cap: int, kind: CardEffect.EffectType, eligible: Array[CardView] = []) -> void:
	_choosing_card_view = card_view
	_choice_marked.clear()
	_choice_cap = cap
	_choice_kind = kind
	_choice_eligible = eligible
	card_view.lift_and_hold(true)
	_hand_container.begin_choice(card_view, eligible)
	hand_choice_started.emit(card_view.card_data.card_name, cap, "CONSUME" if kind == CardEffect.EffectType.CONSUME else "SET ASIDE")
	hand_choice_changed.emit(0, cap)

# Whether a hand choice is open - an armed card's, or the end-of-turn keep.
func _choice_open() -> bool:
	return _choosing_card_view != null or _keep_choice_open

# The end-of-turn keep (TrinketData.end_turn_keep - Frayed Cord): End Turn
# opens it before anything of the turn ends, Bide's mode with no card
# armed - 0 to `cap` hand cards marked, End Turn (or Enter/Space) to
# confirm, right-click/Esc back to the turn with nothing ended. Asked
# whenever the hand holds a card, even one. False, and nothing opened,
# when the keepsake keeps none or the hand is empty.
func _begin_keep_choice() -> bool:
	var cap: int = mini(_end_turn_keep, deck.hand.size())
	if cap <= 0:
		return false
	_keep_choice_open = true
	_choice_marked.clear()
	_choice_cap = cap
	_choice_eligible = []
	_hand_container.begin_choice(null)
	hand_choice_started.emit("END TURN", cap, "KEEP")
	hand_choice_changed.emit(0, cap)
	return true

func toggle_choice(card_view: CardView) -> void:
	if not _choice_open() or card_view == _choosing_card_view:
		return
	if not _choice_eligible.is_empty() and not _choice_eligible.has(card_view):
		return
	if _choice_marked.has(card_view):
		_choice_marked.erase(card_view)
		card_view.set_marked(false)
	elif _choice_marked.size() < _choice_cap:
		_choice_marked.append(card_view)
		card_view.set_marked(true)
	else:
		return
	hand_choice_changed.emit(_choice_marked.size(), _choice_cap)

func confirm_choice() -> void:
	if _keep_choice_open:
		var kept: Array[CardData] = []
		for view in _choice_marked:
			kept.append(view.card_data)
		_close_choice()
		_finish_turn(kept)
		return
	if _choosing_card_view == null:
		return
	var card_view: CardView = _choosing_card_view
	var chosen: Array[CardView] = _choice_marked.duplicate()
	if _choice_kind == CardEffect.EffectType.CONSUME:
		# Exactly one of the tied cards, then on to the target, the
		# chosen card staying marked while it waits.
		if chosen.size() != _choice_cap:
			return
		_pending_consume_view = chosen[0]
		_close_choice(_pending_consume_view)
		_arm_or_play(card_view)
		return
	_close_choice()
	_resolve_play(card_view, null, chosen)

func cancel_choice() -> void:
	if _keep_choice_open:
		_close_choice()
		return
	if _choosing_card_view == null:
		return
	var card_view: CardView = _choosing_card_view
	_close_choice()
	card_view.release()

# `keep` stays marked (Deny's pick, waiting on its target).
func _close_choice(keep: CardView = null) -> void:
	_choosing_card_view = null
	_keep_choice_open = false
	_choice_marked.clear()
	_choice_cap = 0
	_choice_eligible = []
	_hand_container.end_choice(keep)
	hand_choice_ended.emit()

func confirm_target(enemy: FieldEnemy) -> void:
	if _pending_card_view == null:
		return
	if not _can_target(_pending_card_view.card_data, _combatants.get(enemy)):
		return
	var card_view := _pending_card_view
	var consume_view: CardView = _pending_consume_view
	_pending_card_view = null
	_pending_consume_view = null
	_clear_hover()
	_set_cursor_enemy(null)
	_enemy_rects.clear()
	_resolve_play(card_view, enemy, [], consume_view)

func cancel_target() -> void:
	if _pending_card_view == null:
		return
	_pending_card_view.release()
	_pending_card_view = null
	if _pending_consume_view != null and is_instance_valid(_pending_consume_view):
		_pending_consume_view.set_marked(false)
	_pending_consume_view = null
	_clear_hover()
	_set_cursor_enemy(null)
	_enemy_rects.clear()
	target_cancelled.emit()

# End Turn: with a keepsake that keeps cards and a card in hand, the keep
# choice first (_begin_keep_choice()) - and End Turn again confirms it.
func end_turn() -> void:
	if _input_locked:
		return
	if _keep_choice_open:
		confirm_choice()
		return
	cancel_choice()
	if _begin_keep_choice():
		return
	await _finish_turn([])

# The turn ends: the hand discarded but for `keep` (the end-of-turn keep's
# cards, which stay for the next turn's draw to land on top of), Grace
# closed, stance and turn statuses aged, the enemy turn, the next turn.
func _finish_turn(keep: Array[CardData]) -> void:
	RunLogger.turn_ended(player.energy)
	_input_locked = true
	turn_phase_changed.emit(false)
	# The hand fades out in place, card after card; the enemy turn waits
	# for the last of it (below).
	var discard_fade: float = _hand_container.discard_hand(keep)
	_close_grace_window()
	# A stance with a duration ages on the player's own turn ending, the
	# same beat Grace closes on.
	if Stance.tick(player):
		stance_changed.emit(player.stance)
	# A status that lasts only the player's turn (Ransom's Drain) ends with
	# it, before the enemy turn - the readout never claims "this turn" for
	# the enemy's.
	Status.remove_at_turn_end(player.statuses)
	status_changed.emit()
	if discard_fade > 0.0:
		await get_tree().create_timer(discard_fade).timeout
	await _run_enemy_turn()
	_input_locked = false
	if not _check_battle_end():
		_start_player_turn()
		turn_phase_changed.emit(true)

# The play, in order (DESIGN.md, the played card out of the hand):
# - Commit: the cost paid; the card leaves deck.hand (Deck.begin_play()) -
#   no slot, not counted toward the hand cap, in no pile; card_played
#   fires, so a swing starts now; the hand fades the card out.
# - The fade's end (HandContainer.play_fade_duration): the card goes to its
#   pile (Deck.settle_play(), exhausts_on_play()) and DISCARD or SPENT
#   ticks. A card with no battle_animation resolves in this same frame,
#   after it - so the cards it draws fly in once it has gone.
# - A card with a battle_animation resolves at its own impact delay from
#   the commit instead - min(card.impact_time, the clip's real length, so a
#   shorter clip still fires at its own end) - its lunge and hit as before.
# - Resolved: Deck.end_play(). Until then a reshuffle leaves the card in
#   the discard, so a draw on it never draws it back.
# Every existing consumer of the signals below
# (damage_dealt, hp_changed, enemy_hp_changed, RunState.lose_hp, the
# floating number, HP bars) already reacts to whichever of them fires
# once resolve_card() actually runs, so all of that lands in sync with
# the swing with no rewiring - only the wait moved. _input_locked (set
# by the caller path this always runs on) keeps a second card from being
# armed while this is in flight.
func _resolve_play(card_view: CardView, target_enemy: FieldEnemy, set_aside_views: Array[CardView] = [], consume_view: CardView = null) -> void:
	var card: CardData = card_view.card_data
	# Read before anything is spent: whether a cost replacement (Collateral)
	# covers this card depends on the free card and any cost reduction
	# (Leverage) still being there.
	var replacement: Status = player.cost_replacement_for(card)
	var replaced_hp: int = player.replaced_cost_hp(card)
	var energy_paid: int = player.energy_cost(card)
	player.energy -= energy_paid
	# The play is committed: a free card (House Key) is spent here, before
	# card_played re-reads the hand's faces - never on a hover, a face or
	# a cancelled target. So is a cost replacement's charge; its HP is paid
	# as the card resolves, before its effects (EffectContext.replaced_
	# cost_hp). And a waiting cost reduction, unless this card adds to it.
	# A 0-cost card spends neither discount: they wait for the next card
	# that costs something (Combatant.takes_next_card_discount()).
	if Combatant.takes_next_card_discount(card):
		player.first_card_free = false
		Status.spend_cost_reduction(player.statuses, card)
	Status.spend_cost_replacement(player.statuses, replacement)
	_input_locked = true
	# Counted at commit, before anyone hears of the play - so a face that
	# re-reads itself on card_played sees this card as played. The card's
	# own context carries the count from before it (below).
	cards_played_this_turn += 1

	var target_name: String = target_enemy.enemy_data.enemy_name if target_enemy != null and target_enemy.enemy_data != null else ""
	RunLogger.card_started(card.card_name, energy_paid, target_name)
	deck.begin_play(card)
	card_played.emit(card, target_enemy)
	_hand_container.play_card(card, _screen_pos_for(target_enemy))

	# Three moments from the commit: the swing's lead (a clip only), the
	# fade's end (the card to its pile) and the impact (the fade's end
	# without a clip). In time order; the pile first on a tie.
	var settle_at: float = maxf(_hand_container.play_fade_duration, 0.0)
	var has_clip: bool = card.battle_animation != &""
	var impact_at: float = _impact_delay_for(card) if has_clip else settle_at
	var swing_at: float = impact_at - clampf(swing_lead_seconds, 0.0, impact_at)
	var settled: bool = false
	# As before: a swing only for a clip with a delay to lead into.
	var swung: bool = not has_clip or impact_at <= 0.0
	var elapsed: float = 0.0
	while true:
		var next: float = impact_at
		if not settled:
			next = minf(next, settle_at)
		if not swung:
			next = minf(next, swing_at)
		if next > elapsed:
			await get_tree().create_timer(next - elapsed).timeout
			elapsed = next
		if not settled and settle_at <= elapsed:
			deck.settle_play(exhausts_on_play(card))
			settled = true
		if not swung and swing_at <= elapsed:
			card_swing.emit(card)
			swung = true
		if impact_at <= elapsed:
			break
	# A clip shorter than the fade: the card still reaches its pile.
	if not settled:
		deck.settle_play(exhausts_on_play(card))

	card_impact.emit(card)

	var ctx := EffectContext.new()
	ctx.player = player
	ctx.target = _combatants.get(target_enemy)
	ctx.enemies = _hittable_enemy_combatants()
	ctx.deck = deck
	ctx.cards_played_before_this = cards_played_this_turn - 1
	ctx.replaced_cost_hp = replaced_hp
	if replacement != null and replacement.data != null:
		ctx.replaced_cost_source = "status:" + replacement.data.id
	ctx.on_grace_reclaimed = _on_grace_reclaimed
	ctx.on_heal = _on_card_heal
	ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
		_report_damage("player", target_combatant, amount, kind)
	ctx.on_block = _report_block
	# Bide's chosen cards: their own views leave the hand just before the
	# Deck sets their cards aside, so the marked copy is the one that goes.
	for view in set_aside_views:
		if is_instance_valid(view) and view.card_data != null:
			ctx.set_aside_choice.append(view.card_data)
	if not set_aside_views.is_empty():
		_hand_container.release_views(set_aside_views)
	# Deny's pick: its own view leaves the hand as the Deck spends it.
	if consume_view != null and is_instance_valid(consume_view) and consume_view.card_data != null:
		ctx.consume_choice = consume_view.card_data
		_hand_container.release_views([consume_view] as Array[CardView])

	var hp_before_effects: int = player.hp
	_effect_resolver.resolve_card(card, ctx)
	deck.end_play()
	# A CONSUMED card leaves the run's deck when this fight ends: its play
	# is a choice the run log keeps on its own line, whatever the card.
	if card.removal_scope == CardData.RemovalScope.CONSUMED:
		RunLogger.event("consumed_play", {"card": card.card_name, "hp_before": hp_before_effects, "hp_after": player.hp})
	_count_attack_card(card, ctx)
	RunLogger.card_finished()
	# Taken, deepened or replaced by the card just played - and the card
	# faces need to know either way, since a stance changes what the hand
	# says it will do.
	stance_changed.emit(player.stance)

	toll_changed.emit(player.toll)
	status_changed.emit()
	# A kill can leave only buried enemies standing.
	_push_enemy_target_available()
	energy_changed.emit(player.energy)
	# Block/statuses may have moved - the previews' modified numbers and
	# lethal flags follow.
	_emit_intent_previews()
	# A charge broken by this card lets its rear down now, on the same
	# frame its ring closes - the body settling is the confirmation.
	for enemy in enemies:
		_pose_for_intent(enemy)

	_input_locked = false
	_check_battle_end()

# An Attack card has been played: each enemy it was played against - its
# target, and every enemy it could hit when one of its effects hits all
# of them - counts it once (EnemyTurn.take_attack_card(), the Dunecur's
# Roused). Skills, Powers and Stances never count.
func _count_attack_card(card: CardData, ctx: EffectContext) -> void:
	if card.card_type != CardData.CardType.ATTACK:
		return
	var against: Array[Combatant] = []
	if ctx.target != null:
		against.append(ctx.target)
	for effect in card.effects:
		if effect != null and effect.target_scope == CardEffect.TargetScope.ALL_ENEMIES:
			for combatant in ctx.enemies:
				if not against.has(combatant):
					against.append(combatant)
			break
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if against.has(combatant):
			EnemyTurn.take_attack_card(combatant, enemy.enemy_data)

# CardData.impact_time's own clamp: a clip shorter than the authored
# impact_time fires at the clip's own end instead of after it's already
# finished. _wanderer is only used to look up that length - if it's ever
# unset, the authored impact_time is used unclamped rather than dropped
# to 0.
func _impact_delay_for(card: CardData) -> float:
	if card.battle_animation == &"":
		return 0.0
	var delay: float = card.impact_time
	if _wanderer != null:
		var clip_length: float = _wanderer.get_clip_length(card.battle_animation)
		if clip_length > 0.0:
			delay = minf(delay, clip_length)
	return delay

# Where a played card goes: the exhaust pile (true) for a SPENT or
# CONSUMED card, and for a power or a stance - it has done its work once
# played and stays, as a status or a stance stack, so it leaves rotation
# for the rest of the fight like SPENT and is back in the deck next fight.
# For a stance that is what makes a stack one physical copy: reshuffled,
# the same card would stack itself again. Every other card, the discard.
static func exhausts_on_play(card: CardData) -> bool:
	if card.card_type == CardData.CardType.POWER or card.card_type == CardData.CardType.STANCE:
		return true
	return card.removal_scope != CardData.RemovalScope.NONE

# --- Run log: mechanics ---

# An enemy as the run log names it: its data's file name.
func _log_id(enemy: FieldEnemy) -> String:
	if enemy == null or enemy.enemy_data == null:
		return ""
	return enemy.enemy_data.resource_path.get_file().get_basename()

# EnemyTurn.take_turn(), with what the run log wants from around it: the
# escalation stage the turn is taken at; for an intent with an interrupt
# threshold (the Siltjaw's Charge, the Greyshelf's Gape), how it went -
# broken, landed, or skipped by a pain turn or Deny - with what the player
# dealt this turn, the hit's damage and what reached HP, and the attack-
# card stacks (Goaded) it carried into resolution; a pain turn spent; and
# the next intent, when it has a threshold.
func _take_turn_logged(enemy: FieldEnemy, combatant: Combatant, data: EnemyData) -> Dictionary:
	var id: String = _log_id(enemy)
	if not data.escalation_multipliers.is_empty():
		var stage: int = EnemyTurn.escalation_stage(combatant, data)
		RunLogger.escalation_stage(combatant.get_instance_id(), id, stage, data.escalation_multipliers[stage])
	var intent: EnemyIntent = EnemyTurn.current_intent(combatant, data)
	var threshold: int = intent.interrupt_threshold if intent != null and intent.type == EnemyIntent.IntentType.ATTACK else 0
	var dealt: int = combatant.damage_taken_this_turn
	var stacks: int = 0
	if threshold > 0 and intent.counts_attack_cards and data.attack_card_status != null:
		var held: Status = Status.find_in(combatant.statuses, data.attack_card_status)
		stacks = held.stack_count if held != null else 0
	var result: Dictionary = EnemyTurn.take_turn(combatant, data, player)
	if result["pain_turn"]:
		RunLogger.mechanic("pain_turn_spent", {"enemy": id})
	if threshold > 0:
		var outcome: String = "broken" if result["interrupted"] else ("landed" if result["attacked"] else ("pain_turn" if result["pain_turn"] else ("denied" if result["denied"] else "none")))
		var damage: int = 0
		for hit: Dictionary in result["hits"]:
			damage += int(hit["damage"])
		RunLogger.mechanic("threshold_resolved", {"enemy": id, "intent": intent.intent_name, "threshold": threshold, "dealt": dealt, "outcome": outcome, "damage": damage, "to_hp": result["damage_to_hp"], "stacks": stacks})
	if combatant.hp > 0:
		_log_threshold_queued(enemy)
	return result

# The enemy's queued intent has an interrupt threshold: a line saying so.
func _log_threshold_queued(enemy: FieldEnemy) -> void:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or enemy.enemy_data == null:
		return
	var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
	if intent != null and intent.type == EnemyIntent.IntentType.ATTACK and intent.interrupt_threshold > 0:
		RunLogger.mechanic("threshold_queued", {"enemy": _log_id(enemy), "intent": intent.intent_name, "threshold": intent.interrupt_threshold})

func _log_pain_turn(enemy: FieldEnemy) -> void:
	RunLogger.mechanic("pain_turn", {"enemy": _log_id(enemy)})

# Only the phase's own status (Off the rock) - the same signal carries
# others (a pack's alone grant).
func _log_status_gained(enemy: FieldEnemy, status: StatusData) -> void:
	if enemy != null and enemy.enemy_data != null and status != null and status == enemy.enemy_data.phase_status:
		RunLogger.mechanic("phase", {"enemy": _log_id(enemy), "status": status.id})

# Same shape as _resolve_play()'s own await: EnemyTurn.take_turn() has
# already mutated combatant/player HP synchronously by the time this
# awaits anything (rules stay instant), but the report - and everything
# that reacts to it - waits for enemy.play_attack_snap()'s own return
# value, the point in its forward lunge that counts as "landed". Creatures
# have no clips to sync to (see FieldEnemy.play_attack_snap()'s own doc),
# so that snap is this loop's equivalent of a card's battle_animation.
# Runs regardless of whether the attack actually did any damage (a fully
# blocked attack still visibly lunges), the report itself only fires with
# damage_to_hp > 0, same as before.
#
# A pack's shared move (EnemyIntent.simultaneous, the dragonflies' Swarm)
# runs the other way round: when every living member is queued on one,
# every lunge starts in the same frame, one wait covers the longest
# snap, and every hit is reported in the same beat - the flaps and the
# contact as one event. Each member's take_turn() still runs on its own,
# so the rules (block worn down hit by hit, Grace's largest-single-hit
# cap) see three separate hits, as they always did.
func _run_enemy_turn() -> void:
	if _all_living_simultaneous():
		await _run_simultaneous_turn()
	else:
		await _run_sequential_turn()

	player.took_damage_last_turn = player.took_damage_this_turn
	player.took_damage_this_turn = false
	toll_changed.emit(player.toll)

func _run_sequential_turn() -> void:
	# A copy: a countdown that goes off (Sentence) can kill an enemy mid-
	# loop, and _drop_enemy() takes it out of `enemies`.
	for enemy in enemies.duplicate():
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var data: EnemyData = enemy.enemy_data
		if data == null:
			continue
		enemy_acting.emit(enemy)
		var result := _take_turn_logged(enemy, combatant, data)
		# Killed by its own countdown before it could act: reported, dropped,
		# and nothing more of this enemy's turn plays out.
		if _report_countdown(enemy, combatant, result):
			status_changed.emit()
			continue
		if result["pain_turn_triggered"]:
			enemy_pain_turn.emit(enemy)
		if result["phase_triggered"]:
			enemy_status_gained.emit(enemy, data.phase_status)
		# Denied: no move to watch - the readout loses its Denied, and the
		# turn holds a beat so the skip reads.
		if result["denied"]:
			status_changed.emit()
			if denied_beat_sec > 0.0:
				await get_tree().create_timer(denied_beat_sec).timeout
		if result["attacked"]:
			var snap_delay: float = enemy.play_attack_snap(_wanderer)
			if snap_delay > 0.0:
				await get_tree().create_timer(snap_delay).timeout
			_report_enemy_attack(enemy, result)
		# A charge spent lets the rear down first, then any burrow carries on
		# from there. A broken one is already down - it dropped on the card
		# that broke it (_resolve_play()), so this waits on nothing and the
		# burrow follows at once.
		if result["attacked"] or result["interrupted"] or result["denied"]:
			var drop_delay: float = enemy.set_rearing(false)
			if drop_delay > 0.0:
				await get_tree().create_timer(drop_delay).timeout
		var burrow_delay: float = _play_burrow_for(enemy, result)
		if burrow_delay > 0.0:
			await get_tree().create_timer(burrow_delay).timeout
		if result["heal_allies"] > 0:
			_heal_packmates(enemy, result["heal_allies"], true)
		status_changed.emit()
		# The pose of what comes next, landing on the beat the intent shows.
		var pose_delay: float = _pose_for_intent(enemy)
		if pose_delay > 0.0:
			await get_tree().create_timer(pose_delay).timeout
		# take_turn() has already advanced this enemy to its next intent -
		# show it the moment this action has landed.
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
		if player.hp <= 0:
			break

func _run_simultaneous_turn() -> void:
	var acting: Array[FieldEnemy] = []
	var results: Dictionary = {} # FieldEnemy -> take_turn() result
	var longest_snap: float = 0.0
	# A copy, as in _run_sequential_turn(): a countdown can drop an enemy.
	for enemy in enemies.duplicate():
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or enemy.enemy_data == null:
			continue
		enemy_acting.emit(enemy)
		results[enemy] = _take_turn_logged(enemy, combatant, enemy.enemy_data)
		if _report_countdown(enemy, combatant, results[enemy]):
			continue
		if results[enemy]["pain_turn_triggered"]:
			enemy_pain_turn.emit(enemy)
		if results[enemy]["phase_triggered"]:
			enemy_status_gained.emit(enemy, enemy.enemy_data.phase_status)
		acting.append(enemy)
		if results[enemy]["attacked"]:
			longest_snap = maxf(longest_snap, enemy.play_attack_snap(_wanderer))
		# A Denied member sits the shared move out, on the same beat.
		if results[enemy]["denied"]:
			longest_snap = maxf(longest_snap, denied_beat_sec)
		longest_snap = maxf(longest_snap, _play_burrow_for(enemy, results[enemy]))
	if longest_snap > 0.0:
		await get_tree().create_timer(longest_snap).timeout
	for enemy in acting:
		var result: Dictionary = results[enemy]
		if result["attacked"]:
			_report_enemy_attack(enemy, result)
	status_changed.emit()
	for enemy in acting:
		_show_roused(enemy)
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

# A countdown that went off at the start of this enemy's turn (Sentence -
# EnemyTurn.take_turn()'s "countdown_damage"), reported as the player's
# damage but not a card's. True when it killed the enemy, which is then
# already dropped.
func _report_countdown(enemy: FieldEnemy, combatant: Combatant, result: Dictionary) -> bool:
	var taken: int = result.get("countdown_damage", 0)
	if taken > 0:
		_report_damage("player", combatant, taken, "status")
	return combatant.hp <= 0

# The hit as the view hears it, once the lunge has landed: the damage
# that reached HP, and any Grace it opened.
func _report_enemy_attack(enemy: FieldEnemy, result: Dictionary) -> void:
	RunLogger.block_used(result["blocked"], result["absorbed"])
	if enemy.enemy_data != null:
		RunLogger.enemy_attack(enemy.enemy_data.resource_path.get_file().get_basename(), result["intent"], result["hits"])
	if result["damage_to_hp"] > 0:
		_report_damage(enemy, player, result["damage_to_hp"], "attack")
	# A lethal guard that left the player above where the hit found them
	# (Refuse the End's survive HP): the run's HP follows, the way a card's
	# heal does - HP only, no Toll.
	if result["saved_heal"] > 0:
		_heal_run_hp(result["saved_heal"], "lethal_guard")
		hp_changed.emit(player.hp, player.max_hp)
	if result["grace_opened"] > 0:
		RunLogger.grace_opened(result["grace_opened"])
		grace_changed.emit(player.grace)

# The body's pose for its queued intent (FieldEnemy.set_rearing()):
# reared while an intent that asks for it (EnemyIntent.rear_while_
# queued) is queued, not yet broken (its interrupt threshold met) and the
# enemy is above the sand; flat otherwise. Returns how long the change
# takes; 0 when there is none. A plain attack queued above the sand asks
# for the tell (FieldEnemy.set_poised()), cosmetic and not waited on.
func _pose_for_intent(enemy: FieldEnemy) -> float:
	var combatant: Combatant = _combatants.get(enemy)
	var rear: bool = false
	var poised: bool = false
	if combatant != null and combatant.hp > 0 and not combatant.buried and enemy.enemy_data != null:
		var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
		rear = intent != null and intent.rear_while_queued and not EnemyTurn.is_interrupted(combatant, intent) and not EnemyTurn.is_denied(combatant)
		poised = intent != null and intent.type == EnemyIntent.IntentType.ATTACK and not intent.rear_while_queued
	enemy.set_poised(poised)
	_show_roused(enemy)
	return enemy.set_rearing(rear)

# The body shows the stacks of its attack_card_status it holds (the
# Dunecur's crest, FieldEnemy.set_roused()) - after each card, each enemy
# turn and at the fight's start, with the intent pose.
func _show_roused(enemy: FieldEnemy) -> void:
	var combatant: Combatant = _combatants.get(enemy)
	var data: EnemyData = enemy.enemy_data
	if combatant == null or data == null or data.attack_card_status == null:
		return
	var held: Status = Status.find_in(combatant.statuses, data.attack_card_status)
	enemy.set_roused(held.stack_count if held != null and combatant.hp > 0 else 0)

# An interrupted enemy going under, or a buried one coming up, on the
# field body (FieldEnemy.play_burrow()) - how long that takes, for the
# turn to wait on the way it waits on a lunge. 0 when neither happened.
func _play_burrow_for(enemy: FieldEnemy, result: Dictionary) -> float:
	if result["buried"]:
		return enemy.play_burrow(true)
	if result["surfaced"]:
		return enemy.play_burrow(false)
	return 0.0

# True when the fight is a cluster acting as one this turn: more than one
# living enemy, all of one group, every one queued on a simultaneous
# intent. A lone enemy, a mixed queue or a lone survivor of a pack takes
# the ordinary sequential turn.
func _all_living_simultaneous() -> bool:
	var living: int = 0
	var group: StringName = &""
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or enemy.enemy_data == null:
			continue
		if enemy.group == &"":
			return false
		if living == 0:
			group = enemy.group
		elif enemy.group != group:
			return false
		var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
		if intent == null or not intent.simultaneous:
			return false
		living += 1
	return living > 1

func _start_player_turn() -> void:
	player.block = 0
	# The refill, and Dying Light's 1 if the turn begins Critical - judged
	# here, before any tick, so entering Critical later gives nothing
	# until the next turn starts.
	player.energy = player.turn_start_energy()
	# The run log's turn opens on the refill, before any tick it counts.
	RunLogger.turn_started(player.energy)
	cards_played_this_turn = 0
	# A fresh turn for every interrupt threshold.
	player.damage_taken_this_turn = 0
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null:
			combatant.damage_taken_this_turn = 0

	Status.tick_all(player.statuses, func(amount: int, ticking: Status) -> void:
		# For the run log: the loss, and its Toll, are this status's.
		RunLogger.push_source("status:" + (ticking.data.id if ticking.data != null else ""))
		var lost := DamagePipeline.apply_bypass(amount, player)
		if lost > 0:
			player.gain_self_loss_toll(lost)
			_lose_run_hp(lost, "status")
			hp_changed.emit(player.hp, player.max_hp)
			toll_changed.emit(player.toll)
		RunLogger.pop_source()
	)
	# A tick is a loss to their own effect like any other: one that sets a
	# counter off (The Return) Drains now, in a context of its own - no
	# card is resolving to carry it.
	if player.pending_drain > 0:
		var ctx := EffectContext.new()
		ctx.player = player
		ctx.enemies = _hittable_enemy_combatants()
		ctx.deck = deck
		ctx.on_heal = _on_card_heal
		ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
			_report_damage("player", target_combatant, amount, kind)
		ctx.on_block = _report_block
		RunLogger.push_source("drain")
		ctx.resolve_pending_drain()
		RunLogger.pop_source()
	Status.remove_expired(player.statuses)
	# What was waiting for this turn (Ransom) takes hold now, after the
	# ticks.
	Status.resolve_turn_start_triggers(player.statuses)
	# A tick that took them into Critical counts like any other HP loss.
	Status.resolve_critical_triggers(player)
	status_changed.emit()
	# The enemy turn may have buried or surfaced someone.
	_push_enemy_target_available()
	energy_changed.emit(player.energy)
	# Block just reset to 0 and statuses ticked: lethal flags change here.
	_emit_intent_previews()

	if not _check_battle_end():
		_hand_container.draw_cards(turn_draw_amount)
		# Bide's set-aside cards come back after the draw, so it draws as
		# many as ever; the readout's "Set aside" line goes with them.
		if not deck.set_aside_pile.is_empty():
			deck.return_set_aside()
			status_changed.emit()

func _check_battle_end() -> bool:
	if player.hp <= 0:
		RunLogger.turn_ended(player.energy)
		battle_lost.emit()
		return true
	if _living_enemy_combatants().is_empty():
		RunLogger.turn_ended(player.energy)
		battle_won.emit()
		return true
	return false

# This enemy's current block, for its EnemyStatus's segment - read by
# BattleOverlay on status_changed. 0 for a dead/unknown enemy.
func get_enemy_block(enemy: FieldEnemy) -> int:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return 0
	return combatant.block

# This enemy's statuses as its EnemyStatus row reads them (Status.label())
# - read by BattleOverlay on status_changed. Empty for a dead/unknown
# enemy: whatever it held went with it.
func get_enemy_status_labels(enemy: FieldEnemy) -> PackedStringArray:
	var labels := PackedStringArray()
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return labels
	for active: Status in combatant.statuses:
		var text: String = active.label()
		if not text.is_empty():
			labels.append(text)
	return labels

# This enemy's statuses themselves, for what its readout's hover reveal
# says they do (Status.describe()) - read by BattleOverlay on status_
# changed, beside the labels above. A copy; empty for a dead/unknown
# enemy, like the labels.
func get_enemy_statuses(enemy: FieldEnemy) -> Array[Status]:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return []
	return combatant.statuses.duplicate()

# The living enemies a card can reach - not the buried (Combatant.
# buried). What every card's context carries as ctx.enemies.
func _hittable_enemy_combatants() -> Array[Combatant]:
	var hittable: Array[Combatant] = []
	for combatant in _living_enemy_combatants():
		if not combatant.buried:
			hittable.append(combatant)
	return hittable

# Enemy-target cards fade in the hand while every enemy is buried - told
# before each energy_changed, which is what re-reads playability.
func _push_enemy_target_available() -> void:
	_hand_container.set_enemy_target_available(not _hittable_enemy_combatants().is_empty())

func _living_enemy_combatants() -> Array[Combatant]:
	var living: Array[Combatant] = []
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null and combatant.hp > 0:
			living.append(combatant)
	return living

# source/target_combatant identify who dealt/received the hit; the
# emitted signal reports the FieldEnemy/"player" pair the view actually
# understands, and also fans out into hp_changed/enemy_hp_changed so the
# overlay never has to re-derive HP from a damage event itself.
# Grace spent: the rules layer has already taken it off player.grace and
# put it back on player.hp (see EffectContext.grace_reclaim()); this
# mirrors it onto the run's own HP and tells the readouts. Through
# RunState.heal(), which touches HP and nothing else - Toll accrues only
# from SELF-inflicted loss (status ticks, SELF_DAMAGE, SELF_DAMAGE_TOLL),
# so reclaiming cannot generate Toll or undo any.
# A card put HP back. Mirrored onto the run's own HP the same way a loss
# is - RunState.heal() touches HP and nothing else, so this generates no
# Toll and undoes none.
func _on_card_heal(amount: int) -> void:
	_heal_run_hp(amount)
	hp_changed.emit(player.hp, player.max_hp)

func _on_grace_reclaimed(amount: int) -> void:
	var before: int = RunState.player_hp
	RunState.heal(amount)
	RunLogger.grace_reclaimed(RunState.player_hp - before)
	hp_changed.emit(player.hp, player.max_hp)
	grace_changed.emit(player.grace)

# End of the player's turn: the window ages, and whatever Grace is left
# when it runs out is gone. Runs BEFORE the enemy turn (see end_turn()),
# so the hits that are about to land open a fresh window rather than
# topping up a spent one.
func _close_grace_window() -> void:
	if player.grace <= 0:
		player.grace_turns_left = 0
		return
	player.grace_turns_left -= 1
	if player.grace_turns_left > 0:
		return
	RunLogger.grace_lost(player.grace)
	player.grace = 0
	grace_changed.emit(0)

# EffectContext.on_block: a hit of the player's met an enemy's block.
func _report_block(target_combatant: Combatant, _blocked: int, damage_to_hp: int) -> void:
	var enemy := _field_enemy_for(target_combatant)
	if enemy != null:
		enemy_hit_blocked.emit(enemy, damage_to_hp <= 0)

func _report_damage(source: Variant, target_combatant: Combatant, amount: int, kind: String) -> void:
	if target_combatant == player:
		damage_dealt.emit(source, "player", amount, kind)
		# The log's source: the enemy by name, else the kind ("self",
		# "status").
		var source_name: String = kind
		if source is FieldEnemy and (source as FieldEnemy).enemy_data != null:
			source_name = (source as FieldEnemy).enemy_data.enemy_name
		_lose_run_hp(amount, source_name)
		hp_changed.emit(player.hp, player.max_hp)
	else:
		RunLogger.damage_dealt(target_combatant.get_instance_id(), amount, target_combatant.hp)
		var enemy := _field_enemy_for(target_combatant)
		damage_dealt.emit(source, enemy, amount, kind)
		if enemy != null:
			enemy_hp_changed.emit(enemy, target_combatant.hp, target_combatant.max_hp)
			if target_combatant.hp <= 0:
				_drop_enemy(enemy)
			else:
				if EnemyTurn.check_pain_turn(target_combatant, enemy.enemy_data):
					# Below its pain line on the player's turn: the action it
					# shows now is the one cancelled.
					enemy_pain_turn.emit(enemy)
					enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
				if EnemyTurn.check_phase(target_combatant, enemy.enemy_data):
					# Below its phase line: the status is up at once, and the
					# intent it changes (Off the rock's extra hit) with it.
					enemy_status_gained.emit(enemy, enemy.enemy_data.phase_status)
					status_changed.emit()
					enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

# The run's HP down by `amount`, and the log told what it actually lost
# (lose_hp() floors at 0) and to what.
func _lose_run_hp(amount: int, source: String) -> void:
	var before: int = RunState.player_hp
	RunState.lose_hp(amount)
	RunLogger.player_hp_lost(before - RunState.player_hp, source)

# The run's HP up, the log told what it actually got back - from `source`,
# or whatever it says is acting (the card resolving) when that's empty.
func _heal_run_hp(amount: int, source: String = "") -> void:
	var before: int = RunState.player_hp
	RunState.heal(amount)
	RunLogger.player_healed(RunState.player_hp - before, source)

# The enemy is dead: out of the lists first (so no later preview/turn/
# rect pass touches a node that may be freed), then told. The hover
# clears too, or an armed card could keep a sinking body lit.
func _drop_enemy(enemy: FieldEnemy) -> void:
	RunLogger.enemy_died(_log_id(enemy))
	enemies.erase(enemy)
	_combatants.erase(enemy)
	_enemy_rects.erase(enemy)
	if _hovered_enemy == enemy:
		_clear_hover()
	if _cursor_enemy == enemy:
		_set_cursor_enemy(null)
	_mark_lone_pack_members()
	enemy_defeated.emit(enemy)

# Every living enemy with no living packmate left in the fight (none
# sharing its FieldEnemy.group - an ungrouped enemy has none) stops using
# its pack moves and turns what waits for that (EnemyTurn.leave_pack()):
# the island's last dragonfly bites instead of Swarming alone, the
# Nipper stops foraging, the Blackback turns Hungry. A queued move that
# gives way, or a status that turns, is shown at once. Living by HP, not
# by the list - a card that kills several drops them one at a time, and
# the ones still to go are already dead.
func _mark_lone_pack_members() -> void:
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or combatant.pack_alone or enemy.enemy_data == null:
			continue
		if _has_living_packmate(enemy):
			continue
		var held: Array[StatusData] = []
		for active: Status in combatant.statuses:
			held.append(active.data)
		if EnemyTurn.leave_pack(combatant, enemy.enemy_data):
			for active: Status in combatant.statuses:
				if active.data != null and not held.has(active.data):
					enemy_status_gained.emit(enemy, active.data)
			status_changed.emit()
			enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

# A HEAL_ALLY's heal (the Nipper's Forage): each living packmate of
# `enemy` heals `amount`, capped at its max. Returns the HP healed in
# all; `apply` false only measures it - the intent preview's number, from
# the same call the turn makes.
func _heal_packmates(enemy: FieldEnemy, amount: int, apply: bool) -> int:
	if enemy == null or enemy.group == &"" or amount <= 0:
		return 0
	var healed: int = 0
	for other in enemies:
		if other == enemy or other.group != enemy.group:
			continue
		var combatant: Combatant = _combatants.get(other)
		if combatant == null or combatant.hp <= 0:
			continue
		var heal: int = mini(amount, maxi(combatant.max_hp - combatant.hp, 0))
		healed += heal
		if apply and heal > 0:
			combatant.hp += heal
			RunLogger.enemy_hp_seen(combatant.get_instance_id(), combatant.hp)
			enemy_hp_changed.emit(other, combatant.hp, combatant.max_hp)
	return healed

func _has_living_packmate(enemy: FieldEnemy) -> bool:
	if enemy.group == &"":
		return false
	for other in enemies:
		if other == enemy or other.group != enemy.group:
			continue
		var combatant: Combatant = _combatants.get(other)
		if combatant != null and combatant.hp > 0:
			return true
	return false

func _field_enemy_for(combatant: Combatant) -> FieldEnemy:
	for enemy in _combatants:
		if _combatants[enemy] == combatant:
			return enemy
	return null

func _screen_pos_for(target: FieldEnemy) -> Vector2:
	var camera := get_viewport().get_camera_3d()
	if target != null and camera != null:
		return camera.unproject_position(target.global_position + Vector3.UP * enemy_head_height)
	var overlay := get_parent() as Control
	var overlay_size: Vector2 = overlay.size if overlay != null else Vector2.ZERO
	return overlay_size / 2.0 + self_play_screen_offset

func _on_card_view_clicked(card_view: CardView) -> void:
	if _choice_open():
		if card_view == _choosing_card_view:
			confirm_choice()
		else:
			toggle_choice(card_view)
		return
	request_play(card_view)

# Gated on awaiting-target or Bide's open choice: this controller only
# reacts to input while a card is armed - waiting for an enemy click, or
# for its choice to be confirmed (Enter/Space) or cancelled (right-click/
# Esc) - everything else (movement, camera, ...) is untouched - and
# already frozen by RegionField anyway.
func _unhandled_input(event: InputEvent) -> void:
	if _choice_open():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_choice()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				cancel_choice()
				get_viewport().set_input_as_handled()
			elif event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER or event.keycode == KEY_SPACE:
				confirm_choice()
				get_viewport().set_input_as_handled()
		return
	if _pending_card_view == null:
		return

	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_target()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var enemy := _enemy_at(event.position)
			if enemy != null:
				confirm_target(enemy)
				get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		cancel_target()
		get_viewport().set_input_as_handled()
		return

# The target-under-cursor test runs every physics frame while a card is
# armed (not on mouse motion): the rects move with the camera swing and
# the enemies' own lunges, so a still cursor has to re-evaluate too, and
# motion a card's own Control swallowed never has to reach this node.
func _physics_process(_delta: float) -> void:
	if _pending_card_view == null:
		return
	_refresh_enemy_rects()
	_update_hover(get_viewport().get_mouse_position())

func _update_hover(screen_pos: Vector2) -> void:
	var enemy := _enemy_at(screen_pos)
	_set_cursor_enemy(enemy)
	if enemy == null:
		enemy = _default_target()
	if enemy == _hovered_enemy:
		return
	_clear_hover()
	_hovered_enemy = enemy
	if _hovered_enemy != null:
		_hovered_enemy.set_highlight(true)

func _set_cursor_enemy(enemy: FieldEnemy) -> void:
	if enemy == _cursor_enemy:
		return
	_cursor_enemy = enemy
	hovered_enemy_changed.emit(enemy)

func _clear_hover() -> void:
	if _hovered_enemy != null:
		_hovered_enemy.set_highlight(false)
		_hovered_enemy = null

# What an armed card means when the cursor is over none of them: the
# leftmost living enemy on screen - the one nearest the Wanderer along
# the battle line - shown with the same highlight and target line a
# hover gets. Only in a fight with more than one living enemy; against
# a single enemy nothing is indicated until the cursor reaches it, as
# before. Reads the rect cache, so a member behind the camera is never
# the default.
func _default_target() -> FieldEnemy:
	if enemies.size() < 2:
		return null
	var best: FieldEnemy = null
	var best_x: float = INF
	for enemy: FieldEnemy in _enemy_rects:
		var rect: Rect2 = _enemy_rects[enemy]
		var centre_x: float = rect.get_center().x
		if centre_x < best_x:
			best_x = centre_x
			best = enemy
	return best

# Each living enemy's screen-space bounding rect of its model's world
# AABB (FieldEnemy.get_screen_rect() - the real mesh bounds, as placed,
# padded by target_padding_px on every side). No physics shape, no
# camera-distance dependence - what you can see is what you can target,
# plus a little. Recomputed by _physics_process() while a card is armed;
# _enemy_at() reads the cache. An enemy whose AABB reaches behind the
# camera gets no rect.
func _refresh_enemy_rects() -> void:
	_enemy_rects.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var combatant: Combatant = _combatants.get(enemy)
		# The buried can't be targeted: no rect, so no click, hover or
		# default target lands on one - nor, for the armed card, one it
		# may not land on (Deny on the already Denied).
		if combatant == null or combatant.hp <= 0 or combatant.buried:
			continue
		if _pending_card_view != null and not _can_target(_pending_card_view.card_data, combatant):
			continue
		var rect: Rect2 = enemy.get_screen_rect(camera, target_padding_px)
		if rect.size == Vector2.ZERO:
			continue
		_enemy_rects[enemy] = rect

# The enemy whose padded rect holds screen_pos; on overlap, the one
# nearest the camera. Rebuilds the cache if a click lands before the
# first armed physics frame.
func _enemy_at(screen_pos: Vector2) -> FieldEnemy:
	if _enemy_rects.is_empty():
		_refresh_enemy_rects()
	var camera := get_viewport().get_camera_3d()
	var best: FieldEnemy = null
	var best_distance: float = INF
	for enemy: FieldEnemy in _enemy_rects:
		var rect: Rect2 = _enemy_rects[enemy]
		if not rect.has_point(screen_pos):
			continue
		var distance: float = camera.global_position.distance_to(enemy.global_position) if camera != null else 0.0
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

# The hovered enemy's padded screen rect (see _refresh_enemy_rects()) -
# TargetLine ends at its centre. Empty when nothing is hovered.
func get_hovered_enemy_rect() -> Rect2:
	if _hovered_enemy == null:
		return Rect2()
	return _enemy_rects.get(_hovered_enemy, Rect2())
