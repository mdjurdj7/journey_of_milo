extends Node3D
class_name DressingGroup

# A few hand-placed stones and grass tufts dressing one spot (around a
# hull), where the scatter's random clusters and its prop margin can't go:
# each DressingItem at its own offset, grounded on the relief and sunk by
# its sink_fraction. Stones wear their colour map under the painted
# shader with its fog pass (PaintedProp, as the scatter's textured stones
# do); tufts are the scatter's cards (tuft_card.gdshader). Looks only: no
# collision, so it changes neither the walk grid nor the battle space.
# Spawned from FloorData as a FloorProp (its position the group's origin;
# no yaw). Hide it with the node's own `visible`.

const CARD_SHADER_PATH := "res://field/tuft_card.gdshader"

@export var items: Array[DressingItem] = []:
	set(value):
		for item in items:
			if item != null and item.changed.is_connected(_rebuild):
				item.changed.disconnect(_rebuild)
		items = value
		for item in items:
			if item != null:
				item.changed.connect(_rebuild)
		_rebuild()
# The tufts' sway (tuft_card.gdshader's sway_amount) - the marram's.
@export_range(0.0, 0.2, 0.001) var card_sway: float = 0.04:
	set(value):
		card_sway = value
		for material in _card_materials:
			material.set_shader_parameter("sway_amount", value)
# Aimed by RegionField when spawned as a floor prop.
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

var _ground: Ground = null
var _sky: RegionSky = null
var _sea: Sea = null
var _built: Array[Node3D] = []
var _fog_passes: Array[ShaderMaterial] = []
var _card_materials: Array[ShaderMaterial] = []
var _card_forward: Vector2 = Vector2.ZERO
var _ready_done: bool = false

func _ready() -> void:
	_ground = get_node_or_null(ground_path) as Ground
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field != null:
		_sky = region_field.get_region_sky()
		_sea = region_field.get_node_or_null(^"Sea") as Sea
	if _sky != null:
		_sky.fog_changed.connect(_push_fog)
	if _ground == null:
		push_warning("DressingGroup '%s': ground_path did not resolve to a Ground; not grounded." % name)
	else:
		_ground.relief_rebuilt.connect(_rebuild)
	_ready_done = true
	_rebuild()

func _process(_delta: float) -> void:
	_push_card_forward()

# Frees what was built and builds every item again - placements are few,
# so a live edit just redoes them all.
func _rebuild() -> void:
	if not _ready_done:
		return
	for node in _built:
		node.free()
	_built.clear()
	_fog_passes.clear()
	_card_materials.clear()
	_card_forward = Vector2.ZERO
	for item in items:
		if item == null:
			continue
		if not item.card_texture_path.is_empty():
			_build_card(item)
		elif not item.model_path.is_empty():
			_build_model(item)
	_push_fog()
	_push_card_forward()

func _build_model(item: DressingItem) -> void:
	var entry := ScatterEntry.new()
	entry.mesh_path = item.model_path
	var mesh: Mesh = ScatterMeshes.mesh_for(entry)
	if mesh == null:
		return
	var instance := MeshInstance3D.new()
	instance.name = "Stone%d" % _built.size()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var painted: ShaderMaterial = PaintedProp.material(item.colour_map_path, item.tint)
	if painted != null:
		var fog: ShaderMaterial = PaintedProp.fog_pass()
		if fog != null:
			painted.next_pass = fog
			_fog_passes.append(fog)
		instance.material_override = painted
	else:
		var flat := Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
		flat.albedo_color = item.tint
		instance.material_override = flat
	var box: AABB = mesh.get_aabb()
	var scale_factor: float = maxf(item.size, 0.001)
	var turn := Basis(Vector3.UP, deg_to_rad(item.yaw_degrees)) * Basis(Vector3.RIGHT, deg_to_rad(item.tilt_degrees.x)) * Basis(Vector3.BACK, deg_to_rad(item.tilt_degrees.y))
	# Bottom on the sand, then down by sink_fraction of its height.
	var lift: float = (-box.position.y - box.size.y * clampf(item.sink_fraction, 0.0, 1.0)) * scale_factor
	instance.transform = Transform3D(turn.scaled(Vector3.ONE * scale_factor), _ground_point(item.offset) + Vector3(0.0, lift, 0.0))
	add_child(instance)
	_built.append(instance)

# One card as the scatter draws its tufts: a one-instance MultiMesh (the
# shader reads its yaw, mirror and presence from INSTANCE_CUSTOM).
func _build_card(item: DressingItem) -> void:
	var card := ScatterCard.new()
	card.texture_path = item.card_texture_path
	card.height_m = maxf(item.size, 0.01)
	var mesh: Mesh = ScatterMeshes.card_mesh(card)
	var texture: Texture2D = ScatterMeshes.card_texture(card)
	var shader := load(CARD_SHADER_PATH) as Shader
	if mesh == null or texture == null or shader == null:
		return
	var at: Vector3 = _ground_point(item.offset)
	if _sea != null and at.y + global_position.y < _sea.sea_level:
		push_warning("DressingGroup '%s': a tuft at %s stands under the sea." % [name, item.offset])
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.mesh = mesh
	multimesh.instance_count = 1
	multimesh.set_instance_transform(0, Transform3D.IDENTITY)
	multimesh.set_instance_color(0, Color(1.0, 1.0, 1.0))
	multimesh.set_instance_custom_data(0, Color(deg_to_rad(item.yaw_degrees), -1.0 if item.mirrored else 1.0, 1.0, 0.0))
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("albedo_texture", texture)
	material.set_shader_parameter("albedo_tint", item.tint)
	material.set_shader_parameter("card_height", card.height_m)
	material.set_shader_parameter("sway_amount", card_sway)
	_card_materials.append(material)
	var instance := MultiMeshInstance3D.new()
	instance.name = "Tuft%d" % _built.size()
	# The spot on the node, not the instance, so it reads back like a stone's.
	instance.position = at - Vector3(0.0, card.height_m * clampf(item.sink_fraction, 0.0, 1.0), 0.0)
	instance.multimesh = multimesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(instance)
	_built.append(instance)

# The relief under `offset`, in this node's space (it never turns).
func _ground_point(offset: Vector2) -> Vector3:
	var height: float = global_position.y
	if _ground != null:
		var world := Vector3(global_position.x + offset.x, 0.0, global_position.z + offset.y)
		var local: Vector3 = _ground.to_local(world)
		height = _ground.get_height_at(Vector2(local.x, local.z))
	return Vector3(offset.x, height - global_position.y, offset.y)

func _push_fog() -> void:
	for fog in _fog_passes:
		PaintedProp.push_fog(fog, _sky, 1.0)

# The live camera's ground forward into every card, as FieldScatter does.
func _push_card_forward() -> void:
	if _card_materials.is_empty() or not is_inside_tree():
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var forward: Vector3 = -camera.global_transform.basis.z
	var ground := Vector2(forward.x, forward.z)
	if ground.length() < 1.0e-4:
		return
	ground = ground.normalized()
	if _card_forward != Vector2.ZERO and ground.distance_to(_card_forward) < 1.0e-4:
		return
	_card_forward = ground
	for material in _card_materials:
		material.set_shader_parameter("camera_forward", ground)
