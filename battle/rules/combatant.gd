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
# Grace: HP an enemy took that this player can still take back, and how
# many of their turns are left to do it in. Per FIGHT, not per run - a
# Combatant is rebuilt by BattleController.setup() every battle, so
# leaving or winning a fight discards any open Grace with nothing to
# clear. See CharacterData's own Grace doc for the rule.
var grace: int = 0
var grace_turns_left: int = 0
# Defaults only - BattleController.setup() overwrites all three from
# RunState.character (the run's own CharacterData) the instant a
# Combatant is created. False on every enemy Combatant, which is what
# keeps Grace the Wanderer's alone.
var has_grace: bool = false
var grace_cap_mode: int = CharacterData.GraceCapMode.LARGEST_HIT
var grace_window_turns: int = 1
var took_damage_this_turn: bool = false
var took_damage_last_turn: bool = false
# Critical: HP at or below this fraction of max HP. A default only, like
# the Grace fields above - BattleController.setup() copies CharacterData.
# critical_hp_fraction over it. Read through is_critical_at(), never
# compared against hp directly, so the rule lives in one place.
var critical_hp_fraction: float = 0.3
# Once-per-combat statuses that have fired this fight (StatusData.once_
# per_combat) - what keeps a second copy of the card from re-arming one.
# Per fight, like everything else here.
var spent_statuses: Array[StatusData] = []
# Drain a counter (The Return) has handed over and nothing has resolved
# yet - set here, where a loss is counted but no enemy is in reach, and
# spent by EffectContext.resolve_pending_drain() right after the loss.
var pending_drain: int = 0

# --- Enemy-only ---
#
# Left at its default -1 for the player Combatant - see enemy_turn.gd.
var current_intent_index: int = -1
# An interrupted intent's on_interrupt, queued in front of the loop for
# one turn (see EnemyIntent.on_interrupt) - EnemyTurn.current_intent()
# returns it while it's set. Null = the loop's own intent.
var interjected_intent: EnemyIntent = null
# Under the sand: the queued intent is a BURROW. Can't be targeted, takes
# no damage (DamagePipeline.resolve()). Kept in step with the queued
# intent by EnemyTurn - nothing else writes it.
var buried: bool = false
# HP damage taken since the player's turn began - what an intent's
# interrupt_threshold is measured against. Counted by DamagePipeline.
# resolve(), reset by BattleController._start_player_turn().
var damage_taken_this_turn: int = 0
# No living packmate left in this fight (the last of its FieldEnemy.group,
# or never one): a simultaneous intent is a pack's move, so EnemyTurn
# steps past it from here on - see EnemyTurn.leave_pack(). Set by
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

func _init(starting_hp: int = 1) -> void:
	hp = starting_hp
	max_hp = starting_hp

# HP just lost to this fighter's own effect - a card's self-damage, a
# stance's price, a status tick: the Toll it accrues, 1 per HP, plus any
# status that pays extra for it (Status.take_self_loss_toll_bonus()).
# Every self-inflicted loss comes through here; an enemy's hit never
# does, which is the whole of the rule that Toll is self-inflicted - and
# of what a self-loss counter counts, once per call (Status.count_self_
# loss()).
func gain_self_loss_toll(lost: int) -> void:
	if lost <= 0:
		return
	toll += lost + Status.take_self_loss_toll_bonus(statuses)
	pending_drain += Status.count_self_loss(statuses)

func is_critical() -> bool:
	return is_critical_at(hp)

# Whether `at_hp` is Critical for this fighter - `at_hp` rather than hp so
# a card face can ask about the HP it WILL have once its own costs are
# paid (see EffectContext.preview_hp_cost).
func is_critical_at(at_hp: int) -> bool:
	return critical_at(at_hp, max_hp, critical_hp_fraction)

# The Critical rule itself, for any HP, max HP and fraction - static so a
# readout with no Combatant to ask (HPBar, on the field) reads the same
# line the fight does. Everything else goes through is_critical_at().
static func critical_at(at_hp: int, of_max_hp: int, fraction: float) -> bool:
	return float(at_hp) <= of_max_hp * fraction

# What `card` costs this fighter in Energy right now - the one reading of
# a card's cost the fight uses: affordability, the spend, the hand's fade
# and the face's number all ask here. CardData.cost itself never changes.
func energy_cost(card: CardData) -> int:
	if card == null:
		return 0
	return card.cost
