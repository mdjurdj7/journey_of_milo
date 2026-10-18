extends Resource
class_name CharacterData

# One character's own starting numbers - name, max HP, starting deck
# composition, the class passive, its reward pool and its field model. No
# class-select UI exists yet; RunState.new_run() is just handed one of
# these directly by whatever calls it (RegionField.starting_character, for
# now - see its own doc).
#
# Read once per run or per load: a run started already has its copy in
# RunState.character, and the field model is built when the floor loads,
# so an edit here takes effect on the next floor or run, never live.

@export var character_name: String = ""
@export var max_hp: int = 70

# CardData -> copy count: the run's starting Belongings. Keys are real
# CardData resource references (wired up in the Inspector), not path
# strings, so RunState._build_starting_deck() needs no load()/preload()
# at all to resolve them.
@export var starting_deck_counts: Dictionary = {}

# The weapon a run starts with (RunState.weapon, set by new_run()) - the
# one that modifies this class's basic attack (WeaponData).
@export var starting_weapon: WeaponData = null

# What a won fight, and any prop without a pool of its own, rolls from in
# this character's runs (RegionField.reward_pool()). Null = the floor's own
# FloorData.reward_pool - the Wanderer's case, whose pool every floor of
# Region 1 already names.
@export var reward_pool: RewardPool = null

# How much Grace one enemy turn can open, when several hits land in it -
# each at grace_open_fraction (below).
#   LARGEST_HIT - the biggest single unblocked hit of that turn.
#   SUM         - every unblocked hit added together.
enum GraceCapMode { LARGEST_HIT, SUM }

# --- Toll, the Wanderer's resource ---
#
# Whether self-inflicted HP loss accrues Toll (Combatant.gain_self_loss_
# toll()) and the battle HP readout shows its Toll block. Without it the
# loss still happens, just with no Toll, and nothing carries between
# floors.
@export var has_toll: bool = false

# --- Grace, the Wanderer's passive ---
#
# HP an enemy takes off you is partly not gone yet: grace_open_fraction of
# it (rounded down) becomes Grace, and damage you deal on your next turn
# takes that back 1:1. What you don't reclaim by the end of that turn is
# lost for good.
#
# Only unblocked ENEMY damage opens it - block and absorb eat their share
# first, and self-damage (Bite Down, a status tick) never opens any,
# because that is a price you chose. Reclaimed HP generates no Toll: Toll
# only ever comes from self-inflicted loss, so there is nothing to undo.
#
# Replaces the Rally passive, which was the same idea at 50% of the
# largest hit per CARD rather than 1:1 per turn - see DESIGN.md.
@export var has_grace: bool = false
@export var grace_cap_mode: GraceCapMode = GraceCapMode.LARGEST_HIT
# How many of the player's turns the window stays open for. 1 is "your
# next turn, then it's gone".
@export var grace_window_turns: int = 1
# The share of an unblocked enemy hit that opens as Grace, rounded down:
# 0.5 turns a 10 damage hit into 5 recoverable HP. The window's cap (the
# largest hit, or the turn's sum - grace_cap_mode) scales the same way.
@export_range(0.0, 1.0, 0.05) var grace_open_fraction: float = 0.5

# --- Devour, the Wanderer's battle action ---
#
# Whether the battle offers Devour (BattleController.devour()): its button
# over the energy readout, and an unplayable card arming for it. Without
# it there is no button and nothing reaches the action.
@export var has_devour: bool = false

# Critical: HP at or below this fraction of max HP. What the Critical
# cards (Cornered, Unbroken, Last Wager, Dying Light, Refuse the End, Last
# Resort) read - see Combatant.is_critical_at(). 0.3 is a playtest
# starting point, not a settled number.
@export_range(0.0, 1.0, 0.01) var critical_hp_fraction: float = 0.3
# Whether the HP readout draws Critical - the line across the bar at
# critical_hp_fraction and the numeral's turn to critical_color (HPBar).
# Display only: the rule still holds for every class, so a keepsake that
# reads Critical (Blue Fastener) keeps working without it.
@export var shows_critical: bool = false

# The most Toll this character takes to the next floor: Toll carries in
# full between a floor's fights, and the floor advance keeps min(Toll,
# this) (RunState.carry_toll()). In a fight Toll runs free.
@export var toll_carry_cap: int = 5

# --- Field model ---
#
# The body the Wanderer node wears on the field (Wanderer._ready()) - every
# class walks as that same node, only the model differs. A path, loaded at
# runtime. A model with no Skeleton3D is a static body: it slides as he
# walks, with no clips, sword, footprints or footsteps.
@export_file("*.glb", "*.gltf", "*.tscn", "*.fbx") var field_model_path: String = ""
# The painted shader's albedo. Null = the model's own imported base colour
# (its first mesh material's albedo_texture).
@export var field_albedo: Texture2D = null
# The yaw that turns the model's own front to the body's -Z: 180 for a
# model that faces +Z, as Mixamo rigs and glTF exports do.
@export var field_model_yaw_degrees: float = 180.0
# The height the model is scaled to, by its own AABB (Wanderer.
# target_height's per-character value).
@export var field_model_height: float = 1.8
