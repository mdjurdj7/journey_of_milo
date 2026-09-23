extends Control
class_name LootScreen

# What a bundle holds, shown beside the bundle on the world - no scrim,
# no header, and the field never stops: the Wanderer can walk, the enemy
# keeps walking, a fight can start. RegionField opens it from a click on
# a BundleProp in reach and parents it under FieldHUD (see RegionField.
# _open_loot_screen()).
#
# Placed every physics tick the way EnemyStatus is: the anchor - the
# bundle plus anchor_offset, x metres along the camera's right and y
# metres up - is unprojected, and this control's scale follows camera
# distance (DistanceScale). The side is taken along the CAMERA's right,
# not a world axis, so the contents are beside the bundle whatever the
# yaw (the same reasoning as WorldCard.screen_gap_px). The anchor is the
# column's left edge, level with the item's middle.
#
# The item: gold as a drawn ring and a numeral, or the card as a CardView
# at WorldCard's near size (near_scale times the distance scale, which is
# this control's own), not clickable - TAKE is the button, the card is to
# read. Ink on the world: the Battle ink token from the shared theme, so
# it turns bone on a dark world with the rest of the battle UI
# (BattleTheme.apply_value_set()); an optional outline in the Battle bone
# token.
#
# Under it, TAKE and LEAVE in the title menu's focus language: the
# focused item in full ink with a short hairline to its left, the other
# in the utility grey with none. TAKE has focus on open. ui_up/ui_down
# move it (wrapping), ui_accept activates; hovering an item focuses it
# and a click activates. The two items are the only things here that
# stop the mouse - a click anywhere else is the field's.
#
# TAKE grants through RunState, plays the take's sound (TakeFeedback),
# marks the bundle taken and closes - a card flies to the Belongings
# panel first. LEAVE closes and changes nothing, and so does walking out
# of the bundle's reach or the field freezing (a fight, the floor
# transition): leaving is not final, and the bundle opens again with the
# same thing inside.

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const THEME_PATH := "res://ui/battle_theme.tres"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"

enum Item { TAKE, LEAVE }

# x: metres along the camera's right from the bundle; y: metres up.
@export var anchor_offset: Vector2 = Vector2(0.6, 0.6)
@export var text_outline_px: int = 0
@export var open_fade_sec: float = 0.18

@export_group("Item")
# WorldCard.near_scale - the card at the size a lifted card has.
@export var card_near_scale: float = 1.0
@export var gold_size_px: int = 40:
	set(value):
		gold_size_px = value
		_rebuild_fonts()
@export var ring_radius_px: float = 11.0
@export var ring_width_px: float = 2.0
@export var ring_gap_px: float = 10.0
@export_group("")

@export_group("Choices")
@export var take_text: String = "TAKE"
@export var leave_text: String = "LEAVE"
@export var choice_size_px: int = 22:
	set(value):
		choice_size_px = value
		_rebuild_fonts()
@export_range(0.0, 1.0) var choice_tracking_em: float = 0.16:
	set(value):
		choice_tracking_em = value
		_rebuild_fonts()
@export var choices_gap_px: float = 24.0
@export var choice_gap_px: float = 14.0
# The title menu's unfocused item: CardView's keyline_utility.
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0)
@export var hairline_length_px: float = 28.0
@export var hairline_gap_px: float = 14.0
@export var hairline_thickness_px: float = 1.0
@export_group("")

# Apparent-size correction, EnemyStatus's and WorldCard's knobs and
# defaults.
@export_group("Distance Scale")
@export var min_scale: float = 0.6
@export var max_scale: float = 1.0
@export var near_scale_distance: float = 3.0
@export var far_scale_distance: float = 12.0
@export_group("")

@export_group("Take")
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _bundle: BundleProp = null
var _deck_panel: Control = null
var _wanderer: Node3D = null
var _region_field: Node = null
var _focused: int = Item.TAKE
var _done: bool = false
var _closing: bool = false
var _card_view: CardView = null
var _choices: Array[Control] = []

var _gold_font: Font = null
var _choice_font: Font = null

# Called by RegionField before this enters the tree.
func setup(bundle: BundleProp, deck_panel: Control, wanderer: Node3D, region_field: Node) -> void:
	_bundle = bundle
	_deck_panel = deck_panel
	_wanderer = wanderer
	_region_field = region_field

func get_bundle() -> BundleProp:
	return _bundle

func _ready() -> void:
	# After CameraRig has placed the camera this tick (EnemyStatus's reason).
	process_physics_priority = 1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = load(THEME_PATH) as Theme
	_rebuild_fonts()

	for index in 2:
		var choice := Control.new()
		choice.name = "Take" if index == Item.TAKE else "Leave"
		choice.mouse_filter = Control.MOUSE_FILTER_STOP
		choice.mouse_entered.connect(_set_focus.bind(index))
		choice.gui_input.connect(_on_choice_gui_input.bind(index))
		add_child(choice)
		_choices.append(choice)

	if _bundle == null or _bundle.contents == BundleProp.Contents.NONE:
		close()
		return
	if _bundle.contents_card != null:
		_spawn_card()

	visible = false
	modulate.a = 0.0
	if open_fade_sec > 0.0:
		create_tween().tween_property(self, "modulate:a", 1.0, open_fade_sec)
	else:
		modulate.a = 1.0

func _rebuild_fonts() -> void:
	_gold_font = InkType.numeral_font()
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_size_px, choice_tracking_em)
	queue_redraw()

func _spawn_card() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("LootScreen: could not load %s; no card shown." % CARD_VIEW_SCENE_PATH)
		return
	_card_view = scene.instantiate() as CardView
	_card_view.hover_enabled = false
	_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_card_view)
	_card_view.set_card_data(_bundle.contents_card)
	_card_view.pivot_offset = Vector2.ZERO

# --- Tick ---

func _physics_process(_delta: float) -> void:
	if _done or _closing:
		return
	if _bundle == null or not is_instance_valid(_bundle):
		close()
		return
	# The field froze under us (a fight, the floor transition) - FieldHUD
	# runs ALWAYS, so this would otherwise sit over the battle.
	if _region_field != null and is_instance_valid(_region_field) and not _region_field.can_process():
		close()
		return
	if _wanderer != null and is_instance_valid(_wanderer) and not _bundle.can_open_from(_wanderer.global_position):
		close()
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	right = right.normalized()
	var anchor: Vector3 = _bundle.global_position + right * anchor_offset.x + Vector3.UP * anchor_offset.y
	if camera.is_position_behind(anchor):
		visible = false
		return
	visible = true
	_layout()
	var distance: float = camera.global_position.distance_to(anchor)
	scale = Vector2.ONE * DistanceScale.compute_scale(distance, near_scale_distance, far_scale_distance, min_scale, max_scale)
	position = (camera.unproject_position(anchor) - pivot_offset).round()
	queue_redraw()

# --- Layout (local space; the anchor is pivot_offset) ---

func _item_size() -> Vector2:
	if _card_view != null:
		return _card_view.card_size * card_near_scale
	var text_width: float = InkType.width(_gold_font, str(_bundle.contents_gold), gold_size_px)
	return Vector2(ring_radius_px * 2.0 + ring_gap_px + text_width, float(gold_size_px))

func _choices_width() -> float:
	var widest: float = maxf(InkType.width(_choice_font, take_text, choice_size_px), InkType.width(_choice_font, leave_text, choice_size_px))
	return hairline_length_px + hairline_gap_px + widest

func _choice_top(index: int) -> float:
	return _item_size().y + choices_gap_px + float(index) * (float(choice_size_px) + choice_gap_px)

# The column: the item, then the two choices, left-aligned. The choices'
# hairlines hang in the same column as everything else, so the labels
# start hairline_length_px + hairline_gap_px in.
func _layout() -> void:
	var item_size: Vector2 = _item_size()
	size = Vector2(maxf(item_size.x, _choices_width()), _choice_top(1) + float(choice_size_px) * 1.3)
	pivot_offset = Vector2(0.0, item_size.y * 0.5)
	if _card_view != null:
		_card_view.position = Vector2.ZERO
		_card_view.scale = Vector2.ONE * card_near_scale
	for index in _choices.size():
		_choices[index].position = Vector2(0.0, _choice_top(index))
		_choices[index].size = Vector2(_choices_width(), float(choice_size_px) * 1.3)

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
	if _bundle == null or _choices.size() < 2:
		return
	var ink: Color = _ink()
	if _card_view == null:
		_draw_gold(ink)
	var labels: Array[String] = [take_text, leave_text]
	var label_left: float = hairline_length_px + hairline_gap_px
	for index in labels.size():
		var focused: bool = index == _focused
		var baseline: float = _choice_top(index) + float(choice_size_px)
		_text(_choice_font, labels[index], Vector2(label_left, baseline), choice_size_px, ink if focused else unfocused_color)
		if focused:
			var mid: float = baseline - float(choice_size_px) * 0.35
			draw_rect(Rect2(0.0, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), ink)

# The drawn ring for the coin, then the amount in the numeral face, both
# on the item row's centre line.
func _draw_gold(ink: Color) -> void:
	var centre_y: float = float(gold_size_px) * 0.5
	var ring_centre := Vector2(ring_radius_px, centre_y)
	if text_outline_px > 0:
		draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, get_theme_color("bone", "Battle"), ring_width_px + float(text_outline_px) * 2.0, true)
	draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, ink, ring_width_px, true)
	var baseline: float = float(gold_size_px) * 0.8
	_text(_gold_font, str(_bundle.contents_gold), Vector2(ring_radius_px * 2.0 + ring_gap_px, baseline), gold_size_px, ink)

# --- Input ---

func _set_focus(index: int) -> void:
	if _done or index == _focused:
		return
	_focused = index
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _done or _closing or not visible:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focused + 1, 2))
	elif event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focused - 1, 2))
	elif event.is_action_pressed("ui_accept"):
		_activate(_focused)
	else:
		return
	get_viewport().set_input_as_handled()

func _on_choice_gui_input(event: InputEvent, index: int) -> void:
	if _done:
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	_set_focus(index)
	_activate(index)
	accept_event()

# The one gate: the first activation wins.
func _activate(index: int) -> void:
	if _done:
		return
	if index == Item.LEAVE:
		close()
		return
	_done = true
	if _bundle.contents_card != null:
		RunState.add_card(_bundle.contents_card)
		TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "LootScreen")
		print("LootScreen: took '%s' (deck now %d)." % [_bundle.contents_card.card_name, RunState.deck.size()])
		_bundle.mark_taken()
		if _card_view != null:
			_fly_card()
			return
	else:
		RunState.add_gold(_bundle.contents_gold)
		TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "LootScreen")
		print("LootScreen: took %d gold (run total %d)." % [_bundle.contents_gold, RunState.gold])
		_bundle.mark_taken()
	close()

# The flight is in screen space (TakeFeedback.fly_to() takes a screen
# point), so the card leaves this scaled, moving control for the HUD
# layer first, keeping where and how big it is on screen; the rest of
# the column goes at once.
func _fly_card() -> void:
	var on_screen_scale: float = _card_view.scale.x * scale.x
	var hud: Node = get_parent()
	_card_view.reparent(hud, true)
	_card_view.scale = Vector2.ONE * on_screen_scale
	for choice in _choices:
		choice.visible = false
	visible = false
	var card_view: CardView = _card_view
	var tween: Tween = TakeFeedback.fly_to(card_view, card_view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
	tween.chain().tween_callback(card_view.queue_free)
	close()

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("LootScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()
