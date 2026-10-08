extends Node3D
class_name RegionField

const BATTLE_OVERLAY_SCENE_PATH := "res://battle/battle_overlay.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
const RUN_END_SCENE_PATH := "res://run/run_end.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const BATTLE_THEME_PATH := "res://ui/battle_theme.tres"
const FIELD_ENEMY_SCENE_PATH := "res://field/field_enemy.tscn"
const PROPS_NODE_NAME := "Props"

# Emitted once, when the last REQUIRED enemy (FloorEnemy.required) is
# defeated - see _on_battle_finished()'s own WIN branch and _required_
# enemy_remains(). Opens the ExitGate. An optional fight won afterwards
# doesn't emit it again.
signal floor_cleared

# This scene is the REGION: sea, sky, light, tower, HUD. Which floor of it
# is standing is data - region.floors[RunState.current_floor_index], a
# FloorData (see floors/floor_data.gd) read once per scene load. Its
# landmass and spawn go onto Ground/Wanderer in _enter_tree() (before any
# child's _ready() can read them - see that method's own doc), its
# enemies and props are spawned in _ready(), and everything else (gate,
# wear, rewards) reads get_floor_data() where it needs it. A floor change
# is a scene reload with the index advanced - see _on_floor_exited().
@export var region: RegionData = null

@export var escape_push_distance: float = 4.0
# How far past every enemy's contact_radius the escape push must land the
# Wanderer - the push grows past escape_push_distance until it does (see
# _push_wanderer_away_from()).
@export var escape_clearance_margin: float = 0.5

# Where a won fight's reward is offered. SCREEN is the interim static
# list; WORLD is the three cards laid on the sand where the enemy fell
# (RewardSpread, kept and still working - see DESIGN.md). One or the
# other, never both.
enum RewardMode { SCREEN, WORLD }
@export var reward_mode: RewardMode = RewardMode.SCREEN
@export var reward_screen_scene_path: String = "res://battle/reward_screen.tscn"
@export var reward_spread_scene_path: String = "res://field/reward_spread.tscn"
# What a BundleProp opens into (see _open_loot_screen()).
@export var loot_screen_scene_path: String = "res://battle/loot_screen.tscn"
# What a BelongingsCache opens into (see open_belongings_screen()).
@export var belongings_screen_scene_path: String = "res://battle/belongings_screen.tscn"
@export var collector_screen_scene_path: String = "res://battle/collector_screen.tscn"
@export var wagon_screen_scene_path: String = "res://battle/wagon_screen.tscn"
# What a keepsake is offered in (see open_keepsake_offer()).
@export var keepsake_offer_scene_path: String = "res://battle/keepsake_offer.tscn"
# The run log (RunLogger - one JSON-lines file per run under user://runs/).
# Never touches play; off, nothing is written. A headless instance never
# logs, whatever this says - see RunLogger.
@export var run_logging_enabled: bool = true:
	set(value):
		run_logging_enabled = value
		RunLogger.enabled = value
# Leaving the region's last floor ends the run, won (RunEnd); on, it goes
# round to floor 1 again instead and counts a lap - endless laps, for
# testing. Read at the exit, so a Remote-tab change holds from the next.
@export var loop_region_after_last_floor: bool = false

# Debug builds only: the field's F1 row and its Keepsake button, which
# grants these in turn (see _on_debug_keepsake_pressed()). Paths, loaded
# at the press.
@export var debug_keepsake_paths: PackedStringArray = PackedStringArray([
	"res://run/keepsakes/bent_nail.tres",
	"res://run/keepsakes/white_shell.tres",
	"res://run/keepsakes/frayed_cord.tres",
	"res://run/keepsakes/worn_page.tres",
])
# Debug builds only: the folders the F1 row's card picker lists - every
# CardData .tres in each, sorted by card name. Listed through
# ResourceLoader.list_directory(), which reports an exported build's
# .tres.remap entries under their original names.
@export var debug_card_dirs: PackedStringArray = PackedStringArray([
	"res://cards/data/",
	"res://cards/neutral/",
]):
	set(value):
		debug_card_dirs = value
		if _debug_card_picker != null:
			_debug_card_picker.clear()
			if _debug_row.visible:
				_fill_debug_card_picker()
@export var debug_row_position: Vector2 = Vector2(520.0, 40.0):
	set(value):
		debug_row_position = value
		if _debug_row != null:
			_debug_row.position = debug_row_position
# Held back until the battle framing has gone: the cards should appear on
# an ordinary field view, not under the battle camera mid-swing-out.
# Raised to the camera rig's own battle_transition_time when that's
# longer, so retuning the blend doesn't leave this stale.
@export var reward_spread_delay_sec: float = 0.6
# A fight with an elite in it (EnemyData.is_elite) pays the floor's gold
# roll times this, rounded. Read when the reward screen opens.
@export var elite_gold_multiplier: float = 1.5

# Playable boundary, centered on origin. X = width (left/right side
# edges), Y-component of field_extents = depth along the field's
# forward axis (see get_forward() below — not assumed to be +Z).
@export var field_extents: Vector2 = Vector2(80.0, 50.0)
@export var wall_height: float = 6.0
@export var wall_thickness: float = 2.0
# How far below y=0 every boundary wall extends. Walls used to start at
# y=0, but in water the ground sits at sea_level - landmass_below_sea_depth
# (-1.7 in this scene) - the Wanderer's 1.8m capsule then overlaps a y=0
# wall bottom by centimetres, and a relief dip takes even that away and
# lets them walk underneath. Sized to clear the deepest water plus a
# margin; see _add_wall().
@export var wall_sink: float = 4.0
# Sea and Tower are RegionField's own children, not siblings — paths
# must be direct child names ("Sea"/"Tower"), not "../Sea"/"../Tower".
# RegionField is the scene root, so "../" either finds nothing (edited
# standalone) or looks under the engine's own root Window (run as the
# main scene) — get_node_or_null("../Sea") is null either way, verified
# empirically. sea_path was already like this before this change; fixed
# alongside tower_path since both are exactly this bug.
@export var sea_path: NodePath = ^"Sea"
@export var shoreline_wall_margin: float = 5.0
# The landmark - read only by the threshold look (_on_floor_exited()),
# never for direction: see forward_marker_path.
@export var tower_path: NodePath = ^"Tower"
# What defines the field's forward: spawn -> this marker, XZ (see
# get_forward()). A bare Marker3D, so the direction the floor runs in is
# authored on its own and the Tower is free to stand wherever the frames
# want it. -Z today.
@export var forward_marker_path: NodePath = ^"ForwardMarker"
@export var camera_rig_path: NodePath = ^"CameraPivot"
@export var directional_light_path: NodePath = ^"DirectionalLight3D"
@export var exit_gate_path: NodePath = ^"ExitGate"
@export var sky_path: NodePath = ^"WorldEnvironment"

@export_group("Floor Transition")
# Where the floor ends: the ExitGate's own TriggerArea, this far along
# the floor's exit_direction past the gate line (ExitGate.trigger_
# forward_offset) - two steps onto the surfaced bar and the floor ends.
# Its width is fitted to the land at that line (ExitGate.fit_trigger_to_
# land()). On the tutorial floor (gate at z -16.7) the line is z -19.2;
# on floor 2 (gate at z -23) z -25.5.
@export var transition_distance: float = 2.5
# The look up: the field camera lifts its eyes to the tower over this
# long (CameraRig.look_up()) before the fade begins.
@export var look_up_seconds: float = 0.6
# The fade to the fog colour, and the fade back on the new floor - each
# this long (FloorFade).
@export var fade_seconds: float = 0.8
# A WorldCard lying on the sand (a FloorProp whose scene is world_card.
# tscn) sits this far above the relief - the quad is flat and would
# z-fight the sand at exactly ground height. Same value RewardSpread uses.
@export var world_card_ground_clearance: float = 0.02
# Where the Wanderer's feet are set when the floor's ground is first
# built: this far above the relief at spawn, so the capsule never starts
# inside the heightmap (it used to start at y 0 with the sand at ~0.27,
# leaving the first physics step to push it out - upward if it felt like
# it). See _on_ground_built().
@export var spawn_ground_clearance: float = 0.05
# A LINE floor's exit (FloorData.exit_kind): each time the Wanderer comes
# to rest at the gate line with a required fight still standing, he looks
# back at the nearest one (Wanderer.look_back_toward()). The first time
# in a run, this world-voice line is said over him as well (Wanderer.
# get_head_height() plus the clearance, via WorldVoiceLine.show_line_
# near()), held this long - never again that run (_hold_line_spoken,
# reset by RunState.new_run()); after that the look back carries it.
# Empty = no line.
@export var hold_line_world_line: String = "Not with that still behind him."
@export var hold_line_world_line_seconds: float = 3.0
@export var hold_line_world_line_head_clearance: float = 0.35
@export_group("")

# An enemy's own world-voice lines (its pain turn's - EnemyData.pain_turn_
# line - and its defeat's): said near it, this far above its head, held
# this long.
@export_group("Enemy Lines")
@export var enemy_world_line_seconds: float = 3.0
@export var enemy_world_line_head_clearance: float = 0.35
@export_group("")

# See hold_line_world_line - per run, not per floor or per scene load (a
# floor change is a reload).
static var _hold_line_spoken: bool = false

static func reset_hold_line_spoken() -> void:
	_hold_line_spoken = false

# The zone intro node (ZoneIntro, a child of this scene, process ALWAYS):
# the opening shot a new run's first floor plays before the field is
# handed over - see _ready()'s tail and ZoneIntro's own doc. Absent, or
# its zone_intro_enabled off, the floor starts plain.
@export var zone_intro_path: NodePath = ^"ZoneIntro"

# The follow camera's inland bound (see CameraRig.set_inland_limit()):
# the look target stops this far along the exit direction from the gate
# line - negative is before the gate (-4: the camera stops four metres
# short of it and the Wanderer walks up the frame onto the bar and to
# the trigger), 0 the gate line itself - or, with the override on, at a
# fixed z regardless of where the gate landed. Re-applied live by each
# setter.
@export var camera_inland_limit_offset_m: float = -4.0:
	set(value):
		camera_inland_limit_offset_m = value
		_apply_camera_inland_limit()
@export var camera_inland_limit_override_enabled: bool = false:
	set(value):
		camera_inland_limit_override_enabled = value
		_apply_camera_inland_limit()
@export var camera_inland_limit_override_z: float = 0.0:
	set(value):
		camera_inland_limit_override_z = value
		_apply_camera_inland_limit()
@export var battle_spacing: float = 3.0
# The Wanderer's stance keeps battle_spacing from the anchor unless that
# puts him within stance_dry_margin_m of the water; then it is pulled in
# along the same line toward the pack, never closer than
# battle_spacing_min (see _dry_stance_spacing()). Where even that is wet,
# a cluster's whole line steps inward along itself, up to
# battle_line_shift_max, until it isn't (see _place_cluster_line()).
# The minimum keeps him outside the anchor's contact reach (its 2.0 m
# contact_radius plus his own 0.4 m body): standing inside it through
# the fight, the thaw after an escape would take him for a fresh contact
# before the escape's push had moved him.
@export var stance_dry_margin_m: float = 0.5
@export var battle_spacing_min: float = 2.5
@export var battle_line_shift_max: float = 2.0
# Metres between the members of a cluster along the line they step into
# for a fight (see _place_cluster_line()) - read at contact, so a Remote-
# tab edit takes on the next fight.
@export var cluster_member_gap: float = 1.3
# Which of BattleTheme's two value sets the overlay applies on entering
# battle - see ui/battle_theme.gd's own rule: UI is the dark element on a
# pale world (false, default) and the pale element on a dark one (true).
@export var ui_on_dark_world: bool = false
# The field HUD row's one style - every size, gap, alpha and timing of
# DECK, HP, TOLL, GOLD, GLASSBONE and the keepsake (see HudRowStyle). Its
# own fields re-lay the row live; a new resource here is handed to every
# item at once. Empty = HudRowStyle's defaults.
@export var hud_row_style: HudRowStyle = null:
	set(value):
		hud_row_style = value
		_apply_hud_row_style()

@export_group("Ambience Duck")
# On enemy contact the Ambience bus (both beds: sea and wind) comes down
# by ambience_duck_db over the camera's battle swing (CameraRig.battle_
# transition_time), and comes back over the swing out on a win or an
# escape; a loss puts it straight back before the scene changes, and
# every floor load writes ambience_bus_base_db outright, since the bus
# is global and keeps whatever the last scene left on it. The base must
# be the bus's authored level in default_bus_layout.tres (0).
@export var ambience_duck_db: float = -4.0
@export var ambience_bus_base_db: float = 0.0
@export_group("")

@export var ground_path: NodePath = ^"Ground"

# How far past the (worst-case, noise-included) shoreline the side walls
# sit - lets the Wanderer wade a few metres in before being stopped, same
# shape as shoreline_wall_margin already does on the seaward side. See
# _rebuild_boundary_walls()'s own doc for how "worst-case" is computed
# from Ground's own landmass exports.
@export_group("Pathing")
# The walk grid (NavGrid): its cell, the margin every obstacle is grown by
# (his radius plus a clearance), how deep water has to be before it is
# never planned through, and what a shallow cell costs against a dry one.
# Each rebuilds the grid live.
@export var nav_cell_size: float = 0.35:
	set(value):
		nav_cell_size = maxf(value, 0.1)
		_queue_nav_build()
@export var nav_agent_radius: float = 0.4:
	set(value):
		nav_agent_radius = value
		_queue_nav_build()
@export var nav_clearance: float = 0.1:
	set(value):
		nav_clearance = value
		_queue_nav_build()
@export var nav_deep_water_depth_m: float = 0.6:
	set(value):
		nav_deep_water_depth_m = value
		_queue_nav_build()
@export var nav_shallows_cost: float = 6.0:
	set(value):
		nav_shallows_cost = value
		_queue_nav_build()
# The margin an enemy's contact zone is grown by when a path goes round it.
@export var nav_contact_margin: float = 0.5
# Stuck on a planned walk (Wanderer.path_stuck): planned again from where
# he stands, up to this many times in a row before he stops.
@export var nav_max_replans: int = 2
# Chasing an enemy that moves (a patrol): the path to it is planned again
# this often.
@export var nav_chase_replan_sec: float = 0.5
# Hold to move (left button held after a press on the ground): the walk
# follows the cursor's ground point, planned again at most this often and
# only once the point has moved this far.
@export var hold_replan_sec: float = 0.15
@export var hold_replan_dist: float = 0.5
@export_group("")

@export var side_wade_margin: float = 4.0:
	set(value):
		side_wade_margin = value
		_rebuild_boundary_walls()

# Wading costs HP: draining while the Wanderer stands past the landmass's
# own shoreline (see Ground.get_landmass_distance()'s own doc - this reads
# the exact same noised distance field the visual shoreline is drawn from,
# not an independent approximation of it). No push-back, no floor -
# RunState.lose_hp() already floors at 0, which is exactly the lethal
# behavior this wants. Gated on wade_drain_enabled, which the floor sets
# (FloorData.wade_drain_enabled, pushed in _enter_tree()) - the scene's own
# value only holds until a floor is read.
@export var wade_drain_enabled: bool = false
# distance_in_water (Ground.get_landmass_distance(), floored at 0) is a
# horizontal distance past the shoreline, not a real vertical depth - this
# fakes an outward slope: effective_depth = distance_in_water *
# wade_slope_per_metre.
@export var wade_slope_per_metre: float = 0.15
# Below this effective depth, no drain at all (ankle-deep is free).
@export var wade_depth_threshold: float = 0.05
@export var wade_drain_rate_per_metre: float = 30.0
@export var wade_drain_max_per_second: float = 15.0

@export_group("Point To Move")
# A click on the field sends the Wanderer walking (see Wanderer.
# set_move_target()). An enemy is picked first, by its projected model
# rect grown by this much (FieldEnemy.get_screen_rect(), the same test
# the armed-card targeting uses); otherwise a physics ray from the camera
# through the cursor, this long, against every body but the Wanderer -
# ground, hull, wall alike, the hit point is the target. Clicks the HUD
# swallows (DeckPanel, WorldVoiceLine's band) never get here.
@export var click_target_padding_px: float = 16.0
@export var click_ray_length: float = 1000.0

@onready var wanderer: Wanderer = $Wanderer
@onready var battle_layer: CanvasLayer = $BattleLayer
@onready var deck_panel: DeckPanel = $FieldHUD/DeckPanel
@onready var hp_bar: HPBar = $FieldHUD/HPBar

var _forward: Vector3 = Vector3.FORWARD
# The field HUD row's InkLines after DECK, in order - see _setup_field_hud().
var _hud_row_lines: Array[InkLine] = []
var _forward_computed: bool = false

# The floor this scene load is playing - see get_floor_data().
var _floor: FloorData = null
var _floor_resolved: bool = false
# Set by _on_floor_exited() for the rest of this scene's life: the
# trigger can't fire twice while the field stands frozen, but nothing
# here should depend on that.
var _transitioning: bool = false

# Cached once by _build_boundary() and reused by _rebuild_boundary_walls() -
# field_extents/wall_thickness/forward/shoreline_wall_margin/sea_edge_
# distance never change live, so this can't go stale. Also guards that
# export setter against firing during scene deserialization, before
# _forward/Sea are resolved - same reasoning as ExitGate's own _ready_done
# flag.
var _boundary_ready: bool = false
var _boundary_half_width: float = 0.0
var _boundary_inland_z: float = 0.0
var _boundary_shoreward_z: float = 0.0
var _boundary_span_center_z: float = 0.0
var _boundary_span_length: float = 0.0

var _wall_inland: StaticBody3D = null
var _wall_shoreward: StaticBody3D = null
# Where the Wanderer can walk (NavGrid), built from this floor's data once
# the relief and everything on it stand - see _build_nav_grid().
var _nav: NavGrid = null
var _nav_build_queued: bool = false
# Debug builds: the F1 row's Path draw, made on its first toggle.
var _nav_debug: NavDebugDraw = null
# The walk in progress, for a replan: where to, and after whom.
var _nav_goal: Vector3 = Vector3.INF
var _nav_goal_enemy: FieldEnemy = null
var _nav_replans: int = 0
var _nav_chase_timer: float = 0.0
# Hold to move: the left button went down on the ground and is still held.
var _holding: bool = false
var _hold_point: Vector3 = Vector3.INF
var _hold_timer: float = 0.0
var _wall_left: StaticBody3D = null
var _wall_right: StaticBody3D = null
# The walls' centre-line rectangle, kept for get_wall_rect().
var _wall_rect: Rect2 = Rect2()

# Fractional HP carried between physics frames so a slow drain (a couple
# HP/sec) still costs whole HP over time instead of rounding away to
# nothing every frame - see _physics_process()'s own doc.
var _wade_drain_accumulator: float = 0.0
# Set once RunState.player_hp reaches 0 from wading, so a scene change
# already in flight (change_scene_to_file doesn't happen mid-frame) can't
# be re-triggered by another drain tick before it lands.
var _run_lost_to_wading: bool = false
# Set by _end_run_lost(): a lost run fades once, whatever else asks.
var _run_ending: bool = false

# The click mark, created on first use - see ClickMarker.
var _click_marker: ClickMarker = null

# The Ambience bus's running duck/return - see _duck_ambience().
var _ambience_tween: Tween = null

# The bundle window open beside a bundle, if any - one at a time.
var _loot_screen: LootScreen = null

# The fight in progress, from _on_enemy_contacted() to _on_battle_
# finished(): its guard (a second contact while one is open is ignored,
# loudly), the enemies it holds (in the order the battle layer got them -
# the first is the one the Wanderer squares up to), and where the last
# of them fell, snapshotted at the kill so the reward can land there
# after the body is gone.
var _battle_open: bool = false
# The Wanderer's distance from the anchor's CURRENT spot to his stance,
# as _place_cluster_line() settled it (the line may have stepped the
# anchor inward) - read by the contact handler straight after.
var _line_stance_spacing: float = 0.0
var _battle_members: Array[FieldEnemy] = []
var _last_fallen_at: Vector3 = Vector3.ZERO
var _last_fallen_data: EnemyData = null
# Every enemy killed in the fight in progress - what a keepsake drop is
# rolled from on the win (_roll_keepsake_drop()). Cleared as each fight
# ends, whatever the outcome.
var _fight_fallen: Array[EnemyData] = []
# A keepsake rolled on the last win, waiting for the normal reward to
# close before it's offered (_open_pending_keepsake_offer()).
var _pending_keepsake: TrinketData = null
# Who left it - the enemy's name, for the offer's quiet source line.
var _pending_keepsake_source: String = ""
# Glassbone the last win left (EnemyData.glassbone_reward, summed over
# everyone it was won against), waiting for the reward screen to offer it
# as its own TAKE line. Handed over and zeroed as the screen opens.
var _pending_glassbone: int = 0
# The fight in progress has an elite in it (EnemyData.is_elite): elite
# gold, and its card rolled at the elite rarity rates. A member placed
# with FloorEnemy.CardReward.TOP_TIER_FIRST (the region-end fight) offers
# its cards from the highest tier down instead (RewardPool.roll_top_
# tier()). Set as the fight starts, from every member; carried to the
# last win's reward in the _pending_ pair, as the Glassbone is.
var _fight_elite: bool = false
var _fight_top_tier: bool = false
var _pending_elite: bool = false
var _pending_top_tier: bool = false
var _floor_cleared_emitted: bool = false
# Debug builds only (_setup_debug_row()): the field's F1 row, and which
# of debug_keepsake_paths its button grants next.
var _debug_row: HBoxContainer = null
var _debug_keepsake_button: Button = null
var _debug_keepsake_index: int = 0
# The row's card picker, filled from debug_card_dirs the first time the
# row shows.
var _debug_card_picker: OptionButton = null
# One PackPatrol per FloorData.patrols entry - see _spawn_floor_patrols().
var _patrols: Array[PackPatrol] = []

# Parent-first, before any child has entered the tree or run its
# _ready(): the one moment the floor's landmass and spawn can be put onto
# Ground and the Wanderer such that Ground's own _ready() builds the right
# relief and Sea/Ground read the right spawn - _ready() is bottom-up (see
# get_forward()'s own doc), so it is already too late there. Ground's
# setters store the values without rebuilding until its _ready_done, and
# the Wanderer's local position IS its world position (this node sits at
# the origin), so nothing here needs the tree. The spawn faces the floor's
# exit_direction - same rotation.y = atan2(-dir.x, -dir.z) convention
# FieldEnemy.face_toward()/Wanderer._angle_from_direction() use.
#
# The Wanderer is then HELD (process mode disabled - its body leaves the
# physics space, disable_mode REMOVE) until Ground says its first build is
# done: relief_rebuilt, connected here, before Ground's _ready() emits it.
# Not a frame delay - the release is _on_ground_built(), on the signal,
# and it also seats the feet on the relief that now exists.
func _enter_tree() -> void:
	var floor_data := get_floor_data()
	var ground := get_node_or_null(ground_path) as Ground
	var spawn_node := get_node_or_null(^"Wanderer") as Node3D
	if ground != null and floor_data != null:
		# Before the mask: both rebuild the relief, and the mask's own
		# build should be the one that lands on the final grid.
		ground.relief_extent = floor_data.relief_extent
		ground.relief_subdivisions = floor_data.relief_subdivisions
		ground.elevation_max_height = floor_data.elevation_max_height
		ground.landmass_mask_beyond_is_land = floor_data.mask_beyond_is_land
		ground.landmass_mask = floor_data.mask
		ground.wear_mask = floor_data.wear_mask
		ground.rock_mask = floor_data.rock_mask
		ground.rock_slope_min = floor_data.rock_slope_min
		ground.rock_slope_blend = floor_data.rock_slope_blend
		ground.outer_mask = floor_data.outer_mask
		ground.elevation_mask = floor_data.elevation_mask
		ground.landmass_mask_origin = floor_data.mask_origin
		ground.landmass_interior_height = floor_data.interior_height
		ground.landmass_falloff_width = floor_data.falloff
		ground.landmass_underwater_falloff_width = floor_data.underwater_falloff
		ground.relief_amplitude = floor_data.relief_amplitude
		ground.caustic_strength = floor_data.caustic_strength
		ground.basin_color = floor_data.basin_color
		ground.basin_tint_strength = floor_data.basin_tint_strength
		ground.basin_tint_heights = floor_data.basin_tint_heights
		ground.wear_darken = floor_data.wear_darken
		ground.slope_tint_color = floor_data.slope_tint_color
		ground.slope_tint_strength = floor_data.slope_tint_strength
		ground.slope_tint_min = floor_data.slope_tint_min
		ground.slope_tint_blend = floor_data.slope_tint_blend
		ground.crest_light_strength = floor_data.crest_light_strength
		ground.crest_min_height = floor_data.crest_min_height
		ground.slope_tint_fade_height = floor_data.slope_tint_fade_height
		ground.slope_tint_fade_width = floor_data.slope_tint_fade_width
		ground.wind_ripple_angle = floor_data.wind_ripple_angle
		ground.wind_ripple_scale = floor_data.wind_ripple_scale
		ground.wind_ripple_strength = floor_data.wind_ripple_strength
		ground.wind_ripple_warp = floor_data.wind_ripple_warp
	# The floor's own depth fog over the region's, when it names one.
	var sky := get_node_or_null(sky_path) as RegionSky
	if sky != null and floor_data != null and floor_data.fog_depth_begin > 0.0 and floor_data.fog_depth_end > floor_data.fog_depth_begin:
		sky.fog_depth_begin = floor_data.fog_depth_begin
		sky.fog_depth_end = floor_data.fog_depth_end
	if floor_data != null:
		wade_drain_enabled = floor_data.wade_drain_enabled
	# The floor's ambience balance onto the Sea before its _ready() spawns
	# the bed (the wind bed reads its own in _ready() below); the low-pass
	# written every time, since its bus outlives the scene.
	var sea := get_node_or_null(sea_path) as Sea
	if sea != null and floor_data != null:
		sea.floor_offset_db = floor_data.ambience_sea_db
		sea.set_lowpass_hz(floor_data.ambience_sea_lowpass_hz)
	if spawn_node != null and floor_data != null:
		spawn_node.position = Vector3(floor_data.spawn.x, 0.0, floor_data.spawn.y)
		var exit: Vector3 = get_exit_direction()
		spawn_node.rotation.y = atan2(-exit.x, -exit.z)
	if spawn_node != null and ground != null:
		spawn_node.process_mode = Node.PROCESS_MODE_DISABLED
		if ground.is_built():
			_on_ground_built()
		else:
			ground.relief_rebuilt.connect(_on_ground_built)

# Ground has a relief mesh and a HeightMapShape3D. If the floor paints a
# mask and this build isn't the mask one yet (it always is today - the
# mask is on Ground before its _ready() - but that is the thing being
# guaranteed, not assumed), keep waiting for the build that is. Then:
# feet on the relief at spawn, and the Wanderer is released into the
# simulation. Once only - the connection comes off here.
func _on_ground_built() -> void:
	var ground := get_node_or_null(ground_path) as Ground
	var spawn_node := get_node_or_null(^"Wanderer") as Node3D
	if ground == null or spawn_node == null:
		return
	var floor_data := get_floor_data()
	if floor_data != null and floor_data.mask != null and not ground.has_landmass_mask():
		return
	if ground.relief_rebuilt.is_connected(_on_ground_built):
		ground.relief_rebuilt.disconnect(_on_ground_built)
	var local: Vector3 = ground.to_local(Vector3(spawn_node.global_position.x, 0.0, spawn_node.global_position.z))
	var height: float = ground.get_height_at(Vector2(local.x, local.z))
	spawn_node.global_position.y = height + spawn_ground_clearance
	spawn_node.process_mode = Node.PROCESS_MODE_INHERIT
	print("RegionField: Wanderer released onto %s ground at y %.3f" % ["mask" if ground.has_landmass_mask() else "SDF", spawn_node.global_position.y])

func _ready() -> void:
	# Starts the run once per game session, seeding HP and the starting
	# Belongings from RunState.new_run()'s own doc - guarded on character
	# being unset rather than called unconditionally, because a floor
	# change is a reload_current_scene() (see _on_floor_exited()) that
	# re-runs this same _ready(), and an unconditional call would wipe the
	# run's HP/deck/gold back to starting values on every floor. A proper
	# run-start flow (e.g. a character-select screen) replaces this call
	# site later without RunState itself needing to change. Must run before
	# anything below reads RunState.deck.
	RunLogger.enabled = run_logging_enabled
	if RunState.character == null:
		RunState.new_run(load(STARTING_CHARACTER_PATH) as CharacterData)
	RunLogger.floor_entered(RunState.run_snapshot())

	# Ensures forward is computed (and printed) even if no child asked for
	# it first; a no-op if one already did.
	get_forward()

	# From FloorData, now that Ground has its relief for them to stand on
	# (every authored child is ready by here). Before the "enemies" loops
	# below, which must see them.
	_spawn_floor_enemies()
	_spawn_floor_props()
	_spawn_floor_patrols()
	_spawn_floor_ledges()

	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		enemy.contacted.connect(_on_enemy_contacted)

	_setup_exit_gate()
	_setup_field_hud()
	if OS.is_debug_build():
		_setup_debug_row()
	_build_boundary()
	_setup_exit_gate_channel()

	# The Ambience bus at its base - a loss mid-duck or a restart must not
	# inherit the last scene's level.
	_set_ambience_bus_db(ambience_bus_base_db)

	# The wind bed, at this floor's offset - see WindAmbience.
	var floor_for_wind := get_floor_data()
	var wind := WindAmbience.new()
	wind.name = "WindAmbience"
	add_child(wind)
	wind.setup(floor_for_wind.ambience_wind_db if floor_for_wind != null else 0.0)

	# Arriving from another floor: the fade that took the frame there is
	# still up (it lives on the tree's root, not in this scene) - bring it
	# down over this floor. The first floor of a session has none.
	var fade := FloorFade.find_existing(get_tree())
	if fade != null:
		fade.fade_in(fade_seconds)

	# Keeps the walls in sync with live landmass-shape tuning: Ground emits
	# relief_rebuilt after every mesh/collision rebuild (any landmass/relief
	# export's own setter), and _rebuild_boundary_walls() reads Ground's
	# landmass exports directly to place the walls - see its own doc.
	var ground := get_node_or_null(ground_path) as Ground
	if ground != null:
		ground.relief_rebuilt.connect(_rebuild_boundary_walls)
		# The walk grid follows the relief: built once everything on it has
		# placed itself (deferred), and again on any live rebuild.
		ground.relief_rebuilt.connect(_queue_nav_build)
		if ground.is_built():
			_queue_nav_build()
	if wanderer != null:
		wanderer.path_stuck.connect(_on_wanderer_path_stuck)

	# Last, with the gate placed (the camera's inland limit is set) and the
	# HUD seeded: the new run's zone intro, once, on the region's first
	# floor - or, booted from the title scene (RunState.title_pending),
	# the title held over the intro's own first frame, which Start then
	# plays from. Both flags are consumed here whether or not anything
	# plays, so a run that starts elsewhere (or with the intro off)
	# doesn't carry them to a later floor. ZoneIntro freezes this node
	# (the battle freeze, process_mode DISABLED) and releases it itself
	# when done.
	var opening_pending: bool = RunState.run_opening_pending
	RunState.run_opening_pending = false
	var title_pending: bool = RunState.title_pending
	RunState.title_pending = false
	var zone_intro := get_node_or_null(zone_intro_path) as ZoneIntro
	if zone_intro == null:
		return
	if title_pending:
		zone_intro.hold_title()
	elif opening_pending and RunState.current_floor_index == 0:
		zone_intro.play()

# Wade-HP drain only - everything else on the field (movement, contact,
# battle) is either physics-engine-driven or event-driven and doesn't need
# a per-frame tick here. Naturally stops during battle: RegionField's own
# process_mode goes to PROCESS_MODE_DISABLED on enemy contact (see
# _on_enemy_contacted()), which cascades to this by inheritance same as
# everything else under it.
# Point to move: left or right click, either sets (or replaces) the
# Wanderer's target - an enemy under the cursor, else whatever body the
# camera ray hits. Never reached while frozen for battle (PROCESS_MODE_
# DISABLED gates input too), nor for clicks a HUD control has stopped.
func _unhandled_input(event: InputEvent) -> void:
	# The debug row's toggle - only where the row exists (debug builds).
	# In a fight this node is frozen and the battle's own F1 row answers.
	var key := event as InputEventKey
	if _debug_row != null and key != null and key.pressed and not key.echo and key.keycode == KEY_F1:
		_debug_row.visible = not _debug_row.visible
		if _debug_row.visible and _debug_card_picker.item_count == 0:
			_fill_debug_card_picker()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	# The hold ends with the left button; the walk goes on to its last point.
	if not event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_holding = false
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if event.button_index == MOUSE_BUTTON_LEFT and _try_open_bundle(event.position):
		get_viewport().set_input_as_handled()
		return
	if _handle_move_click(event.position, event.button_index == MOUSE_BUTTON_LEFT):
		get_viewport().set_input_as_handled()

# Frozen (a screen, a fight): a hold in progress ends with it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_holding = false

# `can_hold`: a left press - one that lands on the ground starts a hold
# (_tick_hold()); one on an enemy is that fight, never a hold.
func _handle_move_click(screen_pos: Vector2, can_hold: bool = false) -> bool:
	if wanderer == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var enemy: FieldEnemy = _enemy_under_cursor(camera, screen_pos)
	if enemy != null:
		walk_to_enemy(enemy)
		_show_click_marker(enemy.global_position)
		return true

	var point: Vector3 = _ground_point_under(camera, screen_pos)
	if point == Vector3.INF:
		return false
	walk_to(point)
	_show_click_marker(point)
	if can_hold:
		_holding = true
		_hold_point = point
		_hold_timer = 0.0
	return true

# Where a click at `screen_pos` sends him: the ground under it, or - on a
# prop with nothing to open (a hull, the hitching post) - beside the prop
# on his side. Vector3.INF when the ray meets nothing.
func _ground_point_under(camera: Camera3D, screen_pos: Vector2) -> Vector3:
	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * click_ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	# Not the invisible ledge walls either: a click past a lip is meant
	# for the sand there, not for the air above it.
	var excluded: Array[RID] = [wanderer.get_rid()]
	for barrier: Node in get_tree().get_nodes_in_group(LedgeBarrier.LEDGE_GROUP):
		excluded.append((barrier as CollisionObject3D).get_rid())
	query.exclude = excluded
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return Vector3.INF
	var point: Vector3 = hit["position"]
	if _nav != null and _is_nav_obstacle(hit.get("collider")):
		var beside: Vector2 = _nav.nearest_open_toward(Vector2(point.x, point.z), Vector2(wanderer.global_position.x, wanderer.global_position.z))
		var cell: Vector2i = _nav.world_to_cell(beside)
		point = Vector3(beside.x, _nav.height_at_cell(cell), beside.y)
	return point

# A static body the walk grid stamps - not the ground, a walk surface or
# the spawn slab.
func _is_nav_obstacle(collider: Variant) -> bool:
	var body := collider as StaticBody3D
	if body == null or body == get_node_or_null(ground_path) or body is RockShelf or body.name == &"SpawnSlabBody":
		return false
	return true

# Walks the Wanderer to `point` round what is in the way (plan_path()) -
# straight, as before, until the walk grid exists.
func walk_to(point: Vector3) -> void:
	_nav_goal = point
	_nav_goal_enemy = null
	_nav_replans = 0
	_walk_planned()

# Walks him to `enemy` round every other enemy's contact zone, and on into
# its own - the fight starts there.
func walk_to_enemy(enemy: FieldEnemy) -> void:
	_nav_goal = enemy.global_position
	_nav_goal_enemy = enemy
	_nav_replans = 0
	_nav_chase_timer = 0.0
	_walk_planned()

func _walk_planned() -> void:
	if wanderer == null:
		return
	var enemy: FieldEnemy = _nav_goal_enemy if _nav_goal_enemy != null and is_instance_valid(_nav_goal_enemy) else null
	if enemy != null:
		_nav_goal = enemy.global_position
		wanderer.set_move_target_enemy(enemy)
	if _nav == null:
		if enemy == null:
			wanderer.set_move_target(_nav_goal)
		return
	var path: PackedVector3Array = plan_path(wanderer.global_position, _nav_goal, enemy)
	if path.is_empty():
		if enemy == null:
			wanderer.clear_move_target()
		return
	wanderer.set_move_path(path, enemy != null)

# The planned way from `from` to `to`, world points with `from` first and
# the reached point last: round every living enemy's contact zone (grown
# by nav_contact_margin) but `target_enemy`'s and its pack's, and the
# standing Blocker. Empty when the grid isn't built or nothing can be
# reached. `with_zones` false plans on the ground alone.
func plan_path(from: Vector3, to: Vector3, target_enemy: FieldEnemy = null, with_zones: bool = true) -> PackedVector3Array:
	var points := PackedVector3Array()
	if _nav == null:
		return points
	var zones: Array = []
	if with_zones:
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as FieldEnemy
			if enemy == null or enemy.is_defeated() or enemy.is_queued_for_deletion() or enemy == target_enemy:
				continue
			# Its pack fights with it: walking into one of them is the same fight.
			if target_enemy != null and target_enemy.group != &"" and enemy.group == target_enemy.group:
				continue
			zones.append([Vector2(enemy.global_position.x, enemy.global_position.z), enemy.contact_radius + nav_contact_margin])
	var path: PackedVector2Array = _nav.find_path(Vector2(from.x, from.z), Vector2(to.x, to.z), zones, _nav_dynamic_shapes())
	for i in path.size():
		var cell: Vector2i = _nav.world_to_cell(path[i])
		var height: float = from.y if i == 0 else _nav.height_at_cell(cell)
		points.append(Vector3(path[i].x, height, path[i].y))
	return points

# Stuck on the way: plan again from here - a few times, then stop.
func _on_wanderer_path_stuck() -> void:
	if _nav_replans >= nav_max_replans:
		wanderer.clear_move_target()
		return
	_nav_replans += 1
	_walk_planned()

func _process(delta: float) -> void:
	_tick_hold(delta)
	_tick_chase(delta)

# Held: the walk's goal follows the cursor's ground point - planned again
# every hold_replan_sec at most, once it has moved hold_replan_dist. The
# button let go (even unheard, under a screen), the hold is over.
func _tick_hold(delta: float) -> void:
	if not _holding:
		return
	if wanderer == null or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_holding = false
		return
	_hold_timer += delta
	if _hold_timer < hold_replan_sec:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var point: Vector3 = _ground_point_under(camera, get_viewport().get_mouse_position())
	if point == Vector3.INF or point.distance_to(_hold_point) <= hold_replan_dist:
		return
	_hold_timer = 0.0
	_hold_point = point
	walk_to(point)

# A chased enemy that moves: its path follows it.
func _tick_chase(delta: float) -> void:
	if wanderer == null or _nav_goal_enemy == null:
		return
	if not is_instance_valid(_nav_goal_enemy) or wanderer.get_move_target_enemy() != _nav_goal_enemy:
		_nav_goal_enemy = null
		return
	_nav_chase_timer += delta
	if _nav_chase_timer >= nav_chase_replan_sec:
		_nav_chase_timer = 0.0
		_walk_planned()

# A left click on a bundle's padded screen rect (the enemy's click
# padding) with the Wanderer in its reach opens it. Out of reach, or
# already taken, the click falls through to an ordinary move click.
func _try_open_bundle(screen_pos: Vector2) -> bool:
	if wanderer == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var best: BundleProp = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group(BundleProp.GROUP):
		var bundle := node as BundleProp
		if bundle == null or not bundle.can_open_from(wanderer.global_position):
			continue
		var rect: Rect2 = bundle.get_screen_rect(camera, click_target_padding_px)
		if rect.size == Vector2.ZERO or not rect.has_point(screen_pos):
			continue
		var distance: float = camera.global_position.distance_to(bundle.global_position)
		if distance < best_distance:
			best_distance = distance
			best = bundle
	if best == null:
		return false
	_open_loot_screen(best)
	return true

# The enemy whose padded screen rect holds the cursor; nearest to the
# camera on overlap.
func _enemy_under_cursor(camera: Camera3D, screen_pos: Vector2) -> FieldEnemy:
	var best: FieldEnemy = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.is_defeated():
			continue
		var rect: Rect2 = enemy.get_screen_rect(camera, click_target_padding_px)
		if rect.size == Vector2.ZERO or not rect.has_point(screen_pos):
			continue
		var distance: float = camera.global_position.distance_to(enemy.global_position)
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best

func _show_click_marker(point: Vector3) -> void:
	if _click_marker == null:
		_click_marker = ClickMarker.new()
		add_child(_click_marker)
	var theme := load(BATTLE_THEME_PATH) as Theme
	var ink: Color = theme.get_color("ink", "Battle") if theme != null and theme.has_color("ink", "Battle") else Color.BLACK
	_click_marker.show_at(point, ink)

func _physics_process(delta: float) -> void:
	if not wade_drain_enabled or not _boundary_ready or _run_lost_to_wading:
		return

	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return

	var wanderer_xz := Vector2(wanderer.global_position.x, wanderer.global_position.z)
	var distance_in_water := maxf(ground.get_landmass_distance(wanderer_xz), 0.0)
	if distance_in_water <= 0.0:
		_wade_drain_accumulator = 0.0
		return

	var effective_depth := distance_in_water * wade_slope_per_metre
	var drain_rate := clampf((effective_depth - wade_depth_threshold) * wade_drain_rate_per_metre, 0.0, wade_drain_max_per_second)
	if drain_rate <= 0.0:
		return

	_wade_drain_accumulator += drain_rate * delta
	var whole_damage := int(_wade_drain_accumulator)
	if whole_damage <= 0:
		return
	_wade_drain_accumulator -= whole_damage

	RunState.lose_hp(whole_damage)
	if RunState.player_hp <= 0:
		_run_lost_to_wading = true
		_end_run_lost("drowned")

# The field's forward direction: normalized XZ vector from the
# Wanderer's spawn to the ForwardMarker. Nothing else should assume an
# axis or sign for "ahead" — call get_forward() instead. Falls back to
# Godot's own -Z forward convention if the marker isn't present. The
# Tower used to be the far end of this vector; it is a landmark now
# (placed for the battle frame, off to the field's side) and plays no
# part in direction.
#
# Computed lazily and cached rather than eagerly in _ready(): Godot
# calls _ready() bottom-up (children before their parent), and Sea is
# RegionField's child, so Sea's _ready() runs before RegionField's own
# — an eager computation here would still be Vector3.FORWARD's default
# when Sea first asks. Resolving Wanderer via get_node_or_null() rather
# than the @onready var for the same reason: @onready isn't populated
# until immediately before RegionField's own _ready(), which may be
# after this first runs.
func _compute_forward() -> Vector3:
	var spawn_node := get_node_or_null(^"Wanderer") as Node3D
	var marker := get_node_or_null(forward_marker_path) as Node3D
	if spawn_node == null or marker == null:
		return Vector3.FORWARD
	var to_marker := marker.global_position - spawn_node.global_position
	to_marker.y = 0.0
	return to_marker.normalized() if to_marker.length() > 0.0001 else Vector3.FORWARD

func get_forward() -> Vector3:
	if not _forward_computed:
		_forward = _compute_forward()
		_forward_computed = true
		print("RegionField: forward = %s" % str(_forward))
	return _forward

# The floor this scene load plays: region.floors[RunState.current_floor_
# index], resolved once (lazily, so _enter_tree() and any child can ask in
# whatever order) and held for the scene's life - the index only moves
# in _on_floor_exited(), right before the reload that makes a new one of
# these. Null, with a warning, if no region is set; the scene then stands
# with its own defaults and nothing on it.
func get_floor_data() -> FloorData:
	if _floor_resolved:
		return _floor
	_floor_resolved = true
	if region == null or region.floors.is_empty():
		push_warning("RegionField: no region (or an empty one) - no floor to play.")
		return null
	var index: int = clampi(RunState.current_floor_index, 0, region.floors.size() - 1)
	_floor = region.floors[index]
	if _floor == null:
		push_warning("RegionField: region floor %d is null." % index)
		return null
	print("RegionField: floor %d of %d - %s" % [index + 1, region.floors.size(), _floor.resource_path])
	return _floor

# The way OUT of this floor, unit XZ: the gate channel, the camera's
# inland bound, the worn band's end and the transition trigger all lie
# along it (FloorData.exit_direction). Distinct from get_forward(), which
# is where the TOWER is and so where the sea isn't - "seaward" facings,
# the sea's own placement and the mask's image-up all stay on that. Falls
# back to forward when there's no floor or its direction is degenerate.
func get_exit_direction() -> Vector3:
	var floor_data := get_floor_data()
	if floor_data != null and floor_data.exit_direction.length() > 0.0001:
		return Vector3(floor_data.exit_direction.x, 0.0, floor_data.exit_direction.y).normalized()
	return get_forward()

# The inland wall's own Z, in world space - Ground's landmass shape reads
# this as the "fully inland, full dry width" end of its left/right taper
# (see Ground._landmass_curve_t()'s own doc). A small, order-safe formula
# (get_forward() is itself lazy/safe regardless of node-ready order) rather
# than reading _boundary_half_width/_boundary_inland_z, which only exist
# after _build_boundary() has actually run - Ground's own _ready() (a
# child's, running before this node's) can't rely on that yet.
func get_inland_z() -> float:
	return (field_extents.y / 2.0) * get_forward().z

# The Wanderer's spawn, in world space - Ground places its landmass mask's
# origin pixel here (see Ground._mask_world_to_pixel()). Resolved by node
# lookup, not the @onready var, for the same child-before-parent reason
# _compute_forward() does it that way; falls back to this node's own
# origin if the Wanderer isn't present.
func get_spawn_position() -> Vector3:
	var spawn_node := get_node_or_null(^"Wanderer") as Node3D
	return spawn_node.global_position if spawn_node != null else global_position

# The floor's enemies, one field_enemy.tscn each, direct children of this
# node (its own ^".."/^"../Ground" defaults assume exactly that), placed
# at spawn + the authored XZ offset with the authored yaw taken literally
# (no face-shore). Y is left alone - FieldEnemy grounds its own Y against
# Ground.get_height_at() itself (see its _ground_to_relief(), called once
# deferred from _ready() and again on every Ground.relief_rebuilt), which
# also means it stays correct across live relief edits.
func _spawn_floor_enemies() -> void:
	var floor_data := get_floor_data()
	if floor_data == null:
		return
	var scene := load(FIELD_ENEMY_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no enemies." % FIELD_ENEMY_SCENE_PATH)
		return
	var spawn: Vector3 = get_spawn_position()
	for index in floor_data.enemies.size():
		var entry: FloorEnemy = floor_data.enemies[index]
		if entry == null or entry.enemy_data == null:
			push_warning("RegionField: floor enemy %d has no EnemyData; skipped." % index)
			continue
		var enemy := scene.instantiate() as FieldEnemy
		enemy.name = "FieldEnemy%d" % index
		enemy.enemy_data = entry.enemy_data
		enemy.required = entry.required
		enemy.group = entry.group
		enemy.anchor = entry.anchor
		enemy.card_reward = entry.card_reward
		enemy.floor_index = index
		# The body, from the data's Field Body group - its defaults are
		# this scene's own values, so a resource that sets none (the
		# Sputter) wears exactly what it did.
		enemy.model_scene_path = entry.enemy_data.model_scene_path
		enemy.model_scale = entry.enemy_data.model_scale
		enemy.model_yaw_offset = entry.enemy_data.model_yaw_offset_degrees
		enemy.attachment_scene_path = entry.enemy_data.attachment_scene_path
		enemy.rest_height = entry.enemy_data.rest_height_m
		enemy.sink = entry.enemy_data.sink_m
		enemy.battle_hover = entry.enemy_data.battle_hover_m
		enemy.contact_radius = entry.enemy_data.contact_radius_m
		enemy.harness_point = entry.enemy_data.harness_point
		enemy.face_shore_at_spawn = false
		enemy.position = Vector3(spawn.x + entry.position.x, 0.0, spawn.z + entry.position.y)
		enemy.rotation.y = deg_to_rad(entry.yaw_degrees)
		if entry.face_prop_index >= 0:
			if entry.face_prop_index < floor_data.props.size() and floor_data.props[entry.face_prop_index] != null:
				# Toward the prop's spawn-relative spot, the yaw on top - the
				# same direction<->angle convention as FieldEnemy.face_toward().
				var prop_position: Vector3 = floor_data.props[entry.face_prop_index].position
				var toward := Vector2(prop_position.x - entry.position.x, prop_position.z - entry.position.y)
				if toward.length() > 0.0001:
					enemy.set_prop_facing(atan2(-toward.x, -toward.y) + deg_to_rad(entry.yaw_degrees))
			else:
				push_warning("RegionField: floor enemy %d faces prop %d, which isn't on the floor; yaw as authored." % [index, entry.face_prop_index])
		add_child(enemy)

# The floor's routes (FloorPatrol), one PackPatrol each, direct children
# of this node so the field's freeze stops them: handed the group's
# members as spawned (their authored spots are the flock's shape) and
# the waypoints as world positions, spawn-relative like the enemies'.
func _spawn_floor_patrols() -> void:
	var floor_data := get_floor_data()
	if floor_data == null:
		return
	var spawn: Vector3 = get_spawn_position()
	for index in floor_data.patrols.size():
		var entry: FloorPatrol = floor_data.patrols[index]
		if entry == null or entry.group == &"" or entry.waypoints.size() < 2:
			push_warning("RegionField: floor patrol %d needs a group and at least two waypoints; skipped." % index)
			continue
		var members: Array[FieldEnemy] = []
		for node in get_tree().get_nodes_in_group("enemies"):
			var enemy := node as FieldEnemy
			if enemy != null and enemy.group == entry.group:
				members.append(enemy)
		if members.is_empty():
			push_warning("RegionField: floor patrol %d names group '%s' but no enemy has it; skipped." % [index, entry.group])
			continue
		var waypoints: Array[Vector3] = []
		for point in entry.waypoints:
			waypoints.append(Vector3(spawn.x + point.x, 0.0, spawn.z + point.y))
		var patrol := PackPatrol.new()
		patrol.name = "Patrol_%s" % entry.group
		add_child(patrol)
		patrol.setup(members, waypoints, entry.dwell_min_seconds, entry.dwell_max_seconds)
		_patrols.append(patrol)

# The route a group flies, if any.
func _patrol_for(group: StringName) -> PackPatrol:
	for patrol in _patrols:
		if is_instance_valid(patrol) and patrol.name == "Patrol_%s" % group:
			return patrol
	return null

# The floor's props (FloorProp) under one Props node made here, or under
# an earlier prop when parent_index says so (the Bird on its hull). Each
# prop's relative ground_path/region_field_path are re-aimed for its
# actual depth before it enters the tree (_aim_prop_paths()), its
# overrides applied, then its placement handed to its own
# set_floor_placement() where it has one - a WorldCard has no facing and
# is simply grounded (see _setup_belongings_card()). Once-per-run ids
# (Hull.finding_id / Bird.flight_id / Keeper.offer_id) are the floor
# resource's path plus the prop's index: stable across the reload a
# floor change is, distinct across floors.
# The floor's ledge walls (FloorData.ledges), one LedgeBarrier each,
# standing on Ground's relief and rebuilt with it.
func _spawn_floor_ledges() -> void:
	var floor_data := get_floor_data()
	var ground := get_node_or_null(ground_path) as Ground
	if floor_data == null or ground == null:
		return
	var spawn: Vector3 = get_spawn_position()
	for index in floor_data.ledges.size():
		var line := PackedVector2Array()
		for point: Vector2 in floor_data.ledges[index]:
			line.append(Vector2(spawn.x + point.x, spawn.z + point.y))
		var barrier := LedgeBarrier.new()
		barrier.name = "LedgeBarrier%d" % index
		add_child(barrier)
		barrier.setup(ground, line)

func _spawn_floor_props() -> void:
	var floor_data := get_floor_data()
	if floor_data == null or floor_data.props.is_empty():
		return
	var props_root := Node3D.new()
	props_root.name = PROPS_NODE_NAME
	add_child(props_root)
	var spawn: Vector3 = get_spawn_position()
	# Per index: the spawned node (null if skipped) and its depth below
	# this node, for the parent lookups that follow.
	var spawned: Array[Node3D] = []
	var depths: Array[int] = []
	for index in floor_data.props.size():
		spawned.append(null)
		depths.append(0)
		var entry: FloorProp = floor_data.props[index]
		if entry == null or entry.scene == null:
			push_warning("RegionField: floor prop %d has no scene; skipped." % index)
			continue
		var parent: Node3D = props_root
		var depth: int = 2
		if entry.parent_index >= 0:
			if entry.parent_index >= index or spawned[entry.parent_index] == null:
				push_warning("RegionField: floor prop %d names parent %d, which isn't an earlier, spawned prop; skipped." % [index, entry.parent_index])
				continue
			parent = spawned[entry.parent_index]
			depth = depths[entry.parent_index] + 1
		var prop := entry.scene.instantiate() as Node3D
		if prop == null:
			push_warning("RegionField: floor prop %d's scene is not a Node3D; skipped." % index)
			continue
		prop.name = "%s%d" % [prop.name, index]
		_aim_prop_paths(prop, depth)
		for key: String in entry.overrides:
			prop.set(key, entry.overrides[key])
		var id: String = "%s#%d" % [floor_data.resource_path, index]
		if prop is Hull:
			var hull := prop as Hull
			hull.finding_id = id
			if not entry.world_line.is_empty():
				hull.world_line = entry.world_line
		elif prop is Keeper:
			(prop as Keeper).offer_id = id
		elif prop is Bird:
			(prop as Bird).flight_id = id
		elif prop is WorldCard:
			if not _setup_belongings_card(prop as WorldCard, entry, floor_data):
				prop.free()
				continue
		elif prop is RewardSpread:
			# A cache: the spread rolls its own cards from the prop's pool on
			# entering the tree, and lifts/takes/dismisses exactly as it does
			# after a fight. No enemy, so the roll is flat.
			if entry.pool == null:
				push_warning("RegionField: floor prop %d is a RewardSpread with no pool; skipped." % index)
				prop.free()
				continue
			(prop as RewardSpread).pool = entry.pool
		elif prop is BundleProp:
			_setup_bundle(prop as BundleProp, entry, floor_data)
		elif prop is BelongingsCache:
			_setup_belongings_cache(prop as BelongingsCache, entry, floor_data, id)
		elif prop is TroughProp:
			(prop as TroughProp).trough_id = id
		elif prop is Collector:
			var collector := prop as Collector
			collector.collector_id = id
			if not entry.world_line.is_empty():
				collector.world_line = entry.world_line
			collector.stock_pool = entry.pool
			collector.open_requested.connect(open_collector_screen)
		elif prop is Wagon:
			var wagon := prop as Wagon
			if not entry.world_line.is_empty():
				wagon.world_line = entry.world_line
			wagon.open_requested.connect(open_wagon_screen)
		# A child prop's position is local to its parent (a perch); a top-
		# level one's is an XZ offset from spawn, grounded by the prop.
		var placement: Vector3 = entry.position if entry.parent_index >= 0 else Vector3(spawn.x + entry.position.x, 0.0, spawn.z + entry.position.z)
		if prop.has_method("set_floor_placement"):
			prop.call("set_floor_placement", placement, entry.yaw_degrees, entry.roll_degrees)
		else:
			prop.position = placement
		parent.add_child(prop)
		if prop is WorldCard:
			prop.global_position = _ground_point(prop.global_position, world_card_ground_clearance)
		spawned[index] = prop
		depths[index] = depth

# A prop authored in region_field.tscn sat at a known depth and its
# NodePath exports (^"../Ground", ^"../../Ground", ^"../../..") were
# written for it; spawned under Props, or under another prop, it sits
# `depth` levels below this node instead. Only the two paths every prop
# script declares; a prop without one is left alone.
func _aim_prop_paths(prop: Node, depth: int) -> void:
	var up: String = "../".repeat(depth)
	if "ground_path" in prop:
		prop.set("ground_path", NodePath(up + "Ground"))
	if "region_field_path" in prop:
		prop.set("region_field_path", NodePath(up.trim_suffix("/")))

# The placeholder belongings: a WorldCard on the sand holding one card
# rolled by the run's own generator from the prop's own pool, or the
# floor's reward pool when the prop names none, in the standalone
# configuration RewardSpread uses (no holder to measure a silhouette
# against). A real find type is not this - see the task's out-of-scope
# list. False, with a warning, if there's nothing to hold.
func _setup_belongings_card(card: WorldCard, entry: FloorProp, floor_data: FloorData) -> bool:
	var pool: RewardPool = entry.pool if entry.pool != null else floor_data.reward_pool
	if pool == null:
		push_warning("RegionField: a belongings WorldCard needs a pool to roll from (the prop's, or the floor's reward_pool); none set.")
		return false
	var rolled: Array[CardData] = pool.roll(1, RunState.rng, null)
	if rolled.is_empty():
		push_warning("RegionField: the pool rolled nothing for the belongings WorldCard.")
		return false
	card.card = rolled[0]
	card.holder_path = ^""
	return true

# A bundle's one roll, at floor load from the run's own generator, in
# the props' own order: a card from the prop's pool (the floor's reward
# pool when it names none, as the belongings card does), a rare card
# from FloorData.rare_pool, gold from the floor's range - see
# BundleProp.roll() for the split and the fallbacks.
func _setup_bundle(bundle: BundleProp, entry: FloorProp, floor_data: FloorData) -> void:
	var pool: RewardPool = entry.pool if entry.pool != null else floor_data.reward_pool
	bundle.roll(RunState.rng, floor_data.gold_min, floor_data.gold_max, pool, floor_data.rare_pool)

# A belongings cache's one roll, at floor load from the run's own
# generator - the pack's card from the prop's pool, the floor's reward
# pool when it names none (see BelongingsCache.roll()) - plus its once-
# per-run id and the prop's own line when it names one.
func _setup_belongings_cache(cache: BelongingsCache, entry: FloorProp, floor_data: FloorData, id: String) -> void:
	var pool: RewardPool = entry.pool if entry.pool != null else floor_data.reward_pool
	cache.cache_id = id
	if not entry.world_line.is_empty():
		cache.world_line = entry.world_line
	cache.roll(RunState.rng, pool)

# A world point seated on the relief plus `clearance` - same to_local()-
# first idiom RewardSpread/Keeper use, since get_height_at() works in
# Ground's own frame. Returns the point lifted by clearance alone if
# Ground doesn't resolve.
func _ground_point(world_position: Vector3, clearance: float) -> Vector3:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return world_position + Vector3.UP * clearance
	var local: Vector3 = ground.to_local(Vector3(world_position.x, 0.0, world_position.z))
	var height: float = ground.get_height_at(Vector2(local.x, local.z))
	return Vector3(world_position.x, height + clearance, world_position.z)

# Applies this region's own on-pale/on-dark value set to the shared
# BattleTheme resource - deck_panel and hp_bar are both styled from it
# (see DeckPanel/HPBar's own "CardFace" color reads) same as everything
# BattleOverlay itself styles, but both live outside BattleOverlay's own
# tree (FieldHUD, not BattleLayer), so nothing else ever applies this for
# them. refresh_style() re-reads those colors immediately after, since
# (like CardView/EnemyStatus) both cache them via override at _ready()
# rather than tracking the Theme resource live - without this, they'd
# render with whatever value set the theme resource happened to already
# be on. Also seeds the field-mode display (the run's whole deck) deck_
# panel starts in, and keeps its count current on RunState.deck_changed -
# the panel holds the deck by reference, so a card landing (the Keeper's
# offer) only needs the line re-laid out, not re-seeded.
func _setup_field_hud() -> void:
	var battle_theme := deck_panel.theme as BattleTheme
	if battle_theme != null:
		battle_theme.apply_value_set(ui_on_dark_world)
		deck_panel.refresh_style()
		hp_bar.refresh_style()
		# Every FieldEnemy has already created and registered its own
		# enemy_status by now (children's _ready() runs before this one -
		# see get_forward()'s own doc on the same ordering) - each one read
		# its colors before apply_value_set() above ever ran, so each needs
		# its own refresh here too.
		for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
			if enemy.enemy_status != null:
				enemy.enemy_status.refresh_style()
	# The row's look: DECK first (the field DeckPanel, switched to the
	# row's style - its anchor in region_field.tscn stays put, so the card
	# flights still land on it), then each InkLine beside the one before,
	# all sharing hud_row_style - see _apply_hud_row_style().
	if hud_row_style == null:
		hud_row_style = HudRowStyle.new()
	deck_panel.use_row_style(hud_row_style)
	deck_panel.show_whole_deck(RunState.deck)
	RunState.deck_changed.connect(func() -> void: deck_panel.show_whole_deck(RunState.deck))
	# HP beside DECK, styled from the same theme (set before it enters the
	# tree, so its _ready() reads this region's ink); RunState.player_hp_
	# changed keeps it current from here - see HPLine.
	var hp_line := HPLine.new()
	hp_line.name = "HPLine"
	_add_hud_row_line(hp_line, deck_panel)
	# TOLL beside HP, the same way; RunState.toll_changed keeps it current
	# - see TollLine.
	var toll_line := TollLine.new()
	toll_line.name = "TollLine"
	toll_line.set_toll(RunState.toll)
	_add_hud_row_line(toll_line, hp_line)
	# GOLD beside TOLL, the same way; always shown - see GoldLine. Ahead of
	# GLASSBONE and KEEPSAKE, which hide themselves when empty, so it never
	# moves.
	var gold_line := GoldLine.new()
	gold_line.name = "GoldLine"
	_add_hud_row_line(gold_line, toll_line)
	# GLASSBONE beside GOLD, the last resource; hidden until the first
	# piece is taken, and RunState.glassbone_changed keeps it current - see
	# GlassboneLine.
	var glassbone_line := GlassboneLine.new()
	glassbone_line.name = "GlassboneLine"
	_add_hud_row_line(glassbone_line, gold_line)
	# KEEPSAKE last, set apart past GLASSBONE (beside GOLD while GLASSBONE
	# is hidden - see InkLine._follow()); hidden while the slot is empty,
	# and RunState.keepsake_changed keeps it current - see KeepsakeLine.
	var keepsake_line := KeepsakeLine.new()
	keepsake_line.name = "KeepsakeLine"
	_add_hud_row_line(keepsake_line, glassbone_line)
	hp_bar.set_target(wanderer)

# One InkLine into the field HUD row: this region's theme (set before it
# enters the tree, so its _ready() reads this region's ink), the row's
# style, and the item it sits beside.
func _add_hud_row_line(line: InkLine, beside: Control) -> void:
	line.theme = deck_panel.theme
	deck_panel.get_parent().add_child(line)
	line.set_style(hud_row_style)
	line.sit_beside(beside)
	_hud_row_lines.append(line)

# Hands hud_row_style to every row item - a whole new resource set live
# (edits to the one already held re-lay the row through its own changed
# signal).
func _apply_hud_row_style() -> void:
	if not is_node_ready() or hud_row_style == null or deck_panel == null:
		return
	deck_panel.use_row_style(hud_row_style)
	for line: InkLine in _hud_row_lines:
		line.set_style(hud_row_style)

# Parents a FieldEnemy's own persistent HP display under this field's HUD
# CanvasLayer (a Control needs one as an ancestor to render at all - see
# EnemyStatus's own doc) and applies the shared battle theme to it. Called
# from FieldEnemy._ready(), which runs BEFORE this node's own _ready() -
# see get_forward()'s own doc on the same bottom-up ordering - so this
# resolves FieldHUD via a direct node lookup rather than the @onready
# deck_panel/hp_bar vars use, which aren't populated yet at that point.
func add_enemy_status(status: EnemyStatus) -> void:
	status.theme = load(BATTLE_THEME_PATH) as Theme
	var hud := get_node_or_null(^"FieldHUD") as CanvasLayer
	if hud == null:
		push_warning("RegionField: FieldHUD not found; enemy HP display not added to the tree.")
		return
	hud.add_child(status)

# Positions and orients the ExitGate along the floor's exit direction,
# the floor's gate_distance_beyond_enemy past the first enemy's own
# position, pushes its trigger out to transition_distance and its bar
# offset from the floor, then wires it to this field's floor_cleared/
# floor_exited handshake. Done here rather than in ExitGate's own
# _ready(): children's _ready() runs before their parent's (see
# get_forward()'s own doc on the same bottom-up ordering), and the
# enemies only exist once THIS _ready() has spawned them - so an ExitGate
# trying to position itself would always be too early. Same rotation.y =
# atan2(-dir.x, -dir.z) convention FieldEnemy._face_shore()/face_toward()
# already use to align a node's local -Z with a world direction - which
# is what orients the channel and the surfaced bar (ExitGate.setup_
# channel() reads this node's basis).
func _setup_exit_gate() -> void:
	var exit_gate := get_node_or_null(exit_gate_path) as ExitGate
	if exit_gate == null:
		push_warning("RegionField: exit_gate_path did not resolve to an ExitGate; no floor exit.")
		return
	var floor_data := get_floor_data()
	if floor_data == null:
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		push_warning("RegionField: no enemies to measure the exit gate's distance from.")
		return
	var enemy := enemies[0] as FieldEnemy

	var exit: Vector3 = get_exit_direction()
	exit_gate.exit_kind = floor_data.exit_kind
	exit_gate.channel_bar_axis_offset = floor_data.gate_bar_axis_offset
	exit_gate.channel_max_width = floor_data.gate_channel_max_width
	exit_gate.trigger_forward_offset = transition_distance
	exit_gate.global_position = enemy.global_position + exit * floor_data.gate_distance_beyond_enemy
	exit_gate.rotation.y = atan2(-exit.x, -exit.z)
	# Against the painted land, so before _setup_exit_gate_channel() cuts
	# the channel across it - see ExitGate.fit_trigger_to_land().
	exit_gate.fit_trigger_to_land(get_node_or_null(ground_path) as Ground)
	_apply_camera_inland_limit()
	_aim_wear_path(enemy)

	floor_cleared.connect(exit_gate.open)
	exit_gate.floor_exited.connect(_on_floor_exited)

# Hands the camera rig its inland bound from the gate's final position -
# see camera_inland_limit_offset_m's own doc. Safe to call from the
# limit exports' setters at any time: a no-op until both the rig and a
# placed gate exist (before _setup_exit_gate() the gate still sits at its
# authored transform, so nothing is derived from it).
func _apply_camera_inland_limit() -> void:
	if not is_inside_tree():
		return
	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	var exit_gate := get_node_or_null(exit_gate_path) as ExitGate
	if camera_rig == null or exit_gate == null:
		return
	var exit: Vector3 = get_exit_direction()
	var point: Vector3 = exit_gate.global_position + exit * camera_inland_limit_offset_m
	if camera_inland_limit_override_enabled:
		point = Vector3(exit_gate.global_position.x, exit_gate.global_position.y, camera_inland_limit_override_z)
	camera_rig.set_inland_limit(point, exit)

# Only once the gate is where it will stay AND the boundary walls exist
# (the channel is sized from them) can the gate cut its channel across
# the neck - see ExitGate.setup_channel(). Called from _ready() after
# _build_boundary(). A LINE floor has no channel: the gate hands the
# Wanderer its line instead (ExitGate.setup_hold_line()), and his
# arrivals at it come here.
func _setup_exit_gate_channel() -> void:
	var exit_gate := get_node_or_null(exit_gate_path) as ExitGate
	var ground := get_node_or_null(ground_path) as Ground
	if exit_gate == null or ground == null:
		return
	if exit_gate.exit_kind == FloorData.ExitKind.LINE:
		exit_gate.setup_hold_line(wanderer)
		if wanderer != null and not wanderer.hold_line_reached.is_connected(_on_wanderer_hold_line_reached):
			wanderer.hold_line_reached.connect(_on_wanderer_hold_line_reached)
		return
	exit_gate.setup_channel(ground, get_wall_rect())

# He has come to rest at a LINE floor's gate line with the floor not yet
# cleared (the line lifts on floor_cleared - ExitGate.open()): he looks
# back at the nearest required fight still standing, and the first time
# in a run the line is said over him - see hold_line_world_line.
func _on_wanderer_hold_line_reached() -> void:
	var enemy: FieldEnemy = _nearest_required_enemy(wanderer.global_position)
	if enemy != null:
		wanderer.look_back_toward(enemy.global_position)
	if _hold_line_spoken or hold_line_world_line.is_empty():
		return
	var line := WorldVoiceLine.on_hud(get_node_or_null(^"FieldHUD"))
	if line == null:
		push_warning("RegionField: no FieldHUD to say the hold line's world line on.")
		return
	var height: float = wanderer.get_head_height() + hold_line_world_line_head_clearance
	line.show_line_near(hold_line_world_line, hold_line_world_line_seconds, wanderer, Vector3.UP * height)
	_hold_line_spoken = true

# The rectangle the four boundary walls' centre lines enclose, in world
# XZ (Rect2.x = X, Rect2.y = Z) - what ExitGate sizes its channel from.
# Only meaningful after _build_boundary(); an empty Rect2 before that.
func get_wall_rect() -> Rect2:
	return _wall_rect

# The threshold, from the ExitGate's trigger at the far end of the bar:
# the field freezes (the same process-mode freeze battle uses - this
# node's own coroutine still resumes on the timer/tween signals below,
# and CameraRig, Sea and FloorFade all run ALWAYS), the camera lifts its
# eyes to the tower's base, the ambience ducks, the fog colour takes the
# frame, and only then does the floor index move and the scene reload.
# The new scene's _ready() finds the fade still up and brings it down.
#
# What carries is whatever lives on RunState (deck, HP, gold, the rng's
# state) - an autoload, untouched by the reload; the guarded new_run()
# in _ready() is what keeps it from being reset. Toll lives there too and
# carries, down to the character's cap (RunState.carry_toll()).
# Grace is per combat and lives on the fight's Combatant. Past the
# region's last floor the run is won: logged, and the end screen (RunEnd)
# over the fade, which stays up under it. With loop_region_after_last_
# floor it goes round to floor 1 again instead (the once-per-run findings
# stay spent, as they should).
func _on_floor_exited() -> void:
	if _transitioning:
		return
	_transitioning = true
	process_mode = Node.PROCESS_MODE_DISABLED

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	var tower := get_node_or_null(tower_path) as Tower
	if camera_rig != null and tower != null:
		camera_rig.look_up(tower.get_base_position(), look_up_seconds)
	var sea := get_node_or_null(sea_path) as Sea
	if sea != null:
		sea.duck(look_up_seconds + fade_seconds)

	await get_tree().create_timer(look_up_seconds).timeout
	var fade := FloorFade.get_or_create(get_tree())
	await fade.fade_out(_fog_colour(), fade_seconds)

	RunState.floors_crossed += 1
	var floor_count: int = region.floors.size() if region != null else 0
	if RunState.current_floor_index + 1 >= floor_count:
		if not loop_region_after_last_floor:
			print("RegionField: the region's last floor left - the run is won")
			RunState.log_run_end("won")
			get_tree().change_scene_to_file(RUN_END_SCENE_PATH)
			return
		print("RegionField: end of region - back to floor 1 (loop_region_after_last_floor)")
		RunState.current_floor_index = 0
		RunState.region_lap += 1
	else:
		RunState.current_floor_index += 1
	RunState.carry_toll()
	print("RegionField: floor_exited, current_floor_index = %d" % RunState.current_floor_index)
	get_tree().reload_current_scene()

# A lost run - died in a fight, or drowned: logged, the field frozen (the
# transition's freeze), the frame faded to the fog over fade_seconds as a
# floor's exit does, and then the end screen for a loss (RUN_OVER_SCENE_
# PATH, a RunEnd) over the fade, which stays up under it.
func _end_run_lost(cause: String) -> void:
	if _run_ending:
		return
	_run_ending = true
	RunState.log_run_end(cause)
	process_mode = Node.PROCESS_MODE_DISABLED
	var fade := FloorFade.get_or_create(get_tree())
	await fade.fade_out(_fog_colour(), fade_seconds)
	get_tree().change_scene_to_file(RUN_OVER_SCENE_PATH)

# The pale the fade goes to: the region's own fog colour, so the frame
# fills with the same nothing the far field already is.
func _fog_colour() -> Color:
	var sky := get_node_or_null(sky_path) as RegionSky
	return sky.fog_color if sky != null else Color.WHITE

# The enemies one contact starts a fight with. A lone enemy: itself. A
# cluster member (FieldEnemy.group): every member of its group still on
# the field, its anchor (FieldEnemy.anchor) first when it has one still
# standing, else nearest-to-the-Wanderer first - the first is who the
# Wanderer steps up to and what the camera's fit takes its axis from
# (CameraRig.enter_battle()); the rest follow in the order they will
# stand along the line (see _place_cluster_line()). The contact zone is
# the union of the members' own contact areas - no merged shape.
func _battle_members_for(enemy: FieldEnemy) -> Array[FieldEnemy]:
	var members: Array[FieldEnemy] = [enemy]
	if enemy.group == &"":
		return members
	members.clear()
	for node in get_tree().get_nodes_in_group("enemies"):
		var member := node as FieldEnemy
		if member == null or member.group != enemy.group or member.is_queued_for_deletion() or member.is_defeated():
			continue
		members.append(member)
	var from: Vector3 = wanderer.global_position
	members.sort_custom(func(a: FieldEnemy, b: FieldEnemy) -> bool:
		if a.anchor != b.anchor:
			return a.anchor
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from)
	)
	return members

# The line a cluster fights in, from the members' own arrangement, not
# the Wanderer's approach: it starts at the anchor (the first member -
# its FieldEnemy.anchor, else the nearest - which keeps its spot) and
# runs toward the member farthest from it, the
# others stepping onto it cluster_member_gap apart in order of how far
# along it they already stand. Returns the direction from the anchor
# back toward where the Wanderer stands (the line extended past its near
# end), for Wanderer.enter_battle_stance(); ZERO for a lone enemy, which
# keeps the approach line as it always has.
func _place_cluster_line(members: Array[FieldEnemy], duration: float) -> Vector3:
	if members.size() < 2:
		return Vector3.ZERO
	var anchor: FieldEnemy = members[0]
	var far: FieldEnemy = members[0]
	var far_distance: float = 0.0
	for member in members:
		var distance: float = anchor.global_position.distance_squared_to(member.global_position)
		if distance > far_distance:
			far_distance = distance
			far = member
	var along := far.global_position - anchor.global_position
	along.y = 0.0
	if along.length() < 0.0001:
		return Vector3.ZERO
	along = along.normalized()
	# Anchor first, then by how far along the line each already stands -
	# the pack keeps its own order rather than crossing.
	var rest: Array[FieldEnemy] = members.slice(1)
	rest.sort_custom(func(a: FieldEnemy, b: FieldEnemy) -> bool:
		return (a.global_position - anchor.global_position).dot(along) < (b.global_position - anchor.global_position).dot(along)
	)
	# The Wanderer stands on the line's extension past the anchor. When no
	# spacing down to the minimum puts him on dry sand, the whole line
	# steps inward along itself - the anchor too - a tenth at a time, up to
	# battle_line_shift_max, until one does.
	var start: Vector3 = anchor.global_position
	var shift: float = 0.0
	var spacing: float = _dry_stance_spacing(start, -along)
	while spacing < 0.0 and shift < battle_line_shift_max - 0.001:
		shift += 0.1
		spacing = _dry_stance_spacing(start + along * shift, -along)
	if spacing < 0.0:
		push_warning("RegionField: no dry stance for the line at '%s' even %.1f m in; standing at the minimum." % [anchor.name, shift])
		spacing = battle_spacing_min
	elif shift > 0.0:
		print("RegionField: the line steps %.1f m in from '%s' to keep the stance on dry sand (%.1f m out)." % [shift, anchor.name, spacing])
		anchor.step_to(start + along * shift, duration)
	_line_stance_spacing = spacing - shift
	for index in rest.size():
		var spot: Vector3 = start + along * (shift + cluster_member_gap * float(index + 1))
		rest[index].step_to(spot, duration)
		members[index + 1] = rest[index]
	return -along

func _on_enemy_contacted(enemy: FieldEnemy) -> void:
	# Two contact areas can fire in one physics frame; the second must
	# not open a second fight over the first. Loud, so it's known when a
	# layout makes that happen.
	if _battle_open:
		push_warning("RegionField: enemy '%s' contacted while a battle is already open; ignored." % enemy.name)
		return
	_battle_open = true
	process_mode = Node.PROCESS_MODE_DISABLED

	var swing_rig := get_node_or_null(camera_rig_path) as CameraRig
	_duck_ambience(ambience_bus_base_db + ambience_duck_db, swing_rig.battle_transition_time if swing_rig != null else 0.0)

	# Overlay first: CameraRig's battle fit needs the card hand's resting
	# top edge, and that only exists once the overlay's layout is in the
	# tree (anchors resolve synchronously on add_child).
	var overlay := (load(BATTLE_OVERLAY_SCENE_PATH) as PackedScene).instantiate() as BattleOverlay
	battle_layer.add_child(overlay)
	_battle_members = _battle_members_for(enemy)
	_fight_elite = false
	_fight_top_tier = false
	for member in _battle_members:
		if member.enemy_data != null and member.enemy_data.is_elite:
			_fight_elite = true
		if member.card_reward == FloorEnemy.CardReward.TOP_TIER_FIRST:
			_fight_top_tier = true
	var anchor: FieldEnemy = _battle_members[0]
	# A patrolling pack stops where it is: pending take-offs dropped, and
	# any member in the air comes down where it is - the anchor here,
	# the rest through their own step_to() (see FieldEnemy.land_now()).
	var patrol: PackPatrol = _patrol_for(enemy.group)
	if patrol != null:
		patrol.interrupt()
	anchor.land_now()

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		var viewport_height: float = overlay.get_viewport().get_visible_rect().size.y
		var hand_top_fraction: float = overlay.hand_container.get_rest_top_y() / maxf(viewport_height, 1.0)
		# The line is settled (and _battle_members put in its order)
		# before anyone else gets the list. The camera and the battle
		# layer each get their OWN copy: BattleController erases the dead
		# from the list it holds, and _on_battle_finished() needs the
		# full roster to free the last kill - one shared array left that
		# body standing.
		var stance_direction: Vector3 = _place_cluster_line(_battle_members, camera_rig.battle_transition_time)
		# A cluster's stance was settled with its line. A lone enemy's
		# lies on the line back to where the Wanderer is (the direction
		# Wanderer.enter_battle_stance() takes for it), pulled in toward
		# the enemy if that is wet - it has no line to step.
		var spacing: float = _line_stance_spacing
		if stance_direction == Vector3.ZERO:
			var toward: Vector3 = Vector3(wanderer.global_position.x - anchor.global_position.x, 0.0, wanderer.global_position.z - anchor.global_position.z).normalized()
			spacing = _dry_stance_spacing(anchor.global_position, toward)
			if spacing < 0.0:
				push_warning("RegionField: no dry stance for '%s'; standing at the minimum." % anchor.name)
				spacing = battle_spacing_min
		camera_rig.enter_battle(wanderer, _battle_members.duplicate(), hand_top_fraction)
		wanderer.enter_battle_stance(anchor, spacing, camera_rig.battle_transition_time, stance_direction)
		# A lone enemy faces the Wanderer where he is (his stance lies on
		# that same line); a cluster faces where its line will put him.
		var face_point: Vector3 = wanderer.global_position
		if stance_direction != Vector3.ZERO:
			face_point = anchor.global_position + stance_direction * spacing
		for member in _battle_members:
			member.face_toward_point(face_point, camera_rig.battle_transition_time)

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.enter_battle()

	var transition_time: float = camera_rig.battle_transition_time if camera_rig != null else 0.0
	overlay.enter_battle(ui_on_dark_world, _battle_members.duplicate(), deck_panel, hp_bar, transition_time, wanderer)
	# The battle frame settles on the beat the overlay reveals the intents
	# (BattleOverlay._reveal_enemy_intents()); a flyer takes to the air
	# then, and stays up until the fight ends.
	get_tree().create_timer(transition_time).timeout.connect(_start_battle_hover.bind(_battle_members.duplicate()))
	overlay.battle_finished.connect(_on_battle_finished.bind(overlay))
	# Only reachable now - enter_battle() is what creates battle_controller
	# (see Wanderer.bind_to_battle()'s own doc).
	overlay.battle_controller.enemy_defeated.connect(_on_enemy_defeated.bind(overlay))
	overlay.battle_controller.enemy_pain_turn.connect(_on_enemy_pain_turn)
	overlay.battle_controller.enemy_status_gained.connect(func(member: FieldEnemy, status: StatusData) -> void:
		member.show_status(status, true))
	# The fight's opening statuses (the Blackback's Fed) - applied before
	# anyone could hear of them - shown on the bodies at once.
	for member: FieldEnemy in overlay.battle_controller.enemies:
		for active: Status in overlay.battle_controller.get_enemy_statuses(member):
			member.show_status(active.data, false)
	wanderer.bind_to_battle(overlay.battle_controller)

# The Wanderer's stance distance from `from` (the anchor's spot) along
# `direction`: battle_spacing, pulled in toward the pack a tenth of a
# metre at a time while the spot lies within stance_dry_margin_m of the
# water (Ground.get_landmass_distance(), negative on sand), down to
# battle_spacing_min. -1 when none of those is dry - the caller decides
# what then (a cluster steps its line in, see _place_cluster_line()).
func _dry_stance_spacing(from: Vector3, direction: Vector3) -> float:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null or direction == Vector3.ZERO:
		return battle_spacing
	var spacing: float = battle_spacing
	while spacing >= battle_spacing_min - 0.001:
		var point: Vector3 = from + direction * spacing
		if -ground.get_landmass_distance(Vector2(point.x, point.z)) >= stance_dry_margin_m:
			if spacing < battle_spacing:
				print("RegionField: stance pulled in to %.1f m to stay on dry sand." % spacing)
			return spacing
		spacing -= 0.1
	return -1.0

# The frame has settled: every member of this fight that flies takes to
# the air (FieldEnemy.enter_battle_hover()), each a step further round
# the bob's cycle so a pack never bobs as one. Skipped if the fight is
# already over.
func _start_battle_hover(members: Array[FieldEnemy]) -> void:
	if not _battle_open:
		return
	for index in members.size():
		var member: FieldEnemy = members[index]
		if not is_instance_valid(member) or not _battle_members.has(member):
			continue
		member.enter_battle_hover(TAU * float(index) / float(members.size()))

# A member of the fight died. Where it stood and what it was are kept for
# the reward (see _on_battle_finished()'s WIN). If the fight goes on
# without it, it leaves now (FieldEnemy.settle_and_free()); the last kill
# is the win, and a body on the ground is freed with the win exactly as
# it always was - the controller has already dropped the dead from its
# own `enemies`, so an empty list there means this was the last. A last
# kill in the air folds and falls like any other (the win leaves it to).
func _on_enemy_defeated(enemy: FieldEnemy, overlay: BattleOverlay) -> void:
	_last_fallen_at = enemy.global_position
	_last_fallen_data = enemy.enemy_data
	_fight_fallen.append(enemy.enemy_data)
	# Dead from here whichever path frees it - no contact, no cluster
	# roster, no gate waiting on it (see FieldEnemy.mark_defeated()).
	enemy.mark_defeated()
	# Its defeat line, where it stood - anchored to the body, which the
	# line leaves in place if it goes first.
	if enemy.enemy_data != null:
		_say_near_enemy(enemy, enemy.enemy_data.defeat_line)
	if overlay.battle_controller.enemies.is_empty() and not enemy.is_battle_hovering():
		return
	enemy.settle_and_free()

# The pain turn has just been set: its sound, and its line near it.
func _on_enemy_pain_turn(enemy: FieldEnemy) -> void:
	if enemy == null or enemy.enemy_data == null:
		return
	enemy.play_pain_turn_sound()
	_say_near_enemy(enemy, enemy.enemy_data.pain_turn_line)

# One of an enemy's world-voice lines, over its head (see Enemy Lines).
func _say_near_enemy(enemy: FieldEnemy, text: String) -> void:
	if text.is_empty():
		return
	var line := WorldVoiceLine.on_hud(get_node_or_null(^"FieldHUD"))
	if line == null:
		push_warning("RegionField: no FieldHUD to say an enemy's line on.")
		return
	line.show_line_near(text, enemy_world_line_seconds, enemy, Vector3.UP * (enemy.get_head_height() + enemy_world_line_head_clearance))

func _on_battle_finished(outcome: BattleOverlay.Outcome, overlay: BattleOverlay) -> void:
	# The fight's log line first - HP and Toll as the fight left them,
	# before the carry and any keepsake heal.
	RunLogger.fight_end(String(BattleOverlay.Outcome.find_key(outcome)).to_lower(), overlay.finished_by_debug, RunState.player_hp, RunState.toll)
	# Whatever the fight ended on, only up to the cap carries on.
	RunState.carry_toll()
	wanderer.unbind_battle()
	_apply_consumed_removals(overlay.battle_controller.deck)
	overlay.queue_free()
	process_mode = Node.PROCESS_MODE_INHERIT
	_battle_open = false
	# Whoever is still on the field - not freed, not on the way out. On a
	# win that is the last kill (left standing for this, see _on_enemy_
	# defeated()); on an escape, the survivors.
	var standing: Array[FieldEnemy] = []
	for member in _battle_members:
		if is_instance_valid(member) and not member.is_queued_for_deletion():
			standing.append(member)
	_battle_members.clear()

	deck_panel.show_whole_deck(RunState.deck)

	wanderer.exit_battle_stance()

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		camera_rig.exit_battle()

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.exit_battle()

	# The ambience back up with the frame's return - or at once on a loss,
	# since the scene is about to go and the bus is not.
	if outcome == BattleOverlay.Outcome.LOSE:
		_duck_ambience(ambience_bus_base_db, 0.0)
	else:
		_duck_ambience(ambience_bus_base_db, camera_rig.battle_transition_time if camera_rig != null else 0.0)

	match outcome:
		BattleOverlay.Outcome.WIN:
			RunState.fights_won += 1
			# A win, not an escape: the keepsake's heal_on_win, if any.
			RunState.settle_keepsake_win()
			# The reward lands where the last of them fell. Read off the
			# body still standing when there is one (the last kill, or a
			# debug win with nobody hurt) BEFORE it is freed - the spread
			# is spawned a beat later (see _spawn_reward_spread()), by
			# which time the node is gone; else the snapshot the kill left.
			var fell_at: Vector3 = _last_fallen_at
			var fell_to: EnemyData = _last_fallen_data
			if not standing.is_empty():
				fell_at = standing[0].global_position
				fell_to = standing[0].enemy_data
			# Everyone the fight was won against - the killed, and any still
			# standing on a debug win - can leave a keepsake, offered once the
			# normal reward has closed.
			var won_against: Array[EnemyData] = _fight_fallen.duplicate()
			for member in standing:
				# The last kill is left standing for its fold - counted once.
				if not member.is_defeated():
					won_against.append(member.enemy_data)
			_roll_keepsake_drop(won_against)
			_pending_glassbone = _glassbone_left_by(won_against)
			_pending_elite = _fight_elite
			_pending_top_tier = _fight_top_tier
			for member in standing:
				# The last kill folding from the air frees itself.
				if member.is_settling():
					continue
				# enemy_status lives under FieldHUD, not as the enemy's
				# own child (see FieldEnemy.enemy_status's own doc) -
				# freeing the enemy alone would leave it behind as an
				# orphaned, permanently-invisible leak.
				if member.enemy_status != null:
					member.enemy_status.queue_free()
				member.queue_free()
			_spawn_reward_spread(fell_at, fell_to)
			# queue_free() defers the actual removal from the "enemies"
			# group to end of frame - _required_enemy_remains() skips what
			# is on its way out, so the ordering isn't load-bearing.
			if not _floor_cleared_emitted and not _required_enemy_remains():
				_floor_cleared_emitted = true
				floor_cleared.emit()
		BattleOverlay.Outcome.ESCAPE:
			_push_wanderer_away_from(standing)
			# Back to their own spots, over the same beat the frame
			# blends out on. A lone enemy never stepped; no-op for it.
			var return_time: float = camera_rig.battle_transition_time if camera_rig != null else 0.0
			for member in standing:
				member.return_to_field_pose(return_time)
				member.exit_battle_hover()
		BattleOverlay.Outcome.LOSE:
			_end_run_lost("died")
	_fight_fallen.clear()

# Is a fight the floor demands still standing? FloorEnemy.required,
# mirrored onto each FieldEnemy; a body queued for deletion is already
# counted as gone.
func _required_enemy_remains() -> bool:
	return _nearest_required_enemy(Vector3.ZERO) != null

# The standing required enemy nearest `from` (XZ), by the same rule as
# _required_enemy_remains() - null when none is left. A cluster is its
# members, so this is the nearest member.
func _nearest_required_enemy(from: Vector3) -> FieldEnemy:
	var nearest: FieldEnemy = null
	var nearest_distance: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.is_queued_for_deletion() or enemy.is_defeated():
			continue
		if not enemy.required:
			continue
		var offset := Vector2(enemy.global_position.x - from.x, enemy.global_position.z - from.z)
		if offset.length() < nearest_distance:
			nearest_distance = offset.length()
			nearest = enemy
	return nearest

# Three cards on the sand where the enemy fell, once the battle framing
# has blended away. Awaits rather than spawning inline so the cards don't
# appear under the battle camera; the caller doesn't await this, it just
# lets it run. The position is a snapshotted Vector3, not the enemy - by
# the time this resumes that node is freed.
func _spawn_reward_spread(fell_at: Vector3, fell_to: EnemyData) -> void:
	var floor_data := get_floor_data()
	var has_pool: bool = floor_data != null and floor_data.reward_pool != null
	# No card reward to wait for: a keepsake rolled on this win is still
	# offered, after the same beat.
	if not has_pool and _pending_keepsake == null and _pending_glassbone <= 0:
		return
	var delay: float = reward_spread_delay_sec
	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig != null:
		delay = maxf(delay, camera_rig.battle_transition_time)
	await get_tree().create_timer(delay).timeout
	# The floor can be left, or the run ended, during that beat.
	if not is_inside_tree():
		return
	if not has_pool and _pending_glassbone <= 0:
		_open_pending_keepsake_offer()
		return
	if reward_mode == RewardMode.SCREEN or not has_pool:
		# The keepsake follows when the screen closes (_on_reward_screen_
		# closed()).
		_open_reward_screen()
		return
	var scene := load(reward_spread_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no reward spread." % reward_spread_scene_path)
		return
	if _pending_glassbone > 0:
		# The spread lays cards on the sand and has no piece of its own
		# yet; the Glassbone is not offered there (see DESIGN.md).
		push_warning("RegionField: %d Glassbone left by this win is not offered in RewardMode.SPREAD yet." % _pending_glassbone)
		_pending_glassbone = 0
	var spread := scene.instantiate() as RewardSpread
	spread.pool = floor_data.reward_pool
	spread.enemy = fell_to
	spread.roll_by_rarity = true
	spread.elite_rates = _pending_elite
	spread.top_tier = _pending_top_tier
	_pending_elite = false
	_pending_top_tier = false
	add_child(spread)
	spread.global_position = fell_at
	# The cards are on the sand, nothing to close: the keepsake at once.
	_open_pending_keepsake_offer()

# The interim reward list, over the field. The field goes back under the
# same process-mode freeze the battle used - which is also what stops
# click-to-move and WASD, since both live on nodes below this one - and
# comes back out of it when the screen closes. The screen itself runs
# ALWAYS (see RewardScreen._ready()) or it would freeze with everything
# else the moment it opened.
func _open_reward_screen() -> void:
	var scene := load(reward_screen_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no reward screen." % reward_screen_scene_path)
		return
	var screen := scene.instantiate() as RewardScreen
	# Only reached through _spawn_reward_spread(), which has already checked
	# the floor, and that there is a pool or Glassbone to offer.
	var floor_data := get_floor_data()
	# A floor with no pool opens this only for Glassbone: no gold, no card.
	var gold: int = 0
	if floor_data.reward_pool != null:
		gold = RunState.rng.randi_range(mini(floor_data.gold_min, floor_data.gold_max), maxi(floor_data.gold_min, floor_data.gold_max))
		if _pending_elite:
			gold = roundi(gold * elite_gold_multiplier)
	screen.setup(gold, floor_data.reward_pool, deck_panel, _pending_glassbone, _pending_elite, _pending_top_tier)
	_pending_glassbone = 0
	_pending_elite = false
	_pending_top_tier = false
	screen.closed.connect(_on_reward_screen_closed)
	add_child(screen)
	process_mode = Node.PROCESS_MODE_DISABLED

func _on_reward_screen_closed() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	_open_pending_keepsake_offer()

# A won fight's keepsake: the first enemy it was won against whose own
# table (EnemyData.keepsake_table) drops something - never the one held,
# never a unique one already offered - drawn from the run's generator
# and held for after the normal reward. Offered is offered: it counts
# against unique_per_run whether it's then taken or left.
func _roll_keepsake_drop(won_against: Array[EnemyData]) -> void:
	for data in won_against:
		if data == null or data.keepsake_table == null:
			continue
		var drop: TrinketData = data.keepsake_table.roll(RunState.rng, RunState.keepsake, RunState.keepsakes_offered)
		if drop == null:
			continue
		RunState.note_keepsake_offered(drop)
		_pending_keepsake = drop
		_pending_keepsake_source = data.enemy_name
		print("RegionField: '%s' left the keepsake '%s'." % [data.enemy_name, drop.display_name])
		return

# The Glassbone a win leaves: every enemy's EnemyData.glassbone_reward,
# summed, whatever else they left.
func _glassbone_left_by(won_against: Array[EnemyData]) -> int:
	var total: int = 0
	for data in won_against:
		if data != null:
			total += maxi(data.glassbone_reward, 0)
	return total

func _open_pending_keepsake_offer() -> void:
	if _pending_keepsake == null:
		return
	var trinket: TrinketData = _pending_keepsake
	_pending_keepsake = null
	open_keepsake_offer(trinket, _pending_keepsake_source)

# A keepsake offered over the field, under the belongings screen's own
# scrim and freeze: TAKE / LEAVE on an empty slot, TAKE / KEEP CURRENT on
# a full one (KeepsakeOffer). `source` names who dropped it ("Wardling"),
# shown as a quiet line under its name; empty for a keepsake with no
# named source (the debug grant, later the Keeper or a shop). False while
# a fight is open or the field is already frozen under another screen.
func open_keepsake_offer(trinket: TrinketData, source: String = "") -> bool:
	if trinket == null or _battle_open or not can_process():
		return false
	var scene := load(keepsake_offer_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no keepsake offer." % keepsake_offer_scene_path)
		return false
	var offer := scene.instantiate() as KeepsakeOffer
	offer.setup(trinket, RunState.keepsake, source)
	offer.closed.connect(_on_keepsake_offer_closed)
	if _loot_screen != null and is_instance_valid(_loot_screen):
		_loot_screen.close()
	process_mode = Node.PROCESS_MODE_DISABLED
	add_child(offer)
	return true

func _on_keepsake_offer_closed(_taken: bool) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

# Debug builds only: a row of debug buttons on the field HUD in the
# battle row's style (BattleTheme's DebugButton), hidden until F1 -
# Keepsake, a card picker with its Add card, +1 Glassbone, and Path (the
# planned walk and the walk grid near him - NavDebugDraw). It goes with the DECK
# line when a fight hides that, so it never sits over a battle.
func _setup_debug_row() -> void:
	var hud := get_node_or_null(^"FieldHUD") as CanvasLayer
	if hud == null:
		return
	_debug_row = HBoxContainer.new()
	_debug_row.name = "DebugRow"
	_debug_row.theme = deck_panel.theme
	_debug_row.position = debug_row_position
	_debug_row.visible = false
	_debug_keepsake_button = Button.new()
	_debug_keepsake_button.name = "KeepsakeButton"
	_debug_keepsake_button.theme_type_variation = &"DebugButton"
	_debug_keepsake_button.pressed.connect(_on_debug_keepsake_pressed)
	_debug_row.add_child(_debug_keepsake_button)
	_debug_card_picker = OptionButton.new()
	_debug_card_picker.name = "CardPicker"
	_debug_card_picker.theme_type_variation = &"DebugButton"
	_debug_row.add_child(_debug_card_picker)
	var add_card_button := Button.new()
	add_card_button.name = "AddCardButton"
	add_card_button.theme_type_variation = &"DebugButton"
	add_card_button.text = "Add card"
	add_card_button.pressed.connect(_on_debug_add_card_pressed)
	_debug_row.add_child(add_card_button)
	var glassbone_button := Button.new()
	glassbone_button.name = "AddGlassboneButton"
	glassbone_button.theme_type_variation = &"DebugButton"
	glassbone_button.text = "+1 Glassbone"
	glassbone_button.pressed.connect(_on_debug_glassbone_pressed)
	_debug_row.add_child(glassbone_button)
	var path_button := Button.new()
	path_button.name = "PathButton"
	path_button.theme_type_variation = &"DebugButton"
	path_button.text = "Path"
	path_button.toggle_mode = true
	path_button.toggled.connect(_on_debug_path_toggled)
	_debug_row.add_child(path_button)
	hud.add_child(_debug_row)
	deck_panel.visibility_changed.connect(func() -> void:
		if not deck_panel.visible:
			_debug_row.visible = false)
	_refresh_debug_keepsake_button()

# The F1 row's Path: the walk drawn (NavDebugDraw), made the first time.
func _on_debug_path_toggled(on: bool) -> void:
	if _nav_debug == null:
		_nav_debug = NavDebugDraw.new()
		_nav_debug.name = "NavDebugDraw"
		_nav_debug.setup(self)
		add_child(_nav_debug)
	_nav_debug.visible = on

# One piece of Glassbone, through the run's own grant (RunState.add_
# glassbone()) - a debug button, not a game source.
func _on_debug_glassbone_pressed() -> void:
	RunState.add_glassbone(1)
	RunLogger.event("debug_glassbone_add", {})
	print("RegionField: debug +1 Glassbone (run total %d)." % RunState.glassbone)

# Grants the next of debug_keepsake_paths, skipping the one held: into an
# empty slot at once, or - the slot full - through the take-or-keep offer.
func _on_debug_keepsake_pressed() -> void:
	if debug_keepsake_paths.is_empty() or _battle_open or not can_process():
		return
	var trinket: TrinketData = _next_debug_keepsake()
	if trinket == null:
		return
	RunLogger.event("debug_keepsake", {"keepsake": RunLogger.keepsake_id(trinket)})
	if not RunState.acquire_keepsake(trinket):
		open_keepsake_offer(trinket)
	_refresh_debug_keepsake_button()

func _next_debug_keepsake() -> TrinketData:
	for _attempt in debug_keepsake_paths.size():
		var trinket := load(debug_keepsake_paths[_debug_keepsake_index]) as TrinketData
		_debug_keepsake_index = (_debug_keepsake_index + 1) % debug_keepsake_paths.size()
		if trinket != null and trinket != RunState.keepsake:
			return trinket
	return null

# Every CardData in debug_card_dirs, by card name, each item carrying its
# card as metadata.
func _fill_debug_card_picker() -> void:
	var cards: Array[CardData] = []
	for dir in debug_card_dirs:
		for file in ResourceLoader.list_directory(dir):
			if not file.ends_with(".tres"):
				continue
			var card := load(dir.path_join(file)) as CardData
			if card != null:
				cards.append(card)
	cards.sort_custom(func(a: CardData, b: CardData) -> bool: return a.card_name.naturalnocasecmp_to(b.card_name) < 0)
	for card in cards:
		_debug_card_picker.add_item(card.card_name)
		_debug_card_picker.set_item_metadata(_debug_card_picker.item_count - 1, card)

# The picked card into the run's deck, through the one grant path, and
# into the run log so a run that used it can be left out of tuning.
func _on_debug_add_card_pressed() -> void:
	if _battle_open or not can_process() or _debug_card_picker.selected < 0:
		return
	var card := _debug_card_picker.get_item_metadata(_debug_card_picker.selected) as CardData
	if card == null:
		return
	RunState.add_card(card)
	RunLogger.event("debug_card_add", {"card": card.card_name, "context": "field"})

# The button says what it grants next.
func _refresh_debug_keepsake_button() -> void:
	if _debug_keepsake_button == null or debug_keepsake_paths.is_empty():
		return
	var index: int = _debug_keepsake_index % debug_keepsake_paths.size()
	var next := load(debug_keepsake_paths[index]) as TrinketData
	if next == RunState.keepsake:
		next = load(debug_keepsake_paths[(index + 1) % debug_keepsake_paths.size()]) as TrinketData
	_debug_keepsake_button.text = "Keepsake: %s" % (next.display_name if next != null else "?")

# A belongings cache's choice, over the field under the reward screen's
# own freeze (see _open_reward_screen()) - the camera holds where it is
# and the alcove stays in view behind the scrim. False (the cache tries
# again next tick) while a fight is open or the field is already frozen.
func open_belongings_screen(cache: BelongingsCache) -> bool:
	if _battle_open or not can_process():
		return false
	var scene := load(belongings_screen_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no belongings screen." % belongings_screen_scene_path)
		return false
	var screen := scene.instantiate() as BelongingsScreen
	cache.ensure_keepsake()
	screen.setup(cache.world_line, cache.coin_amount, cache.card, cache.keepsake, cache.glassbone_slot, cache.glassbone_amount, cache.object_scene_paths, cache.object_scales, deck_panel)
	screen.closed.connect(_on_belongings_screen_closed.bind(cache))
	if _loot_screen != null and is_instance_valid(_loot_screen):
		_loot_screen.close()
	process_mode = Node.PROCESS_MODE_DISABLED
	add_child(screen)
	return true

func _on_belongings_screen_closed(taken: int, cache: BelongingsCache) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	if is_instance_valid(cache):
		cache.resolve(taken)

# The collector's screen (CollectorScreen), over the belongings screen's
# scrim-and-freeze: the field DISABLED under it until it closes. False
# when a fight or another screen has the field already.
func open_collector_screen(collector: Collector) -> bool:
	if _battle_open or not can_process():
		return false
	var scene := load(collector_screen_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no collector screen." % collector_screen_scene_path)
		return false
	var screen := scene.instantiate() as CollectorScreen
	screen.setup(collector, deck_panel)
	screen.closed.connect(_on_collector_screen_closed)
	if _loot_screen != null and is_instance_valid(_loot_screen):
		_loot_screen.close()
	process_mode = Node.PROCESS_MODE_DISABLED
	add_child(screen)
	return true

func _on_collector_screen_closed() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

# The wagon's screen (WagonScreen), under the collector's scrim-and-freeze:
# the field DISABLED under it until it closes. False when a fight or
# another screen has the field already.
func open_wagon_screen(wagon: Wagon) -> bool:
	if _battle_open or not can_process():
		return false
	var scene := load(wagon_screen_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no wagon screen." % wagon_screen_scene_path)
		return false
	var screen := scene.instantiate() as WagonScreen
	screen.setup(wagon)
	screen.closed.connect(_on_wagon_screen_closed)
	if _loot_screen != null and is_instance_valid(_loot_screen):
		_loot_screen.close()
	process_mode = Node.PROCESS_MODE_DISABLED
	add_child(screen)
	return true

func _on_wagon_screen_closed() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

# A bundle's loot window, beside the bundle on FieldHUD - the field stays
# live under it (LootScreen closes itself on leaving reach or a freeze).
# A click on the bundle it already shows changes nothing; a click on
# another bundle closes the open one first.
func _open_loot_screen(bundle: BundleProp) -> void:
	if _loot_screen != null and is_instance_valid(_loot_screen):
		if _loot_screen.get_bundle() == bundle:
			return
		_loot_screen.close()
	var hud := get_node_or_null(^"FieldHUD") as CanvasLayer
	if hud == null:
		push_warning("RegionField: FieldHUD not found; no loot window.")
		return
	var scene := load(loot_screen_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no loot window." % loot_screen_scene_path)
		return
	var screen := scene.instantiate() as LootScreen
	screen.setup(bundle, deck_panel, wanderer, self)
	screen.closed.connect(_on_loot_screen_closed.bind(screen))
	_loot_screen = screen
	hud.add_child(screen)

func _on_loot_screen_closed(screen: LootScreen) -> void:
	if _loot_screen == screen:
		_loot_screen = null

# Points the ground's walked band along the route the floor actually
# takes: out of spawn, past the enemy, to the gate - or along the floor's
# own 3 to 8 points when it overrides that (FloorData.wear_path_override).
# Ground knows none of those - it takes world points and draws a band
# through them (see Ground.set_wear_path()), so a floor with a
# different shape re-aims it by calling this with different points rather
# than by editing a shader. Called from _setup_exit_gate(), the first
# moment the gate's own position is final.
func _aim_wear_path(enemy: FieldEnemy) -> void:
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null:
		return
	var gate := get_node_or_null(exit_gate_path) as Node3D
	if gate == null:
		return
	var floor_data := get_floor_data()
	if floor_data == null:
		return
	var spawn: Vector3 = get_spawn_position()
	if floor_data.wear_path_override.size() >= 3:
		var points := PackedVector2Array()
		for offset in floor_data.wear_path_override:
			points.append(Vector2(spawn.x + offset.x, spawn.z + offset.y))
		ground.set_wear_path(points)
		return
	# The middle point is pushed off the enemy along the exit's right, so
	# the band bends past the standing pool painted beside the crab rather
	# than running through it. Right is the exit direction turned a
	# quarter turn, not world +X, so this holds for any exit.
	var right: Vector3 = get_exit_direction().cross(Vector3.UP).normalized()
	var mid: Vector3 = enemy.global_position + right * floor_data.wear_path_mid_offset
	ground.set_wear_path(PackedVector2Array([
		Vector2(spawn.x, spawn.z), Vector2(mid.x, mid.z), Vector2(gate.global_position.x, gate.global_position.z)]))

# The Ambience bus toward `to_db` over `seconds` - one tween, the last
# call wins, and it runs through this node's own battle freeze (TWEEN_
# PAUSE_PROCESS, the same override FieldEnemy's flash carries). 0 seconds
# writes the level outright.
func _duck_ambience(to_db: float, seconds: float) -> void:
	var bus: int = AudioServer.get_bus_index(&"Ambience")
	if bus < 0:
		return
	if _ambience_tween != null and _ambience_tween.is_valid():
		_ambience_tween.kill()
	_ambience_tween = null
	if seconds <= 0.0:
		AudioServer.set_bus_volume_db(bus, to_db)
		return
	_ambience_tween = create_tween()
	_ambience_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_ambience_tween.tween_method(func(value: float) -> void: AudioServer.set_bus_volume_db(bus, value), AudioServer.get_bus_volume_db(bus), to_db, seconds)

func _set_ambience_bus_db(level_db: float) -> void:
	_duck_ambience(level_db, 0.0)

# CONSUMED cards leave RunState.deck (the run's Belongings) for good once
# the fight that consumed them ends; SPENT ones (the rest of exhaust_pile)
# never touch RunState at all - they simply return to the Belongings next
# battle, since BattleController.setup() rebuilds a fresh per-fight Deck
# straight from whatever's still in RunState.deck. Must run before overlay.
# queue_free() above frees battle_controller (and this exhaust_pile) -
# called first in _on_battle_finished() for exactly that reason.
func _apply_consumed_removals(fight_deck: Deck) -> void:
	for card in fight_deck.exhaust_pile:
		if card.removal_scope == CardData.RemovalScope.CONSUMED:
			RunState.remove_card(card)

# Straight back from the nearest of them, escape_push_distance out - and
# further, if that still lands inside any of their contact areas
# (contact_radius + escape_clearance_margin from each, where each stands
# now AND where it is about to go back to, since the area sweeps between
# the two), or the Wanderer lands back inside an Area3D and either
# re-triggers contact immediately or can't leave it. push_warning when
# the export didn't clear on its own, so a misconfigured pair is loud,
# not a silent soft-lock. Empty list (nothing left to escape from): no
# push.
func _push_wanderer_away_from(enemies: Array[FieldEnemy]) -> void:
	var anchor: FieldEnemy = null
	var anchor_distance: float = INF
	for enemy in enemies:
		var distance: float = wanderer.global_position.distance_to(enemy.global_position)
		if distance < anchor_distance:
			anchor_distance = distance
			anchor = enemy
	if anchor == null:
		return

	var push_dir := wanderer.global_position - anchor.global_position
	push_dir.y = 0.0
	push_dir = push_dir.normalized() if push_dir.length() > 0.0001 else Vector3.BACK

	var push_distance := escape_push_distance
	var target: Vector3 = anchor.global_position + push_dir * push_distance
	for enemy in enemies:
		var clearance: float = enemy.contact_radius + escape_clearance_margin
		var centres: Array[Vector3] = [enemy.global_position]
		if enemy.get_field_position() != enemy.global_position:
			centres.append(enemy.get_field_position())
		for centre in centres:
			var to_target := target - centre
			to_target.y = 0.0
			if to_target.length() >= clearance:
				continue
			# Along the push line, how much further out clears this
			# circle: solve |anchor + dir * d - centre| = clearance for d.
			var rel := anchor.global_position - centre
			rel.y = 0.0
			var b: float = rel.dot(push_dir)
			var c: float = rel.length_squared() - clearance * clearance
			var disc: float = b * b - c
			var needed: float = -b + sqrt(maxf(disc, 0.0))
			push_warning("RegionField: escape_push_distance (%.2f) does not clear enemy '%s' contact_radius (%.2f); pushing %.2f." % [push_distance, enemy.enemy_id, enemy.contact_radius, needed])
			push_distance = maxf(push_distance, needed)
			target = anchor.global_position + push_dir * push_distance

	wanderer.global_position = target

# Computes and caches the field's span (see _boundary_ready's own doc),
# then delegates the four collision walls to _rebuild_boundary_walls().
# No berm any more - the inland edge is the neck's own tidal channel (see
# ExitGate) and the landmass shoreline elsewhere; the inland collision
# wall stays. Both Z-boundary edges are positioned from get_forward()'s
# sign, not assumed to be +Z/-Z.
func _build_boundary() -> void:
	var half_depth := field_extents.y / 2.0
	var inland_z := half_depth * _forward.z
	var shoreward_z := _shoreward_wall_z(half_depth)
	# The side walls span between the two actual end-cap Z positions, not
	# a symmetric ±field_extents.y/2 - inland_z and
	# shoreward_z aren't generally symmetric around 0 (see
	# _shoreward_wall_z()'s own doc: the seaward side is placed from Sea's
	# own edge distance/margin, not field_extents, and can sit much closer
	# to spawn than the inland side). Reduces to the old symmetric math
	# exactly when shoreward_z is the half_depth fallback (Sea absent), so
	# this isn't a behavior change for that case - just correct once the
	# two sides diverge.
	_boundary_half_width = field_extents.x / 2.0
	_boundary_inland_z = inland_z
	_boundary_shoreward_z = shoreward_z
	_boundary_span_center_z = (inland_z + shoreward_z) / 2.0
	_boundary_span_length = absf(shoreward_z - inland_z)
	_boundary_ready = true

	_rebuild_boundary_walls()

# The four boundary collision walls. Tracked and
# always freed first so side_wade_margin (and any live landmass-shape edit,
# via _ready()'s own relief_rebuilt connection) can move/resize them with
# no scene reload.
#
# Two placements, picked by whether Ground is running a painted landmass
# mask (Ground.has_landmass_mask()):
#
# Mask mode - the painted land's world-XZ bounding rect (Ground.get_
# landmass_bounds()) grown by side_wade_margin on all four sides, one wall
# per rect edge. Still a rectangle around an arbitrary shape - the wade
# drain is what actually keeps the Wanderer near the shore; the walls are
# the hard stop a few metres past the furthest the painting reaches.
#
# SDF mode - unchanged from before the mask existed: the side walls' X
# offset has to clear the shoreline's own WORST-CASE excursion, not the
# field's nominal width, since the two can differ once the landmass shape
# has its own half-width/noise exports. Worst case is the wider of Ground's
# two half-width exports (seaward is wider by design, but this doesn't
# assume that) plus shoreline_noise_amplitude (the furthest the noised
# crossing could wander out) - then side_wade_margin past THAT. Falls back
# to the old field_extents.x-based offset if Ground doesn't resolve, so a
# misconfigured ground_path degrades rather than breaking wall placement
# entirely. The two end-cap walls widen to match the side walls' X
# (field_extents.x replaced by outer_half_width*2) - without this, the
# strip of X between the field's own edge and the pushed-out side wall, at
# each end-cap's Z line, would have no collision at all, letting the
# Wanderer walk around it. Inland stays unconditionally dry.
# --- Pathing ---

func get_nav_grid() -> NavGrid:
	return _nav

func _queue_nav_build() -> void:
	if _nav_build_queued or not is_inside_tree():
		return
	_nav_build_queued = true
	call_deferred("_build_nav_grid")

# The grid over the boundary walls' rectangle: Ground's heights, the sea's
# level, and every static body's shapes but the ground's own, walk
# surfaces (rock shelves, the spawn slab), the boundary walls and the
# ExitGate's Blocker (stamped per query while it stands - see
# _nav_dynamic_shapes()).
func _build_nav_grid() -> void:
	_nav_build_queued = false
	var ground := get_node_or_null(ground_path) as Ground
	if ground == null or not ground.is_built():
		return
	var rect: Rect2
	if ground.has_landmass_mask():
		rect = ground.get_landmass_bounds().grow(side_wade_margin)
	else:
		rect = Rect2(Vector2(-ground.relief_extent.x * 0.5, -ground.relief_extent.y * 0.5), ground.relief_extent)
	var sea := get_node_or_null(^"Sea")
	var sea_level: float = float(sea.get("sea_level")) if sea != null else 0.0
	var grid := NavGrid.new()
	grid.cell_size = nav_cell_size
	grid.inflation = nav_agent_radius + nav_clearance
	grid.deep_water_depth = nav_deep_water_depth_m
	grid.shallows_cost = nav_shallows_cost
	if wanderer != null:
		grid.step_height = wanderer.step_height
		grid.max_slope_degrees = rad_to_deg(wanderer.floor_max_angle)
	grid.build(ground, sea_level, rect, _nav_static_shapes(ground))
	_nav = grid
	print("RegionField: walk grid %d x %d at %.2f m (%.0f x %.0f m) in %d ms" % [grid.cols, grid.rows, grid.cell_size, rect.size.x, rect.size.y, grid.build_msec])

func _nav_static_shapes(ground: Ground) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var skip: Array[Node] = [ground, _wall_inland, _wall_shoreward, _wall_left, _wall_right]
	var gate := get_node_or_null(exit_gate_path)
	if gate != null:
		skip.append(gate.get_node_or_null(^"Blocker"))
	for node in find_children("*", "StaticBody3D", true, false):
		if skip.has(node) or node is RockShelf or node.name == &"SpawnSlabBody":
			continue
		for child in node.find_children("*", "CollisionShape3D", true, false):
			shapes.append(child as CollisionShape3D)
	return shapes

# The closed channel's Blocker while it stands.
func _nav_dynamic_shapes() -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	var gate := get_node_or_null(exit_gate_path)
	var blocker := gate.get_node_or_null(^"Blocker/CollisionShape3D") as CollisionShape3D if gate != null else null
	if blocker != null and not blocker.disabled:
		shapes.append(blocker)
	return shapes

func _rebuild_boundary_walls() -> void:
	if _wall_inland != null:
		_wall_inland.queue_free()
		_wall_inland = null
	if _wall_shoreward != null:
		_wall_shoreward.queue_free()
		_wall_shoreward = null
	if _wall_left != null:
		_wall_left.queue_free()
		_wall_left = null
	if _wall_right != null:
		_wall_right.queue_free()
		_wall_right = null

	if not _boundary_ready:
		return

	var ground := get_node_or_null(ground_path) as Ground
	if ground != null and ground.has_landmass_mask():
		_build_mask_boundary_walls(ground.get_landmass_bounds())
		return

	var outer_half_width: float = _boundary_half_width + side_wade_margin
	if ground != null:
		var worst_case_half_width: float = maxf(ground.landmass_half_width_inland, ground.landmass_half_width_seaward) + ground.shoreline_noise_amplitude
		outer_half_width = worst_case_half_width + side_wade_margin
	var end_cap_width := outer_half_width * 2.0

	_wall_inland = _add_wall(Vector3(0.0, wall_height / 2.0, _boundary_inland_z), Vector3(end_cap_width, wall_height, wall_thickness))
	_wall_shoreward = _add_wall(Vector3(0.0, wall_height / 2.0, _boundary_shoreward_z), Vector3(end_cap_width, wall_height, wall_thickness))
	_wall_left = _add_wall(Vector3(-outer_half_width, wall_height / 2.0, _boundary_span_center_z), Vector3(wall_thickness, wall_height, _boundary_span_length))
	_wall_right = _add_wall(Vector3(outer_half_width, wall_height / 2.0, _boundary_span_center_z), Vector3(wall_thickness, wall_height, _boundary_span_length))
	_wall_rect = Rect2(-outer_half_width, minf(_boundary_inland_z, _boundary_shoreward_z), outer_half_width * 2.0, _boundary_span_length)

# Mask-mode walls (see _rebuild_boundary_walls()'s own doc): land_bounds is
# Ground's painted-land rect in world XZ (Rect2.x = X, Rect2.y = Z). The
# end caps (min/max Z) run the full outer width plus one wall_thickness so
# they seal the corners against the side walls' own centre lines; which of
# the two is "inland" (the way out) is whichever lies further along the
# floor's exit direction - never assumed to be -Z. Naming only: all four
# walls are built either way, and get_wall_rect() is what the gate reads.
func _build_mask_boundary_walls(land_bounds: Rect2) -> void:
	var bounds: Rect2 = land_bounds.grow(side_wade_margin)
	var center: Vector2 = bounds.get_center()
	var end_cap_width: float = bounds.size.x + wall_thickness
	var min_z_is_inland: bool = get_exit_direction().z < 0.0

	var wall_min_z := _add_wall(Vector3(center.x, wall_height / 2.0, bounds.position.y), Vector3(end_cap_width, wall_height, wall_thickness))
	var wall_max_z := _add_wall(Vector3(center.x, wall_height / 2.0, bounds.end.y), Vector3(end_cap_width, wall_height, wall_thickness))
	_wall_inland = wall_min_z if min_z_is_inland else wall_max_z
	_wall_shoreward = wall_max_z if min_z_is_inland else wall_min_z
	_wall_left = _add_wall(Vector3(bounds.position.x, wall_height / 2.0, center.y), Vector3(wall_thickness, wall_height, bounds.size.y))
	_wall_right = _add_wall(Vector3(bounds.end.x, wall_height / 2.0, center.y), Vector3(wall_thickness, wall_height, bounds.size.y))
	_wall_rect = bounds

# Pushed shoreline_wall_margin past the sea's near edge (derived from
# the Wanderer's spawn, get_forward(), and the Sea's own
# sea_edge_distance) rather than sitting at the fixed field boundary, so
# the Wanderer can walk down to, and a little into, the water. Falls
# back to the fixed half_depth boundary on the opposite side from
# inland_z if the Sea node isn't present.
func _shoreward_wall_z(half_depth: float) -> float:
	var sea := get_node_or_null(sea_path) as Sea
	if sea == null:
		return -half_depth * _forward.z
	var near_edge_z := wanderer.global_position.z - _forward.z * sea.sea_edge_distance
	return near_edge_z - _forward.z * shoreline_wall_margin

# Callers describe a wall standing on y=0 (position.y = wall_height/2,
# size.y = wall_height); the wall_sink extension below y=0 is applied here
# so every wall gets it without each call site restating the offset.
func _add_wall(wall_position: Vector3, size: Vector3) -> StaticBody3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, size.y + wall_sink, size.z)
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape

	var wall := StaticBody3D.new()
	wall.position = wall_position - Vector3(0.0, wall_sink / 2.0, 0.0)
	wall.add_child(collision_shape)

	add_child(wall)
	return wall
