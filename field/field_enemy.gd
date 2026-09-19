extends CharacterBody3D
class_name FieldEnemy

signal contacted(enemy: FieldEnemy)

const MODEL_SCENE_PATH := "res://assets/models/enemies/Sputter/Sputter.glb"
const ENEMY_STATUS_SCENE_PATH := "res://battle/enemy_status.tscn"

@export var enemy_id: StringName = &"enemy"
@export var enemy_data: EnemyData
# The rules-side stats/move list battle_controller.gd builds this fight's
# Combatant from (see EnemyTurn) - FieldEnemy itself stays rules-ignorant,
# just a reference plus the field-visual/contact concerns below.
@export var contact_radius: float = 2.0
# Fallback only, for a model whose mesh ships with no material of its own
# to inherit (see _build_model_material()) - Sputter.glb carries its own
# real textured material, so this doesn't drive its look today the way it
# drove the old untextured placeholder's.
@export var model_color: Color = Color(0.2, 0.22, 0.25, 1)
@export var model_scale: float = 1.0
@export var model_yaw_offset: float = 0.0
@export var model_ground_offset: float = 0.0
@export var face_shore_at_spawn: bool = true
@export var region_field_path: NodePath = ^".."
@export var ground_path: NodePath = ^"../Ground"
@export_range(0.0, 1.0, 0.01) var highlight_lighten_amount: float = 0.35

# The forward-lunge-and-back this enemy's own attacks play in place of a
# clip (creatures have no animations to swing) - see play_attack_snap()'s
# own doc. Lives here, not on BattleFeedback, since it's this enemy's own
# attack-animation timing (the equivalent of CardData.battle_animation/
# impact_time for a card), not one of the reactive hit-feedback effects
# BattleFeedback owns the tunables for.
@export_group("Attack Snap")
@export var attack_snap_distance: float = 0.6
@export var attack_snap_out_time: float = 0.12
@export var attack_snap_return_time: float = 0.2

var _contacted: bool = false
# BaseMaterial3D, not StandardMaterial3D: Godot's glTF importer can produce
# either it or an ORMMaterial3D for a material with a combined metallic-
# roughness texture (both are BaseMaterial3D siblings, not one a subclass
# of the other) - albedo_color/roughness/metallic/*_texture are all
# BaseMaterial3D's own properties, so every read/write below works
# identically regardless of which concrete class _build_model_material()
# actually got handed.
var _model_material: BaseMaterial3D
# Captured once, right after _model_material is built - what set_highlight()/
# play_hit_flash() both return to at rest. Not the same thing as model_color:
# for the real Sputter.glb material this is whatever its own baseColorFactor
# actually is (white, so the real texture reads unmodified), only falling
# back to model_color when the mesh had no material of its own to inherit.
var _model_base_color: Color = Color.WHITE
var _ground: Ground = null
var _slash_mark_mesh: ArrayMesh = null
var _slash_mark_texture: GradientTexture2D = null

# Owned by this enemy, but lives in RegionField.field_hud, not here (a
# Control needs a CanvasLayer ancestor, not a Node3D one) - see _ready()'s
# own creation of it and add_enemy_status()'s doc on the other end.
# BattleOverlay reuses this exact instance rather than creating its own
# (see its own _create_enemy_statuses()); region_field.gd frees it
# explicitly on a WIN outcome, since freeing this node doesn't cascade to
# it the way freeing a real child would.
var enemy_status: EnemyStatus = null
# The model's scaled bounding-box height, from _spawn_model() - the
# creature's own head height above its ground position, for anything
# that anchors above it (BattleIntent). 0 until the model has spawned.
var _model_height: float = 0.0
# Half the model's larger horizontal bbox extent (X or Z), same source -
# how far the body reaches sideways from its ground position, for
# CameraRig's battle fit. 0 until the model has spawned.
var _model_half_width: float = 0.0
# The model's combined mesh AABB in this body's own space, as placed (the
# grounding shift applied) - what BattleController projects for the
# armed-card target test. Empty until the model has spawned.
var _model_aabb: AABB = AABB()

func get_head_height() -> float:
	return _model_height

func get_half_width() -> float:
	return _model_half_width

func get_model_aabb() -> AABB:
	return _model_aabb

# The model's world AABB as a screen rect: its 8 corners unprojected,
# bounded, grown by padding_px on every side - what a click or an armed
# card has to land in to mean this enemy (BattleController's target test
# and RegionField's point-to-move both use it). Empty when the model
# hasn't spawned or any corner is behind the camera.
func get_screen_rect(camera: Camera3D, padding_px: float) -> Rect2:
	if camera == null or _model_aabb.size == Vector3.ZERO:
		return Rect2()
	var rect := Rect2()
	for i in 8:
		var corner: Vector3 = global_transform * _model_aabb.get_endpoint(i)
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		rect = Rect2(point, Vector2.ZERO) if i == 0 else rect.expand(point)
	return rect.grow(padding_px)

@onready var contact_area: Area3D = $ContactArea
@onready var contact_shape: CollisionShape3D = $ContactArea/CollisionShape3D

func _ready() -> void:
	# RegionField's own freeze (PROCESS_MODE_DISABLED on contact) defaults
	# to removing every CollisionObject3D beneath it from the physics space
	# entirely (disable_mode's default, REMOVE) - which would make this
	# enemy un-raycastable for card targeting during the very battle that
	# freeze exists for. MAKE_STATIC keeps the body in space (immobile,
	# which it already effectively is once frozen) instead.
	disable_mode = CollisionObject3D.DISABLE_MODE_MAKE_STATIC

	var shape := SphereShape3D.new()
	shape.radius = contact_radius
	contact_shape.shape = shape

	contact_area.body_entered.connect(_on_body_entered)
	contact_area.body_exited.connect(_on_body_exited)

	_spawn_model()
	_spawn_enemy_status()

	if face_shore_at_spawn:
		_face_shore()

	var contact_shadow := ContactShadow.new()
	contact_shadow.name = "ContactShadow"
	add_child(contact_shadow)

	# relief_rebuilt covers every LIVE relief edit after this point, but its
	# very first emission happens inside Ground's own _ready() - before this
	# node could possibly have connected to it - so the initial grounding
	# still needs a manual call. Deferred a frame (rather than called
	# immediately) so it runs after RegionField's own _ready() has finished
	# repositioning this enemy along get_forward(), not before.
	_ground = get_node_or_null(ground_path) as Ground
	if _ground:
		_ground.relief_rebuilt.connect(_ground_to_relief)
		await get_tree().process_frame
		_ground_to_relief()

# Sits the body on the current terrain height at its own XZ, minus
# model_ground_offset - _spawn_model()'s own AABB grounding puts the
# model's feet at body-local Y = model_ground_offset, not Y = 0, so the
# body's global Y has to account for that for the feet (not the body
# origin) to land on the surface. Called once, deferred, from _ready()
# and again on every Ground.relief_rebuilt - see _ready()'s own comment
# for why both are needed.
func _ground_to_relief() -> void:
	if _ground == null:
		return
	var local_xz: Vector3 = _ground.to_local(Vector3(global_position.x, 0.0, global_position.z))
	global_position.y = _ground.get_height_at(Vector2(local_xz.x, local_xz.z)) - model_ground_offset

# get_forward() points inland (spawn -> Tower, see RegionField's own doc),
# so facing the shore/sea is the opposite direction. Yaws the body itself,
# not the model - model_yaw_offset above stays a separate, local correction
# for the imported asset's own facing.
func _face_shore() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		return
	var to_shore := -region_field.get_forward()
	if to_shore.length() < 0.0001:
		return
	# Same verified direction<->angle convention as face_toward() below and
	# Wanderer._angle_from_direction().
	rotation.y = atan2(-to_shore.x, -to_shore.z)

func _spawn_model() -> void:
	var model := (load(MODEL_SCENE_PATH) as PackedScene).instantiate() as Node3D
	add_child(model)
	model.scale = Vector3.ONE * model_scale
	model.rotation.y = deg_to_rad(model_yaw_offset)

	# Combined AABB of all mesh instances, expressed in this node's own
	# space (not the model's), so its bottom tells us how far to raise the
	# model regardless of the model's own pivot/rotation.
	var combined_aabb: AABB
	var has_aabb := false
	for mesh_instance in model.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh_instance as MeshInstance3D
		# One shared material across every mesh instance, built once from
		# whichever one is found first - matches Sputter.glb's own shape
		# (a single mesh/material today); if a future model ships more than
		# one, every instance still gets this same first material rather
		# than each keeping its own real one, same simplification the old
		# flat-color placeholder already made.
		if _model_material == null:
			_model_material = _build_model_material(mi)
			_model_base_color = _model_material.albedo_color
		mi.material_override = _model_material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

		var mi_transform_in_self := global_transform.affine_inverse() * mi.global_transform
		var mi_aabb_in_self := mi_transform_in_self * mi.get_aabb()
		combined_aabb = mi_aabb_in_self if not has_aabb else combined_aabb.merge(mi_aabb_in_self)
		has_aabb = true

	if has_aabb:
		print("FieldEnemy '%s': model AABB height = %.3f at model_scale = %.3f" % [enemy_id, combined_aabb.size.y, model_scale])
		var grounding_shift: float = -combined_aabb.position.y + model_ground_offset
		model.position.y += grounding_shift
		_model_height = combined_aabb.size.y
		_model_half_width = maxf(combined_aabb.size.x, combined_aabb.size.z) * 0.5
		_model_aabb = AABB(combined_aabb.position + Vector3(0.0, grounding_shift, 0.0), combined_aabb.size)

# Duplicates the mesh's own imported material (Sputter.glb ships a real
# baseColorTexture/metallicRoughnessTexture/normalTexture set) rather than
# replacing it with a flat model_color fill - duplicated so each enemy
# instance gets its own mutable copy set_highlight()/play_hit_flash() can
# tween directly, since a shared Material resource would leak those
# mutations onto every other enemy using the same imported mesh. roughness/
# metallic are forced to this project's own matte convention (every other
# surface here sets roughness=1, no specular/metallic - see Wanderer's own
# material builders) rather than left at whatever PBR values the import
# carried (Sputter.glb's own metallicFactor is 1.0, fully metallic, which
# would read as shiny/reflective against everything else in the game); the
# metallic/roughness texture map is cleared too so that forced scalar
# actually holds instead of being modulated per-pixel by a texture built
# for the original PBR values. Falls back to a flat model_color fill only
# if the mesh ships with no material of its own to inherit at all - same
# "degrade to a solid color rather than render wrong" shape Wanderer's own
# _build_textured_material() uses.
func _build_model_material(mesh_instance: MeshInstance3D) -> BaseMaterial3D:
	var source_material := mesh_instance.get_active_material(0)
	var material: BaseMaterial3D
	if source_material is BaseMaterial3D:
		material = (source_material as BaseMaterial3D).duplicate()
	else:
		material = StandardMaterial3D.new()
		material.albedo_color = model_color
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	material.metallic_texture = null
	material.roughness_texture = null
	return material

# Creates this enemy's own persistent HP display and hands it to RegionField
# to parent (see enemy_status's own doc on why - a Control needs a
# CanvasLayer ancestor, not this Node3D). Seeded at full HP so it reads
# correctly in the field, before any battle has ever touched this enemy;
# BattleController.setup()'s own initial enemy_hp_changed emit re-seeds it
# identically the instant a fight actually starts (see EnemyStatus.update_
# hp()'s own doc on why that reseed doesn't trigger a spurious reveal).
func _spawn_enemy_status() -> void:
	var region_field := get_node_or_null(region_field_path) as RegionField
	if region_field == null:
		push_warning("FieldEnemy '%s': region_field_path did not resolve to a RegionField; no HP display." % enemy_id)
		return

	var status := (load(ENEMY_STATUS_SCENE_PATH) as PackedScene).instantiate() as EnemyStatus
	region_field.add_enemy_status(status)
	status.set_target(self)
	var max_hp: int = enemy_data.max_hp if enemy_data != null else 1
	status.update_hp(max_hp, max_hp)
	enemy_status = status

# Called by BattleController while this enemy is the hovered raycast target
# during card targeting. Brightness lift via albedo only, no emission - a
# hover cue, not a glow effect.
func set_highlight(on: bool) -> void:
	if _model_material == null:
		return
	_model_material.albedo_color = _model_base_color.lightened(highlight_lighten_amount) if on else _model_base_color

# Called by BattleFeedback once BattleController reports a card hit
# landing on this enemy - lerps this enemy's own material albedo up to
# flash_color over rise_time, then back down to _model_base_color over
# fall_time. All-color parameters (not exports here): BattleFeedback owns
# the actual tunables for this and every other reactive hit-feedback
# effect (see its own doc) - this method is only the mechanism.
func play_hit_flash(flash_color: Color, rise_time: float, fall_time: float) -> void:
	if _model_material == null:
		return
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(_model_material, "albedo_color", flash_color, rise_time)
	tween.tween_property(_model_material, "albedo_color", _model_base_color, fall_time)

# from_direction is the direction the hit traveled (attacker -> this
# enemy, not normalized) - this recoils further along that same line,
# away from the attacker, and tilts back the same amount before easing
# back to rest. TRANS_BACK on the return leg is what gives it its own
# small overshoot past rest rather than a plain ease-in stop.
func play_hit_recoil(from_direction: Vector3, distance: float, tilt_degrees: float, out_time: float, return_time: float) -> void:
	var away := Vector3(from_direction.x, 0.0, from_direction.z)
	away = away.normalized() if away.length() > 0.0001 else Vector3.BACK

	var base_position := global_position
	var base_tilt := rotation.x
	var recoil_position := base_position + away * distance
	var recoil_tilt := base_tilt + deg_to_rad(tilt_degrees)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", recoil_position, out_time)
	tween.parallel().tween_property(self, "rotation:x", recoil_tilt, out_time)
	tween.chain().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", base_position, return_time)
	tween.parallel().tween_property(self, "rotation:x", base_tilt, return_time)

# A thin, unshaded, no-texture quad hanging at this enemy's own chest
# height, oriented so its local X axis (the one that actually gets
# scaled/animated) runs along from_direction (attacker -> this enemy,
# flattened) and its local Y axis runs along world UP - built via
# SurfaceTool rather than PlaneMesh/QuadMesh specifically so those two
# axes land exactly where named, not wherever either primitive's own
# default facing happens to put them (see ContactShadow's own doc on why
# QuadMesh's default facing wasn't trusted here either). Grows along X
# from ~0 to length over grow_time while fading its own alpha to 0 over
# fade_time, then frees itself - whichever of the two takes longer is
# what the mesh actually lives for.
func spawn_slash_mark(from_direction: Vector3, color: Color, length: float, width: float, chest_height: float, grow_time: float, fade_time: float) -> void:
	var attack_dir := Vector3(from_direction.x, 0.0, from_direction.z)
	attack_dir = attack_dir.normalized() if attack_dir.length() > 0.0001 else Vector3.FORWARD

	if _slash_mark_mesh == null:
		_slash_mark_mesh = _build_slash_quad_mesh()
	if _slash_mark_texture == null:
		_slash_mark_texture = _build_slash_gradient_texture()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _slash_mark_mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_texture = _slash_mark_texture
	material.albedo_color = color
	material.disable_receive_shadows = true
	mesh_instance.material_override = material

	var x_axis := attack_dir
	var y_axis := Vector3.UP
	var z_axis := x_axis.cross(y_axis).normalized()
	var mark_basis := Basis(x_axis, y_axis, z_axis)

	add_child(mesh_instance)
	mesh_instance.global_transform = Transform3D(mark_basis, global_position + Vector3.UP * chest_height)
	mesh_instance.scale = Vector3(0.001, width, 1.0)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(true)
	tween.tween_property(mesh_instance, "scale:x", length, grow_time)
	tween.tween_property(material, "albedo_color:a", 0.0, fade_time)
	tween.chain().tween_callback(mesh_instance.queue_free)

# A vertical-normal, XY-plane unit quad (X/Y each -0.5..0.5, normal +Z),
# built directly rather than relying on PlaneMesh/QuadMesh's own default
# facing - see spawn_slash_mark()'s own doc on why. UVs run 0..1 across
# both axes so _build_slash_gradient_texture()'s vertical gradient reads
# top-to-bottom regardless of how this quad is later scaled/oriented.
func _build_slash_quad_mesh() -> ArrayMesh:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_normal(Vector3(0.0, 0.0, 1.0))
	surface_tool.set_uv(Vector2(0.0, 1.0))
	surface_tool.add_vertex(Vector3(-0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 1.0))
	surface_tool.add_vertex(Vector3(0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 0.0))
	surface_tool.add_vertex(Vector3(0.5, 0.5, 0.0))
	surface_tool.set_uv(Vector2(0.0, 1.0))
	surface_tool.add_vertex(Vector3(-0.5, -0.5, 0.0))
	surface_tool.set_uv(Vector2(1.0, 0.0))
	surface_tool.add_vertex(Vector3(0.5, 0.5, 0.0))
	surface_tool.set_uv(Vector2(0.0, 0.0))
	surface_tool.add_vertex(Vector3(-0.5, 0.5, 0.0))
	return surface_tool.commit()

# Transparent -> opaque -> transparent along V (top to bottom, per
# spawn_slash_mark()'s own UVs) - the "vertical alpha gradient" the mark
# needs so its top/bottom edges read as soft rather than a hard-edged
# rectangle. 8px wide is enough since it's stretched uniformly across the
# mark's own fixed width, not sampled per-pixel-detail.
func _build_slash_gradient_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 0.0),
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 8
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	return texture

# A one-shot puff of flat, unshaded, no-texture quads in the ground's own
# color, kicked gently upward and outward from this enemy's own feet -
# same "read Ground.ground_color at the actual spawn point" source
# FootprintSpawner's footprints already use. process_mode is forced to
# ALWAYS since GPUParticles3D drives its own simulation per-frame (same
# reasoning as ContactShadow/the Wanderer's model needing it during
# RegionField's battle freeze) - a plain MeshInstance3D driven only by a
# Tween (see spawn_slash_mark()) doesn't need this, but this node's own
# advancement isn't a Tween.
func spawn_sand_puff(particle_count: int, lifetime: float, velocity: float, spread_degrees: float) -> void:
	if _ground == null:
		return

	var particles := GPUParticles3D.new()
	particles.process_mode = Node.PROCESS_MODE_ALWAYS
	particles.emitting = false
	particles.one_shot = true
	particles.amount = particle_count
	particles.lifetime = lifetime
	particles.explosiveness = 1.0

	var quad_mesh := QuadMesh.new()
	quad_mesh.size = Vector2(0.12, 0.12)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = _ground.ground_color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad_mesh.material = material
	particles.draw_pass_1 = quad_mesh

	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3(0.0, 1.0, 0.0)
	process_material.spread = spread_degrees
	process_material.initial_velocity_min = velocity * 0.5
	process_material.initial_velocity_max = velocity
	process_material.gravity = Vector3(0.0, -2.0, 0.0)
	process_material.scale_min = 0.6
	process_material.scale_max = 1.2
	particles.process_material = process_material

	add_child(particles)
	particles.global_position = global_position
	particles.emitting = true
	get_tree().create_timer(lifetime + 0.1).timeout.connect(particles.queue_free)

# Creatures have no clips to swing (unlike a card's own battle_animation),
# so this is their equivalent: a short lunge toward target and back,
# TWEEN_PAUSE_PROCESS'd through RegionField's own battle freeze same as
# every other in-battle tween here. Returns attack_snap_out_time - the
# point in the lunge BattleController._run_enemy_turn() awaits before
# reporting the hit - rather than the tween's own total duration, since
# the return leg keeps playing (cosmetically) after the hit has already
# landed.
func play_attack_snap(target: Node3D) -> float:
	if target == null:
		return 0.0

	var direction := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	direction = direction.normalized() if direction.length() > 0.0001 else -global_transform.basis.z

	var base_position := global_position
	var lunge_position := base_position + direction * attack_snap_distance

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "global_position", lunge_position, attack_snap_out_time)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "global_position", base_position, attack_snap_return_time)

	return attack_snap_out_time

# Called by region_field.gd on contact. Yaws to face target over duration,
# taking the short way around. RegionField's contact freeze stops nothing
# here (FieldEnemy has no _physics_process), but the tween still needs
# TWEEN_PAUSE_PROCESS to play through it, same as Wanderer.enter_battle_stance().
#
# Rotation only, deliberately - unlike Wanderer.enter_battle_stance(), this
# never repositions the enemy (contact happens wherever the enemy already
# stands), and its Y stays correct on its own via _ground_to_relief() (see
# _ready()/Ground.relief_rebuilt) regardless of when battle starts, so
# nothing here needs to re-sample terrain height itself.
func face_toward(target: Node3D, duration: float) -> void:
	if target == null:
		return

	var to_target := Vector3(target.global_position.x - global_position.x, 0.0, target.global_position.z - global_position.z)
	if to_target.length() < 0.0001:
		return

	# Same verified direction<->angle convention as Wanderer._angle_from_
	# direction()/_forward_from_angle().
	var face_angle := atan2(-to_target.x, -to_target.z)
	var target_angle := rotation.y + wrapf(face_angle - rotation.y, -PI, PI)

	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", target_angle, duration)

func _on_body_entered(body: Node3D) -> void:
	if _contacted or not body.is_in_group("wanderer"):
		return
	_contacted = true
	contacted.emit(self)

# Reset the once-only guard when the Wanderer leaves, so a return visit
# (e.g. after an ESCAPE push-back) can trigger contact again.
func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_contacted = false
