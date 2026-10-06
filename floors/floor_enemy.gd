extends Resource
class_name FloorEnemy

# One enemy placed on a floor - see FloorData.enemies. RegionField
# instantiates field_enemy.tscn for each of these (RegionField._spawn_
# floor_enemies()), hands it the rules-side EnemyData and puts it here.
# The Sputter facts (enemy_id, model_yaw_offset) live on field_enemy.tscn's
# own defaults, not here - only one enemy type exists in the field today.

@export var enemy_data: EnemyData = null
# World XZ offset from the floor's spawn (x = X, y = Z), so the tutorial
# floor's positions read exactly as its old scene transforms did (its
# spawn is the origin). Y is never authored - a FieldEnemy grounds itself
# on the relief.
@export var position: Vector2 = Vector2.ZERO
# The body's yaw in degrees, the same rotation.y the scene used to carry.
# Authored outright rather than derived from "seaward": the crab beside
# the pool faces where it faces.
@export var yaw_degrees: float = 0.0
# Index into the same floor's props of a prop this body faces - the
# Wardling and his hitching post. Set: the yaw is toward that prop, with
# yaw_degrees on top, and after an escape the body turns back to it
# (FieldEnemy.set_prop_facing()). -1 = yaw_degrees alone, as authored.
@export var face_prop_index: int = -1
# Whether this enemy stands between the Wanderer and the gate: the floor
# is cleared (RegionField.floor_cleared, the ExitGate opens) once no
# required enemy is left standing. False = an optional fight, there to be
# chosen or walked past.
@export var required: bool = true
# This placement's fight rolls its card reward at the elite rarity rates
# (RewardPool's Elite rarity rates) though its enemy isn't elite - and
# only that: no elite gold. Floor 5's region-end placeholder, until the
# region-end fight exists. A fight with an elite in it (EnemyData.
# is_elite) rolls them anyway. False = the enemy decides.
@export var elite_card_rates: bool = false
# Entries sharing a non-empty id are one cluster: contact with any of
# them starts one fight with all of them (RegionField._battle_members_
# for()), and they step into one line for it (FieldEnemy.step_to()). The
# line runs through their authored positions, so lay a cluster out
# roughly as it should stand; their contact areas (contact_radius, 2 m)
# are the zone, so keep members within 2 x that of a neighbour or the
# zone has a hole. Empty (the default) = fights alone.
@export var group: StringName = &""
# The member a cluster's line is built from, whichever way it is
# approached: the Wanderer steps up to it, it keeps its spot and the rest
# line up beyond it (RegionField._battle_members_for()). Without one the
# member nearest the Wanderer at contact anchors. Floor 2's crab anchors
# its dragonfly, so the stance never lands up the shelf's rise behind it.
@export var anchor: bool = false
