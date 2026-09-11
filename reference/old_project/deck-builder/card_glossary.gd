extends Node2D
class_name CardGlossary
# Browse a full character's card pool outside of any run - for reviewing
# existing cards and brainstorming new ones (see this feature's own plan,
# 2026-08-27). Reachable directly from the title screen's main menu (see
# title_screen.gd's own "Card glossary" button) - unlike dev_encounter_
# picker.gd, this isn't a dev-only affordance.
#
# Deliberately its OWN screen rather than a reuse of deck_viewer.gd:
# DeckViewer is built as a pause-the-tree overlay (backdrop, close button,
# equipped-weapon row, selection mode) for in-run contexts - none of that
# applies to a standalone full-screen browser with nothing underneath to
# protect. What IS reused is the same grid-building TECHNIQUE deck_
# viewer.gd's _populate()/_add_card()/_compare_cards() already use
# (preload card.tscn, one instance per CardData in a GridContainer, sort
# cost-then-name) - copied and adapted here, not inherited.
#
# The character tab row is built from CharacterPool.list_all() (see that
# file's own header) rather than one hardcoded button per known
# CharacterData - a future third character needs zero changes to this
# script to show up here, just a new .tres in resources/characters/.

const CARD_SCENE := preload("res://card.tscn")

@export var card_scale: float = 0.8
@export var card_hover_scale: float = 1.35
@export var card_hover_rise_px: float = 40.0
@export var grid_columns: int = 6

@export_group("Grid Spacing")
@export var grid_top_clearance_px: float = 90.0
# Room for the TOP row's own hover growth to expand into, above the grid -
# without this, hovering a top-row card clips against the screen/scroll-
# view edge (nothing above the grid to grow into). Card's hover animation
# scales from a CENTER pivot (see card.gd's _apply_layout(): visual.pivot_
# offset = design_size * f / 2.0), so growth splits evenly above and
# below rest position - only half of the size increase pushes upward,
# plus the separate hover_offset rise on top of that. At this screen's
# defaults (card_scale 0.8, card_hover_scale 1.35, card_hover_rise_px 40),
# that works out to roughly 48px (half the scale growth) + 40px (rise) =
# ~88px, so 90 covers it with a small margin. Same fix, same rough
# number, as deck_viewer.gd's own now-revised content_top_clearance_px
# used to be sized for this exact problem before its Equipped section
# started providing the clearance instead - this screen has no such
# section above its grid, so it needs the margin directly.
@export var grid_bottom_clearance_px: float = 60.0
# Same idea for the LAST row - nothing below the grid to absorb hover
# growth either. Reuses deck_viewer.gd's own content_bottom_clearance_px
# value rather than inventing a new number, for the same hover-growth
# math as the top value above.
@export var grid_left_clearance_px: float = 40.0
@export var grid_right_clearance_px: float = 40.0
# Same problem again, sideways: the leftmost/rightmost COLUMN's hover
# growth has no room outside the grid either, so it clips against the
# scroll view's edge same as the top row did before grid_top_clearance_px.
# No hover_offset rise to account for here (that's a vertical-only nudge -
# see card.gd's hover_offset), just half the scale growth: design_size.x
# * f * (card_hover_scale - 1.0) / 2.0, which at this screen's defaults
# (247.5 * 0.8 * 0.35 / 2.0) is ~35px - 40 covers it with a small margin,
# same "round up a bit" approach grid_top_clearance_px already took.

@onready var back_button: Button = $UI/Margin/Root/HeaderRow/BackButton
@onready var character_tab_row: HBoxContainer = $UI/Margin/Root/CharacterTabRow
@onready var type_filter_row: HBoxContainer = $UI/Margin/Root/TypeFilterRow
@onready var grid_margin: MarginContainer = $UI/Margin/Root/MainRow/GridScroll/GridMargin
@onready var card_grid: GridContainer = $UI/Margin/Root/MainRow/GridScroll/GridMargin/CardGrid
@onready var detail_name_label: Label = $UI/Margin/Root/MainRow/DetailPanel/DetailNameLabel
@onready var detail_flavor_label: Label = $UI/Margin/Root/MainRow/DetailPanel/DetailFlavorLabel

const ALL_TYPES := -1
# Sentinel for "no type filter" - not a real CardData.CardType value (that
# enum starts at 0), so it can never collide with one, including if a
# future CardType value is ever added at the end of the enum.

var _characters: Array[CharacterData] = []
var _tab_buttons: Array[Button] = []
var _selected_character: CharacterData = null

var _type_filter_buttons: Array[Button] = []
var _type_filter_values: Array[int] = []
# Parallel array to _type_filter_buttons (ALL_TYPES or a CardData.CardType
# value per button) - same "index-parallel arrays" shape _tab_buttons/
# _characters above already use for the same reason (a plain Button has
# nowhere else to stash which value it represents).
var _selected_type: int = ALL_TYPES

func _ready() -> void:
	back_button.pressed.connect(_on_back_pressed)
	card_grid.columns = grid_columns
	_apply_grid_clearance()
	_characters = CharacterPool.list_all()
	_build_tab_row()
	_build_type_filter_row()
	if not _characters.is_empty():
		_select_character(_default_character())

# The tab to open on: the first character (in CharacterPool scan order)
# whose pool holds at least one card, so the glossary never opens on an
# empty grid while some populated class exists (e.g. the Samurai's pool is
# empty right now - opening straight onto it would look broken). Falls
# back to the first character only if EVERY pool is empty. No class is
# special-cased - a class slots in by scan order like any other the
# moment it has cards.
func _default_character() -> CharacterData:
	for character: CharacterData in _characters:
		if not CardPool.load_class_pool(character).is_empty():
			return character
	return _characters[0]

# The one place grid_top/bottom_clearance_px actually land on a node -
# card_glossary.tscn bakes in matching starting values so the scene still
# looks right in the editor before this ever runs, same shape as deck_
# viewer.gd's own _apply_equipped_slot_size().
func _apply_grid_clearance() -> void:
	grid_margin.add_theme_constant_override("margin_top", grid_top_clearance_px)
	grid_margin.add_theme_constant_override("margin_bottom", grid_bottom_clearance_px)
	grid_margin.add_theme_constant_override("margin_left", grid_left_clearance_px)
	grid_margin.add_theme_constant_override("margin_right", grid_right_clearance_px)

# --- Character tabs ---
#
# Plain toggle Buttons, same shape as dev_encounter_picker.gd's own
# ClassRow - just built from _characters in a loop instead of one button
# per class hand-placed in the scene, so the row grows on its own as
# CharacterPool.list_all() finds more.
func _build_tab_row() -> void:
	for child in character_tab_row.get_children():
		child.queue_free()
	_tab_buttons.clear()
	for character: CharacterData in _characters:
		var button := Button.new()
		button.text = character.character_name
		button.toggle_mode = true
		button.pressed.connect(_select_character.bind(character))
		character_tab_row.add_child(button)
		_tab_buttons.append(button)

func _select_character(character: CharacterData) -> void:
	_selected_character = character
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = _characters[i] == character
	_refresh_grid()

# --- Type filter ---
#
# Same shape as _build_tab_row() above, just sourced from the CardType
# enum instead of a folder scan - CardData.CardType.keys() (see card_
# data.gd) rather than a hardcoded "Attack"/"Skill" pair, so a future
# third CardType value shows up here with no change to this function.
# "All" is prepended as ALL_TYPES, not a real enum value.
func _build_type_filter_row() -> void:
	for child in type_filter_row.get_children():
		child.queue_free()
	_type_filter_buttons.clear()
	_type_filter_values.clear()
	_add_type_filter_button("All", ALL_TYPES)
	_type_filter_buttons[0].button_pressed = true # "All" is the default filter (_selected_type's own initial value).
	for key: String in CardData.CardType.keys():
		_add_type_filter_button(key.capitalize(), CardData.CardType[key])

func _add_type_filter_button(label: String, type_value: int) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.pressed.connect(_select_type_filter.bind(type_value))
	type_filter_row.add_child(button)
	_type_filter_buttons.append(button)
	_type_filter_values.append(type_value)

func _select_type_filter(type_value: int) -> void:
	_selected_type = type_value
	for i in _type_filter_buttons.size():
		_type_filter_buttons[i].button_pressed = _type_filter_values[i] == type_value
	_refresh_grid()

# --- Card grid (mirrors deck_viewer.gd's _populate()/_add_card()) ---
#
# Shared by both the character tabs and the type filter (see both
# handlers above) - whichever one changes, the grid rebuilds the same
# way: load the selected character's full pool, then narrow it to the
# selected type if one's chosen. Filter selection is deliberately NOT
# reset on a character switch (and vice versa) - flipping from Wanderer
# to Samurai while filtered to "Attack" stays on "Attack", same as
# switching characters doesn't reset anything else about this screen.
func _refresh_grid() -> void:
	var pool := CardPool.load_class_pool(_selected_character)
	if _selected_type == ALL_TYPES:
		_populate_grid(pool)
	else:
		var filtered: Array[CardData] = []
		for data: CardData in pool:
			if data.card_type == _selected_type:
				filtered.append(data)
		_populate_grid(filtered)
	_clear_detail()

func _populate_grid(cards: Array[CardData]) -> void:
	for child in card_grid.get_children():
		child.queue_free()
	var sorted := cards.duplicate()
	sorted.sort_custom(_compare_cards)
	for data: CardData in sorted:
		_add_card(data)

func _add_card(data: CardData) -> void:
	var card_instance: Card = CARD_SCENE.instantiate()
	card_grid.add_child(card_instance)
	card_instance.set_scale_factor(card_scale)
	card_instance.hover_scale = Vector2.ONE * card_hover_scale
	card_instance.hover_offset = Vector2(0, -card_hover_rise_px)
	card_instance.set_card_data(data)
	card_instance.set_affordable(true) # Not being played for energy here - always full brightness.
	# card_clicked is left unconnected, same as deck_viewer.gd outside
	# selection mode - this is browse-only, clicking a card does nothing.
	card_instance.card_hover_changed.connect(_on_card_hover_changed)

func _compare_cards(a: CardData, b: CardData) -> bool:
	if a.energy_cost != b.energy_cost:
		return a.energy_cost < b.energy_cost
	return a.card_name < b.card_name

# --- Detail panel ---
#
# First real reader of CardData.flavor_text (see that field's own doc in
# card_data.gd - "Reserved for the deck viewer to surface later
# (browsing, not optimizing, is where flavor belongs)"). Rules text
# (description) is already visible on the card face itself, so this
# panel only needs to add what the card face doesn't show.
func _on_card_hover_changed(card_data: CardData, hovering: bool) -> void:
	if hovering:
		detail_name_label.text = card_data.card_name
		detail_flavor_label.text = card_data.flavor_text
	else:
		_clear_detail()

func _clear_detail() -> void:
	detail_name_label.text = ""
	detail_flavor_label.text = ""

func _on_back_pressed() -> void:
	SceneTransition.go_to("res://title_screen.tscn")
