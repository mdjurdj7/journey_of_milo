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
# playing the same one again adds a stack. Every value below is PER
# STACK and scales linearly - two stacks of Self-Eater is lose 4, deal 6
# more. A stance that needs a different curve needs a field for it, not a
# reinterpretation of these.

@export var id: String = ""
@export var display_name: String = ""
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
