extends Node3D
class_name WorldKeepsake

# One keepsake held out in the world - the Keeper's today - in the two
# states WorldCard established, driven by the Wanderer's distance to a 3D
# anchor:
#
#   FAR  - a small bone square in the holder's hand: unlit, billboarded
#          about Y only, the same quad WorldCard draws but object-shaped
#          rather than card-shaped. Something is being held out.
#   NEAR - inside lift_radius the square hands over to a plaque on a
#          CanvasLayer, growing out of the square's own projected size and
#          position beside the holder's silhouette, level with her
#          - never over her, never full-screen, the camera untouched.
#
# The plaque is an inspection, not a card: no cost, no type, no rarity,
# no card frame. Top to bottom -
#   its name        Spectral, centred
#   the object      TrinketData.art in a square, or an empty keyline
#                   square while there is no art
#   its flavour     TrinketData.flavor_text, slanted, quiet
#   what it does    TrinketData.describe(), between two printed rules
#   the action      TAKE with the slot empty; with one held, REPLACE
#                   <held> and KEEP <held> - so what taking costs is said
#                   before the click, not after. The title menu's
#                   treatment (TitleMenu): tracked caps, the focused
#                   option in ink with a short hairline to its left, the
#                   others in the utility grey. No plate, no box.
#
# Lifted, the plaque is drawn at lifted_scale - absolute, not distance-
# corrected, so its rules text is always description_size_px x
# lifted_scale on screen: 16 px at 1.0, over a card's rules text in the
# hand at rest (CardView.rules_font_sizes[0] 15 x HandContainer.hand_card_
# scale 0.95 = 14.25 px).
#
# Nothing is granted by walking into range: only a click on the action
# resolves it. Resolving is final either way - the one-slot rule
# KeepsakeOffer already keeps (TAKE equips, the held one is gone; KEEP
# leaves this one behind) - and the offer is noted against the run
# (RunState.note_keepsake_offered()). `resolved` fires after that, and the
# plaque fades where it stands; whoever spawned this (Keeper) decides what
# resolving MEANS. Walking away without choosing resolves nothing: the
# plaque settles back into the square and waits.
#
# A second copy of WorldCard's projection and lift, not a shared helper -
# two consumers (see CLAUDE.md on extracting at the third).

signal resolved(taken: bool)

enum Choice { TAKE, KEEP }

const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"

@export var keepsake: TrinketData = null:
	set(value):
		keepsake = value
		_layout()

# Anchor = this node's origin plus this, in its local space (WorldCard's
# own meaning).
@export var anchor_offset: Vector3 = Vector3.ZERO:
	set(value):
		anchor_offset = value
		_apply_quad()
# The plaque stands this many pixels clear of the holder's projected
# silhouette edge, its bottom edge on a point near_bottom_height above
# her feet - WorldCard's placement rule and its reasons. Her screen-right
# by default; her screen-left when the Wanderer is on her screen-right,
# so it never sits over him (see _choose_side()). Her edge is her
# meshes' bounds projected (see _silhouette_edge()), not a half-width
# off her origin, so her hair tips are inside it from every angle.
@export var screen_gap_px: float = 40.0
@export var near_bottom_height: float = 0.15
# 0 (the default) = her edge is her meshes' own bounds, measured once
# and projected each frame. Set non-zero to place from her origin plus
# this many metres instead (WorldCard's rule).
@export var holder_half_width: float = 0.0
@export var holder_path: NodePath = ^".."
@export var lift_radius: float = 2.5
@export var lift_duration_sec: float = 0.18
# The whole plaque's scale once lifted - name, flavour, rules and the
# choices together. Read every physics frame, so a Remote-tab edit shows
# at once; the setter re-places it straight away for a frozen field too.
@export var lifted_scale: float = 1.0:
	set(value):
		lifted_scale = maxf(value, 0.01)
		_reapply_transform()

@export_group("Far Quad")
# Square: an object, not a card.
@export var quad_size: Vector2 = Vector2(0.07, 0.07):
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
@export var quad_texture_width_px: int = 12:
	set(value):
		quad_texture_width_px = value
		_apply_quad()
@export_group("")

# The plaque's look: KeepsakeOffer's bone and ink, its frame and rule
# alphas, at inspection size.
@export_group("Plaque")
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_redraw()
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_redraw()
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_redraw()
@export var plaque_width_px: float = 280.0:
	set(value):
		plaque_width_px = value
		_layout()
@export var padding_px: float = 20.0:
	set(value):
		padding_px = value
		_layout()
@export var corner_radius_px: int = 4:
	set(value):
		corner_radius_px = value
		_redraw()
@export_range(0.0, 1.0) var frame_alpha: float = 0.88:
	set(value):
		frame_alpha = value
		_redraw()
@export_range(0.0, 1.0) var rule_alpha: float = 0.25:
	set(value):
		rule_alpha = value
		_redraw()
@export var shadow_size_px: int = 12:
	set(value):
		shadow_size_px = value
		_redraw()
@export_range(0.0, 1.0) var shadow_alpha: float = 0.22:
	set(value):
		shadow_alpha = value
		_redraw()
@export var name_size_px: int = 24:
	set(value):
		name_size_px = value
		_layout()
@export var art_size_px: float = 72.0:
	set(value):
		art_size_px = value
		_layout()
@export var section_gap_px: float = 12.0:
	set(value):
		section_gap_px = value
		_layout()
# The empty art square's keyline and wash - a neutral placeholder until
# the object has art of its own.
@export_range(0.0, 1.0) var placeholder_line_alpha: float = 0.25:
	set(value):
		placeholder_line_alpha = value
		_redraw()
@export_range(0.0, 1.0) var placeholder_fill_alpha: float = 0.05:
	set(value):
		placeholder_fill_alpha = value
		_redraw()
@export var flavor_size_px: int = 15:
	set(value):
		flavor_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var flavor_alpha: float = 0.62:
	set(value):
		flavor_alpha = value
		_redraw()
# The flavour line's lean - a slanted AlegreyaSans, since the project
# ships no italic face. 0 sets it upright.
@export_range(-0.5, 0.5, 0.01) var flavor_slant: float = 0.2:
	set(value):
		flavor_slant = value
		_rebuild_fonts()
@export var description_size_px: int = 16:
	set(value):
		description_size_px = value
		_layout()
@export var line_pitch_em: float = 1.3:
	set(value):
		line_pitch_em = value
		_layout()
@export_group("")

@export_group("Actions")
@export var take_text: String = "TAKE":
	set(value):
		take_text = value
		_layout()
# %s is the held keepsake's name, upper-cased.
@export var replace_format: String = "REPLACE %s":
	set(value):
		replace_format = value
		_layout()
@export var keep_format: String = "KEEP %s":
	set(value):
		keep_format = value
		_layout()
@export var action_size_px: int = 14:
	set(value):
		action_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var caps_tracking_em: float = 0.16:
	set(value):
		caps_tracking_em = value
		_rebuild_fonts()
# One choice's row - its hit area too, the plaque's full inner width.
@export var action_row_height_px: float = 28.0:
	set(value):
		action_row_height_px = value
		_layout()
@export var action_gap_px: float = 4.0:
	set(value):
		action_gap_px = value
		_layout()
# The focus hairline: TitleMenu's 28 px long, 14 px clear of the text at
# its 22 px items, kept in proportion at action_size_px.
@export var focus_hairline_length_px: float = 18.0:
	set(value):
		focus_hairline_length_px = value
		_redraw()
@export var focus_hairline_gap_px: float = 9.0:
	set(value):
		focus_hairline_gap_px = value
		_redraw()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_redraw()
@export var take_volume_db: float = -18.0
# How long the plaque (and the square under it) take to fade once
# resolved.
@export var resolve_fade_sec: float = 0.45
@export_group("")

var _layer: CanvasLayer = null
var _plaque: Control = null
var _quad: MeshInstance3D = null
var _quad_mesh: QuadMesh = null
var _quad_material: StandardMaterial3D = null
var _wanderer: Node3D = null
var _lift: float = 0.0
var _lift_tween: Tween = null
var _near: bool = false
# Which side of her the lifted plaque stands: 1 her screen-right, -1 her
# screen-left. Chosen once as it lifts (_choose_side()) and held until it
# lowers, so it never swaps sides while he moves about in front of it.
var _side: int = 1
var _resolving: bool = false
# Her meshes' bounds in her own space - the figure's, not the shadow
# disc or this node's square. Measured once: the model doesn't change
# size, and the hem wind only moves vertices.
var _holder_box: AABB = AABB()

var _name_font: Font = null
var _text_font: Font = null
var _flavor_font: Font = null
var _action_font: Font = null

# Plaque-space layout, from _layout().
var _plaque_size: Vector2 = Vector2.ZERO
var _name_baseline: float = 0.0
var _art_rect: Rect2 = Rect2()
var _flavor: TextParagraph = null
var _flavor_top: float = 0.0
var _rule_top_y: float = 0.0
var _description: TextParagraph = null
var _description_top: float = 0.0
var _rule_bottom_y: float = 0.0
# One row per choice, in Choice order.
var _action_rects: Array[Rect2] = []
# The focused Choice. TAKE on every lift, as the title menu opens on its
# first item; the mouse moves it, and leaving the plaque leaves it where
# it was.
var _focus: int = Choice.TAKE

func _ready() -> void:
	# After CameraRig has placed the camera this frame (WorldCard's reason).
	process_priority = 1
	if keepsake == null:
		push_warning("WorldKeepsake: spawned with no keepsake; freeing rather than holding out nothing.")
		queue_free()
		return
	_spawn_quad()
	_layer = CanvasLayer.new()
	_layer.name = "KeepsakeLayer"
	add_child(_layer)
	_plaque = Control.new()
	_plaque.name = "Plaque"
	_plaque.mouse_filter = Control.MOUSE_FILTER_STOP
	_plaque.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_plaque.draw.connect(_draw_plaque)
	_plaque.gui_input.connect(_on_plaque_gui_input)
	_plaque.visible = false
	_layer.add_child(_plaque)
	_rebuild_fonts()
	# The actions name what's held, and that can change while she waits
	# (a Wardling's drop taken between visits).
	RunState.keepsake_changed.connect(_on_keepsake_changed)
	_wanderer = _find_wanderer()
	_holder_box = _measure_holder_box()

func _on_keepsake_changed(_held_now: TrinketData) -> void:
	_layout()

# --- Far quad (WorldCard's, square) ---

func _spawn_quad() -> void:
	_quad = MeshInstance3D.new()
	_quad.name = "FarQuad"
	_quad_mesh = QuadMesh.new()
	_quad.mesh = _quad_mesh
	_quad_material = StandardMaterial3D.new()
	_quad_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_quad_material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_quad_material.billboard_keep_scale = true
	_quad_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_quad_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_quad.material_override = _quad_material
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_quad)
	_apply_quad()

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

# --- The plaque ---

func _rebuild_fonts() -> void:
	_name_font = InkType.numeral_font()
	_text_font = InkType.text_font()
	var slanted := FontVariation.new()
	slanted.base_font = InkType.text_font()
	# x_axis.y is the slant (FontVariation.variation_transform's own doc).
	slanted.variation_transform = Transform2D(Vector2(1.0, flavor_slant), Vector2(0.0, 1.0), Vector2.ZERO)
	_flavor_font = slanted
	_action_font = InkType.tracked(InkType.text_bold_font(), action_size_px, caps_tracking_em)
	_layout()

func _pitch(size_px: int) -> float:
	return roundf(float(size_px) * line_pitch_em)

func _held() -> TrinketData:
	var held: TrinketData = RunState.keepsake
	return held if held != keepsake else null

# How many actions the plaque offers: TAKE alone into an empty slot,
# REPLACE and KEEP with one held.
func choice_count() -> int:
	return 2 if _held() != null else 1

func _choice_label(index: int) -> String:
	var held: TrinketData = _held()
	if index == Choice.TAKE:
		return take_text if held == null else replace_format % held.display_name.to_upper()
	return keep_format % held.display_name.to_upper() if held != null else ""

func _layout() -> void:
	if _plaque == null or keepsake == null or _text_font == null:
		return
	var inner: float = plaque_width_px - padding_px * 2.0
	var y: float = padding_px
	_name_baseline = y + float(name_size_px)
	y = _name_baseline + section_gap_px
	_art_rect = Rect2(roundf((plaque_width_px - art_size_px) / 2.0), y, art_size_px, art_size_px)
	y = _art_rect.end.y + section_gap_px
	_flavor = null
	_flavor_top = y
	if not keepsake.flavor_text.is_empty():
		_flavor = TextParagraph.new()
		_flavor.width = inner
		_flavor.add_string(keepsake.flavor_text, _flavor_font, flavor_size_px)
		y += _pitch(flavor_size_px) * _flavor.get_line_count() + section_gap_px * 0.5
	_rule_top_y = roundf(y)
	y = _rule_top_y + section_gap_px
	_description = TextParagraph.new()
	_description.width = inner
	_description.add_string(keepsake.describe(), _text_font, description_size_px)
	_description_top = y - 4.0
	y += _pitch(description_size_px) * _description.get_line_count() + section_gap_px * 0.5
	_rule_bottom_y = roundf(y)
	y = _rule_bottom_y + section_gap_px * 0.5
	_action_rects.clear()
	for index in choice_count():
		_action_rects.append(Rect2(padding_px, roundf(y), inner, action_row_height_px))
		y += action_row_height_px + action_gap_px
	y -= action_gap_px
	if _focus >= choice_count():
		_focus = Choice.TAKE
	_plaque_size = Vector2(plaque_width_px, roundf(y + padding_px))
	_plaque.size = _plaque_size
	_redraw()

func _redraw() -> void:
	if _plaque != null:
		_plaque.queue_redraw()

func _text_centred(font: Font, text: String, baseline: float, size_px: int, color: Color) -> void:
	var left: float = roundf((_plaque_size.x - InkType.width(font, text, size_px)) / 2.0)
	InkType.draw_run(_plaque, font, text, Vector2(left, baseline), size_px, color)

# Each line centred by its own width, as KeepsakeOffer draws its own.
func _paragraph_centred(paragraph: TextParagraph, top: float, size_px: int, color: Color) -> void:
	var y: float = top
	for line_index in paragraph.get_line_count():
		y += _pitch(size_px)
		var left: float = roundf((_plaque_size.x - paragraph.get_line_width(line_index)) / 2.0)
		paragraph.draw_line(_plaque.get_canvas_item(), Vector2(left, y - paragraph.get_line_ascent(line_index)), line_index, color)

func _rule(y: float) -> void:
	_plaque.draw_rect(Rect2(padding_px, y, _plaque_size.x - padding_px * 2.0, hairline_thickness_px), Color(ink, rule_alpha))

func _draw_plaque() -> void:
	if keepsake == null or _description == null:
		return
	var rect := Rect2(Vector2.ZERO, _plaque_size)
	var body := StyleBoxFlat.new()
	body.bg_color = bone
	body.set_corner_radius_all(corner_radius_px)
	body.set_border_width_all(1)
	body.border_color = Color(ink, frame_alpha)
	body.shadow_color = Color(0.0, 0.0, 0.0, shadow_alpha)
	body.shadow_size = shadow_size_px
	body.shadow_offset = Vector2(0.0, 4.0)
	_plaque.draw_style_box(body, rect)

	_text_centred(_name_font, keepsake.display_name, _name_baseline, name_size_px, ink)
	if keepsake.art != null:
		_plaque.draw_texture_rect(keepsake.art, _art_rect, false)
	else:
		_plaque.draw_rect(_art_rect, Color(ink, placeholder_fill_alpha))
		_plaque.draw_rect(_art_rect, Color(ink, placeholder_line_alpha), false, hairline_thickness_px)
	if _flavor != null:
		_paragraph_centred(_flavor, _flavor_top, flavor_size_px, Color(ink, flavor_alpha))
	_rule(_rule_top_y)
	_paragraph_centred(_description, _description_top, description_size_px, ink)
	_rule(_rule_bottom_y)
	_draw_actions()

# TitleMenu's treatment: each choice centred on its row in tracked caps,
# the focused one in ink with a short hairline to its left, the others in
# the utility grey. Nothing else marks it.
func _draw_actions() -> void:
	for index in _action_rects.size():
		var row: Rect2 = _action_rects[index]
		var label: String = _choice_label(index)
		var width: float = InkType.width(_action_font, label, action_size_px)
		var left: float = roundf(row.get_center().x - width / 2.0)
		var baseline: float = roundf(row.get_center().y + float(action_size_px) * 0.35)
		var focused: bool = index == _focus
		InkType.draw_run(_plaque, _action_font, label, Vector2(left, baseline), action_size_px, ink if focused else unfocused_color)
		if focused:
			var hairline_y: float = roundf(baseline - float(action_size_px) * 0.35 - hairline_thickness_px * 0.5)
			_plaque.draw_rect(Rect2(left - focus_hairline_gap_px - focus_hairline_length_px, hairline_y, focus_hairline_length_px, hairline_thickness_px), ink)

# --- Placement (WorldCard's) ---

func _find_wanderer() -> Node3D:
	var found: Array[Node] = get_tree().get_nodes_in_group("wanderer")
	return found[0] as Node3D if not found.is_empty() else null

func _measure_holder_box() -> AABB:
	var holder := get_node_or_null(holder_path) as Node3D
	if holder == null:
		return AABB()
	var union := AABB()
	var have: bool = false
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null or mesh_instance is ContactShadow or is_ancestor_of(mesh_instance):
			continue
		var box: AABB = holder.global_transform.affine_inverse() * (mesh_instance.global_transform * mesh_instance.get_aabb())
		union = box if not have else union.merge(box)
		have = true
	return union

func anchor_position() -> Vector3:
	return global_transform * anchor_offset

func _physics_process(_delta: float) -> void:
	if _plaque == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var anchor: Vector3 = anchor_position()
	if _wanderer == null or not is_instance_valid(_wanderer):
		_wanderer = _find_wanderer()
	if _wanderer != null and not _resolving:
		_set_near(anchor.distance_to(_wanderer.global_position) <= lift_radius)
	var lifted: bool = _lift > 0.001
	if _quad != null and not _resolving:
		_quad.visible = not lifted
	if lifted and not camera.is_position_behind(anchor):
		_plaque.visible = true
		_apply_transform(camera, anchor)
	else:
		_plaque.visible = false

# Grows from exactly the square's projected width to lifted_scale, and
# comes up in opacity with it, so the plaque reads as the object opening
# out rather than a panel popping in.
func _apply_transform(camera: Camera3D, anchor: Vector3) -> void:
	var pixels_per_metre: float = _pixels_per_metre(camera, anchor)
	var far_end: float = quad_size.x * pixels_per_metre / maxf(_plaque_size.x, 1.0)
	var final_scale: float = lerpf(far_end, lifted_scale, _lift)
	_plaque.scale = Vector2.ONE * final_scale
	if not _resolving:
		_plaque.modulate.a = _lift
	var anchor_screen: Vector2 = camera.unproject_position(anchor)
	var half: Vector2 = _plaque_size * final_scale / 2.0
	var near_centre: Vector2 = Vector2(
		_silhouette_edge(camera, pixels_per_metre, _side) + float(_side) * (screen_gap_px + half.x),
		camera.unproject_position(_holder_feet() + Vector3.UP * near_bottom_height).y - half.y)
	_plaque.position = (anchor_screen.lerp(near_centre, _lift) - half).round()

# A lifted_scale edit lands on the next physics frame on a live field;
# this places it at once, frozen or not.
func _reapply_transform() -> void:
	if _plaque == null or not _plaque.visible or not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		_apply_transform(camera, anchor_position())

func _holder_feet() -> Vector3:
	var holder := get_node_or_null(holder_path) as Node3D
	return holder.global_position if holder != null else anchor_position()

# Screen x of the holder's edge on `side` (1 right, -1 left): the
# outermost of her bounds' eight corners, projected. Origin plus
# holder_half_width when that's set; the anchor with no holder.
func _silhouette_edge(camera: Camera3D, pixels_per_metre: float, side: int) -> float:
	var holder := get_node_or_null(holder_path) as Node3D
	if holder == null:
		return camera.unproject_position(anchor_position()).x
	if holder_half_width > 0.0 or not _holder_box.has_volume():
		return camera.unproject_position(holder.global_position).x + float(side) * holder_half_width * pixels_per_metre
	var edge: float = camera.unproject_position(holder.global_transform * _holder_box.get_endpoint(0)).x
	for corner in range(1, 8):
		var x: float = camera.unproject_position(holder.global_transform * _holder_box.get_endpoint(corner)).x
		edge = maxf(edge, x) if side > 0 else minf(edge, x)
	return edge

# Her screen-right unless the Wanderer stands to her screen-right - his
# origin's projection against hers - in which case her screen-left.
func _choose_side() -> void:
	_side = 1
	var camera := get_viewport().get_camera_3d()
	var holder := get_node_or_null(holder_path) as Node3D
	if camera == null or holder == null or _wanderer == null or not is_instance_valid(_wanderer):
		return
	if camera.unproject_position(_wanderer.global_position).x > camera.unproject_position(holder.global_position).x:
		_side = -1

func _pixels_per_metre(camera: Camera3D, target: Vector3) -> float:
	var right: Vector3 = camera.global_transform.basis.x
	return camera.unproject_position(target).distance_to(camera.unproject_position(target + right))

func _set_near(near: bool) -> void:
	if near == _near:
		return
	_near = near
	if near:
		# The slot may have changed since she was last approached.
		_focus = Choice.TAKE
		_layout()
		# Only from the square: a plaque still on its way down keeps its
		# side if he steps back in, rather than jumping across her.
		if _lift <= 0.001:
			_choose_side()
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_lift_tween = create_tween()
	_lift_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_lift_tween.tween_property(self, "_lift", 1.0 if near else 0.0, lift_duration_sec)

# The field's freeze (a fight, a reward screen) stops _physics_process;
# the plaque drops back to the square outright so it can't hang over the
# battle - WorldCard._drop_for_freeze()'s reason. A resolving plaque is
# left to finish its fade.
func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED:
		_drop_for_freeze()

func _drop_for_freeze() -> void:
	if _plaque == null or _resolving:
		return
	if _lift_tween != null and _lift_tween.is_valid():
		_lift_tween.kill()
	_near = false
	_lift = 0.0
	_plaque.visible = false
	if _quad != null and is_instance_valid(_quad):
		_quad.visible = true

# --- Input ---

func _hit(position: Vector2) -> int:
	for index in _action_rects.size():
		if _action_rects[index].has_point(position):
			return index
	return -1

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	_focus = index
	_redraw()

# Only a lifted plaque takes a click. The plaque's STOP filter keeps a
# click on it from reaching the field's point-to-move either way.
func _on_plaque_gui_input(event: InputEvent) -> void:
	if _resolving or not _near:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _hit(motion.position)
		if under >= 0:
			_set_focus(under)
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	var index: int = _hit(button.position)
	if index >= 0:
		_activate(index)
	_plaque.accept_event()

# The one gate: the first activation wins. TAKE (or REPLACE) puts this in
# the slot - whatever was held is gone for the run; KEEP changes nothing.
# Either way it has been offered.
func _activate(index: int) -> void:
	if _resolving or index < 0 or index >= choice_count():
		return
	_resolving = true
	var held: TrinketData = _held()
	RunState.note_keepsake_offered(keepsake)
	var taken: bool = index == Choice.TAKE
	RunLogger.event("keepsake_offer", {
		"source": "Keeper",
		"offered": RunLogger.keepsake_id(keepsake),
		"held": RunLogger.keepsake_id(held),
		"taken": taken,
	})
	if taken:
		RunState.equip_keepsake(keepsake)
		TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "KeepsakeTakeAudio", "WorldKeepsake")
		print("WorldKeepsake: took '%s'%s." % [keepsake.display_name, " (left '%s')" % held.display_name if held != null else ""])
	else:
		print("WorldKeepsake: left '%s' (kept '%s')." % [keepsake.display_name, held.display_name])
	resolved.emit(taken)
	_fade_and_free()

# The plaque fades where it stands, and the square with it - nothing
# flies anywhere: a keepsake has no deck to fly to.
func _fade_and_free() -> void:
	if _quad != null:
		_quad.visible = false
	var tween := create_tween()
	if _plaque != null and _plaque.visible:
		tween.tween_property(_plaque, "modulate:a", 0.0, maxf(resolve_fade_sec, 0.01))
	else:
		tween.tween_interval(0.0)
	tween.tween_callback(queue_free)
