extends Panel
class_name CardView

signal clicked(card_data: CardData)

@export var card_size: Vector2 = Vector2(247.0, 345.0)

@export_group("Card Layout")
@export var card_outer_margin: float = 12.0
@export var name_zone_height: float = 40.0
@export var name_font_size_px: int = 26
@export var badge_diameter: float = 40.0
@export var badge_margin: float = 8.0
@export var art_zone_height: float = 120.0
@export var description_font_size_px: int = 18
@export var name_font: Font = load("res://assets/fonts/Spectral-SemiBold.ttf")

@export_group("Hover")
@export var hover_lift: float = 26.0
@export var hover_duration_sec: float = 0.12

@onready var name_label: Label = $NameLabel
@onready var badge: Panel = $Badge
@onready var cost_label: Label = $Badge/CostLabel
@onready var art_rect: ColorRect = $ArtRect
@onready var description_label: Label = $DescriptionLabel

var card_data: CardData
var _armed: bool = false

func _ready() -> void:
	size = card_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	_apply_style()
	_apply_layout()
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)

func set_card_data(data: CardData) -> void:
	card_data = data
	name_label.text = data.card_name
	cost_label.text = str(data.cost)
	description_label.text = data.description

# Held while awaiting a target for this card (see BattleController.
# request_play()) - hover in/out is ignored while armed, since the card is
# already deliberately lifted and shouldn't drop just because the mouse
# passes over it.
func lift_and_hold() -> void:
	_armed = true
	_tween_to(-hover_lift)

func release() -> void:
	_armed = false
	_tween_to(0.0)

func _on_mouse_entered() -> void:
	if not _armed:
		_tween_to(-hover_lift)

func _on_mouse_exited() -> void:
	if not _armed:
		_tween_to(0.0)

func _tween_to(target_y: float) -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "position:y", target_y, hover_duration_sec)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(card_data)

func _apply_style() -> void:
	var panel_color: Color = get_theme_color("panel_color", "CardFace")
	var panel_light_color: Color = get_theme_color("panel_light_color", "CardFace")
	var text_color: Color = get_theme_color("text_color", "CardFace")
	var badge_bg_color: Color = get_theme_color("badge_bg_color", "CardFace")
	var badge_fg_color: Color = get_theme_color("badge_fg_color", "CardFace")

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = panel_color
	card_style.corner_radius_top_left = 10
	card_style.corner_radius_top_right = 10
	card_style.corner_radius_bottom_right = 10
	card_style.corner_radius_bottom_left = 10
	card_style.shadow_size = 0
	add_theme_stylebox_override("panel", card_style)

	name_label.add_theme_color_override("font_color", text_color)
	name_label.add_theme_font_size_override("font_size", name_font_size_px)
	if name_font != null:
		name_label.add_theme_font_override("font", name_font)

	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = badge_bg_color
	var badge_radius: int = int(badge_diameter / 2.0)
	badge_style.corner_radius_top_left = badge_radius
	badge_style.corner_radius_top_right = badge_radius
	badge_style.corner_radius_bottom_right = badge_radius
	badge_style.corner_radius_bottom_left = badge_radius
	badge_style.shadow_size = 0
	badge.add_theme_stylebox_override("panel", badge_style)
	cost_label.add_theme_color_override("font_color", badge_fg_color)

	art_rect.color = panel_light_color

	description_label.add_theme_color_override("font_color", text_color)
	description_label.add_theme_font_size_override("font_size", description_font_size_px)

func _apply_layout() -> void:
	name_label.position = Vector2(card_outer_margin, card_outer_margin)
	name_label.size = Vector2(card_size.x - card_outer_margin * 2.0, name_zone_height)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	badge.position = Vector2(badge_margin, badge_margin)
	badge.size = Vector2(badge_diameter, badge_diameter)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE

	cost_label.position = Vector2.ZERO
	cost_label.size = Vector2(badge_diameter, badge_diameter)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var art_top: float = card_outer_margin + name_zone_height + card_outer_margin
	art_rect.position = Vector2(card_outer_margin, art_top)
	art_rect.size = Vector2(card_size.x - card_outer_margin * 2.0, art_zone_height)
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var desc_top: float = art_top + art_zone_height + card_outer_margin
	description_label.position = Vector2(card_outer_margin, desc_top)
	description_label.size = Vector2(card_size.x - card_outer_margin * 2.0, card_size.y - desc_top - card_outer_margin)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
