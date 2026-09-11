extends HBoxContainer
class_name HandContainer

@export var card_size: Vector2 = Vector2(247.0, 345.0)
@export var card_spacing: float = 14.0:
	set(value):
		card_spacing = value
		add_theme_constant_override("separation", int(card_spacing))
@export var hover_lift: float = 26.0
@export var hover_duration_sec: float = 0.12
@export var draw_stagger_sec: float = 0.07
@export var discard_collapse_duration_sec: float = 0.16

# Row width cap - past this, every card in the row is scaled down
# uniformly (see _apply_hand_scale()) so the hand never runs off-screen.
# 1600 keeps six cards at full card_size (6 * 247 + 5 * 14 = 1552) but
# starts shrinking at seven (7 * 247 + 6 * 14 = 1813) - "more than six
# cards would overflow" at this card_size/card_spacing pairing.
@export var hand_max_span: float = 1600.0

@export_group("Card Layout")
@export var card_outer_margin: float = 12.0
@export var name_zone_height: float = 40.0
@export var name_font_size_px: int = 26
@export var badge_diameter: float = 40.0
@export var badge_margin: float = 8.0
@export var art_zone_height: float = 120.0
@export var description_font_size_px: int = 18
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
	_apply_hand_scale()
	_collapse_and_remove(slot)

func _add_card_view(card: CardData) -> void:
	var panel_color: Color = get_theme_color("panel_color", "CardFace")
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var badge_bg_color: Color = get_theme_color("badge_bg_color", "CardFace")
	var badge_fg_color: Color = get_theme_color("badge_fg_color", "CardFace")

	var slot := Control.new()
	slot.custom_minimum_size = card_size

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = panel_color
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.shadow_size = 0

	var visual := Panel.new()
	visual.position = Vector2.ZERO
	visual.size = card_size
	visual.mouse_filter = Control.MOUSE_FILTER_STOP
	visual.add_theme_stylebox_override("panel", card_style)
	slot.add_child(visual)

	var name_top: float = card_outer_margin
	var name_label := Label.new()
	name_label.position = Vector2(card_outer_margin, name_top)
	name_label.size = Vector2(card_size.x - card_outer_margin * 2.0, name_zone_height)
	name_label.text = card.card_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", text_color)
	name_label.add_theme_font_size_override("font_size", name_font_size_px)
	if name_font != null:
		name_label.add_theme_font_override("font", name_font)
	visual.add_child(name_label)

	var badge := Panel.new()
	badge.position = Vector2(badge_margin, badge_margin)
	badge.size = Vector2(badge_diameter, badge_diameter)
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = badge_bg_color
	var badge_radius: int = int(badge_diameter / 2.0)
	badge_style.corner_radius_top_left = badge_radius
	badge_style.corner_radius_top_right = badge_radius
	badge_style.corner_radius_bottom_right = badge_radius
	badge_style.corner_radius_bottom_left = badge_radius
	badge_style.shadow_size = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	visual.add_child(badge)

	var cost_label := Label.new()
	cost_label.position = Vector2.ZERO
	cost_label.size = Vector2(badge_diameter, badge_diameter)
	cost_label.text = str(card.cost)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.add_theme_color_override("font_color", badge_fg_color)
	badge.add_child(cost_label)

	var art_top: float = name_top + name_zone_height + card_outer_margin
	var art_rect := ColorRect.new()
	art_rect.position = Vector2(card_outer_margin, art_top)
	art_rect.size = Vector2(card_size.x - card_outer_margin * 2.0, art_zone_height)
	art_rect.color = panel_light_color
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.add_child(art_rect)

	var desc_top: float = art_top + art_zone_height + card_outer_margin
	var description_label := Label.new()
	description_label.position = Vector2(card_outer_margin, desc_top)
	description_label.size = Vector2(card_size.x - card_outer_margin * 2.0, card_size.y - desc_top - card_outer_margin)
	description_label.text = card.description
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_color_override("font_color", text_color)
	description_label.add_theme_font_size_override("font_size", description_font_size_px)
	visual.add_child(description_label)

	visual.mouse_entered.connect(_on_card_hover.bind(visual, true))
	visual.mouse_exited.connect(_on_card_hover.bind(visual, false))

	add_child(slot)
	_views[card] = slot
	_apply_hand_scale()

func _on_card_hover(visual: Control, hovering: bool) -> void:
	var target_y: float = -hover_lift if hovering else 0.0
	var tween: Tween = create_tween()
	tween.tween_property(visual, "position:y", target_y, hover_duration_sec)

func _collapse_and_remove(slot: Control) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(slot, "scale", Vector2.ZERO, discard_collapse_duration_sec)
	tween.tween_callback(slot.queue_free)

# Scales every card in the row down uniformly (footprint via
# slot.custom_minimum_size, rendering via the inner visual's own scale)
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
		var visual: Control = slot.get_child(0) as Control
		visual.scale = Vector2(scale_factor, scale_factor)
