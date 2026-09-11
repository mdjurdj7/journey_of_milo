extends Resource
class_name EncounterData
# An AUTHORED multi-enemy group (see DESIGN.md's Bestiary: Authored
# encounters) - same "plain data container, define once as a .tres" shape
# as EnemyData/CardData. Where EnemyPool.pick_random() rolls one enemy
# independently, EncounterPool.pick_random() rolls one of THESE - a
# deliberate combination composed for a specific tactical reason, not
# several unrelated enemy rolls that happened to land in the same fight.

@export var encounter_name: String = ""
# For debugging/print - not shown to the player anywhere yet (no UI
# currently names a fight going in; only each enemy's own NameLabel
# intro once battle starts - see enemy.gd's "Name introduction" note).

@export var enemies: Array[EnemyData] = []
# 1-3 entries, battle-ready as-is - battle.gd's _spawn_enemies() reads
# this the same way it reads any Array[EnemyData], no per-encounter code
# needed there. The SAME EnemyData resource can appear more than once
# (see twin_glasswings.tres) - nothing at runtime mutates an EnemyData
# (per-fight state like current_intent_index lives on each
# EnemyCombatant, not here - see battle.gd's EnemyCombatant), so two
# combatants safely sharing one Resource object is fine, not a bug
# waiting to happen.

@export var pool_weight: float = 1.0
# Same weighted-pick idea as EnemyData.pool_weight, but for
# EncounterPool.pick_random() - tune an encounter rarer by lowering
# this, same as wardling.tres does within EnemyPool.

@export var field_preview_enemies: Array[EnemyData] = []
# What the FIELD blob actually renders (see field_blob.gd's field_
# display_enemies) - separate from `enemies` above, which stays the real
# battle roster no matter what. Empty (Twin Glasswings, Wardling Solo -
# every encounter before Mushroom Patch) means "preview = enemies,
# exactly like before this field existed" - see field_preview() below.
# Non-empty (Mushroom Patch: one entry) lets a field icon simplify a
# roster down to a single representative silhouette without touching how
# many actually spawn once the fight starts - the field and the fight
# are allowed to diverge here on purpose, unlike the ordinary single-
# enemy blob's own ironclad "what you see is what you fight" promise
# (see field_blob.gd's own enemy_data doc), because this is about
# reading as ONE encounter at a glance, not concealing what's inside it.
# 1-3 entries if ever set to more than one - no different a shape from
# `enemies` itself, just conceptually "the icon," not "the roster."

# The one place "preview or real roster" gets decided - field_room.gd
# and room_state.gd's own field-width math both call this instead of
# reading either array directly, so there's exactly one fallback rule to
# ever change.
func field_preview() -> Array[EnemyData]:
	return field_preview_enemies if not field_preview_enemies.is_empty() else enemies
