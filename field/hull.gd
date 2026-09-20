extends Node3D
class_name Hull

# An aged rowing-boat hull pulled up on the sand: the opening room's mid-
# distance dressing (Region 1 doc, section 3). Loads hull.glb at runtime
# under this node, applies the project's flat matte material (same shape
# as Wanderer._build_flat_material() - one StandardMaterial3D via
# material_override on every mesh, roughness 1, no specular; the glb's own
# PBR textures are ignored, this field is flat-shaded), faces its bow
# seaward, and sits on the relief minus sink_depth of its own height.
# Solid to the Wanderer at the gunwale (see collision_inset).

const MODEL_SCENE_PATH := "res://assets/models/hull/hull.glb"

# hull.glb ships normalised to a 1m-long boat (bbox 1.00 x 0.31 x 0.51m,
# long axis X, verified from the vertex data, no import scale); a rowing
# boat is ~4-5m. The mesh's final size is model_scale x mesh_scale -
# mesh_scale is the on-screen correction knob, model_scale the nominal
# metres-per-unit. _ready() prints the resulting bbox so the real size is
# never a guess.
@export var model_scale: float = 4.5:
	set(value):
		model_scale = value
		_apply_model_transform()
@export var mesh_scale: float = 0.65:
	set(value):
		mesh_scale = value
		_apply_model_transform()
# Yaw of the model under this node so its bow lies on the node's local -Z
# (the direction _apply_facing() points seaward). The glb's long axis is
# X; 90 maps +X onto -Z. Flip to -90 if the boat lands stern-first.
@export var model_yaw_offset_degrees: float = 90.0:
	set(value):
		model_yaw_offset_degrees = value
		_apply_model_transform()
# Fraction of the model's SCALED bounding-box height the hull is lowered
# into the ground - the bbox bottom sits that far below the relief
# surface at the hull's centre (and the hull is pitched to the beach
# slope, so both ends sit the same way - see _ground_to_relief()). 0.3
# with a ~10 degree roll puts the sand up the low side inside the hull
# and leaves the outer quarter of the floor (the inside of the bottom
# planking) showing on the high side, 12-16cm proud.
@export_range(0.0, 1.0) var sink_depth: float = 0.3:
	set(value):
		sink_depth = value
		_apply_collision()
		_ground_to_relief()
# Collision: one BoxShape3D under a StaticBody3D child of this node (so
# the sink, pitch and roll carry over), sized from the scaled bbox - X/Z
# inset by collision_inset so the Wanderer brushes the gunwale rather
# than snagging on the box's own corners, height cut down by the sink so
# the box top sits at the visible gunwale and its bottom at the sand.
# Default physics layer/mask (1/1), the same the boundary walls and the
# Wanderer use. A box is still square at the pointed bow, so the corners
# there stand ~0.5m proud of the wood - raise collision_inset if that
# snags.
@export var collision_inset: float = 0.15:
	set(value):
		collision_inset = value
		_apply_collision()
# List around the hull's own long axis (the keel line), so it reads as
# settled into the sand rather than sitting level - sand climbs one side
# inside, the floor shows on the other.
@export var roll_degrees: float = 10.0:
	set(value):
		roll_degrees = value
		_ground_to_relief()
# Added to the seaward facing, so several hulls don't all point exactly
# the same way. Re-grounds (not just re-faces): the slope samples run
# along the facing, so the pitch changes with it.
@export var yaw_offset_degrees: float = 0.0:
	set(value):
		yaw_offset_degrees = value
		_ground_to_relief()
# Weathered wood as a dark figure on the pale ground: a grey with a
# slight warm bias (R - B +0.08, less warm than the sand's +0.14),
# applied as the albedo of this hull's own duplicate of the shared flat
# material (see _shared_flat_material), so it's well below the sand
# (Ground.ground_color (0.74, 0.70, 0.60), value 0.74 vs 0.50 here)
# without touching the material anything else shares.
@export var hull_tint: Color = Color(0.50, 0.47, 0.42):
	set(value):
		hull_tint = value
		if _material != null:
			_material.albedo_color = value
# Instances live under RegionField/Hulls, so Ground and RegionField are
# two levels up.
@export var ground_path: NodePath = ^"../../Ground"
@export var region_field_path: NodePath = ^"../.."

# A finding, not an incident: when the Wanderer first comes within
# approach_radius, world_line (if any) is shown once through the field's
# WorldVoiceLine (see ui/world_voice_line.gd) - fades in, holds
# hold_seconds, fades out. No sound, no prompt, no interaction. Empty
# world_line = this hull says nothing (Hull1/Hull3). shows_once_per_run
# remembers the finding across the floor reloads a run goes through (see
# _findings_shown).
@export_group("Finding")
@export var approach_radius: float = 2.5:
	set(value):
		approach_radius = value
		_apply_approach_radius()
@export_multiline var world_line: String = ""
@export var shows_once_per_run: bool = true
@export var hold_seconds: float = 4.0
@export var fade_seconds: float = 0.5
# What the once-per-run set keys this hull's line under. Set by RegionField
# when the hull is spawned from FloorData (the floor resource's path plus
# its index in that floor's props - stable across the reload a floor
# change is, distinct across floors); empty = derived from the scene this
# node was authored in, see _finding_id().
@export var finding_id: String = ""
@export_group("")

# Findings already shown this run, keyed by _finding_id() - static so it
# survives the reload_current_scene() a floor exit does (a node-local
# flag would replay the line on the next floor). Cleared by
# RunState.new_run() via reset_findings(), so a new run hears every
# line again.
static var _findings_shown: Dictionary = {}

static func reset_findings() -> void:
	_findings_shown.clear()

# The project's flat matte material (the same recipe as Wanderer._build_
# flat_material(): roughness 1, no specular), built once for the class
# and never applied directly - every Hull duplicates it and tints the
# copy (hull_tint), so the shared instance stays untouched for anything
# else that adopts it.
static var _shared_flat_material: StandardMaterial3D = null

static func _get_shared_flat_material() -> StandardMaterial3D:
	if _shared_flat_material == null:
		_shared_flat_material = StandardMaterial3D.new()
		_shared_flat_material.roughness = 1.0
		_shared_flat_material.metallic_specular = 0.0
	return _shared_flat_material

var _model: Node3D = null
# This hull's own tinted duplicate of _shared_flat_material.
var _material: StandardMaterial3D = null
var _approach_area: Area3D = null
var _approach_shape: SphereShape3D = null
var _collision_body: StaticBody3D = null
var _collision_shape_node: CollisionShape3D = null
var _collision_shape: BoxShape3D = null
# The model's combined bbox in this node's space at the final scale, as
# measured by _apply_model_transform() (before it seats the bottom on the
# origin - _aabb_height/_aabb_length are its size).
var _aabb: AABB = AABB()
var _ground: Ground = null
# Model bbox in this node's space at the final scale, from _apply_model_
# transform(): height for sink_depth, length for the slope samples,
# bottom for seating the bbox on the node origin.
var _aabb_height: float = 0.0
var _aabb_length: float = 0.0
# Guards the setters above during scene deserialization, same as
# Ground/Sea's own _ready_done flags.
var _ready_done: bool = false

func _ready() -> void:
	_spawn_model()
	_spawn_approach_area()
	_ready_done = true
	_apply_facing()

	# Ground precedes Hulls in the scene, so Ground's own first
	# relief_rebuilt (inside its _ready()) has already fired by now - the
	# manual call covers the initial grounding (model scale and relief
	# both final at this point), the connection every live relief/landmass
	# edit after it (same reasoning as FieldEnemy's).
	_ground = get_node_or_null(ground_path) as Ground
	if _ground == null:
		push_warning("Hull '%s': ground_path did not resolve to a Ground; not grounded." % name)
		return
	_ground.relief_rebuilt.connect(_ground_to_relief)
	_ground_to_relief()

func _spawn_model() -> void:
	var scene := load(MODEL_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("Hull: could not load %s; no model." % MODEL_SCENE_PATH)
		return
	_model = scene.instantiate() as Node3D
	_model.name = "Model"
	add_child(_model)

	_material = _get_shared_flat_material().duplicate() as StandardMaterial3D
	_material.albedo_color = hull_tint
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		mi.material_override = _material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	_apply_model_transform()

# The approach trigger: a sphere of approach_radius around the hull's
# origin, watching for the Wanderer (group "wanderer", a CharacterBody3D
# on the default layer). Built here rather than in hull.tscn so the
# radius export can re-apply live. Not monitorable - nothing needs to
# detect the hull.
func _spawn_approach_area() -> void:
	_approach_area = Area3D.new()
	_approach_area.name = "ApproachArea"
	_approach_area.monitorable = false
	_approach_shape = SphereShape3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.shape = _approach_shape
	_approach_area.add_child(shape_node)
	add_child(_approach_area)
	_apply_approach_radius()
	_approach_area.body_entered.connect(_on_approach_body_entered)

func _apply_approach_radius() -> void:
	if _approach_shape != null:
		_approach_shape.radius = maxf(approach_radius, 0.0)

# finding_id if the spawner set one; else scene file + path from the scene
# root, so the same hull on a reloaded floor has the same id and the same
# hull in another scene doesn't. (A hull spawned at runtime has no owner,
# so that fallback would give every such hull the same id - which is why
# FloorData spawns set finding_id.)
func _finding_id() -> String:
	if not finding_id.is_empty():
		return finding_id
	var root: Node = owner if owner != null else self
	return "%s:%s" % [root.scene_file_path, str(root.get_path_to(self))]

# FloorProp's placement onto this hull's own exports (RegionField._spawn_
# floor_props()): the node sits at `world_position` (Y ignored, the hull
# grounds itself), yaw is yaw_offset_degrees on top of the bow-to-sea
# facing, roll is roll_degrees. Called before this node enters the tree.
func set_floor_placement(world_position: Vector3, yaw: float, roll: float) -> void:
	position = Vector3(world_position.x, 0.0, world_position.z)
	yaw_offset_degrees = yaw
	roll_degrees = roll

func _on_approach_body_entered(body: Node3D) -> void:
	if not body.is_in_group("wanderer"):
		return
	if world_line.is_empty():
		return
	var id: String = _finding_id()
	if shows_once_per_run and _findings_shown.has(id):
		return
	var region_field := get_node_or_null(region_field_path) as Node
	var hud: Node = region_field.get_node_or_null(^"FieldHUD") if region_field != null else null
	var line := WorldVoiceLine.on_hud(hud)
	if line == null:
		push_warning("Hull '%s': no FieldHUD to show its world line on." % name)
		return
	line.fade_in_seconds = fade_seconds
	line.fade_out_seconds = fade_seconds
	line.show_line(world_line, hold_seconds)
	_findings_shown[id] = true

# Order of operations, because it matters for the sink: (1) scale + bow
# yaw on the model, (2) measure its combined bbox in THIS node's space -
# the model's transform is already applied, so height/length are the
# final scaled ones - (3) seat the bbox bottom on the node origin, (4)
# re-ground (a no-op until _ready() is done; _ready() then grounds once
# itself, after Ground's relief already exists). The node's own Y is
# therefore always "relief minus sink x the SCALED height", never a
# pre-scale number. Same AABB-grounding idiom as FieldEnemy._spawn_model().
func _apply_model_transform() -> void:
	if _model == null:
		return
	_model.scale = Vector3.ONE * model_scale * mesh_scale
	_model.rotation = Vector3(0.0, deg_to_rad(model_yaw_offset_degrees), 0.0)
	_model.position = Vector3.ZERO

	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in _model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		var mi_transform_in_self := _model.transform * _model_local_transform_of(mi)
		var mi_aabb_in_self := mi_transform_in_self * mi.get_aabb()
		combined_aabb = mi_aabb_in_self if not has_aabb else combined_aabb.merge(mi_aabb_in_self)
		has_aabb = true
	if not has_aabb:
		return
	_aabb = combined_aabb
	_aabb_height = combined_aabb.size.y
	_aabb_length = combined_aabb.size.z
	_model.position.y = -combined_aabb.position.y
	print("Hull '%s': scaled bbox %.2f long x %.2f high x %.2f beam (model_scale %.2f x mesh_scale %.2f)" % [name, combined_aabb.size.z, combined_aabb.size.y, combined_aabb.size.x, model_scale, mesh_scale])
	_apply_collision()
	_ground_to_relief()

# Builds the StaticBody3D/BoxShape3D on first call, then (re)sizes it
# from _aabb, collision_inset and sink_depth - see collision_inset's own
# doc. In node space the bbox bottom sits on the origin (see above) and
# the sand surface at sink_depth x height, so the box runs from the sand
# to the gunwale: size.y = height x (1 - sink), centred between the two.
func _apply_collision() -> void:
	if _model == null or _aabb.size == Vector3.ZERO:
		return
	if _collision_body == null:
		_collision_body = StaticBody3D.new()
		_collision_body.name = "Collision"
		# Same reasoning as Ground's/FieldEnemy's/Keeper's own override:
		# RegionField's battle freeze would otherwise remove the hull from
		# the physics space entirely (disable_mode's default, REMOVE), and a
		# click on it during a fight would fall through to the sand behind -
		# the point-to-move raycast takes whatever body it hits (see
		# RegionField._unhandled_input()). MAKE_STATIC keeps it solid frozen.
		_collision_body.disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC
		_collision_shape = BoxShape3D.new()
		_collision_shape_node = CollisionShape3D.new()
		_collision_shape_node.shape = _collision_shape
		_collision_body.add_child(_collision_shape_node)
		add_child(_collision_body)
	var inset: float = maxf(collision_inset, 0.0)
	var sink: float = clampf(sink_depth, 0.0, 1.0)
	var box_height: float = _aabb.size.y * (1.0 - sink)
	_collision_shape.size = Vector3(
		maxf(_aabb.size.x - 2.0 * inset, 0.01),
		maxf(box_height, 0.01),
		maxf(_aabb.size.z - 2.0 * inset, 0.01)
	)
	# XZ centred on the bbox (the model yaw leaves it centred on the
	# origin, but don't assume it); Y from the sand level up.
	var centre: Vector3 = _aabb.get_center()
	_collision_shape_node.position = Vector3(centre.x, _aabb.size.y * sink + box_height * 0.5, centre.z)

# A mesh instance's transform relative to the model root (not the world),
# so the bbox measurement above doesn't depend on this node's own current
# rotation/position - it must be the same number before and after
# _apply_facing() pitches and rolls the node.
func _model_local_transform_of(mi: MeshInstance3D) -> Transform3D:
	return _model.global_transform.affine_inverse() * mi.global_transform

# The hull's yaw: bow toward the sea (-get_forward(), same direction<->
# angle convention FieldEnemy._face_shore() uses) plus yaw_offset_degrees.
func _facing_yaw() -> float:
	var to_sea := Vector3.BACK
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field != null:
		to_sea = -region_field.get_forward()
	if to_sea.length() < 0.0001:
		to_sea = Vector3.BACK
	return atan2(-to_sea.x, -to_sea.z) + deg_to_rad(yaw_offset_degrees)

# Rebuilds the node's basis from yaw, the beach-slope pitch and
# roll_degrees around the hull's long axis (the node's local Z once the
# model yaw has put the bow on -Z). Replaces the basis outright -
# position is left to the editor, rotation isn't authored there.
func _apply_facing(pitch: float = 0.0) -> void:
	if not _ready_done:
		return
	basis = Basis(Vector3.UP, _facing_yaw()) * Basis(Vector3.RIGHT, pitch) * Basis(Vector3.BACK, deg_to_rad(roll_degrees))

# Relief height at a world XZ - get_height_at() is in Ground's local
# frame, to_local() first, same as FieldEnemy/Wanderer.
func _relief_height_at(world_x: float, world_z: float) -> float:
	var local_xz: Vector3 = _ground.to_local(Vector3(world_x, 0.0, world_z))
	return _ground.get_height_at(Vector2(local_xz.x, local_xz.z))

# Seats the hull on the relief: height sampled at the bow and stern (half
# the scaled length either way along the facing), the node placed at
# their mean minus sink_depth x the SCALED bbox height, and pitched to
# the slope between them - grounding at the centre alone left one end
# floating clear of the sand on the beach's 1:8-1:12 slope, which is what
# read as "the keel is visible". Called once from _ready() (after both
# the model scale and Ground's relief are final) and on every Ground.
# relief_rebuilt, so landmass tuning re-seats it.
func _ground_to_relief() -> void:
	if not _ready_done or _ground == null:
		return
	var yaw: float = _facing_yaw()
	# Local -Z (the bow) in world space for this yaw.
	var bow_dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var half_length: float = _aabb_length * 0.5
	var centre := Vector3(global_position.x, 0.0, global_position.z)
	var bow_point: Vector3 = centre + bow_dir * half_length
	var stern_point: Vector3 = centre - bow_dir * half_length
	var bow_height: float = _relief_height_at(bow_point.x, bow_point.z)
	var stern_height: float = _relief_height_at(stern_point.x, stern_point.z)

	# Pitch about local X: positive tips the bow (local -Z) up. The bow
	# is lower than the stern when the beach falls seaward, so the sign
	# follows (bow - stern).
	var pitch: float = atan2(bow_height - stern_height, maxf(_aabb_length, 0.001))
	_apply_facing(pitch)
	global_position.y = (bow_height + stern_height) * 0.5 - sink_depth * _aabb_height
