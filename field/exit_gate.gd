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
# - the gate's own line, shifted across by channel_bar_axis_offset for a
# neck that isn't centred on the gate (Map2's runs x -1.4..3.1, axis
# 0.85) - leaving a channel either side. 9 m so the bar reads as ground
# to walk on, not a plank laid across.
@export var channel_near_offset: float = 1.0
@export var channel_beyond_wall: float = 12.0
@export var channel_width_margin: float = 4.0
@export var channel_depth: float = 0.5
@export var channel_edge: float = 1.2
@export var channel_edge_noise_scale: float = 2.0
@export var channel_edge_noise_amplitude: float = 0.6
# The channel spans the walls, which is right for a field whose land IS
# the neck. A floor with land off to one side (floor 2's alcove) would
# have the channel reach out to it and carve its near bank straight
# through - so past this many metres the channel holds its width and
# centres on the GATE instead of the walls' midline, staying the neck's
# own channel. 0 = span the walls, as every floor did before.
@export var channel_max_width: float = 0.0
@export var channel_bar_width: float = 9.0
# Metres across (the gate's local right) from the gate's own line to the
# bar's centre line.
@export var channel_bar_axis_offset: float = 0.0
# How long the channel takes to drain after open(), eased out - fast at
# first, settling as the sand surfaces. The drain itself is a shader
# uniform tween (Ground.set_channel_live_amount(), one uniform write per
# frame - the relief mesh isn't touched); Ground bakes the drained
# channel into mesh/collision/get_height_at() ONCE when the tween ends,
# and only then does the Blocker come down. 2 s: at the start of the
# ease the sand rises about 1.25 cm per physics frame, still well under
# the Wanderer's 3 cm ground-hold tolerance (tests/drain_probe.gd checks
# this). Read once per open(), so an edit made before the floor clears
# applies; it doesn't re-time a drain that's already running.
@export var drain_seconds: float = 2.0

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
# The TriggerArea's distance inland of the gate line - the floor's far
# end. RegionField pushes its own transition_distance here (12 m past the
# gate, the end of the surfaced bar); the 2.0 default is only what a gate
# standing alone gets.
@export var trigger_forward_offset: float = 2.0:
	set(value):
		trigger_forward_offset = value
		_rebuild()
# Across (x) is only the standalone default: RegionField fits it to the
# painted land at the trigger's own line - see fit_trigger_to_land().
@export var trigger_size: Vector3 = Vector3(4.0, 3.0, 2.0):
	set(value):
		trigger_size = value
		_rebuild()
# Metres across (local +X, the gate's right) from the gate's own line to
# the trigger's centre - the neck at the trigger line needn't be centred
# on the gate. Set by fit_trigger_to_land().
@export var trigger_across_offset: float = 0.0:
	set(value):
		trigger_across_offset = value
		_rebuild()
# How far past the land's edge the fitted trigger reaches on each side,
# and the step it samples the shore distance at (the mask distance grid
# is 0.25 m; sampling finer buys nothing).
@export var trigger_land_margin: float = 2.0
@export var trigger_fit_step: float = 0.25
# Furthest the fit looks either side of the trigger line's centre before
# giving up - wider than any neck this region paints.
@export var trigger_fit_max_half_width: float = 40.0
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
	if channel_max_width > 0.0 and _channel_width > channel_max_width:
		_channel_width = channel_max_width
		# Centred on the gate, so the bar stays exactly where it was.
		across_centre = 0.0
	var centre: Vector2 = gate + forward * (length * 0.5 - channel_near_offset) + right * across_centre

	if _channel == null:
		_channel = GroundChannel.new()
	_channel.centre = centre
	# The one axis the channel runs along - the gate's own forward, the
	# floor's exit direction - for Ground's CPU functions and its shader.
	_channel.axis = forward
	_channel.length = length
	_channel.width = _channel_width
	_channel.depth = channel_depth
	_channel.edge = channel_edge
	_channel.edge_noise_scale = channel_edge_noise_scale
	_channel.edge_noise_amplitude = channel_edge_noise_amplitude
	_channel.bar_width = channel_bar_width
	# The bar sits on the gate line, not the walls' midline.
	_channel.bar_offset = -across_centre + channel_bar_axis_offset
	_channel.amount = _channel_amount
	if _channel_index < 0:
		_channel_index = _ground.add_channel(_channel)
	else:
		_ground.set_channel_amount(_channel_index, _channel_amount)
	print("ExitGate: channel %.1f x %.1f m, near bank %.1f m spawn-side of the gate line, bar %.1f m at %+.2f m across" % [length, _channel_width, channel_near_offset, channel_bar_width, channel_bar_axis_offset])
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
	trigger_area.position = Vector3(trigger_across_offset, trigger_size.y / 2.0, -trigger_forward_offset)

# Called by RegionField once this node is placed and Ground is built,
# BEFORE the channel is registered (the channel turns everything past the
# gate line into water for Ground.get_landmass_distance(), and it is the
# painted land this measures): samples the shore distance along the
# trigger's own line (across = local +X) either side of its centre, takes
# the contiguous run of land the centre sits in - or the nearest run if
# the centre itself is water - and sizes/centres the trigger on it plus
# trigger_land_margin each side, so no path up the neck can miss it.
# Leaves the authored size alone, with a warning, if no land is found.
func fit_trigger_to_land(ground: Ground) -> void:
	if ground == null:
		return
	var forward := Vector2(-global_transform.basis.z.x, -global_transform.basis.z.z).normalized()
	var right := Vector2(-forward.y, forward.x)
	var centre: Vector2 = Vector2(global_position.x, global_position.z) + forward * trigger_forward_offset
	var step: float = maxf(trigger_fit_step, 0.01)
	var count: int = int(ceil(trigger_fit_max_half_width / step))
	# land[i] is the sample at across = (i - count) * step.
	var land: PackedByteArray = PackedByteArray()
	land.resize(count * 2 + 1)
	var nearest: int = -1
	for i in land.size():
		var across: float = float(i - count) * step
		var on_land: bool = ground.get_landmass_distance(centre + right * across) <= 0.0
		land[i] = 1 if on_land else 0
		if on_land and (nearest < 0 or absi(i - count) < absi(nearest - count)):
			nearest = i
	if nearest < 0:
		push_warning("ExitGate: no painted land within %.0f m of the trigger line; trigger left at %.1f m across." % [trigger_fit_max_half_width, trigger_size.x])
		return
	var lo: int = nearest
	while lo > 0 and land[lo - 1] == 1:
		lo -= 1
	var hi: int = nearest
	while hi < land.size() - 1 and land[hi + 1] == 1:
		hi += 1
	var left_edge: float = float(lo - count) * step - trigger_land_margin
	var right_edge: float = float(hi - count) * step + trigger_land_margin
	trigger_across_offset = (left_edge + right_edge) * 0.5
	trigger_size = Vector3(right_edge - left_edge, trigger_size.y, trigger_size.z)
	print("ExitGate: trigger fitted to the land at its line - %.1f m across (land %.1f m, +%.1f m each side), centred %+.2f m across from the gate line" % [trigger_size.x, float(hi - lo) * step, trigger_land_margin, trigger_across_offset])

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

# Only once open: the trigger now sits a couple of metres past the gate
# line, inside the closed Blocker's own reach, so a Wanderer pressed
# against the blocker must not be able to end the floor through it.
func _on_trigger_body_entered(body: Node3D) -> void:
	if _open and body.is_in_group("wanderer"):
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
