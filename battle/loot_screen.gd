extends CanvasLayer
class_name LootScreen

# What a bundle holds, over the dimmed field - RewardScreen's look (the
# scrim, bone text over a 1 px ink outline, no box, the field frozen
# underneath) with one item instead of a list. RegionField opens it from
# a click on a BundleProp in reach (see RegionField._open_loot_screen()).
#
# The item: gold as a numeral beside a drawn ring, or the card as a
# CardView at the deck view's inspect size, so it can be read here.
# Under it, TAKE and LEAVE in the title menu's focus language turned for
# the dark scrim: the focused item in full bone with a short hairline to
# its left, the other dimmed with none; hover moves focus, a click
# activates, ui_up/ui_down move it (wrapping), ui_accept activates,
# ui_cancel is LEAVE.
#
# TAKE grants through RunState, plays the take's sound (TakeFeedback),
# marks the bundle taken and closes - a card flies to the Belongings
# panel first. LEAVE closes and changes nothing: unlike the reward
# screen's skip, leaving is not final, and the bundle opens again with
# the same thing inside.

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"

enum Item { TAKE, LEAVE }

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.40)
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0)
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0)
@export var text_outline_px: int = 1

@export_group("Item")
@export var header_text: String = "INSIDE"
@export var header_size_px: int = 11
@export_range(0.0, 1.0) var header_tracking_em: float = 0.22
@export var header_gap_px: float = 28.0
# The deck view's own inspect scale, so a card here reads at the size it
# reads there.
@export var card_scale: float = 2.2
@export var gold_size_px: int = 64
@export var ring_radius_px: float = 17.0
@export var ring_width_px: float = 3.0
@export var ring_gap_px: float = 16.0
@export_group("")

@export_group("Choices")
@export var take_text: String = "TAKE"
@export var leave_text: String = "LEAVE"
@export var choice_size_px: int = 22
@export_range(0.0, 1.0) var choice_tracking_em: float = 0.16
@export var choices_gap_px: float = 40.0
@export var choice_gap_px: float = 18.0
@export_range(0.0, 1.0) var unfocused_alpha: float = 0.55
@export var hairline_length_px: float = 28.0
@export var hairline_gap_px: float = 14.0
@export var hairline_thickness_px: float = 1.0
@export_group("")

@export_group("Take")
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
@export_group("")

var _bundle: BundleProp = null
var _deck_panel: Control = null
var _focused: int = Item.TAKE
var _done: bool = false
var _card_view: CardView = null
var _choice_rects: Array[Rect2] = [Rect2(), Rect2()]

var _draw_layer: Control = null
var _header_font: Font = null
var _gold_font: Font = null
var _choice_font: Font = null

# Called by RegionField before the screen enters the tree.
func setup(bundle: BundleProp, deck_panel: Control) -> void:
	_bundle = bundle
	_deck_panel = deck_panel

func _ready() -> void:
	# RegionField is frozen under this, as under the reward screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_header_font = InkType.tracked(InkType.text_bold_font(), header_size_px, header_tracking_em)
	_gold_font = InkType.numeral_font()
	_choice_font = InkType.tracked(InkType.text_bold_font(), choice_size_px, choice_tracking_em)

	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = scrim_color
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Column"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_column)
	add_child(_draw_layer)

	if _bundle == null or _bundle.contents == BundleProp.Contents.NONE:
		close()
		return
	if _bundle.contents_card != null:
		_spawn_card()

# The card at inspect size, placed by _layout() on every draw. Not
# clickable and not hover-grown: TAKE is the button, the card is to read.
func _spawn_card() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("LootScreen: could not load %s; no card shown." % CARD_VIEW_SCENE_PATH)
		return
	_card_view = scene.instantiate() as CardView
	_card_view.hover_enabled = false
	_card_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_layer.add_child(_card_view)
	_card_view.set_card_data(_bundle.contents_card)
	_card_view.pivot_offset = Vector2.ZERO
	_card_view.scale = Vector2.ONE * card_scale

# --- Layout ---

func _item_size() -> Vector2:
	if _card_view != null:
		return _card_view.card_size * card_scale
	var text_width: float = InkType.width(_gold_font, str(_bundle.contents_gold), gold_size_px)
	return Vector2(ring_radius_px * 2.0 + ring_gap_px + text_width, float(gold_size_px))

func _choices_height() -> float:
	return float(choice_size_px) * 2.0 + choice_gap_px

# Everything as one centred column: header, item, the two choices.
func _column_top() -> float:
	var total: float = float(header_size_px) + header_gap_px + _item_size().y + choices_gap_px + _choices_height()
	return (_draw_layer.size.y - total) / 2.0

# --- Draw ---

func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> float:
	if font == null or text.is_empty():
		return 0.0
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	return InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _draw_column() -> void:
	if _bundle == null:
		return
	var centre_x: float = _draw_layer.size.x / 2.0
	var top: float = _column_top()
	var header_width: float = InkType.width(_header_font, header_text, header_size_px)
	_text(_header_font, header_text, Vector2(centre_x - header_width / 2.0, top + float(header_size_px)), header_size_px, bone)

	var item_top: float = top + float(header_size_px) + header_gap_px
	var item_size: Vector2 = _item_size()
	var item_left: float = roundf(centre_x - item_size.x / 2.0)
	if _card_view != null:
		if not _done:
			_card_view.position = Vector2(item_left, roundf(item_top))
	else:
		_draw_gold(Vector2(item_left, item_top))

	var y: float = item_top + item_size.y + choices_gap_px
	var labels: Array[String] = [take_text, leave_text]
	var widest: float = maxf(InkType.width(_choice_font, take_text, choice_size_px), InkType.width(_choice_font, leave_text, choice_size_px))
	var label_left: float = roundf(centre_x - widest / 2.0)
	for index in labels.size():
		var focused: bool = index == _focused
		var color: Color = bone
		if not focused:
			color.a = unfocused_alpha
		var baseline: float = y + float(choice_size_px)
		_text(_choice_font, labels[index], Vector2(label_left, baseline), choice_size_px, color)
		var hairline_left: float = label_left - hairline_gap_px - hairline_length_px
		_choice_rects[index] = Rect2(hairline_left, y, hairline_length_px + hairline_gap_px + widest, float(choice_size_px) * 1.3)
		if focused:
			var mid: float = baseline - float(choice_size_px) * 0.35
			_draw_layer.draw_rect(Rect2(hairline_left, mid - hairline_thickness_px * 0.5, hairline_length_px, hairline_thickness_px), bone)
		y += float(choice_size_px) + choice_gap_px

# The amount in the numeral face with a drawn ring for the coin to its
# left, both on the item row's centre line.
func _draw_gold(top_left: Vector2) -> void:
	var centre_y: float = top_left.y + float(gold_size_px) * 0.5
	var ring_centre := Vector2(top_left.x + ring_radius_px, centre_y)
	if text_outline_px > 0:
		_draw_layer.draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, ink, ring_width_px + float(text_outline_px) * 2.0, true)
	_draw_layer.draw_arc(ring_centre, ring_radius_px, 0.0, TAU, 48, bone, ring_width_px, true)
	var baseline: float = top_left.y + float(gold_size_px) * 0.8
	_text(_gold_font, str(_bundle.contents_gold), Vector2(top_left.x + ring_radius_px * 2.0 + ring_gap_px, baseline), gold_size_px, bone)

# --- Input ---

func _set_focus(index: int) -> void:
	if _done or index == _focused:
		return
	_focused = index
	_draw_layer.queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if _done:
		return
	if event.is_action_pressed("ui_down"):
		_set_focus(posmod(_focused + 1, 2))
	elif event.is_action_pressed("ui_up"):
		_set_focus(posmod(_focused - 1, 2))
	elif event.is_action_pressed("ui_accept"):
		_activate(_focused)
	elif event.is_action_pressed("ui_cancel"):
		_activate(Item.LEAVE)
	else:
		return
	get_viewport().set_input_as_handled()

func _on_gui_input(event: InputEvent) -> void:
	if _done:
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		for index in _choice_rects.size():
			if _choice_rects[index].has_point(motion.position):
				_set_focus(index)
		return
	var button := event as InputEventMouseButton
	if button == null or button.button_index != MOUSE_BUTTON_LEFT or not button.pressed:
		return
	for index in _choice_rects.size():
		if _choice_rects[index].has_point(button.position):
			_set_focus(index)
			_activate(index)
			_draw_layer.accept_event()
			return

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
			var tween: Tween = TakeFeedback.fly_to(self, _card_view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
			tween.chain().tween_callback(close)
			return
	else:
		RunState.add_gold(_bundle.contents_gold)
		TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "GoldTakeAudio", "LootScreen")
		print("LootScreen: took %d gold (run total %d)." % [_bundle.contents_gold, RunState.gold])
		_bundle.mark_taken()
	close()

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		push_warning("LootScreen: no DeckPanel to fly to; dropping the card off-screen instead.")
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

func close() -> void:
	closed.emit()
	queue_free()
