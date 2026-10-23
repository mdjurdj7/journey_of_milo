extends Node3D
class_name CollectorDisplay

# A weapon the collector has stocked, lying on the sand beside it until it
# is bought (Collector's Display group, which makes, places and frees it).
# Placed in world axes - top_level, so the collector's own facing never
# turns it: its XZ the collector's plus an offset, its Y the relief's.
# This node carries the yaw; the model under it the rest of the turn and
# the scale, its box centred on this node in XZ and its lowest point on
# the sand. Dressed as the collector is - the painted shader on its own
# colour map, the fog pass laid over it (PaintedProp) at the collector's
# fog_factor - over a contact pool the box's size. No collision: it lies
# flat on the sand, under nothing the Wanderer would walk into.

var _model: Node3D = null
var _material: Material = null
var _fog: ShaderMaterial = null
var _shadow: ContactShadow = null
var _ground: Ground = null
var _model_path: String = ""
# The model's own length, end to end at scale 1 - its widest extent in
# any direction (a model may lie diagonal in its box), measured on dress().
var _length: float = 0.0

func _ready() -> void:
	top_level = true
	_shadow = ContactShadow.new()
	_shadow.name = "ContactShadow"
	add_child(_shadow)
	if _ground != null:
		_shadow.set_ground(_ground)

# The model at `model_path` on `colour_map_path`; a change of model
# rebuilds it. False when it can't be loaded.
func dress(model_path: String, colour_map_path: String) -> bool:
	if _model != null and model_path == _model_path:
		return true
	if _model != null:
		_model.free()
		_model = null
	_model_path = model_path
	var scene := load(model_path) as PackedScene if not model_path.is_empty() else null
	if scene == null:
		push_warning("CollectorDisplay: could not load %s; nothing shown." % model_path)
		return false
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_material = PaintedProp.material(colour_map_path, Color.WHITE)
	_fog = null
	if _material != null:
		_fog = PaintedProp.fog_pass()
		_material.next_pass = _fog
	else:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	PaintedProp.dress_model(_model, _material, self)
	_length = _measure_length(_model)
	return true

# The model's widest extent over many directions - its length end to end,
# whichever way it lies in its own box.
static func _measure_length(model: Node3D) -> float:
	var points: PackedVector3Array = PackedVector3Array()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		var xf: Transform3D = model.global_transform.affine_inverse() * mesh_instance.global_transform
		for surface in mesh_instance.mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh_instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for i in range(0, vertices.size(), 8):
				points.append(xf * vertices[i])
	var longest: float = 0.0
	for step in 64:
		# Directions spread over a sphere (the golden spiral).
		var y: float = 1.0 - 2.0 * (float(step) + 0.5) / 64.0
		var r: float = sqrt(maxf(1.0 - y * y, 0.0))
		var turn: float = float(step) * 2.39996
		var along := Vector3(cos(turn) * r, y, sin(turn) * r)
		var low: float = INF
		var high: float = -INF
		for point in points:
			var d: float = point.dot(along)
			low = minf(low, d)
			high = maxf(high, d)
		longest = maxf(longest, high - low)
	return longest

# On the sand at `world_xz` (its Y read from the ground), turned
# `rotation_deg` (YXZ, as a Node3D's), `length_m` long end to end.
func place(world_xz: Vector3, rotation_deg: Vector3, length_m: float) -> void:
	if _model == null:
		return
	rotation = Vector3(0.0, deg_to_rad(rotation_deg.y), 0.0)
	var turn := Basis.from_euler(Vector3(deg_to_rad(rotation_deg.x), 0.0, deg_to_rad(rotation_deg.z)))
	var scale_by: float = length_m / _length if _length > 0.0 else 1.0
	_model.transform = Transform3D(turn * Basis.from_scale(Vector3.ONE * scale_by), Vector3.ZERO)
	var box: AABB = PaintedProp.dress_model(_model, _material, self)
	var centre: Vector3 = box.get_center()
	_model.position = -Vector3(centre.x, box.position.y, centre.z)
	if _shadow != null:
		_shadow.footprint = Vector2(box.size.x, box.size.z) * 0.5
	var height: float = 0.0
	if _ground != null:
		var local_xz: Vector3 = _ground.to_local(Vector3(world_xz.x, 0.0, world_xz.z))
		height = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
	global_position = Vector3(world_xz.x, height, world_xz.z)

func set_ground(ground: Ground) -> void:
	_ground = ground
	if _shadow != null and ground != null:
		_shadow.set_ground(ground)

func push_fog(sky: RegionSky, fog_factor: float) -> void:
	PaintedProp.push_fog(_fog, sky, fog_factor)

# For probes: the model's length at scale 1, and the model shown, or null.
func get_model_length() -> float:
	return _length

func get_model() -> Node3D:
	return _model
