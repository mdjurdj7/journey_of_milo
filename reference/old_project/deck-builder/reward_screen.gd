extends Node2D
# Shown after winning a battle, before returning to the field room (or,
# from the title screen's "Dev: Battle Chain" shortcut, before the next
# chained battle - see _continue_to_next_battle()). Lists this battle's
# rewards as a "Loot" window: rows the player claims by clicking, in any
# order, before pressing Continue. This is still where "moving on"
# happens - advancing RunState's battle number and transitioning onward -
# gated behind Continue (with a confirmation if anything's still
# unclaimed) instead of a single forced reward pick.
#
# --- Loot architecture ---
#
# Each reward is a LootEntry (see loot_entry.gd): a type tag plus
# whatever data that type needs (a gold amount, or a set of card
# choices). Gold/card/rare-drop entries all go through the SAME shared
# path: hand each one to a LootRow to display (see loot_row.tscn/.gd),
# react to whichever row gets clicked through ONE dispatch point,
# _claim_entry(), that matches on entry.loot_type - the same "one enum,
# one match statement" shape battle.gd's _resolve_card_effect() already
# uses for card effects.
#
# WEAPON is a partial exception: equipment is a decision, not a plain
# receipt, so claiming its row never just applies an effect the way GOLD/
# CARD_REWARD/RARE_CARD_DROP do - it opens weapon_pickup_window, the same
# dedicated Equip/Leave Behind screen every weapon reward has always used
# (see _claim_entry()'s own WEAPON case and _open_weapon_reward() below).
# For a CHEST-sourced weapon specifically (2026-08-25 rework, see DESIGN.
# md's Rewards note), that row behaves differently from every other loot
# type once resolved: Leaving it does NOT claim the row - it stays
# exactly as clickable as before, so the same weapon can be reconsidered
# again before the chest is closed (see _on_weapon_pickup_resolved()'s
# own note on why "reclaimable" needs that). Taking it DOES claim the
# row, but removes it entirely rather than leaving a greyed receipt
# behind - there's nothing left to compare once equipped. A weapon from
# any OTHER source (the Pay House, a title-screen dev-grant) still opens
# the SAME window immediately in _ready(), with no row and no loot list
# at all - that path is completely unchanged from before this rework.

const CARD_SCENE := preload("res://card.tscn")
const LOOT_ROW_SCENE := preload("res://loot_row.tscn")
const CARD_CHOICE_COUNT := 3
const REWARD_CARD_SCALE := 1.12
# The regular 3-card choice reward's scale - bigger than a hand card
# (card.gd's design size, 247.5x345), there's only three of them and
# plenty of screen to spare here, unlike a battle hand that can hold up
# to ten. See card_reward_container's sizing in reward_screen.tscn, which
# has to fit three cards at this scale side by side. Was 1.6 - sized down
# ~30% by request.
const RARE_DROP_CARD_SCALE := 1.6
# The rare-drop reveal's own scale - deliberately kept at the ORIGINAL
# size rather than following REWARD_CARD_SCALE's reduction above (a
# separate, later request: the rare drop should stay exactly as it was).
# The two used to share one constant; now genuinely independent, so
# retuning one can never accidentally drag the other along with it. See
# rare_card_container's own custom_minimum_size in reward_screen.tscn,
# sized to match THIS constant, not REWARD_CARD_SCALE.
const MIN_GOLD_REWARD := 15
const MAX_GOLD_REWARD := 25

const ROW_HEIGHT := 110.0
# Matches loot_row.tscn's own custom_minimum_size.y - used to compute
# RowScrollContainer's height from the actual row count (see
# _update_row_scroll_height()), not a fixed guess.
@export var max_visible_rows: int = 4
# Beyond this many rows, the list scrolls instead of growing further -
# defensive: today's real max is 3 (gold, card choice, rare drop), but
# this keeps Continue guaranteed reachable (see DESIGN.md's optional-
# UI-elements convention) if a future reward type ever pushes that
# higher, rather than the row list pushing Continue down indefinitely.

# Relative odds of COMMON vs. RARE being rolled for a regular card
# reward slot (see _roll_rarity()) - ULTRA_RARE and SECRET_RARE aren't
# part of this table at all (see DESIGN.md's Rewards note: cards are
# drops, not currency). They don't need to add up to 100; only the ratio
# between them matters.
@export var common_weight: float = 70.0
@export var rare_weight: float = 24.0

# Whether a regular card-choice row appears at all this battle - see
# _generate_loot(). Not guaranteed on purpose: a card choice showing up
# most of the time, but not every time, is what makes it feel like a
# drop instead of a currency payout that's always there.
@export_range(0.0, 1.0, 0.01) var card_reward_chance: float = 0.6

# Independent of card_reward_chance above - a battle can produce a
# regular card choice, a rare drop, both, or neither. Kept low and
# separate on purpose (see _roll_rare_drop()): this is the ONE tier that
# still feels rare when it shows up.
@export_range(0.0, 1.0, 0.01) var rare_drop_chance: float = 0.08

# --- Elite rewards (DECIDED - see DESIGN.md's ELITE Rooms section) ---
#
# Read once per battle from RoomState.current_room_type - still accurate
# by the time this screen loads, since nothing between "the elite blob
# died" and "this screen's _ready()" advances to a new room (see room_
# state.gd's load_room(), the only thing that changes it). Choosing the
# harder fight should visibly pay off, not just feel harder.
@export var elite_gold_multiplier: float = 2.0
@export_range(0.0, 1.0, 0.01) var elite_rare_drop_chance: float = 0.35
# Well above rare_drop_chance (0.08) - "meaningfully higher," not just a
# marginal bump.

@onready var loot_panel: Control = $UI/LootPanel
@onready var row_scroll_container: ScrollContainer = $UI/LootPanel/MainColumn/RowScrollContainer
@onready var loot_row_container: VBoxContainer = $UI/LootPanel/MainColumn/RowScrollContainer/LootRowContainer
@onready var continue_button: Button = $UI/LootPanel/MainColumn/ContinueButton
@onready var deck_button: Button = $UI/DeckButton
@onready var deck_viewer: DeckViewer = $DeckViewer

@onready var card_choice_overlay: Control = $UI/CardChoiceOverlay
@onready var card_reward_container: HBoxContainer = $UI/CardChoiceOverlay/ChoiceModalPanel/MainColumn/CardRewardContainer
@onready var skip_button: Button = $UI/CardChoiceOverlay/ChoiceModalPanel/MainColumn/SkipButton

@onready var rare_drop_overlay: Control = $UI/RareDropOverlay
@onready var rare_card_container: Control = $UI/RareDropOverlay/MainColumn/RareCardContainer
@onready var rare_take_leave_container: HBoxContainer = $UI/RareDropOverlay/MainColumn/TakeLeaveContainer
@onready var rare_take_button: Button = $UI/RareDropOverlay/MainColumn/TakeLeaveContainer/TakeButton
@onready var rare_leave_button: Button = $UI/RareDropOverlay/MainColumn/TakeLeaveContainer/LeaveButton

@onready var leave_confirm_panel: Control = $UI/LeaveConfirmPanel
@onready var leave_button: Button = $UI/LeaveConfirmPanel/ConfirmBox/LeaveButton
@onready var cancel_button: Button = $UI/LeaveConfirmPanel/ConfirmBox/CancelButton

@onready var weapon_pickup_window: WeaponPickupWindow = $UI/WeaponPickupWindow
# A standalone scene (weapon_pickup_window.tscn/.gd), not nodes living
# directly in this one - see its own header for why. This screen only
# ever calls its public open_reward() and listens for its `resolved`
# signal; it never reaches into the window's own child nodes.

var loot: Array[LootEntry] = []

# True when this screen was opened from a field chest (RoomState.
# pending_chest_gold was set - see _ready() below) rather than a real
# battle victory. A local copy, not read fresh from RoomState each time
# it matters - pending_chest_gold itself gets cleared back to -1 the
# moment _ready() reads it, so nothing later in this screen's own
# lifetime (in particular _continue_to_next_battle(), which needs to
# know long after _ready() has finished) could still tell the two cases
# apart without remembering it here first.
var _is_chest_reward: bool = false

# True when this screen was opened from a non-battle, non-chest field
# source - today, only the Pay House (RoomState.pending_non_battle_reward
# was set - see pay_window.gd's own note on this field). Same "a local
# copy, read once in _ready() before RoomState's own one-shot field gets
# cleared" reasoning as _is_chest_reward above, kept as its own separate
# flag rather than folded into _is_chest_reward since the two conditions
# arrive from different pending_* fields and shouldn't be conflated just
# because they currently drive the same skip in _continue_to_next_battle().
var _skips_battle_advance: bool = false

# Which row the card-choice overlay is currently resolving, set right
# before showing it - so _on_card_chosen()/_on_skip_pressed() know which
# row (and therefore which entry) to mark claimed once the player
# finishes picking or skipping.
var _active_card_row: LootRow

# Same idea as _active_card_row above, for the rare-drop reveal overlay -
# see _open_rare_drop_reveal()/_on_rare_take_pressed()/_on_rare_leave_pressed().
var _active_rare_row: LootRow

# Same idea again, for the weapon pickup window - which LootEntry it's
# currently resolving - set by _open_weapon_reward(), read by _on_weapon_
# pickup_resolved().
var _active_weapon_entry: LootEntry

# Which row this weapon came from, or null if it didn't come from one -
# set alongside _active_weapon_entry by _open_weapon_reward(). This is
# the explicit context _on_weapon_pickup_resolved() needs to know what
# "Leave it" should mean this time (return to a still-reclaimable chest
# row, vs. a Pay-House/dev-grant weapon that has no row to return to at
# all) - passed in directly rather than inferred by re-checking RoomState
# or _is_chest_reward, since a future non-chest source could in principle
# also want the row-based flow without this needing to change.
var _active_weapon_row: LootRow

func _ready() -> void:
	# The card-choice overlay pauses the SceneTree while open (see _open_
	# card_choice()) the same way DeckViewer already does - without this,
	# pausing would ALSO freeze this overlay's own buttons/cards, since
	# they're plain children of this scene's root and inherit its default
	# process mode otherwise. See DeckViewer's own identical _ready() note.
	# weapon_pickup_window is a standalone scene and handles its own
	# process_mode/pause internally (see its own _ready()/open_reward()) -
	# nothing to set here for it.
	card_choice_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# deck_button itself needs the same treatment - it's meant to stay
	# interactable even while card_choice_overlay has the tree paused
	# (see its own pressed connection below), which requires deck_button
	# to keep processing input through that pause same as the overlay
	# it's opened from. Not sufficient by itself, though: card_choice_
	# overlay spans the full screen and sits on top of deck_button in
	# draw/input order (it's a LATER sibling of UI, the same reason its
	# own dim visibly covers everything behind it). BOTH it and its own
	# DimBackground child needed mouse_filter set to IGNORE in the .tscn
	# (Control's default, STOP, would otherwise swallow the click before
	# deck_button ever saw it) - fixing DimBackground alone was tried
	# first and wasn't enough: with no child of card_choice_overlay left
	# claiming the click at deck_button's position, Godot's hit-test falls
	# back to the CONTAINER node itself as the next candidate, which was
	# still STOP. Same reasoning card.tscn's own decorative panels already
	# needed IGNORE for, just one level higher than expected. ChoiceModal
	# Panel itself never overlaps deck_button's own bottom-left corner, so
	# it needs no such change.
	#
	# The SAME default-STOP problem turned out to already exist in loot_
	# panel (the screen's own PRIMARY state, shown before any card-choice
	# row is even clicked) - also full-screen, also a later sibling of
	# deck_button, also left at Control's default mouse_filter. Fixed the
	# same way (IGNORE, in the .tscn) since a Deck button that only works
	# from the card-choice overlay and not the screen's normal state
	# would fail "should be interactable" just as surely as not working
	# in the overlay at all. rare_drop_overlay/leave_confirm_panel share
	# the same full-screen-Control-with-default-filter shape and were NOT
	# touched - unverified whether they have the same issue, flagged for
	# whoever next needs deck_button reachable from one of those instead
	# of fixed speculatively here.
	deck_button.process_mode = Node.PROCESS_MODE_ALWAYS

	continue_button.pressed.connect(_on_continue_pressed)
	skip_button.pressed.connect(_on_skip_pressed)
	rare_take_button.pressed.connect(_on_rare_take_pressed)
	rare_leave_button.pressed.connect(_on_rare_leave_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	cancel_button.pressed.connect(_on_cancel_pressed)
	weapon_pickup_window.resolved.connect(_on_weapon_pickup_resolved)
	# Not a direct deck_viewer.open_deck reference (unlike field_room.gd's
	# own identical button) - this button can be pressed both from the
	# plain loot-panel state (tree not yet paused - DeckViewer should
	# pause it, and unpause on close, same as anywhere else) AND from the
	# card-choice modal above (tree ALREADY paused by THAT overlay -
	# DeckViewer must NOT unpause on close, or closing the deck would
	# incorrectly wake the card-choice modal's own paused cards back up).
	# manage_pause = "am I the one pausing this," decided fresh at each
	# click from whichever state is actually true right now.
	deck_button.pressed.connect(func(): deck_viewer.open_deck(not get_tree().paused))

	# A field chest hands off its rolled amount here instead of applying it
	# directly (see field_chest.gd's own note) - a single gold-only row,
	# never a card choice or rare drop (see DESIGN.md's Rewards note: what
	# chests actually contain is still an open question, pending the
	# equipment design - this only routes the PRESENTATION through the
	# same window, it doesn't change what a chest gives). Cleared back to
	# -1 immediately so a later ordinary battle reward screen never
	# mistakes a stale value for a pending chest. pending_weapon_grant is
	# the same idea for a weapon - set by either the title screen's dev-
	# grant buttons OR (2026-08-27) a TREASURE-room chest's own weapon
	# roll (see field_chest.gd's weapon_drop_chance/WeaponPool.pick_
	# weighted()) - _is_chest_reward (set below, before this is read) is
	# what lets the loop right after this tell those two apart now, for
	# the row-vs-auto-open split (see this screen's own header note).
	# Both external sources can in principle be pending at once (a chest
	# sets BOTH pending_chest_gold and pending_weapon_grant together, on
	# the same trip), so this builds a combined list rather than treating
	# them as mutually exclusive - only falling back to a normal rolled
	# reward when NEITHER is pending.
	var external_loot: Array[LootEntry] = []
	if RoomState.pending_chest_gold >= 0:
		_is_chest_reward = true
		external_loot.append(LootEntry.create_gold(RoomState.pending_chest_gold))
		RoomState.pending_chest_gold = -1
	if RoomState.pending_weapon_grant != null:
		external_loot.append(LootEntry.create_weapon_drop(RoomState.pending_weapon_grant))
		RoomState.pending_weapon_grant = null
	if RoomState.pending_non_battle_reward:
		_skips_battle_advance = true
		RoomState.pending_non_battle_reward = false
	loot = external_loot if not external_loot.is_empty() else _generate_loot()
	if _is_chest_reward:
		# "Continue" reads oddly for a chest - it was never about advancing
		# to a next battle here (see _continue_to_next_battle()'s own
		# _is_chest_reward branch, unchanged by this rework), just closing
		# the window and resuming the field room. Making the button's own
		# label say that plainly is the "explicit button to leave/close
		# the chest" this rework asked for - the button's BEHAVIOR already
		# did this before today, only its wording didn't match.
		continue_button.text = "Leave"
	_display_loot()
	_update_row_scroll_height()
	_update_deck_button()

	# A weapon from a chest is NOT auto-opened any more (2026-08-25
	# rework, see this screen's own header note) - it becomes a row like
	# everything else instead (see _display_loot()'s own WEAPON handling),
	# opened only once the player clicks it. Every OTHER weapon source
	# (the Pay House, a title-screen dev-grant) keeps the ORIGINAL
	# behavior unchanged: still the first thing this screen shows, forcing
	# the Equip/Leave Behind decision before loot_panel is ever reachable
	# at all - those sources never produce more than gold-less, card-less
	# loot alongside a weapon (see _has_other_loot()'s own note), so there
	# was never a real "loot list" for them to fit into anyway.
	# _generate_loot() never produces a WEAPON entry itself (see its own
	# header) and pending_weapon_grant is a single field, not a list, so
	# there's at most one to find here - `break` after it rather than
	# looping needlessly.
	for entry in loot:
		if entry.loot_type == LootEntry.LootType.WEAPON and not _is_chest_reward:
			_open_weapon_reward(entry, null)
			break

# Rolls this battle's rewards into a list of LootEntry objects - the only
# place reward generation happens. Gold is guaranteed; the card-choice
# row and the rare-drop row are each their own independent roll, so a
# battle's loot window can end up gold-only, gold-plus-choice,
# gold-plus-rare-drop, or all three (see DESIGN.md's Rewards note: cards
# are drops, not currency, so "no card row" has to be a normal outcome,
# not a special/failure case). Everything is rolled once, up front, and
# just sits here (displayed but not yet applied to RunState) until its
# row is claimed.
func _generate_loot() -> Array[LootEntry]:
	var is_elite := RoomState.current_room_type == RoomType.Kind.ELITE
	# The run's dedicated opening room (see DESIGN.md's Run Structure &
	# Navigation: opening room / run_state.gd's opening_node) guarantees
	# its card-choice row instead of rolling card_reward_chance - its
	# TYPE is ordinary COMBAT (indistinguishable from any other combat
	# room by room_type alone), so this checks node identity instead,
	# same shape as is_elite above just keyed differently. current_node
	# hasn't advanced yet at this point - a room's own graph node only
	# changes when a field exit is walked through (see field_exit.gd),
	# which hasn't happened between "won this battle" and "this loot got
	# rolled."
	var is_opening_room := RunState.current_node == RunState.opening_node
	var gold_amount := randi_range(MIN_GOLD_REWARD, MAX_GOLD_REWARD)
	if is_elite:
		gold_amount = roundi(gold_amount * elite_gold_multiplier)
	var pool := CardPool.load_class_pool()
	var entries: Array[LootEntry] = [LootEntry.create_gold(gold_amount)]

	if is_elite or is_opening_room or randf() < card_reward_chance:
		var card_choices := _roll_card_choices(pool)
		if not card_choices.is_empty():
			entries.append(LootEntry.create_card_reward(card_choices))

	var rare_card := _roll_rare_drop(pool, is_elite)
	if rare_card != null:
		entries.append(LootEntry.create_rare_card_drop(rare_card))

	_print_loot(entries)
	return entries

# Dev aid (see DESIGN.md's Run graph note for the same "print what got
# generated" instinct applied elsewhere): this loot window failing
# silently - rows not generating, or generating but not rendering - was
# exactly what this session's actual bug was, and the console is the
# only place either failure mode would have been visible before now.
func _print_loot(entries: Array[LootEntry]) -> void:
	print("Loot generated (%d entries):" % entries.size())
	for entry in entries:
		match entry.loot_type:
			LootEntry.LootType.GOLD:
				print("  Gold: %d" % entry.gold_amount)
			LootEntry.LootType.CARD_REWARD:
				var names: Array[String] = []
				for card in entry.card_choices:
					names.append(card.card_name)
				print("  Card choice: %s" % ", ".join(names))
			LootEntry.LootType.RARE_CARD_DROP:
				print("  Rare drop: %s" % entry.rare_drop_card.card_name)

func _display_loot() -> void:
	for entry in loot:
		# A non-chest weapon reward never becomes a row - it was already
		# auto-opened above, in _ready(), before this ever runs (see this
		# screen's own header note). A CHEST-sourced weapon falls through
		# to the same row-building code every other loot type already
		# uses below - LootRow already knows how to display a WEAPON
		# entry (see loot_row.gd's own _describe()/set_entry()), and
		# _claim_entry()'s WEAPON case is what opens weapon_pickup_window
		# once its row is actually clicked.
		if entry.loot_type == LootEntry.LootType.WEAPON and not _is_chest_reward:
			continue
		var row: LootRow = LOOT_ROW_SCENE.instantiate()
		loot_row_container.add_child(row)
		row.set_entry(entry)
		# The lambda "remembers" row from this exact call, the same
		# trick battle.gd uses for hand cards - so when THIS row's click
		# comes back, we already know which row (not just which entry)
		# to update, without searching for it.
		row.row_clicked.connect(func(clicked_entry): _claim_entry(clicked_entry, row))

# RowScrollContainer has no height of its own by default (custom_minimum_
# size defaults to 0) - without this, the VBoxContainer it sits in
# collapses it to ~0px tall, and clip_contents = true then clips every
# row inside to invisible (the bug this fixes: rows generated and added
# correctly, just rendered in a zero-height clipped area). Sized to fit
# the actual ROW count (loot_row_container's real child count, not
# loot.size() - a non-chest WEAPON entry is in `loot` but never becomes a
# row, see _display_loot(); a claimed chest weapon's row is removed
# entirely, see _on_weapon_pickup_resolved()), capped at max_visible_rows
# so a hypothetical future
# reward type that pushes the count higher scrolls instead of growing
# the panel (and therefore Continue's position) unboundedly.
func _update_row_scroll_height() -> void:
	var visible_rows := mini(loot_row_container.get_child_count(), max_visible_rows)
	if visible_rows <= 0:
		row_scroll_container.custom_minimum_size.y = 0
		return
	var separation: int = loot_row_container.get_theme_constant("separation")
	row_scroll_container.custom_minimum_size.y = visible_rows * ROW_HEIGHT + (visible_rows - 1) * separation

# The one dispatch point for "what does claiming this kind of loot
# actually do." Everything upstream (LootRow, the click itself) is
# identical no matter the type; only this function knows the difference.
func _claim_entry(entry: LootEntry, row: LootRow) -> void:
	match entry.loot_type:
		LootEntry.LootType.GOLD:
			_claim_gold(entry, row)
		LootEntry.LootType.CARD_REWARD:
			_open_card_choice(row)
		LootEntry.LootType.RARE_CARD_DROP:
			_open_rare_drop_reveal(row)
		LootEntry.LootType.WEAPON:
			# Only reachable for a CHEST-sourced weapon - see _display_
			# loot()'s own skip for every other source, which never
			# builds a row for this case to be dispatched from at all.
			_open_weapon_reward(entry, row)

# --- Modal overlay pattern (the rare-drop reveal's full takeover) ---
#
# A real full-screen state, not a see-through overlay sitting on top of
# the loot window: loot_panel goes fully invisible (not just covered) the
# instant this opens, so nothing of it - title, gold total, other reward
# rows - can bleed through the gaps around the reveal's card/buttons, and
# it can't eat a stray click either. RareDropOverlay has no background of
# its own - the reward screen's shared UI/Background (always present,
# behind everything) is what shows through once loot_panel is gone.
# Reopening the loot window is always a fade (_return_to_loot_panel()),
# never a cut, but LEAVING it is instant - matching the DESIGN.md
# optional-UI convention that showing something new gets a moment, hiding
# it doesn't need one.
#
# This is deliberately NOT what the card-choice screen below uses - a
# card choice is a comparison/decision, not a special moment, so it gets
# the lighter "dimmed, blocked backdrop behind a centered modal" treatment
# instead (see _open_card_choice()), reusing DeckViewer's own pause-based
# blocking rather than this full-takeover-plus-crossfade shape. Two
# different overlay patterns in this same file, on purpose - matched to
# what each moment actually is, not forced into one mold for consistency's
# own sake.

const MODAL_RESOLVE_FADE_DURATION := 0.4

func _open_modal_overlay(overlay: Control) -> void:
	loot_panel.visible = false
	overlay.modulate.a = 1.0
	overlay.visible = true

# loot_panel is unhidden (and faded up from 0) the instant this starts,
# in parallel with the overlay fading out, rather than waiting for the
# overlay to fully disappear first - a wait would leave a beat of nothing
# but bare Background between them. The overlay stays visible=true (still
# fully blocking input) for the whole fade, only actually hidden once
# both tweens land, so a stray click during the crossfade can't reach the
# reappearing loot window early.
func _return_to_loot_panel(overlay: Control) -> void:
	loot_panel.visible = true
	loot_panel.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(overlay, "modulate:a", 0.0, MODAL_RESOLVE_FADE_DURATION)
	tween.tween_property(loot_panel, "modulate:a", 1.0, MODAL_RESOLVE_FADE_DURATION)
	await tween.finished
	overlay.visible = false

# --- Rare drop reveal ---
#
# A gift, but not an instant one anymore: clicking the row opens a reveal
# (the card itself, at the same larger reward-card scale as the regular
# choice, with a short scale/fade-in beat) before the player commits to
# Take or Leave. entry.claimed stays false until one of those is pressed,
# so _has_unclaimed_loot()'s Continue-confirmation check needs no changes
# to cover this row - it already treats "not yet decided" as unclaimed,
# exactly like every other loot type.

const RARE_REVEAL_DURATION := 0.4
const RARE_REVEAL_START_SCALE := 0.6

func _open_rare_drop_reveal(row: LootRow) -> void:
	_active_rare_row = row
	for child in rare_card_container.get_children():
		child.queue_free()

	_open_modal_overlay(rare_drop_overlay)

	var card_instance: Card = CARD_SCENE.instantiate()
	rare_card_container.add_child(card_instance)
	card_instance.set_scale_factor(RARE_DROP_CARD_SCALE)
	card_instance.set_card_data(row.entry.rare_drop_card)
	card_instance.set_affordable(true) # Not being played for energy here - always full brightness.
	# Static display, not an interactive card: Card's hover pop/lift exists
	# to disambiguate an overlapping stack (hand cards) - there's exactly
	# one card here, nothing to disambiguate, and it would be a distracting
	# reaction to a hover that does nothing. IGNORE stops mouse_entered/
	# exited (and _gui_input) from ever reaching this instance at all, so
	# hovering AND clicking the card both go through it to Take/Leave, the
	# only interactive elements this screen has - same "purely a display"
	# treatment shop_window.gd's own read-only card preview already uses.
	card_instance.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Centers the reveal's scale-in on the card's middle instead of its
	# top-left corner (Control's default pivot) - custom_minimum_size is
	# already set by set_scale_factor() above, so this is the card's real
	# on-screen size at reward scale.
	card_instance.pivot_offset = card_instance.custom_minimum_size / 2.0
	card_instance.modulate.a = 0.0
	card_instance.scale = Vector2(RARE_REVEAL_START_SCALE, RARE_REVEAL_START_SCALE)

	# modulate, not visible - TakeLeaveContainer stays visible=true (and
	# so keeps reserving its layout space in MainColumn) the whole time;
	# hiding it via visible instead would shrink MainColumn by its height
	# while it's out, then snap the heading+card up when it reappears.
	# disabled guards against a click landing during the fade itself,
	# same double-guard shape as battle.gd's Continue button.
	rare_take_leave_container.modulate.a = 0.0
	rare_take_button.disabled = true
	rare_leave_button.disabled = true
	AudioManager.play_sfx("rare_drop")

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(card_instance, "modulate:a", 1.0, RARE_REVEAL_DURATION)
	tween.tween_property(card_instance, "scale", Vector2.ONE, RARE_REVEAL_DURATION).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_property(rare_take_leave_container, "modulate:a", 1.0, RARE_REVEAL_DURATION)
	tween.chain().tween_callback(func():
		rare_take_button.disabled = false
		rare_leave_button.disabled = false
	)

func _on_rare_take_pressed() -> void:
	RunState.add_card_to_deck(_active_rare_row.entry.rare_drop_card)
	# The grant itself - separate from "rare_drop" above, which already
	# played at the REVEAL a moment earlier (before Take/Leave was even
	# decided) and marks the reveal moment, not the acquisition one.
	AudioManager.play_sfx("add_card")
	_update_deck_button()
	_finish_rare_drop_reveal(false)

# Leaving still resolves the row (see loot_entry.gd's `declined` field) -
# it's a real decision, not a way to keep the row open for later. The
# card itself is simply never added to the deck.
func _on_rare_leave_pressed() -> void:
	_finish_rare_drop_reveal(true)

func _finish_rare_drop_reveal(declined: bool) -> void:
	rare_take_button.disabled = true
	rare_leave_button.disabled = true
	var card_name: String = _active_rare_row.entry.rare_drop_card.card_name
	RunLogger.log_reward_offered("Rare drop", [card_name], "" if declined else card_name)
	_active_rare_row.entry.claimed = true
	_active_rare_row.entry.declined = declined
	_active_rare_row.refresh_claimed_state()
	_active_rare_row = null
	await _return_to_loot_panel(rare_drop_overlay)

# --- Weapon pickup window ---
#
# Equipment is a decision, not a receipt (2026-08-24 rework) - a weapon
# reward always opens weapon_pickup_window (a standalone scene - see its
# own header for why this isn't inline here), empty slot or not, rather
# than the old silent "auto-equip if nothing's equipped, otherwise ask"
# shortcut. loot_panel itself stays hidden the whole time this is up
# (see below), so Continue simply isn't reachable until the weapon
# decision is made. Everything about how the window ITSELF looks/
# behaves (layout, colors, the equipped-weapon comparison, fonts) lives
# entirely in weapon_pickup_window.gd/.tscn now - this screen only ever
# calls open_reward() and reacts to the resolved signal.
#
# Pausing this early (right in _ready(), before the scene has even
# finished its own incoming fade-in) once caused a real, ugly bug: see
# scene_transition.gd's own fix note - SceneTransition.go_to()'s fade-in
# tween could freeze mid-flight if the tree paused before it finished,
# leaving its full-screen fade_rect stuck at mouse_filter = STOP
# forever, eating every hover/click in the game with no way left to
# unpause and release it. Fixed AT THE SOURCE (SceneTransition is now
# immune to pause, unconditionally), not here - this function doesn't
# need to know or work around that anymore.
func _open_weapon_reward(entry: LootEntry, row: LootRow) -> void:
	_active_weapon_entry = entry
	_active_weapon_row = row
	loot_panel.visible = false
	weapon_pickup_window.open_reward(entry.weapon_data, RunState.equipped_weapon)

func _on_weapon_pickup_resolved(equipped: bool) -> void:
	if equipped:
		RunState.equipped_weapon = _active_weapon_entry.weapon_data
		AudioManager.play_sfx("weapon_equipped")
	var weapon_name: String = _active_weapon_entry.weapon_data.weapon_name
	RunLogger.log_reward_offered("Weapon", [weapon_name], weapon_name if equipped else "")
	_active_weapon_entry.declined = not equipped

	# Opened from a chest's own loot row (_active_weapon_row is the
	# explicit context set by _open_weapon_reward(), not something
	# inferred here) - unlike every other loot type, Leaving this one does
	# NOT claim the row: it's left exactly as unclaimed and clickable as
	# before, so the same weapon can be reconsidered again before the
	# chest is closed (see LootRow._gui_input()'s own unclaimed guard -
	# an unclaimed row is what stays reachable). Taking it DOES claim the
	# row, but the row itself is removed entirely rather than left behind
	# greyed out with a checkmark - there's nothing left to compare once
	# the weapon's equipped, so a lingering "receipt" row would just be
	# clutter no other loot type actually needs. Either way, this returns
	# to the loot window, never closes the chest outright - Leaving the
	# chest itself is still a separate, explicit Continue/Leave click.
	if _active_weapon_row != null:
		if equipped:
			_active_weapon_entry.claimed = true
			loot_row_container.remove_child(_active_weapon_row)
			_active_weapon_row.queue_free()
			_update_row_scroll_height()
		_active_weapon_entry = null
		_active_weapon_row = null
		loot_panel.visible = true
		return

	# No row - this weapon was auto-opened directly in _ready() (the Pay
	# House, a title-screen dev-grant), so the window IS the only
	# interaction point and the decision is final either way, exactly as
	# it was before chest weapons became rows.
	_active_weapon_entry.claimed = true
	_active_weapon_entry = null

	# A weapon-only reward (today: only the Pay House - see pay_window.gd's
	# own pending_non_battle_reward note) has nothing left for loot_panel to
	# show once Take It/Leave It resolves - this only ever fires for a
	# weapon with no other loot. Without this, loot_panel would still
	# appear with nothing but the static gold total and a Continue button -
	# a second, pointless reward screen right after the one the player just
	# resolved. Skip straight to where Continue would have taken them
	# instead of unhiding a panel with nothing to do.
	if not _has_other_loot():
		_continue_to_next_battle()
		return

	loot_panel.visible = true

func _has_other_loot() -> bool:
	for entry in loot:
		if entry.loot_type != LootEntry.LootType.WEAPON:
			return true
	return false

func _claim_gold(entry: LootEntry, row: LootRow) -> void:
	RunState.add_gold(entry.gold_amount)
	RunLogger.log_gold_gained(entry.gold_amount, "field chest" if _is_chest_reward else "battle reward")
	entry.claimed = true
	row.refresh_claimed_state()
	AudioManager.play_sfx("gold_claimed")

# --- Card choice ("Choose a Card") ---
#
# A comparison/decision, not a special moment (contrast with the rare-
# drop reveal above) - presented as a large centered modal (ChoiceModal
# Panel, styled like LeaveConfirmPanel's own ConfirmBox further down)
# over a dimmed backdrop (DimBackground, same 0.6-alpha tone as Leave
# ConfirmPanel's own dim) rather than a full opaque takeover. loot_panel
# stays visible=true and untouched underneath the whole time - it's meant
# to still read as "you're choosing from within the loot screen," just
# completely inert while this is up.
#
# Blocking reuses DeckViewer's own mechanism (see its class-level
# comment) rather than the rare-drop reveal's: pausing the whole
# SceneTree, since a Control's mouse filter alone doesn't stop keyboard/
# other input from reaching whatever's underneath, the same reasoning
# DeckViewer already documents. card_choice_overlay is set PROCESS_MODE_
# ALWAYS in _ready() so ITS OWN buttons/cards keep working while paused.
# No fade either direction - matching DeckViewer's own instant open/
# close, not the rare-drop reveal's crossfade.
func _open_card_choice(row: LootRow) -> void:
	_active_card_row = row
	for child in card_reward_container.get_children():
		child.queue_free()
	for data in row.entry.card_choices:
		_add_card_choice(data)
	card_choice_overlay.visible = true
	get_tree().paused = true

# Reuses the exact Card scene hand cards use, hover animation included,
# since a reward card and a hand card are the same kind of thing to
# look at.
func _add_card_choice(data: CardData) -> void:
	var card_instance: Card = CARD_SCENE.instantiate()
	card_reward_container.add_child(card_instance)
	card_instance.set_scale_factor(REWARD_CARD_SCALE)
	card_instance.set_card_data(data)
	card_instance.set_affordable(true) # Not being played for energy here - always full brightness.
	card_instance.card_clicked.connect(func(clicked_data): _on_card_chosen(clicked_data))

func _on_card_chosen(data: CardData) -> void:
	AudioManager.play_sfx("select_card")
	_log_card_choice(data.card_name)
	RunState.add_card_to_deck(data)
	# The grant landing, not the click - select_card above is the picking
	# gesture (fires even if a caller somehow rejected the pick), this is
	# "a card is now in the deck," the same cue the Keeper/cache-chest
	# grants play at their own equivalent moment.
	AudioManager.play_sfx("add_card")
	_update_deck_button()
	_finish_card_choice()

func _update_deck_button() -> void:
	deck_button.text = "Deck (%d)" % RunState.deck.size()

# Skipping is a legitimate choice (a leaner deck draws its good cards
# more often), not a failure state - it still claims the row (there's
# nothing left to come back for), it just adds nothing to the deck.
func _on_skip_pressed() -> void:
	_log_card_choice("")
	_finish_card_choice()

func _log_card_choice(taken_name: String) -> void:
	var offered: Array[String] = []
	for card in _active_card_row.entry.card_choices:
		offered.append(card.card_name)
	RunLogger.log_reward_offered("Card choice", offered, taken_name)

func _finish_card_choice() -> void:
	_active_card_row.entry.claimed = true
	_active_card_row.refresh_claimed_state()
	_active_card_row = null
	card_choice_overlay.visible = false
	get_tree().paused = false

func _on_continue_pressed() -> void:
	# No confirmation for a chest, even with something unclaimed still
	# sitting in the list (2026-08-25 DECIDED - see DESIGN.md's Rewards
	# note) - leaving a chest is a much lower-stakes moment than leaving a
	# real battle-victory reward screen, and now that a weapon can sit as
	# a reclaimable row instead of forcing an immediate decision, requiring
	# a confirm on top would be asking the player to confirm twice for the
	# one thing (a weapon) that's actually worth pausing over. Flagged as
	# a real open question, not a settled one: if a weapon drop turns out
	# to be significant enough that silently losing one reads as a bug
	# rather than a choice, this is the one branch to revisit.
	if _has_unclaimed_loot() and not _is_chest_reward:
		leave_confirm_panel.visible = true
	else:
		_continue_to_next_battle()

func _has_unclaimed_loot() -> bool:
	for entry in loot:
		if not entry.claimed:
			return true
	return false

func _on_leave_pressed() -> void:
	leave_confirm_panel.visible = false
	_continue_to_next_battle()

func _on_cancel_pressed() -> void:
	leave_confirm_panel.visible = false

func _continue_to_next_battle() -> void:
	# A chest never fought a battle - just close the window and resume the
	# SAME field room, no battle_number advance and no risk of routing to
	# battle.tscn (a chest can't have come from the "Dev: Battle Chain"
	# shortcut, which never touches the field at all - see title_screen.
	# gd). field_chest.gd already set RoomState.chest_opened/chest_root's
	# own opened look before this screen ever opened, so the room reads
	# correctly the instant it reloads - see field_chest.gd's _ready().
	#
	# _skips_battle_advance covers the same "no battle was fought" case
	# for a non-chest field source (today: the Pay House - see pay_window.
	# gd's own note on pending_non_battle_reward) that also can't have
	# come from the dev battle-chain shortcut, for the same reason.
	if _is_chest_reward or _skips_battle_advance:
		SceneTransition.go_to("res://field_room.tscn")
		return
	RunState.advance_to_next_battle()
	# Field encounters (see field_blob.gd) ARE the run's battles now, so
	# this is the common case: RoomState.in_field_encounter is set right
	# before a blob starts a fight, and Victory returns here to the field
	# room instead of chaining into another battle directly. It's false
	# only when this fight came from the title screen's "Dev: Battle
	# Chain" shortcut (see title_screen.gd), which still chains battles
	# directly for quick battle-only iteration.
	if RoomState.in_field_encounter:
		SceneTransition.go_to("res://field_room.tscn")
	else:
		SceneTransition.go_to("res://battle.tscn")

# --- Card reward generation ---

# COMMON/RARE only (see DESIGN.md's Rewards note) - filtered from the
# full pool here rather than at the folder-scan level, since the same
# folder also supplies _roll_rare_drop()'s ULTRA_RARE pool below.
func _roll_card_choices(pool: Array[CardData]) -> Array[CardData]:
	var remaining: Array[CardData] = pool.filter(func(c): return c.rarity <= CardData.Rarity.RARE)
	var choices: Array[CardData] = []
	for i in CARD_CHOICE_COUNT:
		if remaining.is_empty():
			break
		var chosen := _pick_card_by_rarity(remaining)
		remaining.erase(chosen)
		choices.append(chosen)
	return choices

# Delegates to CardPool.pick_weighted_card() (2026-08-29, three-chest
# treasure room) - REPLACES this screen's own private _roll_rarity()/
# rarity-stepdown logic, extracted there so a second call site (field_
# chest.gd's Chest B) can draw one card "the same pool, the same
# weighting" without a separately-tuned copy. Passing this screen's own
# common_weight/rare_weight exports through keeps the roll's actual
# distribution byte-for-byte identical to before this extraction - only
# WHERE the computation happens moved, not what it computes.
func _pick_card_by_rarity(pool: Array[CardData]) -> CardData:
	return CardPool.pick_weighted_card(pool, common_weight, rare_weight)

# The rare-drop roll is independent of everything above: its own flat
# chance (rare_drop_chance, or elite_rare_drop_chance for an elite
# victory - see the "Elite rewards" note above), and its own tier
# (ULTRA_RARE only - see DESIGN.md's Rewards note on cards as drops).
# Returns null (no drop this battle) far more often than not by design,
# and also if nothing in the pool is currently ULTRA_RARE - an empty
# tier is a content gap, not a bug, same stance _pick_card_by_rarity
# already takes toward SECRET_RARE.
func _roll_rare_drop(pool: Array[CardData], is_elite: bool) -> CardData:
	var ultra_rares: Array[CardData] = pool.filter(func(c): return c.rarity == CardData.Rarity.ULTRA_RARE)
	if ultra_rares.is_empty():
		return null
	var chance := elite_rare_drop_chance if is_elite else rare_drop_chance
	if randf() >= chance:
		return null
	return ultra_rares.pick_random()

# Reward pools are per-class now (Slay the Spire-style: Wanderer only ever
# sees Wanderer cards) - CardPool.load_class_pool() scans RunState.current_
# class.card_pool_folder (see character_data.gd and card_pool.gd), shared
# with RoomState's shop stock roll so both agree on what "this class's
# pool" means. A class with a thin or empty pool (Samurai, at the time of
# writing - its folder has nothing in it yet) is expected, not a bug - it
# just offers whatever's actually in its folder.
