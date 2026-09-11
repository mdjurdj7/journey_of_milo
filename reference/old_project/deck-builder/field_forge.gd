extends Area2D
class_name FieldForge
# A workbench where upgrade shards get spent on a card upgrade (2026-09-02,
# forge pass - commit 3 of 3, see room_type.gd's own FORGE doc for the
# other two). Same Area2D "detection zone, not a solid body" idea as field_
# chest.gd/field_heap.gd - walking into it is what arms the prompt.
# Instanced by field_room.gd's _spawn_forge() when RoomState.room_layout
# happens to include one (see room_state.gd's _generate_forge_layout()).
#
# Contact/prompt machinery below (approach prompt, fade in/out, CanvasLayer
# draw-order fix) is DUPLICATED out of field_chest.gd's own version, not
# extracted into something shared - same explicit "two/three uses isn't
# enough to justify guessing at the right shared shape yet" stance field_
# chest.gd's own header already states for its own copy from field_heap.gd.
# If chest's version is ever retuned, this one needs its own separate
# retune, on purpose.
#
# PLACEHOLDER CONTENT, flagged explicitly per this pass's own brief (do not
# "fix" these without a real content pass):
#   - The visual (see _build_geometry() below) is a plain flat-color slab-
#     on-two-supports silhouette, not real forge art.
#   - prompt_text/closed_prompt_text below are placeholder world-voice
#     lines, not finalized copy.
#   - DISPLAY_NAMES["Forge"] (room_type.gd) is a placeholder label too.

@export var forge_id: String = ""
# Which entry of RoomState.forge_used this SPECIFIC forge instance is
# tracked under - mirrors field_chest.gd's own chest_id/RoomState.chest_
# opened exactly. Only one forge ever exists per room today (a FORGE room
# generates exactly one - see _generate_forge_layout()), so a flat bool
# would work just as well, but the Dictionary-keyed-by-id shape is what
# every other per-instance room-content flag here already uses (chest_
# opened, blob_defeated) - matching it costs nothing and means a future
# multi-forge room, if one's ever authored, needs no rework here.

@export var prompt_text: String = "A workbench, tools laid out and ready to use."
# PLACEHOLDER (see class doc above) - the world-voice line shown when the
# forge is actually usable (see _show_prompt()'s own gating). Single flat
# default, unlike field_chest.gd's three per-instance prompt strings -
# there's only ever one forge per room, no siblings that need a DIFFERENT
# line the way TREASURE's three chests do.

@export var closed_prompt_text: String = "Someone's tools, laid out in working order."
# PLACEHOLDER (see class doc above) - shown instead of prompt_text
# whenever the forge ISN'T usable right now, for any of three reasons (see
# _show_prompt()): no shards, no eligible card in the deck, or this forge
# was already used this visit. One shared line covers all three - the
# player doesn't need to be told WHICH reason, just that nothing's on
# offer here right now, same "one flat fact, not per-cause text" shape
# field_chest.gd's own closed_prompt_text already uses for its own
# foreclosed state.

signal upgraded

const CARD_SCENE := preload("res://card.tscn")
# Reused, not rebuilt - the same self-contained Control every other card
# reveal in this project instances (field_room.gd's chest/Keeper offer
# cards, reward_screen.gd's rare-drop reveal). See _play_upgrade_reveal()
# below for this forge's own use of it.
# Fired once, the instant this forge successfully spends a shard on an
# upgrade (see _on_take_pressed()) - field_room.gd doesn't listen to this
# today (nothing room-wide needs to react the way TREASURE's chest
# exclusivity does), but it's reported anyway, same "just report it, let
# something else decide what it means" shape every other commitment signal
# in this project's field interactables already follows (FieldChest.
# claimed, FieldExit.exit_entered).

# --- Placeholder silhouette (see class doc above) ---
#
# A flat slab on two supports - deliberately much simpler than field_
# chest.gd's own three-piece Body/Lid/Latch (no lid to hinge open, no
# latch): a forge doesn't visibly change shape when used, only its PROMPT
# does (see _show_prompt()). Centre-anchored around this Area2D's own
# origin, same convention field_chest.gd's ChestRoot uses (spans roughly
# -half_total..+half_total) - see shadow_y_offset below for why that
# convention needs no per-instance correction either.
@export var slab_width_px: float = 90.0
@export var slab_height_px: float = 12.0
@export var support_width_px: float = 14.0
@export var support_height_px: float = 44.0
@export var support_inset_px: float = 10.0
# How far each support sits in from the slab's own outer edge - purely a
# "does this read as a table" placement knob, not structural.

@export var forge_color: Color = Color(0.35, 0.3, 0.26, 1)
# A plain worked-wood/stone brown - no separate "used" recolor the way
# field_chest.gd's opened_color/open_flash_color give a chest, since a
# forge's used/unused state is communicated entirely through its PROMPT
# text (see _show_prompt()), not a silhouette change - nothing here reads
# `_used` at all.

# --- Approach prompt (DUPLICATED from field_chest.gd - see class doc) ---
@export_group("Approach Prompt")
@export var prompt_width_px: float = 420.0
@export var prompt_head_clearance_px: float = 400.0
# Same value as field_chest.gd's own (unchanged, not re-measured) - this
# clears the PLAYER's own rendered height above wherever they're
# standing, not anything about the forge's own (much smaller) geometry,
# so the number that was already measured against the player's sprite
# extent still applies unchanged here - see field_chest.gd's own doc for
# the full measurement this value is based on.
@export var prompt_font_size: int = 24
@export var prompt_button_font_size: int = 20
@export var prompt_fade_in_sec: float = 0.2
@export var prompt_fade_out_sec: float = 1.1

const PROMPT_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")

@export_group("Upgrade Reveal")
# The quiet, skippable "before -> after" beat shown once a card upgrade is
# confirmed (see _play_upgrade_reveal()) - card rises, the sound/value
# swap lands, a hold, then it dismisses. All five segments below are
# exported so the pacing can be retuned by ear without touching code, same
# reason every other hand-tuned timing export in this project (prompt_
# fade_in_sec above, treasure_card_fade_in_sec in field_room.gd, ...) is
# exported rather than a local constant.
@export var upgrade_reveal_scale: float = 1.6
# Matches reward_screen.gd's RARE_DROP_CARD_SCALE exactly - the project's
# existing "centered, enlarged, static reveal" size, not a new value
# invented for this feature.
@export var upgrade_reveal_start_scale: float = 0.85
@export var upgrade_reveal_pulse_scale: float = 1.08
# How far the change-beat's own scale pulse overshoots ONE.0 - deliberately
# small (per this feature's own "quiet register" brief: no glow burst, no
# camera shake, restrained easing) so the swap reads as a settle, not a pop.
@export var upgrade_reveal_rise_sec: float = 0.25
@export var upgrade_reveal_before_hold_sec: float = 0.3
# The BEFORE state's own hold, once risen - the brief's own "must be
# visible long enough to register before the change lands" requirement.
@export var upgrade_reveal_change_pulse_sec: float = 0.15
@export var upgrade_reveal_after_hold_sec: float = 2.5
# The AFTER state's hold - explicitly the "player's own reading time,"
# excluded from the ~1s target the other four segments sum to (0.25 +
# 0.3 + 0.15 + 0.25 = 0.95s), per this feature's own brief. RETUNED
# (2026-09-03) from 0.5s - too fast to actually read the card, per
# live feedback - to 2.5s.
@export var upgrade_reveal_dismiss_sec: float = 0.25

var _upgrade_reveal_active: bool = false
# True for the exact span _play_upgrade_reveal() is awaiting, below - the
# ONLY thing _unhandled_input() below gates a skip press on, so a click/key
# anywhere else in the game never accidentally sets _upgrade_reveal_skip_
# requested with nothing listening for it.
var _upgrade_reveal_skip_requested: bool = false

@export var shadow_y_offset: float = 0.0
# Same reasoning as field_chest.gd's own shadow_y_offset - this forge is
# built from exact hand-authored Polygon2D pieces, not sprite/texture art,
# so VisualBounds measures its REAL geometric bottom edge precisely (the
# bottom of the two supports), with no trailing-cloth/padding overhang to
# correct for - the RoomState.entity_shadow_y_offset global default (-18)
# would lift the shadow above that already-correct base, same as it would
# for the chest.

@onready var forge_root: Node2D = $ForgeRoot
@onready var slab: Polygon2D = $ForgeRoot/Slab
@onready var support_left: Polygon2D = $ForgeRoot/SupportLeft
@onready var support_right: Polygon2D = $ForgeRoot/SupportRight
@onready var offer_prompt: Control = $PromptCanvas/OfferPrompt
@onready var prompt_label: Label = $PromptCanvas/OfferPrompt/PromptColumn/PromptLabel
@onready var choice_row: HBoxContainer = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow
@onready var take_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/TakeButton
@onready var leave_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/LeaveButton

var _used: bool = false
# True once this forge has actually spent a shard on an upgrade THIS
# visit (see _on_take_pressed()) OR RoomState.forge_used already recorded
# it as used before this node even loaded (see _ready() below - a same-
# room reload, e.g. after a battle round trip, rebuilds this node fresh
# from room_layout and would otherwise forget it was already used).
# _show_prompt() reads this (alongside the live shards/eligibility check)
# every time it runs, so the prompt always reflects current reality
# rather than a snapshot taken once at contact.
var _player_in_contact: Player = null
var _offer_tween: Tween

func _ready() -> void:
	_build_geometry()
	EntityShadow.attach(self, forge_root, shadow_y_offset)
	_configure_offer_prompt()
	_style_prompt_text(prompt_label)
	_style_button(take_button)
	_style_button(leave_button)
	offer_prompt.modulate.a = 0.0
	set_process(false)
	if RoomState.forge_used.get(forge_id, false):
		_used = true
	take_button.pressed.connect(_on_take_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

func _configure_offer_prompt() -> void:
	var column: VBoxContainer = offer_prompt.get_node("PromptColumn")
	column.custom_minimum_size.x = prompt_width_px
	column.size.x = prompt_width_px

func _update_prompt_screen_position() -> void:
	var world_anchor: Vector2 = global_position + Vector2(-prompt_width_px / 2.0, -prompt_head_clearance_px)
	offer_prompt.position = get_viewport().canvas_transform * world_anchor

func _process(_delta: float) -> void:
	_update_prompt_screen_position()

func _style_prompt_text(label: Label) -> void:
	label.add_theme_font_override("font", PROMPT_FONT)
	label.add_theme_font_size_override("font_size", prompt_font_size)
	label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(label, true)

func _style_button(button: Button) -> void:
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", prompt_button_font_size)
	button.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)
	var hover_color: Color = HudPalette.SYSTEM_TEXT.lightened(0.35)
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_outline_color", OverlayStyle.light_color())
	button.add_theme_constant_override("outline_size", OverlayStyle.outline_width)

func _on_body_entered(body_node: Node2D) -> void:
	if body_node is Player:
		_player_in_contact = body_node
		_update_prompt_screen_position()
		set_process(true)
		_show_prompt()

func _on_body_exited(body_node: Node2D) -> void:
	if body_node == _player_in_contact:
		_player_in_contact = null
		set_process(false)
		_fade_prompt_to(0.0, prompt_fade_out_sec)

# Gated at PROMPT TIME, not once at _ready() (per this pass's own brief) -
# re-evaluated every time this runs (contact, and again after a Take press
# resolves, successful or not), so it always reflects live state: shards
# spent elsewhere, or an upgrade's own eligible-card set changing (a card
# removed at the shop, say) between one contact and the next.
func _show_prompt() -> void:
	var interactive := not _used and RunState.shards > 0 and CardUpgradeService.has_eligible_cards()
	if interactive:
		prompt_label.text = prompt_text
		choice_row.visible = true
	else:
		prompt_label.text = closed_prompt_text
		choice_row.visible = false
	_fade_prompt_to(1.0, prompt_fade_in_sec)

func _fade_prompt_to(target_alpha: float, duration: float) -> void:
	if _offer_tween:
		_offer_tween.kill()
	_offer_tween = create_tween()
	_offer_tween.tween_property(offer_prompt, "modulate:a", target_alpha, duration)

func _on_leave_pressed() -> void:
	_fade_prompt_to(0.0, prompt_fade_out_sec)

# Take: opens CardUpgradeService's own card-then-upgrade picker directly -
# no window of THIS script's own to own/wire, unlike field_chest.gd's
# weapon flow (which has to bounce through field_room.gd because Weapon
# PickupWindow is a scene-local node that script owns). CardUpgradeService
# is a plain autoload, callable from anywhere, so this forge is fully
# self-contained: nothing in field_room.gd needs to know a card upgrade is
# happening here at all.
#
# manage_pause=true (field context - see shop_window.gd's own _run_
# upgrade_purchase(), the reference this mirrors): unlike the shop, which
# has ALREADY paused the tree before this ever runs, nothing has paused
# anything yet when a player presses Take out in the field - this call
# has to pause it itself and unpause it again on close, same as battle.
# gd's own DevUpgradeButton caller, offer_upgrade()'s other existing user.
#
# Guarded by the same interactive check _show_prompt() itself uses
# (defensive, not expected to trigger live - the prompt shouldn't be
# showing Take at all once any of the three conditions fails) rather than
# trusting the button was already disabled/hidden, same "trust but verify"
# stance field_chest.gd's own _on_take_pressed() `if opened: return`
# guard takes.
func _on_take_pressed() -> void:
	if _used or RunState.shards <= 0 or not CardUpgradeService.has_eligible_cards():
		return
	_fade_prompt_to(0.0, prompt_fade_out_sec)
	var result: Dictionary = await CardUpgradeService.offer_upgrade(Callable(), true)
	match result["outcome"]:
		CardUpgradeService.Outcome.UPGRADED:
			# The mechanical swap (RunState.replace_card_in_deck()) already
			# happened inside offer_upgrade() above, before this line ever
			# runs - the reveal below is pure presentation layered AFTER an
			# already-committed change, never a gate in front of one, so
			# skipping it (see _play_upgrade_reveal()'s own doc) can only
			# ever shorten what the player SEES, never what actually
			# happened to their deck.
			await _play_upgrade_reveal(result["old_card"], result["new_card"])
			RunState.spend_shards(1)
			RunLogger.log_shard_spent(1, "forge")
			_used = true
			RoomState.forge_used[forge_id] = true
			upgraded.emit()
		CardUpgradeService.Outcome.CANCELLED, CardUpgradeService.Outcome.NO_ELIGIBLE_CARDS:
			pass # No spend, node remains available - nothing to change.
	# Re-show regardless of outcome, but only if the player is still
	# standing here - offer_upgrade()'s own await can take a while (the
	# player picking through two menus), and they may well have walked
	# off before it resolves. _show_prompt() re-reads live state, so this
	# correctly shows the non-interactive line post-upgrade or the SAME
	# accept/decline prompt again post-cancel, not a stale copy of either.
	if _player_in_contact != null:
		_show_prompt()

# Slab centered slab_height_px above the support tops; supports run from
# there down to local y=0 (this Area2D's own origin) - NOT the ground
# line itself (see shadow_y_offset's own doc: EntityShadow measures the
# real polygon bottom directly, so where the origin sits relative to that
# bottom doesn't matter) but centered the same way field_chest.gd's own
# ChestRoot is, for visual/positioning consistency with every other
# field interactable in this room. Two separate support pieces (not one
# wide base) is what actually reads as "table," not "solid block."
func _build_geometry() -> void:
	var half_total := (support_height_px + slab_height_px) / 2.0
	var slab_half_w := slab_width_px / 2.0
	var slab_half_h := slab_height_px / 2.0
	var slab_center_y := -half_total + slab_half_h

	slab.polygon = PackedVector2Array([
		Vector2(-slab_half_w, -slab_half_h), Vector2(slab_half_w, -slab_half_h),
		Vector2(slab_half_w, slab_half_h), Vector2(-slab_half_w, slab_half_h),
	])
	slab.position = Vector2(0, slab_center_y)
	slab.color = forge_color

	var support_half_w := support_width_px / 2.0
	var support_half_h := support_height_px / 2.0
	var support_top_y := slab_center_y + slab_half_h
	var support_center_y := support_top_y + support_half_h
	var support_x := slab_half_w - support_inset_px - support_half_w

	support_left.polygon = _support_points(support_half_w, support_half_h)
	support_left.position = Vector2(-support_x, support_center_y)
	support_left.color = forge_color

	support_right.polygon = _support_points(support_half_w, support_half_h)
	support_right.position = Vector2(support_x, support_center_y)
	support_right.color = forge_color

func _support_points(half_width: float, half_height: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(-half_width, -half_height), Vector2(half_width, -half_height),
		Vector2(half_width, half_height), Vector2(-half_width, half_height),
	])

# --- Upgrade reveal (see _on_take_pressed() and Upgrade Reveal exports) ---
#
# Any mouse/key press while a reveal is running skips it - gated on
# _upgrade_reveal_active so a press anywhere else in the game (including
# the very Take click that started this whole flow, which is already
# consumed by TakeButton's own gui input and never reaches here) can never
# set _upgrade_reveal_skip_requested with nothing listening for it.
func _unhandled_input(event: InputEvent) -> void:
	if not _upgrade_reveal_active or _upgrade_reveal_skip_requested:
		return
	if (event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed):
		_upgrade_reveal_skip_requested = true
		get_viewport().set_input_as_handled()

# Builds ITS OWN CanvasLayer/Card for exactly this one reveal and frees
# both when done - a one-shot presentation (one upgrade per forge visit),
# unlike field_room.gd's persistent Keeper offer card, so there's no
# instance worth keeping alive between visits. CARD_SCENE's own instance-
# then-wire order (add to a live tree FIRST, only THEN set_scale_factor()/
# set_card_data()) matches field_room.gd's own established ordering - see
# that file's _show_npc_offer_card() doc for exactly why getting this
# backwards silently breaks the card's display.
#
# Centered via get_viewport().get_visible_rect().size, not canvas_
# transform like _update_prompt_screen_position() above - this reveal has
# no world-position to track (unlike the approach prompt, which has to
# follow the forge), it's a fixed screen-center overlay, so the simpler
# viewport-size math is all it needs.
func _play_upgrade_reveal(old_card: CardData, new_card: CardData) -> void:
	_upgrade_reveal_skip_requested = false
	_upgrade_reveal_active = true

	var layer := CanvasLayer.new()
	add_child(layer)
	var card: Card = CARD_SCENE.instantiate()
	layer.add_child(card)
	card.set_scale_factor(upgrade_reveal_scale)
	card.set_card_data(old_card)
	# Static display, not an interactive one - same MOUSE_FILTER_IGNORE
	# treatment reward_screen.gd's own rare-drop reveal uses for the exact
	# same reason (nothing to disambiguate, hover would just be a
	# distraction) - skipping is handled globally via _unhandled_input()
	# above, not through this card's own click signal.
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.pivot_offset = card.custom_minimum_size / 2.0
	card.position = get_viewport().get_visible_rect().size / 2.0 - card.custom_minimum_size / 2.0
	card.modulate.a = 0.0
	card.scale = Vector2(upgrade_reveal_start_scale, upgrade_reveal_start_scale)

	# Rise: the BEFORE state fades/scales up into view.
	var rise_tween := create_tween()
	rise_tween.set_parallel(true)
	rise_tween.tween_property(card, "modulate:a", 1.0, upgrade_reveal_rise_sec)
	rise_tween.tween_property(card, "scale", Vector2.ONE, upgrade_reveal_rise_sec).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await _await_tween(rise_tween)
	card.modulate.a = 1.0
	card.scale = Vector2.ONE

	# BEFORE-state hold - long enough to register before it changes.
	await _await_hold(upgrade_reveal_before_hold_sec)

	# The change lands: values swap and the sound plays TOGETHER, unless
	# already skipped past this exact point - a skip requested during the
	# rise or the before-hold above jumps straight to the final values
	# with NO sound at all (the `else` branch below), rather than letting
	# a skip land right as the sound starts and cut it off mid-play, which
	# is the "audio glitch on skip" this feature's brief calls out.
	if not _upgrade_reveal_skip_requested:
		card.set_card_data(new_card)
		AudioManager.play_sfx("card_upgrade")
		var pulse_tween := create_tween()
		pulse_tween.tween_property(card, "scale", Vector2(upgrade_reveal_pulse_scale, upgrade_reveal_pulse_scale), upgrade_reveal_change_pulse_sec * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		pulse_tween.tween_property(card, "scale", Vector2.ONE, upgrade_reveal_change_pulse_sec * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await _await_tween(pulse_tween)
		card.scale = Vector2.ONE
		# AFTER-state hold - the player's own reading time, excluded from
		# this feature's ~1s pacing target (see upgrade_reveal_after_hold_
		# sec's own doc).
		await _await_hold(upgrade_reveal_after_hold_sec)
	else:
		card.set_card_data(new_card)

	# Dismiss - always runs, skip or not, so the reveal never just vanishes
	# mid-fade; skipping only ever shortens the segments ABOVE this line.
	var dismiss_tween := create_tween()
	dismiss_tween.tween_property(card, "modulate:a", 0.0, upgrade_reveal_dismiss_sec)
	await _await_tween(dismiss_tween)
	card.modulate.a = 0.0

	_upgrade_reveal_active = false
	layer.queue_free()

# Polls once a frame rather than trusting Tween's own "finished" signal,
# specifically so a skip mid-tween can act immediately: Tween.kill() does
# NOT emit "finished" (confirmed against Godot's own docs), so awaiting
# that signal directly would leave a skipped tween's caller hanging
# forever instead of returning early. Every property this drives is
# snapped to its own end value by the caller immediately after this
# returns (see _play_upgrade_reveal() above), so it doesn't matter whether
# this loop exits via natural completion or a mid-flight kill() - both
# leave the SAME final state.
func _await_tween(tween: Tween) -> void:
	while tween.is_valid() and tween.is_running():
		if _upgrade_reveal_skip_requested:
			tween.kill()
			return
		await get_tree().process_frame

# Same polling shape as _await_tween() above, for the reveal's two plain
# holds (no Tween involved for those - just time passing).
func _await_hold(duration: float) -> void:
	if duration <= 0.0:
		return
	var timer := get_tree().create_timer(duration)
	while timer.time_left > 0.0:
		if _upgrade_reveal_skip_requested:
			return
		await get_tree().process_frame
