extends Control
class_name TroughChoice

# A field prop's choices, shown beside it on the world - LootScreen's
# column without its item row: no scrim, no header, and the field never
# stops. The trough (TroughProp) and floor 4's pup (DunecurPup) open it
# from a click on themselves in reach and parent it under FieldHUD.
#
# The host is any Node3D that answers three calls: get_choice_labels()
# -> Array[String], its items top to bottom, the last always the one
# that leaves it be ("Leave it"); choose(index) for the one activated;
# and can_open_from(Vector3), its reach. The host does what a choice
# means, logs it, and says any line - this only shows and picks. A host
# may also answer is_choice_enabled(index) -> bool: an item it says no to
# shows, fainter (disabled_ink_alpha), but focus passes over it and a
# click on it does nothing.
#
# Placed every physics tick the way LootScreen is: the anchor - the
# host plus anchor_offset, x metres along the camera's right (or left)
# and y metres up - is unprojected, and this control's scale follows
# camera distance (DistanceScale). The anchor is the column's inner edge
# - its left on the host's right, its right on the host's left - level
# with its middle, and the column is kept on screen inside screen_
# margin_px.
#
# Which side: chosen once, on the first tick it shows (_choose_side()).
# Each side's column - its wash included - is scored on the screen for
# what it would stand over: the host itself and every prop (host_weight,
# prop_weight, by the share of the column each covers), each scatter
# item within scatter_reach_m of the host (scatter_weight apiece), and -
# far heavier - the Wanderer, the HUD's own controls and the screen's
# edge (avoid_weight). The lower score wins; even, the right.
#
# The items stacked one above another in the title menu's focus
# language, LootScreen's: the focused item in full ink (the Battle ink
# token) with a short dash to its left, the others in the same ink a
# little lighter (unfocused_ink_alpha) with none. Behind them all one
# faint wash, FindLine's: feathered on every edge, no box, no border,
# pale behind a dark ink (dark behind a light one), so the words read
# over grass, rock or damp ground alike. The first has focus on open.
# ui_up/ui_down move it (wrapping), ui_accept activates; hovering an
# item focuses it and a click activates. ui_cancel and a right click
# anywhere are the last item, and that right click is spent on closing.
# The items are the only things here that stop the mouse.
#
# Any item closes it once chosen. Walking out of the host's reach or the
# field freezing closes it with nothing chosen: the next click on the
# host opens it again.

signal closed()

# x: metres along the camera's right (or left) from the host; y: metres
# up.
@export var anchor_offset: Vector2 = Vector2(0.8, 0.6)
@export var text_outline_px: int = 0
@export var open_fade_sec: float = 0.18

@export_group("Choices")
@export var choice_size_px: int = 33:
	set(value):
		choice_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var choice_tracking_em: float = 0.03:
	set(value):
		choice_tracking_em = value
		_rebuild_fonts()
@export var choice_gap_px: float = 22.0:
	set(value):
		choice_gap_px = value
		queue_redraw()
# An item without focus: the same ink at this alpha - a step back, never
# faint.
@export_range(0.0, 1.0) var unfocused_ink_alpha: float = 0.72:
	set(value):
		unfocused_ink_alpha = value
		queue_redraw()
# An item the host has disabled: the same ink at this alpha - shown, and
# plainly not on offer.
@export_range(0.0, 1.0) var disabled_ink_alpha: float = 0.32:
	set(value):
		disabled_ink_alpha = value
		queue_redraw()
@export var hairline_length_px: float = 36.0:
	set(value):
		hairline_length_px = value
		queue_redraw()
@export var hairline_gap_px: float = 16.0:
	set(value):
		hairline_gap_px = value
		queue_redraw()
@export var hairline_thickness_px: float = 3.0:
	set(value):
		hairline_thickness_px = value
		queue_redraw()
@export_group("")

# The wash behind the column, FindLine's: wash_color behind a dark ink
# (the pale world), wash_color_on_light_ink behind a light one, at
# wash_opacity at most - wash_pad_px beyond the column each side, full
# strength over the inner wash_solid_share of that reach and easing to
# nothing at its edge.
@export_group("Wash")
@export var wash_color: Color = Color(0.93, 0.91, 0.86):
	set(value):
		wash_color = value
		queue_redraw()
@export var wash_color_on_light_ink: Color = Color(0.16, 0.16, 0.15):
	set(value):
		wash_color_on_light_ink = value
		queue_redraw()
@export_range(0.0, 1.0) var wash_opacity: float = 0.3:
	set(value):
		wash_opacity = value
		queue_redraw()
@export var wash_pad_px: Vector2 = Vector2(84.0, 46.0):
	set(value):
		wash_pad_px = value
		queue_redraw()
@export_range(0.0, 0.95) var wash_solid_share: float = 0.15:
	set(value):
		wash_solid_share = value
		_build_wash()
		queue_redraw()
@export_group("")

# The side's score (see the header). The next open scores again.
@export_group("Side")
@export var scatter_reach_m: float = 12.0
@export var scatter_weight: float = 1.0
@export var prop_weight: float = 40.0
@export var host_weight: float = 60.0
@export var avoid_weight: float = 1000.0
@export var screen_margin_px: float = 24.0:
	set(value):
		screen_margin_px = value
		queue_redraw()
# A HUD control covering more of the screen than this share is a layer
# over it all (a full-screen root), not a thing to keep off.
@export_range(0.0, 1.0) var hud_max_share: float = 0.4
@export_group("")

# Apparent-size correction, LootScreen's knobs and defaults.
@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0
@export_group("")

const THEME_PATH := "res://ui/battle_theme.tres"

var _host: Node3D = null
var _wanderer: Node3D = null
var _region_field: Node = null
var _focused: int = 0
var _done: bool = false
var _closing: bool = false
var _choices: Array[Control] = []
var _choice_font: Font = null
# +1: the host's right on screen; -1: its left. 0 until chosen.
var _side: int = 0
var _wash_texture: GradientTexture2D = null

# Called by the host before this enters the tree.
func setup(host: Node3D, wanderer: Node3D, region_field: Node) -> void:
	_host = host
	_wanderer = wanderer
	_region_field = region_field

func _ready() -> void:
	# After CameraRig has placed the camera this tick (EnemyStatus's reason).
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = load(THEME_PATH) as Theme
	_rebuild_fonts()
	_build_wash()

	var labels: Array[String] = _labels()
	for index in labels.size():
		var choice := Control.new()
		choice.name = "Choice%d" % index
		choice.mouse_filter = Control.MOUSE_FILTER_STOP
		choice.mouse_entered.connect(_set_focus.bind(index))
		choice.gui_input.connect(_on_choice_gui_input.bind(index))
		add_child(choice)
		_choices.append(choice)

	if _host == null or labels.is_empty():
		close()
		return
	# The first item on offer has focus on open.
	_focused = _step_focus(-1, 1)

	visible = false
	modulate.a = 0.0
	if open_fade_sec > 0.0:
		create_tween().tween_property(self, "modulate:a", 1.0, open_fade_sec)
	else:
		modulate.a = 1.0

func _rebuild_fonts() -> void:
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_size_px, choice_tracking_em)
	queue_redraw()

func _labels() -> Array[String]:
	if _host == null or not is_instance_valid(_host):
		return []
	var labels: Array[String] = _host.call("get_choice_labels")
	return labels

func _leave_index() -> int:
	return maxi(_choices.size() - 1, 0)

# Whether the host offers item `index` (is_choice_enabled(), when it has
# one - else every item).
func is_enabled(index: int) -> bool:
	if _host == null or not is_instance_valid(_host) or not _host.has_method("is_choice_enabled"):
		return true
	var enabled: bool = _host.call("is_choice_enabled", index)
	return enabled

# The next item on offer from `from`, `step` at a time, wrapping - `from`
# itself when none other is.
func _step_focus(from: int, step: int) -> int:
	var count: int = _choices.size()
	for i in range(1, count + 1):
		var index: int = posmod(from + step * i, count)
		if is_enabled(index):
			return index
	return from

func _host_reaches(from: Vector3) -> bool:
	var in_reach: bool = _host.call("can_open_from", from)
	return in_reach

# The side it stands on: +1 the host's right, -1 its left, 0 before it
# has shown (for probes and stills).
func get_side() -> int:
	return _side

# --- Tick ---

func _physics_process(_delta: float) -> void:
	if _done or _closing:
		return
	if _host == null or not is_instance_valid(_host):
		close()
		return
	# The field froze under us (a fight, the floor transition) - FieldHUD
	# runs ALWAYS, so this would otherwise sit over the battle.
	if _region_field != null and is_instance_valid(_region_field) and not _region_field.can_process():
		close()
		return
	if _wanderer != null and is_instance_valid(_wanderer) and not _host_reaches(_wanderer.global_position):
		close()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	_layout()
	if _side == 0:
		_side = _choose_side(camera)
		if _side == 0:
			visible = false
			return
		_layout()
	var anchor: Vector3 = _anchor(camera, _side)
	if camera.is_position_behind(anchor):
		visible = false
		return
	visible = true
	scale = Vector2.ONE * _scale_at(camera, anchor)
	# The wash's corner where _kept_on_screen() puts it, and this control
	# back from there: a local point L shows at position + pivot + (L -
	# pivot) * scale.
	var kept: Vector2 = _kept_on_screen(_screen_rect(camera, anchor, _side)).position
	position = (kept - pivot_offset - (_wash_local_rect().position - pivot_offset) * scale.x).round()
	queue_redraw()

func _anchor(camera: Camera3D, side: int) -> Vector3:
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	return _host.global_position + right * anchor_offset.x * float(side) + Vector3.UP * anchor_offset.y

func _scale_at(camera: Camera3D, anchor: Vector3) -> float:
	var distance: float = camera.global_position.distance_to(anchor)
	return DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)

# --- Layout (local space; the anchor is pivot_offset) ---

func _choices_width() -> float:
	var widest: float = 0.0
	for label in _labels():
		widest = maxf(widest, InkType.width(_choice_font, label, choice_size_px))
	return hairline_length_px + hairline_gap_px + widest

func _choice_top(index: int) -> float:
	return float(index) * (float(choice_size_px) + choice_gap_px)

func _row_height() -> float:
	return float(choice_size_px) * 1.3

# The choices, left-aligned, the column's middle on the anchor - its left
# edge there on the host's right, its right edge on its left.
func _layout() -> void:
	size = Vector2(_choices_width(), _choice_top(_leave_index()) + _row_height())
	pivot_offset = _pivot(_side)
	for index in _choices.size():
		_choices[index].position = Vector2(0.0, _choice_top(index))
		_choices[index].size = Vector2(_choices_width(), _row_height())

func _pivot(side: int) -> Vector2:
	return Vector2(size.x if side < 0 else 0.0, size.y * 0.5)

# The column and its wash, local - what it covers on the screen.
func _wash_local_rect() -> Rect2:
	return Rect2(-wash_pad_px, size + wash_pad_px * 2.0)

# That rect on the screen with the anchor at `anchor` on `side`.
func _screen_rect(camera: Camera3D, anchor: Vector3, side: int) -> Rect2:
	var s: float = _scale_at(camera, anchor)
	var local: Rect2 = _wash_local_rect()
	var at: Vector2 = camera.unproject_position(anchor) + (local.position - _pivot(side)) * s
	return Rect2(at, local.size * s)

# `rect` moved the least that keeps it inside the screen less screen_
# margin_px - unless it is the larger, then its top left corner kept.
func _kept_on_screen(rect: Rect2) -> Rect2:
	var view: Rect2 = _safe_rect()
	var at: Vector2 = rect.position
	at.x = clampf(at.x, view.position.x, maxf(view.end.x - rect.size.x, view.position.x))
	at.y = clampf(at.y, view.position.y, maxf(view.end.y - rect.size.y, view.position.y))
	return Rect2(at, rect.size)

func _safe_rect() -> Rect2:
	return get_viewport_rect().grow(-screen_margin_px)

# --- Side ---

# The side with the lower score (see the header), the right when even;
# 0 when neither anchor is in front of the camera.
func _choose_side(camera: Camera3D) -> int:
	var right: float = _side_score(camera, 1)
	var left: float = _side_score(camera, -1)
	if is_inf(right) and is_inf(left):
		return 0
	return -1 if left < right else 1

func _side_score(camera: Camera3D, side: int) -> float:
	var anchor: Vector3 = _anchor(camera, side)
	if camera.is_position_behind(anchor):
		return INF
	var rect: Rect2 = _screen_rect(camera, anchor, side)
	var area: float = rect.get_area()
	if area <= 0.0:
		return INF
	var score: float = 0.0
	# Off the screen: the share it would be pushed back over.
	var safe: Rect2 = _safe_rect()
	score += avoid_weight * (area - rect.intersection(safe).get_area()) / area
	if _wanderer != null and is_instance_valid(_wanderer):
		score += _cover_score(rect, _screen_box(camera, _wanderer), avoid_weight)
	for box in _hud_rects():
		score += _cover_score(rect, box, avoid_weight)
	score += _cover_score(rect, _screen_box(camera, _host), host_weight)
	var props: Node = _region_field.get_node_or_null(RegionField.PROPS_NODE_NAME) if _region_field != null and is_instance_valid(_region_field) else null
	if props != null:
		for prop in props.get_children():
			var prop_3d := prop as Node3D
			if prop_3d == null or prop_3d == _host or prop_3d.is_ancestor_of(_host):
				continue
			score += _cover_score(rect, _screen_box(camera, prop_3d), prop_weight)
	score += scatter_weight * float(_scatter_inside(camera, rect))
	return score

# `weight` times the share of `rect` that `box` covers; nothing for an
# empty box.
func _cover_score(rect: Rect2, box: Rect2, weight: float) -> float:
	if box.get_area() <= 0.0 or not rect.intersects(box):
		return 0.0
	return weight * rect.intersection(box).get_area() / rect.get_area()

# The screen box of every mesh under `node` (itself included) that shows,
# corners behind the camera left out; empty when none is in front.
func _screen_box(camera: Camera3D, node: Node3D) -> Rect2:
	var box := Rect2()
	var any: bool = false
	var meshes: Array[Node] = node.find_children("*", "GeometryInstance3D", true, false)
	if node is GeometryInstance3D:
		meshes.append(node)
	for mesh_node in meshes:
		var mesh := mesh_node as GeometryInstance3D
		if mesh == null or not mesh.is_visible_in_tree() or mesh is GPUParticles3D or mesh is CPUParticles3D:
			continue
		var aabb: AABB = mesh.global_transform * mesh.get_aabb()
		for corner in 8:
			var point: Vector3 = aabb.get_endpoint(corner)
			if camera.is_position_behind(point):
				continue
			var at: Vector2 = camera.unproject_position(point)
			if any:
				box = box.expand(at)
			else:
				box = Rect2(at, Vector2.ZERO)
				any = true
	return box

# The rects of the HUD's own controls that show: every sibling under
# FieldHUD but this, and none that spans more than hud_max_share of the
# screen.
func _hud_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	var parent: Node = get_parent()
	if parent == null:
		return rects
	var screen_area: float = get_viewport_rect().get_area()
	for child in parent.get_children():
		var control := child as Control
		if control == null or control == self or not control.is_visible_in_tree() or control.modulate.a <= 0.01:
			continue
		var rect: Rect2 = control.get_global_rect()
		if rect.get_area() <= 0.0 or rect.get_area() > screen_area * hud_max_share:
			continue
		rects.append(rect)
	return rects

# How many of the floor's scatter items within scatter_reach_m of the
# host would show inside `rect`.
func _scatter_inside(camera: Camera3D, rect: Rect2) -> int:
	if _region_field == null or not is_instance_valid(_region_field) or not _region_field.has_method("get_scatter"):
		return 0
	var scatter := _region_field.call("get_scatter") as FieldScatter
	if scatter == null or not scatter.is_visible_in_tree():
		return 0
	var host_xz := Vector2(_host.global_position.x, _host.global_position.z)
	var count: int = 0
	for instance in scatter.get_instances():
		if instance == null or instance.multimesh == null or not instance.is_visible_in_tree():
			continue
		var multimesh: MultiMesh = instance.multimesh
		var shown: int = multimesh.instance_count if multimesh.visible_instance_count < 0 else mini(multimesh.visible_instance_count, multimesh.instance_count)
		for index in shown:
			var point: Vector3 = instance.global_transform * multimesh.get_instance_transform(index).origin
			if Vector2(point.x, point.z).distance_to(host_xz) > scatter_reach_m or camera.is_position_behind(point):
				continue
			if rect.has_point(camera.unproject_position(point)):
				count += 1
	return count

# --- Draw ---

func _ink() -> Color:
	return get_theme_color("ink", "Battle")

func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = get_theme_color("bone", "Battle")
		outline.a *= color.a
		draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(self, font, text, origin, size_px, color)

func _draw() -> void:
	if _host == null or not is_instance_valid(_host) or _choices.is_empty():
		return
	var ink: Color = _ink()
	_draw_wash(ink)
	var dimmed := Color(ink, ink.a * unfocused_ink_alpha)
	var labels: Array[String] = _labels()
	var label_left: float = hairline_length_px + hairline_gap_px
	var disabled := Color(ink, ink.a * disabled_ink_alpha)
	for index in mini(labels.size(), _choices.size()):
		var focused: bool = index == _focused
		var baseline: float = _choice_top(index) + float(choice_size_px)
		var colour: Color = disabled if not is_enabled(index) else (ink if focused else dimmed)
		_text(_choice_font, labels[index], Vector2(label_left, baseline), choice_size_px, colour)
		if focused:
			var mid: float = baseline - float(choice_size_px) * 0.35
			draw_rect(Rect2(0.0, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), ink)

# FindLine's falloff: a circle, white and solid out to wash_solid_share
# of its radius, then easing (cubic) to clear at the rim.
func _build_wash() -> void:
	var gradient := Gradient.new()
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
	gradient.offsets = PackedFloat32Array([0.0, wash_solid_share, 1.0])
	gradient.colors = PackedColorArray([Color.WHITE, Color.WHITE, Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 64
	texture.height = 64
	_wash_texture = texture

# The falloff's four quarters at the corners, wash_pad_px each way, its
# middle row and column stretched along the edges and its centre under
# the column - one soft rounded wash wash_pad_px beyond the items, faded
# with them by this control's modulate.
func _draw_wash(ink: Color) -> void:
	if wash_opacity <= 0.0 or size.x <= 0.0 or _wash_texture == null:
		return
	var base: Color = wash_color if ink.get_luminance() < 0.5 else wash_color_on_light_ink
	var tint := Color(base, wash_opacity)
	var side: float = float(_wash_texture.width)
	var half: float = side / 2.0
	var pad := Vector2(maxf(wash_pad_px.x, 0.0), maxf(wash_pad_px.y, 0.0))
	# Destination columns and rows, and the texture's matching strips.
	var xs: Array[Vector2] = [Vector2(-pad.x, pad.x), Vector2(0.0, size.x), Vector2(size.x, pad.x)]
	var ys: Array[Vector2] = [Vector2(-pad.y, pad.y), Vector2(0.0, size.y), Vector2(size.y, pad.y)]
	var strips: Array[Vector2] = [Vector2(0.0, half), Vector2(half - 0.5, 1.0), Vector2(half, half)]
	for row in 3:
		for column in 3:
			var dest := Rect2(xs[column].x, ys[row].x, xs[column].y, ys[row].y)
			var source := Rect2(strips[column].x, strips[row].x, strips[column].y, strips[row].y)
			draw_texture_rect_region(_wash_texture, dest, source, tint)

# --- Input ---

func _set_focus(index: int) -> void:
	if _done or index == _focused or not is_enabled(index):
		return
	_focused = index
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _done or _closing or not visible:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(_step_focus(_focused, 1))
	elif event.is_action_pressed("ui_up"):
		_set_focus(_step_focus(_focused, -1))
	elif event.is_action_pressed("ui_accept"):
		_activate(_focused)
	elif event.is_action_pressed("ui_cancel") or _is_right_press(event):
		_activate(_leave_index())
	else:
		return
	get_viewport().set_input_as_handled()

func _is_right_press(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	return button != null and button.button_index == MOUSE_BUTTON_RIGHT and button.pressed

func _on_choice_gui_input(event: InputEvent, index: int) -> void:
	if _done:
		return
	if _is_right_press(event):
		_activate(_leave_index())
		accept_event()
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_set_focus(index)
	_activate(index)
	accept_event()

# The one gate: the first activation of an item on offer wins.
func _activate(index: int) -> void:
	if _done or not is_enabled(index):
		return
	_done = true
	if _host != null and is_instance_valid(_host):
		_host.call("choose", index)
	close()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
