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
# Whether this enemy stands between the Wanderer and the gate: the floor
# is cleared (RegionField.floor_cleared, the ExitGate opens) once no
# required enemy is left standing. False = an optional fight, there to be
# chosen or walked past.
@export var required: bool = true
# Entries sharing a non-empty id are one cluster: contact with any of
# them starts one fight with all of them (RegionField._battle_members_
# for()), and they step into one line for it (FieldEnemy.step_to()). The
# line runs through their authored positions, so lay a cluster out
# roughly as it should stand; their contact areas (contact_radius, 2 m)
# are the zone, so keep members within 2 x that of a neighbour or the
# zone has a hole. Empty (the default) = fights alone.
@export var group: StringName = &""
