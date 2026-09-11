extends HBoxContainer
class_name HandContainer

@export var card_size: Vector2 = Vector2(130.0, 175.0)
@export var card_spacing: float = 14.0:
	set(value):
		card_spacing = value
		add_theme_constant_override("separation", int(card_spacing))
@export var hover_lift: float = 26.0
@export var hover_duration_sec: float = 0.12
@export var draw_stagger_sec: float = 0.07
@export var discard_collapse_duration_sec: float = 0.16
@export var name_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")

var _deck: Deck = null
var _views: Dictionary = {} # CardData -> Control (the card's slot)
var _pending_reveals: Array[CardData] = []
var _revealing: bool = false

func _ready() -> void:
	add_theme_constant_override("separation", int(card_spacing))

func set_deck(deck: Deck) -> void:
	if _deck != null:
		_deck.drawn.disconnect(_on_card_drawn)
		_deck.discarded.disconnect(_on_card_discarded)
	_deck = deck
	_deck.drawn.connect(_on_card_drawn)
	_deck.discarded.connect(_on_card_discarded)

func draw_cards(amount: int) -> void:
	if _deck == null:
		return
	_deck.draw(amount)

func discard_hand() -> void:
	if _deck == null:
		return
	_deck.discard_hand()

func _on_card_drawn(card: CardData) -> void:
	_pending_reveals.append(card)
	if not _revealing:
		_reveal_pending_cards()

# Reveals queued cards one at a time, draw_stagger_sec apart - matches the
# old project's per-card deal stagger (see reference/old_project's
# _draw_cards()/_await_deal_stagger()).
func _reveal_pending_cards() -> void:
	_revealing = true
	while not _pending_reveals.is_empty():
		var card: CardData = _pending_reveals.pop_front()
		_add_card_view(card)
		if not _pending_reveals.is_empty():
			await get_tree().create_timer(draw_stagger_sec).timeout
	_revealing = false

func _on_card_discarded(card: CardData) -> void:
	var slot: Control = _views.get(card)
	if slot == null:
		return
	_views.erase(card)
	_collapse_and_remove(slot)

func _add_card_view(card: CardData) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = card_size

	var visual := PanelContainer.new()
	visual.position = Vector2.ZERO
	visual.size = card_size
	visual.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.add_child(visual)

	var content := VBoxContainer.new()
	visual.add_child(content)

	var name_label := Label.new()
	name_label.text = card.card_name
	if name_font != null:
		name_label.add_theme_font_override("font", name_font)
	content.add_child(name_label)

	var cost_label := Label.new()
	cost_label.text = str(card.cost)
	content.add_child(cost_label)

	visual.mouse_entered.connect(_on_card_hover.bind(visual, true))
	visual.mouse_exited.connect(_on_card_hover.bind(visual, false))

	add_child(slot)
	_views[card] = slot

func _on_card_hover(visual: PanelContainer, hovering: bool) -> void:
	var target_y: float = -hover_lift if hovering else 0.0
	var tween: Tween = create_tween()
	tween.tween_property(visual, "position:y", target_y, hover_duration_sec)

func _collapse_and_remove(slot: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(slot, "scale", Vector2.ZERO, discard_collapse_duration_sec)
	tween.tween_callback(slot.queue_free)
