extends Node3D
class_name DragonflyWings

# Four flat wing quads (front L/R, hind L/R) for the dragonfly body -
# the attachment EnemyData.attachment_scene_path names, instantiated by
# FieldEnemy under the MODEL root after its material pass (see
# FieldEnemy._attach_scene()), so the wings keep their own textured
# materials while riding the body's grounding, yaw, scale and settle.
#
# Each quad is a unit plane in this node's own space: local X the span
# (root at 0, tip at +1), local Z the chord (the leading edge toward +Z,
# the body's own head direction), normal +Y - built once with
# SurfaceTool so those axes are exactly what they say (see FieldEnemy's
# slash quad for the same reasoning). The left pair is the same mesh at
# a negative X scale. The texture's left edge is the wing root, its top
# edge the leading edge; leading_fraction says how much of the chord the
# texture puts ahead of the root's centre row.
#
# Every size is in METRES: this node sits under the model root, which
# FieldEnemy scales by model_scale, so each value is divided by the
# parent's scale on the way in (see _unit()) and reads as a world size in
# the Inspector. Every export re-applies live (the four quads are made
# once, in _ready(); the setters only move/resize them), and the two
# materials - one per pair, both sides of a pair share it - are made once
# and handed to FieldEnemy for its highlight and hit flash (see
# get_tint_materials()), so a live edit never leaves it holding a freed
# material.
#
# Motion, all procedural, all about the root hinge (the dihedral axis:
# tips up and down, the body never moves):
#   Rest quiver  - a small slow wobble, quiver_degrees at quiver_hz, each
#                  wing on its own phase, the hind pair offset, left and
#                  right mirrored; a second, slower sine scales it so it
#                  breathes rather than ticks. Ramps in from rest over
#                  quiver_settle_seconds so nothing pops at spawn.
#   Attack flap  - start_flap(), from FieldEnemy.play_attack_snap(): a
#                  beat of flap_degrees at flap_hz for flap_seconds, then
#                  the quiver takes back over flap_release_seconds.
#   Death fold   - fold(seconds), from FieldEnemy.settle_and_free(): the
#                  quiver stops and the dihedral eases to fold_degrees
#                  (tips down) over the settle; the body sinks after.
# Runs in _process at PROCESS_MODE_ALWAYS - through the field's freeze
# for a fight and for the reward screen alike, the way the Wanderer's
# own idle does (see Wanderer's model process_mode).
#
# Shaded, not unshaded: the body is lit by the overcast light and
# shadowed, and a membrane that ignored both would read as a pasted
# cut-out from the field camera. Alpha scissor, not alpha blend: it
# sorts against the body and the sea without fuss and casts a cut-out
# shadow. Both faces drawn (cull off) - a wing is seen from below as
# often as from above.

@export_group("Textures")
@export_file("*.png") var front_texture_path: String = "res://assets/textures/enemies/dragonfly_wing_front.png":
	set(value):
		front_texture_path = value
		_apply_textures()
@export_file("*.png") var hind_texture_path: String = "res://assets/textures/enemies/dragonfly_wing_hind.png":
	set(value):
		hind_texture_path = value
		_apply_textures()
# Alpha at or below this is cut away.
@export_range(0.0, 1.0, 0.01) var alpha_scissor_threshold: float = 0.5:
	set(value):
		alpha_scissor_threshold = value
		_apply_textures()

@export_group("Placement")
# Metres ahead of the model's origin along its own head direction (+Z
# in the glb) - the thorax, where the wings root.
@export var attach_forward: float = 0.145:
	set(value):
		attach_forward = value
		_apply_layout()
# Metres above the model's origin - the top of the thorax.
@export var attach_height: float = 0.026:
	set(value):
		attach_height = value
		_apply_layout()
# The hind pair roots this far behind the front pair.
@export var hind_offset: float = 0.03:
	set(value):
		hind_offset = value
		_apply_layout()

@export_group("Shape")
# Root to tip, per wing, metres - the root sits on the body's centre
# line, so the whole span is twice this: 1.0 m at the body's 0.55.
@export var span: float = 0.5:
	set(value):
		span = value
		_apply_layout()
# Leading edge to trailing edge, metres.
@export var chord: float = 0.19:
	set(value):
		chord = value
		_apply_layout()
# The part of the chord ahead of the root's centre line - from the
# texture (its root centre row over its height).
@export_range(0.0, 1.0, 0.005) var leading_fraction: float = 0.435:
	set(value):
		leading_fraction = value
		_apply_layout()
# Hind pair size, as a factor of the front pair.
@export var hind_scale: float = 0.9:
	set(value):
		hind_scale = value
		_apply_layout()

@export_group("Pose")
# Tips back toward the tail, degrees. 0 = straight out, perpendicular to
# the body; the reference drawing holds them at about 42.
@export var sweep_degrees: float = 0.0:
	set(value):
		sweep_degrees = value
		_apply_layout()
# Tips up, degrees. 0 = flat.
@export var dihedral_degrees: float = 0.0:
	set(value):
		dihedral_degrees = value
		_apply_layout()

@export_group("Quiver")
# Every value here is read each frame, so an edit takes at once.
@export var quiver_degrees: float = 3.0
@export var quiver_hz: float = 0.6
# The slower sine that scales the quiver between (1 - depth) and 1.
@export var quiver_breath_hz: float = 0.13
@export_range(0.0, 1.0, 0.01) var quiver_breath_depth: float = 0.4
# The hind pair runs this far behind the front pair, in degrees of the
# quiver's own cycle.
@export var hind_phase_degrees: float = 40.0
# From rest to full quiver after spawn, seconds - zero at t = 0.
@export var quiver_settle_seconds: float = 1.0

@export_group("Flap")
@export var flap_degrees: float = 25.0
@export var flap_hz: float = 14.0
@export var flap_seconds: float = 0.35
# The flap hands back to the quiver over this, after flap_seconds.
@export var flap_release_seconds: float = 0.2

@export_group("Flight")
# The beat while airborne (FieldEnemy.fly_to() -> set_airborne()), at
# the flap's amplitude: slower than the attack's beat, steady until the
# landing, which releases into the quiver like an attack does.
@export var flight_flap_hz: float = 8.0

@export_group("Fold")
# Where the tips go on death, degrees of dihedral (negative = down).
@export var fold_degrees: float = -60.0

# [front right, front left, hind right, hind left]
var _quads: Array[MeshInstance3D] = []
var _front_material: StandardMaterial3D = null
var _hind_material: StandardMaterial3D = null
var _mesh: ArrayMesh = null
var _ready_done: bool = false
# Seconds since spawn - the quiver's clock.
var _time: float = 0.0
# The flap: seconds since start_flap() (negative = none running) and the
# angle it last held, which the release eases away from.
var _flap_elapsed: float = -1.0
var _flap_last_angle: float = 0.0
# The fold: 0 = the authored dihedral, 1 = fold_degrees; tweened by
# fold(). Once folding, the quiver and flap are over.
var _fold_blend: float = 0.0
var _folding: bool = false
var _fold_tween: Tween = null
# In the air: the steady flight beat replaces quiver and flap.
var _airborne: bool = false
# Per-quad phase offsets for the quiver, degrees, fixed at _ready() so
# the four never line up: [front right, front left, hind right, hind
# left] - the pairs share a phase (mirrored by `side` in the layout), the
# hind pair sits hind_phase_degrees behind.
var _phases: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _breath_phases: Array[float] = [0.0, 0.0, 0.0, 0.0]

func _ready() -> void:
	_front_material = _build_material()
	_hind_material = _build_material()
	for index in 4:
		var quad := MeshInstance3D.new()
		quad.name = ["FrontRight", "FrontLeft", "HindRight", "HindLeft"][index]
		quad.material_override = _front_material if index < 2 else _hind_material
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(quad)
		_quads.append(quad)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_phases = [0.0, 0.0, hind_phase_degrees, hind_phase_degrees]
	# The breath's own offsets are fixed, not authored: a right/left pair
	# breathes together, the hind pair a quarter turn on.
	_breath_phases = [0.0, 0.0, 90.0, 90.0]
	_ready_done = true
	_apply_textures()
	_apply_layout()

func _process(delta: float) -> void:
	if not _ready_done or _folding:
		return
	_time += delta
	if _flap_elapsed >= 0.0:
		_flap_elapsed += delta
		if _flap_elapsed > flap_seconds + flap_release_seconds:
			_flap_elapsed = -1.0
	_apply_transforms()

# The rest quiver's angle for one quad right now, degrees.
func _quiver_angle(index: int) -> float:
	var settle: float = 1.0 if quiver_settle_seconds <= 0.0 else clampf(_time / quiver_settle_seconds, 0.0, 1.0)
	settle = smoothstep(0.0, 1.0, settle)
	var base: float = sin(TAU * quiver_hz * _time + deg_to_rad(_phases[index]))
	var breath: float = 1.0 - quiver_breath_depth * 0.5 * (1.0 - sin(TAU * quiver_breath_hz * _time + deg_to_rad(_breath_phases[index])))
	return quiver_degrees * base * breath * settle

# The hinge angle a quad adds to the authored dihedral right now: the
# flap while it beats, its last angle easing into the quiver over the
# release, the quiver alone otherwise.
func _motion_angle(index: int) -> float:
	var quiver: float = _quiver_angle(index)
	if _airborne:
		_flap_last_angle = flap_degrees * sin(TAU * flight_flap_hz * _time)
		return _flap_last_angle
	if _flap_elapsed < 0.0:
		return quiver
	if _flap_elapsed <= flap_seconds:
		_flap_last_angle = flap_degrees * sin(TAU * flap_hz * _flap_elapsed)
		return _flap_last_angle
	var release: float = 1.0 if flap_release_seconds <= 0.0 else clampf((_flap_elapsed - flap_seconds) / flap_release_seconds, 0.0, 1.0)
	return lerpf(_flap_last_angle, quiver, smoothstep(0.0, 1.0, release))

# The attack beat - called by FieldEnemy.play_attack_snap() as the lunge
# starts. A beat already running restarts.
func start_flap() -> void:
	if _folding:
		return
	_flap_elapsed = 0.0

# Take-off and landing, from the body's own flight (FieldEnemy.fly_to()
# / _on_landed() / land_now()). Landing hands the last beat angle to the
# flap's release, so the wings ease into the quiver rather than snap.
func set_airborne(on: bool) -> void:
	if _folding or on == _airborne:
		return
	_airborne = on
	_flap_elapsed = -1.0 if on else flap_seconds

# Death: the quiver and any flap stop where they are and the dihedral
# eases to fold_degrees over `seconds` (FieldEnemy's settle_time) -
# through the battle freeze like every tween here. The body sinks after
# this has run (see FieldEnemy.settle_and_free()).
func fold(seconds: float) -> void:
	if _folding:
		return
	_folding = true
	if _fold_tween != null and _fold_tween.is_valid():
		_fold_tween.kill()
	if seconds <= 0.0:
		_set_fold_blend(1.0)
		return
	_fold_tween = create_tween()
	_fold_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fold_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fold_tween.tween_method(_set_fold_blend, _fold_blend, 1.0, seconds)

func _set_fold_blend(blend: float) -> void:
	_fold_blend = clampf(blend, 0.0, 1.0)
	_apply_transforms()

# The materials the body's highlight and hit flash tint alongside its
# own - see FieldEnemy._attach_scene().
func get_tint_materials() -> Array[BaseMaterial3D]:
	var materials: Array[BaseMaterial3D] = []
	if _front_material != null:
		materials.append(_front_material)
	if _hind_material != null:
		materials.append(_hind_material)
	return materials

func _build_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The project's matte convention - see FieldEnemy._build_model_
	# material().
	material.roughness = 1.0
	material.metallic = 0.0
	material.metallic_specular = 0.0
	return material

func _apply_textures() -> void:
	if not _ready_done:
		return
	_front_material.albedo_texture = _load_texture(front_texture_path)
	_front_material.alpha_scissor_threshold = alpha_scissor_threshold
	_hind_material.albedo_texture = _load_texture(hind_texture_path)
	_hind_material.alpha_scissor_threshold = alpha_scissor_threshold

func _load_texture(path: String) -> Texture2D:
	var texture := load(path) as Texture2D
	if texture == null:
		push_warning("DragonflyWings: wing texture failed to load (%s); the quad draws untextured." % path)
	return texture

# Metres per unit of this node's space: the model root above is scaled
# by FieldEnemy.model_scale, so a metre here is 1 / that.
func _unit() -> float:
	var parent := get_parent() as Node3D
	var parent_scale: float = parent.scale.x if parent != null else 1.0
	return 1.0 / maxf(parent_scale, 0.0001)

# The shape changed: rebuild the unit quad, then place the four.
func _apply_layout() -> void:
	if not _ready_done:
		return
	_mesh = _build_unit_quad(leading_fraction)
	_apply_transforms()

# Places the four quads for this frame - the authored pose plus the
# motion. Per frame from _process(); the mesh itself only changes with
# the shape (see _apply_layout()).
func _apply_transforms() -> void:
	if not _ready_done:
		return
	var unit: float = _unit()
	var sweep: float = deg_to_rad(sweep_degrees)
	# The resting dihedral, or the fold once dying - and on top of it,
	# per quad, whatever the quiver or flap adds right now.
	var rest_dihedral: float = lerpf(dihedral_degrees, fold_degrees, _fold_blend)
	for index in _quads.size():
		var quad := _quads[index]
		quad.mesh = _mesh
		var hind: bool = index >= 2
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var size_factor: float = hind_scale if hind else 1.0
		var forward: float = attach_forward - (hind_offset if hind else 0.0)
		var origin := Vector3(0.0, attach_height, forward) * unit
		var motion: float = 0.0 if _folding else _motion_angle(index)
		var dihedral: float = deg_to_rad(rest_dihedral + motion)
		# Sweep about UP takes the right tip (+X) toward the tail (-Z)
		# for a positive angle; the left tip (-X) needs the opposite
		# turn. Dihedral about the body axis the same way - which is also
		# what mirrors the quiver and the flap left to right.
		var basis := Basis.IDENTITY.rotated(Vector3.UP, side * sweep).rotated(Vector3.BACK, side * dihedral)
		var extent := Vector3(side * span * size_factor, 1.0, chord * size_factor) * unit
		quad.transform = Transform3D(basis, origin).scaled_local(extent)

# The unit wing: X 0..1 root to tip, Z from +leading to -(1 - leading)
# across the chord, normal +Y; UV u along the span, v down the chord
# from the leading edge - the texture's own layout.
func _build_unit_quad(leading: float) -> ArrayMesh:
	var z_lead: float = leading
	var z_trail: float = -(1.0 - leading)
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface_tool.set_normal(Vector3.UP)
	surface_tool.set_uv(Vector2(0.0, 0.0))
	surface_tool.add_vertex(Vector3(0.0, 0.0, z_lead))
	surface_tool.set_uv(Vector2(1.0, 0.0))
	surface_tool.add_vertex(Vector3(1.0, 0.0, z_lead))
	surface_tool.set_uv(Vector2(1.0, 1.0))
	surface_tool.add_vertex(Vector3(1.0, 0.0, z_trail))
	surface_tool.set_uv(Vector2(0.0, 0.0))
	surface_tool.add_vertex(Vector3(0.0, 0.0, z_lead))
	surface_tool.set_uv(Vector2(1.0, 1.0))
	surface_tool.add_vertex(Vector3(1.0, 0.0, z_trail))
	surface_tool.set_uv(Vector2(0.0, 1.0))
	surface_tool.add_vertex(Vector3(0.0, 0.0, z_trail))
	return surface_tool.commit()
