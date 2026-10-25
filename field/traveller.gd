extends Node3D
class_name Traveller

# The Iron Pilgrim.

# Someone glimpsed on arrival (FloorData.traveller_glimpse): already walking
# away up the floor, his whole body in frame just under its top edge, as
# the floor fades in - and out through that edge before the player can
# follow (the glimpse's arrival hold lasts until he has left the frame -
# left_frame).
# RegionField spawns one at load the first time a run stands on a floor
# that has a glimpse (has_glimpsed()/mark_glimpsed(), cleared by
# RunState.new_run()) - when the glimpse's chance comes up, and never two
# runs in a row (or always, with debug_force) - and hands it the glimpse
# (walk()). He walks its path
# at its speed, feet on the relief, facing the way he goes. No collision,
# nothing to click, and nothing on the floor reacts to him. The moment he
# is wholly outside the camera's frustum he is freed: he leaves through
# the frame's top edge, so it never happens on screen, and a player who
# runs after him finds the way empty.
#
# The body is a model scene (model_scene_path): the Iron Pilgrim's rigged
# glb, or the placeholder (traveller_placeholder.tscn: a capsule, a small
# head, a flat disc hat). Every mesh under it wears the painted shader on
# the model's own colour map (colour_map_path) times tint - or flat at
# figure_ink with no map; no fog - the arrival fade is what softens him. A
# model with its own walk clip (walk_clip) walks on it and stands on its
# idle clip; one without (the placeholder) walks on a tweened bob and sway.

# Floors with a glimpse already stood on this run, "<region>:<floor>" -
# shown or not - a static set like Hull._findings_shown, so a floor stood
# on again shows no one and never rolls again.
static var _glimpsed: Dictionary = {}

# He is wholly outside the camera's frustum and about to be freed - what
# RegionField's arrival hold waits for on the visit that shows him.
signal left_frame
# Whether this run, and the run before it, showed anyone - the chance
# (TravellerGlimpse.chance_per_run) never comes up two runs in a row.
# Only within the session: nothing persists between sessions.
static var _shown_this_run: bool = false
static var _shown_last_run: bool = false
# The F1 row's Traveller toggle (debug builds): every floor with a glimpse
# shows him on its first visit of a run, whatever the roll. Static, so it
# holds across the floor reloads.
static var debug_force: bool = false

static func has_glimpsed(key: String) -> bool:
	return _glimpsed.has(key)

static func mark_glimpsed(key: String) -> void:
	_glimpsed[key] = true

static func mark_shown() -> void:
	_shown_this_run = true

static func shown_last_run() -> bool:
	return _shown_last_run

# A new run (RunState.new_run()): no floor stood on, and this run's
# showing becomes the last run's.
static func reset_glimpses() -> void:
	_glimpsed.clear()
	_shown_last_run = _shown_this_run
	_shown_this_run = false

# The body. Loaded at runtime; a change swaps it live.
@export_file("*.tscn", "*.glb") var model_scene_path: String = "res://assets/models/iron_pilgrim/iron_pilgrim.glb":
	set(value):
		model_scene_path = value
		if is_inside_tree():
			_build_model()
# Yaw of the model under this node so its front lies on the node's -Z, the
# way he walks. 180 for the Iron Pilgrim's rig (Mixamo-style, facing +Z);
# 0 for the placeholder.
@export var model_yaw_offset_degrees: float = 180.0:
	set(value):
		model_yaw_offset_degrees = value
		if _model != null:
			_model.rotation_degrees.y = model_yaw_offset_degrees
# The model's own colour map: its glb's albedo, extracted once on import
# (the glb's other maps are discarded - the painted shader takes none).
# Empty for flat figure_ink (the placeholder).
@export_file("*.jpg", "*.png") var colour_map_path: String = "res://assets/models/iron_pilgrim/iron_pilgrim_texture_0.png":
	set(value):
		colour_map_path = value
		if is_inside_tree():
			_build_model()
# Multiplied into the colour map - white is the map as painted.
@export var tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		tint = value
		if _material != null and not _inked:
			_material.set_shader_parameter("albedo_tint", tint)
# With no colour map: the darkest figure ink (the art bible's UI ink),
# times the painted shader's light.
@export var figure_ink: Color = Color(0.165, 0.165, 0.18):
	set(value):
		figure_ink = value
		if _material != null and _inked:
			_material.set_shader_parameter("albedo_tint", figure_ink)

@export_group("Walk")
# The model's own clips, looped: walk_clip while he walks, idle_clip while
# he stands (the start delay, the path's end). A model without walk_clip
# walks on the bob and sway below instead.
@export var walk_clip: StringName = &"Walking":
	set(value):
		walk_clip = value
		_loop_clips()
		_start_walk_motion()
@export var idle_clip: StringName = &"Idle_12":
	set(value):
		idle_clip = value
		_loop_clips()
		_start_walk_motion()
# For a model without walk_clip - one step: the body rises bob_height and
# settles once a step, and sways sway_degrees to one side and back over
# each step, the other side the next - a walking cadence for speed
# ~1.3 m/s.
@export var step_seconds: float = 0.55:
	set(value):
		step_seconds = value
		_start_walk_motion()
@export var bob_height: float = 0.035:
	set(value):
		bob_height = value
		_start_walk_motion()
@export var sway_degrees: float = 2.0:
	set(value):
		sway_degrees = value
		_start_walk_motion()
@export_group("")

var _glimpse: TravellerGlimpse = null
var _origin: Vector2 = Vector2.ZERO
# Where he is on the path: the segment's start index and metres into it.
var _segment: int = 0
var _along: float = 0.0
var _delay_left: float = 0.0
var _walking: bool = false
var _model: Node3D = null
var _material: ShaderMaterial = null
# The material is flat figure_ink, not a colour map.
var _inked: bool = false
# The model's AnimationPlayer; null for a model with none.
var _player: AnimationPlayer = null
# The model's bounds in this node's space - what the frustum test reads.
var _bounds: AABB = AABB()
var _bob_tween: Tween = null
var _sway_tween: Tween = null
# Physics frames since walk(): the camera's first frames place it, so the
# frustum is only read once it stands.
var _frames: int = 0

func _ready() -> void:
	_build_model()

# Sets him on `glimpse`'s first point (relative to `origin`, the floor's
# spawn XZ) and starts the walk.
func walk(glimpse: TravellerGlimpse, origin: Vector2) -> void:
	_glimpse = glimpse
	_origin = origin
	_segment = 0
	_along = 0.0
	_frames = 0
	_delay_left = glimpse.start_delay if glimpse != null else 0.0
	_walking = glimpse != null and glimpse.path.size() >= 2
	if glimpse == null or glimpse.path.is_empty():
		push_warning("Traveller: a glimpse with no path; nothing to walk.")
		queue_free()
		return
	_place()
	_start_walk_motion()

func _physics_process(delta: float) -> void:
	if _glimpse == null:
		return
	_frames += 1
	if _walking:
		if _delay_left > 0.0:
			_delay_left -= delta
			if _delay_left <= 0.0:
				_start_walk_motion()
		else:
			_advance(maxf(_glimpse.speed, 0.0) * delta)
	_place()
	if _frames > 2 and _out_of_frame():
		left_frame.emit()
		queue_free()

func _advance(metres: float) -> void:
	_along += metres
	var path: PackedVector2Array = _glimpse.path
	while _segment < path.size() - 1:
		var length: float = path[_segment].distance_to(path[_segment + 1])
		if _along < length:
			return
		if _segment == path.size() - 2:
			# The last point: he stops there.
			_along = length
			_walking = false
			_start_walk_motion()
			return
		_along -= length
		_segment += 1

# On the path at the current point, feet on the relief, facing along the
# segment.
func _place() -> void:
	var path: PackedVector2Array = _glimpse.path
	var a: Vector2 = _origin + path[mini(_segment, path.size() - 1)]
	var b: Vector2 = _origin + path[mini(_segment + 1, path.size() - 1)]
	var length: float = a.distance_to(b)
	var at: Vector2 = a.lerp(b, clampf(_along / length, 0.0, 1.0)) if length > 0.0001 else a
	var height: float = global_position.y
	var ground: Ground = _ground()
	if ground != null:
		var local: Vector3 = ground.to_local(Vector3(at.x, 0.0, at.y))
		height = ground.to_global(Vector3(local.x, ground.get_height_at(Vector2(local.x, local.z)), local.z)).y
	global_position = Vector3(at.x, height, at.y)
	if length > 0.0001:
		var heading: Vector2 = (b - a) / length
		rotation.y = atan2(-heading.x, -heading.y)

# Wholly outside the camera's frustum: every corner of his bounds beyond
# one of its planes (Camera3D.get_frustum() planes face outward).
func _out_of_frame() -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null or not _bounds.has_volume():
		return false
	var corners: Array[Vector3] = []
	for i in 8:
		corners.append(global_transform * _bounds.get_endpoint(i))
	for plane: Plane in camera.get_frustum():
		var all_over: bool = true
		for corner in corners:
			if not plane.is_point_over(corner):
				all_over = false
				break
		if all_over:
			return true
	return false

func _build_model() -> void:
	if _model != null:
		_model.queue_free()
		_model = null
	var scene: PackedScene = load(model_scene_path) as PackedScene if ResourceLoader.exists(model_scene_path) else null
	if scene == null:
		push_warning("Traveller: no model at '%s'." % model_scene_path)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)
	_model.rotation_degrees.y = model_yaw_offset_degrees
	_material = PaintedProp.material(colour_map_path, tint) if not colour_map_path.is_empty() else null
	_inked = _material == null
	if _inked:
		var shader := load(PaintedProp.PAINTED_SHADER_PATH) as Shader
		if shader != null:
			_material = ShaderMaterial.new()
			_material.shader = shader
			_material.set_shader_parameter("albedo_tint", figure_ink)
	_bounds = PaintedProp.dress_model(_model, _material, self)
	# No cast shadow: a shadow stretched past him would stay in frame
	# after he is freed and vanish there.
	for node in _model.find_children("*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var players: Array[Node] = _model.find_children("*", "AnimationPlayer", true, false)
	_player = players[0] as AnimationPlayer if not players.is_empty() else null
	_loop_clips()
	_start_walk_motion()

# Imported clips come in unlooped; walk_clip and idle_clip loop.
func _loop_clips() -> void:
	if _player == null:
		return
	for clip: StringName in [walk_clip, idle_clip]:
		if _player.has_animation(clip):
			_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR

func _has_walk_clip() -> bool:
	return _player != null and _player.has_animation(walk_clip)

# walk_clip while he walks, idle_clip while he stands (the start delay,
# the path's end) - or, for a model without walk_clip, the bob and the
# sway, looping while he walks and settled while he stands.
func _start_walk_motion() -> void:
	if _bob_tween != null:
		_bob_tween.kill()
		_bob_tween = null
	if _sway_tween != null:
		_sway_tween.kill()
		_sway_tween = null
	if _model == null or not is_inside_tree():
		return
	_model.position.y = 0.0
	_model.rotation_degrees.z = 0.0
	var walking: bool = _walking and _delay_left <= 0.0
	if _has_walk_clip():
		var clip: StringName = walk_clip if walking else idle_clip
		if _player.has_animation(clip) and _player.current_animation != clip:
			_player.play(clip)
		elif not _player.has_animation(clip):
			_player.stop()
		return
	if not walking or step_seconds <= 0.0:
		return
	var half: float = step_seconds * 0.5
	# Mid-stride from the first frame: the bob starts at its top.
	_model.position.y = bob_height
	_bob_tween = create_tween().set_loops()
	_bob_tween.tween_property(_model, "position:y", 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_bob_tween.tween_property(_model, "position:y", bob_height, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_model, "rotation_degrees:z", sway_degrees, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_model, "rotation_degrees:z", 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_model, "rotation_degrees:z", -sway_degrees, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_sway_tween.tween_property(_model, "rotation_degrees:z", 0.0, half).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _ground() -> Ground:
	var region_field := get_parent() as RegionField
	if region_field == null:
		return null
	return region_field.get_node_or_null(region_field.ground_path) as Ground
