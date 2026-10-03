extends CanvasLayer
class_name CardCompendium

# Every card in the data, as a reference - not a collection: nothing here
# reads a run, an unlock or the deck, and nothing writes one. Opened from
# the title (TitleMenu's CARDS), over the same held frame zero, with the
# menu's column hidden behind it; BACK, ui_cancel or ui_accept closes it
# and the menu takes input again.
#
# Where the cards come from is card_folders: an explicit folder list,
# each folder under a heading, never a scan rooted at cards/ (DESIGN.md:
# a scan names its folders, so a new folder is a decision rather than a
# side effect). Folders are read flat, not recursively, through
# ResourceLoader.list_directory() - which sees the original .tres names
# in an exported build too, where DirAccess would see .remap files. A
# second class is one more line in card_folders; two folders under one
# heading merge into one section.
#
# Each section is its heading in tracked caps with its card count in
# Spectral, a hairline under it, then the cards in rarity tiers (Common
# to Ultra Rare, then any card still untagged), each tier under a small
# grey caps label, by cost then name inside it. Cards are CardView at
# rest (hover off), straight on the world - no panel, no scrim. Clicking
# one lifts that same CardView out to the middle at reading size while
# the list recedes; clicking anywhere, or ui_cancel, puts it back.
#
# Every size is authored for a 1080-high viewport and scaled by the
# viewport height, as TitleMenu's are; the whole page is rebuilt on a
# resize and on any export change.

signal closed

const CARD_VIEW_SCENE_PATH := "res://battle/card_view.tscn"
const REFERENCE_VIEWPORT_HEIGHT := 1080.0

# One section's heading and every card found under it.
class Section:
	var heading: String = ""
	var cards: Array[CardData] = []

@export_group("Sources")
# Folder -> section heading, in section order.
@export var card_folders: Dictionary[String, String] = {
	"res://cards/data/": "Wanderer",
	"res://cards/neutral/": "Neutral",
}:
	set(value):
		card_folders = value
		_rebuild_if_ready()
@export var back_text: String = "BACK":
	set(value):
		back_text = value
		_rebuild_if_ready()

@export_group("Type")
# Caps labels - BACK, the headings, the tiers: TitleMenu's item face,
# Alegreya Sans Bold at 0.16 em.
@export var label_font: Font = load(InkType.TEXT_BOLD_FONT_PATH):
	set(value):
		label_font = value
		_rebuild_if_ready()
# A heading's card count.
@export var numeral_font: Font = load(InkType.NUMERAL_FONT_PATH):
	set(value):
		numeral_font = value
		_rebuild_if_ready()
@export var tracking_em: float = 0.16:
	set(value):
		tracking_em = value
		_rebuild_if_ready()
@export var back_font_size_px: int = 22:
	set(value):
		back_font_size_px = value
		_rebuild_if_ready()
@export var heading_font_size_px: int = 22:
	set(value):
		heading_font_size_px = value
		_rebuild_if_ready()
@export var count_font_size_px: int = 22:
	set(value):
		count_font_size_px = value
		_rebuild_if_ready()
@export var tier_font_size_px: int = 14:
	set(value):
		tier_font_size_px = value
		_rebuild_if_ready()

@export_group("Colour")
# The UI ink: BACK, its hairline, the headings.
@export var ink: Color = Color(0.165, 0.165, 0.18, 1.0):
	set(value):
		ink = value
		_rebuild_if_ready()
# The utility grey: the counts and the tier labels.
@export var grey: Color = Color(0.58, 0.58, 0.60, 1.0):
	set(value):
		grey = value
		_rebuild_if_ready()
# The hairline under a heading, as a fraction of the ink.
@export_range(0.0, 1.0) var rule_alpha: float = 0.35:
	set(value):
		rule_alpha = value
		_rebuild_if_ready()

@export_group("Layout")
# The left edge BACK and the list share (TitleMenu's own), and the
# matching right edge, as fractions of the viewport width.
@export var left_margin_fraction: float = 0.12:
	set(value):
		left_margin_fraction = value
		_rebuild_if_ready()
@export var right_margin_fraction: float = 0.12:
	set(value):
		right_margin_fraction = value
		_rebuild_if_ready()
# Pixels at 1080p from here down; the hairlines' thickness is not scaled.
@export var top_px: float = 72.0:
	set(value):
		top_px = value
		_rebuild_if_ready()
@export var back_to_list_gap_px: float = 40.0:
	set(value):
		back_to_list_gap_px = value
		_rebuild_if_ready()
@export var bottom_px: float = 48.0:
	set(value):
		bottom_px = value
		_rebuild_if_ready()
# BACK's hairline: TitleMenu's length, gap and thickness.
@export var hairline_length_px: float = 28.0:
	set(value):
		hairline_length_px = value
		_rebuild_if_ready()
@export var hairline_gap_px: float = 14.0:
	set(value):
		hairline_gap_px = value
		_rebuild_if_ready()
@export var hairline_thickness_px: float = 1.0:
	set(value):
		hairline_thickness_px = value
		_rebuild_if_ready()
# Heading baseline area to its hairline, hairline to the first tier
# label, tier label to its cards, a tier's cards to the next label, and
# the last tier of a section to the next heading.
@export var heading_rule_gap_px: float = 10.0:
	set(value):
		heading_rule_gap_px = value
		_rebuild_if_ready()
@export var rule_tier_gap_px: float = 22.0:
	set(value):
		rule_tier_gap_px = value
		_rebuild_if_ready()
@export var tier_cards_gap_px: float = 12.0:
	set(value):
		tier_cards_gap_px = value
		_rebuild_if_ready()
@export var tier_gap_px: float = 30.0:
	set(value):
		tier_gap_px = value
		_rebuild_if_ready()
@export var section_gap_px: float = 56.0:
	set(value):
		section_gap_px = value
		_rebuild_if_ready()
# The heading's count, after the heading.
@export var heading_count_gap_px: float = 14.0:
	set(value):
		heading_count_gap_px = value
		_rebuild_if_ready()
# A card's scale in the list (of CardView's 1x 200 x 280), and the gap
# between cards both ways.
@export var card_scale: float = 0.75:
	set(value):
		card_scale = value
		_rebuild_if_ready()
@export var card_gap_px: float = 20.0:
	set(value):
		card_gap_px = value
		_rebuild_if_ready()
# Room kept round the list inside the scroll's clip, so the cards' soft
# shadows aren't cut at its edges.
@export var shadow_room_px: float = 16.0:
	set(value):
		shadow_room_px = value
		_rebuild_if_ready()
# How far one ui_up/ui_down press scrolls.
@export var scroll_step_px: float = 120.0

@export_group("Inspect")
# The lifted card's scale, of 1x, before the viewport scale.
@export var inspect_scale: float = 2.2
@export var inspect_duration_sec: float = 0.15
# The list's alpha while a card is lifted - it recedes rather than being
# covered.
@export_range(0.0, 1.0) var inspect_receded_alpha: float = 0.2

@export_group("Flow")
@export var fade_in_seconds: float = 0.2

@onready var page: Control = $Page
@onready var back_item: Control = $Page/BackItem
@onready var scroll: ScrollContainer = $Page/Scroll
@onready var margin: MarginContainer = $Page/Scroll/Margin
@onready var sections_box: VBoxContainer = $Page/Scroll/Margin/Sections
@onready var inspect_layer: Control = $Page/InspectLayer
@onready var inspect_catcher: Control = $Page/InspectLayer/Catcher

# The viewport-height scale of the last rebuild.
var _ui_scale: float = 1.0
# The card lifted out, and the slot it came from - the slot keeps its
# footprint in the list so nothing reflows while it is out.
var _inspected: CardView = null
var _inspect_slot: Control = null
var _inspect_tween: Tween = null
var _inspect_busy: bool = false
var _closing: bool = false

func _ready() -> void:
	page.mouse_filter = Control.MOUSE_FILTER_STOP
	back_item.mouse_filter = Control.MOUSE_FILTER_STOP
	back_item.gui_input.connect(_on_back_gui_input)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sections_box.mouse_filter = Control.MOUSE_FILTER_PASS
	sections_box.add_theme_constant_override("separation", 0)
	inspect_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspect_layer.visible = false
	inspect_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	inspect_catcher.gui_input.connect(_on_catcher_gui_input)
	get_viewport().size_changed.connect(_rebuild)
	_rebuild()
	_fade_in()

func _rebuild_if_ready() -> void:
	if is_inside_tree() and sections_box != null:
		_rebuild()

# --- the cards ----------------------------------------------------------

func _collect_sections() -> Array[Section]:
	var sections: Array[Section] = []
	for folder: String in card_folders:
		var heading: String = card_folders[folder]
		var section: Section = null
		for existing in sections:
			if existing.heading == heading:
				section = existing
				break
		if section == null:
			section = Section.new()
			section.heading = heading
			sections.append(section)
		section.cards.append_array(_load_folder(folder))
	return sections

# Every CardData directly in `folder` - not its subfolders.
func _load_folder(folder: String) -> Array[CardData]:
	var cards: Array[CardData] = []
	var files: PackedStringArray = ResourceLoader.list_directory(folder)
	if files.is_empty():
		push_warning("CardCompendium: no cards found in %s." % folder)
		return cards
	for file in files:
		if file.ends_with("/"):
			continue
		var extension: String = file.get_extension()
		if extension != "tres" and extension != "res":
			continue
		var card := load(folder.path_join(file)) as CardData
		if card == null:
			push_warning("CardCompendium: %s is not a CardData; skipped." % folder.path_join(file))
			continue
		cards.append(card)
	return cards

# The tiers in list order: the four real ones, then UNSET last, so an
# untagged card still shows rather than vanishing.
func _tiers() -> Array[CardData.CardRarity]:
	var tiers: Array[CardData.CardRarity] = CardData.rarity_tiers()
	tiers.append(CardData.CardRarity.UNSET)
	return tiers

func _tier_label(tier: CardData.CardRarity) -> String:
	match tier:
		CardData.CardRarity.COMMON:
			return "COMMON"
		CardData.CardRarity.UNCOMMON:
			return "UNCOMMON"
		CardData.CardRarity.RARE:
			return "RARE"
		CardData.CardRarity.ULTRA_RARE:
			return "ULTRA RARE"
	return "UNTAGGED"

static func _by_cost_then_name(a: CardData, b: CardData) -> bool:
	if a.cost != b.cost:
		return a.cost < b.cost
	return a.card_name.naturalnocasecmp_to(b.card_name) < 0

# --- layout -------------------------------------------------------------

# The whole page from the exports, the folders and the viewport: BACK on
# the left edge with its hairline in the margin, the scroll filling the
# rest, and every section rebuilt inside it. A lifted card is put away
# first - its slot is about to go.
func _rebuild() -> void:
	_drop_inspect()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	_ui_scale = viewport_size.y / REFERENCE_VIEWPORT_HEIGHT
	var left: float = viewport_size.x * left_margin_fraction
	var right: float = viewport_size.x * (1.0 - right_margin_fraction)

	var back_size: int = _scaled_font_size(back_font_size_px)
	var back_label := back_item.get_node(^"Label") as Label
	var back_hairline := back_item.get_node(^"Hairline") as ColorRect
	back_label.text = back_text
	back_label.add_theme_font_override("font", InkType.tracked(label_font, back_size, tracking_em))
	back_label.add_theme_font_size_override("font_size", back_size)
	back_label.add_theme_color_override("font_color", ink)
	back_label.size = back_label.get_combined_minimum_size()
	var hairline_length: float = hairline_length_px * _ui_scale
	var hairline_gap: float = hairline_gap_px * _ui_scale
	back_label.position = Vector2(hairline_length + hairline_gap, 0.0)
	back_item.position = Vector2(left - hairline_length - hairline_gap, top_px * _ui_scale)
	back_item.size = Vector2(back_label.position.x + back_label.size.x, back_label.size.y)
	back_hairline.size = Vector2(hairline_length, hairline_thickness_px)
	back_hairline.position = Vector2(0.0, (back_label.size.y - hairline_thickness_px) * 0.5)
	back_hairline.color = ink

	var room: float = shadow_room_px * _ui_scale
	var list_top: float = back_item.position.y + back_item.size.y + back_to_list_gap_px * _ui_scale
	scroll.position = Vector2(left - room, list_top - room)
	scroll.size = Vector2(right - left + room * 2.0, maxf(viewport_size.y - list_top - bottom_px * _ui_scale + room, 0.0))
	var room_px: int = roundi(room)
	margin.add_theme_constant_override("margin_left", room_px)
	margin.add_theme_constant_override("margin_right", room_px)
	margin.add_theme_constant_override("margin_top", room_px)
	margin.add_theme_constant_override("margin_bottom", room_px)

	for child in sections_box.get_children():
		sections_box.remove_child(child)
		child.queue_free()
	var sections: Array[Section] = _collect_sections()
	for index in sections.size():
		if index > 0:
			_add_spacer(section_gap_px)
		_add_section(sections[index])

func _add_section(section: Section) -> void:
	# Drawn, not two Labels, so the caps heading and the Spectral count
	# share one baseline across the two faces.
	var heading_size: int = _scaled_font_size(heading_font_size_px)
	var count_size: int = _scaled_font_size(count_font_size_px)
	var heading_font: Font = InkType.tracked(label_font, heading_size, tracking_em)
	var heading_text: String = section.heading.to_upper()
	var count_text: String = str(section.cards.size())
	var count_gap: float = heading_count_gap_px * _ui_scale
	var ascent: float = maxf(heading_font.get_ascent(heading_size), numeral_font.get_ascent(count_size))
	var descent: float = maxf(heading_font.get_descent(heading_size), numeral_font.get_descent(count_size))
	var heading := Control.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.custom_minimum_size = Vector2(0.0, ascent + descent)
	heading.draw.connect(func() -> void:
		var x: float = InkType.draw_run(heading, heading_font, heading_text, Vector2(0.0, ascent), heading_size, ink)
		InkType.draw_run(heading, numeral_font, count_text, Vector2(x + count_gap, ascent), count_size, grey))
	sections_box.add_child(heading)

	_add_spacer(heading_rule_gap_px)
	var rule := ColorRect.new()
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.custom_minimum_size = Vector2(0.0, hairline_thickness_px)
	rule.color = Color(ink.r, ink.g, ink.b, ink.a * rule_alpha)
	sections_box.add_child(rule)
	_add_spacer(rule_tier_gap_px)

	var tier_size: int = _scaled_font_size(tier_font_size_px)
	var tier_font: Font = InkType.tracked(label_font, tier_size, tracking_em)
	var first_tier: bool = true
	for tier in _tiers():
		var in_tier: Array[CardData] = []
		for card in section.cards:
			if card.rarity == tier:
				in_tier.append(card)
		if in_tier.is_empty():
			continue
		in_tier.sort_custom(_by_cost_then_name)
		if not first_tier:
			_add_spacer(tier_gap_px)
		first_tier = false

		var tier_label := Label.new()
		tier_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tier_label.text = _tier_label(tier)
		tier_label.add_theme_font_override("font", tier_font)
		tier_label.add_theme_font_size_override("font_size", tier_size)
		tier_label.add_theme_color_override("font_color", grey)
		sections_box.add_child(tier_label)
		_add_spacer(tier_cards_gap_px)

		var flow := HFlowContainer.new()
		flow.mouse_filter = Control.MOUSE_FILTER_PASS
		var gap: int = roundi(card_gap_px * _ui_scale)
		flow.add_theme_constant_override("h_separation", gap)
		flow.add_theme_constant_override("v_separation", gap)
		sections_box.add_child(flow)
		for card in in_tier:
			_add_card(flow, card)

# A CardView at rest in a slot that reserves its scaled footprint. The
# card scales toward its own top-left (pivot ZERO), the corner the slot
# reserves from. PASS once it's in the tree (CardView's _ready() sets
# STOP) so the wheel still reaches the scroll through it.
func _add_card(flow: HFlowContainer, card: CardData) -> void:
	var scene := load(CARD_VIEW_SCENE_PATH) as PackedScene
	if scene == null:
		push_warning("CardCompendium: could not load %s." % CARD_VIEW_SCENE_PATH)
		return
	var card_view := scene.instantiate() as CardView
	var list_scale: float = card_scale * _ui_scale
	card_view.hover_enabled = false
	card_view.pivot_offset = Vector2.ZERO
	card_view.scale = Vector2(list_scale, list_scale)
	var slot := Control.new()
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	slot.custom_minimum_size = card_view.card_size * list_scale
	slot.add_child(card_view)
	flow.add_child(slot)
	card_view.mouse_filter = Control.MOUSE_FILTER_PASS
	card_view.set_card_data(card)
	card_view.clicked.connect(_on_card_clicked.bind(card_view, slot))

func _add_spacer(height_px: float) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(0.0, height_px * _ui_scale)
	sections_box.add_child(spacer)

func _scaled_font_size(size_px: int) -> int:
	return maxi(roundi(float(size_px) * _ui_scale), 1)

func _fade_in() -> void:
	if fade_in_seconds <= 0.0:
		page.modulate.a = 1.0
		return
	page.modulate.a = 0.0
	create_tween().tween_property(page, "modulate:a", 1.0, fade_in_seconds)

# --- input --------------------------------------------------------------

# ui_cancel and ui_accept back out one level at a time: a lifted card is
# put down before the page closes. ui_up/ui_down scroll the list.
func _unhandled_input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_accept"):
		if _inspected != null:
			_end_inspect()
		elif not _inspect_busy:
			close()
	elif event.is_action_pressed("ui_down", true):
		if _inspected == null:
			_scroll_by(scroll_step_px)
	elif event.is_action_pressed("ui_up", true):
		if _inspected == null:
			_scroll_by(-scroll_step_px)
	else:
		return
	get_viewport().set_input_as_handled()

func _scroll_by(step_px: float) -> void:
	scroll.scroll_vertical += roundi(step_px * _ui_scale)

func _on_back_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	get_viewport().set_input_as_handled()
	if _inspected == null and not _inspect_busy:
		close()

# Emits closed and goes; the owner (TitleMenu) shows its column again.
func close() -> void:
	if _closing:
		return
	_closing = true
	_drop_inspect()
	closed.emit()
	queue_free()

# --- inspect ------------------------------------------------------------

# DeckView's inspect, without its dim: the same CardView lifted out of
# its slot (the scroll clips, so it can't grow in place), the list
# receding behind it. Only the lifted card or the catcher can be clicked
# while one is out, so there is no card-to-card swap.
func _on_card_clicked(_card_data: CardData, card_view: CardView, slot: Control) -> void:
	if _inspect_busy or _closing:
		return
	if _inspected == card_view:
		_end_inspect()
	elif _inspected == null:
		_begin_inspect(card_view, slot)

func _on_catcher_gui_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button == null or not button.pressed or button.button_index != MOUSE_BUTTON_LEFT:
		return
	_end_inspect()
	get_viewport().set_input_as_handled()

func _begin_inspect(card_view: CardView, slot: Control) -> void:
	var from_position: Vector2 = card_view.global_position
	slot.remove_child(card_view)
	inspect_layer.add_child(card_view)
	card_view.global_position = from_position
	_inspected = card_view
	_inspect_slot = slot
	inspect_layer.visible = true
	# Up for inspection: its keywords define themselves on hover.
	card_view.set_keyword_inspect(true)
	var lifted_scale: float = inspect_scale * _ui_scale
	var centre: Vector2 = (get_viewport().get_visible_rect().size - card_view.card_size * lifted_scale) / 2.0
	_tween_inspect(card_view, centre, lifted_scale, inspect_receded_alpha)

func _end_inspect() -> void:
	if _inspected == null or _inspect_busy:
		return
	var card_view: CardView = _inspected
	var slot: Control = _inspect_slot
	_inspected = null
	_inspect_slot = null
	card_view.set_keyword_inspect(false)
	_tween_inspect(card_view, slot.global_position, card_scale * _ui_scale, 1.0)
	_inspect_tween.tween_callback(func() -> void:
		if is_instance_valid(card_view) and is_instance_valid(slot):
			card_view.get_parent().remove_child(card_view)
			slot.add_child(card_view)
			card_view.position = Vector2.ZERO
		inspect_layer.visible = false)

func _tween_inspect(card_view: CardView, to_position: Vector2, to_scale: float, list_alpha: float) -> void:
	if _inspect_tween != null and _inspect_tween.is_valid():
		_inspect_tween.kill()
	_inspect_busy = true
	_inspect_tween = create_tween()
	_inspect_tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_inspect_tween.set_parallel(true)
	_inspect_tween.tween_property(card_view, "global_position", to_position, inspect_duration_sec)
	_inspect_tween.tween_property(card_view, "scale", Vector2.ONE * to_scale, inspect_duration_sec)
	_inspect_tween.tween_property(scroll, "modulate:a", list_alpha, inspect_duration_sec)
	_inspect_tween.chain()
	_inspect_tween.tween_callback(func() -> void: _inspect_busy = false)

# Any lift, in flight or held, gone at once - for a rebuild, which frees
# its slot, and for close. The lifted card is freed with it.
func _drop_inspect() -> void:
	if _inspect_tween != null and _inspect_tween.is_valid():
		_inspect_tween.kill()
	_inspect_tween = null
	_inspect_busy = false
	for child in inspect_layer.get_children():
		if child is CardView:
			inspect_layer.remove_child(child)
			child.queue_free()
	_inspected = null
	_inspect_slot = null
	inspect_layer.visible = false
	scroll.modulate.a = 1.0
