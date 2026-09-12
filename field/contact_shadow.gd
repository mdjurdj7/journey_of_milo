extends MeshInstance3D
class_name ContactShadow

# A soft, dark, flat disc that sits just above the ground directly under
# whatever this is parented to (the Wanderer, a FieldEnemy) - so the
# figure reads as grounded even where the real directional shadow is
# faint (an overcast sky is a soft, low-contrast light source) or
# offscreen entirely (the battle camera can crop it out of frame). Built
# purely in code - instantiated via ContactShadow.new() and added as a
# child, not part of any .tscn - so tune it by selecting that child node
# directly in the scene tree.
#
# Tracks Ground.get_height_at() every frame rather than being placed
# once: its owner can move (the Wanderer walking, or enter_battle_
# stance()'s own tween), and a contact shadow that doesn't follow would
# visibly detach from its owner.

@export var radius: float = 0.5:
	set(value):
		radius = value
		_apply_size()
@export var shadow_opacity: float = 0.25:
	set(value):
		shadow_opacity = value
		_apply_opacity()
@export var height_offset: float = 0.01
@export var ground_path: NodePath = ^"../Ground"

var _ground: Ground = null

func _ready() -> void:
	# RegionField's battle freeze would otherwise stop this from tracking
	# its owner mid-transition (e.g. Wanderer.enter_battle_stance()'s own
	# tween keeps moving the Wanderer through the freeze) - same reasoning
	# as Wanderer's model/AnimationPlayer overrides.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# PlaneMesh's default orientation already faces +Y (lies flat in the
	# XZ plane) with no rotation needed - the same primitive and default
	# ground.gd already relies on for its own flat dressing/relief meshes,
	# so its facing is already proven correct in this project rather than
	# assumed. QuadMesh was tried first but its own default facing axis
	# isn't something this project had independently verified, and got
	# dropped for exactly that reason.
	mesh = PlaneMesh.new()

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_texture = _build_radial_texture()
	material.albedo_color = Color(0.0, 0.0, 0.0, 1.0)
	# A decal-like blob standing in for a real shadow, not a real
	# occluder - it shouldn't cast its own shadow (that would double up
	# with the real one) or have the real shadow darken it further.
	material.disable_receive_shadows = true
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_apply_size()
	_apply_opacity()

	_ground = get_node_or_null(ground_path) as Ground

# Opaque white at the center fading to fully transparent at the edge -
# GradientTexture2D's own FILL_RADIAL does the round falloff, no shader
# needed. fill_to sits at UV-distance 0.5 from fill_from (the texture's
# center), i.e. exactly the square texture's inscribed circle, so the
# corners beyond that circle read as fully transparent too.
func _build_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.0)])
	gradient.offsets = PackedFloat32Array([0.0, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture

func _apply_size() -> void:
	if mesh is PlaneMesh:
		(mesh as PlaneMesh).size = Vector2.ONE * radius * 2.0

func _apply_opacity() -> void:
	if material_override is StandardMaterial3D:
		var material := material_override as StandardMaterial3D
		var albedo: Color = material.albedo_color
		albedo.a = shadow_opacity
		material.albedo_color = albedo

func _process(_delta: float) -> void:
	if _ground == null:
		return
	var world_xz := Vector3(global_position.x, 0.0, global_position.z)
	var local_xz: Vector3 = _ground.to_local(world_xz)
	var height: float = _ground.get_height_at(Vector2(local_xz.x, local_xz.z))
	global_position.y = height + height_offset
