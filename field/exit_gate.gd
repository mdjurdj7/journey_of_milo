extends Node3D
class_name ExitGate

# Floor-exit prototype (see region_field.gd's own doc on the floor_cleared/
# floor_exited handshake). RegionField positions and orients this node
# itself - see RegionField._setup_exit_gate()'s own doc for why this can't
# compute its own placement from its _ready(), the same ordering constraint
# FieldEnemy's own doc describes for get_forward(). Every export below is
# baked into a mesh/shape once in _ready(); each one that affects a built
# shape gets a setter so a Remote-tab edit rebuilds it live, same pattern
# as contact_shadow.gd's radius/shadow_opacity.

signal floor_exited

@export var gap_width: float = 3.0:
	set(value):
		gap_width = value
		_rebuild()
@export var block_width: float = 2.0:
	set(value):
		block_width = value
		_rebuild()
@export var block_height: float = 1.4:
	set(value):
		block_height = value
		_rebuild()
@export var block_depth: float = 3.0:
	set(value):
		block_depth = value
		_rebuild()
@export var block_color: Color = Color(0.62, 0.58, 0.46, 1):
	set(value):
		block_color = value
		_rebuild()
@export var strip_height: float = 0.15:
	set(value):
		strip_height = value
		_rebuild()
# Runs from the gate line toward the berm - 2.5 (with the trigger's own
# offset/size below) stays comfortably inside the ~4m this scene's current
# field_extents/wall_thickness leave between the gate line and the inland
# wall - see RegionField.exit_gate_distance_beyond_enemy's own doc for that
# arithmetic.
@export var strip_depth: float = 2.5:
	set(value):
		strip_depth = value
		_rebuild()
@export var strip_color: Color = Color(0.75, 0.73, 0.66, 1):
	set(value):
		strip_color = value
		_rebuild()
# Read live at open() time, not baked into anything at _ready() - no
# setter needed, same reasoning as contact_shadow.gd's height_offset.
@export var strip_open_color: Color = Color(0.92, 0.9, 0.85, 1)
# The thin dark "physical no" bar across the gap at knee height while
# closed - see open()'s own doc on what happens to it.
@export var bar_height_offset: float = 0.5:
	set(value):
		bar_height_offset = value
		_rebuild()
@export var bar_thickness: float = 0.1:
	set(value):
		bar_thickness = value
		_rebuild()
@export var bar_depth: float = 0.15:
	set(value):
		bar_depth = value
		_rebuild()
@export var bar_color: Color = Color(0.15, 0.13, 0.11, 1):
	set(value):
		bar_color = value
		_rebuild()
# Read live at open() time only - no setter needed, same as bar_sink_depth
# below and strip_open_color above.
@export var bar_sink_depth: float = 0.4
@export var open_transition_time: float = 1.0
@export var trigger_forward_offset: float = 2.0:
	set(value):
		trigger_forward_offset = value
		_rebuild()
@export var trigger_size: Vector3 = Vector3(4.0, 3.0, 2.0):
	set(value):
		trigger_size = value
		_rebuild()
# BlockContactArea is padded this much larger than the physical blocker on
# every axis (see _build_blocker()'s own doc) - sized exactly to the
# blocker's own footprint, a Wanderer capsule grazing the solid collision
# might not overlap the Area3D enough to reliably fire body_entered at the
# same moment. FieldEnemy's own ContactArea sphere is deliberately larger
# than its physical capsule for the same reason.
@export var block_contact_padding: float = 0.3:
	set(value):
		block_contact_padding = value
		_rebuild()

var _strip_material: StandardMaterial3D = null
# Guards _rebuild() against running off an export's default-value setter
# firing before _ready() has resolved the @onready node references above -
# not is_node_ready() (its return value during this node's own _ready() is
# not something this project has verified), just an explicit flag set at
# the end of _ready().
var _ready_done: bool = false
var _open: bool = false
# Reset on exit so a Wanderer who backs off and walks into the still-closed
# blocker again gets warned again - same reset-on-exit shape FieldEnemy's
# own _contacted flag uses.
var _blocker_contact_active: bool = false

@onready var left_block: MeshInstance3D = $LeftBlock
@onready var right_block: MeshInstance3D = $RightBlock
@onready var strip: MeshInstance3D = $Strip
@onready var bar: MeshInstance3D = $Bar
@onready var blocker: StaticBody3D = $Blocker
@onready var blocker_shape: CollisionShape3D = $Blocker/CollisionShape3D
@onready var trigger_area: Area3D = $TriggerArea
@onready var trigger_shape: CollisionShape3D = $TriggerArea/CollisionShape3D
@onready var block_contact_area: Area3D = $BlockContactArea
@onready var block_contact_shape: CollisionShape3D = $BlockContactArea/CollisionShape3D

func _ready() -> void:
	trigger_area.body_entered.connect(_on_trigger_body_entered)
	block_contact_area.body_entered.connect(_on_block_contact_entered)
	block_contact_area.body_exited.connect(_on_block_contact_exited)
	_ready_done = true
	_rebuild()
	print("ExitGate: closed")

# Every exported dimension/color above lands here rather than each having
# its own narrow _apply_*() - the block/strip/blocker shapes all share
# gap_width and block_height, so splitting this up would just mean most
# setters call two or three functions instead of one. Cheap enough
# (a handful of small meshes/shapes) that rebuilding the lot on any single
# edit isn't worth avoiding.
func _rebuild() -> void:
	if not _ready_done:
		return
	_build_blocks()
	_build_strip()
	_build_bar()
	_build_blocker()
	_build_trigger()

func _build_blocks() -> void:
	var half_gap := gap_width / 2.0
	var half_block := block_width / 2.0
	_apply_block(left_block, Vector3(-(half_gap + half_block), block_height / 2.0, 0.0))
	_apply_block(right_block, Vector3(half_gap + half_block, block_height / 2.0, 0.0))

func _apply_block(block: MeshInstance3D, block_position: Vector3) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(block_width, block_height, block_depth)
	var material := StandardMaterial3D.new()
	material.albedo_color = block_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	mesh.material = material
	block.mesh = mesh
	block.position = block_position

# The strip is the visible stand-in for the gap the Blocker actually
# blocks - see open()'s own doc on why its material is kept as a separate
# mutable instance rather than shared/duplicated per rebuild.
func _build_strip() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(gap_width, strip_height, strip_depth)
	_strip_material = StandardMaterial3D.new()
	_strip_material.albedo_color = strip_color
	_strip_material.roughness = 1.0
	_strip_material.metallic_specular = 0.0
	mesh.material = _strip_material
	strip.mesh = mesh
	strip.position = Vector3(0.0, strip_height / 2.0, 0.0)

# The visible "physical no" while closed - see open()'s own doc on what
# happens to it. Sits at knee height, a separate element from the
# ground-level strip so the two can read independently (a barrier you'd
# actually catch your shin on, above a runway that's merely tinted).
func _build_bar() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(gap_width, bar_thickness, bar_depth)
	var material := StandardMaterial3D.new()
	material.albedo_color = bar_color
	material.roughness = 1.0
	material.metallic_specular = 0.0
	mesh.material = material
	bar.mesh = mesh
	bar.position = Vector3(0.0, bar_height_offset, 0.0)

# Sized/positioned to exactly cover the strip's footprint (not the whole
# gate) - the dune blocks flanking it are permanent, only the gap itself
# ever opens. BlockContactArea shares this exact footprint so "the Wanderer
# hit the blocker" (see _on_block_contact_entered()) means what it says,
# rather than some looser approximation of it.
func _build_blocker() -> void:
	var footprint := Vector3(gap_width, block_height, strip_depth)

	var shape := BoxShape3D.new()
	shape.size = footprint
	blocker_shape.shape = shape
	blocker.position = Vector3(0.0, block_height / 2.0, 0.0)

	var contact_shape := BoxShape3D.new()
	contact_shape.size = footprint + Vector3.ONE * block_contact_padding
	block_contact_shape.shape = contact_shape
	block_contact_area.position = blocker.position

# Sits trigger_forward_offset further along local -Z than the gate line -
# local -Z is "forward"/inland here, the same rotation.y = atan2(-dir.x,
# -dir.z) convention RegionField._setup_exit_gate() uses to orient this
# whole node, and the one face_toward()/_face_shore() already established
# elsewhere in field/. So this always sits on the inland side of the gate
# regardless of which way the field's forward axis actually points.
func _build_trigger() -> void:
	var shape := BoxShape3D.new()
	shape.size = trigger_size
	trigger_shape.shape = shape
	trigger_area.position = Vector3(0.0, trigger_size.y / 2.0, -trigger_forward_offset)

# Called once by RegionField when floor_cleared fires (see its own doc) -
# this node never watches for that condition itself. _open guards against
# a second call re-triggering the tween/print - floor_cleared itself only
# ever emits once (see RegionField's own doc), but nothing here should
# assume that on its own. Disabling the shape rather than freeing it:
# reopening on a future re-clear (there isn't one yet, but nothing here
# assumes one-way) is just flipping this back.
func open() -> void:
	if _open:
		return
	_open = true
	blocker_shape.disabled = true
	print("ExitGate: open")

	var tween := create_tween()
	tween.set_parallel(true)
	# Sinks the physical-no bar into the sand rather than fading/freeing it -
	# reads as the barrier itself giving way, not just disappearing.
	tween.tween_property(bar, "position:y", bar_height_offset - bar_sink_depth, open_transition_time)
	if _strip_material != null:
		tween.tween_property(_strip_material, "albedo_color", strip_open_color, open_transition_time)

func _on_trigger_body_entered(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		floor_exited.emit()

# push_warning, not print - this is a confirm-the-collision-is-real signal
# for verifying the blocker actually stops the Wanderer, not routine field
# chatter. Once per approach: guarded on _blocker_contact_active so holding
# against the blocker doesn't spam it every physics tick, reset on exit so
# backing off and walking into it again warns again.
func _on_block_contact_entered(body: Node3D) -> void:
	if _open or _blocker_contact_active or not body.is_in_group("wanderer"):
		return
	_blocker_contact_active = true
	push_warning("ExitGate: Wanderer hit closed blocker")

func _on_block_contact_exited(body: Node3D) -> void:
	if body.is_in_group("wanderer"):
		_blocker_contact_active = false
