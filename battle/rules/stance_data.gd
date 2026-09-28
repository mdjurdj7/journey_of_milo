extends Resource
class_name StanceData

# A stance the player holds for a fight: a standing bargain that changes
# what playing a card costs and does. Static definition only - which
# stance is up, how many stacks it has and how long it lasts is per-fight
# state on the Combatant (see stance.gd), the same split StatusData and
# Status already use.
#
# Deliberately NOT a StatusData. A status modifies a number every time
# damage resolves (see Status.apply_modifiers()); a stance fires on an
# EVENT - playing an Attack - and charges for it. Expressed as a status,
# Self-Eater's bonus would land on every damage the player dealt (a Toll
# spend, a reflect) and its HP price would never be charged at all.
#
# One stance is active at a time: playing a different one replaces it,
# every stack gone, at one stack; playing the same one again adds a stack
# - every stance, Last Resort included. A played stance card leaves the
# deck's rotation for the rest of the fight (BattleController._on_play_
# animation_finished()), so a stack is one physical copy and a reshuffle
# can't farm more. Every value below is PER STACK and scales linearly -
# two stacks of Self-Eater is lose 4, deal 6 more; two of Last Resort is
# 12 more while Critical (a flag like prevents_block_gain doesn't scale). A stance that needs a different curve needs a field for it, not a
# reinterpretation of these.

@export var id: String = ""
@export var display_name: String = ""
# Rules text in card voice, one short sentence, shown when the Wanderer's
# battle readout is hovered (Stance.describe()). A template, filled from
# the stance held - the same filling statuses use (Status.fill_template()):
#   {bonus}    attack_damage_bonus × stacks
#   {hp_loss}  attack_hp_loss × stacks
#   {stacks}   stacks held               {turns}  turns left
#   {s}        "s" unless the count token before it is 1
@export_multiline var description: String = ""

# What playing an ATTACK costs and gives, per stack. The HP loss is
# self-inflicted: it bypasses block and absorb, it accrues Toll, and it
# opens no Grace (Grace only ever opens on an enemy's hit - see
# EnemyTurn.open_grace()). Both are 0 on a stance that does something
# else entirely, which is the "empty means unaffected" idiom the rest of
# the rules layer uses.
@export var attack_hp_loss: int = 0
@export var attack_damage_bonus: int = 0

# How many of the player's turns a stack survives. 0 means the rest of
# the combat, which is the common case and the default - a stance is
# supposed to be a commitment, not a buff. A new stack refreshes the
# whole stance's timer rather than tracking its own.
@export var duration_turns: int = 0

# The attack bonus only while the player is Critical (Last Resort) - off
# the moment HP climbs back over the line, on again when it drops. Read
# when the attack lands (see AttackBonus). The HP loss above is never
# gated: a price is a price.
@export var bonus_requires_critical: bool = false

# While held, the player gains no Block from anything - every player
# Block gain goes through EffectContext.gain_block(), which asks. Block
# already up when the stance is taken stays.
@export var prevents_block_gain: bool = false
