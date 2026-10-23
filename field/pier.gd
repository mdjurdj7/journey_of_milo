extends WalkSurface
class_name Pier

# A wooden pier run out level from a shoreline over ground that falls
# away beneath it: a deck strip, a platform at its end and boat steps
# down off the platform to the ground - one walk surface, with rails.
#
# Laid out in its own XZ (x = X, y = Z, from its node origin), which a
# floor places at its spawn with no turn, so the floor's layout numbers go
# in as they are (FloorData.props: position zero; yaw_degrees turns it
# all about the origin if ever set). Heights are over the floor's land
# level (Ground.get_land_level()), the scale an elevation painting's are
# on: the deck and platform tops at deck_height_m; the steps falling in a
# straight line from deck height at steps_from to steps_foot_height_m at
# steps_to, then on under the sand by steps_sink_m so the foot has no lip.
#
# What he walks on is what he collides with: boxes on this body for the
# deck, the platform and the steps, read back through get_top_height_at()
# by his ground hold and the walk grid (WalkSurface). The rails are boxes
# too - rail_height_m tall on the lines in `rails` at deck height, and on
# both sides of the steps steps_rail_inset_m in from their edges, sloped
# with them - drawn by nothing: invisible to the walk grid like the rest
# of a walk surface, which keeps him on the planks by the drop alone.
#
# Drawn by model_path, a glb in the same frame on the same height scale,
# set at the land level - or, with none, by graybox boxes over the
# collision. With colour_map_path the model wears it under the painted
# shader with its fog pass, as the props on the sand do.
#
# One height per XZ (WalkSurface): wherever the pier stands, the walk
# height is its top, so the sand under it must be out of his reach - the
# floor seals it with ledges. No enemy stands on it (none grounds on a
# walk surface), and it leaves no footprints. Scatter isn't kept off its
# outline: the reeds grow on under it.

@export_group("Shape")
@export var deck_root: Vector2 = Vector2.ZERO:
	set(value):
		deck_root = value
		_rebuild()
@export var deck_end: Vector2 = Vector2(12.0, 0.0):
	set(value):
		deck_end = value
		_rebuild()
@export var deck_width_m: float = 2.0:
	set(value):
		deck_width_m = value
		_rebuild()
# The deck's and the platform's top over the land level.
@export var deck_height_m: float = 1.2:
	set(value):
		deck_height_m = value
		_rebuild()
@export var deck_thickness_m: float = 0.25:
	set(value):
		deck_thickness_m = value
		_rebuild()
# XZ rect at deck height; zero size = no platform.
@export var platform: Rect2 = Rect2():
	set(value):
		platform = value
		_rebuild()
# The steps' top edge's middle (at deck height) and their foot's.
@export var steps_from: Vector2 = Vector2(12.0, 0.0):
	set(value):
		steps_from = value
		_rebuild()
@export var steps_to: Vector2 = Vector2(16.0, 0.0):
	set(value):
		steps_to = value
		_rebuild()
@export var steps_width_m: float = 1.4:
	set(value):
		steps_width_m = value
		_rebuild()
# The ground at the steps' foot, over the land level.
@export var steps_foot_height_m: float = 0.0:
	set(value):
		steps_foot_height_m = value
		_rebuild()
@export var steps_sink_m: float = 0.15:
	set(value):
		steps_sink_m = value
		_rebuild()

@export_group("Rails")
# Polylines at deck height, XZ in the pier's frame.
@export var rails: Array[PackedVector2Array] = []:
	set(value):
		rails = value
		_rebuild()
@export var rail_height_m: float = 0.95:
	set(value):
		rail_height_m = value
		_rebuild()
@export var rail_thickness_m: float = 0.08:
	set(value):
		rail_thickness_m = value
		_rebuild()
# The steps' rails, in from each side of the steps - the stringers' line.
@export var steps_rail_inset_m: float = 0.06:
	set(value):
		steps_rail_inset_m = value
		_rebuild()

@export_group("Look")
# A glb in the pier's frame, its heights over the land level. Empty = the
# graybox boxes.
@export_file("*.glb") var model_path: String = "":
	set(value):
		model_path = value
		_rebuild()
# Its colour map under the painted shader; empty = its own materials.
@export_file("*.png", "*.jpg") var colour_map_path: String = "":
	set(value):
		colour_map_path = value
		_rebuild()
@export_range(0.0, 1.0, 0.01) var fog_factor: float = 1.0:
	set(value):
		fog_factor = value
		_push_fog()
@export var wood_color: Color = Color(0.45, 0.36, 0.27):
	set(value):
		wood_color = value
		_apply_graybox_material()
# The render layers its meshes are on besides layer 1: a figure on it
# lays its contact pool here (ContactShadowData.perch_layers), and the
# body is in ContactShadow.STANDABLE_GROUP so the pool finds the top.
@export_flags_3d_render var standable_layers: int = 1 << 17:
	set(value):
		standable_layers = value
		_rebuild()

@export_group("")
@export var ground_path: NodePath = ^"../Ground"
@export var region_field_path: NodePath = ^"../.."

var _ground: Ground = null
var _sky: RegionSky = null
var _graybox_material: StandardMaterial3D = null
var _fog: ShaderMaterial = null
# The deck top, local Y, as last built.
var _deck_top: float = 0.0
var _built: bool = false
var _generated: Array[Node] = []

func _ready() -> void:
	add_to_group(WALK_SURFACE_GROUP)
	add_to_group(ContactShadow.STANDABLE_GROUP)
	# Raycast and stood on during a fight's freeze too.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var region_field := get_node_or_null(region_field_path) as RegionField
	_sky = region_field.get_region_sky() if region_field != null else null
	if _sky != null and not _sky.fog_changed.is_connected(_push_fog):
		_sky.fog_changed.connect(_push_fog)
	_rebuild()

# FloorProp placement: the origin at the placement's XZ, the frame turned
# yaw degrees about it (rotation.y). Roll is ignored.
func set_floor_placement(placement: Vector3, yaw_degrees: float, _roll_degrees: float) -> void:
	position = Vector3(placement.x, 0.0, placement.z)
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)

func get_top_height_at(world_xz: Vector2) -> float:
	if not _built:
		return -INF
	var p: Vector2 = _to_pier(world_xz)
	if _on_deck(p) or (platform.has_area() and platform.has_point(p)):
		return global_position.y + _deck_top
	var along: float = _steps_along(p)
	if along >= 0.0:
		return global_position.y + _deck_top - along * _steps_fall()
	return -INF

func get_top_normal_at(world_xz: Vector2) -> Vector3:
	if not _built:
		return Vector3.UP
	var p: Vector2 = _to_pier(world_xz)
	if _on_deck(p) or (platform.has_area() and platform.has_point(p)) or _steps_along(p) < 0.0:
		return Vector3.UP
	var dir: Vector2 = _steps_dir()
	var slope: float = atan(_steps_fall())
	var local := Vector3(dir.x * sin(slope), cos(slope), dir.y * sin(slope))
	return (global_transform.basis * local).normalized()

func takes_footprints() -> bool:
	return false

# --- the shape, in the pier's own XZ ---

func _to_pier(world_xz: Vector2) -> Vector2:
	var local: Vector3 = global_transform.affine_inverse() * Vector3(world_xz.x, global_position.y, world_xz.y)
	return Vector2(local.x, local.z)

func _on_deck(p: Vector2) -> bool:
	var axis: Vector2 = deck_end - deck_root
	var length: float = axis.length()
	if length < 0.001:
		return false
	var dir: Vector2 = axis / length
	var rel: Vector2 = p - deck_root
	var along: float = rel.dot(dir)
	return along >= 0.0 and along <= length and absf(rel.cross(dir)) <= deck_width_m * 0.5

func _steps_dir() -> Vector2:
	var axis: Vector2 = steps_to - steps_from
	return axis.normalized() if axis.length() > 0.001 else Vector2.RIGHT

func _steps_run() -> float:
	return (steps_to - steps_from).length()

# Metres of fall per metre along the steps.
func _steps_fall() -> float:
	return (deck_height_m - steps_foot_height_m) / maxf(_steps_run(), 0.001)

# How far along the steps (sink included) a point is, or -1 off them.
func _steps_along(p: Vector2) -> float:
	var run: float = _steps_run()
	if run < 0.001:
		return -1.0
	var dir: Vector2 = _steps_dir()
	var rel: Vector2 = p - steps_from
	var along: float = rel.dot(dir)
	var past: float = steps_sink_m / maxf(_steps_fall(), 0.001)
	if along < 0.0 or along > run + past or absf(rel.cross(dir)) > steps_width_m * 0.5:
		return -1.0
	return along

func _get_ground() -> Ground:
	if _ground == null and is_inside_tree():
		_ground = get_node_or_null(ground_path) as Ground
	return _ground

# --- building ---

func _rebuild() -> void:
	if not is_inside_tree():
		return
	var ground: Ground = _get_ground()
	if ground == null:
		push_warning("Pier '%s': ground_path did not resolve to a Ground; not built." % name)
		return
	for node in _generated:
		node.free()
	_generated.clear()
	_fog = null
	# The land level is Ground's local Y; the pier's own frame is only
	# ever turned about Y, so the offset carries over.
	var land: float = to_local(ground.to_global(Vector3(0.0, ground.get_land_level(), 0.0))).y
	_deck_top = land + deck_height_m
	_built = true
	var drawn: bool = model_path.is_empty()
	var thickness: float = deck_thickness_m
	# The deck strip.
	var axis: Vector2 = deck_end - deck_root
	if axis.length() > 0.001:
		var mid: Vector2 = (deck_root + deck_end) * 0.5
		_add_box(Vector3(axis.length(), thickness, deck_width_m), _flat_basis(axis), Vector3(mid.x, _deck_top - thickness * 0.5, mid.y), drawn)
	# The platform.
	if platform.has_area():
		var centre: Vector2 = platform.get_center()
		_add_box(Vector3(platform.size.x, thickness, platform.size.y), Basis(), Vector3(centre.x, _deck_top - thickness * 0.5, centre.y), drawn)
	# The steps: one sloped surface from deck height down past the foot.
	var run: float = _steps_run()
	if run > 0.001:
		var slope: float = atan(_steps_fall())
		var past: float = steps_sink_m / maxf(_steps_fall(), 0.001)
		var total: float = run + past
		var steps_basis: Basis = _sloped_basis(_steps_dir(), slope)
		var dir: Vector2 = _steps_dir()
		var mid_top := Vector3(steps_from.x + dir.x * total * 0.5, _deck_top - total * 0.5 * _steps_fall(), steps_from.y + dir.y * total * 0.5)
		var length: float = total / cos(slope)
		_add_box(Vector3(length, thickness, steps_width_m), steps_basis, mid_top + steps_basis * Vector3(0.0, -thickness * 0.5, 0.0), drawn)
		# Its rails, in from both sides, sloped with it, from the top edge
		# to the foot.
		var rail_length: float = run / cos(slope)
		var rail_mid := Vector3(steps_from.x + dir.x * run * 0.5, _deck_top - run * 0.5 * _steps_fall(), steps_from.y + dir.y * run * 0.5)
		var across := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var offset: Vector2 = across * side * (steps_width_m * 0.5 - steps_rail_inset_m)
			_add_box(Vector3(rail_length, rail_height_m, rail_thickness_m), steps_basis, rail_mid + Vector3(offset.x, 0.0, offset.y) + steps_basis * Vector3(0.0, rail_height_m * 0.5, 0.0), false)
	# The level rails.
	for line in rails:
		for i in range(1, line.size()):
			var a: Vector2 = line[i - 1]
			var b: Vector2 = line[i]
			if a.distance_to(b) < 0.01:
				continue
			var centre: Vector2 = (a + b) * 0.5
			_add_box(Vector3(a.distance_to(b) + rail_thickness_m, rail_height_m, rail_thickness_m), _flat_basis(b - a), Vector3(centre.x, _deck_top + rail_height_m * 0.5, centre.y), false)
	if drawn:
		_apply_graybox_material()
	else:
		_add_model(land)

# A basis whose +X runs along `axis` (XZ), level.
func _flat_basis(axis: Vector2) -> Basis:
	return Basis(Vector3.UP, atan2(-axis.y, axis.x))

# The same, its +X tipped down by `slope` radians.
func _sloped_basis(axis: Vector2, slope: float) -> Basis:
	return _flat_basis(axis) * Basis(Vector3(0.0, 0.0, 1.0), -slope)

# A box collided with, and - `drawn` - drawn as graybox.
func _add_box(size: Vector3, basis: Basis, centre: Vector3, drawn: bool) -> void:
	var xform := Transform3D(basis, centre)
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = xform
	add_child(collision)
	_generated.append(collision)
	if drawn:
		var mesh := BoxMesh.new()
		mesh.size = size
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = mesh
		mesh_instance.transform = xform
		mesh_instance.layers = 1 | standable_layers
		add_child(mesh_instance)
		_generated.append(mesh_instance)

func _add_model(land: float) -> void:
	var scene := load(model_path) as PackedScene if ResourceLoader.exists(model_path) else null
	if scene == null:
		push_warning("Pier '%s': model '%s' didn't load; drawn as graybox." % [name, model_path])
		return
	var model := scene.instantiate() as Node3D
	model.name = "Model"
	model.position = Vector3(0.0, land, 0.0)
	add_child(model)
	_generated.append(model)
	var dress: ShaderMaterial = PaintedProp.material(colour_map_path, Color.WHITE) if not colour_map_path.is_empty() else null
	if dress != null:
		_fog = PaintedProp.fog_pass()
		dress.next_pass = _fog
		_push_fog()
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		mesh_instance.layers = 1 | standable_layers
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if dress != null:
			mesh_instance.material_override = dress

func _push_fog() -> void:
	PaintedProp.push_fog(_fog, _sky, fog_factor)

func _apply_graybox_material() -> void:
	if _graybox_material == null:
		_graybox_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_graybox_material.albedo_color = wood_color
	for node in _generated:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = _graybox_material
