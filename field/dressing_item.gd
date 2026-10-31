extends Resource
class_name DressingItem

# One hand-placed piece of a DressingGroup: a scatter model (a stone) under
# its colour map, or - with card_texture_path set - a grass tuft card,
# at an explicit offset from the group's origin. Every setter emits
# `changed`, so the group re-places it live from the Remote tab.

# The glb, drawn at `size` times its own metres (ScatterMeshes' mesh).
@export_file("*.glb") var model_path: String = "":
	set(value):
		model_path = value
		emit_changed()
# The model's colour map under the painted shader (PaintedProp).
@export_file("*.jpg", "*.png") var colour_map_path: String = "":
	set(value):
		colour_map_path = value
		emit_changed()
# Set: a tuft card of this painting instead of a model, `size` metres
# tall, drawn by tuft_card.gdshader as the scatter's tufts are.
@export_file("*.png") var card_texture_path: String = "":
	set(value):
		card_texture_path = value
		emit_changed()
# Metres from the group's origin on world X/Z (the group never turns).
@export var offset: Vector2 = Vector2.ZERO:
	set(value):
		offset = value
		emit_changed()
# A model's yaw; a card's turn off facing the camera.
@export var yaw_degrees: float = 0.0:
	set(value):
		yaw_degrees = value
		emit_changed()
# A model's tilt about X then Z, after its yaw - a stone settled askew.
@export var tilt_degrees: Vector2 = Vector2.ZERO:
	set(value):
		tilt_degrees = value
		emit_changed()
# A model's scale; a card's height in metres.
@export var size: float = 1.0:
	set(value):
		size = value
		emit_changed()
# Fraction of its own height below the sand - a stone partly buried.
@export_range(0.0, 1.0) var sink_fraction: float = 0.0:
	set(value):
		sink_fraction = value
		emit_changed()
# A card drawn mirrored.
@export var mirrored: bool = false:
	set(value):
		mirrored = value
		emit_changed()
# Times the colour map (white = as painted).
@export var tint: Color = Color(1.0, 1.0, 1.0):
	set(value):
		tint = value
		emit_changed()
