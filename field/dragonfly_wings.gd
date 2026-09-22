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

# [front right, front left, hind right, hind left]
var _quads: Array[MeshInstance3D] = []
var _front_material: StandardMaterial3D = null
var _hind_material: StandardMaterial3D = null
var _mesh: ArrayMesh = null
var _ready_done: bool = false

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
	_ready_done = true
	_apply_textures()
	_apply_layout()

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

func _apply_layout() -> void:
	if not _ready_done:
		return
	_mesh = _build_unit_quad(leading_fraction)
	var unit: float = _unit()
	var sweep: float = deg_to_rad(sweep_degrees)
	var dihedral: float = deg_to_rad(dihedral_degrees)
	for index in _quads.size():
		var quad := _quads[index]
		quad.mesh = _mesh
		var hind: bool = index >= 2
		var side: float = 1.0 if index % 2 == 0 else -1.0
		var size_factor: float = hind_scale if hind else 1.0
		var forward: float = attach_forward - (hind_offset if hind else 0.0)
		var origin := Vector3(0.0, attach_height, forward) * unit
		# Sweep about UP takes the right tip (+X) toward the tail (-Z)
		# for a positive angle; the left tip (-X) needs the opposite
		# turn. Dihedral about the body axis the same way.
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
