extends Node
class_name ClickToMove
# The click-to-move layer shared by every field-style room - plain ground
# clicks, click-to-approach on registered interactables, and the shared
# ground marker (click_move_marker.gd) showing where the player is headed.
# Extracted out of field_room.gd (2026-08-27, pure refactor, no behavior
# change) specifically so field_interior.gd (the Pay House interior, and
# any future structure interior) can reuse the exact same click handling
# instead of field_room.gd being the only scene with it - see that
# investigation's own report on why the interior had none of this at all.
#
# A plain Node, not Node2D - this has no visual footprint or transform of
# its own; everything it draws (the marker) or moves (the player) belongs
# to the host scene. setup()/set_bounds()/register_interactable() below
# are the whole API a host scene needs, in that order: setup() once at
# startup, register_interactable() per interactable as each is spawned/
# wired, set_bounds() once at startup and again any time the room's own
# walkable width changes at runtime.

const CLICK_MOVE_MARKER_SCRIPT := preload("res://click_move_marker.gd")
# See setup() below - same "set_script() onto a plain node, no .tscn"
# reasoning field_room.gd's own FIELD_PARTICULATE_SCRIPT comment gives,
# for the same reason: a single-shape node with no children of its own.

var player: Player = null
var _left_x: float = 0.0
var _right_x: float = 0.0

var click_move_marker
# Deliberately untyped, NOT `: ClickMoveMarker` - same reasoning field_
# room.gd's own FIELD_PARTICULATE_SCRIPT motes need: set_script()
# attaching ClickMoveMarker's members is a RUNTIME effect the static
# analyzer can't see, so a static ClickMoveMarker type here would fail to
# compile against the plain Polygon2D.new() assigned to it in setup()
# below. Built once there, not part of any .tscn - same "procedural node,
# no scene file" shape as the particulate motes above.

# Called once by the host scene right after instantiating this node and
# adding it to the tree (add_child() must happen first - _unhandled_input()
# below only ever fires once this node is actually inside the SceneTree).
# player_ref is whose move_to()/destination_set/destination_cleared this
# drives; content_root is where the shared ground marker gets added (the
# SAME parent field_room.gd always used, so the marker renders at exactly
# the layer/z-order it always has - adding it as a child of THIS node
# instead would give it no CanvasItem transform to inherit, since a plain
# Node isn't one); floor_line_y positions the marker on the room's own
# walking line, matching whatever that room's floor actually sits at.
func setup(player_ref: Player, content_root: Node2D, floor_line_y: float) -> void:
	player = player_ref
	get_viewport().physics_object_picking = true
	click_move_marker = Polygon2D.new()
	click_move_marker.set_script(CLICK_MOVE_MARKER_SCRIPT)
	# Y set ONCE here, never touched again - the marker only ever moves in
	# x (show_at() below only takes an x), same flat-lane assumption every
	# other piece of this feature already makes. Left at the default (0,0)
	# this rendered up near the room's true top edge instead of the floor
	# line the player actually walks on - technically drawing every click,
	# just nowhere anyone would see it.
	click_move_marker.position.y = floor_line_y
	content_root.add_child(click_move_marker)
	player.destination_set.connect(_on_player_destination_set)
	player.destination_cleared.connect(click_move_marker.hide_marker)

# Relayed rather than connecting click_move_marker.show_at directly
# (2026-08-27, room-transition pass) - player.input_locked (see player.gd's
# own doc) now drives scripted move_to() calls too (the walk-on/departure
# beats - see field_room.gd's _play_walk_on_intro()/_on_exit_entered()),
# which still fire destination_set like any other move_to(). A ground
# marker popping up with no click behind it would read as a stray UI bug
# during those - hide_marker() stays connected directly below since hiding
# is harmless/idempotent regardless of who triggered it.
func _on_player_destination_set(x: float) -> void:
	if not player.input_locked:
		click_move_marker.show_at(x)

# Supplied by the host scene, not computed here - a standard field room's
# own ROOM_FLOOR_LEFT_X/_room_floor_right_x() and the Pay House interior's
# own fixed 40/interior_width-40 are two unrelated sizing schemes, and this
# helper has no business knowing about either. Callable again any time
# those bounds change at runtime (e.g. an interior whose own width can
# change after initial setup).
func set_bounds(left_x: float, right_x: float) -> void:
	_left_x = left_x
	_right_x = right_x

# Registers a single interactable's own Area2D.input_event - clicking it
# walks the player exactly onto its position, same as every existing
# walk-and-fire interactable (chests, structures, markers, exit doors)
# already relies on: none of them need a separate "now trigger it" call,
# since arriving at that position is what fires their own body_entered.
func register_interactable(node: Node2D) -> void:
	node.input_event.connect(_on_interactable_clicked.bind(node))

# set_input_as_handled() is what stops this same click from ALSO being
# read by _unhandled_input() below as a plain ground click a moment later,
# which would otherwise immediately overwrite this destination with the
# raw click position instead of the interactable's own.
func _on_interactable_clicked(_viewport: Node, event: InputEvent, _shape_idx: int, node: Node2D) -> void:
	if player.input_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		player.move_to(clampf(node.global_position.x, _left_x, _right_x))
		get_viewport().set_input_as_handled()

# Plain ground clicks - anywhere that ISN'T a UI element and ISN'T one of
# the interactables registered above. Godot only ever calls _unhandled_
# input() with an event no Control already consumed during its own GUI
# input pass, so a click on any of the host scene's own popups/HUD never
# reaches here at all - that alone is what satisfies "clicks on UI must
# not set a destination," with no manual rect-checking needed here.
#
# Uses player's own get_global_mouse_position(), not this node's - a
# ClickToMove is a plain Node, not a CanvasItem, so it has no transform of
# its own to resolve a mouse position through; player's is already the
# same world space move_to()'s own target is expressed in.
#
# Bails out early while player.input_locked (2026-08-27, room-transition
# pass) - a click during a scripted walk-on/departure beat must not
# retarget it; see player.gd's own input_locked doc for why this check
# belongs at the click-consuming call site, not inside move_to() itself.
func _unhandled_input(event: InputEvent) -> void:
	if player.input_locked:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var world_x: float = player.get_global_mouse_position().x
		player.move_to(clampf(world_x, _left_x, _right_x))
