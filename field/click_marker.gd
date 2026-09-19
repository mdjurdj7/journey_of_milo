extends MeshInstance3D
class_name ClickMarker

# The point-to-move click mark: a thin flat ring laid on the ground where
# the click landed, in the battle theme's ink at marker_alpha, fading out
# over fade_time and then hidden - no glow, nothing else moves. One
# instance, created by RegionField on first use and reused for every
# click (a new click restarts the fade at full alpha wherever it landed).
# Unshaded and drawn without depth testing, so it reads through a slope
# or a hull's edge for the fraction of a second it exists.

@export var ring_radius: float = 0.3
@export var ring_width: float = 0.03
@export var ring_segments: int = 48
@export_range(0.0, 1.0) var marker_alpha: float = 0.6
@export var fade_time: float = 0.6
# Raised this far off the hit point so a flat ring on flat sand doesn't
# z-fight it.
@export var lift: float = 0.02

var _material: StandardMaterial3D = null
var _fade_tween: Tween = null

func _ready() -> void:
	mesh = _build_ring_mesh()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = 1
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false

# An annulus in the XZ plane: ring_segments quads between the inner and
# outer radius, wound so the up-facing side is the front (cull is off
# anyway).
func _build_ring_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner: float = maxf(ring_radius - ring_width * 0.5, 0.0)
	var outer: float = ring_radius + ring_width * 0.5
	var segments: int = maxi(ring_segments, 3)
	for i in segments:
		var a0: float = TAU * float(i) / float(segments)
		var a1: float = TAU * float(i + 1) / float(segments)
		var i0 := Vector3(cos(a0) * inner, 0.0, sin(a0) * inner)
		var o0 := Vector3(cos(a0) * outer, 0.0, sin(a0) * outer)
		var i1 := Vector3(cos(a1) * inner, 0.0, sin(a1) * inner)
		var o1 := Vector3(cos(a1) * outer, 0.0, sin(a1) * outer)
		surface.set_normal(Vector3.UP)
		surface.add_vertex(i0)
		surface.add_vertex(i1)
		surface.add_vertex(o0)
		surface.add_vertex(o0)
		surface.add_vertex(i1)
		surface.add_vertex(o1)
	return surface.commit()

# Lays the ring at `point` (world) in `ink` and starts the fade.
func show_at(point: Vector3, ink: Color) -> void:
	global_position = point + Vector3.UP * lift
	var color: Color = ink
	color.a = marker_alpha
	_material.albedo_color = color
	visible = true
	if _fade_tween != null:
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_material, "albedo_color:a", 0.0, fade_time)
	_fade_tween.tween_callback(func() -> void: visible = false)
