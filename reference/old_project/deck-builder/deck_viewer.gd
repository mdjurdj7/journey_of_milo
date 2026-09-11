extends CanvasLayer
class_name DeckViewer
# A reusable "look at a pile of cards" overlay - not battle-specific. It
# reads RunState.deck itself (see open_deck() below) rather than being
# handed data by whoever opens it, so any scene can add this as a plain
# child anywhere in its tree and just call open_deck()/close() - no
# wiring back to the caller needed, no matter which scene that is.
#
# This is its own CanvasLayer (a high `layer`, see deck_viewer.tscn) so
# it always draws on top regardless of where in a scene it's parented -
# it doesn't need to live inside that scene's own "UI" CanvasLayer the
# way battle.tscn/reward_screen.tscn's other panels do.
#
# While open, the whole SceneTree is paused (see open_cards()/close()) -
# the simplest way to guarantee nothing underneath can act while this is
# up. A full-screen blocking Control (the Backdrop) already stops mouse
# clicks reaching anything behind it (same trick reward_screen.tscn's
# CardChoiceOverlay/RareDropOverlay/LeaveConfirmPanel use), but that
# alone wouldn't stop field movement - player.gd polls raw key state
# every physics frame, which no Control's mouse filter can intercept.
# Pausing blocks both uniformly, for any scene this ever gets added to,
# without battle.gd/field_room.gd/player.gd needing to know this overlay
# exists at all. This node (and everything under it) is set
# PROCESS_MODE_ALWAYS in _ready() so it keeps working while paused.
#
# --- Layout (REWORKED - see DESIGN.md) ---
#
# Everything below the title - the equipped-weapon row AND the card
# grid - lives inside ONE ScrollContainer now (ContentColumn, a single
# VBoxContainer: EquippedLabel, EquippedIconRow, DeckLabel, CardGrid, in
# that order). Nothing here is pinned above the scroll anymore - the
# equipped row scrolls with everything else, exactly like any other
# item in the list. Hiding a child (see open_cards()'s selection_mode
# handling) just makes VBoxContainer reflow around the gap on its own;
# nothing here computes manual offsets to compensate.

const CARD_SCENE := preload("res://card.tscn")
const WEAPON_CARD_SCENE := preload("res://weapon_card.tscn")

@export_group("Deck Grid")
@export var deck_card_scale: float = 0.8
# This view's OWN card scale, independent of every other place a Card
# shows up (hand, reward screen, shop) - see card.gd's set_scale_factor().
# REVISED (2026-08-25): the original 0.45 default made cards barely
# legible at rest AND blurry on hover. The hover blur specifically is a
# real scaling artifact, not a bug: Card's hover animation (hover_scale
# below) only ever applies a `visual.scale` TRANSFORM - a purely visual
# stretch of whatever was already rasterized at the RESTING size (fonts,
# in particular, are rasterized at name_font_size_px * deck_card_scale
# and never re-rasterized larger just because the transform grew). At
# 0.45 with the old 2.6x hover multiplier, that meant a ~10px name font
# stretched to a DISPLAYED ~26px - heavy visible blur. A fully crisp fix
# would mean re-rasterizing at native resolution on every hover (calling
# set_scale_factor() instead of just scaling the transform), but that
# changes custom_minimum_size, which GridContainer uses for cell sizing -
# every OTHER card in the grid would jump to make room the instant one
# card is hovered. Not worth that tradeoff. The practical fix instead:
# raise the REST size enough that it's comfortably legible on its own
# (fonts now rasterize at a real, legible size to begin with), and lower
# the hover multiplier to match (less multiplication needed once rest
# is already close to readable) - the stretch ratio, and therefore the
# visible blur, drops sharply as a result.
@export var deck_card_hover_scale: float = 1.35
# How much bigger a card gets on hover, ON TOP OF deck_card_scale above -
# Card.hover_scale is a multiplier on its OWN current size (see card.gd's
# _play_hover_tween()), not an absolute target, so this is set directly
# on every card this view creates (see _add_card()). At the defaults
# above, a hovered card reaches roughly design_size itself (~267x373) -
# close to a normal card's own natural, unscaled size.
@export var deck_card_hover_rise_px: float = 40.0
@export var deck_grid_columns: int = 6
# A FIXED row width, not "however many fit the panel" - filling the
# full 1800px panel width (the original 5-column layout's own scale
# just happened to roughly do this; smaller cards left it looking like
# one long row plus a lone orphan card on the next line) reads as
# unbalanced. A fixed column count means the grid always resolves into
# clean, evenly-filled rows instead.

@export_group("Equipped Slot")
@export var equipped_slot_size: float = 88.0
# The framed box the equipped weapon's icon sits in (see EquippedSlot's
# own StyleBoxFlat in deck_viewer.tscn) - a defined equipment slot, not
# a stray floating image. Still deliberately much smaller than a card
# (a resting deck-grid card is roughly design_size * deck_card_scale,
# ~111x155 at the default above) - this is a glance-sized indicator;
# the full detail lives in the hover preview (see _show_weapon_preview()
# below), not in growing this slot to compete with the card grid.
@export var equipped_icon_padding_px: float = 10.0
# How much smaller the icon itself sits inside the slot's own frame.

const WEAPON_PREVIEW_FADE_DURATION := 0.12
# Same fade duration reward_screen.gd's own weapon-row hover preview
# uses - one hover-to-reveal feel wherever a weapon gets previewed.

@export_group("Content Spacing")
# --- Vertical centering (see _center_content_vertically() below) ---
#
# Fixed clearance always kept above/below the content block, REGARDLESS
# of how much slack centering ends up distributing. REVISED (2026-08-
# 25): the top value used to double as hover-growth clearance for the
# grid's first row, which is why it was large (90px) - but the Equipped
# section itself (EquippedLabel + EquippedIconRow, well over 100px)
# already sits between this margin and the grid, so the grid's first
# row was never actually at risk of touching THIS particular margin in
# the first place. That made the gap between the title and "Equipped"
# far bigger than it needed to be for no real benefit - shrunk to a
# small aesthetic gap instead. CONTENT_BOTTOM_CLEARANCE_PX still guards
# real hover-growth clipping for the grid's LAST row (nothing sits
# below the grid to absorb that the way the Equipped section does
# above it), so it stays larger.
@export var content_top_clearance_px: float = 24.0
@export var content_bottom_clearance_px: float = 60.0

signal card_selected(card_data: CardData)
# Only meaningful while open in selection mode (see open_cards()'s
# selection_mode param below) - shop_window.gd's card-removal flow is the
# one caller today, listening with CONNECT_ONE_SHOT so picking a card
# resolves the purchase without this viewer needing to know what
# "selecting" means (same "just report the click" shape as Card.card_
# clicked/LootRow.row_clicked).

@onready var backdrop: ColorRect = $Backdrop
@onready var title_label: Label = $Panel/TitleLabel
@onready var scroll_container: ScrollContainer = $Panel/ScrollContainer
@onready var content_margin: MarginContainer = $Panel/ScrollContainer/ContentMargin
@onready var content_column: VBoxContainer = $Panel/ScrollContainer/ContentMargin/ContentColumn
@onready var equipped_label: Label = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedLabel
@onready var equipped_icon_row: Control = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow
@onready var equipped_slot: Panel = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/EquippedSlot
@onready var equipped_icon: TextureRect = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/EquippedSlot/EquippedIcon
@onready var equipped_fallback_label: Label = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/EquippedSlot/EquippedFallbackLabel
@onready var trinket_slot: Panel = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/TrinketSlot
@onready var trinket_icon: TextureRect = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/TrinketSlot/TrinketIcon
@onready var trinket_fallback_label: Label = $Panel/ScrollContainer/ContentMargin/ContentColumn/EquippedIconRow/TrinketSlot/TrinketFallbackLabel
@onready var deck_label: Label = $Panel/ScrollContainer/ContentMargin/ContentColumn/DeckLabel
@onready var card_grid: GridContainer = $Panel/ScrollContainer/ContentMargin/ContentColumn/CardGrid
@onready var close_button: Button = $Panel/CloseButton
@onready var weapon_preview_container: Control = $Panel/WeaponPreviewContainer

var _selection_mode: bool = false

var _manages_pause: bool = true
# False when a caller that has ALREADY paused the tree (shop_window.gd,
# nested inside its own already-open, already-pausing window) opens this
# - without this, close() unconditionally resuming the tree would wake
# the field back up even though the shop window is still visibly open on
# top of it. True (the default) covers every other caller (the field's
# Deck button, the reward screen's Deck button), which open this as the
# ONLY thing pausing anything.

# --- Equipped-weapon hover preview ---
#
# Same "one instance, built lazily on first hover, then just re-fed"
# shape as reward_screen.gd's own weapon-row preview (which itself
# mirrors shop_window.gd's card-offer preview) - there's only ONE
# hoverable row here, not a list, so this needs none of those screens'
# "which row is currently being previewed" tracking.
var _preview_weapon_instance: WeaponCard = null
var _weapon_preview_fade_tween: Tween

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Set here, not left to the .tscn's own mouse_filter = 0, alone
	# (2026-09-01, resave-fragility fix) - a stale Godot editor tab
	# resaving its in-memory copy already silently reverted this exact
	# value on ShopWindow's own Backdrop once (see that pass's own
	# report). The scene's own value is still there as documentation of
	# intent, but THIS line is what actually guarantees Backdrop keeps
	# blocking clicks to whatever's behind it, regardless of what any
	# future editor resave does to the .tscn.
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.pressed.connect(close)
	weapon_preview_container.modulate.a = 0.0
	equipped_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	equipped_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Hover detection lives on EquippedSlot itself, not the wide
	# EquippedIconRow that centers it - REVISED (2026-08-25): connecting
	# it to the row meant the hoverable area was the row's full width
	# (mostly empty space either side of the slot), while the slot ITSELF
	# (a child Panel, default mouse_filter STOP) sat on top and silently
	# swallowed input over its own rect without anything listening to
	# IT - hovering the visible icon did nothing, hovering the empty
	# margins around it did. equipped_icon/equipped_fallback_label are
	# set to IGNORE so they can never repeat that same shadowing one
	# level down; equipped_icon_row is IGNORE too since it's now purely
	# a centering container, nothing here should react to it directly.
	equipped_icon_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipped_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipped_fallback_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equipped_slot.mouse_entered.connect(_on_equipped_icon_hovered)
	equipped_slot.mouse_exited.connect(_on_equipped_icon_unhovered)
	_apply_equipped_slot_size()
	card_grid.columns = deck_grid_columns

# The one place equipped_slot_size/equipped_icon_padding_px actually
# land on nodes - deck_viewer.tscn bakes in matching starting values so
# the scene still looks right in the editor before this ever runs, but
# this is what makes the @export actually tunable rather than just a
# number nobody reads.
func _apply_equipped_slot_size() -> void:
	var half := equipped_slot_size / 2.0
	equipped_slot.offset_left = -half
	equipped_slot.offset_top = -half
	equipped_slot.offset_right = half
	equipped_slot.offset_bottom = half
	# A little breathing room above/below the slot itself, same spirit
	# as CONTENT_TOP/BOTTOM_CLEARANCE_PX but much smaller - this is
	# just "don't let the slot touch EquippedLabel/DeckLabel," not
	# hover-growth clearance (the slot itself doesn't hover-enlarge).
	equipped_icon_row.custom_minimum_size.y = equipped_slot_size + 16.0
	var pad := equipped_icon_padding_px
	equipped_icon.offset_left = pad
	equipped_icon.offset_top = pad
	equipped_icon.offset_right = -pad
	equipped_icon.offset_bottom = -pad

# Escape closes the overlay from anywhere it's opened - no per-scene
# wiring needed, this node handles its own input. Guarded by `visible`
# since _unhandled_input still fires on hidden PROCESS_MODE_ALWAYS nodes
# (visibility only affects rendering, not processing).
func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# The one real mode today - see open_cards() below for the general shape
# a future draw-pile/discard-pile viewer would reuse instead of
# rewriting the sort/grid/scroll machinery. Battle's draw/discard piles
# are per-battle local arrays (battle.gd), not run-level state, so a
# future opener for those would live as a wrapper in battle.gd calling
# open_cards(battle.draw_pile, "Draw Pile (%d)" % battle.draw_pile.size())
# - this overlay doesn't need to know battle.gd exists to support that.
#
# manage_pause defaults to true (this call pauses the tree itself, and
# unpauses it again on close - the common case, e.g. the field's own
# Deck button). Pass false when the caller has already paused the tree
# through some OTHER still-open overlay (2026-08-26, first real case:
# the reward screen's own Deck button, clickable from its card-choice
# modal - see reward_screen.gd's own wiring) - same "don't unpause out
# from under a caller that's still open" reasoning open_cards()'s own
# manage_pause already documents for shop_window.gd's nested case.
func open_deck(manage_pause: bool = true) -> void:
	open_cards(RunState.deck, "Belongings", false, manage_pause)

# The general entry point - takes whatever card list and title it's
# given. Sorts a COPY (cost ascending, then alphabetical - see
# _compare_cards()) so the same deck always displays the same way
# regardless of draw order, without touching the array it was handed.
#
# The Equipped section (equipped_label + equipped_icon_row) only makes
# sense for the general "look at my stuff" view - shop_window.gd's
# card-removal flow opens this in selection_mode for a single focused
# task (pick a card to remove), where a hoverable weapon sitting above
# the list would just invite a hover that does nothing useful there.
# Hidden there; DeckLabel and CardGrid stay, and the VBoxContainer they
# all share reflows to fill the gap on its own.
func open_cards(cards: Array[CardData], title: String, selection_mode: bool = false, manage_pause: bool = true) -> void:
	title_label.text = title
	_selection_mode = selection_mode
	_manages_pause = manage_pause
	_populate(cards)
	_refresh_equipped_row()
	_refresh_equipped_trinket_row()
	deck_label.text = "Deck (%d)" % cards.size()
	var show_equipment_section := not selection_mode
	equipped_label.visible = show_equipment_section
	equipped_icon_row.visible = show_equipment_section
	if not show_equipment_section:
		_hide_weapon_preview_immediately()
	_center_content_vertically()
	visible = true
	if manage_pause:
		get_tree().paused = true

# Vertically centers ContentColumn within ScrollContainer's own
# viewport WHEN there's slack to distribute (a short deck, or few
# cards visible in selection mode) - by growing ContentMargin's
# top/bottom margins evenly past their fixed clearance baseline
# (CONTENT_TOP/BOTTOM_CLEARANCE_PX above), rather than leaving all the
# leftover space stranded at the bottom the way plain top-aligned
# VBoxContainer content otherwise would. Once content is TALLER than
# the viewport (a big deck), `extra` clamps to 0 and this is a no-op -
# scrolling from the top is the correct, expected behavior there, not
# something centering should fight.
#
# get_combined_minimum_size() is queried directly rather than waiting a
# frame for layout to settle - Control's minimum-size system recomputes
# synchronously on demand (it isn't render-dependent the way actual
# `size`/`position` are), so this reads ContentColumn's true height
# immediately after _populate()/visibility changes above, no `await`
# needed and no one-frame "pop" from top-aligned to centered.
func _center_content_vertically() -> void:
	var content_height := content_column.get_combined_minimum_size().y
	var viewport_height := scroll_container.size.y
	var natural_block_height := content_height + content_top_clearance_px + content_bottom_clearance_px
	var extra := maxf(viewport_height - natural_block_height, 0.0)
	content_margin.add_theme_constant_override("margin_top", content_top_clearance_px + extra / 2.0)
	content_margin.add_theme_constant_override("margin_bottom", content_bottom_clearance_px + extra / 2.0)

# The equipped weapon (RunState.equipped_weapon - see run_state.gd's own
# note) is run-level state, not tied to whatever card list this viewer
# was opened with, so it's refreshed unconditionally here rather than
# threaded through open_cards()'s own params. Deliberately compact - a
# small icon, not the full WeaponCard (see DESIGN.md's own note on why
# the earlier frozen-full-card version wasted too much of the screen) -
# hovering it reveals the full WeaponCard instead (see _on_equipped_
# icon_hovered() below), the same "small in the list, full detail on
# hover" shape a LootRow/ShopRow already use for their own previews.
# Three states, same "empty means unaffected" shape everywhere else in
# this project uses: nothing equipped -> "None"; equipped but no
# icon_texture yet -> the weapon's name as plain text; equipped with
# art -> the icon itself. Never more than one of icon/fallback visible
# at once.
func _refresh_equipped_row() -> void:
	var weapon: WeaponData = RunState.equipped_weapon
	var has_icon := weapon != null and weapon.icon_texture != null
	equipped_icon.visible = has_icon
	if has_icon:
		equipped_icon.texture = weapon.icon_texture
	equipped_fallback_label.visible = not has_icon
	equipped_fallback_label.text = weapon.weapon_name if weapon != null else "None"

# The equipped trinket (RunState.equipped_trinket) beside the weapon
# above - same shape as _refresh_equipped_row(), no hover preview (out
# of scope for this pass, see this pass's own brief): nothing equipped
# -> "None"; equipped but no icon_texture yet -> the trinket's name as
# plain text; equipped with art -> the icon itself.
func _refresh_equipped_trinket_row() -> void:
	var trinket: TrinketData = RunState.equipped_trinket
	var has_icon := trinket != null and trinket.icon_texture != null
	trinket_icon.visible = has_icon
	if has_icon:
		trinket_icon.texture = trinket.icon_texture
	trinket_fallback_label.visible = not has_icon
	trinket_fallback_label.text = trinket.trinket_name if trinket != null else "None"

# --- Equipped-weapon hover preview (see class-level note above) ---
func _on_equipped_icon_hovered() -> void:
	if RunState.equipped_weapon == null:
		return
	_show_weapon_preview(RunState.equipped_weapon)

func _on_equipped_icon_unhovered() -> void:
	_hide_weapon_preview()

func _show_weapon_preview(weapon: WeaponData) -> void:
	if _preview_weapon_instance == null:
		_preview_weapon_instance = WEAPON_CARD_SCENE.instantiate()
		weapon_preview_container.add_child(_preview_weapon_instance)
	_preview_weapon_instance.set_weapon_data(weapon)
	weapon_preview_container.visible = true
	if _weapon_preview_fade_tween:
		_weapon_preview_fade_tween.kill()
	_weapon_preview_fade_tween = create_tween()
	_weapon_preview_fade_tween.tween_property(weapon_preview_container, "modulate:a", 1.0, WEAPON_PREVIEW_FADE_DURATION)

func _hide_weapon_preview() -> void:
	if _weapon_preview_fade_tween:
		_weapon_preview_fade_tween.kill()
	_weapon_preview_fade_tween = create_tween()
	_weapon_preview_fade_tween.tween_property(weapon_preview_container, "modulate:a", 0.0, WEAPON_PREVIEW_FADE_DURATION)
	_weapon_preview_fade_tween.tween_callback(func(): weapon_preview_container.visible = false)

# Used when the Equipped section itself just got hidden (selection
# mode) - a fade in progress would otherwise keep the preview container
# visible (mid-tween) floating over a screen that no longer has
# anything hoverable to have triggered it.
func _hide_weapon_preview_immediately() -> void:
	if _weapon_preview_fade_tween:
		_weapon_preview_fade_tween.kill()
	weapon_preview_container.visible = false
	weapon_preview_container.modulate.a = 0.0

func close() -> void:
	visible = false
	_hide_weapon_preview_immediately()
	if _manages_pause:
		get_tree().paused = false

func _populate(cards: Array[CardData]) -> void:
	for child in card_grid.get_children():
		child.queue_free()
	var sorted := cards.duplicate()
	sorted.sort_custom(_compare_cards)
	for data: CardData in sorted:
		_add_card(data)

# Duplicates show individually, not stacked with a count - each entry in
# `cards` (RunState.deck, most of the time) gets its own Card instance
# here, so 5x Slash in the deck is 5 Slash cards in the grid, same as
# the deck itself represents them.
func _add_card(data: CardData) -> void:
	var card_instance: Card = CARD_SCENE.instantiate()
	card_grid.add_child(card_instance)
	card_instance.set_scale_factor(deck_card_scale)
	# Bigger hover pop than Card's own defaults (see deck_card_hover_
	# scale/deck_card_hover_rise_px above) - the whole point of shrinking
	# cards this far is that hovering one has to actually enlarge it
	# enough to read, not just nudge it.
	card_instance.hover_scale = Vector2.ONE * deck_card_hover_scale
	card_instance.hover_offset = Vector2(0, -deck_card_hover_rise_px)
	card_instance.set_card_data(data)
	card_instance.set_affordable(true) # Not being played for energy here - always full brightness.
	# Outside selection mode, card_clicked is deliberately left unconnected
	# - hovering still works (Card's hover animation isn't gated on
	# anything this script does), but a click has nothing listening for
	# it, which is exactly "clicking does nothing, this is a viewer." In
	# selection mode (shop_window.gd's card-removal flow), a click instead
	# reports which card was picked via card_selected - this viewer still
	# doesn't know what picking a card actually DOES, same as everywhere
	# else in this project.
	if _selection_mode:
		card_instance.card_clicked.connect(func(clicked_data): card_selected.emit(clicked_data))

func _compare_cards(a: CardData, b: CardData) -> bool:
	if a.energy_cost != b.energy_cost:
		return a.energy_cost < b.energy_cost
	return a.card_name < b.card_name
