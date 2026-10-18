extends CanvasLayer
class_name FreezeFrame

# A captured frame held full-screen across a reload_current_scene(): the
# character select's pick (ZoneIntro) captures the held title frame,
# shows it here and reloads the field; the reloaded field takes it down
# once its own held title frame has drawn under it (ZoneIntro.start_
# held_title()). So the reload itself never shows - no flat colour, no
# half-built field.
#
# Lives directly under the tree's root, as FloorFade does, so the reload
# that replaces the field scene doesn't take it with it; one at a time
# (show_image() replaces any already up). PROCESS_MODE_ALWAYS, so its
# release fade and its backstop run through the field's freeze. Above
# everything, FloorFade included.
#
# Freed on every path: release() by the field that holds the title, or by
# whoever finds the hold can't happen; and its own backstop, max_hold_
# seconds after it went up, whatever else did or didn't.

const NODE_NAME := "FreezeFrame"
# Above FloorFade (128).
const LAYER := 129

# How long it may stay up at most before it frees itself - long enough
# that a slow reload never reveals a half-loaded field.
@export var max_hold_seconds: float = 10.0:
	set(value):
		max_hold_seconds = value
		_restart_backstop()

var _rect: TextureRect = null
var _backstop: SceneTreeTimer = null
var _releasing: bool = false

# `image` full-screen on a fresh FreezeFrame under the root, replacing
# any already there. Null (and nothing shown) for an empty image - a
# headless run captures none.
static func show_image(tree: SceneTree, image: Image) -> FreezeFrame:
	var existing := find_existing(tree)
	if existing != null:
		existing.free()
	if image == null or image.is_empty():
		return null
	var freeze := FreezeFrame.new()
	freeze.name = NODE_NAME
	freeze._make_rect(ImageTexture.create_from_image(image))
	tree.root.add_child(freeze)
	return freeze

static func find_existing(tree: SceneTree) -> FreezeFrame:
	return tree.root.get_node_or_null(NODE_NAME) as FreezeFrame

# Takes the one up, if any: at once, or faded out over `seconds`.
static func release(tree: SceneTree, seconds: float = 0.0) -> void:
	var freeze := find_existing(tree)
	if freeze != null:
		freeze._release(seconds)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	_restart_backstop()

func _make_rect(texture: Texture2D) -> void:
	_rect = TextureRect.new()
	_rect.name = "Frame"
	_rect.texture = texture
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

func _restart_backstop() -> void:
	if not is_inside_tree():
		return
	_backstop = get_tree().create_timer(maxf(max_hold_seconds, 0.0), true, false, true)
	var this_timer: SceneTreeTimer = _backstop
	_backstop.timeout.connect(func() -> void:
		if _backstop == this_timer and is_instance_valid(self):
			push_warning("FreezeFrame: still up after %.1f s; freed by its backstop." % max_hold_seconds)
			queue_free())

func _release(seconds: float) -> void:
	if _releasing:
		return
	_releasing = true
	# Out of the root's name at once, so a new one can go up meanwhile.
	name = NODE_NAME + "_released"
	if seconds <= 0.0 or _rect == null:
		queue_free()
		return
	var tween := create_tween()
	tween.tween_property(_rect, "modulate:a", 0.0, seconds)
	tween.finished.connect(queue_free)
