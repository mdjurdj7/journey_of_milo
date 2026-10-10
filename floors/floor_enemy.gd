extends Resource
class_name FloorEnemy

# One member of an encounter - see EncounterOption.members. RegionField
# instantiates field_enemy.tscn for each member of each slot's chosen
# option (RegionField._spawn_floor_enemies()), hands it the rules-side
# EnemyData and puts it here. Whether it gates the exit is its slot's
# (EncounterSlot.required); which cluster it fights in is its option's
# (all of an option's members fight together).

@export var enemy_data: EnemyData = null
# XZ offset from the slot's anchor, in the slot's frame (x = X, y = Z;
# EncounterSlot.to_floor()). Y is never authored - a FieldEnemy grounds
# itself on the relief.
@export var position: Vector2 = Vector2.ZERO
# The body's yaw in degrees, on top of the slot's yaw - rotation.y.
# Authored outright rather than derived from "seaward": the crab beside
# the pool faces where it faces.
@export var yaw_degrees: float = 0.0
# Index into the same option's props of a prop this body faces - the
# Wardling and his hitching post. Set: the yaw is toward that prop, with
# yaw_degrees on top, and after an escape the body turns back to it
# (FieldEnemy.set_prop_facing()). -1 = yaw_degrees alone, as authored.
@export var face_prop_index: int = -1
# How this member's fight offers its cards. ROLLED: each slot rolls a
# rarity tier at RewardPool's rates (the elite rates with an elite in the
# fight - EnemyData.is_elite). TOP_TIER_FIRST: the highest tier first,
# filled downward only when it runs dry (RewardPool.roll_top_tier()) -
# the region-end fight, floor 5's Greyshelf. Cards only: its gold is the
# floor's. Appended values only - the .tres stores the integer.
enum CardReward { ROLLED, TOP_TIER_FIRST }
@export var card_reward: CardReward = CardReward.ROLLED
# The member a cluster's line is built from, whichever way it is
# approached: the Wanderer steps up to it, it keeps its spot and the rest
# line up beyond it (RegionField._battle_members_for()). Without one the
# member nearest the Wanderer at contact anchors. Floor 2's crab anchors
# its Sputter, so the stance never lands up the shelf's rise behind it.
# The line runs through the members' authored positions, so lay an
# option out roughly as it should stand; their contact areas
# (contact_radius, 2 m) are the zone, so keep members within 2 x that of
# a neighbour or the zone has a hole.
@export var anchor: bool = false
# An encounter's rule for an enemy that picks its moves at random
# (EnemyData.erratic_intent_selection): while another enemy in its fight
# has the intent named excluded_while_packmate_intent queued, this one
# never has the intent named excluded_intent queued - it draws again
# from the rest, its usual rules intact (EnemyTurn.exclude_queued()). On
# other turns its draw is unchanged. Either empty (the default) = no rule.
# Floor 2's Sputter beside the Underfoot: no Scissor on a Sting turn.
@export var excluded_intent: String = ""
@export var excluded_while_packmate_intent: String = ""
