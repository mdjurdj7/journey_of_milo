extends Resource
class_name EnemyData

# Trimmed hard from the old project's enemy_data.gd - name, max HP, a
# move list, and (since the dragonfly) which body to wear on the field.
# Escalation is back (the Wardling's); no charge/growth/escape/encounter-
# linked/mark fields - out of scope, see DESIGN.md. A FieldEnemy references one
# of these (field_enemy.gd's own enemy_data export).

@export var enemy_name: String = ""
# More than one, where the hover lines count them ("3 Nettles"); empty is
# enemy_name with an "s" (plural()).
@export var plural_name: String = ""
# One or two plain sentences: what it does and what it teaches. For the
# enemy export (tests/enemy_export.gd); nothing in a fight shows it.
@export_multiline var mechanic_summary: String = ""
@export var max_hp: int = 1

# enemy_name for `count` of them: plural_name (or enemy_name + "s") for
# any but one.
func named(count: int) -> String:
	if count == 1:
		return enemy_name
	return plural_name if not plural_name.is_empty() else enemy_name + "s"
@export var intents: Array[EnemyIntent] = []
# Opens every fight already under the sand, its loop's first DIG done
# before the first turn (EnemyTurn.pick_initial_intent()): its mounds up,
# its first turn the DIG's first move under, and the loop waiting on the
# move after the DIG. The Siltjaw. False = it opens on its loop's first.
@export var opens_dug_in: bool = false
# Opens every fight dormant (Combatant.dormant): no intent shown, no
# action taken - targeted and damaged as ever, its statuses ticking -
# until it is woken. With nothing in its pack able to wake it, it wakes
# as the next enemy turn begins (BattleController). False (every enemy
# by default) = it acts from the first turn.
@export var starts_dormant: bool = false:
	set(value):
		starts_dormant = value
		emit_changed()
# What its readout shows while it is dormant: this status's name in the
# status row, its description in the row's hover (BattleController.get_
# enemy_status_labels() / get_enemy_statuses()) - display only, never on
# the Combatant, gone the moment it wakes. Null: nothing shown.
@export var dormant_status: StatusData = null:
	set(value):
		dormant_status = value
		emit_changed()
# Statuses it holds from the first frame of every fight, applied as the
# fight starts (BattleController) - a passive, shown and revealed like
# any status (the Blackback's Fed). Empty (every enemy by default) = none.
@export var starting_statuses: Array[StatusData] = []
# The status it gains, one stack per Attack card played against it while
# an intent with counts_attack_cards is queued (EnemyTurn.take_attack_
# card()) - the Dunecur's Roused. Only those intents add its bonus and
# spend it; any other attack leaves it waiting (EnemyTurn.held_back()).
# Null (every enemy by default) = none.
@export var attack_card_status: StatusData = null
# The status it gains, turn_end_status_stacks at a time, at the end of
# each turn it acts - its move resolved, not lost to Stunned, a Deny, a
# pain turn or an interrupt, which pause it (EnemyTurn.take_turn()) - and
# keeps for the fight: the Dragonfly's Quickening, its attacks one more
# each turn. Up before its next intent is read, so that intent and the
# lethal warning already count it. Null (every enemy by default) = none.
@export var turn_end_status: StatusData = null
@export var turn_end_status_stacks: int = 1
# The sound of a card's hit landing on this creature (its shell, its
# hide), played by its FieldEnemy on the hit frame - takes dealt
# at random, never the same take twice running (SoundPool.next_random());
# one take is fine.
@export var contact_sounds: Array[AudioStream] = []
# Played instead of contact_sounds when the hit meets this creature's
# block - judged per hit as it lands, before the block is spent, whether
# the block takes all of it or the hit breaks through (BattleController.
# enemy_hit_blocked). Its own pool, picked the same way. Empty (every
# enemy by default) = contact_sounds always.
@export var armored_contact_sounds: Array[AudioStream] = []
# Each contact play's pitch scale is drawn from 1 +/- this, so repeated
# takes don't sound identical. Read by FieldEnemy at play time.
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.06:
	set(value):
		pitch_jitter = value
		emit_changed()
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

# The phase: the first time this enemy's HP falls below this fraction of
# its max (strictly below), it gains phase_status - once per fight, and
# nothing it does is cancelled (EnemyTurn.check_phase()). Judged where the
# pain line is. The Greyshelf off its rock. 0 (every enemy by default) or
# no status is none.
@export_range(0.0, 1.0, 0.01) var phase_hp_threshold: float = 0.0
@export var phase_status: StatusData = null

# A sound this enemy makes when it gains status_gained_sound_on in a
# fight (BattleController.enemy_status_gained - the Blackback turning
# Hungry): played once from its body (FieldEnemy.show_status()), never
# for the statuses a fight opens with. Null (every enemy by default) or
# no status = none.
@export var status_gained_sound: AudioStream = null
@export var status_gained_sound_on: StatusData = null

# Elite-tier content (the Wardling). A fight with one in it pays
# RegionField.elite_gold_multiplier on the floor's gold (rounded) and
# rolls its card reward at RewardPool's elite rarity rates (RegionField.
# _open_reward_screen()). Keepsakes and Glassbone are their own fields.
@export var is_elite: bool = false
# Said where it stood, in the world voice, as it dies (RegionField._on_
# enemy_defeated()). Empty = nothing.
@export var defeat_line: String = ""
# The defeat line held instead until the win's screens have closed and
# the field is live again, said once over the basking slab where the
# enemy lay - not as it dies, over the fight (the Greyshelf's, beside its
# empty crest rock; RegionField._say_pending_defeat_line()).
@export var defeat_line_after_rewards: bool = false
# What this enemy can leave as a keepsake - its own table, offered after
# a won fight's normal reward (RegionField._roll_keepsake_drop()). Null =
# none. An elite leaves armor instead (armor_table).
@export var keepsake_table: KeepsakeTable = null
# Glassbone this enemy leaves on a won fight, offered as its own TAKE line
# on the reward screen beside the gold and the card (RegionField._open_
# reward_screen()); left behind if the player walks on. 0 = none.
@export var glassbone_reward: int = 0
# A weapon this enemy leaves on every won fight (the Greyshelf: its Tail),
# offered after the normal reward and any keepsake, TAKE or LEAVE in
# place of the weapon carried (RegionField.open_weapon_offer()) - never
# while it is the one carried. Null = none.
@export var weapon_reward: WeaponData = null
# What this enemy leaves to wear - its own small table of worn pieces
# (TrinketData.slot WORN), one guaranteed per won fight, lying on the sand
# where it fell (RegionField, WorldArmor). Null = none.
@export var armor_table: KeepsakeTable = null
# The chance (0..1) that piece is the table's RARE one rather than a
# COMMON (KeepsakeTable.roll_by_rarity()).
@export_range(0.0, 1.0, 0.01) var armor_rare_chance: float = 0.22

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
# A painted albedo (tools/paint_texture.py, or the glb's own colour map)
# worn under the Wanderer's soft light, field/wanderer_painted.gdshader,
# in place of the glb's own material - so the body reads in his style.
# Empty = the glb's material, matte (FieldEnemy._build_model_material()).
@export_file("*.png", "*.jpg") var painted_albedo_path: String = "":
	set(value):
		painted_albedo_path = value
		emit_changed()
# Where a rope is tied to this body, glb units in the glb's own space -
# the Wardling's harness, which floor 3's HitchingPost ties its rope to
# (FieldEnemy.get_harness_point()). Unused by a body nothing is tied to.
@export var harness_point: Vector3 = Vector3.ZERO
# This body's share of the field's depth fog, in place of RegionField.
# enemy_fog_factor (see FieldEnemy.refresh_fog()): 0 = never fogged, 1 =
# fogged as the scenery is. -1 = use the field's.
@export_range(-1.0, 1.0, 0.01) var fog_factor_override: float = -1.0:
	set(value):
		fog_factor_override = value
		emit_changed()
# Metres the body stands clear of the sand in the field, applied after
# its AABB grounding - legs the mesh doesn't carry (the dragonfly's
# 0.12). Its contact shadow stays on the sand. 0 = the mesh's own feet.
# Negative = sunk that far under the sand (the Siltjaw, buried in the
# field); a fight lifts it to battle_hover_m when the frame settles.
@export var rest_height_m: float = 0.0
# A buried body's tell in the field (FieldEnemy._trickle()): every
# mound_trickle_interval_min_s to _max_s seconds a little silt spills off
# its mound near the crest - mound_trickle_particles grains, each alive
# mound_trickle_lifetime_s, thrown up at up to mound_trickle_velocity m/s
# within mound_trickle_spread_degrees of straight up, in the sand's colour
# times mound_trickle_tint, from within mound_trickle_reach of the crest
# (a fraction of the mound's half-width and length). Only the mound over
# a body does it, so an empty slot's leftover signs lie still. A max of 0
# = no trickle; nothing without a negative rest height (no mound).
@export var mound_trickle_interval_min_s: float = 0.0:
	set(value):
		mound_trickle_interval_min_s = maxf(value, 0.0)
		emit_changed()
@export var mound_trickle_interval_max_s: float = 0.0:
	set(value):
		mound_trickle_interval_max_s = maxf(value, 0.0)
		emit_changed()
@export var mound_trickle_particles: int = 5:
	set(value):
		mound_trickle_particles = maxi(value, 1)
		emit_changed()
@export var mound_trickle_lifetime_s: float = 1.0:
	set(value):
		mound_trickle_lifetime_s = maxf(value, 0.05)
		emit_changed()
@export var mound_trickle_velocity: float = 0.4:
	set(value):
		mound_trickle_velocity = value
		emit_changed()
@export var mound_trickle_spread_degrees: float = 30.0:
	set(value):
		mound_trickle_spread_degrees = value
		emit_changed()
@export var mound_trickle_tint: float = 0.75:
	set(value):
		mound_trickle_tint = value
		emit_changed()
@export_range(0.0, 1.0, 0.01) var mound_trickle_reach: float = 0.35:
	set(value):
		mound_trickle_reach = value
		emit_changed()
# Metres the model is set into the ground below its AABB feet, in the
# field and in a fight alike - still seen, never buried (no mound, unlike
# a negative rest height): the Greyshelf's belly on its rock. 0 = the
# mesh's own feet.
@export var sink_m: float = 0.0
# Its own look for the pool under it (ContactShadow) - empty for the
# shared field/contact_shadow.tres every figure wears.
@export var contact_shadow: ContactShadowData = null:
	set(value):
		contact_shadow = value
		emit_changed()
# Metres above the sand the body hovers at through a fight, from the
# moment the battle frame settles (FieldEnemy.enter_battle_hover()). 0 =
# it stays where it stands (the Sputter) - or, under a negative rest
# height, surfaces onto the sand (the Siltjaw). Only a body with this
# above 0 flies: bobs, beats its wings.
@export var battle_hover_m: float = 0.0
# The attack lunge's forward lean, onto FieldEnemy.attack_lean_degrees/
# _pivot_forward: the model tips this many degrees toward its target as
# it lunges and eases back with the return, about a pivot on its base
# attack_lean_pivot_forward of the way from its centre (0) to its front
# edge toward the target (1) - the head drops and reaches, the back lifts.
# A lunge that slides a low body (the adder's coil) reads as a strike.
# The body, and the readouts on it, only move. 0 = no lean.
@export_range(0.0, 60.0) var attack_lean_degrees: float = 0.0
@export_range(0.0, 1.0) var attack_lean_pivot_forward: float = 1.0
# In a fight, how far its model turns toward the camera on top of facing
# the Wanderer, onto FieldEnemy.battle_camera_turn_degrees - the mirror of
# his own turn, so the two still read as facing each other in a 3/4 view.
# 0 keeps it exactly side-on.
@export var battle_camera_turn_degrees: float = 20.0
# Radius of the sphere the Wanderer has to walk into to start this
# fight, metres, onto FieldEnemy.contact_radius. 2.0 is every standing
# enemy's; a roaming one wants its own body's size, so drifting past him
# never reaches out and takes him.
@export var contact_radius_m: float = 2.0
# Metres from the member before it to this one when its cluster forms
# its fighting line (RegionField._place_cluster_line()), in place of
# RegionField.cluster_member_gap - a long body wants more room than the
# shared gap gives. -1 = the shared gap.
@export var cluster_gap_m: float = -1.0
