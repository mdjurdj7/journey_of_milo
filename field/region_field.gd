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
@export var berm_height: float = 1.4
@export var berm_width: float = 3.0
@export var berm_color: Color = Color(0.54, 0.55, 0.50)
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

@onready var wanderer: Wanderer = $Wanderer
@onready var battle_layer: CanvasLayer = $BattleLayer
@onready var deck_panel: DeckPanel = $FieldHUD/DeckPanel
@onready var hp_bar: HPBar = $FieldHUD/HPBar

var _forward: Vector3 = Vector3.FORWARD
var _forward_computed: bool = false

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

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		camera_rig.enter_battle(wanderer, enemy)
		wanderer.enter_battle_stance(enemy, battle_spacing, camera_rig.battle_transition_time)
		enemy.face_toward(wanderer, camera_rig.battle_transition_time)

	var directional_light := get_node_or_null(directional_light_path) as OvercastLight
	if directional_light:
		directional_light.enter_battle()

	var overlay := (load(BATTLE_OVERLAY_SCENE_PATH) as PackedScene).instantiate() as BattleOverlay
	battle_layer.add_child(overlay)
	# Single-enemy contact model for now - a list of one. BattleController
	# owns whatever this becomes once a fight can hold more than one enemy.
	var battle_enemies: Array[FieldEnemy] = [enemy]
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

# Four invisible collision walls around field_extents, tall enough to
# block the Wanderer, plus a low mesh berm along the inland and side
# edges. The edge behind the Wanderer (opposite get_forward()) is left
# open visually for the sea — no berm there. Both Z-boundary edges are
# positioned from get_forward()'s sign, not assumed to be +Z/-Z.
func _build_boundary() -> void:
	var half_width := field_extents.x / 2.0
	var half_depth := field_extents.y / 2.0
	var inland_z := half_depth * _forward.z
	var shoreward_z := _shoreward_wall_z(half_depth)
	# The side walls/berms span between the two actual end-cap Z positions,
	# not a symmetric ±field_extents.y/2 - inland_z and shoreward_z aren't
	# generally symmetric around 0 (see _shoreward_wall_z()'s own doc: the
	# seaward side is placed from Sea's own edge distance/margin, not
	# field_extents, and can sit much closer to spawn than the inland side).
	# Reduces to the old symmetric math exactly when shoreward_z is the
	# half_depth fallback (Sea absent), so this isn't a behavior change for
	# that case - just correct once the two sides diverge.
	var span_center_z := (inland_z + shoreward_z) / 2.0
	var span_length := absf(shoreward_z - inland_z)

	_add_wall(Vector3(0.0, wall_height / 2.0, inland_z), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(0.0, wall_height / 2.0, shoreward_z), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(-half_width, wall_height / 2.0, span_center_z), Vector3(wall_thickness, wall_height, span_length))
	_add_wall(Vector3(half_width, wall_height / 2.0, span_center_z), Vector3(wall_thickness, wall_height, span_length))

	# Berm length is extended by berm_width past the true edge so the two
	# side berms overlap the inland berm at the corners, with no gap.
	_add_berm(Vector3(0.0, berm_height / 2.0, inland_z), Vector3(field_extents.x + berm_width, berm_height, berm_width))
	_add_berm(Vector3(-half_width, berm_height / 2.0, span_center_z), Vector3(berm_width, berm_height, span_length + berm_width))
	_add_berm(Vector3(half_width, berm_height / 2.0, span_center_z), Vector3(berm_width, berm_height, span_length + berm_width))

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

func _add_wall(wall_position: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision_shape := CollisionShape3D.new()
	collision_shape.shape = shape

	var wall := StaticBody3D.new()
	wall.position = wall_position
	wall.add_child(collision_shape)

	add_child(wall)

func _add_berm(berm_position: Vector3, size: Vector3) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = berm_color
	material.roughness = 1.0
	material.metallic_specular = 0.0

	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = berm_position

	add_child(mesh_instance)
