extends Decal
class_name ContactShadow

# The soft pale pool under a figure (Art Bible §7: a contact shadow, not
# a hard shape, never black) - a Decal projected down onto the surface
# under the figure, so it lies on the sand's own relief (a dune face, a
# channel bank) instead of a flat disc cutting through it. It lands only
# on the render layers its data names: Ground's contact layer, and a
# standable prop's (a basking slab, the crest rock) when the figure may
# perch - never on the figure, other props or the sea.
#
# Built in code: the owner (Wanderer, FieldEnemy, Keeper, DunecurPup)
# makes one with ContactShadow.new(), hands it the Ground (set_ground()),
# its footprint, and where its feet are (feet_source - the model's, so a
# lunge that moves the model and not the body takes the pool along). The
# pool is an ellipse turned with its parent's facing - a long body (the
# Greyshelf, the Dunecur) lies in a long pool.
# Its look is a ContactShadowData (data; the shared field/contact_shadow.
# tres when none is given) - edits to it re-apply live.
#
# Every frame: at the feet's XZ, the surface under them (the sand, or a
# standable prop's top there), the pool laid on it in that surface's own
# colour darkened (data.darkening - Ground's ground_color, or the prop's
# get_surface_colour()), faded and shrunk by how far the feet are above
# it (a hover, a leap), and faded with the sand's depth under the sea.

const DEFAULT_DATA_PATH := "res://field/contact_shadow.tres"
# The collision bodies a figure can stand on that aren't the Ground - a
# perch. Their tops are found by a ray down from the feet.
const STANDABLE_GROUP := &"standable"
const _PERCH_RAY_TRIES := 4

@export var data: ContactShadowData = null:
	set(value):
		if data != null and data.changed.is_connected(_apply_look):
			data.changed.disconnect(_apply_look)
		data = value
		if data != null:
			data.changed.connect(_apply_look)
		_apply_look()
# The figure's own footprint, metres: its radius across (x) and along
# (y) its parent's facing - a capsule's radius both ways, or its model's
# half-extents. The pool is this times data.footprint_scale, plus
# data.footprint_margin_m.
@export var footprint: Vector2 = Vector2(0.4, 0.4):
	set(value):
		footprint = value
		_place()
# The same for the body alone, without its attachments (FieldEnemy's
# model before its wings or claws); used in place of footprint when
# data.footprint_from_body. Zero for no difference.
@export var body_footprint: Vector2 = Vector2.ZERO:
	set(value):
		body_footprint = value
		_place()
# Over everything else: 1 the pool as its data says, 0 gone (a death's
# fade).
@export_range(0.0, 1.0, 0.01) var fade: float = 1.0:
	set(value):
		fade = value
		_place()

# The feet's world position: () -> Vector3. Unset, the parent's origin.
var feet_source: Callable = Callable()

var _ground: Ground = null
# The colour of the standable prop the last perch ray landed on; alpha 0
# when the pool is on the sand (or the prop has no colour to give).
var _perch_colour: Color = Color(0.0, 0.0, 0.0, 0.0)

func _ready() -> void:
	# RegionField's battle freeze would otherwise stop the pool following
	# its figure through the fight's own tweens (a stance, a lunge).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Placed in world space each frame - the body's tilt (a recoil) never
	# tips the projection.
	top_level = true
	if data == null:
		data = load(DEFAULT_DATA_PATH) as ContactShadowData
	_apply_look()

func set_ground(ground: Ground) -> void:
	_ground = ground
	_place()

func _process(_delta: float) -> void:
	_place()

func _apply_look() -> void:
	if data == null or not is_inside_tree():
		return
	texture_albedo = _build_falloff(data.falloff_start)
	albedo_mix = 1.0
	normal_fade = data.normal_fade
	upper_fade = data.edge_fade
	lower_fade = data.edge_fade
	cull_mask = data.ground_layers | (data.perch_layers if data.perch_surfaces else 0)
	_place()

# Full strength out to `start` of the radius, then a smoothstep down to
# nothing at the edge - sampled into the gradient so there's no ring.
func _build_falloff(start: float) -> GradientTexture2D:
	var offsets := PackedFloat32Array([0.0])
	var colors := PackedColorArray([Color(1.0, 1.0, 1.0, 1.0)])
	var steps: int = 8
	for i in steps + 1:
		var u: float = float(i) / float(steps)
		offsets.append(lerpf(start, 1.0, u))
		colors.append(Color(1.0, 1.0, 1.0, 1.0 - smoothstep(0.0, 1.0, u)))
	var gradient := Gradient.new()
	gradient.offsets = offsets
	gradient.colors = colors
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 128
	texture.height = 128
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _place() -> void:
	if data == null or not is_inside_tree():
		return
	var feet: Vector3 = _feet()
	var sand: float = _sand_height(feet)
	var surface: float = sand
	_perch_colour = Color(0.0, 0.0, 0.0, 0.0)
	if data.perch_surfaces:
		surface = maxf(sand, _perch_top(feet, sand))
	if surface <= sand:
		_perch_colour = Color(0.0, 0.0, 0.0, 0.0)
	var height: float = maxf(feet.y - surface, 0.0)
	var lift: float = clampf(height / maxf(data.hover_fade_height_m, 0.001), 0.0, 1.0)
	var base: Vector2 = body_footprint if data.footprint_from_body and body_footprint != Vector2.ZERO else footprint
	var extent: Vector2 = base * data.footprint_scale + Vector2.ONE * data.footprint_margin_m
	var radii: Vector2 = extent * lerpf(1.0, data.hover_min_scale, lift)
	var alpha: float = data.strength * (1.0 - lift) * _wade_factor(surface) * fade
	global_transform = Transform3D(Basis(Vector3.UP, _yaw()), Vector3(feet.x, surface, feet.z))
	size = Vector3(radii.x * 2.0, maxf(data.reach_m, 0.01) * 2.0, radii.y * 2.0)
	var ground_tone: Color = _perch_colour if _perch_colour.a > 0.0 else _sand_colour()
	modulate = Color(ground_tone.r * data.darkening, ground_tone.g * data.darkening, ground_tone.b * data.darkening, alpha)

# The parent's facing round world Y - from its +Z flattened, so a tilt
# (a recoil, a lean) doesn't turn the pool.
func _yaw() -> float:
	var parent := get_parent() as Node3D
	if parent == null:
		return 0.0
	var along: Vector3 = parent.global_basis.z
	return atan2(along.x, along.z)

# Ground's dry sand colour; a mid sand with no Ground to ask.
func _sand_colour() -> Color:
	return _ground.ground_color if _ground != null else Color(0.74, 0.70, 0.60)

func _feet() -> Vector3:
	if feet_source.is_valid():
		return feet_source.call() as Vector3
	var parent := get_parent() as Node3D
	return parent.global_position if parent != null else global_position

# The sand under `feet`; the feet's own height with no Ground to ask.
func _sand_height(feet: Vector3) -> float:
	if _ground == null:
		return feet.y
	var local_xz: Vector3 = _ground.to_local(Vector3(feet.x, 0.0, feet.z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# The top of a standable prop under the feet, from a ray down from a
# reach above them to the sand; `sand` where there is none. Anything else
# the ray meets on the way (the figure's own body, a neighbour's) is
# passed through.
func _perch_top(feet: Vector3, sand: float) -> float:
	var from := Vector3(feet.x, feet.y + data.reach_m, feet.z)
	var to := Vector3(feet.x, sand, feet.z)
	if from.y <= to.y:
		return sand
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return sand
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var exclude: Array[RID] = []
	for i in _PERCH_RAY_TRIES:
		query.exclude = exclude
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			return sand
		var collider := hit["collider"] as Node
		if collider != null and collider.is_in_group(STANDABLE_GROUP):
			var point: Vector3 = hit["position"]
			var prop: Node = collider.get_parent()
			if prop != null and prop.has_method("get_surface_colour"):
				_perch_colour = prop.call("get_surface_colour") as Color
			return point.y
		var rid: RID = hit["rid"]
		exclude.append(rid)
	return sand

# 1 on dry sand, easing to 0 by data.wade_fade_depth_m under the sea.
func _wade_factor(surface: float) -> float:
	if _ground == null:
		return 1.0
	var depth: float = _ground.get_sea_level() - surface
	return 1.0 - smoothstep(0.0, maxf(data.wade_fade_depth_m, 0.001), depth)
