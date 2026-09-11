extends HBoxContainer
class_name HandContainer

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"

signal card_clicked(card_view: CardView)
signal play_animation_finished(card_data: CardData)

@export var card_size: Vector2 = Vector2(247.0, 345.0)
@export var card_spacing: float = 14.0:
	set(value):
		card_spacing = value
		add_theme_constant_override("separation", int(card_spacing))
@export var draw_stagger_sec: float = 0.07
@export var discard_collapse_duration_sec: float = 0.16

# Row width cap - past this, every card in the row is scaled down
# uniformly (see _apply_hand_scale()) so the hand never runs off-screen.
# 1600 keeps six cards at full card_size (6 * 247 + 5 * 14 = 1552) but
# starts shrinking at seven (7 * 247 + 6 * 14 = 1813) - "more than six
# cards would overflow" at this card_size/card_spacing pairing.
@export var hand_max_span: float = 1600.0

@export_group("Play Tween")
@export var play_to_target_duration_sec: float = 0.25
@export var play_to_discard_duration_sec: float = 0.2
@export var discard_point: Vector2 = Vector2(1750.0, 150.0)

var _deck: Deck = null
var _views: Dictionary = {} # CardData -> Control (the card's slot; its only child is a CardView)
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

# No-op if play_card() already erased this card's entry and freed its view -
# the controller only calls Deck.discard() after play_card()'s own
# choreography (and view removal) has already finished.
func _on_card_discarded(card: CardData) -> void:
	var slot: Control = _views.get(card)
	if slot == null:
		return
	_views.erase(card)
	_apply_hand_scale()
	_collapse_and_remove(slot)

func _add_card_view(card: CardData) -> void:
	var slot := Control.new()
	slot.custom_minimum_size = card_size

	var card_view := (load(CARD_VIEW_SCENE_PATH) as PackedScene).instantiate() as CardView
	card_view.card_size = card_size
	slot.add_child(card_view)

	# Brings slot (and card_view within it) into the live tree, firing
	# CardView._ready() - must happen before set_card_data() below, which
	# needs card_view's @onready label references already populated.
	add_child(slot)

	card_view.position = Vector2.ZERO
	card_view.set_card_data(card)
	card_view.clicked.connect(_on_card_view_clicked.bind(card_view))

	_views[card] = slot
	_apply_hand_scale()

func _on_card_view_clicked(_card_data: CardData, card_view: CardView) -> void:
	card_clicked.emit(card_view)

func _collapse_and_remove(slot: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(slot, "scale", Vector2.ZERO, discard_collapse_duration_sec)
	tween.tween_callback(slot.queue_free)

# Runs the hand -> target -> discard travel for a played card, removing its
# view when done and emitting play_animation_finished. target_screen_pos is
# wherever the controller decided to aim it (an enemy's unprojected head for
# an ENEMY-target card, or some up-and-away point for SELF/NONE) - this
# function doesn't interpret target_type at all, only where it's told to go.
func play_card(card_data: CardData, target_screen_pos: Vector2) -> void:
	var slot: Control = _views.get(card_data)
	if slot == null:
		return
	_views.erase(card_data)
	_apply_hand_scale()

	var card_view: CardView = slot.get_child(0) as CardView
	card_view.release()

	# Detach from the row - left parented under this HBoxContainer, it would
	# keep getting re-laid-out every frame, fighting the tween below. Its
	# parent (BattleOverlay's own root Control) is a plain, non-container
	# Control, safe for free on-screen travel.
	var slot_global_pos: Vector2 = slot.global_position
	remove_child(slot)
	get_parent().add_child(slot)
	slot.global_position = slot_global_pos

	var tween := create_tween()
	tween.tween_property(slot, "global_position", target_screen_pos - slot.size / 2.0, play_to_target_duration_sec)
	tween.tween_property(slot, "global_position", discard_point - slot.size / 2.0, play_to_discard_duration_sec)
	tween.parallel().tween_property(card_view, "modulate:a", 0.0, play_to_discard_duration_sec)
	tween.tween_callback(func() -> void:
		slot.queue_free()
		play_animation_finished.emit(card_data)
	)

# Scales every card in the row down uniformly (footprint via
# slot.custom_minimum_size, rendering via the inner card_view's own scale)
# once the row's natural width would exceed hand_max_span. card_size
# itself never changes - only this derived factor does.
func _apply_hand_scale() -> void:
	var count: int = _views.size()
	if count == 0:
		return
	var natural_width: float = count * card_size.x + max(count - 1, 0) * card_spacing
	var scale_factor: float = 1.0
	if natural_width > hand_max_span:
		scale_factor = hand_max_span / natural_width
	for slot: Control in _views.values():
		slot.custom_minimum_size = card_size * scale_factor
		var card_view: Control = slot.get_child(0) as Control
		card_view.scale = Vector2(scale_factor, scale_factor)
