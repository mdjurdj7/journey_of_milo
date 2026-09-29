extends Resource
class_name EnemyData

# Trimmed hard from the old project's enemy_data.gd - name, max HP, a
# move list, and (since the dragonfly) which body to wear on the field.
# Escalation is back (the Wardling's); no charge/growth/escape/encounter-
# linked/mark fields - out of scope, see DESIGN.md. A FieldEnemy references one
# of these (field_enemy.gd's own enemy_data export).

@export var enemy_name: String = ""
@export var max_hp: int = 1
@export var intents: Array[EnemyIntent] = []
# The sound of a card's hit landing on this creature (its shell, its
# hide), played by its FieldEnemy on the hit frame - takes dealt
# round-robin (see SoundPool); one take is fine.
@export var contact_sounds: Array[AudioStream] = []
# The enemy's attack pattern. Fixed enemies step through this in order,
# looping; erratic ones (see below) pick freely each turn instead.

@export var erratic_intent_selection: bool = false
# False (every enemy by default): intents advance in a fixed loop. True:
# a fresh independent weighted pick every turn, repeats allowed (subject
# to each intent's own no_immediate_repeat/turn_one_locked) - see
# enemy_turn.gd.

# Escalation: an ATTACK's value times the multiplier of the stage its turn
# falls in - stage (turn - 1) / escalation_stage_length, the last one held
# once the fight outruns them - rounded (EnemyTurn.intent_value()). Before
# any status modifier, and the same call feeds the intent preview, so the
# number shown is the number that lands. Empty (every enemy by default)
# is no escalation.
@export var escalation_multipliers: Array[float] = []
@export var escalation_stage_length: int = 2

# The pain turn: the first time this enemy's HP falls below this fraction
# of its max (strictly below), its queued action is cancelled - it does
# nothing that turn - once per fight (EnemyTurn.check_pain_turn()). The
# loop and the turn count carry on; escalation isn't reset. The line is
# said near it and the sound played as it happens. 0 (every enemy by
# default) is none.
@export_range(0.0, 1.0, 0.01) var pain_turn_hp_threshold: float = 0.0
@export var pain_turn_line: String = ""
@export var pain_turn_sound: AudioStream = null

# Elite-tier content (the Wardling). A tag only for now - nothing rolls or
# rewards on it yet.
@export var is_elite: bool = false
# Said where it stood, in the world voice, as it dies (RegionField._on_
# enemy_defeated()). Empty = nothing.
@export var defeat_line: String = ""
# What this enemy can leave as a keepsake - its own table, offered after
# a won fight's normal reward (RegionField._roll_keepsake_drop()). Null =
# none, which is every enemy but the Wardling today.
@export var keepsake_table: KeepsakeTable = null

# The field body. RegionField copies these onto the FieldEnemy it
# spawns for this data (RegionField._spawn_floor_enemies()), the same
# way it hands over `required`/`group`; FieldEnemy._spawn_model() does
# the rest (AABB grounding, the shared matte material). Every default
# equals what field_enemy.tscn carried before these existed, so a
# resource that sets none of them - the Sputter - looks exactly as it
# did.
@export_group("Field Body")
# The glb, loaded at spawn. Empty = FieldEnemy's own default model.
@export_file("*.glb", "*.gltf", "*.fbx", "*.tscn") var model_scene_path: String = ""
# The glb's units to metres - a Meshy export is what it is; measure the
# body and set this (the dragonfly: 1.899 units long -> 0.55 m).
@export var model_scale: float = 1.0
# The glb's own facing to the game's -Z forward. Meshy/Blender exports
# face +Z, so 180 for both bodies so far.
@export var model_yaw_offset_degrees: float = 180.0
# An optional scene FieldEnemy instantiates under the model root after
# the material pass (the dragonfly's wings, DragonflyWings) - it keeps its
# own materials but rides the body's grounding, yaw, scale and settle.
# Empty = nothing attached.
@export_file("*.tscn") var attachment_scene_path: String = ""
# Metres the body stands clear of the sand in the field, applied after
# its AABB grounding - legs the mesh doesn't carry (the dragonfly's
# 0.12). Its contact shadow stays on the sand. 0 = the mesh's own feet.
# Negative = sunk that far under the sand (the Siltjaw, buried in the
# field); a fight lifts it to battle_hover_m when the frame settles.
@export var rest_height_m: float = 0.0
# Metres above the sand the body hovers at through a fight, from the
# moment the battle frame settles (FieldEnemy.enter_battle_hover()). 0 =
# it stays where it stands (the Sputter) - or, under a negative rest
# height, surfaces onto the sand (the Siltjaw). Only a body with this
# above 0 flies: bobs, beats its wings.
@export var battle_hover_m: float = 0.0
# Radius of the sphere the Wanderer has to walk into to start this
# fight, metres, onto FieldEnemy.contact_radius. 2.0 is every standing
# enemy's; a roaming one wants its own body's size, so drifting past him
# never reaches out and takes him.
@export var contact_radius_m: float = 2.0
# How it behaves on the field before a fight. DEFAULT: stands as placed.
# WATCHER: stands as placed until the Wanderer comes within notice_radius_
# m, then turns to face him once, over notice_turn_seconds (eased), and
# holds - no other motion, no following, no second turn.
enum FieldBehaviour { DEFAULT, WATCHER }
@export var field_behaviour: FieldBehaviour = FieldBehaviour.DEFAULT
@export var notice_radius_m: float = 8.0
@export var notice_turn_seconds: float = 2.0
