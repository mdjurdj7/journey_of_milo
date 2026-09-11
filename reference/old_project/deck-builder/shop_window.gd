extends CanvasLayer
class_name ShopWindow
# The SHOP room's real interaction, opened by walking into its field
# marker (see field_marker.gd's shop_entered signal and field_room.gd's
# wiring of it). Neutral, purely capability - no merchant flavor, since
# the game's aesthetic direction is still undecided (see DESIGN.md).
# Reuses the loot window's structural pattern - a panel of rows, a Leave
# button, blocking the field beneath it while open - the same way Deck
# Viewer already does it (pausing the whole SceneTree, PROCESS_MODE_
# ALWAYS so this keeps working while paused).
#
# Stock lives on RoomState (RoomState.shop_stock), rolled ONCE when the
# room itself is generated (see room_state.gd's _generate_shop_layout()).
# This window only ever DISPLAYS and DEPLETES that list - it never
# rerolls it, which is what makes closing the window and walking back
# onto the marker show exactly what's left rather than a fresh offering.
#
# Gold is spent immediately per purchase, not a cart/checkout flow: every
# Buy button calls straight into RunState.spend_gold() the instant it's
# pressed, and every row's own affordability is re-checked right after.

const SHOP_ROW_SCENE := preload("res://shop_row.tscn")
const CARD_SCENE := preload("res://card.tscn")

const CARD_PREVIEW_SCALE := 1.5
# Readable but small enough to sit in the margin beside Panel without
# overlapping it - see CardPreviewContainer's fixed position in shop_
# window.tscn, sized to match a Card at exactly this scale.
const CARD_PREVIEW_FADE_DURATION := 0.12

@export_group("Card offers")
@export var common_card_price: int = 45
@export var rare_card_price: int = 80
# ULTRA_RARE never appears in shop_stock in the first place (see room_
# state.gd's _roll_shop_stock()), so there's no price for it here.

@export_group("Card removal")
@export var removal_base_price: int = 50
@export var removal_price_increment: int = 25
# Each removal purchased THIS RUN (RunState.card_removals_purchased) adds
# one increment - removal is the single strongest deck-improving purchase
# in the genre, and a flat price would let one lucky gold haul buy
# several in the same visit; scaling keeps the first one cheap and
# accessible while curbing how many a single spike of gold can stack.

@export_group("Card upgrade")
@export var upgrade_price: int = 60
# FLAT, unlike removal_base_price above - the player's decision here is
# WHICH CARD to improve, not which upgrade to buy (every card offers at
# most a small, curated set of upgrades, decided at authoring time, not
# priced individually - see this feature's own brief). Deliberately NOT
# derived from the selected card or its upgrade either, for the same
# reason. Sits between removal's own base price (50, the strongest
# single purchase in the genre) and a rare card's price (80) - a real
# improvement, but a narrower one than outright removing a bad card.

@export_group("Rest")
@export var rest_heal_fraction: float = 0.25
@export var rest_price: int = 75
# The run's only healing outside rare ULTRA_RARE cards, priced
# accordingly - not a casual top-up.

@onready var backdrop: ColorRect = $Backdrop
@onready var gold_label: Label = $Panel/GoldLabel
@onready var card_rows_container: VBoxContainer = $Panel/ScrollContainer/Column/CardRowsContainer
@onready var remove_row: ShopRow = $Panel/ScrollContainer/Column/RemoveRow
@onready var upgrade_row: ShopRow = $Panel/ScrollContainer/Column/UpgradeRow
@onready var rest_row: ShopRow = $Panel/ScrollContainer/Column/RestRow
@onready var close_button: Button = $Panel/CloseButton
@onready var card_preview_container: Control = $CardPreviewContainer

var deck_viewer: DeckViewer
# Set by field_room.gd right after both this and DeckViewer exist as
# siblings - the "Remove a Card" purchase opens THIS SAME instance in
# selection mode rather than owning a second deck viewer, the same "one
# asset, not two" spirit as everywhere else this project reuses a scene
# instead of duplicating it.

var _card_offers: Array[Dictionary] = []
# {"row": ShopRow, "card_data": CardData, "price": int} per still-unsold
# card row currently on screen - keeps each row paired with the exact
# card/price it was built for without re-deriving that from RoomState.
# shop_stock's current index order (which shifts every time a purchase
# erases an entry).

var _preview_card_instance: Card = null
# Built once, on first hover, then just re-fed via set_card_data() every
# time a different row is hovered - same "one instance, restyled" idea
# as reward_screen.gd's rare-drop reveal, rather than instancing a fresh
# Card per hover.

var _previewing_row: ShopRow = null
# Which row the preview currently reflects, if any - guards against a
# stale unhover clobbering a freshly-shown preview: moving the mouse
# directly from row A to adjacent row B can fire B's hovered before A's
# unhovered (Godot doesn't guarantee the order), so _on_row_unhovered()
# only ever hides the preview if IT was the row that showed it.

var _preview_fade_tween: Tween

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Set here, not left to the .tscn's own mouse_filter = 0, alone
	# (2026-09-01, resave-fragility fix) - a stale Godot editor tab
	# resaving its in-memory copy already silently reverted this exact
	# value once (see this pass's own report). The scene's own value is
	# still there as documentation of intent, but THIS line is what
	# actually guarantees Backdrop keeps blocking clicks to whatever's
	# behind it, regardless of what any future editor resave does to the
	# .tscn.
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	close_button.pressed.connect(close_shop)
	remove_row.buy_pressed.connect(_on_remove_pressed)
	upgrade_row.buy_pressed.connect(_on_upgrade_pressed)
	rest_row.buy_pressed.connect(_on_rest_pressed)
	remove_row.set_highlighted(true)
	card_preview_container.modulate.a = 0.0

func _unhandled_input(event: InputEvent) -> void:
	# The deck_viewer.visible guard matters regardless of which sibling's
	# _unhandled_input actually fires first: without it, Escape while the
	# nested removal-selection DeckViewer is open could close the WHOLE
	# shop instead of just backing out of card selection - DeckViewer has
	# its own identical Escape handler (see deck_viewer.gd), which should
	# be the one to win while it's the topmost thing on screen.
	if visible and (deck_viewer == null or not deck_viewer.visible) and event.is_action_pressed("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()

func open_shop() -> void:
	_rebuild_card_rows()
	_refresh_services()
	gold_label.text = "Gold: %d" % RunState.gold
	visible = true
	get_tree().paused = true

func close_shop() -> void:
	visible = false
	get_tree().paused = false

# --- Card offers ---

func _rebuild_card_rows() -> void:
	_hide_preview_immediately()
	for offer in _card_offers:
		offer["row"].queue_free()
	_card_offers.clear()
	for card_data: CardData in RoomState.shop_stock:
		var row: ShopRow = SHOP_ROW_SCENE.instantiate()
		card_rows_container.add_child(row)
		var price := _card_price(card_data)
		row.set_offer(card_data.card_name, _rarity_name(card_data.rarity), price)
		row.set_affordable(RunState.gold >= price)
		row.set_card_data(card_data)
		row.buy_pressed.connect(func(): _on_card_buy_pressed(card_data, row))
		row.hovered.connect(_on_row_hovered.bind(row))
		row.unhovered.connect(_on_row_unhovered.bind(row))
		_card_offers.append({"row": row, "card_data": card_data, "price": price})

func _card_price(card_data: CardData) -> int:
	return rare_card_price if card_data.rarity == CardData.Rarity.RARE else common_card_price

func _rarity_name(rarity: CardData.Rarity) -> String:
	return "Rare" if rarity == CardData.Rarity.RARE else "Common"

func _on_card_buy_pressed(card_data: CardData, row: ShopRow) -> void:
	var price := _card_price(card_data)
	if RunState.gold < price:
		return # The Buy button should already be disabled - defensive, not expected to trigger.
	RunState.spend_gold(price)
	RunState.add_card_to_deck(card_data)
	# The card entering the deck, layered alongside gold_claimed below (the
	# GOLD side of the same purchase) - same "add_card" cue every other
	# card-acquisition moment plays, this is a two-cue transaction (spend
	# AND gain) rather than either replacing the other.
	AudioManager.play_sfx("add_card")
	RoomState.shop_stock.erase(card_data)
	AudioManager.play_sfx("gold_claimed") # Same "gold changed hands" cue the loot window/chests already use.
	for i in _card_offers.size():
		if _card_offers[i]["row"] == row:
			_card_offers.remove_at(i)
			break
	if _previewing_row == row:
		# The row is about to be gone, and with it any chance of a natural
		# mouse_exited ever firing for it (the mouse hasn't necessarily
		# moved) - clean up explicitly rather than leaving the just-bought
		# card's preview stuck on screen indefinitely.
		_previewing_row = null
		_hide_card_preview()
	row.queue_free()
	_refresh_after_purchase()

# --- Card offer preview ---
#
# Reuses the exact Card scene hand cards/reward cards/the deck viewer all
# use - same hover-to-reveal language, just triggered by hovering a SHOP
# ROW instead of the card itself. Buying is entirely separate (BuyButton's
# own press, see ShopRow.buy_pressed) and never reads hover state, so
# inspecting a card by hovering it can never trigger a purchase.

func _on_row_hovered(card_data: CardData, row: ShopRow) -> void:
	_previewing_row = row
	_show_card_preview(card_data)

func _on_row_unhovered(row: ShopRow) -> void:
	if _previewing_row == row:
		_previewing_row = null
		_hide_card_preview()

func _show_card_preview(card_data: CardData) -> void:
	if _preview_card_instance == null:
		_preview_card_instance = CARD_SCENE.instantiate()
		card_preview_container.add_child(_preview_card_instance)
		_preview_card_instance.set_scale_factor(CARD_PREVIEW_SCALE)
		_preview_card_instance.set_affordable(true) # Not being played for energy here - always full brightness, same as every other read-only card display (reward screen, deck viewer).
		_preview_card_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE # Purely a display - shouldn't be hoverable/clickable in its own right, off to the side of the row that's actually driving it.
	_preview_card_instance.set_card_data(card_data)
	card_preview_container.visible = true
	if _preview_fade_tween:
		_preview_fade_tween.kill()
	_preview_fade_tween = create_tween()
	_preview_fade_tween.tween_property(card_preview_container, "modulate:a", 1.0, CARD_PREVIEW_FADE_DURATION)

func _hide_card_preview() -> void:
	if _preview_fade_tween:
		_preview_fade_tween.kill()
	_preview_fade_tween = create_tween()
	_preview_fade_tween.tween_property(card_preview_container, "modulate:a", 0.0, CARD_PREVIEW_FADE_DURATION)
	_preview_fade_tween.tween_callback(func(): card_preview_container.visible = false)

# Used when rebuilding the row list itself (open_shop()) - the OLD rows
# are about to be freed, so any in-progress fade referencing them (via
# _previewing_row) needs to snap off immediately rather than tween, or a
# purchase made while hovering could leave a lingering fade-out racing
# against the brand new row list.
func _hide_preview_immediately() -> void:
	if _preview_fade_tween:
		_preview_fade_tween.kill()
	card_preview_container.visible = false
	card_preview_container.modulate.a = 0.0
	_previewing_row = null

# --- Card removal ---

func _removal_price() -> int:
	return removal_base_price + RunState.card_removals_purchased * removal_price_increment

func _on_remove_pressed() -> void:
	var price := _removal_price()
	if RunState.gold < price:
		return
	# If a previous "Remove a Card" was opened and then cancelled (Close/
	# Escape instead of picking a card), the one-shot connection below
	# never fired and is still attached - connecting the same callable
	# again without disconnecting first would error. manage_pause=false:
	# the tree is already paused by THIS window (see open_shop()) -
	# letting DeckViewer's own close() also resume it would wake the field
	# up while the shop is still visibly open on top of it.
	if deck_viewer.card_selected.is_connected(_on_removal_card_selected):
		deck_viewer.card_selected.disconnect(_on_removal_card_selected)
	deck_viewer.card_selected.connect(_on_removal_card_selected, CONNECT_ONE_SHOT)
	deck_viewer.open_cards(RunState.deck, "Remove a Card - Select One", true, false)

func _on_removal_card_selected(card_data: CardData) -> void:
	var price := _removal_price()
	RunState.spend_gold(price)
	RunState.remove_card_from_deck(card_data)
	RunState.card_removals_purchased += 1
	AudioManager.play_sfx("gold_claimed")
	deck_viewer.close()
	_refresh_after_purchase()

# --- Card upgrade ---
#
# Sells a single generic "upgrade a card" offer, not specific upgrades
# priced individually - the player's decision is which card to improve,
# not which upgrade to buy (see upgrade_price's own doc). Repeatable
# within a visit, same as Remove a Card above (no one-shot "already
# used" flag on either) - _refresh_after_purchase() re-evaluates this
# row's own affordability/eligibility after every purchase exactly like
# it already does for remove_row, rather than the two services behaving
# differently from each other.
#
# CardUpgradeService owns its OWN DeckViewer instance (unlike removal
# above, which reuses THIS window's externally-wired one) - see card_
# upgrade_service.gd's own header for why. manage_pause=false for the
# exact same reason _on_remove_pressed() passes it to ITS deck_viewer:
# this window already paused the tree (see open_shop()); letting the
# service's own close() unpause it too would wake the field up while the
# shop is still visibly open on top of it.

func _on_upgrade_pressed() -> void:
	if RunState.gold < upgrade_price or not CardUpgradeService.has_eligible_cards():
		return # Buy should already be disabled for both cases - defensive, not expected to trigger.
	_run_upgrade_purchase()

# A real coroutine (offer_upgrade() awaits the player's own selection),
# split out from _on_upgrade_pressed() so that function can stay a plain
# fire-and-forget call - same "guard function calls an async worker"
# split _on_dev_upgrade_button_pressed()/_run_dev_upgrade() already
# establishes in battle.gd.
func _run_upgrade_purchase() -> void:
	var result: Dictionary = await CardUpgradeService.offer_upgrade(Callable(), false)
	match result["outcome"]:
		CardUpgradeService.Outcome.UPGRADED:
			RunState.spend_gold(upgrade_price)
			AudioManager.play_sfx("gold_claimed")
			_refresh_after_purchase()
		CardUpgradeService.Outcome.CANCELLED, CardUpgradeService.Outcome.NO_ELIGIBLE_CARDS:
			pass # No gold deducted, deck untouched, offer stays exactly as it was.

# --- Rest ---

func _on_rest_pressed() -> void:
	if RunState.gold < rest_price or RunState.player_hp >= RunState.player_max_hp:
		return
	RunState.spend_gold(rest_price)
	var heal_amount := roundi(RunState.player_max_hp * rest_heal_fraction)
	RunState.heal(heal_amount)
	AudioManager.play_sfx("heal")
	_refresh_after_purchase()

# --- Shared refresh ---

func _refresh_after_purchase() -> void:
	gold_label.text = "Gold: %d" % RunState.gold
	for offer in _card_offers:
		offer["row"].set_affordable(RunState.gold >= offer["price"])
	_refresh_services()

func _refresh_services() -> void:
	var removal_price := _removal_price()
	remove_row.set_offer("Remove a Card", "Permanently remove one card from your deck.", removal_price)
	remove_row.set_affordable(RunState.gold >= removal_price)

	upgrade_row.set_offer("Upgrade a Card", "Permanently improve one card in your deck.", upgrade_price)
	# Greyed whenever there's nothing it could actually do (see this
	# feature's own brief point 4) as well as when it's simply unaffordable
	# - both fold into the one set_affordable() call ShopRow already
	# exposes rather than adding a second, parallel "eligible" concept to
	# that shared component. has_eligible_cards() is the SAME check offer_
	# upgrade() itself uses internally, not a re-derived copy of it.
	upgrade_row.set_affordable(RunState.gold >= upgrade_price and CardUpgradeService.has_eligible_cards())

	var at_full_hp := RunState.player_hp >= RunState.player_max_hp
	rest_row.set_offer("Rest", "Heal %d%% of max HP." % roundi(rest_heal_fraction * 100), rest_price)
	rest_row.set_affordable(not at_full_hp and RunState.gold >= rest_price)
