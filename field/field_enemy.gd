extends CharacterBody3D
class_name FieldEnemy

signal contacted(enemy: FieldEnemy)
# Its death has played out (settle_and_free()) - sent the moment before
# the node is freed. The fight it died in waits on the last one's before
# the win (BattleController._maybe_win()).
signal death_finished()

# The body worn when enemy_data names none (EnemyData.model_scene_path
# empty) - see model_scene_path below.
const DEFAULT_MODEL_SCENE_PATH := "res://assets/models/enemies/Sputter/Sputter.glb"
const ENEMY_STATUS_SCENE_PATH := "res://battle/enemy_status.tscn"
const FOG_SHADER_PATH := "res://field/enemy_fog.gdshader"
const PAINTED_SHADER_PATH := "res://field/wanderer_painted.gdshader"

@export var enemy_id: StringName = &"enemy"
@export var enemy_data: EnemyData
# The rules-side stats/move list battle_controller.gd builds this fight's
# Combatant from (see EnemyTurn) - FieldEnemy itself stays rules-ignorant,
# just a reference plus the field-visual/contact concerns below.
@export var contact_radius: float = 2.0
# Fallback only, for a model whose mesh ships with no material of its own
# to inherit (see _build_model_material()) - Sputter.glb carries its own
# real textured material, so this doesn't drive its look today the way it
# drove the old untextured placeholder's.
@export var model_color: Color = Color(0.2, 0.22, 0.25, 1)
# Which glb this body is, its units-to-metres and its facing - set from
# EnemyData's Field Body group by RegionField at spawn (like required/
# group below), or left at this scene's own values for an enemy placed
# by hand. Empty path = DEFAULT_MODEL_SCENE_PATH.
@export_file("*.glb", "*.gltf", "*.fbx", "*.tscn") var model_scene_path: String = ""
@export var model_scale: float = 1.0
@export var model_yaw_offset: float = 0.0
# An optional scene instantiated under the model root AFTER the material
# pass (the dragonfly's wings, DragonflyWings) - EnemyData.attachment_
# scene_path, copied the same way. It keeps its own materials, rides the
# model's grounding/yaw/scale/settle, and if it offers get_tint_
# materials() those lighten and flash with the body's. Empty = none.
@export_file("*.tscn") var attachment_scene_path: String = ""
# EnemyData.painted_albedo_path, copied the same way: set, the body wears
# this texture under wanderer_painted.gdshader (see _build_painted_
# material()). Live: an edit swaps the texture on a painted body.
@export_file("*.png", "*.jpg") var painted_albedo_path: String = "":
	set(value):
		painted_albedo_path = value
		if _model_material is ShaderMaterial and not value.is_empty():
			(_model_material as ShaderMaterial).set_shader_parameter("albedo_texture", load(value) as Texture2D)
@export var model_ground_offset: float = 0.0
# FloorEnemy.height_offset_m, copied at spawn: metres the BODY stands over
# the sand, at any XZ - its feet, contact shadow and contact area, and
# the camera's feet test, all with it - for a body set on something the
# relief doesn't draw (floor 4's Adder on its basking slab). 0 = on the
# sand.
@export var height_offset: float = 0.0:
	set(value):
		height_offset = value
		_ground_to_relief()
# FloorEnemy.stance_gap_m and holds_facing, copied at spawn - read at
# contact (RegionField._battle_gap_for(), _on_enemy_contacted()).
@export var stance_gap: float = -1.0
@export var holds_facing: bool = false
# FloorEnemy.battle_frame_screen, copied at spawn - read by CameraRig's
# battle fit every frame.
@export var battle_frame_screen: Vector2 = Vector2.ZERO
# EnemyData.harness_point, copied the same way: where a rope is tied to
# this body, glb units (see get_harness_point()).
@export var harness_point: Vector3 = Vector3.ZERO
# Off for an enemy placed from FloorData (RegionField._spawn_floor_
# enemies()), whose yaw is authored outright - the crab beside the pool
# faces where it faces.
@export var face_shore_at_spawn: bool = true
# EncounterSlot.required, mirrored here at spawn so RegionField can read
# it off the "enemies" group when it decides whether the floor is cleared
# (see RegionField._required_enemy_remains()). True for an enemy this
# scene is placed by hand, same as the data default.
@export var required: bool = true
# The cluster it fights in: its slot's id when its option has more than
# one member, else empty (fights alone) - set at spawn. RegionField reads
# it off the "enemies" group to find this enemy's cluster on contact.
@export var group: StringName = &""
# FloorEnemy.anchor, mirrored the same way - read at contact.
@export var anchor: bool = false
# FloorEnemy.excluded_intent / excluded_while_packmate_intent, mirrored
# the same way - read through the fight (BattleController).
@export var excluded_intent: String = ""
@export var excluded_while_packmate_intent: String = ""
# FloorEnemy.card_reward, mirrored the same way - read as the fight
# starts (RegionField).
@export var card_reward: FloorEnemy.CardReward = FloorEnemy.CardReward.ROLLED
# Where this enemy is in its floor's spawn order (slot by slot, member by
# member - FieldEnemy<n>) - set at spawn, for the run log's encounter
# fields. -1 for an enemy placed by hand.
var floor_index: int = -1
# The EncounterSlot.slot_id and EncounterOption.option_id it was spawned
# from - set at spawn, for the run log and for a prop that watches its
# slot (TroughProp.guard_slot). Empty for an enemy placed by hand.
var slot_id: StringName = &""
var option_id: StringName = &""
@export var region_field_path: NodePath = ^".."
@export var ground_path: NodePath = ^"../Ground"
# The hover highlight and the hit flash both BRIGHTEN: albedo times this,
# not Color.lightened() toward white - a textured body's albedo is
# already white (the texture carries the colour), and lightening white
# is nothing, which is what the hover did on the Sputter from the day it
# got its real material. Above 1.0 the albedo overdrives the texture.
@export var highlight_brightness: float = 1.35

# The forward-lunge-and-back this enemy's own attacks play in place of a
# clip (creatures have no animations to swing) - see play_attack_snap()'s
# own doc. Lives here, not on BattleFeedback, since it's this enemy's own
# attack-animation timing (the equivalent of CardData.battle_animation/
# impact_time for a card), not one of the reactive hit-feedback effects
# BattleFeedback owns the tunables for.
@export_group("Attack Snap")
@export var attack_snap_distance: float = 0.6
@export var attack_snap_out_time: float = 0.12
@export var attack_snap_return_time: float = 0.2
# EnemyData.attack_lean_degrees / _pivot_forward, copied at spawn: the
# model tips toward the target over the lunge and back over the return,
# about a pivot on its base this far from its centre (0) to its front
# edge (1). Read at each attack; 0 at spawn = no lean pivot at all.
@export_range(0.0, 60.0) var attack_lean_degrees: float = 0.0
@export_range(0.0, 1.0) var attack_lean_pivot_forward: float = 1.0
# EnemyData.battle_camera_turn_degrees, copied at spawn: in a fight its
# model turns this far toward the camera on top of facing the Wanderer
# (enter_battle_turn()). The model turns, not the body - its facing,
# lunge, lean and recoil stay on the line. Live while it is in one.
@export var battle_camera_turn_degrees: float = 20.0:
	set(value):
		battle_camera_turn_degrees = value
		if _battle_turned and _model != null:
			_model.rotation.y = _model_yaw()

# The sound of a card's hit landing on this creature - enemy_data.
# contact_sounds picked at random, never the last take twice running
# (SoundPool.next_random()), through one
# AudioStreamPlayer3D on the SFX bus, played on the hit frame by
# BattleFeedback._react_to_card_hit() (with the flash, recoil and damage
# number). Levels: the takes are normalised to -6 dBFS; at the battle
# camera's ~10.6 m the 3D attenuation takes ~0.5 dB, so -4 peaks about
# -10.5 dBFS at the listener - the loudest thing in a strike. Pitch
# varies per play by enemy_data.pitch_jitter. A hit that meets block
# draws from enemy_data.armored_contact_sounds instead, when it has any.
@export_group("Contact Sound")
@export var contact_volume_db: float = -4.0
@export var contact_volume_variance_db: float = 1.0

# The pain turn's sound (EnemyData.pain_turn_sound), played from this body
# when the turn is set - read at play time.
@export_group("Pain Sound")
@export var pain_volume_db: float = -4.0
@export_group("")

# EnemyData.status_gained_sound, played from this body as it gains that
# status - read at play time.
@export_group("Status Sound")
@export var status_gained_volume_db: float = -4.0
@export_group("")

# How a body leaves a fight it died in (see settle_and_free()) - the last
# kill's as much as any, the win waiting for it.
@export_group("Settle")
# A winged body's fold, before the death proper (DragonflyWings.fold()).
@export var settle_time: float = 0.4
# The death (settle_and_free()): the body slumps - sinks death_slump_depth
# of its height and tilts death_slump_tilt_degrees, overshooting a little
# and settling, over death_slump_time - while it goes into the fog: the
# fog colour laid over it (its fog pass's veil) over death_fade_time,
# losing its contrast rather than its opacity; then it dissolves out
# (dithered) over death_vanish_time and is freed. No glow, no flash.
@export var death_slump_time: float = 0.35
@export_range(0.0, 0.5) var death_slump_depth: float = 0.08
@export var death_slump_tilt_degrees: float = 5.0
@export var death_fade_time: float = 0.8
@export var death_vanish_time: float = 0.25
# A few wisps of sand lift from where it lies and drift off downwind
# (RegionField.get_wind_direction()), fading: death_wisp_count of them,
# each living death_wisp_lifetime, moving death_wisp_speed m/s along the
# wind with death_wisp_lift of rise, death_wisp_size across, at most
# death_wisp_alpha opaque - sand, death_wisp_fog_blend of the way to the
# fog colour so they sit in the air. They leave over death_wisp_spread of
# a second, starting death_wisp_delay into the death.
@export var death_wisp_count: int = 5
@export var death_wisp_lifetime: float = 1.6
@export var death_wisp_speed: float = 0.45
@export var death_wisp_lift: float = 0.12
@export var death_wisp_size: float = 0.22
@export_range(0.0, 1.0) var death_wisp_alpha: float = 0.45
@export_range(0.0, 1.0) var death_wisp_fog_blend: float = 0.3
@export_range(0.0, 1.0) var death_wisp_spread: float = 0.5
@export var death_wisp_delay: float = 0.15

# Flight, for a patrolling pack member (PackPatrol -> fly_to()): how
# fast the body turns to face its travel, and how long a flyer takes to
# drop where it is when a fight starts (land_now(), from RegionField's
# contact handler or step_to()).
@export_group("Flight")
@export var flight_turn_rate: float = 6.0
@export var battle_land_seconds: float = 0.3

# Standing clear of the sand and hovering through a fight - EnemyData.
# rest_height_m and battle_hover_m, copied by RegionField at spawn like
# model_scale. Both move the MODEL, never the body: the body stays on the
# sand, and with it the contact shadow, the contact area and every
# lunge/recoil/step tween, so none of them has to know. See
# enter_battle_hover() for the fight's hover and its bob.
@export_group("Phase Drop")
# The drop off its rock at its phase (drop_off(), FloorEnemy.phase_drop_
# offset): the step sideways and the fall together over phase_drop_
# seconds, with a hop of phase_drop_hop_m at its middle; the turn to the
# Wanderer after it; the puff of sand on landing (spawn_sand_puff()'s
# settings).
@export var phase_drop_seconds: float = 0.5
# A seated rider's way down to its line spot at a fight's start
# (climb_down_to()) - and back up after an escape: the hop over its
# carrier's side, metres, at the middle of the move. The move takes the
# fight's own transition (the camera's swing), the Wanderer's step.
@export var climb_hop_m: float = 0.3
@export var phase_drop_hop_m: float = 0.15
@export var phase_drop_turn_seconds: float = 0.4
@export var phase_drop_puff_particles: int = 16
@export var phase_drop_puff_lifetime: float = 0.8
@export var phase_drop_puff_velocity: float = 1.4
@export var phase_drop_puff_spread_degrees: float = 70.0
@export var phase_drop_puff_tint: float = 0.75
@export_group("")
@export_group("Rest And Hover")
@export var rest_height: float = 0.0:
	set(value):
		rest_height = value
		_apply_model_lift()
# EnemyData.sink_m, copied the same way: metres the model is set into the
# ground below its feet, field and fight alike - seen, never buried (no
# mound, no hiding; a negative rest_height is the burial). The
# Greyshelf's belly on its rock. Moves the model like the rest; the
# camera fit and the intent's head height come down with it.
@export var sink: float = 0.0:
	set(value):
		sink = value
		_apply_model_lift()
# Above the sand, metres; 0 = this body never leaves the ground in a fight
# (or, sunk under a negative rest_height, surfaces onto it - the Siltjaw).
@export var battle_hover: float = 0.0:
	set(value):
		battle_hover = value
		if _hovering:
			_tween_hover(_hover_lift(), _flight_bob_weight(), battle_rise_seconds, Tween.EASE_OUT)
# The bob on top of the hover: this far either way, over this long.
@export var battle_bob_m: float = 0.03
@export var battle_bob_seconds: float = 1.2:
	set(value):
		battle_bob_seconds = value
		if _hovering:
			_start_bob()
@export var battle_rise_seconds: float = 0.3
# Back down to rest height on a win or an escape.
@export var battle_settle_seconds: float = 0.4
# A buried body going under mid-fight, or coming back up (play_burrow()).
@export var burrow_seconds: float = 0.5
@export_group("")

@export_group("Dig")
# A DIG's mounds (begin_dig()): in a row across the line to the Wanderer,
# this far apart centre to centre, each its own SandMound this long (along
# the body's facing), wide and high. Edits reshape mounds already up.
@export var dig_mound_spacing_m: float = 1.7:
	set(value):
		dig_mound_spacing_m = value
		_place_dig_mounds()
@export var dig_mound_length_m: float = 2.4:
	set(value):
		dig_mound_length_m = value
		_shape_dig_mounds()
@export var dig_mound_width_m: float = 1.5:
	set(value):
		dig_mound_width_m = value
		_shape_dig_mounds()
@export var dig_mound_height_m: float = 0.28:
	set(value):
		dig_mound_height_m = value
		_shape_dig_mounds()
# The row's middle stepped this far from where the body stood toward the
# Wanderer's side of the screen - a row centred on a body framed at the
# screen's edge runs off it - but never so far that a mound stands within
# dig_wanderer_clear_m of him. Read at a fight's first dig.
@export var dig_row_toward_m: float = 1.3
@export var dig_wanderer_clear_m: float = 3.0
# The mounds swelling up, and a wrong one falling flat.
@export var dig_mound_rise_seconds: float = 0.6
@export var dig_mound_collapse_seconds: float = 0.35
# A hit on a mound (play_mound_hit()): it dips by dig_mound_hit_dip of its
# height and springs back over dig_mound_hit_seconds, with a strike into
# sand (dig_mound_hit_clips, in turn at random) - the same on every mound,
# so it never says which one the enemy is under. The sand clips carry
# about 6 dB less body than a contact sound at the same peak (their
# loudest 50 ms, -18 dBFS against the Sputter shell's -12), so they play
# dig_mound_hit_gain_db over contact_volume_db, to read at contact level
# (04_FIELD_ASSET_SPEC section 4: contact about -13 at the listener)
# rather than under the swing.
@export_range(0.0, 1.0, 0.01) var dig_mound_hit_dip: float = 0.25
@export var dig_mound_hit_seconds: float = 0.2
@export var dig_mound_hit_gain_db: float = 6.0
# Its Dig queued (set_dig_spray(), from BattleOverlay): a low, steady
# spray of sand at it - dig_spray_amount grains alive at once, each
# dig_spray_lifetime seconds, thrown up at up to dig_spray_velocity m/s
# within dig_spray_spread_degrees of straight up, in the ground's dry
# colour times dig_spray_tint. Unshaded, no glow. Each re-applies live.
@export var dig_spray_amount: int = 6:
	set(value):
		dig_spray_amount = maxi(value, 1)
		_apply_dig_spray()
@export var dig_spray_lifetime: float = 1.4:
	set(value):
		dig_spray_lifetime = maxf(value, 0.05)
		_apply_dig_spray()
@export var dig_spray_velocity: float = 1.2:
	set(value):
		dig_spray_velocity = value
		_apply_dig_spray()
@export var dig_spray_spread_degrees: float = 35.0:
	set(value):
		dig_spray_spread_degrees = value
		_apply_dig_spray()
@export var dig_spray_tint: float = 0.75:
	set(value):
		dig_spray_tint = value
		_apply_dig_spray()
@export var dig_mound_hit_clips: Array[AudioStream] = [
	load("res://assets/audio/sfx/sword_ground_strike_sand_1.mp3") as AudioStream,
	load("res://assets/audio/sfx/sword_ground_strike_sand_2.mp3") as AudioStream,
	load("res://assets/audio/sfx/sword_ground_strike_sand_3.mp3") as AudioStream,
]
# Added over a mound while the cursor is on it - the same for every
# mound, so the hover says nothing about which is which.
@export var dig_mound_highlight: Color = Color(0.09, 0.08, 0.06):
	set(value):
		dig_mound_highlight = value
		if _dig_highlight_material != null:
			_dig_highlight_material.albedo_color = value
@export_group("")

@export_group("Dig tell")
# The one clue to which mound the body is under (set_dig_tell()), on that
# mound alone: every tell_breathe_interval seconds it settles by
# tell_strength of its height and rises back, over tell_breathe_seconds -
# then lies still again. No particles; the other mounds never move.
# tell_strength is how subtle it is. Edits take hold on the next dig.
@export_range(0.0, 0.5, 0.01) var tell_strength: float = 0.06
@export var tell_breathe_seconds: float = 1.2
@export var tell_breathe_interval: float = 3.5

var _contacted: bool = false
var _contact_player: AudioStreamPlayer3D = null
var _heavy_player: AudioStreamPlayer3D = null
# The facing turn running now, if any (_turn_to()) - stopped when a new
# one starts, so two turns never pull on rotation.y at once.
var _face_tween: Tween = null
# Whether the model carries battle_camera_turn_degrees (_model_yaw()),
# and the tween turning it there or back.
var _battle_turned: bool = false
var _battle_turn_tween: Tween = null
# Made on the first pain turn (play_pain_turn_sound()); none before.
var _pain_player: AudioStreamPlayer3D = null
# Made on the first status_gained_sound (show_status()); none before.
var _status_player: AudioStreamPlayer3D = null
var _contact_pool := SoundPool.new()
var _mound_hit_pool := SoundPool.new()
var _armored_contact_pool := SoundPool.new()
# BaseMaterial3D, not StandardMaterial3D: Godot's glTF importer can produce
# either it or an ORMMaterial3D for a material with a combined metallic-
# roughness texture (both are BaseMaterial3D siblings, not one a subclass
# of the other) - albedo_color/roughness/metallic/*_texture are all
# BaseMaterial3D's own properties, so every read/write below works
# identically regardless of which concrete class _build_model_material()
# actually got handed. Or a ShaderMaterial on wanderer_painted.gdshader
# (painted_albedo_path): its tint is the albedo_tint uniform, its
# dissolve the presence uniform - _tint_property() and
# _set_death_presence() tell the two apart.
var _model_material: Material
# Captured once, right after _model_material is built - what set_highlight()/
# play_hit_flash() both return to at rest. Not the same thing as model_color:
# for the real Sputter.glb material this is whatever its own baseColorFactor
# actually is (white, so the real texture reads unmodified), only falling
# back to model_color when the mesh had no material of its own to inherit.
var _model_base_color: Color = Color.WHITE
# Everything the highlight and the hit flash tint, with what each returns
# to: the body's material first, then whatever an attachment hands over
# (see _attach_scene()). Parallel arrays, filled by _spawn_model().
var _tint_materials: Array[Material] = []
var _tint_base_colors: Array[Color] = []
# The attachment_scene_path instance, if any (see _attach_scene()) - the
# lunge tells it to flap and the settle tells it to fold, when it can.
var _attachment: Node3D = null
# The fog overlays (see _add_fog_overlay()) and, parallel, the material
# each one is the next_pass of.
var _fog_overlays: Array[ShaderMaterial] = []
var _fog_bases: Array[Material] = []
# The hit flash running now (play_hit_flash()) - a death stops it, or its
# fall would write full opacity back over the dissolve.
var _flash_tween: Tween = null
# The death running now (settle_and_free()), for skip_death().
var _death_tween: Tween = null
# The instantiated glb root from _spawn_model() - what settle_and_free()
# sinks. The BODY keeps its place (the recoil tweens that), the model
# moves under it.
var _model: Node3D = null
# Between this body and _model when it leans to attack (attack_lean_
# degrees above 0 at spawn), else null: identity at rest, so the model's
# grounding, lift and settle are unchanged; play_attack_snap() turns it.
var _lean_pivot: Node3D = null
var _settling: bool = false
# Set the moment this enemy's HP reaches 0 in a fight (RegionField._on_
# enemy_defeated() -> mark_defeated()), whether it settles now or is
# freed with the win a beat later: from then on it is not a thing the
# Wanderer can bump into, not a member a cluster fight collects, and
# not a required fight the gate waits on.
var _defeated: bool = false
# Where this enemy stood before step_to() moved it into a fight's line,
# and which way it faced - what return_to_field_pose() goes back to
# after an escape. Set by step_to(), cleared by the return.
var _field_position: Vector3 = Vector3.ZERO
var _field_yaw: float = 0.0
var _has_field_pose: bool = false
# Facing a prop as placed (FloorEnemy.face_prop_index, set_prop_facing()):
# the yaw that faces it, which an escape turns back to.
var _faces_prop: bool = false
var _prop_yaw: float = 0.0
# In the air (fly_to() until it lands): the flight tween drives
# _flight_xz and _hover, and _process() puts the body at that XZ, hover
# above the relief there, turned toward _flight_heading. The contact
# area doesn't monitor while airborne - a flyer is nothing to bump into.
var _airborne: bool = false
var _flight_tween: Tween = null
var _flight_xz: Vector2 = Vector2.ZERO
var _hover: float = 0.0
var _flight_heading: float = 0.0
var _ground: Ground = null
# The model's grounded Y (its AABB feet on the body floor), from
# _spawn_model() - what rest height, hover and bob are added to.
var _model_ground_y: float = 0.0
# A fight's hover (see enter_battle_hover()): the lift above rest height
# and the bob's weight, both tweened in and out; the bob's angle, looped;
# this member's own phase on it.
var _hovering: bool = false
var _lift: float = 0.0
var _bob_weight: float = 0.0
var _bob_angle: float = 0.0
var _bob_phase: float = 0.0
var _hover_tween: Tween = null
var _bob_tween: Tween = null
# A hit-stop on this body (hold_for()): the timer that ends it (null =
# none); the tweens it paused, to play on; its attachment's process mode,
# to put back. And the latest recoil and attack lunge, which a stop also
# holds.
var _hold_timer: SceneTreeTimer = null
var _held_tweens: Array[Tween] = []
var _held_attachment_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _recoil_tween: Tween = null
var _attack_tween: Tween = null
var _slash_mark_mesh: ArrayMesh = null
# A buried body's show while it's down (rest height under the sand; see
# _apply_model_lift()): the sand swelling over it, and the contact shadow
# that goes with the model.
var _mound: SandMound = null
var _contact_shadow: ContactShadow = null
# The mound's silt trickle (_setup_trickle()) and its own rolls.
var _trickle_timer: Timer = null
var _trickle_rng: RandomNumberGenerator = RandomNumberGenerator.new()
# Riding (ride_on()): the member it rides on, where on it (the carrier's
# body frame, metres up from its feet), turned how far from its facing,
# and whether it is seated there now - a fight takes it down to its line
# spot (step_to()), an escape back up (return_to_field_pose()).
var _carrier: FieldEnemy = null
var _ride_offset: Vector3 = Vector3.ZERO
var _ride_yaw: float = 0.0
var _seated: bool = false
# Where it stood as placed, before it was seated - its authored spot,
# which its cluster's line reads (get_line_point()).
var _line_spot: Vector3 = Vector3.ZERO
# A DIG under way (begin_dig()): the row's centre and its across
# direction, each mound's anchor (top-level, world-fixed: a lunge never
# drags the sand) by mound number - null once collapsed or gone - and
# the hover's overlay. _dig_centre is kept from the fight's first dig, so
# every dig of the fight lays its row in the same place.
var _dig_active: bool = false
var _dig_centre: Vector3 = Vector3.ZERO
var _dig_centre_set: bool = false
var _dig_across: Vector3 = Vector3.RIGHT
var _dig_anchors: Array[Node3D] = []
var _dig_highlight_material: StandardMaterial3D = null
# The Dig's spray (set_dig_spray()), made the first time it is wanted.
var _dig_spray: GPUParticles3D = null
# The tell's mound and its breathing, while it shows (set_dig_tell()).
var _tell_mound: int = -1
# The body's own mound giving way to a dig's row (begin_dig()).
var _own_mound_tween: Tween = null
var _tell_tweens: Array[Tween] = []
# FloorEnemy.phase_drop_offset resolved at spawn: whether it drops at its
# phase, and the world XZ it lands on (Y unused).
var has_phase_drop: bool = false
var phase_drop_spot: Vector3 = Vector3.ZERO
# FloorEnemy.phase_drop_frame_offset resolved the same way: whether the
# frame after the drop is fitted somewhere other than where it lands, and
# where (world XZ; Y unused).
var has_phase_drop_frame: bool = false
var phase_drop_frame_spot: Vector3 = Vector3.ZERO
# Dropped this fight (drop_off()), and the height it lay at before - what
# an escape climbs back to (return_to_field_pose()).
var _dropped: bool = false
var _field_height_offset: float = 0.0
var _slash_mark_texture: GradientTexture2D = null

# Owned by this enemy, but lives in RegionField.field_hud, not here (a
# Control needs a CanvasLayer ancestor, not a Node3D one) - see _ready()'s
# own creation of it and add_enemy_status()'s doc on the other end.
# BattleOverlay reuses this exact instance rather than creating its own
# (see its own _create_enemy_statuses()); region_field.gd frees it
# explicitly on a WIN outcome, since freeing this node doesn't cascade to
# it the way freeing a real child would.
var enemy_status: EnemyStatus = null
# The model's scaled bounding-box height, from _spawn_model() - the
# creature's own head height above its ground position, for anything
# that anchors above it (BattleIntent). 0 until the model has spawned.
var _model_height: float = 0.0
# Half the model's larger horizontal bbox extent (X or Z), same source -
# how far the body reaches sideways from its ground position, for
# CameraRig's battle fit. 0 until the model has spawned.
var _model_half_width: float = 0.0
# The model's combined mesh AABB in this body's own space, as placed (the
# grounding shift applied) - what BattleController projects for the
# armed-card target test. Empty until the model has spawned.
var _model_aabb: AABB = AABB()
# _model_aabb before the attachment widens it (_attach_scene()): the body
# alone - the contact pool's footprint where its data asks for the body.
var _body_aabb: AABB = AABB()
# The model's outline seen from above, body-local XZ before any battle
# turn (a convex hull of its vertices) - what its frame reaches are read
# from, the body's own taper and all (battle_frame_reaches()).
var _model_outline: PackedVector2Array = PackedVector2Array()

# The head above the body's feet: the model's own height, standing at
# rest height, lifted by a fight's hover, and raised by a rear (see
# set_rearing()). Not the bob - the camera's battle fit reads this every
# frame and must not breathe with it.
func get_head_height() -> float:
	return _model_height + rest_height - sink + _lift + _rear_lift()

func get_half_width() -> float:
	return _model_half_width

# harness_point in the world, through the model's scale, yaw, grounding,
# lift and settle - where a HitchingPost's rope ends. The body's own
# position before the model has spawned.
func get_harness_point() -> Vector3:
	if _model == null:
		return global_position
	return _model.global_transform * harness_point

# RegionField at spawn, for a FloorEnemy with face_prop_index: face `yaw`
# (the angle toward that prop) now, and again after an escape.
func set_prop_facing(yaw: float) -> void:
	_faces_prop = true
	_prop_yaw = yaw
	rotation.y = yaw

func get_model_aabb() -> AABB:
	return AABB(_model_aabb.position + Vector3.UP * get_body_lift(), _model_aabb.size + Vector3.UP * _rear_lift())

# How far its body reaches toward the Wanderer in a fight, metres from its
# origin along the battle axis: every member turns to face his stance
# (face_toward_point()), its local -Z toward him, so the near edge is its
# model's box (scale, model yaw and attachment in) at -Z - the same
# whichever way he came - turned toward the camera as it will stand
# (battle_camera_turn_degrees), unless `turned` is false. What RegionField
# measures his battle_gap_m from.
func battle_front_reach(turned: bool = true) -> float:
	return _battle_reach(Vector3.FORWARD, turned)

# The same reach away from him (local +Z) - toward the member behind it
# in a line (RegionField._cluster_gap_for()).
func battle_back_reach(turned: bool = true) -> float:
	return _battle_reach(Vector3.BACK, turned)

# How far the body reaches toward the Wanderer (x, its snout) and away
# (z, its tail) in a fight, from its outline as it will stand turned to
# the camera - the shape itself, not its box, whose corners a long
# tapering body overstates - and how far each of those points stands off
# the body's line toward the camera (y and w: the turn brings the snout
# nearer, the tail further). What CameraRig frames a fight by rule with
# (battle_frame_screen). The box's reaches, on the line, until the
# outline is measured.
func battle_frame_reaches() -> Vector4:
	if _model_outline.is_empty():
		return Vector4(battle_front_reach(), 0.0, battle_back_reach(), 0.0)
	var turn: float = deg_to_rad(battle_camera_turn_degrees)
	var pivot: Vector2 = Vector2(_model.position.x, _model.position.z) if _model != null else Vector2.ZERO
	var front: float = 0.0
	var front_side: float = 0.0
	var back: float = 0.0
	var back_side: float = 0.0
	for point in _model_outline:
		# Turned about the model's own origin the way _battle_reach() turns
		# the box: Basis(UP, turn) on (x, z).
		var p: Vector2 = point - pivot
		var turned := Vector2(p.x * cos(turn) + p.y * sin(turn), -p.x * sin(turn) + p.y * cos(turn)) + pivot
		# Body +X is the camera's own forward in a fight (CameraRig's
		# ground forward is UP x the line to it), so toward the camera is -x.
		if -turned.y > front:
			front = -turned.y
			front_side = -turned.x
		if turned.y > back:
			back = turned.y
			back_side = -turned.x
	return Vector4(front, front_side, back, back_side)

# The convex hull of every mesh vertex under `model`, body-local XZ.
func _measure_outline(model: Node3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		var to_body: Transform3D = global_transform.affine_inverse() * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			var vertices: PackedVector3Array = mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var at: Vector3 = to_body * vertex
				points.append(Vector2(at.x, at.z))
	return Geometry2D.convex_hull(points) if points.size() >= 3 else points

# The model box's furthest corner along body-local `direction`, metres,
# with the box turned about the model's own origin by the battle turn
# when `turned` - never less than 0.
func _battle_reach(direction: Vector3, turned: bool) -> float:
	var turn := Basis(Vector3.UP, deg_to_rad(battle_camera_turn_degrees) if turned else 0.0)
	var pivot := Vector3(_model.position.x, 0.0, _model.position.z) if _model != null else Vector3.ZERO
	var reach: float = 0.0
	for corner in 8:
		reach = maxf(reach, (turn * (_model_aabb.get_endpoint(corner) - pivot) + pivot).dot(direction))
	return reach

# Called by RegionField on contact, with face_toward_point(): turns the
# model battle_camera_turn_degrees toward the camera over duration.
func enter_battle_turn(duration: float) -> void:
	_battle_turned = true
	_tween_model_turn(duration)

# An escape's counterpart: the model back to its plain yaw.
func exit_battle_turn(duration: float) -> void:
	_battle_turned = false
	_tween_model_turn(duration)

func _tween_model_turn(duration: float) -> void:
	if _model == null:
		return
	if _battle_turn_tween != null and _battle_turn_tween.is_valid():
		_battle_turn_tween.kill()
	_battle_turn_tween = create_tween()
	_battle_turn_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_battle_turn_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_battle_turn_tween.tween_property(_model, "rotation:y", _model_yaw(), maxf(duration, 0.001))

# The model's yaw under the body: model_yaw_offset, and in a fight
# battle_camera_turn_degrees toward the camera. CameraRig's battle frame
# puts the enemies screen-right facing left (_battle_ground_forward()),
# so toward the camera is always a turn to its left - a positive yaw, the
# mirror of the Wanderer's.
func _model_yaw() -> float:
	return deg_to_rad(model_yaw_offset + (battle_camera_turn_degrees if _battle_turned else 0.0))

# The move an intent names (EnemyIntent.motion), toward `target` - the
# Wanderer - played by the attachment (CraneMotion.play_motion()).
# Returns how long until it lands - an Attack's contact, the whole of
# any other move - for the enemy turn to wait on; -1 for a body with no
# such move, which then does what it always did.
func play_intent_motion(motion: StringName, target: Node3D) -> float:
	if motion == &"" or _attachment == null or not _attachment.has_method("play_motion") or _settling:
		return -1.0
	return float(_attachment.call("play_motion", motion, target))

# The pose a queued intent asks of the body (EnemyIntent.rear_while_
# queued, the Siltjaw's charge): the attachment rears the front up or
# lets it back down (RearPose.set_rearing()). Returns how long that
# takes, for the enemy turn to wait on - 0 for a body with no such
# attachment, or already heading there.
func set_rearing(on: bool) -> float:
	if _attachment == null or not _attachment.has_method("set_rearing") or _settling:
		return 0.0
	return float(_attachment.call("set_rearing", on))

# How many stacks of Roused it holds (the Dunecur's crest, DunecurPose.
# set_roused()); a body with no such attachment ignores it.
func set_roused(stacks: int) -> void:
	if _attachment == null or not _attachment.has_method("set_roused"):
		return
	_attachment.call("set_roused", stacks)

# The crest held at `stacks` stacks' rise out of a fight as well (Dunecur
# Pose.set_alert() - floor 4's pup meeting it, DunecurPup); -1 lets it go.
# A body with no such attachment ignores it.
func set_alert(stacks: int) -> void:
	if _attachment == null or not _attachment.has_method("set_alert"):
		return
	_attachment.call("set_alert", stacks)

# The body stood at world XZ (x, z), its feet on the relief there, `lift`
# above them - a walk driven from outside, with no fight on (floor 4's
# Dunecur walking off with its pup, DunecurPup).
func walk_to_xz(x: float, z: float, lift: float) -> void:
	global_position = Vector3(x, _body_y_on_ground(x, z) + lift, z)

# The tell a queued Snap may hold (RearPose.set_poised() - shown only
# with its hold_tell on); a body with no such attachment ignores it.
func set_poised(on: bool) -> void:
	if _attachment == null or not _attachment.has_method("set_poised") or _settling:
		return
	_attachment.call("set_poised", on)

# The statuses this enemy holds, after each move and card (BattleController.
# _pose_for_intent()), for a body that shows one - GlowerPose, swollen
# while it taunts. Returns how long the change takes; 0 for any other.
func show_held_statuses(statuses: Array[StatusData]) -> float:
	if _attachment == null or not _attachment.has_method("show_held_statuses") or _settling:
		return 0.0
	return float(_attachment.call("show_held_statuses", statuses))

# The status the queued intent holds its enemy in (EnemyIntent.status_
# while_queued - the Underfoot's Covered or Exposed), for the body to
# take its pose (UnderfootPose.set_queued_status()). Returns how long
# that takes, for the enemy turn to wait on - 0 for a body with no such
# attachment, or already heading there.
func set_queued_status(status: StatusData) -> float:
	if _attachment == null or not _attachment.has_method("set_queued_status") or _settling:
		return 0.0
	return float(_attachment.call("set_queued_status", status))

# How much higher a rear has put the top of the body, metres.
func _rear_lift() -> float:
	if _attachment == null or not _attachment.has_method("get_rear_lift"):
		return 0.0
	return float(_attachment.call("get_rear_lift"))

# How far the model sits above its grounded place right now: rest height,
# hover and bob. What anything anchored to the body adds (EnemyStatus).
func get_body_lift() -> float:
	return rest_height - sink + _lift + get_bob_offset()

# The bob alone, for what anchors to the head (BattleIntent), which
# already has the rest of the lift through get_head_height().
func get_bob_offset() -> float:
	return battle_bob_m * _bob_weight * sin(_bob_angle + _bob_phase)

# The model's world AABB as a screen rect: its 8 corners unprojected,
# bounded, grown by padding_px on every side - what a click or an armed
# card has to land in to mean this enemy (BattleController's target test
# and RegionField's point-to-move both use it). Empty when the model
# hasn't spawned or any corner is behind the camera.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _model_aabb.size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2()
	var aabb: AABB = get_model_aabb()
	for i in 8:
		var corner: Vector3 = global_transform * aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

# What a click or hover picks it by: get_screen_rect() grown by padding_px,
# then to at least min_size_px each way about its own centre - so a small
# body (a Nettle) is never a target smaller than the floor, and the
# centre a target line ends at never moves. Empty where that is.
func get_pick_rect(camera: Camera3D, padding_px: float, min_size_px: float) -> Rect2:
	var rect: Rect2 = get_screen_rect(camera, padding_px)
	if rect.size == Vector2.ZERO:
		return rect
	var size := Vector2(maxf(rect.size.x, min_size_px), maxf(rect.size.y, min_size_px))
	return Rect2(rect.get_center() - size * 0.5, size)

@onready var contact_area: Area3D = $ContactArea
@onready var contact_shape: CollisionShape3D = $ContactArea/CollisionShape3D

func _ready() -> void:
	# RegionField's own freeze (PROCESS_MODE_DISABLED on contact) defaults
	# to removing every CollisionObject3D beneath it from the physics space
	# entirely (disable_mode's default, REMOVE) - which would make this
	# enemy un-raycastable for card targeting during the very battle that
	# freeze exists for. MAKE_STATIC keeps the body in space (immobile,
	# which it already effectively is once frozen) instead.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC

	var shape := SphereShape3D.new()
	shape.radius = contact_radius
	contact_shape.shape = shape

	contact_area.body_entered.connect(_on_body_entered)
	contact_area.body_exited.connect(_on_body_exited)
	# _process() is the flight's own; nothing runs there on the ground.
	set_process(false)

	_spawn_model()
	_spawn_enemy_status()
	_spawn_contact_audio()

	if face_shore_at_spawn:
		_face_shore()

	var contact_shadow := ContactShadow.new()
	contact_shadow.name = "ContactShadow"
	if enemy_data != null and enemy_data.contact_shadow != null:
		contact_shadow.data = enemy_data.contact_shadow
	if _model_aabb.size != Vector3.ZERO:
		contact_shadow.footprint = Vector2(_model_aabb.size.x, _model_aabb.size.z) * 0.5
		contact_shadow.body_footprint = Vector2(_body_aabb.size.x, _body_aabb.size.z) * 0.5
	contact_shadow.feet_source = _contact_feet
	add_child(contact_shadow)
	_contact_shadow = contact_shadow
	_set_seated(_seated)

	if rest_height < 0.0:
		_mound = SandMound.new()
		_mound.name = "SandMound"
		add_child(_mound)
	_apply_model_lift()
	_setup_trickle()

	# relief_rebuilt covers every LIVE relief edit after this point, but its
	# very first emission happens inside Ground's own _ready() - before this
	# node could possibly have connected to it - so the initial grounding
	# still needs a manual call. Deferred a frame (rather than called
	# immediately) so it runs after RegionField's own _ready() has finished
	# placing this enemy from FloorData, not before.
	_ground = get_node_or_null(ground_path) as Ground
	_contact_shadow.set_ground(_ground)
	if _ground:
		if _mound != null:
			_mound.set_ground(_ground)
		_ground.relief_rebuilt.connect(_ground_to_relief)
		await get_tree().process_frame
		_ground_to_relief()

# Sits the body on the current terrain height at its own XZ, minus
# model_ground_offset - _spawn_model()'s own AABB grounding puts the
# model's feet at body-local Y = model_ground_offset, not Y = 0, so the
# body's global Y has to account for that for the feet (not the body
# origin) to land on the surface. Called once, deferred, from _ready()
# and again on every Ground.relief_rebuilt - see _ready()'s own comment
# for why both are needed.
func _ground_to_relief() -> void:
	if _seated and is_riding():
		_seat_on_carrier()
		return
	if _ground == null:
		return
	global_position.y = _body_y_on_ground(global_position.x, global_position.z)
	# The mound's one sample of the sand: here, once the body stands where
	# it was placed - and again only if the relief itself is rebuilt.
	if _mound != null:
		_mound.resample()

# Where the pool under it is laid (ContactShadow.feet_source): under the
# middle of the box its footprint was sized from - the body's alone where
# its data says footprint_from_body (the dragonfly, without its wings),
# else the model's - turned with the body, at its feet; lifted with the
# model by a rest height or a fight's hover and bob, so the pool fades
# with them.
func _contact_feet() -> Vector3:
	if _model == null:
		return global_position
	var from_body: bool = _contact_shadow != null and _contact_shadow.data != null and _contact_shadow.data.footprint_from_body and _body_aabb.size != Vector3.ZERO
	var centre: Vector3 = (_body_aabb if from_body else _model_aabb).get_center()
	var lift: float = _model.position.y - _model_ground_y
	return global_transform * Vector3(centre.x, _model_aabb.position.y + lift, centre.z)

# The body's global Y with its feet on the relief at this XZ (see
# _ground_to_relief()'s doc for the model_ground_offset part), raised by
# height_offset. The current Y when there is no Ground to ask.
func _body_y_on_ground(x: float, z: float) -> float:
	if _ground == null:
		return global_position.y
	var local_xz: Vector3 = _ground.to_local(Vector3(x, 0.0, z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z)) - model_ground_offset + height_offset

# get_forward() points inland (spawn -> ForwardMarker, see RegionField's own doc),
# so facing the shore/sea is the opposite direction. Yaws the body itself,
# not the model - model_yaw_offset above stays a separate, local correction
# for the imported asset's own facing.
func _face_shore() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		return
	var to_shore := -region_field.get_forward()
	if to_shore.length() < 0.0001:
		return
	# Same verified direction<->angle convention as face_toward() below and
	# Wanderer._angle_from_direction().
	rotation.y = atan2(-to_shore.x, -to_shore.z)

# Takes `base` out of the environment's depth fog and lays this body's
# own share back over it - an enemy_fog.gdshader overlay as its next_pass
# (see that shader's doc), at the end of its pass chain. The body's
# material and every material an attachment hands over (the dragonfly's
# wings) get one; refresh_fog() fills them.
func _add_fog_overlay(base: Material) -> void:
	var shader := load(FOG_SHADER_PATH) as Shader
	if shader == null:
		push_warning("FieldEnemy '%s': fog overlay shader failed to load (%s); fogged as scenery." % [enemy_id, FOG_SHADER_PATH])
		return
	var overlay := ShaderMaterial.new()
	overlay.shader = shader
	# A painted body is out of the fog already (wanderer_painted.gdshader
	# is fog_disabled).
	if base is BaseMaterial3D:
		(base as BaseMaterial3D).disable_fog = true
	var tail: Material = base
	while tail.next_pass != null:
		tail = tail.next_pass
	tail.next_pass = overlay
	_fog_overlays.append(overlay)
	_fog_bases.append(base)

# Pushes the field's depth fog (RegionField's RegionSky) and this body's
# share of it - enemy_data.fog_factor_override when set, else RegionField.
# enemy_fog_factor - into every fog overlay. Called once the overlays are
# built, and by RegionField whenever the fog or the factor changes.
func refresh_fog() -> void:
	if _fog_overlays.is_empty():
		return
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		return
	var sky: RegionSky = region_field.get_region_sky()
	if sky == null:
		return
	var factor: float = region_field.enemy_fog_factor
	if enemy_data != null and enemy_data.fog_factor_override >= 0.0:
		factor = enemy_data.fog_factor_override
	for index in _fog_overlays.size():
		var overlay: ShaderMaterial = _fog_overlays[index]
		var standard := _fog_bases[index] as BaseMaterial3D
		overlay.set_shader_parameter("fog_color", sky.fog_color)
		overlay.set_shader_parameter("fog_energy", sky.fog_light_energy)
		overlay.set_shader_parameter("fog_begin", sky.current_fog_depth_begin())
		overlay.set_shader_parameter("fog_end", sky.current_fog_depth_end())
		overlay.set_shader_parameter("fog_density", sky.fog_density)
		overlay.set_shader_parameter("fog_factor", clampf(factor, 0.0, 1.0))
		# An alpha-scissor surface keeps its cut-away part clear of the fog.
		var scissor: bool = standard != null and standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and standard.albedo_texture != null
		overlay.set_shader_parameter("use_alpha_texture", scissor)
		overlay.set_shader_parameter("alpha_texture", standard.albedo_texture if scissor else null)
		if standard != null:
			overlay.set_shader_parameter("alpha_scissor_threshold", standard.alpha_scissor_threshold)

func _spawn_model() -> void:
	var scene_path: String = model_scene_path if not model_scene_path.is_empty() else DEFAULT_MODEL_SCENE_PATH
	var scene := load(scene_path) as PackedScene
	if scene == null:
		push_warning("FieldEnemy '%s': model scene failed to load (%s); no body." % [enemy_id, scene_path])
		return
	var model := scene.instantiate() as Node3D
	if attack_lean_degrees > 0.0:
		_lean_pivot = Node3D.new()
		_lean_pivot.name = "LeanPivot"
		add_child(_lean_pivot)
		_lean_pivot.add_child(model)
	else:
		add_child(model)
	_model = model
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = deg_to_rad(model_yaw_offset)

	# Combined AABB of all mesh instances, expressed in this node's own
	# space (not the model's), so its bottom tells us how far to raise the
	# model regardless of the model's own pivot/rotation.
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		# One shared material across every mesh instance, built once from
		# whichever one is found first - matches Sputter.glb's own shape
		# (a single mesh/material today); if a future model ships more than
		# one, every instance still gets this same first material rather
		# than each keeping its own real one, same simplification the old
		# flat-color placeholder already made.
		if _model_material == null:
			if not painted_albedo_path.is_empty():
				_model_material = _build_painted_material()
			if _model_material == null:
				_model_material = _build_model_material(mi)
			_model_base_color = _tint_of(_model_material)
		mi.material_override = _model_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		var mi_transform_in_self := global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_self := mi_transform_in_self * mi.get_aabb()
		combined_aabb = mi_aabb_in_self if not has_aabb else combined_aabb.merge(mi_aabb_in_self)
		has_aabb = true

	if _model_material != null:
		_tint_materials.append(_model_material)
		_tint_base_colors.append(_model_base_color)

	if has_aabb:
		print("FieldEnemy '%s': model AABB height = %.3f at model_scale = %.3f" % [enemy_id, combined_aabb.size.y, model_scale])
		var grounding_shift: float = -combined_aabb.position.y + model_ground_offset
		model.position.y += grounding_shift
		_model_height = combined_aabb.size.y
		_model_half_width = maxf(combined_aabb.size.x, combined_aabb.size.z) * 0.5
		_model_aabb = AABB(combined_aabb.position + Vector3(0.0, grounding_shift, 0.0), combined_aabb.size)
		_body_aabb = _model_aabb
		_model_outline = _measure_outline(model)
	_model_ground_y = model.position.y

	_attach_scene(model)
	# After the attachment: a pose's own pass on the body (the Greyshelf's
	# throat, the Stork's sac) is already on the chain, and the fog goes
	# over it, last.
	if _model_material != null:
		_add_fog_overlay(_model_material)
	_apply_model_lift()
	refresh_fog()
	if enemy_data != null and not enemy_data.changed.is_connected(refresh_fog):
		enemy_data.changed.connect(refresh_fog)

# The attachment (attachment_scene_path), under the model root once the
# body is grounded and its material pass is over, so the attachment's
# own materials are left alone - and taken into the tint list when it
# offers them (DragonflyWings.get_tint_materials()). Its meshes widen the
# extents the camera fit and the click rect read (a wing sticks out
# further than the body) but never the grounding, which the body's own
# feet already settled.
func _attach_scene(model: Node3D) -> void:
	if attachment_scene_path.is_empty():
		return
	var scene := load(attachment_scene_path) as PackedScene
	if scene == null:
		push_warning("FieldEnemy '%s': attachment scene failed to load (%s); none attached." % [enemy_id, attachment_scene_path])
		return
	var attachment := scene.instantiate() as Node3D
	if attachment == null:
		push_warning("FieldEnemy '%s': attachment scene (%s) is not a Node3D; none attached." % [enemy_id, attachment_scene_path])
		return
	model.add_child(attachment)
	_attachment = attachment
	if attachment.has_method("get_tint_materials"):
		# Untyped: the wings hand over BaseMaterial3Ds, the Glower's
		# inflated body a painted ShaderMaterial.
		var materials: Array = attachment.call("get_tint_materials")
		for item: Variant in materials:
			var material := item as Material
			if material == null:
				continue
			_tint_materials.append(material)
			_tint_base_colors.append(_tint_of(material))
			_add_fog_overlay(material)
	for mesh_instance in attachment.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		if mi.mesh == null:
			continue
		var mi_transform_in_self := global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_self := mi_transform_in_self * mi.get_aabb()
		_model_aabb = mi_aabb_in_self if _model_aabb.size == Vector3.ZERO else _model_aabb.merge(mi_aabb_in_self)
	_model_half_width = maxf(_model_aabb.size.x, _model_aabb.size.z) * 0.5
	_model_height = maxf(_model_height, _model_aabb.position.y + _model_aabb.size.y)

# Duplicates the mesh's own imported material (Sputter.glb ships a real
# baseColorTexture/metallicRoughnessTexture/normalTexture set) rather than
# replacing it with a flat model_color fill - duplicated so each enemy
# instance gets its own mutable copy set_highlight()/play_hit_flash() can
# tween directly, since a shared Material resource would leak those
# mutations onto every other enemy using the same imported mesh. roughness/
# metallic are forced to this project's own matte convention (every other
# surface here sets roughness=1, no specular/metallic - see Wanderer's own
# material builders) rather than left at whatever PBR values the import
# carried (Sputter.glb's own metallicFactor is 1.0, fully metallic, which
# would read as shiny/reflective against everything else in the game); the
# metallic/roughness texture map is cleared too so that forced scalar
# actually holds instead of being modulated per-pixel by a texture built
# for the original PBR values. Falls back to a flat model_color fill only
# if the mesh ships with no material of its own to inherit at all - same
# "degrade to a solid color rather than render wrong" shape Wanderer's own
# _build_textured_material() uses.
func _build_model_material(mesh_instance: MeshInstance3D) -> BaseMaterial3D:
	var source_material := mesh_instance.get_active_material(0)
	var material: BaseMaterial3D
	if source_material is BaseMaterial3D:
		material = (source_material as BaseMaterial3D).duplicate()
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = model_color
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.metallic_texture = null
	material.roughness_texture = null
	return material

# The body under wanderer_painted.gdshader with painted_albedo_path as
# its albedo - the Wanderer's soft light at the shader's own settings
# (wrap, self_shadow_strength; roughness 1, no specular, no normal map,
# both sides drawn). Each enemy its own material, so its tint is its own.
# Null when the shader or the texture fails to load: the glb's material
# is worn instead.
func _build_painted_material() -> ShaderMaterial:
	var shader := load(PAINTED_SHADER_PATH) as Shader
	var texture := load(painted_albedo_path) as Texture2D
	if shader == null or texture == null:
		push_warning("FieldEnemy '%s': painted material failed to load (%s, %s); wearing the glb's own." % [enemy_id, PAINTED_SHADER_PATH, painted_albedo_path])
		return null
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_tint", Color.WHITE)
	return material

# Where a tinted material keeps the colour the highlight, the hit flash
# and the dissolve write: a BaseMaterial3D's albedo_color, a painted
# body's albedo_tint uniform.
func _tint_property(material: Material) -> NodePath:
	return ^"shader_parameter/albedo_tint" if material is ShaderMaterial else ^"albedo_color"

func _tint_of(material: Material) -> Color:
	var tint: Variant = material.get_indexed(_tint_property(material))
	return tint if tint is Color else Color.WHITE

func _set_tint(material: Material, color: Color) -> void:
	material.set_indexed(_tint_property(material), color)

# Creates this enemy's own persistent HP display and hands it to RegionField
# to parent (see enemy_status's own doc on why - a Control needs a
# CanvasLayer ancestor, not this Node3D). Seeded at full HP so it reads
# correctly in the field, before any battle has ever touched this enemy;
# BattleController.setup()'s own initial enemy_hp_changed emit re-seeds it
# identically the instant a fight actually starts (see EnemyStatus.update_
# hp()'s own doc on why that reseed doesn't trigger a spurious reveal).
func _spawn_enemy_status() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		push_warning("FieldEnemy '%s': region_field_path did not resolve to a RegionField; no HP display." % enemy_id)
		return

	var status := (load(ENEMY_STATUS_SCENE_PATH) as PackedScene).instantiate() as EnemyStatus
	region_field.add_enemy_status(status)
	status.set_target(self)
	var max_hp: int = enemy_data.max_hp if enemy_data != null else 1
	status.update_hp(max_hp, max_hp)
	enemy_status = status

# Called by BattleController while this enemy is the hovered raycast target
# during card targeting. Brightness lift via albedo only, no emission - a
# hover cue, not a glow effect.
func set_highlight(on: bool) -> void:
	for index in _tint_materials.size():
		var base: Color = _tint_base_colors[index]
		_set_tint(_tint_materials[index], _brightened(base) if on else base)

# base x highlight_brightness on the colour channels, alpha untouched.
func _brightened(base: Color) -> Color:
	return Color(base.r * highlight_brightness, base.g * highlight_brightness, base.b * highlight_brightness, base.a)

# Called by BattleFeedback once BattleController reports a card hit
# landing on this enemy - lerps each tinted material's albedo up to its
# base x flash_color x highlight_brightness over rise_time (the same
# multiplicative lift the hover uses, tinted by BattleFeedback's flash
# colour), then back down to its base over fall_time. Timing and tint
# are parameters, not exports here: BattleFeedback owns the tunables
# for this and every other reactive hit-feedback effect (see its own
# doc) - this method is only the mechanism.
func play_hit_flash(flash_color: Color, rise_time: float, fall_time: float) -> void:
	if _tint_materials.is_empty():
		return
	# Every tinted material rises together, then falls together: the
	# rises in parallel, chain() puts the first fall after them, and the
	# remaining falls run alongside it.
	if _settling:
		return
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	var tween := create_tween()
	_flash_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	for index in _tint_materials.size():
		var target: Color = _brightened(_tint_base_colors[index] * flash_color)
		target.a = _tint_base_colors[index].a
		tween.tween_property(_tint_materials[index], _tint_property(_tint_materials[index]), target, rise_time)
	tween.chain()
	for index in _tint_materials.size():
		tween.tween_property(_tint_materials[index], _tint_property(_tint_materials[index]), _tint_base_colors[index], fall_time)

# from_direction is the direction the hit traveled (attacker -> this
# enemy, not normalized) - this recoils further along that same line,
# away from the attacker, and tilts back the same amount before easing
# back to rest. TRANS_BACK on the return leg is what gives it its own
# small overshoot past rest rather than a plain ease-in stop.
# See the Contact Sound exports. ALWAYS: RegionField's battle freeze
# cascades here and this plays during it.
func _spawn_contact_audio() -> void:
	if enemy_data != null:
		_contact_pool.set_clips(enemy_data.contact_sounds)
		_armored_contact_pool.set_clips(enemy_data.armored_contact_sounds)
	_contact_player = AudioStreamPlayer3D.new()
	_contact_player.name = "ContactAudio"
	_contact_player.bus = &"SFX"
	_contact_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_contact_player)

# A status this enemy holds, for its body's tells: handed to the
# attachment if it shows statuses (StorkTells - the marabou's sac).
# `animate` false at a fight's opening, where it's set at once. One
# gained mid-fight (`animate`) that EnemyData names plays its sound.
func show_status(status: StatusData, animate: bool) -> void:
	if status == null:
		return
	if _attachment != null and _attachment.has_method("show_status"):
		_attachment.call("show_status", status, animate)
	if animate and enemy_data != null and enemy_data.status_gained_sound != null and status == enemy_data.status_gained_sound_on:
		_play_status_gained_sound()

# EnemyData.status_gained_sound, from this body - on the SFX bus and
# through the battle freeze, like the pain turn's.
func _play_status_gained_sound() -> void:
	if _status_player == null:
		_status_player = AudioStreamPlayer3D.new()
		_status_player.name = "StatusAudio"
		_status_player.bus = &"SFX"
		_status_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_status_player)
	_status_player.stream = enemy_data.status_gained_sound
	_status_player.volume_db = status_gained_volume_db
	_status_player.play()

# EnemyData.pain_turn_sound, once, from this body - on the SFX bus and
# through the battle freeze, like the contact sound. Nothing without one.
func play_pain_turn_sound() -> void:
	if enemy_data == null or enemy_data.pain_turn_sound == null:
		return
	if _pain_player == null:
		_pain_player = AudioStreamPlayer3D.new()
		_pain_player.name = "PainAudio"
		_pain_player.bus = &"SFX"
		_pain_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_pain_player)
	_pain_player.stream = enemy_data.pain_turn_sound
	_pain_player.volume_db = pain_volume_db
	_pain_player.play()

# A heavy card hit's impact layer (BattleFeedback's heavy tier): `stream`
# at `volume_db`, from this body with its contact sound - on the SFX bus
# and through the battle freeze, like it.
func play_heavy_impact(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	if _heavy_player == null:
		_heavy_player = AudioStreamPlayer3D.new()
		_heavy_player.name = "HeavyImpactAudio"
		_heavy_player.bus = &"SFX"
		_heavy_player.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_heavy_player)
	_heavy_player.stream = stream
	_heavy_player.volume_db = volume_db
	_heavy_player.play()

# `armored`: the hit met this creature's block - its armored takes, if
# it has any, else the usual ones.
func play_contact_sound(armored: bool = false) -> void:
	var pool: SoundPool = _armored_contact_pool if armored and not _armored_contact_pool.is_empty() else _contact_pool
	var clip: AudioStream = pool.next_random()
	if clip == null or _contact_player == null:
		return
	_contact_player.stream = clip
	_contact_player.pitch_scale = 1.0 + randf_range(-enemy_data.pitch_jitter, enemy_data.pitch_jitter)
	_contact_player.volume_db = contact_volume_db + randf_range(-contact_volume_variance_db, contact_volume_variance_db)
	_contact_player.play()

func play_hit_recoil(from_direction: Vector3, distance: float, tilt_degrees: float, out_time: float, return_time: float) -> void:
	var away := Vector3(from_direction.x, 0.0, from_direction.z)
	away = away.normalized() if away.length() > 0.0001 else Vector3.BACK

	var base_position := global_position
	var base_tilt := rotation.x
	var recoil_position := base_position + away * distance
	var recoil_tilt := base_tilt + deg_to_rad(tilt_degrees)

	var tween := create_tween()
	_recoil_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", recoil_position, out_time)
	tween.parallel().tween_property(self, "rotation:x", recoil_tilt, out_time)
	tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", base_position, return_time)
	tween.parallel().tween_property(self, "rotation:x", base_tilt, return_time)
	# Struck inside a hit-stop: the recoil waits for it to end.
	if _hold_timer != null:
		tween.pause()
		_held_tweens.append(tween)

# A hit-stop on this body (a contact it gives or takes - BattleFeedback)
# for `seconds` of game time: what moves it holds where it is - its turn,
# hover, bob, flight, recoil and attack-lunge tweens pause, a recoil
# started during the stop waits for its end, and its attachment (claws,
# crest, wings) stops processing - then all of it plays on. Its flash,
# sound and slash mark run through it. A stop only ever extends the one
# running. Timed by a SceneTreeTimer, so under the probes' fixed frame
# rate it lasts the same frames every run.
func hold_for(seconds: float) -> void:
	if seconds <= 0.0 or _settling:
		return
	if _hold_timer != null and _hold_timer.time_left >= seconds:
		return
	if _hold_timer == null:
		for tween: Tween in [_recoil_tween, _attack_tween, _face_tween, _battle_turn_tween, _flight_tween, _hover_tween, _bob_tween]:
			if tween != null and tween.is_valid() and tween.is_running():
				tween.pause()
				_held_tweens.append(tween)
		if _attachment != null:
			_held_attachment_mode = _attachment.process_mode
			_attachment.process_mode = Node.PROCESS_MODE_DISABLED
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	_hold_timer = timer
	timer.timeout.connect(_end_hold.bind(timer))

# Whether a hit-stop holds this body now (hold_for()).
func is_held() -> bool:
	return _hold_timer != null

func _end_hold(timer: SceneTreeTimer) -> void:
	if timer != _hold_timer:
		return
	_hold_timer = null
	for tween in _held_tweens:
		if tween.is_valid():
			tween.play()
	_held_tweens.clear()
	if _attachment != null and is_instance_valid(_attachment):
		_attachment.process_mode = _held_attachment_mode

# A thin, unshaded, no-texture quad hanging at this enemy's own chest
# height, oriented so its local X axis (the one that actually gets
# scaled/animated) runs along from_direction (attacker -> this enemy,
# flattened) and its local Y axis runs along world UP - built via
# SurfaceTool rather than PlaneMesh/QuadMesh specifically so those two
# axes land exactly where named, not wherever either primitive's own
# default facing happens to put them (see ContactShadow's own doc on why
# QuadMesh's default facing wasn't trusted here either). Grows along X
# from ~0 to length over grow_time while fading its own alpha to 0 over
# fade_time, then frees itself - whichever of the two takes longer is
# what the mesh actually lives for.
func spawn_slash_mark(from_direction: Vector3, color: Color, length: float, width: float, chest_height: float, grow_time: float, fade_time: float) -> void:
	var attack_dir := Vector3(from_direction.x, 0.0, from_direction.z)
	attack_dir = attack_dir.normalized() if attack_dir.length() > 0.0001 else Vector3.FORWARD

	if _slash_mark_mesh == null:
		_slash_mark_mesh = _build_slash_quad_mesh()
	if _slash_mark_texture == null:
		_slash_mark_texture = _build_slash_gradient_texture()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _slash_mark_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _slash_mark_texture
	material.albedo_color = color
	material.disable_receive_shadows = true
	mesh_instance.material_override = material

	var x_axis := attack_dir
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	var mark_basis := Basis(x_axis, y_axis, z_axis)

	add_child(mesh_instance)
	mesh_instance.global_transform = Transform3D(mark_basis, global_position + Vector3.UP * chest_height)
	mesh_instance.scale = Vector3(0.001, width, 1.0)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale:x", length, grow_time)
	tween.tween_property(material, "albedo_color:a", 0.0, fade_time)
	tween.chain().tween_callback(mesh_instance.queue_free)

# A vertical-normal, XY-plane unit quad (X/Y each -0.5..0.5, normal +Z),
# built directly rather than relying on PlaneMesh/QuadMesh's own default
# facing - see spawn_slash_mark()'s own doc on why. UVs run 0..1 across
# both axes so _build_slash_gradient_texture()'s vertical gradient reads
# top-to-bottom regardless of how this quad is later scaled/oriented.
func _build_slash_quad_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_normal(Vector3(0.0, 0.0, 1.0))
	surface_tool.set_uv(Vector2(0.0, 1.0))
	surface_tool.add_vertex(Vector3(-0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 1.0))
	surface_tool.add_vertex(Vector3(0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 0.0))
	surface_tool.add_vertex(Vector3(0.5, 0.5, 0.0))
	surface_tool.set_uv(Vector2(0.0, 1.0))
	surface_tool.add_vertex(Vector3(-0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 0.0))
	surface_tool.add_vertex(Vector3(0.5, 0.5, 0.0))
	surface_tool.set_uv(Vector2(0.0, 0.0))
	surface_tool.add_vertex(Vector3(-0.5, 0.5, 0.0))
	return surface_tool.commit()

# Transparent -> opaque -> transparent along V (top to bottom, per
# spawn_slash_mark()'s own UVs) - the "vertical alpha gradient" the mark
# needs so its top/bottom edges read as soft rather than a hard-edged
# rectangle. 8px wide is enough since it's stretched uniformly across the
# mark's own fixed width, not sampled per-pixel-detail.
func _build_slash_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture

# A one-shot puff of flat, unshaded, no-texture quads in the ground's own
# color, kicked gently upward and outward from this enemy's own feet -
# same "read Ground.ground_color at the actual spawn point" source
# FootprintSpawner's footprints already use. process_mode is forced to
# ALWAYS since GPUParticles3D drives its own simulation per-frame (same
# reasoning as ContactShadow/the Wanderer's model needing it during
# RegionField's battle freeze) - a plain MeshInstance3D driven only by a
# Tween (see spawn_slash_mark()) doesn't need this, but this node's own
# advancement isn't a Tween.
# `tint` multiplies the ground colour the grains take (BattleFeedback.
# sand_puff_tint).
# `at`: where it bursts - the body's own place when INF (a mound's hit
# names its mound's).
func spawn_sand_puff(particle_count: int, lifetime: float, velocity: float, spread_degrees: float, tint: float = 1.0, at: Vector3 = Vector3.INF) -> void:
	if _ground == null:
		return

	var particles := GPUParticles3D.new()
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = false
	particles.one_shot = true
	particles.amount = particle_count
	particles.lifetime = lifetime
	particles.explosiveness = 1.0

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.12, 0.12)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var sand: Color = _ground.ground_color
	material.albedo_color = Color(sand.r * tint, sand.g * tint, sand.b * tint, sand.a)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mesh.material = material
	particles.draw_pass_1 = quad_mesh

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = spread_degrees
	process_material.initial_velocity_min = velocity * 0.5
	process_material.initial_velocity_max = velocity
	process_material.gravity = Vector3(0.0, -2.0, 0.0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.2
	particles.process_material = process_material

	add_child(particles)
	particles.global_position = global_position if at == Vector3.INF else at
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(particles.queue_free)

# The silt trickle off a buried body's mound (EnemyData.mound_trickle_*,
# read at each spill, so edits are live): a one-shot timer, rolled afresh
# after each. It stops with the field freeze on contact, skips its spill
# while the body is met or up out of the sand, and ends at defeat.
func _setup_trickle() -> void:
	if _mound == null or enemy_data == null:
		return
	_trickle_rng.randomize()
	_trickle_timer = Timer.new()
	_trickle_timer.name = "TrickleTimer"
	_trickle_timer.one_shot = true
	add_child(_trickle_timer)
	_trickle_timer.timeout.connect(_trickle)
	if not enemy_data.changed.is_connected(_arm_trickle):
		enemy_data.changed.connect(_arm_trickle)
	_arm_trickle()

func _arm_trickle() -> void:
	if _trickle_timer == null or not _trickle_timer.is_inside_tree():
		return
	var longest: float = maxf(enemy_data.mound_trickle_interval_min_s, enemy_data.mound_trickle_interval_max_s)
	if longest <= 0.0 or _defeated:
		_trickle_timer.stop()
		return
	_trickle_timer.start(maxf(_trickle_rng.randf_range(minf(enemy_data.mound_trickle_interval_min_s, longest), longest), 0.1))

func _trickle() -> void:
	if _mound != null and _mound.get_rise() > 0.5 and not _contacted and not _defeated:
		var reach: float = enemy_data.mound_trickle_reach
		var local := Vector2(
			_trickle_rng.randf_range(-reach, reach) * _mound.width_m * 0.5,
			_mound.get_crest_z() + _trickle_rng.randf_range(-reach, reach) * _mound.length_m * 0.5)
		spawn_sand_puff(enemy_data.mound_trickle_particles, enemy_data.mound_trickle_lifetime_s, enemy_data.mound_trickle_velocity, enemy_data.mound_trickle_spread_degrees, enemy_data.mound_trickle_tint, _mound.surface_point(local))
	_arm_trickle()

# Creatures have no clips to swing (unlike a card's own battle_animation),
# so this is their equivalent: a short lunge toward target and back,
# TWEEN_PAUSE_PROCESS'd through RegionField's own battle freeze same as
# every other in-battle tween here. Returns attack_snap_out_time - the
# point in the lunge BattleController._run_enemy_turn() awaits before
# reporting the hit - rather than the tween's own total duration, since
# the return leg keeps playing (cosmetically) after the hit has already
# landed. An attachment that winds up first (RearPose.play_windup(), the
# Siltjaw's Snap) holds the lunge back by its wind-up, and that is added
# to the wait. An attachment may lunge the body less than attack_snap_
# distance (UnderfootPose.get_lunge_distance() - its tail strikes, and
# its nose is close to its packmate's back).
func play_attack_snap(target: Node3D) -> float:
	if target == null:
		return 0.0

	var direction := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	direction = direction.normalized() if direction.length() > 0.0001 else -global_transform.basis.z

	var base_position := global_position
	var distance: float = attack_snap_distance
	if _attachment != null and _attachment.has_method("get_lunge_distance"):
		distance = float(_attachment.call("get_lunge_distance"))
	var lunge_position := base_position + direction * distance

	# The wings beat as the lunge starts (DragonflyWings.start_flap()).
	if _attachment != null and _attachment.has_method("start_flap"):
		_attachment.call("start_flap")
	var windup: float = 0.0
	if _attachment != null and _attachment.has_method("play_windup"):
		windup = float(_attachment.call("play_windup", attack_snap_out_time))

	var tween := create_tween()
	_attack_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if windup > 0.0:
		tween.tween_interval(windup)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", lunge_position, attack_snap_out_time)
	var lean: Callable = _attack_lean(direction)
	if lean.is_valid():
		tween.parallel().tween_method(lean, 0.0, 1.0, attack_snap_out_time)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", base_position, attack_snap_return_time)
	if lean.is_valid():
		tween.parallel().tween_method(lean, 1.0, 0.0, attack_snap_return_time)

	return windup + attack_snap_out_time

# The lean toward world `direction` (horizontal) as a tween method of 0
# (at rest) to 1 (attack_lean_degrees): the lean pivot turned about the
# base's edge facing `direction` - attack_lean_pivot_forward of the way
# out from the base's centre - so the top tips toward the target. An
# invalid Callable when this body doesn't lean.
func _attack_lean(direction: Vector3) -> Callable:
	if _lean_pivot == null or attack_lean_degrees <= 0.0 or _model_aabb.size == Vector3.ZERO:
		return Callable()
	var forward: Vector3 = global_transform.basis.orthonormalized().inverse() * direction
	forward.y = 0.0
	if forward.length() < 0.0001:
		return Callable()
	forward = forward.normalized()
	var aabb: AABB = get_model_aabb()
	var centre: Vector3 = aabb.get_center()
	var reach: float = absf(forward.x) * aabb.size.x * 0.5 + absf(forward.z) * aabb.size.z * 0.5
	var pivot := Vector3(centre.x, aabb.position.y, centre.z) + forward * reach * attack_lean_pivot_forward
	var axis: Vector3 = Vector3.UP.cross(forward).normalized()
	var full: float = deg_to_rad(attack_lean_degrees)
	return func(amount: float) -> void:
		var turn := Basis(axis, full * amount)
		_lean_pivot.transform = Transform3D(turn, pivot - turn * pivot)

# Called by region_field.gd on contact. Yaws to face target over duration,
# taking the short way around. RegionField's contact freeze stops nothing
# here (FieldEnemy has no _physics_process), but the tween still needs
# TWEEN_PAUSE_PROCESS to play through it, same as Wanderer.enter_battle_stance().
#
# Rotation only, deliberately - unlike Wanderer.enter_battle_stance(), this
# never repositions the enemy (contact happens wherever the enemy already
# stands), and its Y stays correct on its own via _ground_to_relief() (see
# _ready()/Ground.relief_rebuilt) regardless of when battle starts, so
# nothing here needs to re-sample terrain height itself.
func face_toward(target: Node3D, duration: float) -> void:
	if target == null:
		return
	face_toward_point(target.global_position, duration)

# The same yaw, to a world point - where the Wanderer is GOING to stand
# when a cluster's line puts him somewhere other than where contact
# happened (see RegionField._on_enemy_contacted()).
func face_toward_point(point: Vector3, duration: float) -> void:
	var to_target := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	if to_target.length() < 0.0001:
		return

	# Same verified direction<->angle convention as Wanderer._angle_from_
	# direction()/_forward_from_angle().
	var face_angle := atan2(-to_target.x, -to_target.z)
	_turn_to(face_angle, duration)

# One eased facing turn to `angle` the short way round, through the battle
# freeze. A turn still running - an escape's turn back caught by contact - is
# stopped first and the new one starts from wherever it had got to.
func _turn_to(angle: float, duration: float) -> void:
	if _face_tween != null and _face_tween.is_valid():
		_face_tween.kill()
	var target_angle := rotation.y + wrapf(angle - rotation.y, -PI, PI)
	_face_tween = create_tween()
	_face_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_face_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_face_tween.tween_property(self, "rotation:y", target_angle, duration)

# Called by RegionField on contact for a cluster member that isn't the
# one the Wanderer squares up to (see its _place_cluster_line()): tweens
# this body's XZ to `spot` over duration, through the battle freeze
# like face_toward(), with its Y sampled from the relief at the NEW spot
# (the relief callback only re-grounds at the current one). The pose it
# leaves is kept for return_to_field_pose(); a second step in the same
# fight (none today) keeps the first pose, not the stepped one.
func step_to(spot: Vector3, duration: float) -> void:
	# A flyer drops where it is first (short), then walks in - the step
	# waits that long, so the two never pull on the body at once.
	var delay: float = land_now()
	if not _has_field_pose:
		_field_position = global_position
		_field_yaw = rotation.y
		_has_field_pose = true
	if is_seated():
		climb_down_to(spot, duration)
		return
	_set_seated(false)
	_tween_to(spot, duration, delay)

# A seated rider off its carrier to `spot` over `duration`: its XZ eased
# there, its height from the seat down to the sand there, climb_hop_m
# over the carrier's side at the middle - a procedural move, no clip.
func climb_down_to(spot: Vector3, duration: float) -> void:
	_set_seated(false)
	var from: Vector3 = global_position
	var to := Vector3(spot.x, _body_y_on_ground(spot.x, spot.z), spot.z)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_climb_step.bind(from, func() -> Vector3: return to), 0.0, 1.0, maxf(duration, 0.01))

# One step of a climb: XZ eased from `from` to where `to_point` says now,
# the height eased between the two with climb_hop_m over it.
func _climb_step(t: float, from: Vector3, to_point: Callable) -> void:
	var to: Vector3 = to_point.call()
	var eased: float = smoothstep(0.0, 1.0, t)
	global_position = Vector3(lerpf(from.x, to.x, eased), lerpf(from.y, to.y, eased) + climb_hop_m * sin(t * PI), lerpf(from.z, to.z, eased))

# --- Riding (FloorEnemy.rides_on) ---

# Seated on `carrier` from now on: `offset` in its body frame - metres, x
# to its right, y up from its feet, z toward its back - turned
# `yaw_degrees` from its facing. It follows the carrier's grounding (its
# own _ground_to_relief() seats it instead of standing it on the sand)
# and casts no contact shadow of its own while it rides.
func ride_on(carrier: FieldEnemy, offset: Vector3, yaw_degrees: float) -> void:
	_carrier = carrier
	_ride_offset = offset
	_ride_yaw = deg_to_rad(yaw_degrees)
	_line_spot = global_position if is_inside_tree() else position
	_set_seated(carrier != null)
	if is_inside_tree() and _seated:
		_seat_on_carrier()

# Whether it rides on another member - seated now or not (a fight takes
# it down; the carrier is kept for an escape's climb back).
func is_riding() -> bool:
	return _carrier != null and is_instance_valid(_carrier)

func is_seated() -> bool:
	return _seated and is_riding()

func get_carrier() -> FieldEnemy:
	return _carrier if is_riding() else null

# Where its cluster's line takes it to be (RegionField._place_cluster_
# line()): where it stands - or, seated, its authored spot (a rider's
# position in its option), not the seat on its carrier.
func get_line_point() -> Vector3:
	return _line_spot if is_seated() else global_position

func _set_seated(on: bool) -> void:
	_seated = on
	if _contact_shadow != null:
		_contact_shadow.visible = not (on and is_riding())

# Where its body origin goes seated: the carrier's feet on the relief at
# its own XZ, the offset turned by its yaw, then this body's own grounding
# terms - as _body_y_on_ground() puts a standing body.
func get_seat_position() -> Vector3:
	if not is_riding():
		return global_position
	var carrier_origin := Vector3(_carrier.global_position.x, _carrier._body_y_on_ground(_carrier.global_position.x, _carrier.global_position.z), _carrier.global_position.z)
	var feet: Vector3 = carrier_origin + Vector3(0.0, _carrier.model_ground_offset, 0.0)
	var seat: Vector3 = feet + Basis(Vector3.UP, _carrier.rotation.y) * _ride_offset
	return seat + Vector3(0.0, -model_ground_offset + height_offset, 0.0)

func _seat_on_carrier() -> void:
	global_position = get_seat_position()
	rotation.y = _carrier.rotation.y + _ride_yaw

# Its phase come (RegionField._drop_at_phase()): off what it lies on to
# phase_drop_spot - sideways, height_offset down to the sand, a hop at
# the middle - a puff of sand as it lands, then a turn to `face_point`
# (the Wanderer). Once a fight; its spot and height are kept for an
# escape (return_to_field_pose()).
func drop_off(face_point: Vector3) -> void:
	if not has_phase_drop or _dropped:
		return
	_dropped = true
	if not _has_field_pose:
		_field_position = global_position
		_field_yaw = rotation.y
		_has_field_pose = true
	_field_height_offset = height_offset
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_drop_step.bind(Vector2(global_position.x, global_position.z), Vector2(phase_drop_spot.x, phase_drop_spot.z), height_offset, 0.0), 0.0, 1.0, maxf(phase_drop_seconds, 0.01))
	tween.tween_callback(func() -> void:
		spawn_sand_puff(phase_drop_puff_particles, phase_drop_puff_lifetime, phase_drop_puff_velocity, phase_drop_puff_spread_degrees, phase_drop_puff_tint)
		face_toward_point(face_point, phase_drop_turn_seconds))

# Where CameraRig's battle frame takes this body to stand: its own
# position, or - once it has dropped, with a frame spot set - that spot,
# at its own height (FloorEnemy.phase_drop_frame_offset).
func get_frame_position() -> Vector3:
	if _dropped and has_phase_drop_frame:
		return Vector3(phase_drop_frame_spot.x, global_position.y, phase_drop_frame_spot.z)
	return global_position

# Whether it has dropped off its rock this fight (drop_off()).
func has_dropped() -> bool:
	return _dropped

# One step of a drop (or an escape's climb back): XZ eased from `from` to
# `to`, height_offset from `height_from` to `height_to` with the hop over
# it - its setter puts the body on the relief at the new XZ.
func _drop_step(t: float, from: Vector2, to: Vector2, height_from: float, height_to: float) -> void:
	var xz: Vector2 = from.lerp(to, sin(t * PI * 0.5))
	global_position.x = xz.x
	global_position.z = xz.y
	height_offset = lerpf(height_from, height_to, smoothstep(0.0, 1.0, t)) + phase_drop_hop_m * sin(t * PI)

# The escape's counterpart: back to where it stood and faced before the
# fight, over duration. A body that never stepped stays where it is - and
# turns back to its prop if it faces one (the Wardling, his post). One
# that dropped off its rock climbs back onto it the way it came down.
func return_to_field_pose(duration: float) -> void:
	if _dropped:
		_dropped = false
		_has_field_pose = false
		var tween := create_tween()
		tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_method(_drop_step.bind(Vector2(global_position.x, global_position.z), Vector2(_field_position.x, _field_position.z), height_offset, _field_height_offset), 0.0, 1.0, maxf(duration, 0.01))
		_turn_to(_field_yaw, duration)
		return
	# A rider brought down for the fight climbs back up onto its carrier -
	# toward its seat as the carrier walks back too, so it lands where
	# the carrier ends.
	if is_riding() and not _seated:
		_has_field_pose = false
		var back := create_tween()
		back.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		back.tween_method(_climb_step.bind(global_position, get_seat_position), 0.0, 1.0, maxf(duration, 0.01))
		back.tween_callback(func() -> void:
			_set_seated(true)
			_seat_on_carrier())
		_turn_to(_carrier.rotation.y + _ride_yaw, duration)
		return
	if not _has_field_pose:
		if _faces_prop:
			_turn_to(_prop_yaw, duration)
		return
	_has_field_pose = false
	_tween_to(_field_position, duration)
	_turn_to(_field_yaw, duration)
	# A buried body's mound is sampled where it stands: again once it is
	# back (after a dig moved it).
	if _mound != null:
		var settle := create_tween()
		settle.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		settle.tween_interval(maxf(duration, 0.0))
		settle.tween_callback(_ground_to_relief)

# The XZ where this enemy stands when not stepped into a line - its
# authored spot - for anything that must clear its contact area after it
# has gone back there (RegionField._push_wanderer_away_from()).
func get_field_position() -> Vector3:
	return _field_position if _has_field_pose else global_position

func _tween_to(spot: Vector3, duration: float, delay: float = 0.0) -> void:
	var destination := Vector3(spot.x, _body_y_on_ground(spot.x, spot.z), spot.z)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "global_position", destination, duration)

# --- Flight (a patrolling pack member; see PackPatrol) ---

# Take off, cross to `spot` (world XZ) at `speed`, land there: the
# hover rises over rise_seconds, the crossing eases in and out, the
# descent takes land_seconds, and _on_landed() puts the feet on the
# relief. The tween is the default TWEEN_PAUSE_BOUND - the field's
# freeze holds a flyer in the air exactly where it was, and it carries
# on when the field thaws; a fight lands it first (see land_now()).
# Facing turns toward the travel direction as it goes.
func fly_to(spot: Vector3, hover: float, speed: float, rise_seconds: float, land_seconds: float) -> void:
	_kill_flight()
	_airborne = true
	contact_area.monitoring = false
	_set_wings_airborne(true)
	_flight_xz = Vector2(global_position.x, global_position.z)
	_hover = global_position.y - _body_y_on_ground(global_position.x, global_position.z)
	var target := Vector2(spot.x, spot.z)
	var distance: float = _flight_xz.distance_to(target)
	if distance > 0.0001:
		var direction: Vector2 = (target - _flight_xz) / distance
		# Same direction<->angle convention as face_toward_point().
		_flight_heading = atan2(-direction.x, -direction.y)
	var seconds: float = maxf(distance / maxf(speed, 0.01), 0.2)
	set_process(true)
	_flight_tween = create_tween()
	_flight_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_flight_tween.tween_property(self, "_hover", hover, rise_seconds)
	_flight_tween.set_ease(Tween.EASE_IN_OUT)
	_flight_tween.tween_property(self, "_flight_xz", target, seconds)
	_flight_tween.set_ease(Tween.EASE_IN)
	_flight_tween.tween_property(self, "_hover", 0.0, land_seconds)
	_flight_tween.tween_callback(_on_landed)

func is_airborne() -> bool:
	return _airborne

# A fight is starting and this member is in the air: the flight ends
# here, and the body drops straight down over battle_land_seconds -
# through the freeze (PAUSE_PROCESS, like every battle tween), since
# the field is already frozen by the time this is called. Returns how
# long the drop takes (0 for a body on the ground), so a step onto the
# battle line can wait for it (see step_to()).
func land_now() -> float:
	if not _airborne:
		return 0.0
	_kill_flight()
	_airborne = false
	set_process(false)
	_set_wings_airborne(false)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position:y", _body_y_on_ground(global_position.x, global_position.z), battle_land_seconds)
	tween.tween_callback(_restore_contact)
	return battle_land_seconds

func _on_landed() -> void:
	_airborne = false
	set_process(false)
	_ground_to_relief()
	_set_wings_airborne(false)
	_restore_contact()

func _restore_contact() -> void:
	contact_area.monitoring = true

func _kill_flight() -> void:
	if _flight_tween != null and _flight_tween.is_valid():
		_flight_tween.kill()
	_flight_tween = null

# --- A fight's hover (a flyer: battle_hover > 0) ---

# From the moment the battle frame settles (RegionField, on the same beat
# BattleOverlay reveals the intents) until the fight ends: the model
# rises to battle_hover above the sand over battle_rise_seconds and bobs
# battle_bob_m either way every battle_bob_seconds, on `phase` (radians -
# RegionField spreads a pack's members around the cycle so they never bob
# together), and the wings beat their flight beat the whole time
# (DragonflyWings.set_airborne()) with the lunge's flap on top. Every
# tween is PAUSE_PROCESS, through the fight's freeze. A no-op for a body
# that doesn't hover.
#
# A body sunk under a negative rest_height surfaces here the same way -
# the lift is the depth it was buried at, up to battle_hover (0: onto the
# sand) - without the bob or the wings, which are a flyer's.
#
# Hovering or not, an attachment that waits for the frame (UnderfootPose.
# enter_battle_frame() - its barb's first rise) hears of it here.
func enter_battle_hover(phase: float) -> void:
	if not _settling and not _defeated and _attachment != null and _attachment.has_method("enter_battle_frame"):
		_attachment.call("enter_battle_frame")
	if _hover_lift() <= 0.0 or _hovering or _settling or _defeated or _model == null:
		return
	_hovering = true
	_bob_phase = phase
	if _flies():
		_set_wings_airborne(true)
		_start_bob()
	_tween_hover(_hover_lift(), _flight_bob_weight(), battle_rise_seconds, Tween.EASE_OUT)

func is_battle_hovering() -> bool:
	return _hovering

# A fight that opens with this body dug in (EnemyData.opens_dug_in): in
# the fight's hover as enter_battle_hover() puts it, but left down under
# the sand - its first sight of the fight is its dig's row (begin_dig()),
# and it rises only when found or erupting (play_burrow()). Called before
# the frame settles, so enter_battle_hover() then raises nothing. A no-op
# for a body already hovering, leaving or dead.
func enter_battle_dug_in() -> void:
	if _hovering or _settling or _defeated or _model == null:
		return
	_hovering = true

# A win or an escape: back down to rest height over battle_settle_
# seconds, the bob fading out with the lift; the wings land at the end.
# Hovering or not, an attachment with a fight's pose of its own goes back
# to the field's (UnderfootPose.exit_battle_frame() - reburied, barb
# down).
func exit_battle_hover() -> void:
	# A dig's row goes with the fight; the body's own mound is its show.
	_end_dig_mounds()
	_dig_centre_set = false
	if not _settling and _attachment != null and _attachment.has_method("exit_battle_frame"):
		_attachment.call("exit_battle_frame")
	if not _hovering or _settling:
		return
	_hovering = false
	set_rearing(false)
	set_poised(false)
	var tween: Tween = _tween_hover(0.0, 0.0, battle_settle_seconds, Tween.EASE_IN_OUT)
	tween.tween_callback(_on_hover_landed)

func _on_hover_landed() -> void:
	if _hovering or _settling:
		return
	_kill_bob()
	_set_wings_airborne(false)

# The hover's lift above rest height.
func _hover_lift() -> float:
	return maxf(battle_hover - rest_height, 0.0)

# Only a body that leaves the sand in a fight flies - bobs, beats its
# wings. A buried one surfacing just rises.
func _flies() -> bool:
	return battle_hover > 0.0

func _flight_bob_weight() -> float:
	return 1.0 if _flies() else 0.0

# The Siltjaw's burial mid-fight (BattleController, on an interrupted
# charge and on the turn it comes back up): down to its field rest under
# the sand, or back up to its fight's surface, over burrow_seconds.
# Returns how long that takes, for the enemy turn to wait on - 0 for a
# body with nowhere to go (not in a fight's hover, or leaving).
func play_burrow(buried: bool) -> float:
	if not _hovering or _settling:
		return 0.0
	var lift: float = 0.0 if buried else _hover_lift()
	var bob_weight: float = 0.0 if buried else _flight_bob_weight()
	_tween_hover(lift, bob_weight, burrow_seconds, Tween.EASE_IN_OUT)
	return maxf(burrow_seconds, 0.0)

# --- The dig (EnemyIntent.IntentType.DIG) ---
#
# Where the body is under shows in one thing only - the tell on its mound
# (set_dig_tell()): the body goes under where it stands, then waits at the
# row's middle - the spot the fight's intent, HP bar, status row and camera
# all read off this node - until a mound is named for it to come up
# through (surface_at_mound()). Every mound is built, lit, shaped and
# hovered the same.

# Under the sand, and `count` mounds swell up in a row along `across`
# (the battle camera's own right, so the row reads left to right on
# screen, no mound behind another), dig_mound_spacing_m apart, each
# turned broadside to the row, its middle where the fight's first dig
# stood moved dig_row_toward_m toward `toward` (the Wanderer) - less, or
# away, until every mound keeps dig_wanderer_clear_m from him. Returns
# how long that takes, for the enemy turn to wait on.
func begin_dig(count: int, toward: Vector3, across: Vector3) -> float:
	_end_dig_mounds()
	# Where it stood, for an escape to bring it back to (return_to_field_
	# pose()) - the dig moves it to the row's middle.
	if not _has_field_pose:
		_field_position = global_position
		_field_yaw = rotation.y
		_has_field_pose = true
	var under: float = play_burrow(true)
	var flat := Vector3(across.x, 0.0, across.z)
	_dig_across = flat.normalized() if flat.length() > 0.0001 else global_transform.basis.x
	if not _dig_centre_set:
		var spot: Vector3 = global_position
		var to_him := Vector3(toward.x - spot.x, 0.0, toward.z - spot.z)
		var side: float = 1.0 if _dig_across.dot(to_him) >= 0.0 else -1.0
		var shift: float = dig_row_toward_m
		var floor_shift: float = -float(maxi(count, 1)) * dig_mound_spacing_m
		while shift > floor_shift and _row_nearest(spot + _dig_across * side * shift, count, toward) < dig_wanderer_clear_m:
			shift -= 0.1
		_dig_centre = spot + _dig_across * side * shift
		_dig_centre_set = true
	_dig_active = true
	for mound in count:
		var anchor := Node3D.new()
		anchor.name = "DigMound%d" % mound
		anchor.top_level = true
		add_child(anchor)
		var sand := SandMound.new()
		sand.name = "SandMound"
		anchor.add_child(sand)
		_dig_anchors.append(anchor)
	_place_dig_mounds()
	_shape_dig_mounds()
	# The row swells as the body sinks; once it is down it waits at the
	# middle.
	var rise: float = maxf(dig_mound_rise_seconds, 0.01)
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(_set_dig_rise, 0.0, 1.0, rise)
	tween.parallel().tween_callback(_move_body_to(_dig_centre)).set_delay(under)
	_set_dig_rise(0.0)
	# Its own mound - still up for a fight that opens dug in, flat for a
	# body digging from its surface - flattens as the row swells.
	if _mound != null and _mound.get_rise() > 0.0:
		_own_mound_tween = create_tween()
		_own_mound_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		_own_mound_tween.tween_method(_mound.set_rise, _mound.get_rise(), 0.0, rise)
	return maxf(under, rise)

# How near `toward` the nearest of a row of `count` centred on `centre`
# would stand, XZ.
func _row_nearest(centre: Vector3, count: int, toward: Vector3) -> float:
	var nearest: float = INF
	for index in count:
		var offset: float = (float(index) - float(count - 1) * 0.5) * dig_mound_spacing_m
		var at: Vector3 = centre + _dig_across * offset
		nearest = minf(nearest, Vector2(at.x - toward.x, at.z - toward.z).length())
	return nearest

func is_dug_in() -> bool:
	return _dig_active

# The top of its standing mounds on screen - all alike, so the centre
# one's while it stands - for its intent to sit over while it is dug in
# (BattleIntent). INF with none standing.
func get_dug_in_screen_top(camera: Camera3D) -> float:
	var top: float = INF
	for mound in _dig_anchors.size():
		var rect: Rect2 = get_mound_screen_rect(camera, mound, 0.0)
		if rect.has_area():
			top = minf(top, rect.position.y)
	return top

# The Dig's spray on (its Dig queued) or off - see the dig_spray exports.
func set_dig_spray(on: bool) -> void:
	if not on and _dig_spray == null:
		return
	if _dig_spray == null:
		_dig_spray = GPUParticles3D.new()
		_dig_spray.name = "DigSpray"
		_dig_spray.process_mode = Node.PROCESS_MODE_ALWAYS
		_dig_spray.emitting = false
		add_child(_dig_spray)
		_apply_dig_spray()
	_dig_spray.emitting = on

func _apply_dig_spray() -> void:
	if _dig_spray == null:
		return
	_dig_spray.amount = dig_spray_amount
	_dig_spray.lifetime = dig_spray_lifetime
	_dig_spray.explosiveness = 0.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.1, 0.1)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sand: Color = _ground.ground_color if _ground != null else Color(0.74, 0.70, 0.60)
	material.albedo_color = Color(sand.r * dig_spray_tint, sand.g * dig_spray_tint, sand.b * dig_spray_tint, sand.a)
	quad.material = material
	_dig_spray.draw_pass_1 = quad
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = dig_spray_spread_degrees
	process_material.initial_velocity_min = dig_spray_velocity * 0.4
	process_material.initial_velocity_max = dig_spray_velocity
	process_material.gravity = Vector3(0.0, -2.0, 0.0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.2
	_dig_spray.process_material = process_material
	_dig_spray.position = Vector3.ZERO

# Where mound `mound` stands, world (its anchor's), or the body's own
# place when there is no such mound.
func get_mound_position(mound: int) -> Vector3:
	var anchor: Node3D = _dig_anchor(mound)
	return anchor.global_position if anchor != null else global_position

# Mound `mound`'s screen rect, padded like get_screen_rect(): its own
# footprint and height, projected. Empty for a mound that isn't standing
# or reaches behind the camera.
func get_mound_screen_rect(camera: Camera3D, mound: int, padding_px: float) -> Rect2:
	var anchor: Node3D = _dig_anchor(mound)
	if camera == null or anchor == null:
		return Rect2()
	var half := Vector3(dig_mound_width_m * 0.5, 0.0, dig_mound_length_m * 0.5)
	var rect := Rect2()
	var first: bool = true
	for corner in [Vector3(-1, 0, -1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, 1)]:
		for lift in [0.0, dig_mound_height_m]:
			var world: Vector3 = anchor.global_transform * Vector3(half.x * corner.x, lift, half.z * corner.z)
			if camera.is_position_behind(world):
				return Rect2()
			var point: Vector2 = camera.unproject_position(world)
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect.grow(padding_px)

# The hover over one mound (-1: none) - the same light over whichever.
func set_mound_highlight(mound: int) -> void:
	if _dig_highlight_material == null:
		_dig_highlight_material = StandardMaterial3D.new()
		_dig_highlight_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dig_highlight_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_dig_highlight_material.albedo_color = dig_mound_highlight
	for index in _dig_anchors.size():
		var sand: SandMound = _dig_sand(index)
		if sand != null:
			sand.material_overlay = _dig_highlight_material if index == mound else null

# A hit on mound `mound`: it dips and springs back, and the sand takes the
# blade (see dig_mound_hit_dip) - the same on every mound.
func play_mound_hit(mound: int) -> void:
	var sand: SandMound = _dig_sand(mound)
	if sand == null:
		return
	var half: float = maxf(dig_mound_hit_seconds, 0.02) * 0.5
	var low: float = sand.get_rise() * (1.0 - clampf(dig_mound_hit_dip, 0.0, 1.0))
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_method(sand.set_rise, sand.get_rise(), low, half).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_method(sand.set_rise, low, 1.0, half).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_mound_hit_pool.set_clips(dig_mound_hit_clips)
	var clip: AudioStream = _mound_hit_pool.next_random()
	if clip != null and _contact_player != null:
		_contact_player.stream = clip
		_contact_player.pitch_scale = 1.0 + randf_range(-enemy_data.pitch_jitter, enemy_data.pitch_jitter)
		_contact_player.volume_db = contact_volume_db + dig_mound_hit_gain_db + randf_range(-contact_volume_variance_db, contact_volume_variance_db)
		_contact_player.play()

# A wrong mound, falling flat and gone. Returns how long it takes.
func collapse_mound(mound: int) -> float:
	var anchor: Node3D = _dig_anchor(mound)
	if anchor == null:
		return 0.0
	_dig_anchors[mound] = null
	var sand: SandMound = anchor.get_node_or_null(^"SandMound") as SandMound
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if sand != null:
		sand.material_overlay = null
		tween.tween_method(sand.set_rise, sand.get_rise(), 0.0, maxf(dig_mound_collapse_seconds, 0.01))
	tween.tween_callback(anchor.queue_free)
	return maxf(dig_mound_collapse_seconds, 0.0)

# The tell on mound `mound` (see the Dig tell exports): its slow settle
# and rise, every so often - once its row is up. Stops when the row goes.
func set_dig_tell(mound: int) -> void:
	_stop_dig_tell()
	var sand: SandMound = _dig_sand(mound)
	if sand == null:
		return
	_tell_mound = mound
	# The rise owns the mound until the row is up; a first breath after a
	# full interval, so the row never opens on it.
	var breathe := create_tween()
	breathe.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	breathe.tween_interval(maxf(dig_mound_rise_seconds, 0.0))
	breathe.tween_callback(_breathe.bind(sand))
	_tell_tweens.append(breathe)

func _breathe(sand: SandMound) -> void:
	if not is_instance_valid(sand):
		return
	var half: float = maxf(tell_breathe_seconds, 0.2) * 0.5
	var low: float = 1.0 - clampf(tell_strength, 0.0, 1.0)
	var breathe := create_tween()
	breathe.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	breathe.set_loops()
	breathe.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	breathe.tween_interval(maxf(tell_breathe_interval, 0.0))
	breathe.tween_method(sand.set_rise, 1.0, low, half)
	breathe.tween_method(sand.set_rise, low, 1.0, half)
	_tell_tweens.append(breathe)

func _stop_dig_tell() -> void:
	for tween in _tell_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_tell_tweens.clear()
	_tell_mound = -1

# Up through mound `mound` - found, or erupting on its own: the body moves
# under it, the row flattens and goes, and the body rises. Returns how
# long that takes.
func surface_at_mound(mound: int) -> float:
	if not _dig_active:
		return 0.0
	_stop_dig_tell()
	var spot: Vector3 = get_mound_position(mound)
	_move_body_to(spot).call()
	var flatten: float = maxf(burrow_seconds, 0.01)
	var anchors: Array[Node3D] = _dig_anchors.duplicate()
	_dig_anchors.clear()
	_dig_active = false
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	for anchor in anchors:
		if anchor == null:
			continue
		var sand: SandMound = anchor.get_node_or_null(^"SandMound") as SandMound
		if sand != null:
			sand.material_overlay = null
			tween.tween_method(sand.set_rise, sand.get_rise(), 0.0, flatten)
	tween.set_parallel(false)
	for anchor in anchors:
		if anchor != null:
			tween.tween_callback(anchor.queue_free)
	return play_burrow(false)

# The row gone at once - a new dig over an old one, a fight's end.
func _end_dig_mounds() -> void:
	_stop_dig_tell()
	if _own_mound_tween != null and _own_mound_tween.is_valid():
		_own_mound_tween.kill()
	_own_mound_tween = null
	for anchor in _dig_anchors:
		if anchor != null and is_instance_valid(anchor):
			anchor.queue_free()
	_dig_anchors.clear()
	_dig_active = false

func _dig_anchor(mound: int) -> Node3D:
	if mound < 0 or mound >= _dig_anchors.size():
		return null
	var anchor: Node3D = _dig_anchors[mound]
	return anchor if anchor != null and is_instance_valid(anchor) else null

func _dig_sand(mound: int) -> SandMound:
	var anchor: Node3D = _dig_anchor(mound)
	return anchor.get_node_or_null(^"SandMound") as SandMound if anchor != null else null

# Each mound at its place in the row - the middle one on the centre, the
# rest dig_mound_spacing_m apart either side - facing as the body does,
# and the sand under it sampled again.
func _place_dig_mounds() -> void:
	var count: int = _dig_anchors.size()
	for index in count:
		var anchor: Node3D = _dig_anchor(index)
		if anchor == null:
			continue
		var offset: float = (float(index) - float(count - 1) * 0.5) * dig_mound_spacing_m
		var spot: Vector3 = _dig_centre + _dig_across * offset
		if _ground != null:
			var local: Vector3 = _ground.to_local(spot)
			spot.y = _ground.to_global(Vector3(local.x, _ground.get_visible_height_at(Vector2(local.x, local.z)), local.z)).y
		# Broadside to the row: its width along it, its length across.
		anchor.global_transform = Transform3D(Basis(Vector3.UP, atan2(-_dig_across.z, _dig_across.x)), spot)
		var sand: SandMound = _dig_sand(index)
		if sand != null:
			sand.set_ground(_ground)
			sand.resample()

func _shape_dig_mounds() -> void:
	for index in _dig_anchors.size():
		var sand: SandMound = _dig_sand(index)
		if sand == null:
			continue
		sand.length_m = dig_mound_length_m
		sand.width_m = dig_mound_width_m
		sand.height_m = dig_mound_height_m
		sand.resample()

func _set_dig_rise(rise: float) -> void:
	for index in _dig_anchors.size():
		var sand: SandMound = _dig_sand(index)
		if sand != null:
			sand.set_rise(rise)

# The body to `spot` (XZ), on the sand there, its own mound sampled again
# where it now is - as a callable, for a tween to call when it's under.
func _move_body_to(spot: Vector3) -> Callable:
	return func() -> void:
		global_position = Vector3(spot.x, global_position.y, spot.z)
		_ground_to_relief()

func _tween_hover(lift: float, bob_weight: float, seconds: float, easing: Tween.EaseType) -> Tween:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	var duration: float = maxf(seconds, 0.001)
	_hover_tween = create_tween()
	_hover_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_hover_tween.set_trans(Tween.TRANS_SINE).set_ease(easing)
	_hover_tween.set_parallel(true)
	_hover_tween.tween_method(_set_lift, _lift, lift, duration)
	_hover_tween.tween_method(_set_bob_weight, _bob_weight, bob_weight, duration)
	_hover_tween.set_parallel(false)
	return _hover_tween

func _start_bob() -> void:
	_kill_bob()
	_bob_tween = create_tween()
	_bob_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_bob_tween.set_loops()
	_bob_tween.tween_method(_set_bob_angle, 0.0, TAU, maxf(battle_bob_seconds, 0.05))

func _kill_bob() -> void:
	if _bob_tween != null and _bob_tween.is_valid():
		_bob_tween.kill()
	_bob_tween = null

func _set_lift(value: float) -> void:
	_lift = value
	_apply_model_lift()

func _set_bob_weight(value: float) -> void:
	_bob_weight = value
	_apply_model_lift()

func _set_bob_angle(value: float) -> void:
	_bob_angle = value
	_apply_model_lift()

# The model at its grounded place plus rest height, hover and bob. Left
# alone once settling - the sink owns the model from then on.
#
# A buried body (rest height under the sand) is not seen at all while it
# is down: the model and its contact shadow are hidden and the mound
# (SandMound) shows instead. The same lift that raises the body flattens
# the mound - it falls as the body comes up through it, one motion, and
# swells back as the body goes under (play_burrow(), an escape's exit_
# battle_hover()).
func _apply_model_lift() -> void:
	if _model == null or _settling:
		return
	_model.position.y = _model_ground_y + get_body_lift()
	var surfaced: float = _surfaced_fraction()
	_model.visible = surfaced > 0.0
	if _contact_shadow != null:
		_contact_shadow.visible = surfaced > 0.0
	if _mound != null and not _dig_active:
		# Under a DIG's mounds the body's own mound is left to the dig
		# (begin_dig() flattens it): the row is all that shows.
		_mound.set_rise(1.0 - surfaced)

# How far a buried body is on its way up to its fight's surface: 0 down
# at rest height, 1 all the way up. 1 for a body that isn't buried.
func _surfaced_fraction() -> float:
	if rest_height >= 0.0:
		return 1.0
	var reach: float = _hover_lift()
	if reach <= 0.0:
		return 0.0
	return clampf(_lift / reach, 0.0, 1.0)

func _set_wings_airborne(on: bool) -> void:
	if _attachment != null and _attachment.has_method("set_airborne"):
		_attachment.call("set_airborne", on)

# Only while airborne (set_process() is switched with the flight): the
# body at the flight's XZ, hover above the relief THERE - so a crossing
# follows the ground's shape - turning toward its heading.
func _process(delta: float) -> void:
	if not _airborne:
		return
	global_position = Vector3(_flight_xz.x, _body_y_on_ground(_flight_xz.x, _flight_xz.y) + _hover, _flight_xz.y)
	rotation.y = lerp_angle(rotation.y, _flight_heading, clampf(delta * flight_turn_rate, 0.0, 1.0))

# The death (settle_and_free()), called by RegionField when it begins -
# once the blow that killed this enemy has shown in full (its
# _on_enemy_defeated()). The HP readout goes at once - a "0/45" hanging
# under a body that's leaving is a corpse in the line - an attachment
# that can fold drops its wings over settle_time, and then the body
# slumps a little and goes into the fog: the fog colour laid over it
# whatever the distance, so it loses its contrast rather than its
# opacity, while a few wisps of sand lift and drift off downwind; gone
# into the fog it dissolves out (dithered), says so (death_finished) and
# is freed - all through the battle freeze, like every tween here, and
# each part an export in the Settle group. Moves the MODEL rather than
# the body so the killing blow's own recoil (play_hit_recoil(), a tween on
# this body's global_position) never fights it - though the death only
# starts once that has played. The contact area goes with the node, so a
# fight the Wanderer re-contacts later can't include a member that isn't
# there.
func mark_defeated() -> void:
	_defeated = true

func is_defeated() -> bool:
	return _defeated

# On its way out through settle_and_free() - RegionField's win leaves a
# settling body to finish rather than freeing it outright.
func is_settling() -> bool:
	return _settling

func settle_and_free() -> void:
	if _settling:
		return
	_end_dig_mounds()
	_settling = true
	mark_defeated()
	set_highlight(false)
	if enemy_status != null and is_instance_valid(enemy_status):
		enemy_status.queue_free()
		enemy_status = null
	# A hovering body stops where it is - no more lift, no more bob - and
	# folds and falls from there.
	_hovering = false
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_kill_bob()
	if _model == null or _model_height <= 0.0:
		_finish_death()
		return
	_stop_hit_flash()
	var tween := create_tween()
	_death_tween = tween
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Wings first: an attachment that can fold takes settle_time to drop
	# its wings before the body goes.
	if _attachment != null and _attachment.has_method("fold"):
		_attachment.call("fold", settle_time)
		tween.tween_interval(settle_time)
	# The slump, from wherever it is (standing, or hovering in a fight) to a
	# little under its grounded place - overshooting and settling back
	# (TRANS_BACK) - and a small tilt; the fog over it and its shadow going
	# alongside; the sand lifting a beat in.
	tween.tween_callback(_begin_death_wisps)
	tween.set_parallel(true)
	tween.tween_property(_model, "position:y", _model_ground_y - _model_height * death_slump_depth, maxf(death_slump_time, 0.001)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_model, "rotation:z", _model.rotation.z + deg_to_rad(death_slump_tilt_degrees), maxf(death_slump_time, 0.001)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_method(_set_death_veil, 0.0, 1.0, maxf(death_fade_time, 0.001)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if _contact_shadow != null:
		tween.tween_property(_contact_shadow, "fade", 0.0, maxf(death_fade_time, 0.001))
	# Then, gone into the fog, it dissolves out and is freed.
	tween.set_parallel(false)
	tween.tween_callback(_begin_death_vanish)
	tween.tween_method(_set_death_presence, 1.0, 0.0, maxf(death_vanish_time, 0.001))
	tween.tween_callback(_finish_death)

# A click during a death (BattleController.skip_deaths()): straight to
# its end - the slump settled, the body gone, the node freed. The sand
# already lifting drifts on.
func skip_death() -> void:
	if _death_tween != null and _death_tween.is_valid():
		_death_tween.custom_step(1.0e6)

# Whether its death is running now (settle_and_free(), not yet finished).
func is_dying() -> bool:
	return _death_tween != null and _death_tween.is_valid()

# The hit flash, stopped where it is and its colours put back - its fall
# would otherwise write full opacity over the dissolve.
func _stop_hit_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	for index in _tint_materials.size():
		_set_tint(_tint_materials[index], _tint_base_colors[index])

# The fog colour over the whole body, distance aside (its fog pass's veil).
func _set_death_veil(value: float) -> void:
	for overlay in _fog_overlays:
		overlay.set_shader_parameter("veil", value)

# The last dissolve: every tinted surface dithered (alpha hash keeps them
# opaque-sorted, so nothing behind sorts wrong; a painted body dithers in
# its shader, by presence) and casting no shadow.
func _begin_death_vanish() -> void:
	for material in _tint_materials:
		if material is BaseMaterial3D:
			(material as BaseMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		(mesh_instance as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

# How much of the body is left: its surfaces' alpha and its fog pass's.
func _set_death_presence(value: float) -> void:
	for index in _tint_materials.size():
		var material: Material = _tint_materials[index]
		if material is ShaderMaterial:
			(material as ShaderMaterial).set_shader_parameter("presence", value)
			continue
		var color: Color = _tint_base_colors[index]
		color.a *= value
		_set_tint(material, color)
	for overlay in _fog_overlays:
		overlay.set_shader_parameter("presence", value)

func _begin_death_wisps() -> void:
	if death_wisp_delay > 0.0:
		get_tree().create_timer(death_wisp_delay).timeout.connect(spawn_death_wisps)
	else:
		spawn_death_wisps()

# A few wisps of sand lifting from where the body lies and drifting off
# downwind, fading (the Settle group's death_wisp_*): sand-coloured,
# death_wisp_fog_blend toward the fog, never brighter than the sand - no
# glow, no burst. On the field, not this node, so they outlive it; set to
# run through the battle freeze, and freed once the last has faded.
func spawn_death_wisps() -> void:
	if _ground == null or death_wisp_count <= 0 or not is_inside_tree():
		return
	var field := get_node_or_null(region_field_path) as RegionField
	var wind: Vector3 = field.get_wind_direction() if field != null else Vector3.RIGHT
	var sand: Color = _ground.ground_color
	if not _fog_overlays.is_empty():
		var fog: Color = _fog_overlays[0].get_shader_parameter("fog_color")
		sand = sand.lerp(fog, death_wisp_fog_blend)

	var particles := GPUParticles3D.new()
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = false
	particles.one_shot = true
	particles.amount = death_wisp_count
	particles.lifetime = death_wisp_lifetime
	particles.explosiveness = 1.0 - death_wisp_spread

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(death_wisp_size, death_wisp_size * 0.6)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	material.billboard_keep_scale = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mesh.material = material
	particles.draw_pass_1 = quad_mesh
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(_model_aabb.size.x, _model_aabb.size.y * 0.3, _model_aabb.size.z) * 0.35
	process_material.direction = (wind + Vector3.UP * 0.35).normalized()
	process_material.spread = 12.0
	process_material.initial_velocity_min = death_wisp_speed * 0.7
	process_material.initial_velocity_max = death_wisp_speed
	process_material.gravity = Vector3(0.0, death_wisp_lift, 0.0)
	process_material.damping_min = 0.1
	process_material.damping_max = 0.2
	process_material.scale_min = 0.7
	process_material.scale_max = 1.2
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.6))
	grow.add_point(Vector2(1.0, 1.4))
	var scale_texture := CurveTexture.new()
	scale_texture.curve = grow
	process_material.scale_curve = scale_texture
	var fade := Gradient.new()
	fade.set_color(0, Color(sand, 0.0))
	fade.set_color(1, Color(sand, 0.0))
	fade.add_point(0.15, Color(sand, death_wisp_alpha))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	process_material.color_ramp = ramp
	particles.process_material = process_material

	_wisp_parent().add_child(particles)
	particles.global_position = global_position + Vector3.UP * (_model_aabb.position.y + _model_aabb.size.y * 0.2)
	particles.emitting = true
	get_tree().create_timer(death_wisp_lifetime + 0.2).timeout.connect(particles.queue_free)

# Where a death's wisps live: the field, so they outlive this node - or
# its own parent, with no field to name.
func _wisp_parent() -> Node:
	var field := get_node_or_null(region_field_path)
	return field if field != null else get_parent()

# The death's end: said, then the node goes.
func _finish_death() -> void:
	death_finished.emit()
	queue_free()

# Deferred: body_entered is a physics callback, and the contact
# (RegionField._on_enemy_contacted()) freezes the field, taking its bodies
# out of the physics space - not allowed mid-callback. It goes out at the
# end of this frame instead; _contacted is set now, so a second body this
# frame queues nothing more.
func _on_body_entered(body: Node3D) -> void:
	# A dead body's area comes back into the space with the field's
	# unfreeze a beat before the node is freed - never a contact.
	if _contacted or _defeated or is_queued_for_deletion() or not body.is_in_group("wanderer"):
		return
	_contacted = true
	contacted.emit.call_deferred(self)

# Reset the once-only guard when the Wanderer leaves, so a return visit
# (e.g. after an ESCAPE push-back) can trigger contact again.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_contacted = false
