extends Node3D
class_name WorldCard

# One card offered in the world, in two states driven by the Wanderer's
# distance to a 3D anchor (the Keeper's hand today):
#
#   FAR  - a real quad in the world: quad_size metres of bone with a
#          one-texel ink edge, unlit, billboarded about Y only. An object
#          in her hand, lit by nothing and pitching with nothing - she is
#          holding something and you cannot yet see what.
#   NEAR - inside lift_radius the quad goes and a CardView takes over,
#          starting at exactly the quad's projected position and apparent
#          size and tweening over lift_duration_sec to near_scale, out to
#          the RIGHT of the holder's projected silhouette and level with
#          the hand - so it never covers her. Only then is it clickable,
#          and hovering it grows it by the CardView's own hover_scale.
#
# Leaving the radius runs that backwards and the quad returns; taking is
# the only thing that consumes it.
#
# The near state is a CardView on a CanvasLayer, projected to the anchor
# every physics frame - the same shape HPBar and EnemyStatus use for
# their own floating readouts, DistanceScale included. It's a CardView
# rather than a higher-resolution quad texture so the card in her hand
# and the card in the deck view are literally the same Control, with no
# second rendering of card layout to keep in step.
#
# The handover is seamless because the CardView's far-end scale is
# COMPUTED from the quad, not authored: see _quad_match_scale(). Change
# quad_size and the lift still starts at the right size.
#
# Click (only while lifted) grants the card through RunState.add_card(),
# the run's one card-grant path, then flies the CardView to the field
# DeckPanel and frees this node. Deliberately NOT reusing HandContainer's
# own play-to-discard fly: that one animates a card between hand slots it
# owns, keyed to discard_point in its own coordinate space, and has no
# way to be handed a foreign Control or an arbitrary screen target.
#
# `taken` fires after the grant, before the flight - whoever spawned this
# (see Keeper) decides what taking MEANS; this node only knows it happened.

signal taken(card_data: CardData)

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

@export var card: CardData = null:
	set(value):
		card = value
		if _card_view != null and card != null:
			_card_view.set_card_data(card)

# Anchor = this node's own origin plus this, in the node's local space -
# so a spawner can place the node at the hand and leave this at zero, or
# place the node at the figure's feet and lift the anchor instead.
@export var anchor_offset: Vector3 = Vector3.ZERO:
	set(value):
		anchor_offset = value
		_apply_quad()
# Where the lifted card goes, in SCREEN space rather than world space -
# the point is that it never covers the figure holding it, and "beside
# her" is a thing about the picture, not about the world. A world-space
# offset can't promise it: whichever way you push the card in 3D, some
# camera yaw puts it back over her.
#
# The card's LEFT edge lands this many pixels right of the holder's
# projected silhouette edge (see holder_half_width), and its centre sits
# on the anchor's own screen height - so it reads as held out at the
# hand, just clear of her.
@export var screen_gap_px: float = 16.0
# Where the lifted card's BOTTOM EDGE sits: this many metres above the
# holder's feet, projected. Pinning the bottom rather than the centre is
# what keeps the card off her legs no matter how tall it renders - it is
# about 1.8 m tall in world terms at the usual camera distance (168 px at
# 93 px/m), so a centre-based rule moves the bottom whenever the scale
# changes, and a card that clears her head can still hang across her
# knees. Measured from the HOLDER's feet, not the anchor, so moving the
# hand offset doesn't drag the lifted card with it.
@export var near_bottom_height: float = 0.15
# Half the holder's width in metres, projected each frame to find that
# silhouette edge. 0 (the default) measures it once from holder_path's
# own meshes; set it non-zero to override. Measured rather than authored
# because the number that matters is the rendered figure's, and the
# Keeper's own is 0.39 m - a hand-typed guess drifts the moment a model
# is swapped.
@export var holder_half_width: float = 0.0
@export var holder_path: NodePath = ^".."

@export var lift_radius: float = 2.5
# Off when something else decides whether this card is lifted - see
# set_lifted(). A RewardSpread lifts its three together from the spread's
# own centre, so each card measuring its own radius would stagger them.
@export var lift_radius_enabled: bool = true
@export var lift_duration_sec: float = 0.18

@export var near_scale: float = 1.0
# Growth on hover, this node's own rather than CardView.hover_scale (1.15,
# which is tuned for a card already close in the hand). The tween's
# duration still comes from the CardView - see _hover_scale().
@export var hover_scale: float = 1.35

# The far state's quad. Card-shaped rather than square; 0.09 x 0.13 m is
# a playing card at roughly a third scale, which is what reads as "held"
# rather than "propped" in a 1.65 m figure's hand.
@export_group("Far Quad")
@export var quad_size: Vector2 = Vector2(0.09, 0.13):
	set(value):
		quad_size = value
		_apply_quad()
@export var quad_color: Color = Color(0.94, 0.91, 0.86):
	set(value):
		quad_color = value
		_apply_quad()
@export var quad_border_color: Color = Color(0.165, 0.165, 0.18):
	set(value):
		quad_border_color = value
		_apply_quad()
# The border is always exactly ONE texel, so this width sets how thick it
# reads: at 14 texels across 0.09 m, one texel is ~6.4 mm, which at the
# field camera's usual ~150 px/m lands on about one screen pixel. Nearest
# filtering keeps it a hard edge rather than a grey smear. Raise the
# width and the border gets finer, not coarser.
@export var quad_texture_width_px: int = 14:
	set(value):
		quad_texture_width_px = value
		_apply_quad()
@export_group("")

# Apparent-size correction, same knobs and same defaults as HPBar's.
@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0
@export_group("")

@export_group("Take Flight")
# How long the quad takes to fade once a card is dismissed rather than
# taken - see dismiss().
@export var dismiss_fade_sec: float = 0.6
@export var flight_duration_sec: float = 0.45
@export var flight_end_scale: float = 0.12
# Resolved to <region_field>/FieldHUD/DeckPanel - the card flies to the
# Belongings count it is about to increment. Without it the flight still
# plays, just straight down off the bottom of the frame.
@export var region_field_path: NodePath = ^"../.."
@export_group("")

var _card_view: CardView = null
var _layer: CanvasLayer = null
var _quad: MeshInstance3D = null
var _quad_mesh: QuadMesh = null
var _quad_material: StandardMaterial3D = null
var _wanderer: Node3D = null
# 0 = far, 1 = lifted. Tweened, not snapped, so crossing the radius reads
# as the card rising rather than popping.
var _lift: float = 0.0
var _lift_tween: Tween = null
var _near: bool = false
var _taking: bool = false
# Being taken away un-taken - see dismiss(). Distinct from _taking: the
# card still tracks its anchor while it settles, it just can't be
# clicked any more.
var _dismissing: bool = false
# 0 = not hovered, 1 = hovered. Same shape as _lift, and the same reason:
# tweened so it grows rather than snaps.
var _hover: float = 0.0
var _hover_tween: Tween = null
# Measured once from holder_path - the model doesn't change size, and the
# hem wind only moves vertices, never the authored bounds.
var _holder_half_width: float = 0.0

func _ready() -> void:
	# The projection has to run AFTER CameraRig has moved the camera this
	# frame, or the card tracks a frame-old camera and visibly lags the
	# anchor whenever the camera is moving. CameraRig places the camera in
	# its own _physics_process at the default priority, so a higher number
	# here puts this behind it in the same frame.
	process_priority = 1
	# A WorldCard with nothing to offer has no reason to exist: the quad
	# would sit in her hand looking takeable and _take() would refuse it,
	# which reads as a broken offer rather than as no offer. Refuse to
	# spawn instead, loudly. Keeper already declines to build one when its
	# pool comes up empty; this is the backstop for any other caller.
	if card == null:
		push_warning("WorldCard: spawned with no card; freeing rather than showing an empty one.")
		queue_free()
		return
	_spawn_quad()
	_layer = CanvasLayer.new()
	_layer.name = "CardLayer"
	add_child(_layer)

	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("WorldCard: could not load %s; nothing to show." % CARD_VIEW_SCENE_PATH)
		return
	_card_view = scene.instantiate() as CardView
	# Hover is a hand-container behaviour (grow over your neighbours); out
	# here the lift IS the hover, so it would fight this node's own scale.
	_card_view.hover_enabled = false
	_layer.add_child(_card_view)
	if card != null:
		_card_view.set_card_data(card)
	# Scale and position about the card's own middle - the lift should
	# grow it in place, not out of its top-left corner.
	_card_view.pivot_offset = _card_view.card_size / 2.0
	_card_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_card_view.gui_input.connect(_on_card_gui_input)
	# CardView's own hover is off (it's a hand-container behaviour that
	# would fight this node's scale), so the hover is driven here - but
	# from the CardView's OWN hover_scale/hover_duration_sec, so a lifted
	# card and a card in the hand grow by the same amount at the same rate
	# without the number being typed twice.
	_card_view.mouse_entered.connect(_on_card_mouse_entered)
	_card_view.mouse_exited.connect(_on_card_mouse_exited)
	_card_view.visible = false

	_wanderer = _find_wanderer()
	_holder_half_width = _measure_holder_half_width()

# Half the holder's rendered width, in its own space - the FIGURE's, not
# everything parented to her. Two things under her are meshes and neither
# belongs in a silhouette:
#   ContactShadow - a ground disc, radius 0.5, wider than she is (0.392).
#                   Taking it would push the card ~11 cm further out for
#                   no visible reason, since the disc is flat on the sand.
#   this WorldCard - the far quad is a child of a child of hers. Measuring
#                    the card to place the card is circular.
# Both were actually hit before these two lines existed; the union is
# still over every remaining mesh rather than one assumed model node.
func _measure_holder_half_width() -> float:
	if holder_half_width > 0.0:
		return holder_half_width
	var holder := get_node_or_null(holder_path) as Node3D
	if holder == null:
		return 0.0
	var widest: float = 0.0
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance is ContactShadow or is_ancestor_of(mesh_instance):
			continue
		var box: AABB = holder.global_transform.affine_inverse() * (mesh_instance.global_transform * mesh_instance.get_aabb())
		widest = maxf(widest, maxf(absf(box.position.x), absf(box.position.x + box.size.x)))
	return widest

# The far state, as a real object rather than a shrunken Control.
#
# BILLBOARD_FIXED_Y is doing the "yawed to face the camera, no pitch" -
# the material's own vertex stage, not a per-frame look_at here, so it
# can't lag the camera by a frame and costs nothing on two triangles.
#
# Unlit on purpose: the overcast key would otherwise grade a 9 cm quad
# across its width as the camera orbits, and a card that changes value
# while nothing about it moves reads as a bug. It also means the bone is
# exactly the authored bone.
#
# No shadow. Casting one is cheap enough (two triangles), but a
# billboarded quad's shadow is a rectangle that spins on the sand as the
# camera moves, which is worse than no shadow at all - and a ContactShadow
# blob is wrong for a different reason: it grounds things to the terrain,
# and this is held at chest height, so a disc beneath it would read as a
# second figure's shadow rather than the card's.
func _spawn_quad() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "FarQuad"
	_quad_mesh = QuadMesh.new()
	_quad.mesh = _quad_mesh
	_quad_material = StandardMaterial3D.new()
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_quad_material.billboard_keep_scale = true
	# Billboarded, so which way the quad's own face points is meaningless -
	# culling either side would just make it vanish from some angles.
	_quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_quad.material_override = _quad_material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_apply_quad()

# Bone with a one-texel ink edge, drawn as a texture rather than as a
# second, slightly larger quad behind this one: a backing quad would need
# a depth offset to stay behind, and BILLBOARD_FIXED_Y rotates the MESH
# while leaving the node's own transform alone, so any such offset would
# swing out of alignment as the camera orbits. One quad, one texture, no
# depth fight.
func _apply_quad() -> void:
	if _quad_mesh == null or _quad_material == null:
		return
	_quad_mesh.size = quad_size
	_quad.position = anchor_offset
	var w: int = maxi(quad_texture_width_px, 3)
	var aspect: float = quad_size.y / maxf(quad_size.x, 0.0001)
	var h: int = maxi(int(round(float(w) * aspect)), 3)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	image.fill(quad_color)
	for x in w:
		image.set_pixel(x, 0, quad_border_color)
		image.set_pixel(x, h - 1, quad_border_color)
	for y in h:
		image.set_pixel(0, y, quad_border_color)
		image.set_pixel(w - 1, y, quad_border_color)
	_quad_material.albedo_texture = ImageTexture.create_from_image(image)

func _find_wanderer() -> Node3D:
	var found: Array[Node] = get_tree().get_nodes_in_group("wanderer")
	return found[0] as Node3D if not found.is_empty() else null

func anchor_position() -> Vector3:
	return global_transform * anchor_offset

func _physics_process(_delta: float) -> void:
	if _card_view == null or _taking:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var anchor: Vector3 = anchor_position()
	if _wanderer == null or not is_instance_valid(_wanderer):
		_wanderer = _find_wanderer()
	if lift_radius_enabled and _wanderer != null:
		_set_near(anchor.distance_to(_wanderer.global_position) <= lift_radius)

	# Exactly one of the two is ever on screen. The quad holds the far end
	# alone; the instant the lift starts it hands over to the CardView,
	# which picks up at the quad's own projected position and apparent size
	# (see _quad_match_scale()), so the swap reads as the card growing out
	# of the object rather than as one thing replacing another.
	var lifted: bool = _lift > 0.001
	if _quad != null:
		_quad.visible = not lifted

	# Behind the camera unprojects to a mirrored on-screen point, which
	# would park the card at a plausible-looking but wrong position rather
	# than hiding it.
	if lifted and not camera.is_position_behind(anchor):
		_card_view.visible = true
		_apply_transform(camera, anchor)
	else:
		_card_view.visible = false

# The card stays at the anchor's DEPTH throughout - it slides across the
# frame, it doesn't travel toward the camera - so one apparent size and
# one pixels-per-metre serve the whole move.
func _apply_transform(camera: Camera3D, anchor: Vector3) -> void:
	var distance: float = camera.global_position.distance_to(anchor)
	var apparent: float = DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	var pixels_per_metre: float = _pixels_per_metre(camera, anchor)
	# Far end is whatever scale makes the CardView cover the quad exactly;
	# near end is the authored near_scale, distance-corrected the way the
	# other floating readouts are, times the hover growth.
	var far_end: float = _quad_match_scale(pixels_per_metre)
	var near_end: float = near_scale * apparent * _hover_scale()
	var final_scale: float = lerpf(far_end, near_end, _lift)
	_card_view.scale = Vector2.ONE * final_scale

	var anchor_screen: Vector2 = camera.unproject_position(anchor)
	var half: Vector2 = _card_view.card_size * final_scale / 2.0
	# Far end: dead on the anchor, covering the quad it replaced.
	var far_centre: Vector2 = anchor_screen
	# Near end: clear of the holder's silhouette to the right, and level
	# with the hand. The silhouette edge is measured from the HOLDER's own
	# screen position, not the anchor's - the anchor is the hand, which is
	# already off-centre, so measuring from it would shift the gap by
	# however far she happens to be reaching.
	# Height is set by the BOTTOM edge, not the centre: project a point
	# near_bottom_height above the holder's feet, put the card's lower edge
	# on it, and let the top land where the card's own height takes it.
	# Screen y grows downward, so the centre is half a card ABOVE that.
	# The card's DEPTH is still the anchor's: it moves in the frame, it
	# doesn't come toward the camera, so the scale computed above stays
	# right.
	var near_centre: Vector2 = Vector2(
		_silhouette_right_edge(camera, pixels_per_metre) + screen_gap_px + half.x,
		camera.unproject_position(_holder_feet() + Vector3.UP * near_bottom_height).y - half.y)
	_card_view.position = (far_centre.lerp(near_centre, _lift) - half).round()

# The holder's own origin, which is at her feet (the glb's origin is at
# the feet and Keeper grounds that origin onto the relief). Falls back to
# the anchor, which only makes the bottom edge relative to the hand.
func _holder_feet() -> Vector3:
	var holder := get_node_or_null(holder_path) as Node3D
	return holder.global_position if holder != null else anchor_position()

# Screen x of the holder's right-hand silhouette edge, at the anchor's
# depth. Falls back to the anchor itself if there's no holder to measure,
# which just makes the gap measured from the hand instead.
func _silhouette_right_edge(camera: Camera3D, pixels_per_metre: float) -> float:
	var holder := get_node_or_null(holder_path) as Node3D
	if holder == null:
		return camera.unproject_position(anchor_position()).x
	return camera.unproject_position(holder.global_position).x + _holder_half_width * pixels_per_metre

# Pixels one metre covers at this depth. Projecting two points a metre
# apart rather than reading the camera's focal length keeps this correct
# for any fov or viewport size without duplicating the projection maths.
func _pixels_per_metre(camera: Camera3D, target: Vector3) -> float:
	var right: Vector3 = camera.global_transform.basis.x
	return camera.unproject_position(target).distance_to(camera.unproject_position(target + right))

# The CardView scale at which it covers the same screen width the quad
# does at this depth. Derived, never authored: the quad is quad_size.x
# metres wide and the CardView is card_size.x pixels wide at scale 1.
func _quad_match_scale(pixels_per_metre: float) -> float:
	if pixels_per_metre <= 0.0 or _card_view.card_size.x <= 0.0:
		return 0.0
	return quad_size.x * pixels_per_metre / _card_view.card_size.x

# 1 at rest, hover_scale when hovered. The SCALE is this node's own (a
# card in the world is read at a distance and needs a bigger jump than
# one already filling the hand), but the DURATION still comes off the
# CardView, so the two grow at the same rate even at different sizes.
func _hover_scale() -> float:
	return lerpf(1.0, hover_scale, _hover)

func _on_card_mouse_entered() -> void:
	_tween_hover(1.0)

func _on_card_mouse_exited() -> void:
	_tween_hover(0.0)

func _tween_hover(to: float) -> void:
	if _card_view == null or _taking:
		return
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_hover_tween.tween_property(self, "_hover", to, _card_view.hover_duration_sec)

# Lift this card from outside, for a holder that decides for a GROUP -
# a RewardSpread measures once from the spread's centre and pushes the
# same answer into all three, so they rise together instead of each
# crossing its own radius a step apart. Turn lift_radius_enabled off
# alongside, or the card's own per-frame check fights this every frame.
func set_lifted(lifted: bool) -> void:
	_set_near(lifted)

func _set_near(near: bool) -> void:
	if near == _near:
		return
	_near = near
	# Dropping back to far hides the CardView, and a Control that stops
	# being visible under the cursor doesn't reliably get mouse_exited -
	# without this the card would come back next approach already grown.
	if not near:
		_tween_hover(0.0)
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_lift_tween.tween_property(self, "_lift", 1.0 if near else 0.0, lift_duration_sec)

# Only a lifted card takes a click - a far card is scenery, and clicking
# through it would otherwise swallow a point-to-move click on the sand
# behind it (CardView's own mouse_filter is STOP).
func _on_card_gui_input(event: InputEvent) -> void:
	if _taking or _dismissing or not _near:
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_take()

# Not taken - withdrawn. The card settles back to its quad first and only
# then fades, so it never dissolves in mid-air: a card you didn't choose
# should be seen being put down. Frees itself at the end, which is what
# lets a RewardSpread free itself simply by noticing it has no cards
# left. Immediate if it wasn't lifted (nothing to settle).
func dismiss() -> void:
	if _taking or _dismissing:
		return
	_dismissing = true
	if _card_view != null:
		_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var settle: float = lift_duration_sec if _lift > 0.001 else 0.0
	_set_near(false)
	var tween := create_tween()
	tween.tween_interval(settle)
	tween.tween_callback(_fade_quad_and_free)

# The quad is unlit and opaque; fading it means opting into the
# transparent pipeline for these last 0.6 s only, which is why this isn't
# just set up front in _spawn_quad().
func _fade_quad_and_free() -> void:
	if _quad_material == null:
		queue_free()
		return
	_quad_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var tween := create_tween()
	tween.tween_property(_quad_material, "albedo_color:a", 0.0, dismiss_fade_sec)
	tween.tween_callback(queue_free)

func _take() -> void:
	if _taking or card == null:
		return
	_taking = true
	RunState.add_card(card)
	taken.emit(card)
	_fly_to_deck()

# To the Belongings panel it just incremented. Frees this whole node at
# the end rather than only the CardView - the anchor has nothing left to
# hold.
func _fly_to_deck() -> void:
	if _card_view == null:
		queue_free()
		return
	_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var destination: Vector2 = _deck_panel_centre()
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(true)
	tween.tween_property(_card_view, "position", destination - _card_view.card_size * flight_end_scale / 2.0, flight_duration_sec)
	tween.tween_property(_card_view, "scale", Vector2.ONE * flight_end_scale, flight_duration_sec)
	tween.tween_property(_card_view, "modulate:a", 0.0, flight_duration_sec)
	tween.chain().tween_callback(queue_free)

func _deck_panel_centre() -> Vector2:
	var region_field: Node = get_node_or_null(region_field_path)
	var panel: Control = null
	if region_field != null:
		panel = region_field.get_node_or_null(^"FieldHUD/DeckPanel") as Control
	if panel == null:
		push_warning("WorldCard: no FieldHUD/DeckPanel to fly to; dropping the card off-screen instead.")
		return _card_view.position + Vector2(0.0, float(get_viewport().get_visible_rect().size.y))
	return panel.get_global_rect().get_center()
