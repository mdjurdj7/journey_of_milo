extends RefCounted
class_name Combatant

# One fighter's rules-side state - the player or one enemy. Pure data;
# no signals, no view references. battle_controller.gd is what turns a
# mutation here into a signal for the overlay to react to.

var hp: int = 1
var max_hp: int = 1
var block: int = 0
var absorb: int = 0
var statuses: Array[Status] = []
# The one stance this fighter holds, or null. Player-only in practice;
# an enemy simply never takes one. See stance.gd for why it's one and not
# a list.
var stance: Stance = null

# --- Player-only resources ---
#
# Left at their defaults, unused, on an enemy Combatant - same "empty
# means unaffected" idiom the old project used throughout EnemyData/
# CardEffect.
#
# Toll is the one that outlives the fight: on the run's player (run_toll_
# owner, the RunState autoload, handed in by BattleController.setup()) it
# IS the owner's toll - read and written straight through, so every
# effect's `player.toll += n` lands on the floor's Toll with nothing to
# copy back at battle end. Anything else (an enemy, a bare Combatant in a
# probe) keeps its own local value. Held as a Node rather than named, so
# this script compiles where the autoload isn't registered yet (the
# headless probes).
var run_toll_owner: Node = null
var _local_toll: int = 0
var toll: int:
	get:
		if run_toll_owner != null:
			return run_toll_owner.get(&"toll") as int
		return _local_toll
	set(value):
		if run_toll_owner != null:
			run_toll_owner.call(&"set_toll", value)
		else:
			_local_toll = value
var energy: int = 0
var max_energy: int = 3

# The Energy a turn starts with: the refill, plus what a status adds for
# a turn begun Critical (Dying Light) - Critical judged now, as it
# refills (BattleController._start_player_turn()).
func turn_start_energy() -> int:
	return max_energy + Status.turn_start_energy(statuses, is_critical())
# Grace: HP an enemy took that this player can still take back, and how
# many of their turns are left to do it in. Per FIGHT, not per run - a
# Combatant is rebuilt by BattleController.setup() every battle, so
# leaving or winning a fight discards any open Grace with nothing to
# clear. See CharacterData's own Grace doc for the rule.
var grace: int = 0
var grace_turns_left: int = 0
# Defaults only - BattleController.setup() overwrites all four from
# RunState.character (the run's own CharacterData) the instant a
# Combatant is created. False on every enemy Combatant, which is what
# keeps Grace the Wanderer's alone.
var has_grace: bool = false
var grace_cap_mode: int = CharacterData.GraceCapMode.LARGEST_HIT
var grace_window_turns: int = 1
var grace_open_fraction: float = 0.5
var took_damage_this_turn: bool = false
# Whether self-inflicted loss accrues Toll (gain_self_loss_toll()). True
# for every enemy, as it always was; the player's is CharacterData.has_
# toll, copied by BattleController.setup() - false for a class without it.
var has_toll: bool = true
# Any Toll spent since this turn began, by any card or effect - set by
# EffectContext.spend_toll(), cleared by BattleController._start_player_
# turn(). Read by CardEffect.Condition.TOLL_SPENT_THIS_TURN (Gnaw).
var toll_spent_this_turn: bool = false
# Cards played since this turn began, by tag (CardData.tags): tag ->
# count. Counted at a play's commit (count_play() - BattleController.
# _resolve_play()), cleared by BattleController._start_player_turn().
# Read through EffectContext.tagged_plays_before_this (Lash's repeats).
var tagged_plays_this_turn: Dictionary = {}
# The last Attack card played this turn, what it was played at (null for
# an all-enemies one) and whether it hit every enemy - what Second Swing
# plays again (ReplayLastAttackEffect). Set at a play's commit (record_
# attack() - BattleController._resolve_play()), never by a replay; cleared
# by BattleController._start_player_turn().
var last_attack: CardData = null
var last_attack_target: Combatant = null
var last_attack_all: bool = false
var took_damage_last_turn: bool = false
# Critical: HP at or below this fraction of max HP. A default only, like
# the Grace fields above - BattleController.setup() copies CharacterData.
# critical_hp_fraction over it. Read through is_critical_at(), never
# compared against hp directly, so the rule lives in one place - and its
# line through critical_fraction(), which a status can raise (Gone Under).
var critical_hp_fraction: float = 0.3
# Lethal guards that have fired their last charge this fight (Refuse the
# End - Status.refuse_lethal()), each once: the readout's spent line. A
# copy played since arms it again. Per fight, like everything else here.
var spent_statuses: Array[StatusData] = []
# Drain a counter (The Return) has handed over and nothing has resolved
# yet - set here, where a loss is counted but no enemy is in reach, and
# spent by EffectContext.resolve_pending_drain() right after the loss.
var pending_drain: int = 0
# The keepsake's free card (TrinketData.first_card_free): while true, the
# next card played that costs at least 1 Energy costs 0 - a 0-cost card
# passes it by (takes_next_card_discount()). Set by BattleController.
# setup(), spent by the play itself (_resolve_play()) - never by a hover,
# a face, or a target armed and cancelled. Per fight, like everything
# here.
var first_card_free: bool = false
# The keepsake's Critical-entry Block (TrinketData.critical_entry_block)
# and whether it is still waiting: armed only while this fighter is seen
# OUT of Critical, so opening a fight already there doesn't count as
# entering it - see resolve_critical_entry(). Once fired, spent for the
# fight (critical_entry_block drops to 0).
var critical_entry_block: int = 0
var critical_entry_armed: bool = false
# The Critical-entry Block given and not yet shown - the controller reads
# and clears it once the action that gave it has reported.
var entry_block_unreported: int = 0
# The worn piece's first hit (TrinketData.first_hit_scale): below 1, the
# first enemy attack hit this fight that would get past Block and absorb
# is scaled by it, rounded down, before Block takes its share - see
# EnemyTurn.scale_first_hit(). Once taken, first_hit_spent for the fight.
var first_hit_scale: float = 1.0
var first_hit_spent: bool = false
# The worn piece's damage back (TrinketData.hit_back_damage): this much
# to an enemy, through its Block, once for each of its attacks that lands
# on this fighter (EnemyTurn.land_attack()). 0 = none.
var hit_back_damage: int = 0

# --- Enemy-only ---
#
# Left at its default -1 for the player Combatant - see enemy_turn.gd.
var current_intent_index: int = -1
# An interrupted intent's on_interrupt, queued in front of the loop for
# one turn (see EnemyIntent.on_interrupt) - EnemyTurn.current_intent()
# returns it while it's set. Null = the loop's own intent.
var interjected_intent: EnemyIntent = null
# The loop index queued before the last erratic pick - what that pick's
# no_immediate_repeat was judged against, kept for a redraw
# (EnemyTurn.exclude_queued()). -1 = none yet.
var previous_intent_index: int = -1
# Under the sand: the queued intent is a BURROW. Can't be targeted, takes
# no damage (DamagePipeline.resolve()). Kept in step with the queued
# intent by EnemyTurn - nothing else writes it.
var buried: bool = false
# Under the sand after a DIG (EnemyIntent.IntentType.DIG): dug_in, by
# which DIG (dig_intent), how many turns under so far (dug_step - its
# under_moves index), the mounds still standing (mounds, of the DIG's
# mound_count, 0-based), each mound's own Combatant by number (mound_
# guards - the targets in its place, EnemyIntent.mound_hp each) and the
# one it is under (true_mound). Set and cleared by EnemyTurn only
# (start_dig(), break_mound(), unearth(), take_turn()).
var dug_in: bool = false
var dig_intent: EnemyIntent = null
var dug_step: int = 0
var mounds: Array[int] = []
var mound_guards: Array[Combatant] = []
var true_mound: int = -1
# A mound's own Combatant (mound_guards above): the enemy under the row
# and which mound this is. Null / -1 for any other fighter.
var mound_owner: Combatant = null
var mound_index: int = -1
# What the last hit through DamagePipeline.resolve() took past this
# fighter's HP - a broken mound's, carried into the enemy under it.
var last_overkill: int = 0
# HP damage taken since the player's turn began - what an intent's
# interrupt_threshold is measured against. Counted by DamagePipeline.
# resolve(), reset by BattleController._start_player_turn().
var damage_taken_this_turn: int = 0
# No living packmate left in this fight (the last of its FieldEnemy.group,
# or never one): a pack move (EnemyTurn.is_pack_move()) is stepped past
# from here on - see EnemyTurn.leave_pack(). Set by
# BattleController; never cleared, a pack doesn't regroup mid-fight.
var pack_alone: bool = false
# Turns this enemy has taken this fight - every EnemyTurn.take_turn() it
# runs, a cancelled one included. The turn it is about to take is
# turns_taken + 1, which is what escalation reads (EnemyTurn.intent_
# value()). Per fight, like everything here.
var turns_taken: int = 0
# The pain turn (EnemyData.pain_turn_hp_threshold): it has happened this
# fight, and its cancelled action is still to come.
var pain_turn_used: bool = false
var pain_turn_pending: bool = false
# An enemy that takes no action and shows no intent until it is woken
# (EnemyData.starts_dormant - BattleController wakes it). It is
# targeted and damaged as ever, and its statuses still tick; its loop
# waits where it is.
var dormant: bool = false
# An enemy's own rules (BattleController sets it): what its queued intent
# is read from where only the Combatant is to hand - whether a card that
# marks an intent (StatusData.intent_mark - Brace, Garnish) may target it
# (EffectResolver.can_target()), and which intent it binds to. Null on the
# player and on a bare Combatant.
var enemy_data: EnemyData = null
# The phase (EnemyData.phase_hp_threshold): its status has been gained
# this fight, so it never is again.
var phase_reached: bool = false

func _init(starting_hp: int = 1) -> void:
	hp = starting_hp
	max_hp = starting_hp

# HP just lost to this fighter's own effect - a card's self-damage, a
# stance's price, a status tick: the Toll it accrues, 1 per HP.
# Every self-inflicted loss comes through here; an enemy's hit never
# does, which is the whole of the rule that Toll is self-inflicted - and
# of what a self-loss counter counts, once per call (Status.count_self_
# loss()).
func gain_self_loss_toll(lost: int) -> void:
	if lost <= 0:
		return
	if has_toll:
		toll += lost
	pending_drain += Status.count_self_loss(statuses)

# `card` has been played this turn: once for each of its tags.
func count_play(card: CardData) -> void:
	if card == null:
		return
	for tag in card.tags:
		tagged_plays_this_turn[tag] = int(tagged_plays_this_turn.get(tag, 0)) + 1

# `card` has been played this turn: the last Attack, if it is one.
func record_attack(card: CardData, target: Combatant, all_enemies: bool) -> void:
	if card == null or card.card_type != CardData.CardType.ATTACK:
		return
	last_attack = card
	last_attack_target = null if all_enemies else target
	last_attack_all = all_enemies

func clear_last_attack() -> void:
	last_attack = null
	last_attack_target = null
	last_attack_all = false

func is_critical() -> bool:
	return is_critical_at(hp)

# Whether `at_hp` is Critical for this fighter - `at_hp` rather than hp so
# a card face can ask about the HP it WILL have once its own costs are
# paid (see EffectContext.preview_hp_cost).
func is_critical_at(at_hp: int) -> bool:
	return critical_at(at_hp, max_hp, critical_fraction())

# The fraction of max HP this fighter is Critical at or below now: their
# own line, or the higher one a status raises it to for the fight (Status.
# raised_critical_fraction() - Gone Under). Every reading of Critical goes
# through here, so none keeps the old line.
func critical_fraction() -> float:
	return maxf(critical_hp_fraction, Status.raised_critical_fraction(statuses))

# The Critical rule itself, for any HP, max HP and fraction - static so a
# readout with no Combatant to ask (HPBar, on the field) reads the same
# line the fight does. Everything else goes through is_critical_at().
static func critical_at(at_hp: int, of_max_hp: int, fraction: float) -> bool:
	return float(at_hp) <= of_max_hp * fraction

# What `card` costs this fighter in Energy right now - the one reading of
# a card's cost the fight uses: affordability, the spend, the hand's fade
# and the face's number all ask here. CardData.cost itself never changes.
#
# Its base first (base_cost(): critical_cost while Critical), then
# House Key's free card, then a cost reduction (Leverage), then a
# cost replacement (Collateral) on what's left: a card the free card or a
# reduction already took below the replacement's threshold passes it by,
# so it keeps its charge. A covered card costs 0 Energy here and
# replaced_cost_hp() HP instead. The free card and the reduction are
# "your next card" discounts: a card that costs 0 takes neither and
# leaves both waiting (takes_next_card_discount()).
func energy_cost(card: CardData) -> int:
	if card == null:
		return 0
	if cost_replacement_for(card) != null:
		return 0
	return _reduced_cost(card)

# The HP `card` costs this fighter in place of its Energy right now - a
# cost replacement's (StatusData.replacement_hp_cost) when one covers the
# card, else 0. Paid before the card's effects (EffectResolver.resolve_
# card()); shown on the face's "-N HP" line.
func replaced_cost_hp(card: CardData) -> int:
	var replacement: Status = cost_replacement_for(card)
	return replacement.data.replacement_hp_cost if replacement != null else 0

# The cost replacement status that covers `card` right now, or null -
# judged on its Energy after every other modifier (the free card, a cost
# reduction).
func cost_replacement_for(card: CardData) -> Status:
	if card == null:
		return null
	return Status.cost_replacement(statuses, _reduced_cost(card))

# `card`'s Energy before any cost replacement: its base, then the free
# card, then every waiting cost reduction (Status.cost_reduction()),
# never below 0. A card whose base is 0 is 0 with neither.
func _reduced_cost(card: CardData) -> int:
	if not takes_next_card_discount(card):
		return maxi(base_cost(card), 0)
	var base: int = 0 if first_card_free else base_cost(card)
	return maxi(base - Status.cost_reduction(statuses), 0)

# `card`'s Energy before any modifier: its critical_cost while this
# fighter is Critical at the HP held now - Energy is paid before any HP
# the play costs - when it has one, else its printed cost.
func base_cost(card: CardData) -> int:
	if card.critical_cost >= 0 and is_critical():
		return card.critical_cost
	return card.cost

# Whether `card` is the one a "your next card" discount (the free card,
# a cost reduction) lands on and is spent by: any card whose base costs
# at least 1 Energy. A card at 0 - printed, or by its critical_cost
# while Critical - has nothing to discount and passes them by.
func takes_next_card_discount(card: CardData) -> bool:
	return card != null and base_cost(card) >= 1

# The Critical-entry edge, checked wherever Critical is (Status.resolve_
# critical_triggers(), after each action that can move HP). Out of
# Critical arms it; in Critical while armed fires it once: ordinary Block,
# through the same stance rule a card's Block obeys, and spent for the
# fight either way. Returns the Block gained.
func resolve_critical_entry() -> int:
	if critical_entry_block <= 0:
		return 0
	if not is_critical():
		critical_entry_armed = true
		return 0
	if not critical_entry_armed:
		return 0
	var amount: int = critical_entry_block
	critical_entry_block = 0
	critical_entry_armed = false
	if Stance.prevents_block_gain(stance):
		return 0
	block += amount
	RunLogger.block_gained(amount)
	entry_block_unreported += amount
	return amount
