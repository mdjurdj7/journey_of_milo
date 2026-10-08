extends CanvasLayer
class_name CollectorScreen

# What the collector has, over the field. Opened by RegionField.open_
# collector_screen() on the collector's open_requested, over the scrim-
# and-freeze the reward and belongings screens use: the field goes
# DISABLED under it, the camera holds, and this layer runs ALWAYS on
# layer 100. No title, no panel, no box - the system voice only.
#
# A row of cards at 1x: the collector's rolled stock (Collector.get_
# stock()), then its fixed card (Samphire) set a little apart at the right
# end. Each card's price sits under it in Spectral numerals. A card the
# run can't afford is dimmed (CardView.set_playable(false)) and its click
# does nothing; an affordable one, clicked, spends its price (RunState.
# spend_gold()), joins the deck (RunState.add_card()), flies to the deck
# panel and leaves its slot empty - for good: the collector never
# restocks.
#
# Under the row, HAND ONE OVER with its price: it opens the deck in pick
# mode (DeckPanel.open_picker(), above this layer); a card picked spends
# the price and leaves the deck (RunState.remove_card()); a cancel comes
# back here with nothing spent. Once per collector, then grey and inert -
# and grey and inert while it can't be paid for. Then LEAVE, which
# closes the screen, as do ui_cancel and a right click. The run's gold
# stays readable on the screen itself (GOLD n, beside LEAVE), since the
# HUD's sits dimmed under the scrim.
#
# The focus language of the other screens over the scrim: a card
# focused grows in place (CardView.set_hovered()); a text line focused is
# full bone with the short hairline to its left, grey at rest. The mouse
# focuses by hovering and acts by clicking; ui_left/ui_right move along
# the row, ui_down drops to HAND ONE OVER then LEAVE, ui_up climbs back,
# ui_accept acts.
#
# The scrim, the outlined text and the hairline are copies of
# BelongingsScreen's (themselves RewardScreen's) - the shared focus-
# drawing extraction is its own task (DESIGN.md).

signal closed()

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const TAKE_SFX_PATH := "res://assets/audio/cards/card_take.wav"
const GOLD_SFX_PATH := "res://assets/audio/ui/gold_take.wav"

@export var scrim_color: Color = Color(0.165, 0.165, 0.18, 0.55):
	set(value):
		scrim_color = value
		if _scrim != null:
			_scrim.color = value
@export var bone: Color = Color(0.94, 0.91, 0.86, 1.0):
	set(value):
		bone = value
		_refresh()
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_refresh()
@export var text_outline_px: int = 1:
	set(value):
		text_outline_px = value
		_refresh()
@export var unfocused_color: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		unfocused_color = value
		_refresh()
# A price that can't be paid, and HAND ONE OVER once spent.
@export var inert_color: Color = Color(0.58, 0.58, 0.60, 0.45):
	set(value):
		inert_color = value
		_refresh()

@export_group("Row")
# Every size below is authored for this window height and scaled by the
# window's own (held lower if the row would overrun the width).
@export var reference_height: float = 1080.0:
	set(value):
		reference_height = value
		_relayout()
@export var card_scale: float = 1.0:
	set(value):
		card_scale = value
		_relayout()
# Between two cards, as a fraction of a card's width.
@export var card_gap_fraction: float = 0.18:
	set(value):
		card_gap_fraction = value
		_relayout()
# The extra room before the fixed card, as a fraction of a card's width.
@export var fixed_gap_fraction: float = 0.35:
	set(value):
		fixed_gap_fraction = value
		_relayout()
@export_range(0.0, 1.0) var row_centre_fraction: float = 0.4:
	set(value):
		row_centre_fraction = value
		_relayout()
@export_range(0.1, 1.0) var max_width_fraction: float = 0.92:
	set(value):
		max_width_fraction = value
		_relayout()
@export var price_size_px: int = 26:
	set(value):
		price_size_px = value
		_relayout()
@export var price_gap_px: float = 18.0:
	set(value):
		price_gap_px = value
		_relayout()
@export_group("")

@export_group("Lines")
@export var removal_text: String = "HAND ONE OVER":
	set(value):
		removal_text = value
		_refresh()
@export var leave_text: String = "LEAVE":
	set(value):
		leave_text = value
		_refresh()
@export var gold_text: String = "GOLD":
	set(value):
		gold_text = value
		_refresh()
# DeckView's header while picking.
@export var removal_header_text: String = "Hand one over":
	set(value):
		removal_header_text = value
@export var label_size_px: int = 22:
	set(value):
		label_size_px = value
		_relayout()
@export_range(0.0, 1.0) var label_tracking_em: float = 0.16:
	set(value):
		label_tracking_em = value
		_relayout()
# Room between a label and its price numeral.
@export var label_price_gap_px: float = 18.0:
	set(value):
		label_price_gap_px = value
		_refresh()
@export_range(0.0, 1.0) var removal_baseline_fraction: float = 0.76:
	set(value):
		removal_baseline_fraction = value
		_refresh()
@export_range(0.0, 1.0) var leave_baseline_fraction: float = 0.84:
	set(value):
		leave_baseline_fraction = value
		_refresh()
@export var hairline_length_px: float = 28.0:
	set(value):
		hairline_length_px = value
		_refresh()
@export var hairline_gap_px: float = 14.0:
	set(value):
		hairline_gap_px = value
		_refresh()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_refresh()
@export_group("")

@export_group("Take")
@export var take_volume_db: float = -18.0
@export var gold_volume_db: float = -20.0
@export var card_flight_duration_sec: float = 0.45
@export var card_flight_end_scale: float = 0.12
# The picker's layer, over this one.
@export var picker_layer_offset: int = 1
@export_group("")

var _collector: Collector = null
var _deck_panel: Control = null
var _scrim: ColorRect = null
var _draw_layer: Control = null
var _numeral_font: Font = null
var _label_font: Font = null
var _fit: float = 1.0
var _label_px: int = 22
var _price_px: int = 26
# One per slot: the rolled stock, then the fixed card - null once bought
# (or a slot that rolled nothing).
var _views: Array[CardView] = []
var _cards: Array[CardData] = []
# Focus: a slot index, or REMOVAL / LEAVE below; -1 = nothing.
var _focus: int = -1
var _mouse_on: int = -1
var _picker: DeckView = null
var _closing: bool = false

# Called by RegionField before the screen enters the tree.
func setup(collector: Collector, deck_panel: Control) -> void:
	_collector = collector
	_deck_panel = deck_panel

func _ready() -> void:
	# The field is frozen under this (RegionField.open_collector_screen());
	# this layer opts out of the freeze or would stop with it.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100

	_scrim = ColorRect.new()
	_scrim.name = "Scrim"
	_scrim.color = scrim_color
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP: a click must not reach the field and order the Wanderer off.
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_draw_layer = Control.new()
	_draw_layer.name = "Row"
	_draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_draw_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_draw_layer.gui_input.connect(_on_gui_input)
	_draw_layer.draw.connect(_draw_screen)
	_draw_layer.resized.connect(_relayout)
	add_child(_draw_layer)

	if _collector != null:
		_collector.ensure_stock()
		_collector.prices_changed.connect(_on_prices_changed)
		for card in _collector.get_stock():
			_cards.append(card)
		_cards.append(_collector.fixed_card if _collector.is_fixed_available() else null)
	_build_views()
	_relayout()

func _exit_tree() -> void:
	if _collector != null and is_instance_valid(_collector) and _collector.prices_changed.is_connected(_on_prices_changed):
		_collector.prices_changed.disconnect(_on_prices_changed)
	if _picker != null and is_instance_valid(_picker):
		_picker.close()

# --- Slots ---

func _slot_count() -> int:
	return _cards.size()

func _fixed_slot() -> int:
	return _cards.size() - 1

func _removal_index() -> int:
	return _cards.size()

func _leave_index() -> int:
	return _cards.size() + 1

func _price_at(slot: int) -> int:
	if _collector == null or _cards[slot] == null:
		return 0
	if slot == _fixed_slot():
		return _collector.fixed_price
	return _collector.price_of(_cards[slot])

func _affordable(slot: int) -> bool:
	return _cards[slot] != null and RunState.gold >= _price_at(slot)

func _removal_open() -> bool:
	return _collector != null and not _collector.is_removal_used() and RunState.gold >= _collector.removal_price and not RunState.deck.is_empty()

func _build_views() -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("CollectorScreen: could not load %s; no cards shown." % CARD_VIEW_SCENE_PATH)
		return
	for slot in _cards.size():
		var card: CardData = _cards[slot]
		if card == null:
			_views.append(null)
			continue
		var view := scene.instantiate() as CardView
		# The reward screen's choice card: grows in place about its centre
		# (pivot set after add_child(), which puts a hover card's pivot at
		# its bottom centre for the hand), no lift; keywords define
		# themselves on hover.
		view.hover_lift = 0.0
		_draw_layer.add_child(view)
		view.pivot_offset = view.card_size / 2.0
		view.set_card_data(card)
		view.set_keyword_inspect(true)
		view.clicked.connect(_on_card_clicked.bind(slot))
		view.mouse_entered.connect(_on_card_mouse_entered.bind(slot))
		view.mouse_exited.connect(_on_card_mouse_exited.bind(slot))
		_views.append(view)
	_apply_affordability()
	# The stock arriving: each card's name sheens once (a Common's doesn't).
	for view: CardView in _views:
		if view != null:
			view.play_name_sheen()

# Dims every card the run can't pay for now.
func _apply_affordability() -> void:
	for slot in _views.size():
		var view: CardView = _views[slot]
		if view != null and is_instance_valid(view):
			view.set_playable(_affordable(slot))

# --- Layout ---

func _relayout() -> void:
	if _draw_layer == null or not is_node_ready():
		return
	var window: Vector2 = _draw_layer.size
	var card_size := Vector2(200.0, 280.0)
	for view in _views:
		if view != null:
			card_size = view.card_size
			break
	var count: int = maxi(_views.size(), 1)
	var span_at_one: float = _row_span(card_size.x * card_scale, count)
	_fit = window.y / maxf(reference_height, 1.0)
	if span_at_one > 0.0:
		_fit = minf(_fit, window.x * max_width_fraction / span_at_one)
	_fit = maxf(_fit, 0.01)
	var face_scale: float = card_scale * _fit
	var card: Vector2 = card_size * face_scale
	var start_x: float = roundf((window.x - _row_span(card.x, count)) / 2.0)
	var top: float = roundf(window.y * row_centre_fraction - card.y * 0.5)
	var pivot_shift: Vector2 = (card_size * 0.5) * (face_scale - 1.0)
	for slot in _views.size():
		var view: CardView = _views[slot]
		if view == null or not is_instance_valid(view):
			continue
		view.position = Vector2(_slot_left(slot, start_x, card.x), top) + pivot_shift
		view.set_rest_offset(view.position.y)
		view.set_base_scale(face_scale)
	_label_px = maxi(roundi(float(label_size_px) * _fit), 1)
	_price_px = maxi(roundi(float(price_size_px) * _fit), 1)
	_numeral_font = InkType.numeral_font()
	_label_font = InkType.tracked(InkType.text_bold_font(), _label_px, label_tracking_em)
	_refresh()

func _row_span(card_width: float, count: int) -> float:
	var gaps: float = float(maxi(count - 1, 0)) * card_width * card_gap_fraction
	return float(count) * card_width + gaps + card_width * fixed_gap_fraction

func _slot_left(slot: int, start_x: float, card_width: float) -> float:
	var left: float = start_x + float(slot) * card_width * (1.0 + card_gap_fraction)
	if slot == _fixed_slot():
		left += card_width * fixed_gap_fraction
	return roundf(left)

# A slot's face, on screen - where its card stands, bought or not.
func _slot_rect(slot: int) -> Rect2:
	var window: Vector2 = _draw_layer.size
	var card_size := Vector2(200.0, 280.0)
	for view in _views:
		if view != null:
			card_size = view.card_size
			break
	var card: Vector2 = card_size * card_scale * _fit
	var start_x: float = roundf((window.x - _row_span(card.x, maxi(_views.size(), 1))) / 2.0)
	var top: float = roundf(window.y * row_centre_fraction - card.y * 0.5)
	return Rect2(_slot_left(slot, start_x, card.x), top, card.x, card.y)

func _line_baseline(index: int) -> float:
	var fraction: float = removal_baseline_fraction if index == _removal_index() else leave_baseline_fraction
	return roundf(_draw_layer.size.y * fraction)

func _line_label(index: int) -> String:
	return removal_text if index == _removal_index() else leave_text

# The label's left edge: the line is centred, label and price together.
func _line_left(index: int) -> float:
	return roundf((_draw_layer.size.x - _line_width(index)) / 2.0)

func _line_width(index: int) -> float:
	var width: float = InkType.width(_label_font, _line_label(index), _label_px)
	if index == _removal_index() and _collector != null:
		width += label_price_gap_px * _fit + InkType.width(_numeral_font, str(_collector.removal_price), _label_px)
	return width

# The line and the hairline's room to its left.
func _line_rect(index: int) -> Rect2:
	var left: float = _line_left(index) - (hairline_gap_px + hairline_length_px) * _fit
	var right: float = _line_left(index) + _line_width(index)
	return Rect2(left, _line_baseline(index) - float(_label_px), right - left, float(_label_px) * 1.3)

# --- Draw ---

func _refresh() -> void:
	if _draw_layer != null:
		_draw_layer.queue_redraw()

# One bone run over its ink outline, the outline carrying the run's alpha.
func _text(font: Font, text: String, origin: Vector2, size_px: int, color: Color) -> void:
	if font == null or text.is_empty():
		return
	if text_outline_px > 0:
		var outline: Color = ink
		outline.a = ink.a * color.a
		_draw_layer.draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, text_outline_px, outline)
	InkType.draw_run(_draw_layer, font, text, origin, size_px, color)

func _draw_screen() -> void:
	if _closing or _label_font == null:
		return
	for slot in _cards.size():
		if _cards[slot] == null:
			continue
		var rect: Rect2 = _slot_rect(slot)
		var price: String = str(_price_at(slot))
		var x: float = roundf(rect.get_center().x - InkType.width(_numeral_font, price, _price_px) / 2.0)
		var y: float = roundf(rect.end.y + price_gap_px * _fit + float(_price_px))
		_text(_numeral_font, price, Vector2(x, y), _price_px, bone if _affordable(slot) else inert_color)
	for index: int in [_removal_index(), _leave_index()]:
		_draw_line(index)
	# The run's gold, at LEAVE's baseline on the row's right edge.
	var gold: String = str(RunState.gold)
	var row_right: float = _slot_rect(_fixed_slot()).end.x
	var gold_width: float = InkType.width(_numeral_font, gold, _label_px)
	var gold_baseline: float = _line_baseline(_leave_index())
	_text(_numeral_font, gold, Vector2(roundf(row_right - gold_width), gold_baseline), _label_px, bone)
	var caps_width: float = InkType.width(_label_font, gold_text, _label_px)
	_text(_label_font, gold_text, Vector2(roundf(row_right - gold_width - label_price_gap_px * _fit - caps_width), gold_baseline), _label_px, unfocused_color)

func _draw_line(index: int) -> void:
	var inert: bool = index == _removal_index() and not _removal_open()
	var focused: bool = _focus == index and not inert
	var color: Color = inert_color if inert else (bone if focused else unfocused_color)
	var left: float = _line_left(index)
	var baseline: float = _line_baseline(index)
	_text(_label_font, _line_label(index), Vector2(left, baseline), _label_px, color)
	if index == _removal_index() and _collector != null:
		var price_left: float = left + InkType.width(_label_font, removal_text, _label_px) + label_price_gap_px * _fit
		_text(_numeral_font, str(_collector.removal_price), Vector2(roundf(price_left), baseline), _label_px, color)
	if focused:
		var mid: float = baseline - float(_label_px) * 0.35
		var length: float = hairline_length_px * _fit
		_draw_layer.draw_rect(Rect2(left - hairline_gap_px * _fit - length, mid - hairline_thickness_px * 0.5, length, hairline_thickness_px), bone)

# --- Focus ---

func _focusable(index: int) -> bool:
	if index >= 0 and index < _cards.size():
		return _cards[index] != null
	if index == _removal_index():
		return _removal_open()
	return index == _leave_index()

func _set_focus(index: int) -> void:
	if index == _focus:
		return
	if _focus >= 0 and _focus < _views.size() and _views[_focus] != null and is_instance_valid(_views[_focus]):
		_views[_focus].set_hovered(false)
	_focus = index
	if _focus >= 0 and _focus < _views.size() and _views[_focus] != null and is_instance_valid(_views[_focus]):
		_views[_focus].set_hovered(true)
	_refresh()

# The next focusable slot from `from` stepping `step` along the row,
# wrapping; -1 when the row is empty.
func _row_step(from: int, step: int) -> int:
	var count: int = _cards.size()
	var start: int = from if from >= 0 else (-1 if step > 0 else count)
	for i in count:
		var index: int = posmod(start + step * (i + 1), count)
		if _focusable(index):
			return index
	return -1

func _on_card_mouse_entered(slot: int) -> void:
	if _input_open():
		_set_focus(slot)

func _on_card_mouse_exited(slot: int) -> void:
	if _input_open() and _focus == slot:
		_set_focus(-1)

func _input_open() -> bool:
	return not _closing and (_picker == null or not is_instance_valid(_picker))

func _line_hit(position: Vector2) -> int:
	for index: int in [_removal_index(), _leave_index()]:
		if _focusable(index) and _line_rect(index).has_point(position):
			return index
	return -1

func _on_gui_input(event: InputEvent) -> void:
	if not _input_open():
		return
	var motion := event as InputEventMouseMotion
	if motion != null:
		var under: int = _line_hit(motion.position)
		if under != _mouse_on:
			if under >= 0:
				_set_focus(under)
			elif _focus == _mouse_on:
				_set_focus(-1)
			_mouse_on = under
		return
	var button := event as InputEventMouseButton
	if button == null or not button.pressed:
		return
	if button.button_index == MOUSE_BUTTON_RIGHT:
		_activate(_leave_index())
		_draw_layer.accept_event()
	elif button.button_index == MOUSE_BUTTON_LEFT:
		var index: int = _line_hit(button.position)
		if index >= 0:
			_activate(index)
		_draw_layer.accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if not _input_open():
		return
	var on_row: bool = _focus >= 0 and _focus < _cards.size()
	if event.is_action_pressed("ui_right"):
		_set_focus(_row_step(_focus if on_row else -1, 1))
	elif event.is_action_pressed("ui_left"):
		_set_focus(_row_step(_focus if on_row else -1, -1))
	elif event.is_action_pressed("ui_down"):
		if _focus == _removal_index() or _focus == _leave_index():
			_set_focus(_leave_index())
		else:
			_set_focus(_removal_index() if _focusable(_removal_index()) else _leave_index())
	elif event.is_action_pressed("ui_up"):
		if _focus == _leave_index() and _focusable(_removal_index()):
			_set_focus(_removal_index())
		elif not on_row:
			_set_focus(_row_step(-1, 1))
	elif event.is_action_pressed("ui_accept"):
		if _focus >= 0:
			_activate(_focus)
	elif event.is_action_pressed("ui_cancel"):
		_activate(_leave_index())
	else:
		return
	get_viewport().set_input_as_handled()

# --- Acting ---

func _on_card_clicked(_card_data: CardData, slot: int) -> void:
	if _input_open():
		_activate(slot)

func _activate(index: int) -> void:
	if not _input_open():
		return
	if index == _leave_index():
		close()
	elif index == _removal_index():
		_open_picker()
	elif index >= 0 and index < _cards.size():
		_buy(index)

# A card bought: its price spent, the card in the deck, the slot empty
# for good. An unaffordable or empty slot does nothing.
func _buy(slot: int) -> void:
	var card: CardData = _cards[slot]
	if card == null or _collector == null:
		return
	var price: int = _price_at(slot)
	if not RunState.spend_gold(price):
		return
	RunState.add_card(card)
	if slot == _fixed_slot():
		_collector.take_fixed()
	else:
		_collector.take_stock(slot)
	_cards[slot] = null
	RunLogger.event("collector_buy", {"card": card.card_name, "rarity": String(CardData.CardRarity.find_key(card.rarity)).to_lower(), "price": price, "gold_after": RunState.gold})
	TakeFeedback.play_sound(get_tree(), TAKE_SFX_PATH, take_volume_db, "CardTakeAudio", "CollectorScreen")
	print("CollectorScreen: bought '%s' for %d (gold %d, deck %d)." % [card.card_name, price, RunState.gold, RunState.deck.size()])
	var view: CardView = _views[slot]
	_views[slot] = null
	if _focus == slot:
		_focus = -1
	if view != null and is_instance_valid(view):
		view.set_hovered(false)
		var tween: Tween = TakeFeedback.fly_to(self, view, _deck_panel_centre(), card_flight_duration_sec, card_flight_end_scale)
		tween.chain().tween_callback(view.queue_free)
	_apply_affordability()
	_refresh()

func _open_picker() -> void:
	if not _removal_open():
		return
	_picker = DeckPanel.open_picker(get_tree(), RunState.deck, removal_header_text, layer + picker_layer_offset)
	_picker.card_picked.connect(_on_removal_picked)
	_picker.closed.connect(_on_picker_closed)
	_set_focus(-1)

# The deck's card handed over: the price spent, the card gone - once.
func _on_removal_picked(card: CardData) -> void:
	if _collector == null or _collector.is_removal_used():
		return
	var price: int = _collector.removal_price
	if not RunState.spend_gold(price):
		return
	RunState.remove_card(card)
	_collector.use_removal()
	RunLogger.event("collector_removal", {"card": card.card_name, "price": price, "gold_after": RunState.gold})
	TakeFeedback.play_sound(get_tree(), GOLD_SFX_PATH, gold_volume_db, "RemovalAudio", "CollectorScreen")
	print("CollectorScreen: handed over '%s' for %d (gold %d, deck %d)." % [card.card_name, price, RunState.gold, RunState.deck.size()])

# Picked or cancelled, the picker is gone: back to the screen.
func _on_picker_closed() -> void:
	_picker = null
	_apply_affordability()
	_refresh()

func _on_prices_changed() -> void:
	_apply_affordability()
	_relayout()

func _deck_panel_centre() -> Vector2:
	if _deck_panel == null:
		return Vector2(_draw_layer.size.x * 0.5, _draw_layer.size.y + 200.0)
	return _deck_panel.get_global_rect().get_center()

# LEAVE, ui_cancel or a right click: the screen goes and the field comes
# back (RegionField._on_collector_screen_closed()).
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()

# For probes: what is in each slot now (null = bought or empty).
func get_slot_cards() -> Array[CardData]:
	return _cards.duplicate()
