extends Node3D
class_name ExitGate

# Floor-exit prototype (see region_field.gd's own doc on the floor_cleared/
# floor_exited handshake). RegionField positions and orients this node
# itself - see RegionField._setup_exit_gate()'s own doc for why this can't
# compute its own placement from its _ready(), the same ordering constraint
# FieldEnemy's own doc describes for get_forward().
#
# The gate has no geometry of its own any more: what closes the neck is a
# tidal channel cut into the relief across it (a GroundChannel registered
# on Ground by setup_channel(), once RegionField has placed this node),
# full of water while the floor is uncleared and drained by open(). The
# only things here are the invisible Blocker (a StaticBody3D across the
# channel's whole width while closed), its BlockContactArea, and the
# TriggerArea on the inland side that fires floor_exited. Every export
# that affects a built shape gets a setter so a Remote-tab edit rebuilds
# it live, same pattern as contact_shadow.gd's radius/shadow_opacity.

signal floor_exited

# The channel (see ground_channel.gd) is sized from the boundary walls in
# setup_channel(): its near bank sits channel_near_offset past the gate
# line on the spawn side, it runs inland to the inland wall and channel_
# beyond_wall metres past it (into the fog), and it spans the side walls
# plus channel_width_margin - so from the gate line inland there is
# nothing but water while the floor is uncleared. channel_depth 0.5 puts
# the floor 0.25m under sea_level at the neck's 0.25m interior. The banks
# wander by the relief's noise (channel_edge_noise_*) over a channel_edge
# soft edge - the near bank is the one that has to read as a shore.
# Draining surfaces only channel_bar_width of sand along the neck's axis
# (the gate's own line), leaving a channel either side.
@export var channel_near_offset: float = 1.0
@export var channel_beyond_wall: float = 12.0
@export var channel_width_margin: float = 4.0
@export var channel_depth: float = 0.5
@export var channel_edge: float = 1.2
@export var channel_edge_noise_scale: float = 2.0
@export var channel_edge_noise_amplitude: float = 0.6
@export var channel_bar_width: float = 6.0
# How long the channel takes to drain after open(), eased out - fast at
# first, settling as the sand surfaces. The drain itself is a shader
# uniform tween (Ground.set_channel_live_amount(), one uniform write per
# frame - the relief mesh isn't touched); Ground bakes the drained
# channel into mesh/collision/get_height_at() ONCE when the tween ends,
# and only then does the Blocker come down.
@export var drain_seconds: float = 4.0

# The Blocker: an invisible box across the closed channel's near bank -
# blocker_depth along the neck, centred blocker_inland_offset inland of
# the gate line (2.5: its near face is 1m past the waterline, so the
# Wanderer is held standing in water at the channel's full depth, with
# the drain running), as wide as the channel, block_height tall.
@export var block_height: float = 1.4:
	set(value):
		block_height = value
		_rebuild()
@export var blocker_depth: float = 3.0:
	set(value):
		blocker_depth = value
		_rebuild()
@export var blocker_inland_offset: float = 2.5:
	set(value):
		blocker_inland_offset = value
		_rebuild()
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

var _ground: Ground = null
var _channel: GroundChannel = null
var _channel_index: int = -1
# The channel's width once sized from the walls (the Blocker's width).
var _channel_width: float = 14.0
# The tweened value: 1 = channel fully cut and full, 0 = gone.
var _channel_amount: float = 1.0

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

# Called by RegionField once this node is in its final place and the
# boundary walls exist (wall_rect: their centre-line rectangle in world
# XZ): sizes and registers the channel. Along the neck (this node's local
# -Z = the field's forward): from channel_near_offset on the spawn side
# of the gate line to the inland wall plus channel_beyond_wall. Across:
# the walls' span plus channel_width_margin, centred on the walls, with
# the drained bar centred on the gate line itself. Everything is
# projected onto forward/right rather than read off X/Z, so it holds for
# any forward. Ground cuts the channel through its partial path (no full
# rebuild). Idempotent - a second call re-sizes the existing channel.
func setup_channel(ground: Ground, wall_rect: Rect2) -> void:
	_ground = ground
	var forward := Vector2(-global_transform.basis.z.x, -global_transform.basis.z.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var gate := Vector2(global_position.x, global_position.z)

	# Wall extents along forward (inland = furthest along it) and across.
	var corners: Array[Vector2] = [wall_rect.position, wall_rect.end, Vector2(wall_rect.position.x, wall_rect.end.y), Vector2(wall_rect.end.x, wall_rect.position.y)]
	var inland_along: float = -INF
	var across_min: float = INF
	var across_max: float = -INF
	for corner in corners:
		var rel: Vector2 = corner - gate
		inland_along = maxf(inland_along, rel.dot(forward))
		across_min = minf(across_min, rel.dot(right))
		across_max = maxf(across_max, rel.dot(right))
	if wall_rect.size == Vector2.ZERO:
		inland_along = channel_beyond_wall
		across_min = -7.0
		across_max = 7.0

	var length: float = channel_near_offset + inland_along + channel_beyond_wall
	_channel_width = (across_max - across_min) + channel_width_margin
	var across_centre: float = (across_min + across_max) * 0.5
	var centre: Vector2 = gate + forward * (length * 0.5 - channel_near_offset) + right * across_centre

	if _channel == null:
		_channel = GroundChannel.new()
	_channel.centre = centre
	_channel.length = length
	_channel.width = _channel_width
	_channel.depth = channel_depth
	_channel.edge = channel_edge
	_channel.edge_noise_scale = channel_edge_noise_scale
	_channel.edge_noise_amplitude = channel_edge_noise_amplitude
	_channel.bar_width = channel_bar_width
	# The bar sits on the gate line, not the walls' midline.
	_channel.bar_offset = -across_centre
	_channel.amount = _channel_amount
	if _channel_index < 0:
		_channel_index = _ground.add_channel(_channel)
	else:
		_ground.set_channel_amount(_channel_index, _channel_amount)
	print("ExitGate: channel %.1f x %.1f m, near bank %.1f m spawn-side of the gate line, bar %.1f m" % [length, _channel_width, channel_near_offset, channel_bar_width])
	_rebuild()

# Every exported dimension above lands here rather than each having its
# own narrow _apply_*() - the blocker and its contact area share the same
# footprint, and the lot is a couple of shapes. Cheap enough that
# rebuilding everything on any single edit isn't worth avoiding.
func _rebuild() -> void:
	if not _ready_done:
		return
	_build_blocker()
	_build_trigger()

# Spans the closed channel's near bank: the channel's full width across
# the neck, blocker_depth along it, centred blocker_inland_offset inland
# (local -Z) of the gate line, block_height tall - the water is what
# reads as the closed gate, this is the physical "no" standing in it, and
# there's no dry way round it since the channel runs wall to wall.
# BlockContactArea shares this exact footprint so "the Wanderer hit the
# blocker" (see _on_block_contact_entered()) means what it says.
func _build_blocker() -> void:
	var footprint := Vector3(_channel_width, block_height, blocker_depth)

	var shape := BoxShape3D.new()
	shape.size = footprint
	blocker_shape.shape = shape
	blocker.position = Vector3(0.0, block_height / 2.0, -blocker_inland_offset)

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
# assume that on its own. Drains the channel over drain_seconds (ease-
# out), and only when the water is gone does the Blocker's shape get
# disabled - disabled rather than freed: reopening on a future re-clear
# (there isn't one yet, but nothing here assumes one-way) is just flipping
# this back. As the sand surfaces, Ground's own wet band/wet mark take
# over the look.
func open() -> void:
	if _open:
		return
	_open = true
	print("ExitGate: open - draining")

	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(_set_channel_amount, _channel_amount, 0.0, drain_seconds)
	tween.tween_callback(_on_drained)

# Per tween frame: the shader-side amount only (and the drain's view of
# it) - no relief re-cut.
func _set_channel_amount(amount: float) -> void:
	_channel_amount = amount
	if _ground == null or _channel_index < 0:
		return
	_ground.set_channel_live_amount(_channel_index, amount)

# Tween done: one CPU bake at the final amount so mesh, collision and
# get_height_at() agree with what the shader has been showing (the
# shader's delta collapses to 0 in the same call), then the Blocker
# comes down.
func _on_drained() -> void:
	_channel_amount = 0.0
	if _ground != null and _channel_index >= 0:
		_ground.set_channel_amount(_channel_index, 0.0)
	blocker_shape.disabled = true
	print("ExitGate: drained")

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
