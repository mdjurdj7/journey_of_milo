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
# The last Attack played again (Second Swing - _replay_attack()), after
# the card that replays it: the Wanderer swings it as if played - its
# clip and lunge at `target` (null for an all-enemies Attack) - and its
# card_swing and card_impact follow as a play's do. Not card_played: it
# isn't one (no play sound, no hand, no cost).
signal card_replayed(card: CardData, target: FieldEnemy)
# A played card has resolved in full - its effects, its further hits'
# beats and any replay it set off (Second Swing) - so every HP it cost has
# landed. Before what the enemy it hit answers with (Coiled) and the
# play's wind-down (_after_play()). What the HP bar's cost preview holds
# for (BattleOverlay).
signal play_resolved(card: CardData)
signal hand_changed()
signal target_requested(card: CardData)
signal target_cancelled()
# A hand choice (see _begin_choice()) - Bide's Keep
# among cards tied for most expensive, or the keep a keepsake allows at
# the end of the turn (_begin_keep_choice()): opened with up to `cap`
# cards to mark, the verb that names what happens to them, what to click
# to confirm when that's something other than DONE (END TURN, the keep's;
# empty otherwise) and whether it has a DONE (Bide's - a variable count,
# confirm_choice()), the count marked as it moves, and closed (confirmed,
# or cancelled with nothing spent).
signal hand_choice_started(confirm_label: String, cap: int, verb: String, done: bool)
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
# The fight's opening hold (lock_entry_input()) starts (true) and ends
# (false) - BattleOverlay disables End Turn through it.
signal entry_lock_changed(locked: bool)
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
# One hit of `enemy`'s attack the player's Block or absorb took whole: no
# damage_dealt for it - BattleFeedback's blocked stop and armored sound.
signal player_hit_blocked(enemy: FieldEnemy)
# A hit on mound `mound` of a dug-in enemy's row (EnemyIntent.IntentType.
# DIG - each mound its own target, Combatant.mound_guards): `amount` HP
# off it, `hp` of `max_hp` left - in place of damage_dealt, which is the
# enemy's own. Then mound_broken when it reached 0: `own` for the one the
# enemy was under, up through it now, the overkill to follow as the
# enemy's damage_dealt.
signal mound_damaged(enemy: FieldEnemy, mound: int, amount: int, hp: int, max_hp: int)
signal mound_broken(enemy: FieldEnemy, mound: int, own: bool)
# A status living on one of `enemy`'s intents (StatusData.intent_mark -
# Brace's, Garnish's) has left it: `entry` is EnemyTurn.mark_entry()'s,
# with "outcome" "spent" (its intent landed - "before" and "after" the
# hits' totals either side of it) or "lost" ("reason": "replaced",
# "cancelled" or "enemy died").
signal intent_mark_settled(enemy: FieldEnemy, entry: Dictionary)
# Something a combatant gained that no damage_dealt carries, for its
# floating number: `kind` "heal" (HP back - a card's heal or Drain, Grace
# reclaimed, Devour, a lethal guard's lift, a packmate's Forage) or
# "block" (Block gained - a card, the Critical-entry keepsake, an enemy's
# Defend). `target` as damage_dealt's: "player" or a FieldEnemy. Sent in
# the frame its readout moves. The fight's opening Block is read instead
# (opening_block_gained), shown as the intents reveal.
signal combat_text(target: Variant, amount: int, kind: String)
# source/target are each either the String "player" or a FieldEnemy node -
# whichever combatant actually dealt/received the hit.
# An enemy's death begins. Its HP reached 0 on a hit some time before:
# the rules dropped it then (out of `enemies`/_combatants at once), but
# the killing blow's presentation - every hit of the card, numbers, hit-
# stop, recoil, the play effect - is let finish first (_hold_death_for(),
# _release_deaths_when_due()). The overlay drops the member's displays on
# this; RegionField starts its death (FieldEnemy.settle_and_free()), and
# the fight hears it end through FieldEnemy.death_finished - the last
# one's is what lets battle_won go (_check_battle_end()).
signal enemy_defeated(enemy: FieldEnemy)
# The deaths held for a killing blow have just begun (enemy_defeated sent
# for each) - the card that dealt it lets input go on this.
signal deaths_released()
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
# Devour (devour()): whether it can be used now, and whether this turn's
# uses are spent - emitted whenever either may have changed, and when
# what it would eat changes (a card armed or disarmed). DevourButton
# re-reads is_devour_lit() on it.
signal devour_changed(available: bool, used: bool)
# A hand card was devoured: out of the hand to the Spent pile, unplayed.
signal card_devoured(card: CardData)
# Sheathe (sheathe()): whether it can be used now, and whether this turn's
# use is spent - at the same moments as devour_changed, and when its pick
# opens or closes. SheatheButton re-reads is_sheathe_lit() on it.
signal sheathe_changed(available: bool, used: bool)
# A hand card was sheathed: it keeps for this turn's end (Deck.grant_keep_
# once()), where it stands in the hand.
signal card_sheathed(card: CardData)
# A hand card was Devoured by the keyword (Take In), as its bite starts -
# once per card eaten; never the Devour button's (card_devoured).
signal keyword_devoured(card: CardData)
signal battle_won()
signal battle_lost()

@export var turn_draw_amount: int = 5
# The HP the play being committed pays on top of its Energy (Collateral -
# Combatant.replaced_cost_hp(), read before the Energy is spent), from its
# commit until the next: what the play sound's Critical check counts.
var play_hp_cost: int = 0
# A Stunned enemy's skipped turn, or a Delayed one's do-nothing turn,
# holds this long (seconds), the status gone from the readout, so the
# turn reads - it has no lunge to wait on.
@export var denied_beat_sec: float = 0.5
# See card_swing.
@export var swing_lead_seconds: float = 0.04
# A card hit that lands several times as it resolves (CardEffect.repeat_
# per_earlier_play_tag - Lash) shows them this far apart (seconds), the
# first at the card's impact - each its own number, contact and the
# multi-hit stop, as an enemy's several hits are (enemy_hit_interval).
# No swing of their own.
@export var card_hit_interval: float = 0.12
# A strike back (Coiled - _counter_strikes()) starts its lunge this long
# after the card it answers has resolved, so the card's own blows -
# Blood Arc's staggered reactions among them - have shown first.
@export var counter_strike_delay: float = 0.35
# An enemy attack of several hits (Peck, Tail Lash) reports them this far
# apart (seconds), the first at its move's contact - each its own number,
# contact sound and hit-stop (_report_enemy_attack()).
@export var enemy_hit_interval: float = 0.12
# A killed enemy's death waits for the blow that killed it to show in
# full - kill_presentation_time's answer for it, then this much more
# (real seconds) - before it begins (_hold_death_for()).
@export var kill_presentation_margin: float = 0.1
@export var enemy_head_height: float = 1.8
# Where a SELF/NONE card's play tween aims, relative to the viewport's own
# center - there's no "target" to unproject for those, just somewhere up
# and away from the hand.
@export var self_play_screen_offset: Vector2 = Vector2(0.0, -250.0)
# Padding around each enemy's projected model rect for the armed-card
# target test - see _refresh_enemy_rects().
@export var target_padding_px: float = 16.0
# Every enemy's target is at least this many pixels each way (FieldEnemy.
# get_pick_rect()) - RegionField's min_target_size_px, the one floor the
# field's click-to-move shares, set as the fight opens. Not on mounds.
var min_target_size_px: float = 0.0
# Devour - the Wanderer's own action, not a card (devour()): the HP one
# eaten card gives back, how many it may eat per turn, and the Energy each
# eating costs - paid when the card is eaten, and needed in hand for
# Devour to be available at all (is_devour_available()).
@export var devour_heal_amount: int = 3
@export var devour_uses_per_turn: int = 1
@export var devour_energy_cost: int = 1:
	set(value):
		devour_energy_cost = value
		if is_inside_tree():
			_emit_devour_changed()
# Sheathe - the Samurai's own action, not a card (sheathe()): how many
# cards it may keep per turn, and the Energy each costs - paid when the
# card is picked, and needed in hand for Sheathe to be available at all
# (is_sheathe_available()).
@export var sheathe_uses_per_turn: int = 1:
	set(value):
		sheathe_uses_per_turn = value
		if is_inside_tree():
			_emit_sheathe_changed()
@export var sheathe_energy_cost: int = 1:
	set(value):
		sheathe_energy_cost = value
		if is_inside_tree():
			_emit_sheathe_changed()

var deck: Deck
var player: Combatant
var enemies: Array[FieldEnemy] = []
var cards_played_this_turn: int = 0
# Whether this class has Devour at all (CharacterData.has_devour), from
# setup(). Off, is_devour_available() is always false and devour() does
# nothing.
var has_devour: bool = true
# Devours this player turn - reset at its start (_start_player_turn()).
var _devour_uses_this_turn: int = 0
# Whether this class has Sheathe (CharacterData.has_sheathe), from setup().
# Off, is_sheathe_available() is always false and sheathe() does nothing.
var has_sheathe: bool = false
# Sheathes this player turn - reset at its start, as Devour's are.
var _sheathe_uses_this_turn: int = 0
# Sheathe was clicked: the next hand card clicked keeps - see sheathe().
var _sheathe_picking: bool = false

var _hand_container: HandContainer
var _pending_card_view: CardView = null
# The armed card can't be played (unaffordable, blocked, nothing to land
# on) and is armed for Devour alone: no enemy is a target - see
# _arm_for_devour().
var _pending_devour_only: bool = false
# Devour was clicked with nothing armed: the next hand card clicked is
# eaten - see _begin_devour_pick().
var _devour_picking: bool = false
# The GRANT_KEEP card (Bide) armed while its choice is open, the other hand cards
# marked for it, and how many may be - see _begin_choice().
var _choosing_card_view: CardView = null
# The cards the open choice may take, when it names them (Twice Over's -
# everything else in the hand is faded and unpickable); empty for any.
var _choice_eligible: Array[CardView] = []
var _choice_marked: Array[CardView] = []
var _choice_cap: int = 0
# The end-of-turn keep is open (see _begin_keep_choice()): a choice with
# no armed card, confirmed by End Turn. How many cards the held keepsake
# lets the hand keep (TrinketData.end_turn_keep), read as the fight opens.
var _keep_choice_open: bool = false
var _end_turn_keep: int = 0
# The most unspent Energy the held pieces carry into the next turn
# (TrinketData.energy_carry - Departure Stub), read as the fight opens;
# and what the turn just ended left for the next one's refill.
var _energy_carry: int = 0
var _energy_carried: int = 0
var _hovered_enemy: FieldEnemy = null
# The enemy under the cursor itself, without the default - see
# hovered_enemy_changed.
var _cursor_enemy: FieldEnemy = null
var _enemy_rects: Dictionary = {} # FieldEnemy -> Rect2, see _refresh_enemy_rects()
# A dug-in enemy's mounds take its place as targets (EnemyIntent.
# IntentType.DIG): {"enemy": FieldEnemy, "mound": int, "rect": Rect2} each,
# refreshed with _enemy_rects. The mound the cursor was last over in
# _enemy_at() (-1: none, or the enemy itself), and the one lit.
var _mound_rects: Array[Dictionary] = []
var _cursor_mound: int = -1
# An enemy's intent readout on screen, for a card that marks an intent
# (Brace, Garnish) to be aimed at it as well as at the body: (enemy:
# FieldEnemy) -> Rect2, empty when it shows none. Set by BattleOverlay,
# which owns the readouts.
var intent_rect_of: Callable = Callable()
# The intents a card that marks one may be aimed at now: FieldEnemy ->
# Rect2 (_refresh_enemy_rects()), read by _enemy_at() before the bodies.
var _intent_rects: Dictionary = {}
var _hovered_mound: int = -1
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
# The fight's opening hold (lock_entry_input()): cards, End Turn,
# targeting and Devour take no input until it ends. The hand still deals
# in under it.
var _entry_locked: bool = false
# The signal that ends the hold early (lock_entry_input()'s `release`),
# connected while it is on; null when there is none.
var _entry_release: Signal = Signal()
# A play is resolving (_resolve_play(), commit to resolved), and a next
# one is waiting - on it, or on the Wanderer's swing reaching its cancel
# point (_resolve_play()'s cancel window). While one resolves a next card
# can still be armed and confirmed; only one waits at a time, and End
# Turn and Devour wait with it.
var _play_in_flight: bool = false
var _play_queued: bool = false
# How long a killing hit on an enemy takes to show in full, in real
# seconds from the hit: (enemy: FieldEnemy, amount: int) -> float. Set by
# BattleOverlay, which owns the reactions and numbers; unset, a death
# waits only kill_presentation_margin.
var kill_presentation_time: Callable = Callable()
# Killed, their deaths waiting on the blow (enemy_defeated not yet sent)...
var _pending_deaths: Array[FieldEnemy] = []
# ...dying (sent, FieldEnemy.death_finished not yet heard)...
var _dying: Array[FieldEnemy] = []
# ...and when the held deaths may begin, in real microseconds.
var _death_release_usec: int = 0
var _death_release_running: bool = false
# The last enemy is down and its death is running: battle_won waits for
# it (_maybe_win()).
var _win_waiting: bool = false
# Set by the resolving card's EffectContext.on_replay (Second Swing): the
# last Attack is played again once the card has resolved (_replay_attack()).
var _replay_pending: bool = false
# The FieldEnemy and mound the last Attack this turn was played at - what
# Combatant.last_attack_target is to the rules, for the view: where a
# replay swings. Cleared with it each turn.
var _last_attack_enemy: FieldEnemy = null
var _last_attack_mound: int = -1
# The Block the held pieces opened the fight with (TrinketData.combat_
# start_block) - BattleOverlay shows it once the battle frame settles.
var opening_block_gained: int = 0
# Set by the resolving card's EffectContext.on_extra_hit: each further
# hit's reports, one list per hit, held for that hit's beat (_land_extra_
# hits()).
var _extra_hit_reports: Array[Array] = []
# While a card's own effects resolve: a kill only notes that the packs
# need looking at (_pack_check_due), and _mark_lone_pack_members() runs
# once the card is done - so a card that kills a whole pack never turns
# a member that it is about to kill too (a damage-to-all lands and
# reports one target at a time).
var _deferring_pack_check: bool = false
var _pack_check_due: bool = false
# Which of the Wanderer's turns it is, from 1, and whether the enemies
# are acting - so a death knows when it fell (_fell_on): the player turn
# it died in, or -1 on an enemy's turn. _roster is everyone the fight
# opened with, for felled_together().
var _player_turn: int = 1
var _enemy_phase: bool = false
var _fell_on: Dictionary = {} # FieldEnemy -> player turn, -1 on the enemies'
var _roster: Array[FieldEnemy] = []
# The keepsake's draw for a card that takes HP from two or more enemies
# (TrinketData.draw_on_multi_hit): the enemies the resolving card has
# taken HP from, and whether this turn's draw is spent.
var _card_damaged: Dictionary = {} # Combatant -> true
var _multi_hit_draw_used: bool = false
# Whether this turn's card-count draw (TrinketData.draw_on_card_count -
# Worn Page) has been taken. Reset at the turn's start.
var _card_count_draw_used: bool = false
# The held pieces' Skill-after-Attack draw (Knotted Cord) spent this turn.
var _skill_after_attack_draw_used: bool = false
# The HP enemy hits have taken by the rules but not yet reported, hit by
# hit (_owe_attacks()) - what the HP bar is still to lose: shown_player_
# hp(). And whether the hit reporting now is one of an attack's several
# (is_multi_hit_report()).
var _hp_owed: int = 0
# The Toll an attack's hits have taken (Thick Skin) but not yet reported:
# the readout drops hit by hit, as the HP bar does (_report_enemy_hit()).
var _toll_owed: int = 0
# Packmates a SIGNAL woke this enemy turn (_answer_signal()) - their
# answer was their turn. Cleared as each enemy turn begins.
var _signal_woken: Dictionary = {}
var _multi_hit_report: bool = false
# Members of a shared move (_run_simultaneous_turn()) still reporting
# their hits.
var _reports_running: int = 0

func setup(hand_container: HandContainer, enemy_list: Array[FieldEnemy], wanderer: Wanderer) -> void:
	_hand_container = hand_container
	enemies = enemy_list
	_roster = enemy_list.duplicate()
	_wanderer = wanderer
	# Every Brace or Garnish leaving its intent, into the run log.
	if not intent_mark_settled.is_connected(_log_intent_mark):
		intent_mark_settled.connect(_log_intent_mark)

	player = Combatant.new(RunState.player_max_hp)
	player.hp = RunState.player_hp
	# Toll carries between fights, up to a cap - see RunState.toll.
	player.run_toll_owner = RunState
	player.has_toll = RunState.character.has_toll
	player.has_grace = RunState.character.has_grace
	has_devour = RunState.character.has_devour
	has_sheathe = RunState.character.has_sheathe
	player.grace_cap_mode = RunState.character.grace_cap_mode
	player.grace_window_turns = RunState.character.grace_window_turns
	player.grace_open_fraction = RunState.character.grace_open_fraction
	player.critical_hp_fraction = RunState.character.critical_hp_fraction
	player.parry_block_per_level = RunState.character.parry_block_per_level
	player.recover_draw = RunState.character.recover_draw
	player.lunge_damage_per_level = RunState.character.lunge_damage_per_level
	player.energy = player.max_energy
	# Nothing lost in this fight yet (RunState.hp_lost_this_combat).
	RunState.begin_combat()
	# The keepsake's and the worn piece's part in the fight opening (see
	# TrinketData), both slots summed: their statuses and Block on the
	# Wanderer now, the free card, Critical-entry Block, the first hit's
	# scale and the damage back armed, their extra cards in the opening
	# draw below. The first turn opens without _start_player_turn()'s
	# Block reset, so the opening Block stands until the first enemy turn
	# is over.
	# The weapon's one fight hook (Gaff Hook): its self-loss bonus, for the
	# basic attack it names.
	if RunState.weapon != null and RunState.weapon.self_loss_attack_bonus > 0:
		player.self_loss_attack_bonus = RunState.weapon.self_loss_attack_bonus
		player.self_loss_attack_tag = RunState.weapon.basic_attack_tag
	var held: Array[TrinketData] = RunState.held_pieces()
	var opening_block: int = 0
	var opening_bonus: int = 0
	for piece in held:
		piece.apply_combat_start(player.statuses)
		opening_block += maxi(piece.combat_start_block, 0)
		opening_bonus += maxi(piece.opening_draw_bonus, 0)
		player.first_card_free = player.first_card_free or piece.first_card_free
		player.critical_entry_block += maxi(piece.critical_entry_block, 0)
		# The largest turn discount held, with its own count.
		if piece.card_count_discount > player.card_count_discount:
			player.card_count_discount = piece.card_count_discount
			player.discount_on_card_count = maxi(piece.discount_on_card_count, 0)
		_end_turn_keep += maxi(piece.end_turn_keep, 0)
		_energy_carry += maxi(piece.energy_carry, 0)
		player.first_hit_scale = minf(player.first_hit_scale, clampf(piece.first_hit_scale, 0.0, 1.0))
		# The largest big-hit cut held, with its own threshold.
		if piece.big_hit_reduction > player.big_hit_reduction:
			player.big_hit_reduction = piece.big_hit_reduction
			player.big_hit_threshold = maxi(piece.big_hit_threshold, 0)
		player.hit_back_damage += maxi(piece.hit_back_damage, 0)
	player.block += opening_block
	opening_block_gained = opening_block
	if not held.is_empty():
		# Opening already Critical is not entering it.
		player.critical_entry_armed = not player.is_critical()

	_combatants.clear()
	var enemy_names: Array[String] = []
	var enemy_ids: Array[String] = []
	# The run log's encounter fields, one per member (RunLogger.fight_start()).
	var members: Array[Dictionary] = []
	for enemy in enemies:
		var data: EnemyData = enemy.enemy_data
		var combatant := Combatant.new(data.max_hp if data != null else 1)
		combatant.enemy_data = data
		if data != null:
			EnemyTurn.pick_initial_intent(combatant, data)
			combatant.dormant = data.starts_dormant
			# Its passives (the Blackback's Fed), before the pack check
			# below can turn one.
			for status_data: StatusData in data.starting_statuses:
				if status_data != null:
					Status.apply_to(combatant.statuses, status_data)
			enemy_names.append(data.enemy_name)
			# Two enemies can share a name (the Dragonflies) - the file
			# tells them apart in the log.
			enemy_ids.append(data.resource_path.get_file().get_basename())
			members.append(encounter_member(enemy))
		_combatants[enemy] = combatant
	# A pack met with one member left (the rest killed in an earlier fight
	# it was escaped from) opens without its pack move.
	_mark_lone_pack_members()

	# One fight is one slot's option (a cluster never spans slots): the
	# first member's.
	var slot_id: String = String(enemies[0].slot_id) if not enemies.is_empty() else ""
	var option_id: String = String(enemies[0].option_id) if not enemies.is_empty() else ""
	RunLogger.fight_start(RunLogger.encounter_key(enemy_names), enemy_ids, RunState.run_snapshot(), members, encounter_role(members), slot_id, option_id)
	for enemy in enemies:
		var logged: Combatant = _combatants[enemy]
		RunLogger.enemy_hp_seen(logged.get_instance_id(), logged.hp)
	if not held.is_empty():
		RunLogger.block_gained(opening_block)
	RunLogger.turn_started(player.energy)
	# The run log's mechanic lines, off the signals the view already hears.
	if not enemy_pain_turn.is_connected(_log_pain_turn):
		enemy_pain_turn.connect(_log_pain_turn)
		enemy_status_gained.connect(_log_status_gained)
	for enemy in enemies:
		_log_threshold_queued(enemy)

	var fight_cards: Array[CardData] = []
	for card in RunState.deck:
		fight_cards.append(fight_card(card))
	deck = Deck.new(fight_cards)
	deck.drawn.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.drawn.connect(func(_card: CardData) -> void: RunLogger.card_drawn())
	deck.discarded.connect(func(_card: CardData) -> void: hand_changed.emit())
	deck.keep_changed.connect(func() -> void: hand_changed.emit())
	# A fight-only copy (Twice Over's) gone unplayed at the turn's end.
	deck.vanished.connect(func(card: CardData) -> void:
		RunLogger.mechanic("copy_end", {"card": card.card_name, "outcome": "vanished"}))
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
	_devour_uses_this_turn = 0
	_sheathe_uses_this_turn = 0
	_emit_devour_changed()
	_hand_container.draw_cards(turn_draw_amount + opening_bonus)
	_apply_intent_exclusions(enemies)
	_emit_intent_previews()
	# Each body takes the pose of what it opens on - under way through the
	# camera's swing, so a rear is held by the time the frame settles.
	for enemy in enemies:
		_pose_for_intent(enemy)

# A card of the run's deck as this fight plays it: through the run's
# weapon (WeaponData.modify_basic_attack() - Greyshelf's Tail's Slash
# as a Lash of its own), anything else the run's own instance. The run's
# deck is never rewritten; a CONSUMED card is never a basic attack, so
# _apply_consumed_removals() still finds every one it needs by identity.
func fight_card(card: CardData) -> CardData:
	return RunState.as_carried(card)

# The queued action of one enemy as the display should show it - see
# EnemyTurn.preview_intent() - and the lethal warning across enemies: when
# no enemy is lethal on its own but everything queued for the coming enemy
# turn together would be (_lethal_together()), every intent that adds to
# it is "lethal" too, with "lethal_together". Empty for a dead/unknown
# enemy.
func get_intent_preview(enemy: FieldEnemy) -> Dictionary:
	var previews: Dictionary = _turn_previews()
	var preview: Dictionary = previews.get(enemy, {})
	if preview.is_empty() or bool(preview.get("lethal", false)):
		return preview
	if _lethal_together(previews).has(enemy):
		preview["lethal"] = true
		preview["lethal_together"] = true
	return preview

# Every enemy's preview for the coming enemy turn, in turn order, each
# read from where the ones before it leave the player (EnemyTurn.turn_
# state()): the worn piece's first hit and No Further's armed are spent
# by the first attack that spends them, not shown off every enemy's, and
# Unbroken cuts each attack until the player's next turn - so each
# readout, each Signal's answers and the warning across enemies carry
# the hits that will land.
func _turn_previews() -> Dictionary:
	var state: Dictionary = EnemyTurn.turn_state(player)
	var previews: Dictionary = {}
	for enemy in enemies:
		previews[enemy] = _intent_preview_alone(enemy, state)
	return previews

# The enemies whose queued actions together would be lethal for the coming
# enemy turn, when none is on its own: every damage-dealing action queued
# - each attack's hits as they will land (Brace and Garnish off, both of a
# two-action enemy's, the Erupt's), each Signal's answers - in turn order,
# run through his Block and HP from where they stand (EnemyTurn.
# simulate_hits()). Empty when the sum isn't lethal, or when one enemy is
# lethal alone (its own warning says it). Stunned, Delayed, cancelled or
# broken intents add nothing.
func _lethal_together(previews: Dictionary) -> Dictionary:
	var contributors: Dictionary = {}
	var amounts: Array[int] = []
	for enemy in enemies:
		var preview: Dictionary = previews.get(enemy, {})
		if preview.is_empty():
			continue
		if bool(preview.get("lethal", false)):
			return {}
		if bool(preview.get("denied", false)) or bool(preview.get("delayed", false)) or bool(preview.get("pain_turn", false)) or bool(preview.get("interrupted", false)):
			continue
		var adds: Array = []
		match int(preview.get("type", -1)):
			EnemyIntent.IntentType.ATTACK:
				adds = preview.get("hit_amounts", [])
			EnemyIntent.IntentType.SIGNAL:
				adds = preview.get("answers", [])
		var total: int = 0
		for amount: Variant in adds:
			amounts.append(int(amount))
			total += int(amount)
		if total > 0:
			contributors[enemy] = true
	if contributors.size() < 2 or not bool(EnemyTurn.simulate_hits(player, amounts)["lethal"]):
		return {}
	return contributors

# One enemy's preview (get_intent_preview() without the lethal warning
# across enemies), read from and spending `state` - the player as the
# enemies before it in the turn leave him (_turn_previews()).
func _intent_preview_alone(enemy: FieldEnemy, state: Dictionary) -> Dictionary:
	var combatant: Combatant = _combatants.get(enemy)
	var data: EnemyData = enemy.enemy_data if enemy != null else null
	if combatant == null or data == null or combatant.hp <= 0:
		return {}
	_drop_lost_marks(enemy, combatant, data)
	var preview: Dictionary = EnemyTurn.preview_intent(combatant, data, player, state)
	# A heal for packmates shows what it will actually heal - the same
	# call the turn makes, without applying it.
	if int(preview.get("type", -1)) == EnemyIntent.IntentType.HEAL_ALLY and not bool(preview.get("pain_turn", false)):
		preview["per_hit"] = _heal_packmates(enemy, int(preview["per_hit"]), false)
	# A Signal shows what its pack's answers will land in all ("per_hit"),
	# each answer's damage ("answers", member order), and whether they
	# alone would be lethal (EnemyTurn.simulate_hits()) - nothing, Stunned,
	# Delayed or cancelled.
	if int(preview.get("type", -1)) == EnemyIntent.IntentType.SIGNAL and not bool(preview.get("pain_turn", false)) and not bool(preview.get("denied", false)) and not bool(preview.get("delayed", false)):
		var lists: Array = signal_answer_lists(enemy, state)
		var answers: Array[int] = []
		for list: Array[int] in lists:
			answers.append_array(list)
		var total: int = 0
		for amount in answers:
			total += amount
		preview["answers"] = answers
		preview["answer_lists"] = lists
		preview["per_hit"] = total
		var landed: Dictionary = EnemyTurn.simulate_hits(player, answers)
		preview["damage_to_hp"] = int(landed["to_hp"])
		preview["lethal"] = bool(landed["lethal"])
	return preview

# What each living packmate of `enemy` would answer its SIGNAL with, in
# member order - one list of hits per answer (EnemyTurn.signal_answer_
# intent() - its first ATTACK, every hit of it), as each would land:
# replayed on `state` (EnemyTurn.replay_attack()), so they read the
# player's Unbroken, and read and spend No Further's armed and the worn
# piece's first hit, as the answers do, the mate's own marks (Braced,
# Garnished on its own intent) set by, as EnemyTurn.answer_signal() sets them by. Empty `state`
# = the player as he stands. Empty without a pack.
func signal_answer_lists(enemy: FieldEnemy, state: Dictionary = {}) -> Array:
	var lists: Array = []
	if enemy == null or enemy.group == &"":
		return lists
	if state.is_empty():
		state.merge(EnemyTurn.turn_state(player))
	for member in enemies:
		if member == enemy or member.group != enemy.group or member.enemy_data == null:
			continue
		var mate: Combatant = _combatants.get(member)
		if mate == null or mate.hp <= 0:
			continue
		var answer: EnemyIntent = EnemyTurn.signal_answer_intent(mate, member.enemy_data)
		if answer == null:
			continue
		var marked: Array[Status] = Status.marks(mate.statuses)
		var at: Array[int] = []
		for active in marked:
			at.append(mate.statuses.find(active))
			mate.statuses.erase(active)
		lists.append(EnemyTurn.replay_attack(mate, member.enemy_data, answer, player, state))
		for i in marked.size():
			mate.statuses.insert(mini(at[i], mate.statuses.size()), marked[i])
	return lists

# What no longer holds on `enemy`'s intent (EnemyTurn.mark_loss() - the
# intent replaced or cancelled since the card landed) leaves it, said
# (intent_mark_settled). Every change to an intent is shown through
# get_intent_preview(), which asks this first - so what the readout shows
# never carries a mark that won't hold.
func _drop_lost_marks(enemy: FieldEnemy, combatant: Combatant, data: EnemyData) -> void:
	for active in Status.marks(combatant.statuses):
		var reason: String = EnemyTurn.mark_loss(active, combatant, data)
		if reason.is_empty():
			continue
		combatant.statuses.erase(active)
		var entry: Dictionary = EnemyTurn.mark_entry(active)
		entry["outcome"] = "lost"
		entry["reason"] = reason
		intent_mark_settled.emit(enemy, entry)

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
	ctx.tagged_plays_before_this = player.tagged_plays_this_turn.duplicate()
	# The chain as it stands: what a Burst card in hand would read played now.
	ctx.chain_level_before_this = player.chain_level
	if ctx.enemies.size() == 1:
		ctx.target = ctx.enemies[0]
	return ctx

# The turn's plays by tag before `card`, which the commit has already
# counted: its own tags taken back off.
func _tagged_plays_before(card: CardData) -> Dictionary:
	var before: Dictionary = player.tagged_plays_this_turn.duplicate()
	for tag in card.tags:
		before[tag] = maxi(int(before.get(tag, 0)) - 1, 0)
	return before

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

# The fight's opening hold: no card, End Turn, target or Devour takes
# input until `release` is emitted (RegionField._on_enemy_contacted()
# passes the Wanderer's draw_strike_passed - his draw's ground strike), or
# `seconds` from now at the latest. Zero or less holds nothing.
func lock_entry_input(seconds: float, release: Signal = Signal()) -> void:
	if seconds <= 0.0:
		return
	_drop_entry_release()
	_entry_locked = true
	entry_lock_changed.emit(true)
	_emit_devour_changed()
	get_tree().create_timer(seconds, true).timeout.connect(unlock_entry_input)
	if not release.is_null():
		_entry_release = release
		release.connect(unlock_entry_input, CONNECT_ONE_SHOT)

# The opening hold ends - a no-op once it has.
func unlock_entry_input() -> void:
	_drop_entry_release()
	if not _entry_locked:
		return
	_entry_locked = false
	entry_lock_changed.emit(false)
	_emit_devour_changed()

func _drop_entry_release() -> void:
	if not _entry_release.is_null() and _entry_release.is_connected(unlock_entry_input):
		_entry_release.disconnect(unlock_entry_input)
	_entry_release = Signal()

func is_entry_locked() -> bool:
	return _entry_locked

# Whether `action` is refused by the opening hold - said once per refusal
# in a debug build, so a call dropped there (a probe acting too early) is
# never silent.
func _refused_by_entry_hold(action: String) -> bool:
	if not _entry_locked:
		return false
	if OS.is_debug_build():
		push_warning("BattleController: %s refused - the battle-entry hold is on (lock_entry_input(), until the Wanderer's draw strikes)." % action)
	return true

func request_play(card_view: CardView) -> void:
	if _refused_by_entry_hold("card play"):
		return
	if (_input_locked and not _play_in_flight) or _play_queued or _pending_card_view != null or _choice_open() or card_view.card_data == null:
		return
	# Devour first: the card clicked is the one it eats, playable or not.
	if _devour_picking:
		_devour_picking = false
		_devour_card(card_view, "pick")
		return
	# Sheathe first: the card clicked is the one it keeps, playable or not;
	# one it can't keep is passed over, the pick still open.
	if _sheathe_picking:
		if can_sheathe(card_view.card_data):
			_sheathe_picking = false
			_sheathe_card(card_view.card_data)
		return
	var card: CardData = card_view.card_data
	if not _is_playable(card):
		# A card that can't be played arms for Devour alone while Devour
		# is available; with Devour spent or its Energy short, nothing - as
		# before Devour existed.
		if is_devour_available():
			_arm_for_devour(card_view)
		return
	# A GRANT_KEEP card (Bide) asks which cards first, unless there is
	# nothing else in the hand to choose - then it just plays.
	var cap: int = _keep_cap(card)
	if cap > 0:
		_begin_choice(card_view, cap)
		return
	# A COPY_HAND_CARD card (Twice Over) asks which one card to copy,
	# from those it may (EffectResolver.copy_targets()), and plays the
	# moment it's picked.
	if EffectResolver.copies_hand_card(card):
		var eligible: Array[CardView] = []
		var targets: Array[CardData] = EffectResolver.copy_targets(card, deck.hand)
		for view: CardView in _hand_container.call("_card_views"):
			if view != card_view and targets.has(view.card_data):
				eligible.append(view)
		_begin_choice(card_view, 1, eligible)
		return
	# A DEVOUR_FROM_HAND card (Take In) asks which one card to eat, from
	# every other in the hand (EffectResolver.devour_targets()), and plays
	# the moment it's picked - Twice Over's way.
	if EffectResolver.devours_from_hand(card):
		var to_eat: Array[CardView] = []
		var edible: Array[CardData] = EffectResolver.devour_targets(card, deck.hand)
		for view: CardView in _hand_container.call("_card_views"):
			if view != card_view and edible.has(view.card_data):
				to_eat.append(view)
		_begin_choice(card_view, 1, to_eat, "DEVOUR")
		return
	_arm_or_play(card_view)

# Whether `card` can be played now: affordable, not blocked by the rules,
# and with something to land on.
func _is_playable(card: CardData) -> bool:
	if not player.can_pay(card):
		return false
	# A fixed Toll the player doesn't hold (Come Due), nothing to replay
	# (Second Swing) - the hand shows it
	# faded, and this is the rule behind the fade.
	if EffectResolver.card_blocked(card, player):
		return false
	# Every enemy buried - or, for Deny, every one already Delayed: an
	# enemy-target card has nothing to land on.
	if card.target_type == CardData.TargetType.ENEMY and not _has_valid_target(card):
		return false
	# Twice Over with nothing it may copy.
	if EffectResolver.copies_hand_card(card) and EffectResolver.copy_targets(card, deck.hand).is_empty():
		return false
	# Take In with nothing else in the hand to eat.
	if EffectResolver.devours_from_hand(card) and EffectResolver.devour_targets(card, deck.hand).is_empty():
		return false
	# Second Swing whose Attack's enemy is gone: another it can land on.
	if _replay_needs_target(card) and not _has_valid_target(card):
		return false
	return true

# Whether `card` replays the last Attack (Second Swing).
func _replays(card: CardData) -> bool:
	return _has_effect(card, CardEffect.EffectType.REPLAY_LAST_ATTACK)

# The card whose targeting rules a play of `card` follows: the Attack it
# replays for Second Swing - its taunt and its can-it-land, not the
# Skill's - `card` itself for any other.
func _targeting_card(card: CardData) -> CardData:
	if card != null and _replays(card) and player != null and player.last_attack != null:
		return player.last_attack
	return card

# Second Swing asks for a target only when its Attack was aimed at one
# enemy and that enemy can't be hit now; an all-enemies Attack, or one
# whose enemy still stands, replays where it went.
func _replay_needs_target(card: CardData) -> bool:
	if not _replays(card) or player == null or player.last_attack == null or player.last_attack_all:
		return false
	return not _last_attack_enemy_standing()

func _last_attack_enemy_standing() -> bool:
	var enemy: FieldEnemy = _last_attack_enemy
	if enemy == null or not is_instance_valid(enemy) or not enemies.has(enemy):
		return false
	return _can_target(player.last_attack, _combatants.get(enemy))

# The card goes on: an enemy-target card arms for its target (from
# wherever it is held), any other resolves now.
func _arm_or_play(card_view: CardView) -> void:
	var card: CardData = card_view.card_data
	if card.target_type == CardData.TargetType.ENEMY or _replay_needs_target(card):
		_pending_card_view = card_view
		card_view.lift_and_hold(card_view == _choosing_card_view)
		target_requested.emit(card)
		_emit_devour_changed()
	else:
		_resolve_play(card_view, null)

# An unplayable card armed with Devour its only target: held like any
# armed card and cancelled the same way, but its dimmed look kept (lift_
# and_hold() leaves the fade alone), and no enemy lit or clickable
# (_refresh_enemy_rects() gives none). No Bide choice, no Deny pick: it
# isn't going to be played.
func _arm_for_devour(card_view: CardView) -> void:
	_pending_card_view = card_view
	_pending_devour_only = true
	card_view.lift_and_hold()
	target_requested.emit(card_view.card_data)
	_emit_devour_changed()

func _has_effect(card: CardData, type: CardEffect.EffectType) -> bool:
	for effect in card.effects:
		if effect != null and effect.effect_type == type:
			return true
	return false

# Whether `card` may land on `combatant` (EffectResolver.can_target() -
# not buried, Deny not on the already Delayed, and a single-target Attack
# only on a taunting enemy while one stands).
func _can_target(card: CardData, combatant: Combatant) -> bool:
	return EffectResolver.can_target(_targeting_card(card), combatant, _hittable_enemy_combatants())

# Whether `card` marks an intent (StatusData.intent_mark - Brace, Garnish,
# Wrest): aimed at an enemy's queued intent, its readout or its body.
func _marks_intent(card: CardData) -> bool:
	return marking_status(card) != null

# The status `card` puts on an intent (EffectResolver.intent_mark_
# status()), or null.
func marking_status(card: CardData) -> StatusData:
	if card == null:
		return null
	for effect in card.effects:
		var mark: StatusData = EffectResolver.intent_mark_status(effect)
		if mark != null:
			return mark
	return null

# Why `card` can't mark `enemy`'s queued intent (EnemyTurn.mark_refusal()):
# NONE when it can, or for a card that marks none.
func mark_refusal_for(card: CardData, enemy: FieldEnemy) -> EnemyTurn.MarkRefusal:
	var status_data: StatusData = marking_status(card)
	var combatant: Combatant = _combatants.get(enemy)
	if status_data == null:
		return EnemyTurn.MarkRefusal.NONE
	return EnemyTurn.mark_refusal(combatant, enemy.enemy_data if enemy != null else null, status_data)

func _has_valid_target(card: CardData) -> bool:
	return EffectResolver.has_target(_targeting_card(card), _hittable_enemy_combatants())

# How many cards a GRANT_KEEP card may give Keep right now: its number,
# capped at the other cards in the hand. 0 for every other card.
func _keep_cap(card: CardData) -> int:
	var value: int = 0
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.GRANT_KEEP:
			value += effect.value
	if value <= 0:
		return 0
	return mini(value, maxi(deck.hand.size() - 1, 0))

# A hand choice, opened: the card arms the way a targeting card does (the
# hand stops hovering, End Turn greys), then the cards it may take wake up
# to be clicked, the rest faded (HandContainer.begin_choice()) - each click
# marks or unmarks one, up to `cap`; a click past the cap, or on a card it
# may not take, does nothing. Right-click or Esc cancel with nothing
# spent. Bide's (GRANT_KEEP) takes 0 to `cap` of any other card, confirmed
# by DONE (the overlay's, confirm_choice()) or Enter/Space - clicking the
# armed card again does nothing.
# Twice Over's (`eligible` given) takes exactly one of `eligible` - the
# rest faded and unpickable - and the play goes on the moment it's picked,
# with no DONE; Take In's the same, its prompt's `verb` DEVOUR.
func _begin_choice(card_view: CardView, cap: int, eligible: Array[CardView] = [], verb: String = "COPY") -> void:
	_choosing_card_view = card_view
	_choice_marked.clear()
	_choice_cap = cap
	_choice_eligible = eligible
	card_view.lift_and_hold(true)
	_hand_container.begin_choice(card_view, eligible)
	if eligible.is_empty():
		hand_choice_started.emit("", cap, "KEEP", true)
	else:
		hand_choice_started.emit("", cap, verb, false)
	hand_choice_changed.emit(0, cap)
	_emit_devour_changed()

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
	_hand_container.begin_choice(null)
	hand_choice_started.emit("END TURN", cap, "KEEP", false)
	hand_choice_changed.emit(0, cap)
	_emit_devour_changed()
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
	# Twice Over's goes on at its pick.
	if not _choice_eligible.is_empty() and _choosing_card_view != null and _choice_marked.size() == _choice_cap:
		confirm_choice()

func confirm_choice() -> void:
	if _keep_choice_open:
		var kept: Array[CardData] = []
		for view in _choice_marked:
			kept.append(view.card_data)
		if not kept.is_empty():
			var kept_names: Array[String] = []
			for kept_card in kept:
				kept_names.append(kept_card.card_name)
			RunLogger.mechanic("keepsake_keep", {"cards": kept_names, "kept": kept.size()})
		_close_choice()
		_finish_turn(kept)
		return
	if _choosing_card_view == null:
		return
	var card_view: CardView = _choosing_card_view
	var chosen: Array[CardView] = _choice_marked.duplicate()
	# Twice Over: exactly its one.
	if not _choice_eligible.is_empty() and chosen.size() != _choice_cap:
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

func _close_choice() -> void:
	_choosing_card_view = null
	_keep_choice_open = false
	_choice_marked.clear()
	_choice_cap = 0
	_choice_eligible = []
	_hand_container.end_choice()
	hand_choice_ended.emit()
	_emit_devour_changed()

# `mound`: for an enemy dug in under its mounds (DIG), which mound the card
# is played at - one still standing, or the play is refused. Ignored for
# any other.
func confirm_target(enemy: FieldEnemy, mound: int = -1) -> void:
	if _entry_locked or _pending_card_view == null or _pending_devour_only:
		return
	var combatant: Combatant = _combatants.get(enemy)
	if not _can_target(_pending_card_view.card_data, combatant):
		return
	if combatant != null and combatant.dug_in and not combatant.mounds.has(mound):
		return
	var card_view := _pending_card_view
	_pending_card_view = null
	_clear_hover()
	_set_cursor_enemy(null)
	_enemy_rects.clear()
	_mound_rects.clear()
	_resolve_play(card_view, enemy, [], mound)

func cancel_target() -> void:
	if _pending_card_view == null:
		return
	_pending_card_view.release()
	_pending_card_view = null
	_pending_devour_only = false
	_clear_hover()
	_set_cursor_enemy(null)
	_enemy_rects.clear()
	target_cancelled.emit()
	_emit_devour_changed()

# End Turn: with a keepsake that keeps cards and a card in hand, the keep
# choice first (_begin_keep_choice()) - and End Turn again confirms it.
func end_turn() -> void:
	if _refused_by_entry_hold("End Turn"):
		return
	if _input_locked or _play_queued:
		return
	if _keep_choice_open:
		confirm_choice()
		return
	cancel_choice()
	# Deny's tie choice steps back to its target rather than closing: End
	# Turn lets it go altogether.
	cancel_target()
	cancel_devour_pick()
	cancel_sheathe_pick()
	if _begin_keep_choice():
		return
	await _finish_turn([])

# The turn ends: the hand discarded but for `keep` (the end-of-turn keep's
# cards, which stay for the next turn's draw to land on top of), Grace
# closed, stance and turn statuses aged, the enemy turn, the next turn.
# A turn owed (Owed Time - Status.take_extra_turn()) skips the enemy turn:
# their intents stand as shown, and the next player turn starts in full.
func _finish_turn(keep: Array[CardData]) -> void:
	RunLogger.turn_ended(player.energy)
	# What the next turn's refill gets of the Energy left unspent.
	_energy_carried = mini(maxi(player.energy, 0), _energy_carry)
	_input_locked = true
	turn_phase_changed.emit(false)
	_emit_devour_changed()
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
	# The chain is the turn's: gone before the enemies act.
	Skillchain.reset(player)
	status_changed.emit()
	if discard_fade > 0.0:
		await get_tree().create_timer(discard_fade).timeout
	if Status.take_extra_turn(player.statuses):
		# "Last turn" is the player's own just ended, as the enemy turn
		# would have left it (_run_enemy_turn()).
		player.took_damage_last_turn = player.took_damage_this_turn
		player.took_damage_this_turn = false
		RunLogger.mechanic("extra_turn", {"turn": _player_turn + 1})
		status_changed.emit()
	else:
		await _run_enemy_turn()
	_input_locked = false
	if not _check_battle_end():
		_start_player_turn()
		turn_phase_changed.emit(true)
		_emit_devour_changed()

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
# by the caller path this always runs on) keeps anything but one next card
# from being armed while this is in flight.
# - The cancel window: a play confirmed while another is in flight, or
#   while the Wanderer's swing is short of its cancel point (Wanderer.
#   holds_next_play() - the glb's Slash, slash_cancel_time), waits for
#   both before its commit - so its swing, and its impact timer, start
#   from there and stay in sync. If the wait leaves it unplayable (the
#   fight over, the card or its target gone, too dear) it goes back to
#   the hand.
func _resolve_play(card_view: CardView, target_enemy: FieldEnemy, chosen_views: Array[CardView] = [], target_mound: int = -1) -> void:
	if _play_in_flight or _swing_holds_next_play():
		_play_queued = true
		_emit_devour_changed()
		while _play_in_flight or _swing_holds_next_play():
			await get_tree().process_frame
		_play_queued = false
		if not _still_playable(card_view, target_enemy):
			if is_instance_valid(card_view):
				card_view.release()
			_emit_devour_changed()
			return
	_play_in_flight = true
	var card: CardData = card_view.card_data
	# Read before anything is spent: what Collateral's HP comes to depends
	# on the Energy held and any cost reduction (Leverage) still there.
	var collateral: Status = Status.missing_energy_status(player.statuses)
	var replaced_hp: int = player.replaced_cost_hp(card)
	var energy_paid: int = player.energy_cost(card)
	# The free card (House Key) about to be spent, and what the card would
	# have cost without it - for the run log's line below.
	var free_card_saved: int = -1
	if player.first_card_free and player.takes_next_card_discount(card):
		player.first_card_free = false
		free_card_saved = player.energy_cost(card) - energy_paid
		player.first_card_free = true
	play_hp_cost = replaced_hp
	player.energy -= energy_paid
	# What this card's cost left: Patient Cut's bonus reads it at impact,
	# whatever a later play has spent since.
	var unspent_energy: int = maxi(player.energy, 0)
	# The play is committed: a free card (House Key) is spent here, before
	# card_played re-reads the hand's faces - never on a hover, a face or
	# a cancelled target. So is a cost replacement's charge; its HP is paid
	# as the card resolves, before its effects (EffectContext.replaced_
	# cost_hp). And a waiting cost reduction, unless this card adds to it.
	# A 0-cost card spends neither discount: they wait for the next card
	# that costs something (Combatant.takes_next_card_discount() - a base
	# of 0, printed or while Critical).
	if player.takes_next_card_discount(card):
		player.first_card_free = false
		Status.spend_cost_reduction(player.statuses, card)
	_input_locked = true
	_emit_devour_changed()
	# Counted at commit, before anyone hears of the play - so a face that
	# re-reads itself on card_played sees this card as played. The card's
	# own context carries the count from before it (below).
	cards_played_this_turn += 1
	player.plays_this_turn = cards_played_this_turn
	player.count_play(card)
	# The chain steps at commit too: a Burst card reads the level from
	# before it, and the link's skillchain fires after the card's effects.
	var chain_before: int = player.chain_level
	var skillchain: StringName = Skillchain.step(player, card)
	var skillchain_level: int = player.chain_level
	if card.battle_copy:
		RunLogger.mechanic("copy_end", {"card": card.card_name, "outcome": "played"})
	# The last Attack, for Second Swing - a real play only, never a replay.
	if card.card_type == CardData.CardType.ATTACK:
		var all_enemies: bool = card.target_type != CardData.TargetType.ENEMY
		player.record_attack(card, null if all_enemies else _card_target(target_enemy, target_mound), all_enemies)
		_last_attack_enemy = null if all_enemies else target_enemy
		_last_attack_mound = -1 if all_enemies else target_mound

	var target_name: String = target_enemy.enemy_data.enemy_name if target_enemy != null and target_enemy.enemy_data != null else ""
	RunLogger.card_started(card.card_name, energy_paid, target_name)
	if free_card_saved >= 0:
		RunLogger.mechanic("keepsake_free_card", {"card": card.card_name, "saved": free_card_saved})
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

	var ctx: EffectContext = _card_context(target_enemy, target_mound)
	ctx.cards_played_before_this = cards_played_this_turn - 1
	ctx.tagged_plays_before_this = _tagged_plays_before(card)
	ctx.chain_level_before_this = chain_before
	ctx.unspent_energy = unspent_energy
	ctx.skillchain = skillchain
	ctx.skillchain_level = skillchain_level
	ctx.replaced_cost_hp = replaced_hp
	if replaced_hp > 0 and collateral != null and collateral.data != null:
		ctx.replaced_cost_source = "status:" + collateral.data.id
	ctx.on_replay = func() -> void:
		_replay_pending = true
	# The hand choice's cards: Bide's to gain Keep where they are,
	# Twice Over's one to copy.
	for view in chosen_views:
		if is_instance_valid(view) and view.card_data != null:
			ctx.keep_choice.append(view.card_data)
	if not ctx.keep_choice.is_empty():
		ctx.copy_choice = ctx.keep_choice[0]
		# Take In's one pick, to eat.
		ctx.devour_choice = ctx.keep_choice[0]
	ctx.on_devour = _on_keyword_devoured

	var hp_before_effects: int = player.hp
	# A hit that will land several times (Lash) shows its first as one of
	# several: the multi-hit stop (is_multi_hit_report()).
	var multi_hit: bool = _card_hit_count(card, ctx) > 1
	_multi_hit_report = multi_hit
	_deferring_pack_check = true
	_effect_resolver.resolve_card(card, ctx)
	_deferring_pack_check = false
	_multi_hit_report = false
	_after_card_effects()
	_draw_for_card_count()
	_draw_for_skill_after_attack(card)
	if not _extra_hit_reports.is_empty():
		await _land_extra_hits()
	if _replay_pending:
		await _replay_attack(target_enemy)
	deck.end_play()
	# A CONSUMED card leaves the run's deck when this fight ends: its play
	# is a choice the run log keeps on its own line, whatever the card.
	if card.removal_scope == CardData.RemovalScope.CONSUMED:
		RunLogger.event("consumed_play", {"card": card.card_name, "hp_before": hp_before_effects, "hp_after": player.hp})
	var attacked: Array[FieldEnemy] = _count_attack_card(card, ctx)
	RunLogger.card_finished()
	play_resolved.emit(card)
	# Then whoever it was played against strikes back (Coiled), before the
	# previews and the battle-end check read where the play left things.
	await _counter_strikes(attacked)
	await _after_play()

# A card's effect context for the fight as it stands, aimed at
# `target_enemy` (at `target_mound` when it's dug in), its reports wired to
# the view - each now, or held for a further hit's beat. The caller sets
# what is the play's own (the turn's counts, a cost replacement).
func _card_context(target_enemy: FieldEnemy, target_mound: int) -> EffectContext:
	var ctx := EffectContext.new()
	ctx.player = player
	# A dug-in enemy is hit through its mounds: the card at a mound lands on
	# that mound (EffectContext.landing_for() - nothing once it is gone),
	# a card at every enemy on every mound standing.
	ctx.target = _card_target(target_enemy, target_mound)
	ctx.enemies = _card_enemy_combatants()
	_wire_mounds(ctx)
	ctx.deck = deck
	ctx.on_grace_reclaimed = func(amount: int) -> void:
		_report_or_hold(_on_grace_reclaimed.bind(amount))
	ctx.on_heal = func(amount: int) -> void:
		_report_or_hold(_on_card_heal.bind(amount))
	_card_damaged.clear()
	ctx.on_damage = func(target_combatant: Combatant, amount: int, kind: String) -> void:
		# A mound is no enemy (draw_on_multi_hit counts enemies).
		if target_combatant != player and target_combatant.mound_owner == null and amount > 0:
			_card_damaged[target_combatant] = true
		_report_or_hold(_report_damage.bind("player", target_combatant, amount, kind))
	ctx.on_block = func(target_combatant: Combatant, blocked: int, damage_to_hp: int) -> void:
		_report_or_hold(_report_block.bind(target_combatant, blocked, damage_to_hp))
	ctx.on_block_gained = func(amount: int) -> void:
		_report_or_hold(combat_text.emit.bind("player", amount, "block"))
	ctx.on_extra_hit = func() -> void:
		_extra_hit_reports.append([])
	_card_damaged.clear()
	return ctx

# What follows any card's effects, a replay's too: the keepsake's Critical-
# entry Block, the packs a kill left alone, and the once-a-turn draw for a
# card that took HP from two enemies (Leg Band).
func _after_card_effects() -> void:
	_report_entry_block()
	if _pack_check_due:
		_pack_check_due = false
		_mark_lone_pack_members()
	_draw_for_multi_hit()

# The last Attack played again (Second Swing), once the card replaying it
# has resolved: at `chosen` when the play asked for a target (its enemy
# gone), else where it was played - every enemy for an all-enemies one.
# Its clip and lunge (card_replayed), swing and impact at a play's own
# timing, then its effects in full as if played (EffectContext.is_replay -
# no Energy, no pile, no played-card or tag count, no Bent Nail), its hits
# shown at their beats, what it struck counting it (Goaded, Roused) and
# striking back (Coiled). Nothing left to hit: nothing happens.
func _replay_attack(chosen: FieldEnemy) -> void:
	_replay_pending = false
	var card: CardData = player.last_attack
	if card == null:
		return
	var target_enemy: FieldEnemy = null
	var mound: int = -1
	if not player.last_attack_all:
		target_enemy = chosen if chosen != null else _last_attack_enemy
		if target_enemy == _last_attack_enemy:
			mound = _last_attack_mound
		if target_enemy == null or not is_instance_valid(target_enemy) or not enemies.has(target_enemy) or not _can_target(card, _combatants.get(target_enemy)):
			return
	card_replayed.emit(card, target_enemy)
	if card.battle_animation != &"":
		var impact_at: float = _impact_delay_for(card)
		var swing_at: float = impact_at - clampf(swing_lead_seconds, 0.0, impact_at)
		if swing_at > 0.0:
			await get_tree().create_timer(swing_at).timeout
		card_swing.emit(card)
		if impact_at - swing_at > 0.0:
			await get_tree().create_timer(impact_at - swing_at).timeout
	card_impact.emit(card)
	RunLogger.mechanic("replay", {"attack": card.card_name, "target": _log_id(target_enemy) if target_enemy != null else ""})
	# Its own Toll, HP and heals are the replay's in the run log, not the
	# card that replayed it.
	RunLogger.push_source("replay:" + card.card_name)
	var ctx: EffectContext = _card_context(target_enemy, mound)
	ctx.is_replay = true
	# Not a play: every card this turn was played before it, and it adds no
	# count of its own.
	ctx.cards_played_before_this = cards_played_this_turn
	ctx.tagged_plays_before_this = player.tagged_plays_this_turn.duplicate()
	# No cost of its own: the Energy held as it replays.
	ctx.unspent_energy = maxi(player.energy, 0)
	_multi_hit_report = _card_hit_count(card, ctx) > 1
	_deferring_pack_check = true
	_effect_resolver.resolve_card(card, ctx)
	_deferring_pack_check = false
	_multi_hit_report = false
	RunLogger.pop_source()
	_after_card_effects()
	if not _extra_hit_reports.is_empty():
		await _land_extra_hits()
	var attacked: Array[FieldEnemy] = _count_attack_card(card, ctx)
	await _counter_strikes(attacked)

# The play's last beats: the readouts catch up, the input reopens and the
# battle's end is checked.
func _after_play() -> void:
	# Taken, deepened or replaced by the card just played - and the card
	# faces need to know either way, since a stance changes what the hand
	# says it will do.
	stance_changed.emit(player.stance)

	toll_changed.emit(player.toll)
	status_changed.emit()
	# A card may have closed some Grace (Not So).
	grace_changed.emit(player.grace)
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

	# A kill: input waits for the blow to show in full and the deaths to
	# begin - not for them to end; a non-final death plays on while the
	# player acts.
	if has_held_deaths():
		await deaths_released
	_play_in_flight = false
	_input_locked = false
	_emit_devour_changed()
	_check_battle_end()

# A report from the resolving card: now, or - once a further hit of it is
# landing (EffectContext.on_extra_hit - Lash) - held for that hit's beat.
func _report_or_hold(report: Callable) -> void:
	if not _extra_hit_reports.is_empty():
		var current: Array = _extra_hit_reports[_extra_hit_reports.size() - 1]
		current.append(report)
	else:
		report.call()

# How many times `card`'s first damage effect lands as it resolves in
# `ctx` (DamageEffect.hit_count()) - 1 for a card with none.
func _card_hit_count(card: CardData, ctx: EffectContext) -> int:
	for effect in card.effects:
		if effect != null and effect.effect_type == CardEffect.EffectType.DAMAGE:
			return DamageEffect.hit_count(effect, ctx)
	return 1

# A repeating hit's further hits (Lash), card_hit_interval apart after
# the card's impact - each one's held reports at its own beat, as one of
# several (the multi-hit stop). Rules-wise they're long done; only what
# is shown waits.
func _land_extra_hits() -> void:
	var hits: Array[Array] = _extra_hit_reports
	_extra_hit_reports = []
	for reports in hits:
		if card_hit_interval > 0.0:
			await get_tree().create_timer(card_hit_interval).timeout
		_multi_hit_report = true
		for report: Callable in reports:
			report.call()
		_multi_hit_report = false

# An Attack card has been played: each enemy it was played against - its
# target, and every enemy it could hit when one of its effects hits all
# of them - counts it once (EnemyTurn.take_attack_card(), the Dunecur's
# Roused). Skills, Powers and Stances never count. Returns the living
# enemies it counted against, in the fight's order - those a strike back
# answers from (_counter_strikes()).
func _count_attack_card(card: CardData, ctx: EffectContext) -> Array[FieldEnemy]:
	var counted: Array[FieldEnemy] = []
	if card.card_type != CardData.CardType.ATTACK:
		return counted
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
			if combatant.hp > 0:
				counted.append(enemy)
	return counted

# The card just played was played against each of `against`: one holding
# a strike back (Coiled - EnemyTurn.counter_strike()) answers it, one at a
# time, in the fight's order - counter_strike_delay after the card, its
# lunge, then the hit reported as any enemy attack's is (_report_enemy_
# attack(): the number, Block, Grace, the lethal guard's heal, the run
# log). Stops once the player is down: the play's _check_battle_end()
# takes it from there.
func _counter_strikes(against: Array[FieldEnemy]) -> void:
	for enemy in against:
		if player.hp <= 0:
			return
		if not enemies.has(enemy) or not is_instance_valid(enemy):
			continue
		var combatant: Combatant = _combatants.get(enemy)
		var result: Dictionary = EnemyTurn.counter_strike(combatant, enemy.enemy_data, player)
		if result.is_empty():
			continue
		_owe_attacks([result] as Array[Dictionary])
		if counter_strike_delay > 0.0:
			await get_tree().create_timer(counter_strike_delay).timeout
		var snap_delay: float = enemy.play_attack_snap(_wanderer)
		if snap_delay > 0.0:
			await get_tree().create_timer(snap_delay).timeout
		await _report_enemy_attack(enemy, result)
		_hp_owed = 0
		# What the strike spent leaves the readouts (Garnished and
		# Unbroken wait for the enemy's own turn - ignores_strike_backs).
		status_changed.emit()

# --- The dig (EnemyIntent.IntentType.DIG) ---

# `enemy`'s standing mounds' Combatants by mound number - null for one
# broken or gone; empty when it isn't dug in. For their plates
# (BattleOverlay).
func mound_guards_of(enemy: FieldEnemy) -> Array[Combatant]:
	var standing: Array[Combatant] = []
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or not combatant.dug_in:
		return standing
	for guard in combatant.mound_guards:
		standing.append(guard if EnemyTurn.mound_standing(guard) else null)
	return standing

# What a card played at `enemy` (at `mound` of its row, when it is dug in)
# lands on: that mound's Combatant while the enemy is under, else the
# enemy's own. A mound gone since the card was armed (a play queued behind
# another) is still its target - and takes nothing (EffectContext.
# landing_for()).
func _card_target(enemy: FieldEnemy, mound: int) -> Combatant:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant != null and combatant.dug_in and mound >= 0 and mound < combatant.mound_guards.size():
		return combatant.mound_guards[mound]
	return combatant

# The enemies a card can hit: the hittable ones, each dug-in enemy's
# standing mounds in its place - a card at every enemy hits every mound,
# never the body under them.
func _card_enemy_combatants() -> Array[Combatant]:
	var hittable: Array[Combatant] = []
	for combatant in _hittable_enemy_combatants():
		if combatant.dug_in:
			for guard in combatant.mound_guards:
				if EnemyTurn.mound_standing(guard):
					hittable.append(guard)
		else:
			hittable.append(combatant)
	return hittable

# A card's context told about the mounds: whose rules each dug-in enemy's
# row follows, and what to do when one breaks (_on_mound_broken(), held
# with the card's other reports for a further hit's beat).
func _wire_mounds(ctx: EffectContext) -> void:
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null and combatant.dug_in:
			ctx.mound_data[combatant] = enemy.enemy_data
	ctx.on_mound_broken = func(owner: Combatant, mound: int, own: bool) -> void:
		_report_or_hold(_on_mound_broken.bind(_field_enemy_for(owner), mound, own))

# A mound broken (EnemyTurn.break_mound()): a wrong one falls flat and
# gone; its own brings the enemy up through it, Exposed - the overkill's
# damage_dealt follows straight after, onto the body coming up.
func _on_mound_broken(enemy: FieldEnemy, mound: int, own: bool) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var combatant: Combatant = _combatants.get(enemy)
	mound_broken.emit(enemy, mound, own)
	if own:
		enemy.surface_at_mound(mound)
		RunLogger.mechanic("dig_found", {"enemy": _log_id(enemy), "by": "mound", "left": combatant.mound_guards.size() if combatant != null else 0})
		status_changed.emit()
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
	else:
		enemy.collapse_mound(mound)
		RunLogger.mechanic("dig_wrong_mound", {"enemy": _log_id(enemy), "left": combatant.mounds.size() if combatant != null else 0})

# The Wanderer's swing is short of its cancel point (_resolve_play()).
func _swing_holds_next_play() -> bool:
	return _wanderer != null and _wanderer.holds_next_play()

# Whether a play that waited in the cancel window can still go: the fight
# on, the card still in the hand and playable, its target (and Deny's
# pick) still there.
func _still_playable(card_view: CardView, target_enemy: FieldEnemy) -> bool:
	if not is_instance_valid(card_view) or card_view.card_data == null or not deck.hand.has(card_view.card_data):
		return false
	if player.hp <= 0 or _win_waiting or _living_enemy_combatants().is_empty():
		return false
	var card: CardData = card_view.card_data
	if not _is_playable(card):
		return false
	if target_enemy != null and (not is_instance_valid(target_enemy) or not enemies.has(target_enemy) or not _can_target(card, _combatants.get(target_enemy))):
		return false
	return true

# CardData.impact_time's own clamp: a clip shorter than the authored
# impact_time fires at the clip's own end instead of after it's already
# finished. A clip that knows its own contact frame (Wanderer.get_clip_
# contact_time() - the glb's Slash) lands there instead, whatever the card
# says. _wanderer is only used to look these up - if it's ever unset, the
# authored impact_time is used unclamped rather than dropped to 0.
func _impact_delay_for(card: CardData) -> float:
	if card.battle_animation == &"":
		return 0.0
	var delay: float = card.impact_time
	if _wanderer != null:
		var contact: float = _wanderer.get_clip_contact_time(card.battle_animation)
		if contact >= 0.0:
			return contact
		var clip_length: float = _wanderer.get_clip_length(card.battle_animation)
		if clip_length > 0.0:
			delay = minf(delay, clip_length)
	return delay

# One member of an encounter as the run log and the reward read it
# (RunLogger.fight_start()'s members, encounter_role()): its
# data's file name, its place on the floor, the three flags its role is
# made of, and the encounter slot and option it was spawned from. `enemy`
# must have its enemy_data.
static func encounter_member(enemy: FieldEnemy) -> Dictionary:
	var data: EnemyData = enemy.enemy_data
	return {
		"id": data.resource_path.get_file().get_basename(),
		"floor_index": enemy.floor_index,
		"required": enemy.required,
		"elite": data.is_elite,
		"region_end": enemy.card_reward == FloorEnemy.CardReward.TOP_TIER_FIRST,
		"slot_id": String(enemy.slot_id),
		"option_id": String(enemy.option_id),
	}

# The encounter's role - the strongest any member is (encounter_member()):
# region_end, elite, required, else basic. The rule the rewards are paid
# by (EncounterRewards) and the run log records (setup() hands it to
# RunLogger.fight_start()).
static func encounter_role(members: Array[Dictionary]) -> String:
	var role: String = "basic"
	for member in members:
		if bool(member.get("region_end", false)):
			return "region_end"
		if bool(member.get("elite", false)):
			role = "elite"
		elif bool(member.get("required", false)) and role == "basic":
			role = "required"
	return role

# --- Devour ---

# Whether Devour can be used now: a use left this turn, its Energy
# (devour_energy_cost) in hand, on the player's turn with nothing
# resolving, and no hand choice open - never for a class without it
# (has_devour). Everything that offers it keys on this - the button,
# arming an unplayable card for it, the pick, lighting up as a target.
func is_devour_available() -> bool:
	return has_devour and player != null and _devour_uses_this_turn < devour_uses_per_turn and is_devour_affordable() and not _entry_locked and not _input_locked and not _play_queued and not _choice_open()

# Whether the player has the Energy Devour costs.
func is_devour_affordable() -> bool:
	return player != null and player.energy >= maxi(devour_energy_cost, 0)

# Whether this turn's Devours are spent.
func is_devour_used() -> bool:
	return _devour_uses_this_turn >= devour_uses_per_turn

# Whether Devour is a target right now: available, with a card armed or
# a card to pick.
func is_devour_lit() -> bool:
	return is_devour_available() and (_pending_card_view != null or _devour_picking)

# Devour first: waiting for the hand card it will eat.
func is_devour_picking() -> bool:
	return _devour_picking

# The armed card is armed for Devour alone (it can't be played).
func is_armed_for_devour_only() -> bool:
	return _pending_card_view != null and _pending_devour_only

# What Devour would eat right now: the armed card, or null (none armed,
# or picking).
func get_devour_card() -> CardData:
	return _pending_card_view.card_data if _pending_card_view != null else null

# Devour first: every hand card - the dimmed ones too, looking as they
# do - is the next click's to eat (request_play()); no enemy targeting,
# End Turn greyed. Right-click, Esc or Devour again cancel.
func _begin_devour_pick() -> void:
	_devour_picking = true
	_emit_devour_changed()

func cancel_devour_pick() -> void:
	if not _devour_picking:
		return
	_devour_picking = false
	_emit_devour_changed()

func _emit_devour_changed() -> void:
	devour_changed.emit(is_devour_available(), is_devour_used())
	# Sheathe's availability turns on the same moments (a play, a hold, a
	# choice, the turn), so it is told at each of them too.
	_emit_sheathe_changed()

# Devour, clicked (DevourButton): the armed card is eaten - see
# _devour_card(). Nothing armed: the pick opens (_begin_devour_pick()),
# and a second click closes it. No use left: nothing.
func devour() -> void:
	# A class without Devour: nothing, not even the entry hold's refusal.
	if not has_devour:
		return
	if _devour_picking:
		cancel_devour_pick()
		return
	if _refused_by_entry_hold("Devour"):
		return
	if not is_devour_available():
		return
	if _pending_card_view == null:
		_begin_devour_pick()
		return
	var card_view: CardView = _pending_card_view
	_pending_card_view = null
	_pending_devour_only = false
	_clear_hover()
	_set_cursor_enemy(null)
	_enemy_rects.clear()
	_devour_card(card_view, "armed")

# The card leaves the hand without being played - none of ITS cost paid
# any way (the free card, a reduction or a replacement all wait; Devour's
# own devour_energy_cost is paid instead), no effect, no Toll, not
# counted as played, no card_played - to the Spent
# pile for this fight (Deck.spent_unplayed: back next fight even if it is
# CONSUMED). Like a play: out of deck.hand at once, the hand taking it
# out (bitten, then into the jaw), in the pile once that has ended.
# devour_heal_amount HP back, at the bite, capped at max, and one of this
# turn's uses spent. `route` is how it was chosen, for the run log:
# "armed" (the card first) or "pick" (Devour first).
func _devour_card(card_view: CardView, route: String) -> void:
	var card: CardData = card_view.card_data
	var playable: bool = _is_playable(card)
	_devour_uses_this_turn += 1
	# Devour's own price, out of the pips as a card's is.
	var energy_spent: int = mini(maxi(devour_energy_cost, 0), player.energy)
	player.energy -= energy_spent
	energy_changed.emit(player.energy)
	_input_locked = true
	deck.begin_play(card)
	deck.spent_unplayed.append(card)
	card_devoured.emit(card)
	# Bitten and slid into the jaw (HandContainer.devour_card()) - input
	# stays locked until it has gone.
	var exit_sec: float = _hand_container.devour_card(card)

	var hp_before: int = player.hp
	player.hp = mini(player.hp + maxi(devour_heal_amount, 0), player.max_hp)
	if player.hp > hp_before:
		_heal_run_hp(player.hp - hp_before, "devour")
		hp_changed.emit(player.hp, player.max_hp)
		combat_text.emit("player", player.hp - hp_before, "heal")
	RunLogger.event("devour", {"card": card.card_name, "playable": playable, "route": route, "energy": energy_spent, "hp_before": hp_before, "hp_after": player.hp})
	# HP moved: the lethal flags follow, and a Critical line it may have
	# left.
	status_changed.emit()
	_emit_intent_previews()
	_emit_devour_changed()

	if exit_sec > 0.0:
		await get_tree().create_timer(exit_sec).timeout
	deck.settle_play(true)
	deck.end_play()
	_input_locked = false
	_emit_devour_changed()

# EffectContext.on_devour: a card Devoured by the keyword (Take In) - the
# hand's bite, faded where it stands, and keyword_devoured with it (its
# sound). Nothing of the Devour button's: no card_devoured, no slide into
# its jaw, no use of it, no heal.
func _on_keyword_devoured(card: CardData) -> void:
	_hand_container.devour_card(card, false)
	keyword_devoured.emit(card)

# --- Sheathe ---

# Whether Sheathe can be used now: a use left this turn, its Energy
# (sheathe_energy_cost) in hand, on the player's turn with nothing
# resolving, and no hand choice open - never for a class without it
# (has_sheathe). The button and the pick both key on this.
func is_sheathe_available() -> bool:
	return has_sheathe and player != null and _sheathe_uses_this_turn < sheathe_uses_per_turn and is_sheathe_affordable() and not _entry_locked and not _input_locked and not _play_queued and not _choice_open()

# Whether the player has the Energy Sheathe costs.
func is_sheathe_affordable() -> bool:
	return player != null and player.energy >= maxi(sheathe_energy_cost, 0)

# Whether this turn's Sheathes are spent.
func is_sheathe_used() -> bool:
	return _sheathe_uses_this_turn >= sheathe_uses_per_turn

# Whether Sheathe is lit: available, with its pick open.
func is_sheathe_lit() -> bool:
	return is_sheathe_available() and _sheathe_picking

# Sheathe first: waiting for the hand card it will keep.
func is_sheathe_picking() -> bool:
	return _sheathe_picking

# Whether Sheathe may keep `card`: in the hand, without Keep already, and
# not a fight-only copy (Twice Over's), which is gone at the turn's end
# whatever keeps it.
func can_sheathe(card: CardData) -> bool:
	return card != null and deck != null and deck.hand.has(card) and not deck.has_keep(card) and not card.battle_copy

func cancel_sheathe_pick() -> void:
	if not _sheathe_picking:
		return
	_sheathe_picking = false
	_emit_sheathe_changed()

func _emit_sheathe_changed() -> void:
	sheathe_changed.emit(is_sheathe_available(), is_sheathe_used())

# Sheathe, clicked (SheatheButton): the pick opens - every hand card the
# next click's to keep (request_play()), the dimmed ones too; no enemy
# targeting, End Turn greyed - and a second click closes it, as do
# right-click and Esc. An armed card is let go first. No use left, or its
# Energy short: nothing. There is no arming a card first: Sheathe is
# always picked after.
func sheathe() -> void:
	# A class without Sheathe: nothing, not even the entry hold's refusal.
	if not has_sheathe:
		return
	if _sheathe_picking:
		cancel_sheathe_pick()
		return
	if _refused_by_entry_hold("Sheathe"):
		return
	if not is_sheathe_available():
		return
	cancel_target()
	_sheathe_picking = true
	_emit_sheathe_changed()

# The card keeps for this turn's end (Deck.grant_keep_once()) where it
# stands in the hand, with Keep's marker, and is in the hand for the next
# turn; sheathe_energy_cost paid and one of this turn's uses spent.
# Nothing of the card's own: not played, no cost, no effect.
func _sheathe_card(card: CardData) -> void:
	# Read before Sheathe's Energy goes: whether it could have been played.
	var playable: bool = _is_playable(card)
	if not deck.grant_keep_once(card):
		_emit_sheathe_changed()
		return
	_sheathe_uses_this_turn += 1
	var energy_spent: int = mini(maxi(sheathe_energy_cost, 0), player.energy)
	player.energy -= energy_spent
	energy_changed.emit(player.energy)
	card_sheathed.emit(card)
	RunLogger.event("sheathe", {"card": card.card_name, "playable": playable, "energy": energy_spent})
	_emit_devour_changed()

# Where a played card goes: the exhaust pile (true) for a SPENT or
# CONSUMED card, and for a power or a stance - it has done its work once
# played and stays, as a status or a stance stack, so it leaves rotation
# for the rest of the fight like SPENT and is back in the deck next fight.
# For a stance that is what makes a stack one physical copy: reshuffled,
# the same card would stack itself again. Every other card, the discard.
static func exhausts_on_play(card: CardData) -> bool:
	# A fight-only copy (Twice Over's) is Spent whatever it copies.
	if card.battle_copy or card.card_type == CardData.CardType.POWER or card.card_type == CardData.CardType.STANCE:
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
# card stacks (Goaded) it carried into resolution; a pain turn spent; the
# next intent, when it has a threshold; and, for an intent that holds a
# status while queued (the Underfoot's Covered / Exposed), the state the
# player's turn just faced and the HP damage it took in it.
func _take_turn_logged(enemy: FieldEnemy, combatant: Combatant, data: EnemyData) -> Dictionary:
	var id: String = _log_id(enemy)
	if not data.escalation_multipliers.is_empty():
		var stage: int = EnemyTurn.escalation_stage(combatant, data)
		RunLogger.escalation_stage(combatant.get_instance_id(), id, stage, data.escalation_multipliers[stage])
	var intent: EnemyIntent = EnemyTurn.current_intent(combatant, data)
	var threshold: int = EnemyTurn.interrupt_threshold(combatant, intent)
	var dealt: int = combatant.damage_taken_this_turn
	if intent != null and intent.status_while_queued != null:
		RunLogger.mechanic("queued_state", {"enemy": id, "intent": intent.intent_name, "state": intent.status_while_queued.id, "taken": dealt})
	var stacks: int = 0
	if threshold > 0 and intent.counts_attack_cards and data.attack_card_status != null:
		var held: Status = Status.find_in(combatant.statuses, data.attack_card_status)
		stacks = held.stack_count if held != null else 0
	var result: Dictionary = EnemyTurn.take_turn(combatant, data, player)
	if result["delayed"]:
		RunLogger.mechanic("delay", {"enemy": id, "intent": result["intent"]})
	for entry: Dictionary in result.get("marks", []):
		intent_mark_settled.emit(enemy, entry)
	if result["pain_turn"]:
		RunLogger.mechanic("pain_turn_spent", {"enemy": id})
	if threshold > 0:
		var outcome: String = "broken" if result["interrupted"] else ("landed" if result["attacked"] else ("pain_turn" if result["pain_turn"] else ("denied" if result["denied"] else ("delayed" if result["delayed"] else "none"))))
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
	var threshold: int = EnemyTurn.interrupt_threshold(combatant, intent)
	if threshold > 0:
		RunLogger.mechanic("threshold_queued", {"enemy": _log_id(enemy), "intent": intent.intent_name, "threshold": threshold})

func _log_intent_mark(enemy: FieldEnemy, entry: Dictionary) -> void:
	RunLogger.intent_mark(_log_id(enemy), entry)

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
	_enemy_phase = true
	_signal_woken.clear()
	_wake_unaided_dormant()
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
	# Those whose queued intent is already the coming turn's.
	var acted: Array[FieldEnemy] = []
	for enemy in enemies.duplicate():
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var data: EnemyData = enemy.enemy_data
		if data == null:
			continue
		# Woken by a SIGNAL this enemy turn: its answer was its turn.
		if _signal_woken.has(enemy):
			continue
		enemy_acting.emit(enemy)
		# What it is about to carry out, and how often - its body plays
		# the intent's move each time (_play_attack_move(), _play_defend_
		# moves()).
		var intent: EnemyIntent = EnemyTurn.current_intent(combatant, data)
		var times: int = EnemyTurn.repeats(combatant, intent)
		var result := _take_turn_logged(enemy, combatant, data)
		acted.append(enemy)
		# Its Block went as the turn began: the readout empties now, as it
		# starts acting, not once its move has played out.
		if result["block_cleared"] > 0:
			status_changed.emit()
		# Killed by its own countdown before it could act: reported, dropped,
		# and nothing more of this enemy's turn plays out.
		if _report_countdown(enemy, combatant, result):
			status_changed.emit()
			continue
		# Dormant: its statuses ticked, and nothing more of its turn.
		if bool(result.get("dormant", false)):
			continue
		if result["pain_turn_triggered"]:
			enemy_pain_turn.emit(enemy)
		if result["phase_triggered"]:
			enemy_status_gained.emit(enemy, data.phase_status)
		# Stunned or Delayed: no move to watch - the readout loses the
		# status, and the turn holds a beat so it reads.
		if result["denied"] or result["delayed"]:
			status_changed.emit()
			if denied_beat_sec > 0.0:
				await get_tree().create_timer(denied_beat_sec).timeout
		# Never found: it erupts - up through its own mound first, then the
		# hit.
		if result["erupted"]:
			var up_delay: float = enemy.surface_at_mound(combatant.true_mound)
			if up_delay > 0.0:
				await get_tree().create_timer(up_delay).timeout
		if result["attacked"]:
			# Each attack of the turn its own lunge and its own report, one
			# after another (EnemyTurn.repeats() - Bereft's two). A bite from
			# under the sand has no lunge: the body isn't there to see.
			var attacks: Array[Dictionary] = _attacks_of(result)
			_owe_attacks(attacks)
			for attack: Dictionary in attacks:
				var snap_delay: float = counter_strike_delay if enemy.is_dug_in() else _play_attack_move(enemy, intent)
				if snap_delay > 0.0:
					await get_tree().create_timer(snap_delay).timeout
				await _report_enemy_attack(enemy, attack)
				if player.hp <= 0:
					break
			_hp_owed = 0
			# Killed by what came back off its own attack (the worn
			# piece's hit_back_damage): reported and dropped with that
			# attack, and nothing more of its turn plays out.
			if combatant.hp <= 0:
				status_changed.emit()
				continue
		if result["dug"] and _wanderer != null and combatant.dig_intent != null:
			# The row across the battle camera's view, so it reads left to
			# right on screen.
			var camera := get_viewport().get_camera_3d()
			var across: Vector3 = camera.global_transform.basis.x if camera != null else Vector3.ZERO
			var dig_delay: float = enemy.begin_dig(combatant.dig_intent.mound_count, _wanderer.global_position, across)
			# The one clue, on its own mound alone.
			enemy.set_dig_tell(combatant.true_mound)
			if dig_delay > 0.0:
				await get_tree().create_timer(dig_delay).timeout
		if result["defended"]:
			for move in times:
				var move_delay: float = _play_defend_move(enemy, intent)
				if move_delay > 0.0:
					await get_tree().create_timer(move_delay).timeout
			_report_enemy_block(enemy, result)
		# A charge spent lets the rear down first, then any burrow carries on
		# from there. A broken one is already down - it dropped on the card
		# that broke it (_resolve_play()), so this waits on nothing and the
		# burrow follows at once.
		if result["attacked"] or result["interrupted"] or result["denied"] or result["delayed"]:
			var drop_delay: float = enemy.set_rearing(false)
			if drop_delay > 0.0:
				await get_tree().create_timer(drop_delay).timeout
		var burrow_delay: float = _play_burrow_for(enemy, result)
		if burrow_delay > 0.0:
			await get_tree().create_timer(burrow_delay).timeout
		if result["heal_allies"] > 0:
			_heal_packmates(enemy, result["heal_allies"], true)
		if bool(result.get("signal", false)):
			await _answer_signal(enemy)
			if player.hp <= 0:
				break
		status_changed.emit()
		# The pose of what comes next, landing on the beat the intent shows.
		var pose_delay: float = _pose_for_intent(enemy)
		if pose_delay > 0.0:
			await get_tree().create_timer(pose_delay).timeout
		# take_turn() has already advanced this enemy to its next intent -
		# show it the moment this action has landed.
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
		# What it queued may rule out a move another has queued already.
		_apply_intent_exclusions(acted)
		if player.hp <= 0:
			break

# A dormant enemy (Combatant.dormant) that nothing living in its pack
# could wake (_can_wake()) wakes as the enemy turn begins - and takes
# that turn.
func _wake_unaided_dormant() -> void:
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or not combatant.dormant:
			continue
		var waker: bool = false
		if enemy.group != &"":
			for other in enemies:
				if other != enemy and other.group == enemy.group and _can_wake(other):
					waker = true
					break
		if not waker:
			_wake(enemy, "alone")

# Whether `enemy` could still wake a dormant packmate: living, with a
# SIGNAL in its loop.
func _can_wake(enemy: FieldEnemy) -> bool:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0 or enemy.enemy_data == null:
		return false
	for intent: EnemyIntent in enemy.enemy_data.intents:
		if intent != null and intent.type == EnemyIntent.IntentType.SIGNAL:
			return true
	return false

# `caller`'s SIGNAL: every living packmate, in member order, wakes if it
# was dormant and answers with one attack out of turn (EnemyTurn.answer_
# signal()) - its own move and its own report, one after another. One
# woken here takes no turn of its own this enemy turn (_signal_woken).
func _answer_signal(caller: FieldEnemy) -> void:
	if caller.group == &"":
		return
	for member in enemies.duplicate():
		if member == caller or member.group != caller.group or member.enemy_data == null:
			continue
		var combatant: Combatant = _combatants.get(member)
		if combatant == null or combatant.hp <= 0:
			continue
		if combatant.dormant:
			_wake(member, "signal")
			_signal_woken[member] = true
		var attack: Dictionary = EnemyTurn.answer_signal(combatant, member.enemy_data, player)
		if not bool(attack["attacked"]):
			continue
		RunLogger.mechanic("signal_answer", {"enemy": _log_id(member), "caller": _log_id(caller), "to_hp": attack["damage_to_hp"]})
		enemy_acting.emit(member)
		var attacks: Array[Dictionary] = [attack]
		_owe_attacks(attacks)
		var snap_delay: float = _play_attack_move(member, EnemyTurn.signal_answer_intent(combatant, member.enemy_data))
		if snap_delay > 0.0:
			await get_tree().create_timer(snap_delay).timeout
		await _report_enemy_attack(member, attack)
		_hp_owed = 0
		if player.hp <= 0:
			return
		enemy_intent_changed.emit(member, get_intent_preview(member))

# Out of its dormancy: it acts from its next turn (this one, woken as the
# enemy turn begins), and its intent shows.
func _wake(enemy: FieldEnemy, cause: String) -> void:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or not combatant.dormant:
		return
	combatant.dormant = false
	RunLogger.mechanic("woke", {"enemy": _log_id(enemy), "by": cause})
	enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
	# Its Dormant goes from the status row.
	status_changed.emit()

# Each member's hits land at its own move's contact (_report_attacks_
# after(), all running at once), not after the longest: one wait covers
# the longest move and every member's last hit.
func _run_simultaneous_turn() -> void:
	var acting: Array[FieldEnemy] = []
	var results: Dictionary = {} # FieldEnemy -> take_turn() result
	var snaps: Dictionary = {} # FieldEnemy -> its attack move's contact
	var longest_snap: float = 0.0
	# A copy, as in _run_sequential_turn(): a countdown can drop an enemy.
	for enemy in enemies.duplicate():
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or enemy.enemy_data == null:
			continue
		enemy_acting.emit(enemy)
		var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
		results[enemy] = _take_turn_logged(enemy, combatant, enemy.enemy_data)
		# Its Block went as the turn began - the readout empties now.
		if results[enemy]["block_cleared"] > 0:
			status_changed.emit()
		if _report_countdown(enemy, combatant, results[enemy]):
			continue
		if results[enemy]["pain_turn_triggered"]:
			enemy_pain_turn.emit(enemy)
		if results[enemy]["phase_triggered"]:
			enemy_status_gained.emit(enemy, enemy.enemy_data.phase_status)
		acting.append(enemy)
		# The members' moves start together - one shared move.
		if results[enemy]["attacked"]:
			var snap: float = _play_attack_move(enemy, intent)
			snaps[enemy] = snap
			longest_snap = maxf(longest_snap, snap)
		if results[enemy]["defended"]:
			longest_snap = maxf(longest_snap, _play_defend_move(enemy, intent))
		# A Stunned or Delayed member sits the shared move out, on the same
		# beat.
		if results[enemy]["denied"] or results[enemy]["delayed"]:
			longest_snap = maxf(longest_snap, denied_beat_sec)
		longest_snap = maxf(longest_snap, _play_burrow_for(enemy, results[enemy]))
	# The rules have taken every member's hits already: all of them owed
	# before the first is shown.
	for enemy in acting:
		if results[enemy]["attacked"]:
			_owe_attacks(_attacks_of(results[enemy]))
	_reports_running = 0
	for enemy in acting:
		if results[enemy]["attacked"]:
			_reports_running += 1
			_report_attacks_after(enemy, _attacks_of(results[enemy]), float(snaps.get(enemy, 0.0)))
	if longest_snap > 0.0:
		await get_tree().create_timer(longest_snap).timeout
	while _reports_running > 0:
		await get_tree().process_frame
	_hp_owed = 0
	for enemy in acting:
		if results[enemy]["defended"]:
			_report_enemy_block(enemy, results[enemy])
	for enemy in acting:
		if bool(results[enemy].get("signal", false)) and player.hp > 0:
			await _answer_signal(enemy)
	status_changed.emit()
	for enemy in acting:
		_show_roused(enemy)
		enemy_intent_changed.emit(enemy, get_intent_preview(enemy))
	_apply_intent_exclusions(acting)

# One attack's move: the intent's own (EnemyIntent.motion), else the
# lunge. How long until it lands.
func _play_attack_move(enemy: FieldEnemy, intent: EnemyIntent) -> float:
	var delay: float = enemy.play_intent_motion(intent.motion, _wanderer) if intent != null else -1.0
	return delay if delay >= 0.0 else enemy.play_attack_snap(_wanderer)

# A Defend's move (EnemyIntent.motion) as its Block goes up - how long
# it takes, 0 for one with none.
func _play_defend_move(enemy: FieldEnemy, intent: EnemyIntent) -> float:
	if intent == null:
		return 0.0
	return maxf(enemy.play_intent_motion(intent.motion, _wanderer), 0.0)

# Whether the fight's whole pack fell together: two or more opened it,
# and every one of them was killed on the same turn of the Wanderer's -
# none on an enemy's turn, none left standing.
func felled_together() -> bool:
	if _roster.size() < 2:
		return false
	var turn: int = -1
	for enemy in _roster:
		if not _fell_on.has(enemy) or int(_fell_on[enemy]) < 0:
			return false
		if turn < 0:
			turn = int(_fell_on[enemy])
		elif int(_fell_on[enemy]) != turn:
			return false
	return true

# The held pieces' draw (TrinketData.draw_on_multi_hit, both slots
# summed): the card just resolved took HP from two or more enemies -
# kills included - and this turn's draw is unspent.
func _draw_for_multi_hit() -> void:
	var draw: int = 0
	for piece in RunState.held_pieces():
		draw += maxi(piece.draw_on_multi_hit, 0)
	if draw <= 0 or _multi_hit_draw_used or _card_damaged.size() < 2:
		return
	_multi_hit_draw_used = true
	print("BattleController: a card took HP from %d enemies; drawing %d (draw_on_multi_hit)." % [_card_damaged.size(), draw])
	deck.draw(draw)

# How much Block outlasts each turn's reset: the held pieces' block_carry,
# summed.
func _block_carry() -> int:
	var carry: int = 0
	for piece in RunState.held_pieces():
		carry += maxi(piece.block_carry, 0)
	return carry

# The held pieces' draw for the turn's Nth card (TrinketData.draw_on_
# card_count - Worn Page, both slots summed): the card just resolved
# brought this turn's plays (cards_played_this_turn, counted at commit -
# 0-cost cards included, never a set-aside, Devoured or discarded one) to
# a piece's count, and this turn's draw is unspent. Once a turn.
func _draw_for_card_count() -> void:
	if _card_count_draw_used:
		return
	var draw: int = 0
	for piece in RunState.held_pieces():
		if piece.draw_on_card_count > 0 and cards_played_this_turn >= piece.draw_on_card_count:
			draw += maxi(piece.card_count_draw, 0)
	if draw <= 0:
		return
	_card_count_draw_used = true
	print("BattleController: card %d this turn; drawing %d (draw_on_card_count)." % [cards_played_this_turn, draw])
	RunLogger.mechanic("keepsake_draw", {"card_count": cards_played_this_turn, "drawn": draw})
	deck.draw(draw)

# The held pieces' draw for a Skill after an Attack (TrinketData.draw_on_
# skill_after_attack - Knotted Cord, both slots summed): `card`, just
# resolved, is a Skill, an Attack has been played this turn (Combatant.
# last_attack - a real play, set at its commit, cleared as the turn
# starts), and this turn's draw is unspent. Once a turn.
func _draw_for_skill_after_attack(card: CardData) -> void:
	if _skill_after_attack_draw_used or card == null or card.card_type != CardData.CardType.SKILL or player.last_attack == null:
		return
	var draw: int = 0
	for piece in RunState.held_pieces():
		draw += maxi(piece.draw_on_skill_after_attack, 0)
	if draw <= 0:
		return
	_skill_after_attack_draw_used = true
	print("BattleController: a Skill after an Attack; drawing %d (draw_on_skill_after_attack)." % draw)
	RunLogger.mechanic("keepsake_draw", {"skill_after_attack": true, "drawn": draw})
	deck.draw(draw)

# The attacks a turn's result landed, each as _report_enemy_attack()
# reads one: its "actions" (EnemyTurn.take_turn()), or the result itself
# when it holds none.
func _attacks_of(result: Dictionary) -> Array[Dictionary]:
	var attacks: Array[Dictionary] = []
	for attack: Dictionary in result.get("actions", []):
		attacks.append(attack)
	if attacks.is_empty():
		attacks.append(result)
	return attacks

# A countdown that went off at the start of this enemy's turn (Sentence -
# EnemyTurn.take_turn()'s "countdown_damage"), reported as the player's
# damage but not a card's. True when it killed the enemy, which is then
# already dropped.
func _report_countdown(enemy: FieldEnemy, combatant: Combatant, result: Dictionary) -> bool:
	var taken: int = result.get("countdown_damage", 0)
	if taken > 0:
		RunLogger.mechanic("sentence_resolved", {"enemy": _log_id(enemy), "damage": taken, "by": "tick"})
		_report_damage("player", combatant, taken, "status")
	return combatant.hp <= 0

# One member's attacks in a shared move: its hits from `delay` (its own
# move's contact), each attack after the last enemy_hit_interval on.
func _report_attacks_after(enemy: FieldEnemy, attacks: Array[Dictionary], delay: float) -> void:
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	for i in attacks.size():
		if i > 0 and enemy_hit_interval > 0.0:
			await get_tree().create_timer(enemy_hit_interval).timeout
		await _report_enemy_attack(enemy, attacks[i])
	_reports_running -= 1

# The HP `attacks` took by the rules, owed to the HP bar until each hit is
# reported (_report_enemy_hit()). Called before the first of them shows.
func _owe_attacks(attacks: Array[Dictionary]) -> void:
	for attack in attacks:
		for hit: Dictionary in attack.get("hits", []):
			_hp_owed += int(hit["to_hp"]) - int(hit.get("saved_heal", 0))

# `target`'s max HP - a FieldEnemy in the fight, or "player"; 0 for one
# it no longer holds. For the size of its numbers (BattleFeedback.
# number_scale()).
func max_hp_of(target: Variant) -> int:
	if target is FieldEnemy:
		var combatant: Combatant = _combatants.get(target)
		return combatant.max_hp if combatant != null else 0
	return player.max_hp if player != null else 0

# The player's HP as the readouts should show it now: the rules' HP, plus
# what enemy hits have taken but not yet reported (_owe_attacks()). Read
# by BattleFeedback in a hit's own frame - 0 or less: that hit kills.
func shown_player_hp() -> int:
	return player.hp + _hp_owed

# Whether the enemy hit reporting now is one of its attack's several - its
# stop is the multi-hit one (BattleFeedback). Read in the hit's own frame.
func is_multi_hit_report() -> bool:
	return _multi_hit_report

# The attack as the view hears it, once its move has landed: hit by hit,
# enemy_hit_interval apart, each its own report (_report_enemy_hit()) -
# then the Grace it opened, what it left on them and the worn piece's hit
# back. Its HP is owed already (_owe_attacks()).
func _report_enemy_attack(enemy: FieldEnemy, result: Dictionary) -> void:
	RunLogger.block_used(result["blocked"], result["absorbed"])
	if enemy.enemy_data != null:
		RunLogger.enemy_attack(enemy.enemy_data.resource_path.get_file().get_basename(), result["intent"], result["hits"])
	var hits: Array = result.get("hits", [])
	_toll_owed = 0
	for hit: Variant in hits:
		_toll_owed += int((hit as Dictionary).get("tolled", 0))
	for i in hits.size():
		if i > 0 and enemy_hit_interval > 0.0:
			await get_tree().create_timer(enemy_hit_interval).timeout
			if not is_instance_valid(enemy):
				_toll_owed = 0
				return
		_report_enemy_hit(enemy, hits[i] as Dictionary, hits.size() > 1)
	_toll_owed = 0
	_report_entry_block()
	if result["grace_opened"] > 0:
		RunLogger.grace_opened(result["grace_opened"])
		grace_changed.emit(player.grace)
	# What it left on them (the Adder's Venom) shows with the hit.
	if int(result.get("applied_to_player", 0)) > 0:
		status_changed.emit()
	# Barbed going off (EnemyTurn.land_attack()'s "barbed_fired"): gone from
	# the player's row, and its damage back - already taken off the enemy -
	# reported as the worn piece's is, below.
	if result.get("barbed_fired", false):
		status_changed.emit()
		var barbed: int = int(result.get("barbed", 0))
		var barbed_target: Combatant = _combatants.get(enemy)
		RunLogger.mechanic("barbed", {"attacker": _log_id(enemy), "damage": barbed})
		if barbed > 0 and barbed_target != null:
			_report_damage("player", barbed_target, barbed, "hit_back")
	# The worn piece's damage back (EnemyTurn.land_attack()'s "hit_back"),
	# already taken off the enemy: reported as the Wanderer's damage, not a
	# card's - a kill held for its blow and dropped, like a countdown's.
	var hit_back: int = int(result.get("hit_back", 0))
	if hit_back > 0:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null:
			RunLogger.mechanic("hit_back", {"enemy": _log_id(enemy), "damage": hit_back})
			_report_damage("player", combatant, hit_back, "hit_back")

# One hit of an enemy's attack (`multi`: one of several): what reached HP
# as its own report, or - Block, absorb or Toll (Thick Skin) having taken
# it whole - player_hit_blocked. Toll it took drops the readout now, hit
# by hit. A lethal guard that left the player above where the
# hit found them (Refuse the End's survive HP) lifts the run's HP after
# it, the way a card's heal does - HP only, no Toll - in the fight's
# order: all the loss first would stop the run's HP at 0 and lose the
# later hits.
func _report_enemy_hit(enemy: FieldEnemy, hit: Dictionary, multi: bool) -> void:
	var to_hp: int = int(hit["to_hp"])
	var tolled: int = int(hit.get("tolled", 0))
	_multi_hit_report = multi
	if tolled > 0:
		_toll_owed = maxi(_toll_owed - tolled, 0)
		toll_changed.emit(player.toll + _toll_owed)
	if to_hp > 0:
		_hp_owed -= to_hp
		_report_damage(enemy, player, to_hp, "attack")
	elif int(hit["damage"]) > 0 and int(hit["blocked"]) + int(hit["absorbed"]) + tolled > 0:
		player_hit_blocked.emit(enemy)
	_multi_hit_report = false
	var lift: int = int(hit.get("saved_heal", 0))
	if lift > 0:
		_hp_owed += lift
		_heal_run_hp(lift, "lethal_guard")
		hp_changed.emit(shown_player_hp(), player.max_hp)
		combat_text.emit("player", lift, "heal")

# The body's pose for its queued intent (FieldEnemy.set_rearing()):
# reared while an intent that asks for it (EnemyIntent.rear_while_
# queued) is queued, not yet broken (its interrupt threshold met) and the
# enemy is above the sand; flat otherwise. Returns how long the change
# takes; 0 when there is none. A plain attack queued above the sand asks
# for the tell (FieldEnemy.set_poised()), cosmetic and not waited on. The
# status the intent holds it in (EnemyIntent.status_while_queued - the
# Underfoot's Covered / Exposed) is the body's to show too (FieldEnemy.
# set_queued_status()), waited on with the rear, and so are the statuses
# it holds (FieldEnemy.show_held_statuses() - the Glower's swell).
func _pose_for_intent(enemy: FieldEnemy) -> float:
	var combatant: Combatant = _combatants.get(enemy)
	var rear: bool = false
	var poised: bool = false
	var held: StatusData = null
	if combatant != null and combatant.hp > 0 and not combatant.buried and enemy.enemy_data != null:
		var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
		rear = intent != null and intent.rear_while_queued and not EnemyTurn.is_interrupted(combatant, intent) and not EnemyTurn.is_denied(combatant) and not EnemyTurn.is_delayed(combatant)
		poised = intent != null and intent.type == EnemyIntent.IntentType.ATTACK and not intent.rear_while_queued
		held = intent.status_while_queued if intent != null else null
	enemy.set_poised(poised)
	_show_roused(enemy)
	var state_delay: float = enemy.set_queued_status(held)
	# What it holds now, for a body that shows it (the Glower swollen
	# while Inflated) - the living only, so a kill doesn't let it down.
	if combatant != null and combatant.hp > 0:
		var statuses: Array[StatusData] = []
		for active: Status in combatant.statuses:
			statuses.append(active.data)
		state_delay = maxf(state_delay, enemy.show_held_statuses(statuses))
	return maxf(enemy.set_rearing(rear), state_delay)

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

# The battle frame has settled (RegionField._start_battle_hover()): each
# enemy that opens the fight dug in (EnemyData.opens_dug_in - its rules
# already under, EnemyTurn.pick_initial_intent()) stays down, and its
# row swells up across the battle camera's view as a turn's Dig lays it,
# the tell on its own mound. Called before the frame's hover, so the body
# never rises first.
func open_dug_in() -> void:
	var camera := get_viewport().get_camera_3d()
	var across: Vector3 = camera.global_transform.basis.x if camera != null else Vector3.ZERO
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0 or not combatant.dug_in or combatant.dig_intent == null or enemy.is_dug_in() or _wanderer == null:
			continue
		enemy.enter_battle_dug_in()
		enemy.begin_dig(combatant.dig_intent.mound_count, _wanderer.global_position, across)
		enemy.set_dig_tell(combatant.true_mound)

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

# The encounter's exclusions (FloorEnemy.excluded_intent): every living
# enemy with one redraws if its excluded move is queued while another
# living enemy in the fight has the triggering one queued
# (EnemyTurn.exclude_queued()), and shows what it drew. Run whenever an
# intent is newly queued - the fight's opening picks and after each
# enemy's action - so the turn the player faces never has both. Only
# `settled` enemies take part, as the trigger and as the one redrawing:
# those whose queued intent is already the coming turn's (all of them at
# the opening; in an enemy turn, those that have acted). One still to act
# shows the turn now ending - the Underfoot's Sting as the Sputter, ahead
# of it, picks - or a move about to resolve.
func _apply_intent_exclusions(settled: Array[FieldEnemy]) -> void:
	for enemy in settled:
		if enemy.excluded_intent.is_empty() or enemy.enemy_data == null:
			continue
		var combatant: Combatant = _combatants.get(enemy)
		if combatant == null or combatant.hp <= 0:
			continue
		var others: Array[EnemyIntent] = []
		for other in settled:
			var other_combatant: Combatant = _combatants.get(other)
			if other == enemy or other_combatant == null or other_combatant.hp <= 0 or other.enemy_data == null:
				continue
			others.append(EnemyTurn.current_intent(other_combatant, other.enemy_data))
		if EnemyTurn.exclude_queued(combatant, enemy.enemy_data, enemy.excluded_intent, enemy.excluded_while_packmate_intent, others):
			enemy_intent_changed.emit(enemy, get_intent_preview(enemy))

func _start_player_turn() -> void:
	# Block resets, but the held pieces' carry (TrinketData.block_carry -
	# Blue Fastener, both slots summed) keeps up to that much of what's
	# left. Absorb isn't Block, and never resets here.
	var block_before: int = player.block
	var carry: int = _block_carry()
	player.block = mini(player.block, carry)
	_enemy_phase = false
	_player_turn += 1
	_multi_hit_draw_used = false
	_card_count_draw_used = false
	_skill_after_attack_draw_used = false
	# The refill, Dying Light's 1 if the turn begins Critical - judged
	# here, before any tick, so entering Critical later gives nothing
	# until the next turn starts - and the Energy carried over, with any
	# debt paid out of all of it.
	var owed: int = Status.energy_debt(player.statuses)
	var carried: int = _energy_carried
	_energy_carried = 0
	player.energy = player.turn_start_energy(carried)
	# The run log's turn opens on the refill, before any tick it counts.
	RunLogger.turn_started(player.energy)
	# Marrow (a Devoured Skill's yield): its Block, on top of what the
	# reset kept, before any tick.
	var marrow: int = Status.turn_start_block(player.statuses)
	if marrow > 0:
		player.block += marrow
		combat_text.emit("player", marrow, "block")
		RunLogger.block_gained(marrow)
	# Energy owed (Come Due) paid off in the refill just now, out of the
	# carried Energy too: the "energy" the turn starts on after it.
	if owed > 0:
		RunLogger.mechanic("energy_debt", {"owed": owed, "carried": carried, "energy": player.energy})
	# In the new turn's lines: the Energy carried over (Departure Stub) and
	# the turn it starts on, debt paid.
	if carried > 0:
		RunLogger.mechanic("keepsake_energy_carry", {"carried": carried, "energy": player.energy})
	# In the new turn's lines: what the carry kept of the Block left over.
	if carry > 0 and block_before > 0:
		RunLogger.mechanic("keepsake_block_carry", {"kept": player.block, "lost": block_before - player.block})
	cards_played_this_turn = 0
	player.plays_this_turn = 0
	_devour_uses_this_turn = 0
	_sheathe_uses_this_turn = 0
	# A fresh turn for every interrupt threshold, and for Toll spent
	# (Condition.TOLL_SPENT_THIS_TURN).
	player.damage_taken_this_turn = 0
	player.toll_spent_this_turn = false
	player.tagged_plays_this_turn.clear()
	player.self_loss_attack_armed = false
	Skillchain.reset(player)
	player.clear_last_attack()
	_last_attack_enemy = null
	_last_attack_mound = -1
	for enemy in enemies:
		var combatant: Combatant = _combatants.get(enemy)
		if combatant != null:
			combatant.damage_taken_this_turn = 0

	Status.tick_all(player.statuses, func(amount: int, ticking: Status) -> void:
		# For the run log: the loss, and its Toll, are this status's.
		RunLogger.push_source("status:" + (ticking.data.id if ticking.data != null else ""))
		var hp_before: int = player.hp
		var was_critical: bool = player.is_critical()
		var lost := DamagePipeline.apply_bypass(amount, player)
		if ticking.data == null or ticking.data.tick_is_self_loss:
			if lost > 0:
				player.gain_self_loss_toll(lost)
				# A tick has no contact: its number, nothing else (BattleFeedback
				# reacts to an enemy's or a card's hit only).
				damage_dealt.emit("player", "player", lost, "self")
				_lose_run_hp(lost, "status")
				hp_changed.emit(player.hp, player.max_hp)
				toll_changed.emit(player.toll)
		else:
			# Not their own doing (Venom): no Toll, the loss the status's own
			# in the run log - and a tick that would kill them Critical is
			# caught by a lethal guard, as an enemy hit is (EnemyTurn.land_
			# attack()), the HP over what they had a heal.
			var saved_heal: int = 0
			if Status.refuse_lethal(player, was_critical):
				lost = maxi(hp_before - player.hp, 0)
				saved_heal = maxi(player.hp - hp_before, 0)
			if lost > 0:
				damage_dealt.emit("player", "player", lost, "status")
				_lose_run_hp(lost, ticking.data.id)
			if saved_heal > 0:
				_heal_run_hp(saved_heal, "lethal_guard")
				combat_text.emit("player", saved_heal, "heal")
			if lost > 0 or saved_heal > 0:
				hp_changed.emit(player.hp, player.max_hp)
		RunLogger.pop_source()
	)
	# A tick is a loss to their own effect like any other: one that sets a
	# counter off (The Return) Drains now, in a context of its own - no
	# card is resolving to carry it.
	if player.pending_drain > 0:
		var ctx := EffectContext.new()
		ctx.player = player
		ctx.enemies = _card_enemy_combatants()
		_wire_mounds(ctx)
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
	_report_entry_block()
	status_changed.emit()
	# The enemy turn may have buried or surfaced someone.
	_push_enemy_target_available()
	energy_changed.emit(player.energy)
	# A fresh use, and the refill it's paid from.
	_emit_devour_changed()
	# Block just reset to 0 and statuses ticked: lethal flags change here.
	_emit_intent_previews()

	if not _check_battle_end():
		_hand_container.draw_cards(turn_draw_amount)

func _check_battle_end() -> bool:
	if player.hp <= 0:
		RunLogger.turn_ended(player.energy)
		battle_lost.emit()
		return true
	if _living_enemy_combatants().is_empty():
		if _win_waiting:
			return true
		RunLogger.turn_ended(player.energy)
		# Won - but the last deaths play first: the win goes when they've
		# ended (_maybe_win()), and nothing new starts meanwhile.
		if not _pending_deaths.is_empty() or not _dying.is_empty():
			_win_waiting = true
			_input_locked = true
			return true
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
# enemy: whatever it held went with it. One shown beside the HP instead
# (StatusData.shows_beside_hp - Coiled) isn't among them: see get_enemy_
# hp_mark_status().
func get_enemy_status_labels(enemy: FieldEnemy) -> PackedStringArray:
	var labels := PackedStringArray()
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return labels
	# Dormant: its EnemyData.dormant_status first, while it sleeps.
	if combatant.dormant and enemy.enemy_data != null and enemy.enemy_data.dormant_status != null:
		labels.append(enemy.enemy_data.dormant_status.display_name)
	for active: Status in combatant.statuses:
		if active.data != null and active.data.shows_beside_hp:
			continue
		# A countdown (Sentence) shows beside the intent, glyph and numeral
		# (get_enemy_countdowns()).
		if active.has_countdown():
			continue
		# What lives on its intent (Braced, Garnished) shows there
		# (BattleIntent), not in the row.
		if active.data != null and active.data.intent_mark != &"":
			continue
		var text: String = active.label()
		if not text.is_empty():
			labels.append(text)
	return labels

# The turns left on each countdown on this enemy (Sentence), soonest
# first - its readout's hourglass marks beside the HP. Empty for none, or
# for a dead/unknown enemy.
func get_enemy_countdowns(enemy: FieldEnemy) -> Array[int]:
	var turns: Array[int] = []
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return turns
	for active: Status in combatant.statuses:
		if active.has_countdown():
			turns.append(active.turns_remaining)
	turns.sort()
	return turns

# The status this enemy's readout shows beside its HP (StatusData.shows_
# beside_hp - Coiled: its mark and magnitude), or null - none, or the
# enemy dead/unknown. Read by BattleOverlay with the labels above.
func get_enemy_hp_mark_status(enemy: FieldEnemy) -> Status:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return null
	for active: Status in combatant.statuses:
		if active.data != null and active.data.shows_beside_hp:
			return active
	return null

# This enemy's statuses themselves, for what its readout's hover reveal
# says they do (Status.describe()) - read by BattleOverlay on status_
# changed, beside the labels above. A copy; empty for a dead/unknown
# enemy, like the labels.
func get_enemy_statuses(enemy: FieldEnemy) -> Array[Status]:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or combatant.hp <= 0:
		return []
	var shown: Array[Status] = []
	if combatant.dormant and enemy.enemy_data != null and enemy.enemy_data.dormant_status != null:
		shown.append(Status.new(enemy.enemy_data.dormant_status))
	for active in combatant.statuses:
		if active.data == null or active.data.intent_mark == &"":
			shown.append(active)
	return shown

# What an intent hover says of `enemy`'s queued intent (BattleOverlay's
# intent hover line), as facts for the overlay to word: "name", "preview"
# (get_intent_preview()), "intent" (the EnemyIntent), "next" (the next
# move's EnemyIntent in a fixed loop, null for an erratic one), "brings"
# / "holds" ([display name, what it does] of its status_on_resolve /
# status_while_queued, empty for none), "answers" (each living
# packmate's answer to a SIGNAL: [move name, damage, its EnemyData]),
# "waking" (how many of them sleep), "heals" (a HEAL_ALLY's living
# packmates' EnemyData), "under" (a DIG's first move under the sand:
# [name, value]). Empty for no intent.
func intent_facts(enemy: FieldEnemy) -> Dictionary:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or enemy == null or enemy.enemy_data == null or combatant.hp <= 0:
		return {}
	var data: EnemyData = enemy.enemy_data
	var intent: EnemyIntent = EnemyTurn.current_intent(combatant, data)
	if intent == null or combatant.dormant:
		return {}
	var facts: Dictionary = {"name": intent.intent_name, "preview": get_intent_preview(enemy), "intent": intent, "next": null, "brings": [], "brings_status": null, "holds": [], "answers": [], "waking": 0, "heals": [], "under": []}
	if not data.erratic_intent_selection and not combatant.dug_in and not data.intents.is_empty():
		facts["next"] = data.intents[(combatant.current_intent_index + 1) % data.intents.size()]
	# What lives on the intent (Braced, Garnished), and each hit as it would
	# read without them - for the hover's breakdown.
	var marked: Array[Status] = Status.marks(combatant.statuses)
	if not marked.is_empty() and intent.type == EnemyIntent.IntentType.ATTACK:
		facts["marks"] = marked
		var unmarked: Array[int] = []
		var each: int = EnemyTurn.unmarked_hit_amount(combatant, data, intent, player.statuses)
		for hit in EnemyTurn.hit_count(combatant, intent) * EnemyTurn.repeats(combatant, intent):
			unmarked.append(each)
		facts["unmarked_hits"] = unmarked
	if intent.status_on_resolve != null:
		facts["brings"] = [intent.status_on_resolve.display_name, Status.new(intent.status_on_resolve).describe()]
		facts["brings_status"] = intent.status_on_resolve
	if intent.status_while_queued != null:
		facts["holds"] = [intent.status_while_queued.display_name, Status.new(intent.status_while_queued).describe()]
	if intent.type == EnemyIntent.IntentType.DIG and not intent.under_moves.is_empty() and intent.under_moves[0] != null:
		facts["under"] = [intent.under_moves[0].intent_name, intent.under_moves[0].value]
	if intent.type == EnemyIntent.IntentType.SIGNAL and enemy.group != &"":
		var answers: Array = []
		var waking: int = 0
		# Each answer's hits as they will land (signal_answer_lists(), in
		# the same member order).
		# A Signal that won't go (Stunned, Delayed, a pain turn) carries none: what they
		# would answer with from where he stands.
		var lists: Array = (facts["preview"] as Dictionary).get("answer_lists", [])
		if lists.is_empty():
			lists = signal_answer_lists(enemy)
		var listed: int = 0
		for member in enemies:
			if member == enemy or member.group != enemy.group or member.enemy_data == null:
				continue
			var mate: Combatant = _combatants.get(member)
			if mate == null or mate.hp <= 0:
				continue
			var answer: EnemyIntent = EnemyTurn.signal_answer_intent(mate, member.enemy_data)
			if answer == null:
				continue
			if mate.dormant:
				waking += 1
			var landed: int = 0
			if listed < lists.size():
				for amount: int in lists[listed]:
					landed += amount
			listed += 1
			answers.append([answer.intent_name, landed, member.enemy_data])
		facts["answers"] = answers
		facts["waking"] = waking
	if intent.type == EnemyIntent.IntentType.HEAL_ALLY and enemy.group != &"":
		var heals: Array[EnemyData] = []
		for member in enemies:
			if member == enemy or member.group != enemy.group or member.enemy_data == null:
				continue
			var mate: Combatant = _combatants.get(member)
			if mate != null and mate.hp > 0:
				heals.append(member.enemy_data)
		facts["heals"] = heals
	return facts

# The name of the intent `enemy` has queued (EnemyIntent.intent_name), ""
# for none - what an armed Brace or Garnish's refusal names.
func queued_intent_name(enemy: FieldEnemy) -> String:
	var combatant: Combatant = _combatants.get(enemy)
	if combatant == null or enemy == null or enemy.enemy_data == null:
		return ""
	var intent: EnemyIntent = EnemyTurn.current_intent(combatant, enemy.enemy_data)
	return intent.intent_name if intent != null else ""

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
	combat_text.emit("player", amount, "heal")

func _on_grace_reclaimed(amount: int) -> void:
	var before: int = RunState.player_hp
	RunState.heal(amount)
	RunLogger.grace_reclaimed(RunState.player_hp - before)
	hp_changed.emit(player.hp, player.max_hp)
	grace_changed.emit(player.grace)
	combat_text.emit("player", amount, "heal")

# End of the player's turn: the window ages, and whatever Grace is left
# when it runs out is gone. Runs BEFORE the enemy turn (see end_turn()),
# so the hits that are about to land open a fresh window rather than
# topping up a spent one.
func _close_grace_window() -> void:
	if player.grace <= 0:
		player.grace_turns_left = 0
		player.grace_window_hits.clear()
		return
	player.grace_turns_left -= 1
	if player.grace_turns_left > 0:
		return
	RunLogger.grace_lost(player.grace)
	player.grace = 0
	player.grace_window_hits.clear()
	grace_changed.emit(0)

# The Critical-entry Block the keepsake gave since the last report
# (Combatant.entry_block_unreported) - its number, once the action that
# crossed the line has shown.
func _report_entry_block() -> void:
	var gained: int = player.entry_block_unreported
	player.entry_block_unreported = 0
	if gained > 0:
		combat_text.emit("player", gained, "block")

# An enemy's Defend has gone up (its move landed): its Block's number.
func _report_enemy_block(enemy: FieldEnemy, result: Dictionary) -> void:
	var gained: int = int(result.get("block_gained", 0))
	if gained > 0 and is_instance_valid(enemy):
		combat_text.emit(enemy, gained, "block")

# EffectContext.on_block: a hit of the player's met an enemy's block.
func _report_block(target_combatant: Combatant, _blocked: int, damage_to_hp: int) -> void:
	var enemy := _field_enemy_for(target_combatant)
	if enemy != null:
		enemy_hit_blocked.emit(enemy, damage_to_hp <= 0)

func _report_damage(source: Variant, target_combatant: Combatant, amount: int, kind: String) -> void:
	# A mound's HP: its own report - the enemy under it took nothing.
	if target_combatant.mound_owner != null:
		var owner_enemy := _field_enemy_for(target_combatant.mound_owner)
		if owner_enemy != null:
			mound_damaged.emit(owner_enemy, target_combatant.mound_index, amount, target_combatant.hp, target_combatant.max_hp)
		return
	if target_combatant == player:
		damage_dealt.emit(source, "player", amount, kind)
		# The log's source: the enemy by name, else the kind ("self",
		# "status").
		var source_name: String = kind
		if source is FieldEnemy and (source as FieldEnemy).enemy_data != null:
			source_name = (source as FieldEnemy).enemy_data.enemy_name
		_lose_run_hp(amount, source_name)
		hp_changed.emit(shown_player_hp(), player.max_hp)
	else:
		RunLogger.damage_dealt(target_combatant.get_instance_id(), amount, target_combatant.hp)
		var enemy := _field_enemy_for(target_combatant)
		# A killing hit: its death is held from here (is_dying()), so its
		# own presentation - which asks - can show it in full.
		var killed: bool = enemy != null and target_combatant.hp <= 0
		if killed and not _pending_deaths.has(enemy):
			_pending_deaths.append(enemy)
		if killed and not _fell_on.has(enemy):
			_fell_on[enemy] = -1 if _enemy_phase else _player_turn
		damage_dealt.emit(source, enemy, amount, kind)
		if enemy != null:
			enemy_hp_changed.emit(enemy, target_combatant.hp, target_combatant.max_hp)
			if killed:
				_hold_death_for(enemy, amount)
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

# The enemy is dead to the rules: out of the lists at once, so no later
# preview/turn/rect pass reads it. The hover clears too, or an armed card
# could keep it lit. Its death - enemy_defeated - waits for the blow
# (_release_deaths_when_due()).
func _drop_enemy(enemy: FieldEnemy) -> void:
	RunLogger.enemy_died(_log_id(enemy))
	# What lived on its intent goes with it, unspent.
	var dying: Combatant = _combatants.get(enemy)
	if dying != null:
		for active in Status.marks(dying.statuses):
			dying.statuses.erase(active)
			var entry: Dictionary = EnemyTurn.mark_entry(active)
			entry["outcome"] = "lost"
			entry["reason"] = "enemy died"
			intent_mark_settled.emit(enemy, entry)
	enemies.erase(enemy)
	_combatants.erase(enemy)
	_enemy_rects.erase(enemy)
	if _hovered_enemy == enemy:
		_clear_hover()
	if _cursor_enemy == enemy:
		_set_cursor_enemy(null)
	if _deferring_pack_check:
		_pack_check_due = true
	else:
		_mark_lone_pack_members()

# Whether `enemy` was killed and its death hasn't finished - held for its
# blow, or running. BattleFeedback reads it in the killing hit's own
# frame, for the kill's hit-stop.
func is_dying(enemy: Variant) -> bool:
	return enemy is FieldEnemy and (_pending_deaths.has(enemy) or _dying.has(enemy))

# Whether any death is still waiting on its blow.
func has_held_deaths() -> bool:
	return not _pending_deaths.is_empty()

# A killing hit on `enemy` for `amount`: the deaths held until its whole
# presentation has played (kill_presentation_time, plus kill_presentation_
# margin) - a later kill in the same blow only ever extends the hold.
func _hold_death_for(enemy: FieldEnemy, amount: int) -> void:
	var seconds: float = kill_presentation_margin
	if kill_presentation_time.is_valid():
		seconds += float(kill_presentation_time.call(enemy, amount))
	_death_release_usec = maxi(_death_release_usec, Time.get_ticks_usec() + int(maxf(seconds, 0.0) * 1000000.0))
	if not _death_release_running:
		_release_deaths_when_due()

# Waits out the hold on real time - a hit-stop slows scaled time, and the
# hold already counts it - then begins every held death: enemy_defeated
# for each, the overlay and RegionField taking it from there. One nobody
# took off the field (not settling) has finished at once. Then the win,
# if it was waiting on these (_maybe_win()).
func _release_deaths_when_due() -> void:
	_death_release_running = true
	while Time.get_ticks_usec() < _death_release_usec:
		await get_tree().create_timer(float(_death_release_usec - Time.get_ticks_usec()) / 1000000.0, true, false, true).timeout
	_death_release_running = false
	var released: Array[FieldEnemy] = _pending_deaths.duplicate()
	_pending_deaths.clear()
	for enemy in released:
		if not is_instance_valid(enemy):
			continue
		_dying.append(enemy)
		enemy.death_finished.connect(_on_death_finished.bind(enemy), CONNECT_ONE_SHOT)
		enemy_defeated.emit(enemy)
		if not enemy.is_settling():
			_on_death_finished(enemy)
	deaths_released.emit()
	_maybe_win()

func _on_death_finished(enemy: FieldEnemy) -> void:
	_dying.erase(enemy)
	_maybe_win()

# Every death running now, straight to its end (FieldEnemy.skip_death()):
# a click does it (_input()). Only a death that has begun - a blow still
# showing (its death held) is never cut.
func skip_deaths() -> void:
	for enemy in _dying.duplicate():
		if is_instance_valid(enemy):
			enemy.skip_death()

# Whether any death is running now.
func has_running_deaths() -> bool:
	return not _dying.is_empty()

# A click anywhere while a death runs skips it - and goes on to whatever
# else it does (a card, the end of the turn): never consumed here.
func _input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and not _dying.is_empty():
		skip_deaths()

# The last enemy fell and every death has played out: the fight is won.
func _maybe_win() -> void:
	if _win_waiting and _pending_deaths.is_empty() and _dying.is_empty():
		_win_waiting = false
		battle_won.emit()

# Every living enemy with no living packmate left in the fight (none
# sharing its FieldEnemy.group - an ungrouped enemy has none) stops using
# its pack moves and turns what waits for that (EnemyTurn.leave_pack()):
# the island's last dragonfly bites instead of Swarming alone, the
# Nipper stops foraging, the Blackback turns Hungry. A queued move that
# gives way, or a status that turns, is shown at once. Living by HP, not
# by the list. A card's own kills are looked at once it is done (see
# _deferring_pack_check), so one that fells a whole pack turns none of it.
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
			combat_text.emit(other, heal, "heal")
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
		if card_view != _choosing_card_view:
			toggle_choice(card_view)
		return
	request_play(card_view)

# Gated on awaiting-target or Bide's open choice: this controller only
# reacts to input while a card is armed - waiting for an enemy click, or
# for its choice to be confirmed (Enter/Space) or cancelled (right-click/
# Esc) - everything else (movement, camera, ...) is untouched - and
# already frozen by RegionField anyway.
func _unhandled_input(event: InputEvent) -> void:
	if _devour_picking:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
			cancel_devour_pick()
			get_viewport().set_input_as_handled()
		return
	if _sheathe_picking:
		if (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT) or (event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE):
			cancel_sheathe_pick()
			get_viewport().set_input_as_handled()
		return
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
				confirm_target(enemy, _cursor_mound)
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
	var mound: int = _cursor_mound if enemy != null else -1
	_set_cursor_enemy(enemy)
	if enemy == null:
		enemy = _default_target()
	if enemy == _hovered_enemy and mound == _hovered_mound:
		return
	_clear_hover()
	_hovered_enemy = enemy
	_hovered_mound = mound
	if _hovered_enemy != null:
		if _hovered_enemy.is_dug_in():
			_hovered_enemy.set_mound_highlight(mound)
		else:
			_hovered_enemy.set_highlight(true)

func _set_cursor_enemy(enemy: FieldEnemy) -> void:
	if enemy == _cursor_enemy:
		return
	_cursor_enemy = enemy
	hovered_enemy_changed.emit(enemy)

func _clear_hover() -> void:
	if _hovered_enemy != null and is_instance_valid(_hovered_enemy):
		_hovered_enemy.set_highlight(false)
		_hovered_enemy.set_mound_highlight(-1)
	_hovered_enemy = null
	_hovered_mound = -1

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
# AABB (FieldEnemy.get_pick_rect() - the real mesh bounds, as placed,
# padded by target_padding_px on every side, and no smaller than
# min_target_size_px). No physics shape, no
# camera-distance dependence - what you can see is what you can target,
# plus a little. Recomputed by _physics_process() while a card is armed;
# _enemy_at() reads the cache. An enemy whose AABB reaches behind the
# camera gets no rect.
func _refresh_enemy_rects() -> void:
	_enemy_rects.clear()
	_mound_rects.clear()
	_intent_rects.clear()
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		var combatant: Combatant = _combatants.get(enemy)
		# The buried can't be targeted: no rect, so no click, hover or
		# default target lands on one - nor, for the armed card, one it
		# may not land on (Deny on the already Delayed).
		if combatant == null or combatant.hp <= 0 or combatant.buried:
			continue
		# Armed for Devour alone: no enemy is a target.
		if _pending_devour_only:
			continue
		if _pending_card_view != null and not _can_target(_pending_card_view.card_data, combatant):
			continue
		# A card that marks an intent (Brace, Garnish) is aimed at the
		# intent too: its readout is a target of its own (_enemy_at()).
		if _pending_card_view != null and _marks_intent(_pending_card_view.card_data) and intent_rect_of.is_valid():
			var intent_rect: Rect2 = intent_rect_of.call(enemy)
			if intent_rect.has_area():
				_intent_rects[enemy] = intent_rect.grow(target_padding_px)
		# Dug in (DIG): its standing mounds are its targets, each its own
		# rect, every one alike; the body under them has none.
		if combatant.dug_in:
			for mound in combatant.mounds:
				var mound_rect: Rect2 = enemy.get_mound_screen_rect(camera, mound, target_padding_px)
				if mound_rect.size != Vector2.ZERO:
					_mound_rects.append({"enemy": enemy, "mound": mound, "rect": mound_rect})
			continue
		var rect: Rect2 = enemy.get_pick_rect(camera, target_padding_px, min_target_size_px)
		if rect.size == Vector2.ZERO:
			continue
		_enemy_rects[enemy] = rect

# The enemy whose padded rect holds screen_pos; on overlap, the one
# nearest the camera. Rebuilds the cache if a click lands before the
# first armed physics frame.
func _enemy_at(screen_pos: Vector2) -> FieldEnemy:
	if _enemy_rects.is_empty() and _mound_rects.is_empty():
		_refresh_enemy_rects()
	var camera := get_viewport().get_camera_3d()
	var best: FieldEnemy = null
	var best_distance: float = INF
	_cursor_mound = -1
	# An intent under the cursor (a card that marks one - _intent_rects)
	# is its enemy's, before any body: the readout sits over the world.
	for enemy: FieldEnemy in _intent_rects:
		if (_intent_rects[enemy] as Rect2).has_point(screen_pos):
			return enemy
	for enemy: FieldEnemy in _enemy_rects:
		var rect: Rect2 = _enemy_rects[enemy]
		if not rect.has_point(screen_pos):
			continue
		var distance: float = camera.global_position.distance_to(enemy.global_position) if camera != null else 0.0
		if distance < best_distance:
			best_distance = distance
			best = enemy
	# A dug-in enemy's mounds, by where each mound stands: the cursor over
	# one names the enemy and the mound (_cursor_mound).
	for entry: Dictionary in _mound_rects:
		var rect: Rect2 = entry["rect"]
		if not rect.has_point(screen_pos):
			continue
		var mound_enemy: FieldEnemy = entry["enemy"]
		var mound: int = int(entry["mound"])
		var distance: float = camera.global_position.distance_to(mound_enemy.get_mound_position(mound)) if camera != null else 0.0
		if distance < best_distance:
			best_distance = distance
			best = mound_enemy
			_cursor_mound = mound
	return best

# The hovered enemy's padded screen rect (see _refresh_enemy_rects()) -
# TargetLine ends at its centre. Empty when nothing is hovered.
func get_hovered_enemy_rect() -> Rect2:
	if _hovered_enemy == null:
		return Rect2()
	if _hovered_mound >= 0:
		for entry: Dictionary in _mound_rects:
			if entry["enemy"] == _hovered_enemy and int(entry["mound"]) == _hovered_mound:
				return entry["rect"]
		return Rect2()
	return _enemy_rects.get(_hovered_enemy, Rect2())
