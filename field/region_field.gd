extends Node3D
class_name RegionField

const BATTLE_OVERLAY_SCENE_PATH := "res://battle/battle_overlay.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"
const STARTING_CHARACTER_PATH := "res://run/data/wanderer.tres"
const BATTLE_THEME_PATH := "res://ui/battle_theme.tres"

# Floor-exit prototype. Emitted once, when the last "enemies"-group member
# is defeated - see _on_battle_finished()'s own WIN branch.
signal floor_cleared

@export var escape_push_distance: float = 4.0

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
@export var tower_path: NodePath = ^"Tower"
@export var camera_rig_path: NodePath = ^"CameraPivot"
@export var directional_light_path: NodePath = ^"DirectionalLight3D"
@export var exit_gate_path: NodePath = ^"ExitGate"
# Distance beyond the (currently sole) enemy's own position, along
# get_forward() - see _setup_exit_gate()'s own doc. 4.0 pairs with the
# enemy's own authored distance (6.0, see region_field.tscn's FieldEnemy
# transform) to land the gate's own line at 10.0 from spawn - 4.0 clear of
# the inland wall's near face at field_extents.y/2 - wall_thickness/2 = 14.0
# in this scene's current field_extents/wall_thickness.
@export var exit_gate_distance_beyond_enemy: float = 4.0
@export var battle_spacing: float = 3.0
# Which of BattleTheme's two value sets the overlay applies on entering
# battle - see ui/battle_theme.gd's own rule: UI is the dark element on a
# pale world (false, default) and the pale element on a dark one (true).
@export var ui_on_dark_world: bool = false

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
# behavior this wants. Gated on wade_drain_enabled so it can be switched
# off for testing without touching the other wade exports.
@export var wade_drain_enabled: bool = false
# distance_in_water (Ground.get_landmass_distance(), floored at 0) is a
# horizontal distance past the shoreline, not a real vertical depth - this
# fakes an outward slope: effective_depth = distance_in_water *
# wade_slope_per_metre.
@export var wade_slope_per_metre: float = 0.15
# Below this effective depth, no drain at all (ankle-deep is free).
@export var wade_depth_threshold: float = 0.05
@export var wade_drain_rate_per_metre: float = 40.0
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

func _ready() -> void:
	# Starts the run once per game session, seeding HP and the starting
	# Belongings from RunState.new_run()'s own doc - guarded on character
	# being unset rather than called unconditionally, because the floor-exit
	# prototype's own reload_current_scene() (see _on_floor_exited()) re-runs
	# this same _ready(), and an unconditional call would wipe the run's HP/
	# deck back to starting values on every floor transition. A proper
	# run-start flow (e.g. a character-select screen) replaces this call
	# site later without RunState itself needing to change. Must run before
	# anything below reads RunState.deck.
	if RunState.character == null:
		RunState.new_run(load(STARTING_CHARACTER_PATH) as CharacterData)

	# Ensures forward is computed (and printed) even if no child asked for
	# it first; a no-op if one already did.
	get_forward()

	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		enemy.contacted.connect(_on_enemy_contacted)

	_reposition_enemies_along_forward()
	_setup_exit_gate()
	_setup_field_hud()
	_build_boundary()
	_setup_exit_gate_channel()

	# Keeps the walls in sync with live landmass-shape tuning: Ground emits
	# relief_rebuilt after every mesh/collision rebuild (any landmass/relief
	# export's own setter), and _rebuild_boundary_walls() reads Ground's
	# landmass exports directly to place the walls - see its own doc.
	var ground := get_node_or_null(ground_path) as Ground
	if ground != null:
		ground.relief_rebuilt.connect(_rebuild_boundary_walls)

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
# Wanderer's spawn to the Tower. Nothing else should assume an axis or
# sign for "ahead" — call get_forward() instead. Falls back to Godot's
# own -Z forward convention if the Tower isn't present.
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
	var tower := get_node_or_null(tower_path) as Node3D
	if spawn_node == null or tower == null:
		return Vector3.FORWARD
	var to_tower := tower.global_position - spawn_node.global_position
	to_tower.y = 0.0
	return to_tower.normalized() if to_tower.length() > 0.0001 else Vector3.FORWARD

func get_forward() -> Vector3:
	if not _forward_computed:
		_forward = _compute_forward()
		_forward_computed = true
		print("RegionField: forward = %s" % str(_forward))
	return _forward

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

# Preserves each enemy's authored distance from the Wanderer's spawn,
# but re-derives the direction along get_forward() instead of whatever
# axis its .tscn transform happened to assume. Y is left alone here -
# FieldEnemy grounds its own Y against Ground.get_height_at() itself (see
# its _ground_to_relief(), called once deferred from _ready() and again
# on every Ground.relief_rebuilt), which also means it stays correct
# across live relief edits, not just at this one spawn moment.
func _reposition_enemies_along_forward() -> void:
	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		var distance := (enemy.global_position - wanderer.global_position).length()
		enemy.global_position = wanderer.global_position + _forward * distance

# Applies this region's own on-pale/on-dark value set to the shared
# BattleTheme resource - deck_panel and hp_bar are both styled from it
# (see DeckPanel/HPBar's own "CardFace" color reads) same as everything
# BattleOverlay itself styles, but both live outside BattleOverlay's own
# tree (FieldHUD, not BattleLayer), so nothing else ever applies this for
# them. refresh_style() re-reads those colors immediately after, since
# (like CardView/EnemyStatus) both cache them via override at _ready()
# rather than tracking the Theme resource live - without this, they'd
# render with whatever value set the theme resource happened to already
# be on. Also seeds the field-mode display (whole starting deck) deck_
# panel starts in.
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

# Positions and orients the ExitGate along get_forward(), a fixed distance
# beyond the (currently sole) enemy's own position, then wires it to this
# field's floor_cleared/floor_exited handshake. Done here rather than in
# ExitGate's own _ready(): children's _ready() runs before their parent's
# (see get_forward()'s own doc on the same bottom-up ordering), and both
# get_forward() and _reposition_enemies_along_forward() only resolve inside
# THIS _ready() - so an ExitGate trying to position itself would always be
# a frame too early. Same rotation.y = atan2(-dir.x, -dir.z) convention
# FieldEnemy._face_shore()/face_toward() already use to align a node's
# local -Z with a world direction.
func _setup_exit_gate() -> void:
	var exit_gate := get_node_or_null(exit_gate_path) as ExitGate
	if exit_gate == null:
		push_warning("RegionField: exit_gate_path did not resolve to an ExitGate; no floor exit.")
		return

	var enemies := get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		push_warning("RegionField: no enemies to measure the exit gate's distance from.")
		return
	var enemy := enemies[0] as FieldEnemy

	exit_gate.global_position = enemy.global_position + _forward * exit_gate_distance_beyond_enemy
	exit_gate.rotation.y = atan2(-_forward.x, -_forward.z)

	floor_cleared.connect(exit_gate.open)
	exit_gate.floor_exited.connect(_on_floor_exited)

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

# RunState.current_floor_index persists (see RunState.deck's own doc on
# what survives a battle; this is the same idea across a floor) because
# reload_current_scene() only re-runs this scene's own _ready(), and
# RunState is an autoload - it isn't touched by the reload at all. The
# guarded RunState.new_run() call in _ready() is what actually keeps HP/
# deck from being wiped alongside it - see that guard's own doc.
func _on_floor_exited() -> void:
	RunState.current_floor_index += 1
	print("RegionField: floor_exited, current_floor_index = %d" % RunState.current_floor_index)
	get_tree().reload_current_scene()

func _on_enemy_contacted(enemy: FieldEnemy) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

	# Overlay first: CameraRig's battle fit needs the card hand's resting
	# top edge, and that only exists once the overlay's layout is in the
	# tree (anchors resolve synchronously on add_child).
	var overlay := (load(BATTLE_OVERLAY_SCENE_PATH) as PackedScene).instantiate() as BattleOverlay
	battle_layer.add_child(overlay)
	# Single-enemy contact model for now - a list of one. BattleController
	# owns whatever this becomes once a fight can hold more than one enemy.
	var battle_enemies: Array[FieldEnemy] = [enemy]

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		var viewport_height: float = overlay.get_viewport().get_visible_rect().size.y
		var hand_top_fraction: float = overlay.hand_container.get_rest_top_y() / maxf(viewport_height, 1.0)
		camera_rig.enter_battle(wanderer, battle_enemies, hand_top_fraction)
		wanderer.enter_battle_stance(enemy, battle_spacing, camera_rig.battle_transition_time)
		enemy.face_toward(wanderer, camera_rig.battle_transition_time)

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.enter_battle()

	var transition_time: float = camera_rig.battle_transition_time if camera_rig != null else 0.0
	overlay.enter_battle(ui_on_dark_world, battle_enemies, deck_panel, hp_bar, transition_time, wanderer)
	overlay.battle_finished.connect(_on_battle_finished.bind(enemy, overlay))
	# Only reachable now - enter_battle() is what creates battle_controller
	# (see Wanderer.bind_to_battle()'s own doc).
	wanderer.bind_to_battle(overlay.battle_controller)

func _on_battle_finished(outcome: BattleOverlay.Outcome, enemy: FieldEnemy, overlay: BattleOverlay) -> void:
	wanderer.unbind_battle()
	_apply_consumed_removals(overlay.battle_controller.deck)
	overlay.queue_free()
	process_mode = Node.PROCESS_MODE_INHERIT

	deck_panel.show_whole_deck(RunState.deck)

	wanderer.exit_battle_stance()

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		camera_rig.exit_battle()

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.exit_battle()

	match outcome:
		BattleOverlay.Outcome.WIN:
			# Snapshotted before queue_free() below: queue_free() defers the
			# actual removal from the "enemies" group to end of frame, so
			# this enemy would still count itself here either way - taken
			# before freeing just so that ordering isn't load-bearing.
			var was_last_enemy: bool = get_tree().get_nodes_in_group("enemies").size() <= 1
			# enemy_status lives under FieldHUD, not as enemy's own child
			# (see FieldEnemy.enemy_status's own doc) - freeing enemy alone
			# would leave it behind as an orphaned, permanently-invisible
			# leak.
			if enemy.enemy_status != null:
				enemy.enemy_status.queue_free()
			enemy.queue_free()
			if was_last_enemy:
				floor_cleared.emit()
		BattleOverlay.Outcome.ESCAPE:
			_push_wanderer_away_from(enemy)
		BattleOverlay.Outcome.LOSE:
			get_tree().change_scene_to_file(RUN_OVER_SCENE_PATH)

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

# The push distance must clear the enemy's own contact radius, or the
# Wanderer lands back inside the Area3D and either re-triggers contact
# immediately or can't leave it. Clamp up to radius + a small margin and
# push_warning so a misconfigured pair is loud, not a silent soft-lock.
func _push_wanderer_away_from(enemy: FieldEnemy) -> void:
	var push_distance := escape_push_distance
	var min_safe_distance: float = enemy.contact_radius + 0.5
	if push_distance <= enemy.contact_radius:
		push_warning("RegionField: escape_push_distance (%.2f) does not clear enemy '%s' contact_radius (%.2f); clamping to %.2f." % [push_distance, enemy.enemy_id, enemy.contact_radius, min_safe_distance])
		push_distance = min_safe_distance

	var push_dir := wanderer.global_position - enemy.global_position
	push_dir.y = 0.0
	push_dir = push_dir.normalized() if push_dir.length() > 0.0001 else Vector3.BACK

	wanderer.global_position = enemy.global_position + push_dir * push_distance

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
# the two is "inland" is whichever lies further along get_forward() -
# never assumed to be -Z.
func _build_mask_boundary_walls(land_bounds: Rect2) -> void:
	var bounds: Rect2 = land_bounds.grow(side_wade_margin)
	var center: Vector2 = bounds.get_center()
	var end_cap_width: float = bounds.size.x + wall_thickness
	var min_z_is_inland: bool = _forward.z < 0.0

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
