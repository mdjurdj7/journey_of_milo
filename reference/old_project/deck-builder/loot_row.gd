extends Panel
class_name LootRow
# Displays one LootEntry as a clickable row - reusing the exact "just
# report the click, let something else decide what it means" pattern
# Card already established (see card.gd's card_clicked). This row
# doesn't know what claiming an entry actually DOES - award gold? open a
# card choice? something else once equipment exists? - it just displays
# whatever the entry says and reports "I was clicked" when it's clicked
# and not already claimed. reward_screen.gd owns the actual claiming
# logic.

signal row_clicked(entry: LootEntry)

var entry: LootEntry

const CLAIMED_MODULATE := Color(0.5, 0.5, 0.5, 1)
const UNCLAIMED_MODULATE := Color(1, 1, 1, 1)

# Modulate values above 1 aren't clamped - Godot just overbrightens, which
# reads as a highlight/glow rather than a color shift. Cheap and layout-
# safe: unlike Card's hover (which rises/scales a separate Visual child -
# see card.gd), LootRow's root IS what LootRowContainer's VBoxContainer
# positions, so animating this row's own position/scale directly would
# fight the container's layout each frame. modulate isn't a layout
# property, so it has no such conflict.
const HOVER_MODULATE := Color(1.25, 1.25, 1.25, 1)
const HOVER_DURATION := 0.1

const TAKEN_MARK_COLOR := Color(0.4, 0.9, 0.5, 1)
const DECLINED_MARK_COLOR := Color(0.75, 0.75, 0.8, 1)

# Placeholder icon colors per loot type - just enough to tell rows apart
# by a glance at their left edge until there's real art.
const ICON_COLORS := {
	LootEntry.LootType.GOLD: Color(0.9, 0.75, 0.2, 1),
	LootEntry.LootType.CARD_REWARD: Color(0.5, 0.6, 0.9, 1),
	LootEntry.LootType.RARE_CARD_DROP: Color(0.85, 0.65, 0.15, 1),
	LootEntry.LootType.WEAPON: Color(0.6, 0.62, 0.68, 1),
}

# The world-voice serif card.gd's own name_font already uses for
# character-facing text (card names, weapon_pickup_window.gd's own weapon
# name) - a weapon row's name gets the SAME treatment, so it reads as the
# same kind of thing wherever it appears, not a system-voice label like
# every other row's plain "+18 Gold"/"Card Reward" text. Only WEAPON rows
# get this override (see set_entry() below) - every other loot type stays
# on this scene's default sans.
const WEAPON_NAME_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")

# Same gold as card.gd's RARITY_BORDER_COLORS[ULTRA_RARE] - one rarity,
# one color, no matter where it shows up. A rare drop row gets a thicker
# border in this color plus a warmer background, instead of the neutral
# frame every other row uses - "visually elevated," not just re-tinted.
const RARE_DROP_BORDER_COLOR := Color(0.85, 0.65, 0.15, 1)
const RARE_DROP_BG_COLOR := Color(0.22, 0.17, 0.08, 1)
const RARE_DROP_BORDER_WIDTH := 6

@onready var icon_rect: ColorRect = $IconRect
@onready var label: Label = $Label
@onready var type_indicator_label: Label = $TypeIndicatorLabel
# Empty for every row today (see set_entry() - nothing ever writes to
# this) - a reserved, currently-unused slot beside the name for a future
# system-voice type indicator (a small icon, or a short muted word like
# "Weapon"/"Trinket"), so a heterogeneous chest could tell an equipment
# row's SUBTYPE apart without fusing it into the name string itself. Not
# the same thing as icon_rect above, which already exists and already
# distinguishes loot TYPES (gold vs. card vs. weapon) by color - this is
# for a finer distinction WITHIN the equipment category specifically.
@onready var checkmark_label: Label = $CheckmarkLabel

# Same "kill and restart, don't stack" pattern as Card's _hover_tween
# (see card.gd) - stops whatever hover animation is already running so
# quickly wiggling the mouse in and out doesn't queue competing tweens.
var _hover_tween: Tween

# True from a genuine LEFT-button press on this row until either its
# matching release (a real click - see _gui_input()) or the mouse leaving
# before release (a drag-off, cancelled - see _on_mouse_exited()). Same
# guard as card.gd's _press_started_on_card, for the same reason: without
# it, a mouse-wheel scroll tick over this row (also an InputEventMouse
# Button, pressed briefly true) would claim it - scrolling the loot list
# could auto-collect gold or pop open a rare-drop reveal nobody clicked.
var _press_started_on_row: bool = false

func _ready() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

# Only unclaimed rows hint at being clickable - a claimed/declined row
# genuinely isn't (see _gui_input()'s own guard below), so it shouldn't
# invite a click that would do nothing.
func _on_mouse_entered() -> void:
	if entry != null and not entry.claimed:
		_play_hover_tween(HOVER_MODULATE)

func _on_mouse_exited() -> void:
	_press_started_on_row = false # A drag-off cancels the pending click - press and release must both land on this row.
	if entry != null and not entry.claimed:
		_play_hover_tween(UNCLAIMED_MODULATE)

func _play_hover_tween(target_modulate: Color) -> void:
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "modulate", target_modulate, HOVER_DURATION)

# The public entry point for giving this row something to display,
# same pattern as Card.set_card_data()/Enemy.set_enemy_data().
func set_entry(new_entry: LootEntry) -> void:
	entry = new_entry
	icon_rect.color = ICON_COLORS.get(entry.loot_type, Color.WHITE)
	label.text = _describe(entry)
	# WEAPON only (see WEAPON_NAME_FONT's own doc) - every row is built
	# fresh for exactly one entry and never reused for a different one
	# (see reward_screen.gd's _display_loot()), so there's no case where
	# this needs to un-set itself later; the explicit removal for every
	# OTHER type still exists so this can't ever be misread as "the font
	# override happens to be a leftover," even though nothing today would
	# actually trigger that.
	if entry.loot_type == LootEntry.LootType.WEAPON:
		label.add_theme_font_override("font", WEAPON_NAME_FONT)
	else:
		label.remove_theme_font_override("font")
	_apply_rarity_style()
	refresh_claimed_state()

func _describe(e: LootEntry) -> String:
	match e.loot_type:
		LootEntry.LootType.GOLD:
			return "+%d Gold" % e.gold_amount
		LootEntry.LootType.CARD_REWARD:
			return "Card Reward"
		LootEntry.LootType.RARE_CARD_DROP:
			return _describe_rare_drop(e)
		LootEntry.LootType.WEAPON:
			# The name alone - no "Weapon:" prefix, no type fused in, no
			# stats/damage/effect text (see loot_entry.gd's own doc on
			# WEAPON - this row is a pointer to weapon_pickup_window's own
			# comparison screen, not a partial version of it).
			return e.weapon_data.weapon_name
		_:
			return "???"

# Suggestive, not descriptive, before the reveal (see DESIGN.md's Rewards
# note and reward_screen.gd's _open_rare_drop_reveal()) - naming the card
# here would spoil the one moment this row exists to build up to. Once
# resolved, the name is fair game either way (the player already saw it
# during the reveal overlay); which phrasing depends on Take vs Leave.
func _describe_rare_drop(e: LootEntry) -> String:
	if not e.claimed:
		return "Something Rare..."
	elif e.declined:
		return "Left Behind: %s" % e.rare_drop_card.card_name
	else:
		return "Taken: %s" % e.rare_drop_card.card_name

# Every LootRow starts out sharing the same StyleBoxFlat baked into
# loot_row.tscn (same "one shared resource per scene load, not per
# instance" situation card.gd's rarity border deals with) - duplicate()
# makes this instance's frame its own before recoloring it, so elevating
# one rare-drop row can't bleed into every other row on screen.
func _apply_rarity_style() -> void:
	if entry.loot_type != LootEntry.LootType.RARE_CARD_DROP:
		return
	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate()
	style.border_color = RARE_DROP_BORDER_COLOR
	style.bg_color = RARE_DROP_BG_COLOR
	style.border_width_left = RARE_DROP_BORDER_WIDTH
	style.border_width_top = RARE_DROP_BORDER_WIDTH
	style.border_width_right = RARE_DROP_BORDER_WIDTH
	style.border_width_bottom = RARE_DROP_BORDER_WIDTH
	add_theme_stylebox_override("panel", style)

# reward_screen.gd calls this right after actually resolving the entry,
# so the row's look updates without needing set_entry() called again.
# Also re-runs _describe() - RARE_CARD_DROP's text changes once resolved
# (see _describe_rare_drop()); every other loot type's text is static,
# so this is a no-op re-assignment for them.
func refresh_claimed_state() -> void:
	# A hover-in tween can still be running if the click that resolved
	# this row landed right after the mouse entered it - kill it so it
	# can't keep animating modulate toward HOVER_MODULATE after this
	# function has already set the real final color below.
	if _hover_tween:
		_hover_tween.kill()
	label.text = _describe(entry)
	checkmark_label.visible = entry.claimed
	if entry.claimed and entry.declined:
		checkmark_label.text = "✕"
		checkmark_label.add_theme_color_override("font_color", DECLINED_MARK_COLOR)
	else:
		checkmark_label.text = "✓"
		checkmark_label.add_theme_color_override("font_color", TAKEN_MARK_COLOR)
	modulate = CLAIMED_MODULATE if entry.claimed else UNCLAIMED_MODULATE

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_press_started_on_row = true
		return
	if _press_started_on_row:
		_press_started_on_row = false
		if entry != null and not entry.claimed:
			row_clicked.emit(entry)
