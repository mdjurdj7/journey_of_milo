extends Node
class_name BattleOcclusion

# The battle frame's readability rule for what isn't a fighter: while the
# frame is up (CameraRig.is_battle_framing()), any prop that covers a
# fighter from in front - its screen box over the fighter's, nearer the
# camera by more than depth_margin_m - or lies under a fighter's readout
# (its HP/name plate, its intent, his HP bar) fades out with a dither,
# and comes back when the frame goes. The scatter does the same per item
# (FieldScatter.set_battle_screen()). Fighters are never faded, nor a
# prop the fight's own option brought or one a member stands on
# (RegionField.is_battle_exempt_prop()).
#
# The fade runs over the camera's swing (battle_transition_time), unless
# fade_seconds is set. How a prop fades depends on what it wears:
# - the painted shader (wanderer_painted.gdshader): its own `presence`
#   dither, the fog pass's `presence` with it;
# - a plain material (StandardMaterial3D): while faded, a copy of it set
#   to alpha hash (a dither) under the instance's transparency - put back
#   as it was once solid again;
# - any other shader: the instance's transparency alone.
#
# A child of RegionField, made at its _ready(); PROCESS_MODE_ALWAYS, so it
# runs through the fight's freeze.

# Seconds to fade fully out or back; below 0, the camera's swing.
@export var fade_seconds: float = -1.0
# How much nearer the camera than a fighter's origin a prop must be to
# count as in front of it, metres.
@export var depth_margin_m: float = 0.2
# Readouts and fighters' boxes grown by this, pixels, before the test.
@export var screen_margin_px: float = 6.0
# A prop or scatter item standing where the battle press draws the sand
# more than this lower (Ground.get_battle_press_drop()) fades rather than
# float over it, metres.
@export var press_float_m: float = 0.03

var _field: RegionField = null
# GeometryInstance3D -> its presence now (1 solid, 0 gone). Only ones
# that have faded at all.
var _presence: Dictionary = {}
# GeometryInstance3D -> the material_override it had before its hashed
# copy went on (null for none).
var _restore: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_field = get_parent() as RegionField

func _process(delta: float) -> void:
	if _field == null:
		return
	var rig := _field.get_node_or_null(_field.camera_rig_path) as CameraRig
	var framing: bool = rig != null and rig.is_battle_framing() and _field.is_battle_open()
	var seconds: float = fade_seconds if fade_seconds >= 0.0 else (rig.battle_transition_time if rig != null else 0.6)
	var step: float = delta / maxf(seconds, 1.0e-3)
	var camera: Camera3D = get_viewport().get_camera_3d()
	var fighter_rects: Array[Rect2] = []
	var fighter_depths: PackedFloat32Array = PackedFloat32Array()
	var readouts: Array[Rect2] = []
	if framing and camera != null:
		_gather(camera, fighter_rects, fighter_depths, readouts)
	var scatter: FieldScatter = _field.get_scatter()
	if scatter != null:
		scatter.set_battle_screen(camera if framing else null, fighter_rects, fighter_depths, readouts, depth_margin_m, press_float_m)
	var targets: Dictionary = {}
	if framing and camera != null:
		var props_root: Node = _field.get_node_or_null(RegionField.PROPS_NODE_NAME)
		if props_root != null:
			for prop in props_root.get_children():
				if _field.is_battle_exempt_prop(prop):
					continue
				var geometry: Array[GeometryInstance3D] = _geometry_of(prop)
				if _floats(prop) or _occludes(geometry, camera, fighter_rects, fighter_depths, readouts):
					for instance in geometry:
						targets[instance] = true
	for instance: GeometryInstance3D in targets:
		if not _presence.has(instance):
			_presence[instance] = 1.0
	for instance in _presence.keys():
		if not is_instance_valid(instance):
			_presence.erase(instance)
			_restore.erase(instance)
			continue
		var target: float = 0.0 if targets.has(instance) else 1.0
		var now: float = move_toward(float(_presence[instance]), target, step)
		_presence[instance] = now
		_apply(instance as GeometryInstance3D, now)
		if now >= 1.0 and target >= 1.0:
			_presence.erase(instance)

# Whether every prop has reached its fade (none part-way).
func is_settled() -> bool:
	for instance in _presence.keys():
		var now: float = float(_presence[instance])
		if now > 0.0 and now < 1.0:
			return false
	return true

# The fighters' screen boxes and depths, and every readout's rect.
func _gather(camera: Camera3D, fighter_rects: Array[Rect2], fighter_depths: PackedFloat32Array, readouts: Array[Rect2]) -> void:
	var forward: Vector3 = -camera.global_basis.z
	var wanderer: Node3D = _field.wanderer
	if wanderer != null:
		var rect: Rect2 = _screen_rect(_geometry_of(wanderer), camera)
		if rect.has_area():
			fighter_rects.append(rect.grow(screen_margin_px))
			fighter_depths.append((wanderer.global_position - camera.global_position).dot(forward))
	for member in _field.get_battle_members():
		if not is_instance_valid(member) or member.is_defeated():
			continue
		var rect: Rect2 = member.get_screen_rect(camera, screen_margin_px)
		if rect.has_area():
			fighter_rects.append(rect)
			fighter_depths.append((member.global_position - camera.global_position).dot(forward))
	var overlay: BattleOverlay = _field.get_battle_overlay()
	if overlay != null:
		for rect in overlay.get_readout_rects():
			readouts.append(rect.grow(screen_margin_px))
	if _field.hp_bar != null and _field.hp_bar.is_visible_in_tree():
		readouts.append(_field.hp_bar.get_global_rect().grow(screen_margin_px))

# Whether a prop's geometry covers a fighter from in front or lies under
# a readout.
func _occludes(geometry: Array[GeometryInstance3D], camera: Camera3D, fighter_rects: Array[Rect2], fighter_depths: PackedFloat32Array, readouts: Array[Rect2]) -> bool:
	var forward: Vector3 = -camera.global_basis.z
	for instance in geometry:
		var box: AABB = instance.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		var rect := Rect2()
		var first: bool = true
		var nearest: float = INF
		for k in 8:
			var corner: Vector3 = instance.global_transform * box.get_endpoint(k)
			nearest = minf(nearest, (corner - camera.global_position).dot(forward))
			if camera.is_position_behind(corner):
				continue
			var point: Vector2 = camera.unproject_position(corner)
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
		if first:
			continue
		for i in fighter_rects.size():
			if rect.intersects(fighter_rects[i]) and nearest < fighter_depths[i] - depth_margin_m:
				return true
		for readout in readouts:
			if rect.intersects(readout):
				return true
	return false

# Whether a prop stands where the press draws the sand away under it.
func _floats(prop: Node) -> bool:
	var ground := _field.get_node_or_null(_field.ground_path) as Ground
	if ground == null or not prop is Node3D:
		return false
	var at: Vector3 = (prop as Node3D).global_position
	at.y = ground.get_visible_height_at(Vector2(at.x, at.z))
	return ground.get_battle_press_drop(at) > press_float_m

static func _geometry_of(node: Node) -> Array[GeometryInstance3D]:
	var found: Array[GeometryInstance3D] = []
	if node is GeometryInstance3D:
		found.append(node as GeometryInstance3D)
	for child in node.find_children("*", "GeometryInstance3D", true, false):
		var instance := child as GeometryInstance3D
		if instance.is_visible_in_tree():
			found.append(instance)
	return found

static func _screen_rect(geometry: Array[GeometryInstance3D], camera: Camera3D) -> Rect2:
	var rect := Rect2()
	var first: bool = true
	for instance in geometry:
		var box: AABB = instance.get_aabb()
		if box.size == Vector3.ZERO:
			continue
		for k in 8:
			var corner: Vector3 = instance.global_transform * box.get_endpoint(k)
			if camera.is_position_behind(corner):
				continue
			var point: Vector2 = camera.unproject_position(corner)
			rect = Rect2(point, Vector2.ZERO) if first else rect.expand(point)
			first = false
	return rect

# One instance at `presence`: through its painted material's dither, a
# hashed copy of its plain material, or its transparency alone.
func _apply(instance: GeometryInstance3D, presence: float) -> void:
	var painted: ShaderMaterial = _painted_material(instance)
	if painted != null:
		painted.set_shader_parameter("presence", presence)
		var fog := painted.next_pass as ShaderMaterial
		if fog != null:
			fog.set_shader_parameter("presence", presence)
		return
	var plain: BaseMaterial3D = _plain_material(instance)
	if plain != null:
		if presence < 1.0 and not _restore.has(instance):
			_restore[instance] = instance.material_override
			var hashed := plain.duplicate() as BaseMaterial3D
			hashed.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_HASH
			instance.material_override = hashed
		elif presence >= 1.0 and _restore.has(instance):
			instance.material_override = _restore[instance]
			_restore.erase(instance)
	instance.transparency = 1.0 - presence

static func _painted_material(instance: GeometryInstance3D) -> ShaderMaterial:
	var material := instance.material_override as ShaderMaterial
	if material == null and instance is MeshInstance3D:
		var mesh_instance := instance as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			material = mesh_instance.get_active_material(0) as ShaderMaterial
	if material != null and material.shader != null and material.shader.resource_path == PaintedProp.PAINTED_SHADER_PATH:
		return material
	return null

func _plain_material(instance: GeometryInstance3D) -> BaseMaterial3D:
	if _restore.has(instance):
		var original: Material = _restore[instance]
		if original is BaseMaterial3D:
			return original as BaseMaterial3D
	if instance.material_override is BaseMaterial3D:
		return instance.material_override as BaseMaterial3D
	if instance is MeshInstance3D:
		var mesh_instance := instance as MeshInstance3D
		if mesh_instance.mesh != null and mesh_instance.mesh.get_surface_count() > 0:
			return mesh_instance.get_active_material(0) as BaseMaterial3D
	return null
