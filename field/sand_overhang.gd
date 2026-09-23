extends Node3D
class_name SandOverhang

# The lip over the back of floor 2's pocket: a slab of the bank projecting
# out over the pocket's back 1.5 m, and the mass it grows from, sitting on
# the painted bank behind the back wall. The ground is a heightfield and
# tops out at Ground.elevation_max_height, so it can neither overhang nor
# reach this high; this is the one thing on the floor that does both.
#
# Local frame: the origin is the back wall's inner face at the pocket's
# middle, on the pocket floor; +X runs out toward the mouth, Z across it.
# Placed by RegionField from FloorData.props like any prop (set_floor_
# placement(): XZ from the floor, yaw onto yaw_degrees) and grounded on
# the relief just in front of its origin (ground_sample_offset), so the
# underside is underside_height over the pocket floor wherever the floor
# ends up.
#
# Three solids, built into one mesh:
#   the mass - behind the back wall, from embed_height (the floor, so it
#              meets the painted wall's foot and is buried in the bank
#              everywhere else) up to top_height;
#   the lip  - the slab, from underside_height to top_height, out to an
#              irregular edge (lip_depth, wobbled by lip_wobble);
#   the ends - over the side walls, solid from embed_height to the top,
#              so no slot of light shows between the bank and the slab.
# Every face is flat. The whole prop is sand (sand_tint, on the flat
# matte material the hulls use); the faces that look down are darker
# sand (x underside_shade) - the underside is lit by the ambient alone
# (the key light is near overhead) and sits in the prop's own shadow, and
# the vertex colour deepens that without a texture or a new material.
#
# Collision: a box per solid. The lip's stops the Wanderer at its edge -
# he is 1.8 m tall and the underside is 1.6 m, so he never stands under
# it, and nothing needs to fade. Not walkable on top (nothing reaches it
# - the bank round it is unclimbable) and nothing spawns on it.

@export_group("Shape")
# Kept inside the painted back bank (1.3 m wide) so its back rises from
# the bank's own slope, not from the ramp beyond it.
@export var mass_depth: float = 1.0:
	set(value):
		mass_depth = value
		_rebuild()
@export var lip_depth: float = 1.5:
	set(value):
		lip_depth = value
		_rebuild()
# How far the lip's edge wanders either way, metres, and where along its
# sin sum it starts - the edge is the same every load.
@export var lip_wobble: float = 0.25:
	set(value):
		lip_wobble = value
		_rebuild()
@export var wobble_seed: float = 11.0:
	set(value):
		wobble_seed = value
		_rebuild()
# Half the pocket's width (the open part under the lip), and half the
# whole prop's width (the ends run into the side walls).
@export var pocket_half_width: float = 1.5:
	set(value):
		pocket_half_width = value
		_rebuild()
@export var half_span: float = 2.3:
	set(value):
		half_span = value
		_rebuild()
@export var underside_height: float = 1.6:
	set(value):
		underside_height = value
		_rebuild()
@export var top_height: float = 2.0:
	set(value):
		top_height = value
		_rebuild()
# The bottom of the mass and the ends, over the pocket floor. At the floor
# (0) their faces toward the pocket stand on it with no slot beneath,
# and everywhere else they are buried in the painted bank.
@export var embed_height: float = 0.0:
	set(value):
		embed_height = value
		_rebuild()
# Strips along Z the lip's edge is broken into.
@export var lip_segments: int = 14:
	set(value):
		lip_segments = value
		_rebuild()
@export_group("")

@export_group("Colour")
# Dry sand (Ground.ground_color, file 03's palette).
@export var sand_tint: Color = Color(0.74, 0.70, 0.60):
	set(value):
		sand_tint = value
		_rebuild()
# The downward faces, as a multiplier on sand_tint.
@export_range(0.0, 1.0) var underside_shade: float = 0.8:
	set(value):
		underside_shade = value
		_rebuild()
@export_group("")

@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		rotation = Vector3(0.0, deg_to_rad(yaw_degrees), 0.0)
# Grounded on the relief this far in front of the origin (local +X) -
# the pocket floor, clear of the painted back wall whose face wanders
# either side of the origin itself.
@export var ground_sample_offset: float = 0.6:
	set(value):
		ground_sample_offset = value
		_ground_to_relief()
@export var ground_path: NodePath = ^"../../Ground"

var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _body: StaticBody3D = null
var _ground: Ground = null
var _ready_done: bool = false

# RegionField's placement (FloorProp): XZ here, Y from the relief, yaw
# onto yaw_degrees; it doesn't roll.
func set_floor_placement(world_position: Vector3, yaw: float, _roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_degrees = yaw

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mesh_instance)
	_material = Hull._get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.vertex_color_use_as_albedo = true
	# The tints are authored like every other colour here, in sRGB.
	_material.vertex_color_is_srgb = true
	_material.albedo_color = Color.WHITE
	_mesh_instance.material_override = _material
	_body = StaticBody3D.new()
	_body.name = "Collision"
	# Kept in the physics space through RegionField's freeze, like every
	# prop that must stay solid (and clickable) under a fight.
	_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
	add_child(_body)
	_ready_done = true
	_rebuild()
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("SandOverhang '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _ground_to_relief() -> void:
	if _ground == null:
		return
	var sample: Vector3 = global_position + global_transform.basis.x.normalized() * ground_sample_offset
	var local_xz: Vector3 = _ground.to_local(Vector3(sample.x, 0.0, sample.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

func _wobble(t: float) -> float:
	return sin(t * 1.3 + wobble_seed) * 0.6 + sin(t * 2.9 + wobble_seed * 2.1) * 0.4

# The lip's edge at this Z.
func _lip_at(z: float) -> float:
	return maxf(lip_depth + lip_wobble * _wobble(z * 1.7), 0.1)

func _rebuild() -> void:
	if not _ready_done:
		return
	_mesh_instance.mesh = _build_mesh()
	_build_collision()

# --- Mesh ---

var _st: SurfaceTool = null

func _build_mesh() -> ArrayMesh:
	_st = SurfaceTool.new()
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Three runs of strips, split exactly at the pocket's edges: the end
	# over one side wall, the open part, the other end.
	var runs: Array = [[-half_span, -pocket_half_width, true], [-pocket_half_width, pocket_half_width, false], [pocket_half_width, half_span, true]]
	var total: int = maxi(lip_segments, 3)
	for r in runs:
		var r0: float = r[0]
		var r1: float = r[1]
		var solid_end: bool = r[2]
		var n: int = maxi(int(round(float(total) * (r1 - r0) / (2.0 * half_span))), 1)
		var dz: float = (r1 - r0) / float(n)
		for i in n:
			var za: float = r0 + dz * float(i)
			var zb: float = za + dz
			var la: float = _lip_at(za)
			var lb: float = _lip_at(zb)
			var cap_a: bool = is_equal_approx(za, -half_span)
			var cap_b: bool = is_equal_approx(zb, half_span)
			# The mass behind the wall, full height.
			_prism(-mass_depth, -mass_depth, 0.0, 0.0, embed_height, top_height, za, zb, cap_a, cap_b, true, false)
			if solid_end:
				# Over a side wall: solid from the bank up, out to the lip.
				_prism(0.0, 0.0, la, lb, embed_height, top_height, za, zb, cap_a, cap_b, false, true)
			else:
				# Over the pocket: the slab, and under it the mass's own face -
				# the back wall carried on above the painted bank.
				_prism(0.0, 0.0, la, lb, underside_height, top_height, za, zb, false, false, false, true)
				_quad(Vector3(0.0, embed_height, za), Vector3(0.0, embed_height, zb), Vector3(0.0, underside_height, zb), Vector3(0.0, underside_height, za), Vector3.RIGHT)
	# The ends' faces toward the pocket, under the slab.
	for side in [-1.0, 1.0]:
		var zc: float = side * pocket_half_width
		var lc: float = _lip_at(zc)
		_quad(Vector3(0.0, embed_height, zc), Vector3(lc, embed_height, zc), Vector3(lc, underside_height, zc), Vector3(0.0, underside_height, zc), Vector3(0.0, 0.0, -side))
	var mesh: ArrayMesh = _st.commit()
	_st = null
	return mesh

# A strip between za and zb, x from x_back to x_front (front edge per
# end: fa at za, fb at zb), y from y0 to y1. Caps at the strip's ends only
# where asked (the prop's own two ends); a back face only for the mass, a
# front face only where the strip is the lip.
func _prism(ba: float, bb: float, fa: float, fb: float, y0: float, y1: float, za: float, zb: float, cap_a: bool, cap_b: bool, back: bool, front: bool) -> void:
	# Top.
	_quad(Vector3(ba, y1, za), Vector3(bb, y1, zb), Vector3(fb, y1, zb), Vector3(fa, y1, za), Vector3.UP)
	# Bottom.
	_quad(Vector3(ba, y0, za), Vector3(fa, y0, za), Vector3(fb, y0, zb), Vector3(bb, y0, zb), Vector3.DOWN)
	if front:
		var edge := Vector3(fb - fa, 0.0, zb - za)
		var nrm: Vector3 = edge.cross(Vector3.UP).normalized() * -1.0
		if nrm.x < 0.0:
			nrm = -nrm
		_quad(Vector3(fa, y0, za), Vector3(fa, y1, za), Vector3(fb, y1, zb), Vector3(fb, y0, zb), nrm)
	if back:
		_quad(Vector3(ba, y0, za), Vector3(bb, y0, zb), Vector3(bb, y1, zb), Vector3(ba, y1, za), Vector3.LEFT)
	if cap_a:
		_quad(Vector3(ba, y0, za), Vector3(ba, y1, za), Vector3(fa, y1, za), Vector3(fa, y0, za), Vector3.FORWARD)
	if cap_b:
		_quad(Vector3(ba, y0, zb), Vector3(fb, y0, zb), Vector3(fb, y1, zb), Vector3(bb, y1, zb), Vector3.BACK)

# One flat quad, wound to face `normal` (either winding is accepted and
# fixed here), coloured sand or - facing down - darker sand.
func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var face: Vector3 = (b - a).cross(c - a)
	if face.dot(normal) > 0.0:
		var t: Vector3 = b
		b = d
		d = t
	var colour: Color = sand_tint
	if normal.y < -0.5:
		colour = Color(sand_tint.r * underside_shade, sand_tint.g * underside_shade, sand_tint.b * underside_shade, 1.0)
	_st.set_color(colour)
	_st.set_normal(normal)
	for v in [a, b, c, a, c, d]:
		_st.add_vertex(v)

# --- Collision ---

func _build_collision() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var slab_depth: float = lip_depth + lip_wobble
	_add_box("Mass", Vector3(-mass_depth * 0.5, (embed_height + top_height) * 0.5, 0.0), Vector3(mass_depth, top_height - embed_height, 2.0 * half_span))
	_add_box("Lip", Vector3(slab_depth * 0.5, (underside_height + top_height) * 0.5, 0.0), Vector3(slab_depth, top_height - underside_height, 2.0 * pocket_half_width))
	var end_w: float = half_span - pocket_half_width
	for side in [-1.0, 1.0]:
		_add_box("EndSouth" if side > 0.0 else "EndNorth", Vector3(slab_depth * 0.5, (embed_height + top_height) * 0.5, side * (pocket_half_width + end_w * 0.5)), Vector3(slab_depth, top_height - embed_height, end_w))

func _add_box(label: String, centre: Vector3, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var node := CollisionShape3D.new()
	node.name = label
	node.shape = shape
	node.position = centre
	_body.add_child(node)
