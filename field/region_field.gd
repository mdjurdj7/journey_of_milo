extends Node3D

const BATTLE_STUB_SCENE_PATH := "res://battle/battle_stub.tscn"
const RUN_OVER_SCENE_PATH := "res://run/run_over.tscn"

@export var escape_push_distance: float = 4.0

# Playable boundary, centered on origin. X = width (left/right side
# edges), Y-component of field_extents = depth along Z (the walk axis:
# +Z is inland, toward the Tower; -Z is behind the Wanderer's spawn).
@export var field_extents: Vector2 = Vector2(80.0, 50.0)
@export var wall_height: float = 6.0
@export var wall_thickness: float = 2.0
@export var berm_height: float = 1.4
@export var berm_width: float = 3.0
@export var berm_color: Color = Color(0.54, 0.55, 0.50)
@export var sea_path: NodePath = ^"../Sea"
@export var shoreline_wall_margin: float = 5.0

@onready var wanderer: CharacterBody3D = $Wanderer
@onready var battle_layer: CanvasLayer = $BattleLayer

func _ready() -> void:
	for enemy: FieldEnemy in get_tree().get_nodes_in_group("enemies"):
		enemy.contacted.connect(_on_enemy_contacted)

	_build_boundary()

func _on_enemy_contacted(enemy: FieldEnemy) -> void:
	process_mode = Node.PROCESS_MODE_DISABLED

	var stub := (load(BATTLE_STUB_SCENE_PATH) as PackedScene).instantiate() as BattleStub
	battle_layer.add_child(stub)
	stub.set_enemy_id(enemy.enemy_id)
	stub.battle_finished.connect(_on_battle_finished.bind(enemy, stub))

func _on_battle_finished(outcome: BattleStub.Outcome, enemy: FieldEnemy, stub: BattleStub) -> void:
	stub.queue_free()
	process_mode = Node.PROCESS_MODE_INHERIT

	match outcome:
		BattleStub.Outcome.WIN:
			enemy.queue_free()
		BattleStub.Outcome.ESCAPE:
			_push_wanderer_away_from(enemy)
		BattleStub.Outcome.LOSE:
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
# block the Wanderer, plus a low mesh berm along the three land edges
# (+Z inland, -X and +X sides). The -Z edge, behind the Wanderer's
# spawn, is left open visually for a future water plane — no berm there.
func _build_boundary() -> void:
	var half_width := field_extents.x / 2.0
	var half_depth := field_extents.y / 2.0

	_add_wall(Vector3(0.0, wall_height / 2.0, half_depth), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(0.0, wall_height / 2.0, _shoreward_wall_z(half_depth)), Vector3(field_extents.x, wall_height, wall_thickness))
	_add_wall(Vector3(-half_width, wall_height / 2.0, 0.0), Vector3(wall_thickness, wall_height, field_extents.y))
	_add_wall(Vector3(half_width, wall_height / 2.0, 0.0), Vector3(wall_thickness, wall_height, field_extents.y))

	# Berm length is extended by berm_width past the true edge so the two
	# side berms overlap the inland berm at the corners, with no gap.
	_add_berm(Vector3(0.0, berm_height / 2.0, half_depth), Vector3(field_extents.x + berm_width, berm_height, berm_width))
	_add_berm(Vector3(-half_width, berm_height / 2.0, 0.0), Vector3(berm_width, berm_height, field_extents.y + berm_width))
	_add_berm(Vector3(half_width, berm_height / 2.0, 0.0), Vector3(berm_width, berm_height, field_extents.y + berm_width))

# Pushed shoreline_wall_margin past the sea's near edge (derived from
# the Wanderer's spawn and the Sea's own sea_edge_distance) rather than
# sitting at the fixed field boundary, so the Wanderer can walk down to,
# and a little into, the water. Falls back to the fixed half_depth
# boundary if the Sea node isn't present.
func _shoreward_wall_z(half_depth: float) -> float:
	var sea := get_node_or_null(sea_path) as Sea
	if sea == null:
		return -half_depth
	var near_edge_z := wanderer.global_position.z - sea.sea_edge_distance
	return near_edge_z - shoreline_wall_margin

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
