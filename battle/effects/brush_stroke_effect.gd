extends Node3D
class_name BrushStrokeEffect

# A card's play effect as one ink stroke (DESIGN.md: combat effects are
# ink strokes): a ribbon built in code along a path over the fight, laid
# down by a sweep from the Wanderer's side outward, held, then faded -
# matte, no glow, no particles (battle/effects/brush_stroke.gdshader).
#
# A card names its effect scene in CardData.play_effect_scene_path; a new
# effect is a new .tscn of this script with other settings, no code.
# BattleFeedback instances it on the card's impact and calls:
#   setup(origin, targets, ceiling_y)
#                           the Wanderer, the enemies the card hits and
#                           the world height it must stay under (the
#                           lowest intent readout) - builds the stroke
#                           there and plays it
#   arrival_delay(target)   seconds after the impact the stroke reaches
#                           `target` - when its hit reaction lands
# Everything is read from the live bodies when it plays, in world space,
# so it holds under any battle framing and moves with the scene under
# camera shake. Its tweens run on scaled time, so a hit-stop freezes the
# stroke with the reactions it paces.
#
# The ribbon builder takes any path (_build_ribbon()); `path` picks the
# preset that makes it. ARC is the only one so far.

enum Path { ARC }

const SHADER_PATH := "res://battle/effects/brush_stroke.gdshader"

@export var path: Path = Path.ARC:
	set(value):
		path = value
		_rebuild()

@export_group("Ink")
@export var ink_color: Color = Color("461613"):
	set(value):
		ink_color = value
		_push_material()
@export_range(0.0, 1.0) var opacity: float = 0.9:
	set(value):
		opacity = value
		_push_material()
@export_range(0.0, 1.0) var edge_raggedness: float = 0.35:
	set(value):
		edge_raggedness = value
		_push_material()
@export_range(0.0, 1.0) var streak_strength: float = 0.35:
	set(value):
		streak_strength = value
		_push_material()
# The sweep's leading edge, feathered over this fraction of the length.
@export_range(0.0, 0.5) var head_feather: float = 0.04:
	set(value):
		head_feather = value
		_push_material()

@export_group("Shape")
# The stroke's full width, metres, at its middle; the shader tapers it to
# nothing at both tips.
@export var width: float = 0.42:
	set(value):
		width = value
		_rebuild()
# ARC: how far the middle rises above the two ends, metres, at most - it
# rises less where that would reach the ceiling (readout_margin).
@export var arc_height: float = 0.9:
	set(value):
		arc_height = value
		_rebuild()
# Where the ends sit, as a fraction of the tallest target's height above
# its feet - chest height.
@export_range(0.0, 1.5) var end_height_fraction: float = 0.55:
	set(value):
		end_height_fraction = value
		_rebuild()
# How far the stroke starts before the nearest target's near side, and
# runs past the farthest target's far side, metres along the battle line.
@export var reach_before: float = 0.6:
	set(value):
		reach_before = value
		_rebuild()
@export var reach_past: float = 0.6:
	set(value):
		reach_past = value
		_rebuild()
# How far under the ceiling (the lowest enemy intent readout's bottom
# edge, handed to setup()) the stroke's top edge stays, metres - in any
# framing it never crosses a readout.
@export var readout_margin: float = 0.15:
	set(value):
		readout_margin = value
		_rebuild()
# Brought toward the camera this far past the widest target, metres, so it
# reads over the bodies rather than through them.
@export var toward_camera: float = 0.3:
	set(value):
		toward_camera = value
		_rebuild()
@export_range(8, 128) var segments: int = 48:
	set(value):
		segments = value
		_rebuild()

@export_group("Timing")
# Seconds from the impact to the far tip - the sweep that paces the hit
# reactions (arrival_delay()). Then held, then faded out. Read when the
# stroke plays.
@export var sweep_time: float = 0.16
@export var hold_time: float = 0.15
@export var fade_time: float = 0.35

var _material: ShaderMaterial = null
var _mesh_instance: MeshInstance3D = null
var _origin: Node3D = null
var _targets: Array[Node3D] = []
var _ceiling_y: float = INF
# The battle line the stroke runs along: start point, unit direction, and
# the targets' span on it (stroke start/end distances from the origin).
var _line_origin: Vector3 = Vector3.ZERO
var _line_dir: Vector3 = Vector3.RIGHT
var _span_start: float = 0.0
var _span_end: float = 1.0

func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = load(SHADER_PATH) as Shader
	_material.set_shader_parameter("seed", randf() * 100.0)
	_material.set_shader_parameter("progress", 0.0)
	_material.set_shader_parameter("fade", 1.0)
	_push_material()
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh_instance.material_override = _material
	add_child(_mesh_instance)

# Builds the stroke over `targets`, struck from `origin`, its top edge kept
# readout_margin under `ceiling_y`, and plays it: sweep, hold, fade, then
# frees itself.
func setup(origin: Node3D, targets: Array[Node3D], ceiling_y: float = INF) -> void:
	_origin = origin
	_ceiling_y = ceiling_y
	_targets.clear()
	for target in targets:
		if is_instance_valid(target):
			_targets.append(target)
	_rebuild()
	if _material == null:
		return
	var tween := create_tween()
	tween.tween_method(_set_progress, 0.0, 1.0 + head_feather, maxf(sweep_time, 0.001))
	tween.tween_interval(maxf(hold_time, 0.0))
	tween.tween_method(_set_fade, 1.0, 0.0, maxf(fade_time, 0.001))
	tween.tween_callback(queue_free)

# Seconds after the impact the sweep reaches `target`: its place along the
# stroke times sweep_time - 0 at the stroke's start, sweep_time at its far
# tip.
func arrival_delay(target: Node3D) -> float:
	if not is_instance_valid(target) or _span_end <= _span_start:
		return 0.0
	var along: float = (target.global_position - _line_origin).dot(_line_dir)
	return sweep_time * clampf((along - _span_start) / (_span_end - _span_start), 0.0, 1.0)

# --- Building ---

func _rebuild() -> void:
	if _mesh_instance == null or _origin == null or _targets.is_empty():
		return
	var points: PackedVector3Array = _path_points()
	_mesh_instance.mesh = _build_ribbon(points, _plane_normal())

# The preset's path, in world space, start (the Wanderer's side) first.
func _path_points() -> PackedVector3Array:
	var first: Node3D = _targets[0]
	var flat: Vector3 = first.global_position - _origin.global_position
	flat.y = 0.0
	_line_dir = flat.normalized() if flat.length() > 0.001 else Vector3.RIGHT
	_line_origin = _origin.global_position
	var near: float = INF
	var far: float = -INF
	var feet: float = 0.0
	var tallest: float = 0.0
	var widest: float = 0.0
	for target in _targets:
		var along: float = (target.global_position - _line_origin).dot(_line_dir)
		var half: float = _half_width(target)
		near = minf(near, along - half)
		far = maxf(far, along + half)
		feet += _feet_y(target)
		tallest = maxf(tallest, _height(target))
		widest = maxf(widest, half)
	feet /= float(_targets.size())
	_span_start = near - reach_before
	_span_end = far + reach_past
	var end_y: float = feet + tallest * end_height_fraction
	# The highest the centre line may go: its top edge readout_margin under
	# the ceiling. The ends come down to it if need be; the rise is what's
	# left, up to arc_height.
	var top_y: float = _ceiling_y - readout_margin - width * 0.5
	end_y = minf(end_y, top_y)
	var rise: float = clampf(top_y - end_y, 0.0, arc_height)
	var depth: Vector3 = _plane_normal() * (widest + toward_camera)
	var points := PackedVector3Array()
	match path:
		Path.ARC:
			for i in segments + 1:
				var t: float = float(i) / float(segments)
				var along: float = lerpf(_span_start, _span_end, t)
				var lift: float = 4.0 * t * (1.0 - t) * rise
				var point: Vector3 = _line_origin + _line_dir * along + depth
				point.y = end_y + lift
				points.append(point)
	return points

# A strip along `points` in the plane facing `normal`: each point's two
# edge vertices sit width/2 either side of the path, perpendicular to it
# within that plane. UV.x runs 0-1 along the path, UV.y 0-1 across it.
func _build_ribbon(points: PackedVector3Array, normal: Vector3) -> ArrayMesh:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int = points.size()
	if count < 2:
		return null
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	for i in count:
		var tangent: Vector3 = points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]
		var across: Vector3 = normal.cross(tangent.normalized()).normalized() * width * 0.5
		left.append(points[i] + across)
		right.append(points[i] - across)
	for i in count - 1:
		var u0: float = float(i) / float(count - 1)
		var u1: float = float(i + 1) / float(count - 1)
		_quad(tool, left[i], right[i], left[i + 1], right[i + 1], u0, u1, normal)
	return tool.commit()

func _quad(tool: SurfaceTool, l0: Vector3, r0: Vector3, l1: Vector3, r1: Vector3, u0: float, u1: float, normal: Vector3) -> void:
	for corner: Array in [[l0, Vector2(u0, 0.0)], [r0, Vector2(u0, 1.0)], [l1, Vector2(u1, 0.0)], [l1, Vector2(u1, 0.0)], [r0, Vector2(u0, 1.0)], [r1, Vector2(u1, 1.0)]]:
		tool.set_normal(normal)
		tool.set_uv(corner[1])
		tool.add_vertex(corner[0])

# The stroke's plane faces the camera: the battle line's horizontal
# normal, on the camera's side (the battle framing is side-on to it).
func _plane_normal() -> Vector3:
	var normal: Vector3 = _line_dir.cross(Vector3.UP).normalized()
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and (camera.global_position - _line_origin).dot(normal) < 0.0:
		normal = -normal
	return normal

# A target's body, read from a FieldEnemy where it is one (any Node3D
# works, standing in for a 1 m wide, 1.6 m tall body at its origin).
func _half_width(target: Node3D) -> float:
	return float(target.call("get_half_width")) if target.has_method("get_half_width") else 0.5

func _height(target: Node3D) -> float:
	return float(target.call("get_head_height")) if target.has_method("get_head_height") else 1.6

func _feet_y(target: Node3D) -> float:
	var offset: Variant = target.get("model_ground_offset")
	return target.global_position.y + (float(offset) if offset != null else 0.0)

# --- Material ---

func _push_material() -> void:
	if _material == null:
		return
	_material.set_shader_parameter("ink_color", ink_color)
	_material.set_shader_parameter("opacity", opacity)
	_material.set_shader_parameter("edge_raggedness", edge_raggedness)
	_material.set_shader_parameter("streak_strength", streak_strength)
	_material.set_shader_parameter("head_feather", head_feather)

func _set_progress(value: float) -> void:
	_material.set_shader_parameter("progress", value)

func _set_fade(value: float) -> void:
	_material.set_shader_parameter("fade", value)
