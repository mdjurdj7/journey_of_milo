extends StaticBody3D
class_name Ground

@export var ground_color: Color = Color(0.72, 0.73, 0.66):
	set(value):
		ground_color = value
		_apply_uniform("dry_color", value)

@export var plane_size: Vector2 = Vector2(500.0, 500.0)
@export var dressing_subdivisions: Vector2i = Vector2i(4, 4)

# Fine-subdivided inner plane sized to the playable area, so relief
# detail exists where the Wanderer actually walks; the outer dressing
# plane (plane_size, above) stays coarse. Also pushed to the shader as
# relief_edge_fade's bounds — changing this live re-fades the edge but
# does not resize the already-built mesh.
@export var relief_extent: Vector2 = Vector2(80.0, 50.0):
	set(value):
		relief_extent = value
		_apply_uniform("relief_extent", value)
@export var relief_subdivisions: Vector2i = Vector2i(40, 25)

@export var near_color: Color = Color(1.0, 1.0, 1.0):
	set(value):
		near_color = value
		_apply_uniform("near_color", value)
@export var far_color: Color = Color(0.7, 0.7, 0.72):
	set(value):
		far_color = value
		_apply_uniform("far_color", value)
@export var near_distance: float = 5.0:
	set(value):
		near_distance = value
		_apply_uniform("near_distance", value)
@export var far_distance: float = 60.0:
	set(value):
		far_distance = value
		_apply_uniform("far_distance", value)

@export var wetness_scale: float = 30.0:
	set(value):
		wetness_scale = value
		_apply_uniform("wetness_scale", value)
@export var wetness_amount: float = 0.4:
	set(value):
		wetness_amount = value
		_apply_uniform("wetness_amount", value)
@export var wet_color: Color = Color(0.35, 0.38, 0.40):
	set(value):
		wet_color = value
		_apply_uniform("wet_color", value)
@export var wet_roughness: float = 0.15:
	set(value):
		wet_roughness = value
		_apply_uniform("wet_roughness", value)
@export var wet_specular: float = 0.4:
	set(value):
		wet_specular = value
		_apply_uniform("wet_specular", value)

@export var pool_threshold: float = 0.75:
	set(value):
		pool_threshold = value
		_apply_uniform("pool_threshold", value)
@export var pool_edge_width: float = 0.15:
	set(value):
		pool_edge_width = value
		_apply_uniform("pool_edge_width", value)
@export var pool_color: Color = Color(0.696, 0.704, 0.68):
	set(value):
		pool_color = value
		_apply_uniform("pool_color", value)
@export var pool_roughness: float = 0.35:
	set(value):
		pool_roughness = value
		_apply_uniform("pool_roughness", value)

@export var relief_amplitude: float = 0.3:
	set(value):
		relief_amplitude = value
		_apply_uniform("relief_amplitude", value)
@export var relief_noise_scale: float = 4.0:
	set(value):
		relief_noise_scale = value
		_apply_uniform("relief_noise_scale", value)
@export var relief_fade_start: float = 30.0:
	set(value):
		relief_fade_start = value
		_apply_uniform("relief_fade_start", value)
@export var relief_fade_end: float = 60.0:
	set(value):
		relief_fade_end = value
		_apply_uniform("relief_fade_end", value)
# Relief displacement (and its normal contribution) fades to zero over the
# last relief_edge_fade meters inside relief_extent's edges, so the fine
# relief mesh meets the flat outer dressing plane flush instead of leaving
# a seam where the two meshes' displacement disagrees at the boundary.
@export var relief_edge_fade: float = 4.0:
	set(value):
		relief_edge_fade = value
		_apply_uniform("relief_edge_fade", value)

# Drift lines: a few faint bands running parallel to the shore, marking
# where wrack will sit later. Spaced inland from the water line, wobbled
# so they don't read as ruled lines, and faded out after drift_line_count
# of them so only a handful ever show.
@export var drift_line_spacing: float = 6.0:
	set(value):
		drift_line_spacing = value
		_apply_uniform("drift_line_spacing", value)
@export var drift_line_width: float = 1.0:
	set(value):
		drift_line_width = value
		_apply_uniform("drift_line_width", value)
@export var drift_line_wobble: float = 1.5:
	set(value):
		drift_line_wobble = value
		_apply_uniform("drift_line_wobble", value)
@export var drift_line_wobble_scale: float = 10.0:
	set(value):
		drift_line_wobble_scale = value
		_apply_uniform("drift_line_wobble_scale", value)
@export var drift_line_count: int = 3:
	set(value):
		drift_line_count = value
		_apply_uniform("drift_line_count", value)
@export var drift_line_strength: float = 0.05:
	set(value):
		drift_line_strength = value
		_apply_uniform("drift_line_strength", value)
@export var drift_line_color: Color = Color(0.55, 0.48, 0.4):
	set(value):
		drift_line_color = value
		_apply_uniform("drift_line_color", value)
# Pseudo-height (meters) drift lines contribute to the vertex normal only —
# they don't displace VERTEX, this just keeps them reading as shaded relief
# rather than flat paint. Kept small relative to relief_amplitude.
@export var drift_line_normal_amplitude: float = 0.02:
	set(value):
		drift_line_normal_amplitude = value
		_apply_uniform("drift_line_normal_amplitude", value)

# Ripple marks: faint, fine-scale directional noise in wet sand, perpendicular
# to the shore. A value shift, not a texture.
@export var ripple_scale: float = 0.4:
	set(value):
		ripple_scale = value
		_apply_uniform("ripple_scale", value)
@export var ripple_stretch: float = 6.0:
	set(value):
		ripple_stretch = value
		_apply_uniform("ripple_stretch", value)
@export var ripple_strength: float = 0.02:
	set(value):
		ripple_strength = value
		_apply_uniform("ripple_strength", value)
# Same idea as drift_line_normal_amplitude: a reduced-weight pseudo-height
# used only to perturb the normal, so ripples read as surface, not paint.
@export var ripple_normal_amplitude: float = 0.01:
	set(value):
		ripple_normal_amplitude = value
		_apply_uniform("ripple_normal_amplitude", value)

# Wet band: within shore_slope_start of the water line, sand wetness is
# pushed to 1.0 so it reflects like the water does. water_line_z/
# water_forward_z (pushed once in _ready(), below) come from Sea and
# RegionField, not assumed.
@export var shore_slope_start: float = 8.0:
	set(value):
		shore_slope_start = value
		_apply_uniform("shore_slope_start", value)
@export var region_field_path: NodePath = ^".."
@export var sea_path: NodePath = ^"../Sea"

var _material: ShaderMaterial

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

func _ready() -> void:
	# Same reasoning as FieldEnemy's own disable_mode override: RegionField's
	# battle freeze would otherwise remove Ground from the physics space
	# entirely (disable_mode's default, REMOVE), and the targeting raycast
	# needs solid ground behind/around enemies to behave sanely too.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC

	_material = ShaderMaterial.new()
	_material.shader = load("res://field/ground.gdshader")
	_apply_all_uniforms()

	var dressing_mesh := PlaneMesh.new()
	dressing_mesh.size = plane_size
	dressing_mesh.subdivide_width = dressing_subdivisions.x
	dressing_mesh.subdivide_depth = dressing_subdivisions.y
	dressing_mesh.material = _material
	mesh_instance.mesh = dressing_mesh

	var relief_mesh := PlaneMesh.new()
	relief_mesh.size = relief_extent
	relief_mesh.subdivide_width = relief_subdivisions.x
	relief_mesh.subdivide_depth = relief_subdivisions.y
	relief_mesh.material = _material

	var relief_instance := MeshInstance3D.new()
	relief_instance.mesh = relief_mesh
	relief_instance.position.y = 0.02 # clears the coarse dressing plane beneath, avoids z-fighting
	add_child(relief_instance)

	var boundary := WorldBoundaryShape3D.new()
	boundary.plane = Plane(Vector3.UP, 0.0)
	collision_shape.shape = boundary

	_apply_water_line_uniforms()

# RegionField.get_forward() and Sea.get_near_edge_z() are both lazy and
# safe to call regardless of node-ready order (see their own comments),
# so this can run directly from _ready() with no deferral needed.
func _apply_water_line_uniforms() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	var sea := get_node_or_null(sea_path) as Sea
	var forward: Vector3 = region_field.get_forward() if region_field else Vector3.FORWARD
	var water_line_z: float = sea.get_near_edge_z() if sea else 0.0
	_apply_uniform("water_line_z", water_line_z)
	_apply_uniform("water_forward_z", forward.z)

func _apply_all_uniforms() -> void:
	_apply_uniform("dry_color", ground_color)
	_apply_uniform("near_color", near_color)
	_apply_uniform("far_color", far_color)
	_apply_uniform("near_distance", near_distance)
	_apply_uniform("far_distance", far_distance)
	_apply_uniform("wetness_scale", wetness_scale)
	_apply_uniform("wetness_amount", wetness_amount)
	_apply_uniform("wet_color", wet_color)
	_apply_uniform("wet_roughness", wet_roughness)
	_apply_uniform("wet_specular", wet_specular)
	_apply_uniform("shore_slope_start", shore_slope_start)
	_apply_uniform("pool_threshold", pool_threshold)
	_apply_uniform("pool_edge_width", pool_edge_width)
	_apply_uniform("pool_color", pool_color)
	_apply_uniform("pool_roughness", pool_roughness)
	_apply_uniform("relief_amplitude", relief_amplitude)
	_apply_uniform("relief_noise_scale", relief_noise_scale)
	_apply_uniform("relief_fade_start", relief_fade_start)
	_apply_uniform("relief_fade_end", relief_fade_end)
	_apply_uniform("relief_extent", relief_extent)
	_apply_uniform("relief_edge_fade", relief_edge_fade)
	_apply_uniform("drift_line_spacing", drift_line_spacing)
	_apply_uniform("drift_line_width", drift_line_width)
	_apply_uniform("drift_line_wobble", drift_line_wobble)
	_apply_uniform("drift_line_wobble_scale", drift_line_wobble_scale)
	_apply_uniform("drift_line_count", drift_line_count)
	_apply_uniform("drift_line_strength", drift_line_strength)
	_apply_uniform("drift_line_color", drift_line_color)
	_apply_uniform("drift_line_normal_amplitude", drift_line_normal_amplitude)
	_apply_uniform("ripple_scale", ripple_scale)
	_apply_uniform("ripple_stretch", ripple_stretch)
	_apply_uniform("ripple_strength", ripple_strength)
	_apply_uniform("ripple_normal_amplitude", ripple_normal_amplitude)

func _apply_uniform(uniform_name: String, value: Variant) -> void:
	if _material:
		_material.set_shader_parameter(uniform_name, value)

# Called by region_sky.gd so the standing-pool color always tracks the
# sky's horizon color without manual duplication. pool_color's own
# export default above is the fallback if no sky node pushes a value.
# Darkened, not a direct copy: horizon_color at full brightness blows
# pools out white once they're catching sky-colored specular. Pools are
# meant to be the darkest thing on the ground, never the brightest.
func set_pool_color_from_sky(sky_horizon_color: Color) -> void:
	pool_color = Color(
		sky_horizon_color.r * 0.75,
		sky_horizon_color.g * 0.75,
		sky_horizon_color.b * 0.75,
		sky_horizon_color.a
	)
