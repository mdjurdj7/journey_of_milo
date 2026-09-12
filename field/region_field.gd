extends Node3D
class_name RegionField

const BATTLE_OVERLAY_SCENE_PATH := "res://battle/battle_overlay.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"

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
@export var battle_spacing: float = 3.0
# Which of BattleTheme's two value sets the overlay applies on entering
# battle - see ui/battle_theme.gd's own rule: UI is the dark element on a
# pale world (false, default) and the pale element on a dark one (true).
@export var ui_on_dark_world: bool = false

@onready var wanderer: Wanderer = $Wanderer
@onready var battle_layer: CanvasLayer = $BattleLayer
@onready var ground: Ground = $Ground

var _forward: Vector3 = Vector3.FORWARD
var _forward_computed: bool = false

func _ready() -> void:
	# Ensures forward is computed (and printed) even if no child asked for
	# it first; a no-op if one already did.
	get_forward()

	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		enemy.contacted.connect(_on_enemy_contacted)

	_reposition_enemies_along_forward()
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
# axis its .tscn transform happened to assume. Y is set from Ground.
# get_height_at() at the enemy's new XZ - the same function props should
# use to sit on the surface at spawn - since FieldEnemy has no gravity/
# _physics_process of its own to settle onto the relief naturally the way
# the physically-simulated Wanderer does.
#
# get_height_at() alone isn't the whole story though: FieldEnemy._spawn_
# model()'s own AABB grounding places the model's feet at body-local
# Y = model_ground_offset, not Y = 0 - so the body's own global Y has to
# be get_height_at() MINUS that offset for the feet (not the body origin)
# to land on the actual terrain surface. Reads model_ground_offset
# directly since it's already a public @export on FieldEnemy.
func _reposition_enemies_along_forward() -> void:
	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		var distance := (enemy.global_position - wanderer.global_position).length()
		var new_position: Vector3 = wanderer.global_position + _forward * distance
		new_position.y = ground.get_height_at(Vector2(new_position.x, new_position.z)) - enemy.model_ground_offset
		enemy.global_position = new_position

func _on_enemy_contacted(enemy: FieldEnemy) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		camera_rig.enter_battle(wanderer, enemy)
		wanderer.enter_battle_stance(enemy, battle_spacing, camera_rig.battle_transition_time)
		enemy.face_toward(wanderer, camera_rig.battle_transition_time)

	var overlay := (load(BATTLE_OVERLAY_SCENE_PATH) as PackedScene).instantiate() as BattleOverlay
	battle_layer.add_child(overlay)
	# Single-enemy contact model for now - a list of one. BattleController
	# owns whatever this becomes once a fight can hold more than one enemy.
	var battle_enemies: Array[FieldEnemy] = [enemy]
	overlay.enter_battle(ui_on_dark_world, battle_enemies)
	overlay.battle_finished.connect(_on_battle_finished.bind(enemy, overlay))

func _on_battle_finished(outcome: BattleOverlay.Outcome, enemy: FieldEnemy, overlay: BattleOverlay) -> void:
	overlay.queue_free()
	process_mode = Node.PROCESS_MODE_INHERIT

	wanderer.exit_battle_stance()

	var camera_rig := get_node_or_null(camera_rig_path) as CameraRig
	if camera_rig:
		camera_rig.exit_battle()

	match outcome:
		BattleOverlay.Outcome.WIN:
			enemy.queue_free()
		BattleOverlay.Outcome.ESCAPE:
			_push_wanderer_away_from(enemy)
		BattleOverlay.Outcome.LOSE:
			get_tree().change_scene_to_file(RUN_OVER_SCENE_PATH)

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

	_add_wall(Vector3(0.0, wall_height / 2.0, inland_z), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(0.0, wall_height / 2.0, _shoreward_wall_z(half_depth)), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(-half_width, wall_height / 2.0, 0.0), Vector3(wall_thickness, wall_height, field_extents.y))
	_add_wall(Vector3(half_width, wall_height / 2.0, 0.0), Vector3(wall_thickness, wall_height, field_extents.y))

	# Berm length is extended by berm_width past the true edge so the two
	# side berms overlap the inland berm at the corners, with no gap.
	_add_berm(Vector3(0.0, berm_height / 2.0, inland_z), Vector3(field_extents.x + berm_width, berm_height, berm_width))
	_add_berm(Vector3(-half_width, berm_height / 2.0, 0.0), Vector3(berm_width, berm_height, field_extents.y + berm_width))
	_add_berm(Vector3(half_width, berm_height / 2.0, 0.0), Vector3(berm_width, berm_height, field_extents.y + berm_width))

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
