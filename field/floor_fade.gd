extends CanvasLayer
class_name FloorFade

# The pale that takes the frame between floors. Lives directly under the
# SceneTree's root, NOT in region_field.tscn: the floor change is a
# reload_current_scene() (see RegionField._on_floor_exited()), which
# replaces the whole field scene, and a fade that went with it would cut
# to black-then-new-floor instead of holding the colour across. One
# instance per session, made on first use (get_or_create()) and found
# again by the reloaded field to fade back in. PROCESS_MODE_ALWAYS so its
# tweens run while the field is frozen for the transition.
#
# The zone intro (ZoneIntro) is the one other user, and it makes its OWN
# instance under itself instead: that fade only ever lifts, so it needn't
# outlive the scene - and it can't be the root one anyway, since a root
# add_child() from inside a scene's _ready() fails (the root is busy
# setting that scene up) and deferring it would let the first frame draw
# unfaded. set_opaque() puts it up before that frame; clear() takes it
# down mid-tween on a skip.

const NODE_NAME := "FloorFade"
# Above BattleLayer (2) and FieldHUD (1).
const LAYER := 128

var _rect: ColorRect = null
# The running fade, if any - killed by clear() and by the next fade call,
# so two ramps never fight over the alpha.
var _tween: Tween = null

static func get_or_create(tree: SceneTree) -> FloorFade:
	var existing := tree.root.get_node_or_null(NODE_NAME) as FloorFade
	if existing != null:
		return existing
	var fade := FloorFade.new()
	fade.name = NODE_NAME
	tree.root.add_child(fade)
	return fade

# The one already there, if a transition made it - the first floor of a
# session has nothing to fade in from and needn't make one.
static func find_existing(tree: SceneTree) -> FloorFade:
	return tree.root.get_node_or_null(NODE_NAME) as FloorFade

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = LAYER
	_rect = ColorRect.new()
	_rect.name = "Fill"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)
	add_child(_rect)

func is_opaque() -> bool:
	return _rect != null and _rect.color.a >= 0.999

# To full `colour` over `seconds`; awaitable. The rect's own RGB is set
# up front so the ramp is alpha only.
func fade_out(colour: Color, seconds: float) -> void:
	if _rect == null:
		return
	_kill_tween()
	_rect.color = Color(colour.r, colour.g, colour.b, _rect.color.a)
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 1.0, seconds)
	await _tween.finished

# Back to clear over `seconds`; awaitable. A no-op on an already-clear
# rect.
func fade_in(seconds: float) -> void:
	if _rect == null or _rect.color.a <= 0.001:
		return
	_kill_tween()
	_tween = create_tween()
	_tween.tween_property(_rect, "color:a", 0.0, seconds)
	await _tween.finished

# Full `colour` at once, no ramp - the run opening's first frame.
func set_opaque(colour: Color) -> void:
	if _rect == null:
		return
	_kill_tween()
	_rect.color = Color(colour.r, colour.g, colour.b, 1.0)

# Clear at once, whatever ramp was running - the opening's skip.
func clear() -> void:
	if _rect == null:
		return
	_kill_tween()
	_rect.color.a = 0.0

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
