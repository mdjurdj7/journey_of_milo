extends Resource
class_name EnemyIntent

# ATTACK/DEFEND, and BURROW for the Siltjaw - the old project's IDLE/
# WIND_UP/GROWTH/CHARGE_ATTACK/MARK types all belonged to mechanics this
# pass explicitly drops (wind-up telegraphs, growth tracks, boss charge,
# mark attacks - see DESIGN.md's own parked-items note). Extend this enum
# the same way the old project did, when a real enemy needs one of them
# back - BUFF/DEBUFF (a status on self / on the Wanderer) are the expected
# next two; the BattleIntent display draws only what exists here.
#
# BURROW: while this is the enemy's queued intent it is under the sand -
# it can't be targeted and takes no damage (Combatant.buried, kept in
# step by EnemyTurn) - and its turn does nothing; it surfaces at the end
# of it. Reached as an ATTACK's on_interrupt (below), not from the loop.
#
# HEAL_ALLY: no damage - each living packmate (FieldEnemy.group) heals
# `value` HP, capped at its max (BattleController._heal_packmates()). A
# pack move, like a simultaneous one: alone, the enemy steps past it
# (EnemyTurn.leave_pack()). The Nipper's Forage. Appended: an inserted
# value would rewrite every .tres that stores one of these as an integer.
#
# WATCH: the turn does nothing at all - no damage, no block - and the
# display shows its glyph alone, an open eye. No enemy uses it now (the
# Greyshelf's Flick was one).
#
# SETTLE: the turn does nothing - no damage, no block - and the enemy
# stays targetable throughout (unlike a BURROW); what changes is what it
# carries next (status_while_queued, below). The display shows its glyph
# alone, a short down-arrow settling onto a ground line. The Underfoot's
# Rebury.
#
# COIL: as SETTLE - nothing happens, it stays targetable, and what it holds
# next comes with the intent queued after it (the Bite's status_while_
# queued: Coiled). The display shows its glyph alone, a coil. The Adder's
# Coil.
enum IntentType { ATTACK, DEFEND, BURROW, HEAL_ALLY, WATCH, SETTLE, COIL }

# The move's name (the Dunecur's Rush) - for the enemy export (tests/
# enemy_export.gd) and the design docs; nothing in a fight shows it yet.
@export var intent_name: String = ""
@export var type: IntentType = IntentType.ATTACK
@export var value: int = 0
# Damage dealt PER HIT if ATTACK, block gained if DEFEND, HP each living
# packmate heals if HEAL_ALLY.

@export var hits: int = 1
# ATTACK only: how many separate hits of `value` this intent lands in one
# turn - each one goes through the player's block/absorb on its own, and
# one-shot statuses (StatusData.clears_on_trigger) are consumed by the
# first. BattleIntent shows this as "M×N" (damage × hits). A multi-hit intent gains a
# status's bonus_hits (EnemyTurn.hit_count()).

@export var erratic_weight: float = 1.0
# Only consulted when EnemyData.erratic_intent_selection is true - this
# intent's relative likelihood among candidates (double the weight,
# double the odds - not a percentage on its own).

@export var turn_one_locked: bool = false
# Excludes this intent from an erratic enemy's very first pick only -
# from turn two on it's a fully normal candidate again.

@export var no_immediate_repeat: bool = false
# Excludes this intent from being picked as the very next turn's free
# choice if it was ALSO the intent picked last turn.

@export var simultaneous: bool = false
# A pack's shared move (the dragonflies' Swarm): when every living member
# of a fight's cluster is queued on an intent with this set, they act as
# one - lunges started together, one wait, every hit landed in the same
# beat (BattleController._run_enemy_turn()). The rules are unchanged:
# each member's take_turn() runs on its own, so Grace still sees three
# separate hits. False = the ordinary one-after-another turn.

@export var interrupt_threshold: int = 0
# ATTACK only: damage the player has to deal this enemy during the turn
# this intent is queued for (Combatant.damage_taken_this_turn) for it to
# be interrupted - checked when the enemy's turn comes, so everything
# played that turn counts and the enemy is still hittable after the
# number is reached. Interrupted, the attack doesn't land and on_interrupt
# is queued in its place. BattleIntent shows it beside the damage,
# counting down. 0 = can't be interrupted (every enemy but the Siltjaw).

@export var on_interrupt: EnemyIntent = null
# What the enemy does on its NEXT turn when this one is interrupted - an
# interjection outside the intents loop (Combatant.interjected_intent),
# which carries on where it was once this has resolved. The Siltjaw's is
# a BURROW. Null = the interrupted turn is simply lost.

@export var rear_while_queued: bool = false

# The status its enemy holds for exactly as long as this intent is the
# queued one - applied when it is queued, removed when another is (Status.
# apply_to / remove_from, kept in step by EnemyTurn with the BURROW's
# burial). The player's turn always faces the queued intent, so a move
# lost to Denied or a pain turn still hands over to the next one's
# status. The Underfoot: Covered while its Sting is queued, Exposed
# while its Rebury is. Null = none.
@export var status_while_queued: StatusData = null

@export var counts_attack_cards: bool = false
# While this intent is queued, each Attack card the player plays against
# the enemy - once per card, a multi-target Attack included when it's
# among the targets - adds a stack of its EnemyData.attack_card_status
# (BattleController._resolve_play(), EnemyTurn.take_attack_card()). The
# Dunecur's Rush, which Roused feeds. False for every other.
# The body rears for as long as this intent is queued and the enemy is
# above the sand - the front up off it, held, dropping back once the
# intent has resolved or been interrupted (BattleController._pose_for_
# intent(), FieldEnemy.set_rearing()). Only a body whose attachment can
# rear (RearPose) shows it. The Siltjaw's charge; false for every other.

# A status this ATTACK puts on the player, applied_amount of it (the
# Adder's Bite: Venom 3), once the attack has resolved - every time, even
# when Block took all of its damage (EnemyTurn.take_turn(), Status.apply_
# amount()). Null = none.
@export var applies_to_player: StatusData = null
@export var applied_amount: int = 0
