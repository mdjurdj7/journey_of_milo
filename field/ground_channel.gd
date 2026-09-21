extends Resource
class_name GroundChannel

# One tidal channel cut into the relief - see Ground.channels. A world-
# space rectangle centred on `centre` (world XZ), `length` metres along
# `axis` (unit XZ - the floor's exit direction, written by ExitGate.
# setup_channel() and read by Ground's CPU side and its shader alike, so
# there is one axis, never an assumed one) and `width` across it,
# lowering the ground inside by
# `depth` with a soft edge `edge` metres wide. The edge is perturbed by
# the relief's own value noise (edge_noise_scale / edge_noise_amplitude)
# so the banks wander like a shore instead of ruling a canal.
#
# `amount` is what gets tweened (1 = fully cut, 0 = gone) - through
# Ground.set_channel_amount(), which rebuilds only the affected patch of
# the relief. With bar_width > 0 the amount only applies inside a strip
# that wide along the channel's own axis (soft, noised edges too), offset
# bar_offset metres across from the centre: draining then surfaces a bar
# of sand between two channels that stay full.

@export var centre: Vector2 = Vector2.ZERO
@export var axis: Vector2 = Vector2(0.0, -1.0)
@export var length: float = 3.0
@export var width: float = 14.0
@export var depth: float = 0.5
@export var edge: float = 1.2
@export var edge_noise_scale: float = 2.0
@export var edge_noise_amplitude: float = 0.6
@export_range(0.0, 1.0) var amount: float = 1.0
# 0 = the whole rectangle drains with amount.
@export var bar_width: float = 9.0
@export var bar_offset: float = 0.0
