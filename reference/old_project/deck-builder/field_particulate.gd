extends Polygon2D
class_name FieldParticulate
# One drifting mote (ash/spore/salt register - see field_room.gd's
# particulate layer notes). Self-contained ambient motion, same
# "the node animates itself" shape field_wall.gd's own depth_shade_pulse
# already established for the opening room's foam - field_room.gd only
# has to place these, not drive them every frame itself.
#
# Drift is INDEPENDENT of this mote's own ParallaxLayer's motion_scale:
# motion_scale is the camera-pan-driven parallax speed (handled entirely
# by the engine, this script never touches it), drift_speed_px_sec below
# is a constant ambient crawl on top of that, always active regardless of
# whether the camera is moving at all. Horizontal only, matching every
# other background element in this side-scrolling room - a vertical bob
# was considered and dropped as unnecessary motion for something this
# sparse and this far back.

@export var drift_speed_px_sec: float = 6.0
@export var wrap_width: float = 2200.0
# Must match whichever layer's own motion_mirroring width this mote's
# parent ParallaxLayer uses (background_tile_width, normally - see
# field_room.gd's own populate calls) - wrapping the mote's LOCAL x
# position at the same period the layer already repeats content at is
# what keeps the wrap invisible (the mote re-enters exactly where an
# identical copy of the tile would place it), instead of visibly
# teleporting mid-frame.

func _process(delta: float) -> void:
	position.x = fposmod(position.x + drift_speed_px_sec * delta, wrap_width)
