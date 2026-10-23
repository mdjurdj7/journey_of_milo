extends WalkSurface
class_name Pier

# A wooden pier run out level from a shoreline over ground that falls
# away beneath it, and the boat steps down off its far end - graybox: box
# planks, posts and rails in one flat wood colour, the final art to come.
#
# Laid out along its own +X from its node origin, the middle of the
# deck's root end (placed from FloorData.props: the prop's X/Z offset
# from spawn, and its yaw_degrees turning +X toward north - 0 runs it
# east, 90 north). The deck is width_m across and deck_length_m long, its
# top a fixed height: the sand at the root plus root_rise_m, read when
# it's built, so the step up onto it stays a step whatever the relief
# does. Past its end the steps carry on at the same width, down at
# steps_slope_degrees until they meet the sand (and steps_sink_m on
# under it, so there's no lip at the foot) - one sloped plank surface
# for the walk, ruled as steps for the eye.
#
# What he walks on is what he collides with: the deck and the steps are
# boxes on this body, read back through get_top_height_at() by his ground
# hold and the walk grid (WalkSurface). Rails on both long sides, the
# steps' too, stop him stepping off: invisible to the walk grid like the
# rest of a walk surface, which keeps him on the planks by the drop alone.
# The open root end is the only way on; the steps' foot the only way off.
#
# One height per XZ (WalkSurface): wherever the pier stands, the walk
# height is its top, so the sand under it must be out of his reach - the
# floor seals it with ledges. No enemy stands on it (none grounds on a
# walk surface), and it leaves no footprints. Scatter isn't kept off its
# outline: the reeds grow on under the deck, the floor's scatter areas
# keeping clear where it is low.

@export_group("Shape")
@export var deck_length_m: float = 18.0:
	set(value):
		deck_length_m = value
		_rebuild()
@export var width_m: float = 2.0:
	set(value):
		width_m = value
		_rebuild()
# The deck top over the sand at its root - the step up onto it, so at
# most Wanderer.step_height.
@export var root_rise_m: float = 0.12:
	set(value):
		root_rise_m = value
		_rebuild()
@export var deck_thickness_m: float = 0.25:
	set(value):
		deck_thickness_m = value
		_rebuild()
# The steps' fall from the deck end; the walk grid takes up to 45.
@export_range(5.0, 45.0, 0.5) var steps_slope_degrees: float = 32.0:
	set(value):
		steps_slope_degrees = value
		_rebuild()
# How far the steps' surface runs on under the sand past their foot.
@export var steps_sink_m: float = 0.15:
	set(value):
		steps_sink_m = value
		_rebuild()
# The steps' drawn riser, at most; the surface itself is one slope.
@export var steps_riser_m: float = 0.25:
	set(value):
		steps_riser_m = value
		_rebuild()

@export_group("Rails")
@export var rail_height_m: float = 0.9:
	set(value):
		rail_height_m = value
		_rebuild()
@export var rail_thickness_m: float = 0.08:
	set(value):
		rail_thickness_m = value
		_rebuild()

@export_group("Posts")
# The posts under the deck, a pair every this many metres along it.
@export var post_spacing_m: float = 3.0:
	set(value):
		post_spacing_m = value
		_rebuild()
@export var post_radius_m: float = 0.12:
	set(value):
		post_radius_m = value
		_rebuild()
# How far a post runs on into the sand.
@export var post_sink_m: float = 0.3:
	set(value):
		post_sink_m = value
		_rebuild()

@export_group("Colour")
@export var wood_color: Color = Color(0.45, 0.36, 0.27):
	set(value):
		wood_color = value
		_apply_material()
# The render layers its planks are on besides layer 1: a figure on it
# lays its contact pool here (ContactShadowData.perch_layers), and the
# body is in ContactShadow.STANDABLE_GROUP so the pool finds the top.
@export_flags_3d_render var standable_layers: int = 1 << 17:
	set(value):
		standable_layers = value
		_rebuild()

@export_group("")
@export var ground_path: NodePath = ^"../Ground"

var _ground: Ground = null
var _material: StandardMaterial3D = null
# The deck top, local Y, and the steps' run along +X past the deck end
# (to the sand, then under it by steps_sink_m) - as last built.
var _deck_top: float = 0.0
var _steps_run: float = 0.0
var _built: bool = false
var _generated: Array[Node] = []

func _ready() -> void:
	add_to_group(WALK_SURFACE_GROUP)
	add_to_group(ContactShadow.STANDABLE_GROUP)
	# Raycast and stood on during a fight's freeze too.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	var ground: Ground = _get_ground()
	if ground != null and not ground.relief_rebuilt.is_connected(_rebuild):
		ground.relief_rebuilt.connect(_rebuild)
	_rebuild()

# FloorProp placement: the root on the sand's XZ, +X turned yaw degrees
# toward north. Roll is ignored.
func set_floor_placement(placement: Vector3, yaw_degrees: float, _roll_degrees: float) -> void:
	position = Vector3(placement.x, 0.0, placement.z)
	rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)

func get_top_height_at(world_xz: Vector2) -> float:
	if not _built:
		return -INF
	var p: Vector2 = _to_pier(world_xz)
	if absf(p.y) > width_m * 0.5 or p.x < 0.0:
		return -INF
	if p.x <= deck_length_m:
		return global_position.y + _deck_top
	if p.x <= deck_length_m + _steps_run:
		return global_position.y + _deck_top - (p.x - deck_length_m) * tan(deg_to_rad(steps_slope_degrees))
	return -INF

func get_top_normal_at(world_xz: Vector2) -> Vector3:
	if not _built:
		return Vector3.UP
	var p: Vector2 = _to_pier(world_xz)
	if absf(p.y) > width_m * 0.5 or p.x <= deck_length_m or p.x > deck_length_m + _steps_run:
		return Vector3.UP
	var slope: float = deg_to_rad(steps_slope_degrees)
	return (global_transform.basis * Vector3(sin(slope), cos(slope), 0.0)).normalized()

func takes_footprints() -> bool:
	return false

# A world XZ in the pier's own frame: x along the deck from its root, y
# across it.
func _to_pier(world_xz: Vector2) -> Vector2:
	var local: Vector3 = global_transform.affine_inverse() * Vector3(world_xz.x, global_position.y, world_xz.y)
	return Vector2(local.x, local.z)

func _get_ground() -> Ground:
	if _ground == null and is_inside_tree():
		_ground = get_node_or_null(ground_path) as Ground
	return _ground

# The sand as drawn under a point of the pier's frame, in local Y.
func _sand(along: float, across: float) -> float:
	var world: Vector3 = global_transform * Vector3(along, 0.0, across)
	var on_ground: Vector3 = _ground.to_local(Vector3(world.x, 0.0, world.z))
	var height: float = _ground.get_visible_height_at(Vector2(on_ground.x, on_ground.z))
	return to_local(_ground.to_global(Vector3(on_ground.x, height, on_ground.z))).y

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
	_deck_top = _sand(0.0, 0.0) + root_rise_m
	# The steps' foot: where their slope meets the sand, found by stepping
	# out along it (the sand there isn't known until the run is).
	var slope: float = deg_to_rad(steps_slope_degrees)
	var run: float = 0.0
	for i in 8:
		run = maxf(_deck_top - _sand(deck_length_m + run, 0.0), 0.0) / tan(slope)
	_steps_run = run + steps_sink_m / sin(slope)
	_built = true
	var half: float = width_m * 0.5
	# The deck.
	_add_box(Vector3(deck_length_m, deck_thickness_m, width_m), Transform3D(Basis(), Vector3(deck_length_m * 0.5, _deck_top - deck_thickness_m * 0.5, 0.0)), true)
	# The steps: one sloped plank surface, with a riser drawn every
	# steps_riser_m of its fall.
	var steps_length: float = _steps_run / cos(slope)
	var steps_basis := Basis(Vector3(0.0, 0.0, 1.0), -slope)
	var steps_mid_top := Vector3(deck_length_m + _steps_run * 0.5, _deck_top - _steps_run * 0.5 * tan(slope), 0.0)
	var down: Vector3 = steps_basis * Vector3(0.0, -deck_thickness_m * 0.5, 0.0)
	_add_box(Vector3(steps_length, deck_thickness_m, width_m), Transform3D(steps_basis, steps_mid_top + down), true)
	var fall: float = _steps_run * tan(slope)
	var risers: int = int(floor(fall / maxf(steps_riser_m, 0.05)))
	for k in range(1, risers + 1):
		var x: float = deck_length_m + float(k) * steps_riser_m / tan(slope)
		var y: float = _deck_top - float(k) * steps_riser_m
		_add_box(Vector3(0.04, 0.03, width_m), Transform3D(Basis(), Vector3(x, y + 0.01, 0.0)), false)
	# The rails, both sides of the deck and the steps.
	for side: float in [-1.0, 1.0]:
		var z: float = side * (half + rail_thickness_m * 0.5)
		_add_box(Vector3(deck_length_m, rail_height_m, rail_thickness_m), Transform3D(Basis(), Vector3(deck_length_m * 0.5, _deck_top + rail_height_m * 0.5, z)), true)
		var rail_up: Vector3 = steps_basis * Vector3(0.0, rail_height_m * 0.5, 0.0)
		_add_box(Vector3(steps_length, rail_height_m, rail_thickness_m), Transform3D(steps_basis, steps_mid_top + rail_up + Vector3(0.0, 0.0, z)), true)
	# The posts, a pair every post_spacing_m from the root, down into the
	# sand; none where the deck sits on it.
	var spacing: float = maxf(post_spacing_m, 0.5)
	var along: float = spacing
	while along <= deck_length_m + 0.001:
		for side: float in [-1.0, 1.0]:
			var across: float = side * (half - post_radius_m)
			var bottom: float = _sand(along, across) - post_sink_m
			var top: float = _deck_top - deck_thickness_m
			if top - bottom > post_sink_m + 0.05:
				_add_post(Vector3(along, (top + bottom) * 0.5, across), top - bottom)
		along += spacing
	_apply_material()

# A plank box: drawn, and - `solid` - collided with.
func _add_box(size: Vector3, xform: Transform3D, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.transform = xform
	mesh_instance.layers = 1 | standable_layers
	add_child(mesh_instance)
	_generated.append(mesh_instance)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.transform = xform
		add_child(collision)
		_generated.append(collision)

func _add_post(centre: Vector3, height: float) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = post_radius_m
	mesh.bottom_radius = post_radius_m
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = mesh
	mesh_instance.position = centre
	add_child(mesh_instance)
	_generated.append(mesh_instance)

func _apply_material() -> void:
	if _material == null:
		_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = wood_color
	for node in _generated:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance != null:
			mesh_instance.material_override = _material
