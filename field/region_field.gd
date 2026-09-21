extends Node3D
class_name RegionField

const BATTLE_OVERLAY_SCENE_PATH := "res://battle/battle_overlay.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
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
# Held back until the battle framing has gone: the cards should appear on
# an ordinary field view, not under the battle camera mid-swing-out.
# Raised to the camera rig's own battle_transition_time when that's
# longer, so retuning the blend doesn't leave this stale.
@export var reward_spread_delay_sec: float = 0.6

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
@export_group("")

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
# Metres between the members of a cluster along the line they step into
# for a fight (see _place_cluster_line()) - read at contact, so a Remote-
# tab edit takes on the next fight.
@export var cluster_member_gap: float = 1.3
# Which of BattleTheme's two value sets the overlay applies on entering
# battle - see ui/battle_theme.gd's own rule: UI is the dark element on a
# pale world (false, default) and the pale element on a dark one (true).
@export var ui_on_dark_world: bool = false

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

# The click mark, created on first use - see ClickMarker.
var _click_marker: ClickMarker = null

# The Ambience bus's running duck/return - see _duck_ambience().
var _ambience_tween: Tween = null

# The fight in progress, from _on_enemy_contacted() to _on_battle_
# finished(): its guard (a second contact while one is open is ignored,
# loudly), the enemies it holds (in the order the battle layer got them -
# the first is the one the Wanderer squares up to), and where the last
# of them fell, snapshotted at the kill so the reward can land there
# after the body is gone.
var _battle_open: bool = false
var _battle_members: Array[FieldEnemy] = []
var _last_fallen_at: Vector3 = Vector3.ZERO
var _last_fallen_data: EnemyData = null
var _floor_cleared_emitted: bool = false

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
		ground.landmass_mask = floor_data.mask
		ground.elevation_mask = floor_data.elevation_mask
		ground.landmass_mask_origin = floor_data.mask_origin
		ground.landmass_interior_height = floor_data.interior_height
		ground.landmass_falloff_width = floor_data.falloff
		ground.relief_amplitude = floor_data.relief_amplitude
		ground.caustic_strength = floor_data.caustic_strength
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
	if RunState.character == null:
		RunState.new_run(load(STARTING_CHARACTER_PATH) as CharacterData)

	# Ensures forward is computed (and printed) even if no child asked for
	# it first; a no-op if one already did.
	get_forward()

	# From FloorData, now that Ground has its relief for them to stand on
	# (every authored child is ready by here). Before the "enemies" loops
	# below, which must see them.
	_spawn_floor_enemies()
	_spawn_floor_props()

	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		enemy.contacted.connect(_on_enemy_contacted)

	_setup_exit_gate()
	_setup_field_hud()
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
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _handle_move_click(event.position):
		get_viewport().set_input_as_handled()

func _handle_move_click(screen_pos: Vector2) -> bool:
	if wanderer == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false

	var enemy: FieldEnemy = _enemy_under_cursor(camera, screen_pos)
	if enemy != null:
		wanderer.set_move_target_enemy(enemy)
		_show_click_marker(enemy.global_position)
		return true

	var from: Vector3 = camera.project_ray_origin(screen_pos)
	var to: Vector3 = from + camera.project_ray_normal(screen_pos) * click_ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [wanderer.get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var point: Vector3 = hit["position"]
	wanderer.set_move_target(point)
	_show_click_marker(point)
	return true

# The enemy whose padded screen rect holds the cursor; nearest to the
# camera on overlap.
func _enemy_under_cursor(camera: Camera3D, screen_pos: Vector2) -> FieldEnemy:
	var best: FieldEnemy = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null:
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
		get_tree().change_scene_to_file(RUN_OVER_SCENE_PATH)

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
		enemy.face_shore_at_spawn = false
		enemy.position = Vector3(spawn.x + entry.position.x, 0.0, spawn.z + entry.position.y)
		enemy.rotation.y = deg_to_rad(entry.yaw_degrees)
		add_child(enemy)

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
	deck_panel.show_whole_deck(RunState.deck)
	RunState.deck_changed.connect(func() -> void: deck_panel.show_whole_deck(RunState.deck))
	hp_bar.set_target(wanderer)

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
	exit_gate.channel_bar_axis_offset = floor_data.gate_bar_axis_offset
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
# _build_boundary().
func _setup_exit_gate_channel() -> void:
	var exit_gate := get_node_or_null(exit_gate_path) as ExitGate
	var ground := get_node_or_null(ground_path) as Ground
	if exit_gate == null or ground == null:
		return
	exit_gate.setup_channel(ground, get_wall_rect())

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
# in _ready() is what keeps it from being reset. Toll and Grace are per
# combat and live in BattleController, gone with the fight. Past the
# region's last floor there is nothing yet: say so and go round to floor
# 1 again (the once-per-run findings stay spent, as they should).
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

	var floor_count: int = region.floors.size() if region != null else 0
	if RunState.current_floor_index + 1 >= floor_count:
		print("RegionField: end of region - back to floor 1 for now")
		RunState.current_floor_index = 0
	else:
		RunState.current_floor_index += 1
	print("RegionField: floor_exited, current_floor_index = %d" % RunState.current_floor_index)
	get_tree().reload_current_scene()

# The pale the fade goes to: the region's own fog colour, so the frame
# fills with the same nothing the far field already is.
func _fog_colour() -> Color:
	var sky := get_node_or_null(sky_path) as RegionSky
	return sky.fog_color if sky != null else Color.WHITE

# The enemies one contact starts a fight with. A lone enemy: itself. A
# cluster member (FieldEnemy.group): every member of its group still on
# the field, nearest-to-the-Wanderer first - the first is who the
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
		if member == null or member.group != enemy.group or member.is_queued_for_deletion():
			continue
		members.append(member)
	var from: Vector3 = wanderer.global_position
	members.sort_custom(func(a: FieldEnemy, b: FieldEnemy) -> bool:
		return a.global_position.distance_squared_to(from) < b.global_position.distance_squared_to(from)
	)
	return members

# The line a cluster fights in, from the members' own arrangement, not
# the Wanderer's approach: it starts at the anchor (the nearest member,
# which keeps its spot) and runs toward the member farthest from it, the
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
	for index in rest.size():
		var spot: Vector3 = anchor.global_position + along * cluster_member_gap * float(index + 1)
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
	var anchor: FieldEnemy = _battle_members[0]

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		var viewport_height: float = overlay.get_viewport().get_visible_rect().size.y
		var hand_top_fraction: float = overlay.hand_container.get_rest_top_y() / maxf(viewport_height, 1.0)
		camera_rig.enter_battle(wanderer, _battle_members, hand_top_fraction)
		var stance_direction: Vector3 = _place_cluster_line(_battle_members, camera_rig.battle_transition_time)
		wanderer.enter_battle_stance(anchor, battle_spacing, camera_rig.battle_transition_time, stance_direction)
		# A lone enemy faces the Wanderer where he is (his stance lies on
		# that same line); a cluster faces where its line will put him.
		var face_point: Vector3 = wanderer.global_position
		if stance_direction != Vector3.ZERO:
			face_point = anchor.global_position + stance_direction * battle_spacing
		for member in _battle_members:
			member.face_toward_point(face_point, camera_rig.battle_transition_time)

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.enter_battle()

	var transition_time: float = camera_rig.battle_transition_time if camera_rig != null else 0.0
	overlay.enter_battle(ui_on_dark_world, _battle_members, deck_panel, hp_bar, transition_time, wanderer)
	overlay.battle_finished.connect(_on_battle_finished.bind(overlay))
	# Only reachable now - enter_battle() is what creates battle_controller
	# (see Wanderer.bind_to_battle()'s own doc).
	overlay.battle_controller.enemy_defeated.connect(_on_enemy_defeated.bind(overlay))
	wanderer.bind_to_battle(overlay.battle_controller)

# A member of the fight died. Where it stood and what it was are kept for
# the reward (see _on_battle_finished()'s WIN). If the fight goes on
# without it, it leaves now (FieldEnemy.settle_and_free()); the last kill
# is the win, and that body is freed with the win exactly as it always
# was - the controller has already dropped the dead from its own
# `enemies`, so an empty list there means this was the last.
func _on_enemy_defeated(enemy: FieldEnemy, overlay: BattleOverlay) -> void:
	_last_fallen_at = enemy.global_position
	_last_fallen_data = enemy.enemy_data
	if overlay.battle_controller.enemies.is_empty():
		return
	enemy.settle_and_free()

func _on_battle_finished(outcome: BattleOverlay.Outcome, overlay: BattleOverlay) -> void:
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
			for member in standing:
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
		BattleOverlay.Outcome.LOSE:
			get_tree().change_scene_to_file(RUN_OVER_SCENE_PATH)

# Is a fight the floor demands still standing? FloorEnemy.required,
# mirrored onto each FieldEnemy; a body queued for deletion is already
# counted as gone.
func _required_enemy_remains() -> bool:
	for node in get_tree().get_nodes_in_group("enemies"):
		var enemy := node as FieldEnemy
		if enemy == null or enemy.is_queued_for_deletion():
			continue
		if enemy.required:
			return true
	return false

# Three cards on the sand where the enemy fell, once the battle framing
# has blended away. Awaits rather than spawning inline so the cards don't
# appear under the battle camera; the caller doesn't await this, it just
# lets it run. The position is a snapshotted Vector3, not the enemy - by
# the time this resumes that node is freed.
func _spawn_reward_spread(fell_at: Vector3, fell_to: EnemyData) -> void:
	var floor_data := get_floor_data()
	if floor_data == null or floor_data.reward_pool == null:
		return
	var delay: float = reward_spread_delay_sec
	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig != null:
		delay = maxf(delay, camera_rig.battle_transition_time)
	await get_tree().create_timer(delay).timeout
	# The floor can be left, or the run ended, during that beat.
	if not is_inside_tree():
		return
	if reward_mode == RewardMode.SCREEN:
		_open_reward_screen()
		return
	var scene := load(reward_spread_scene_path) as PackedScene
	if scene == null:
		push_warning("RegionField: could not load %s; no reward spread." % reward_spread_scene_path)
		return
	var spread := scene.instantiate() as RewardSpread
	spread.pool = floor_data.reward_pool
	spread.enemy = fell_to
	add_child(spread)
	spread.global_position = fell_at

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
	# the floor and its pool.
	var floor_data := get_floor_data()
	var gold: int = RunState.rng.randi_range(mini(floor_data.gold_min, floor_data.gold_max), maxi(floor_data.gold_min, floor_data.gold_max))
	screen.setup(gold, floor_data.reward_pool, deck_panel)
	screen.closed.connect(_on_reward_screen_closed)
	add_child(screen)
	process_mode = Node.PROCESS_MODE_DISABLED

func _on_reward_screen_closed() -> void:
	process_mode = Node.PROCESS_MODE_INHERIT

# Points the ground's walked band along the route the floor actually
# takes: out of spawn, past the enemy, to the gate - or along the floor's
# own three points when it overrides that (FloorData.wear_path_override).
# Ground knows none of those - it takes three world points and draws a
# band through them (see Ground.set_wear_path()), so a floor with a
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
		var points: PackedVector2Array = floor_data.wear_path_override
		ground.set_wear_path(
			spawn + Vector3(points[0].x, 0.0, points[0].y),
			spawn + Vector3(points[1].x, 0.0, points[1].y),
			spawn + Vector3(points[2].x, 0.0, points[2].y))
		return
	# The middle point is pushed off the enemy along the exit's right, so
	# the band bends past the standing pool painted beside the crab rather
	# than running through it. Right is the exit direction turned a
	# quarter turn, not world +X, so this holds for any exit.
	var right: Vector3 = get_exit_direction().cross(Vector3.UP).normalized()
	var mid: Vector3 = enemy.global_position + right * floor_data.wear_path_mid_offset
	ground.set_wear_path(spawn, mid, gate.global_position)

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
