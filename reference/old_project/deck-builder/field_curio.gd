extends Area2D
# A minimal second EVENT content (2026-08-28, second-event pass) - built
# to prove that a lighter event doesn't need Pay House's own dedicated
# interior scene/modal at all: a plain field-room Area2D, contact-
# triggered, resolved in place with a world-voice prompt, the same shape
# field_heap.gd already established for Sift/Leave. Duplicated from that
# file rather than sharing code with it (same "duplicate a proven shape"
# convention this project keeps choosing over a premature abstraction),
# trimmed down for a ONE-SHOT interaction instead of a repeatable pull:
# no escalating cost, no draw-without-replacement pool, no per-frame
# player-tracking (see prompt positioning's own note below for why that
# one specifically doesn't apply here). Instanced by field_room.gd's
# _spawn_curio().
#
# Placeholder content only - this file's own header inherits the same
# "final text and design are not mine to write" instruction field_heap.gd
# already carries; Investigate/Leave and the seeded outcome table below
# exist to exercise the pattern, not to ship real content.
#
# --- Reuse report: SiftOutcomeData/SiftOutcomeTable/SiftOutcomeResolver,
# no renaming needed ---
#
# All three are already effect-schema/resolver classes with no SIFT-
# specific behavior baked in - only their NAMES reference sifting, a
# historical-authorship artifact from where they were first built, not a
# functional coupling. SiftOutcomeResolver.resolve(outcome) just executes
# whatever effect_type a SiftOutcomeData carries; it has no idea (and no
# need to know) which interactable drew it. Reused here as-is, no
# renaming, exactly as asked.
#
# SiftOutcomePool.draw() is the ONE piece that IS genuinely sift-
# specific, and it's deliberately NOT reused here: it tracks drawn
# indices in the single shared RunState.sift_outcomes_drawn array, with
# no notion of WHICH table an index belongs to. A second interactable
# calling SiftOutcomePool.draw() against its OWN separate table would
# silently collide with the heap's own draw-tracking (index 2 "already
# drawn" for one table says nothing about index 2 of a different table).
# This curio doesn't need that machinery anyway - "a single prompt with
# two options and a resolved outcome" is a ONE-SHOT interaction, not a
# repeat-until-exhausted pool, so it picks exactly once via a plain
# WeightedRandom.pick() over its own table (see _on_investigate_pressed())
# and never needs run-scoped drawn-set tracking at all - only a room-
# instance-local `_resolved` flag, the same "per-instance state IS
# per-visit state" shape field_chest.gd's own `opened` already uses.

signal resolved(outcome: SiftOutcomeData)
# Reports what got resolved. Fires once, ever, per instance - there's no
# repeat draw here to report a second time. field_room.gd USED TO be this
# signal's only listener, refreshing its own HUD's HP bar whenever the
# outcome happened to be HP_CHANGE (VitalsBar was push-fed, not self-
# updating) - see field_heap.gd's own `pulled` doc for why that listener
# is gone now (2026-09-05, HP-signal pass) and why this signal is left in
# place anyway.

@export var outcome_table: SiftOutcomeTable = null

@export_group("Approach")
@export var trigger_width_px: float = 360.0
@export var approach_stop_distance_px: float = 190.0
# Flat pixel values, NOT multipliers off a visual-size export the way
# field_heap.gd's own trigger_width_multiplier/approach_stop_multiplier
# are - this object has no equivalent "how big is the pile" tunable
# driving its own footprint (it's a small, person-scale placeholder, not
# a room-dominating pile), so there's nothing for a ratio to scale
# against. Same flat-value shape (and near-identical defaults) field_
# npc.gd's own trigger_width_px/approach_stop_distance_px already use for
# the same reason.

@export_group("Silhouette")
@export var curio_size_px: float = 50.0
@export var curio_color: Color = Color(0.42, 0.38, 0.33, 1)
# Placeholder only ("final text and design are not mine to write," per
# this pass's own brief) - a single small diamond, same hand-drawn-
# Polygon2D placeholder language as field_chest.gd's own Body/Lid/Latch
# and field_heap.gd's own mound, just simpler (nothing here needs an
# open/closed state or a taper). Built once in _ready(), not baked into
# field_curio.tscn, so a retune only ever touches this one number.

const OFFER_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# Same world-voice serif field_npc.gd/field_heap.gd's own OFFER_FONT
# already uses - what this object "says" is world content, not a
# system-voice HUD readout.

@export_group("Offer Prompt")
@export var prompt_width_px: float = 380.0
@export var prompt_vertical_gap_px: float = 150.0
# LOWERED from 220 (2026-08-29, prompt-hierarchy pass - consistency
# companion to field_chest.gd/field_heap.gd's own identical change) - the
# old value read as floating well above the interaction rather than
# attached to it. A hand-eyeballed starting point, expect to retune again
# once seen live.
#
# A FIXED offset above THIS NODE's own origin, not the player - field_
# heap.gd's own prompt had to switch to per-frame player-tracking
# specifically because its trigger zone was wide enough (and its own
# visual tall enough) that "fixed relative to the interactable" visibly
# diverged from "above the player." Neither applies here: this object is
# person-scale with a narrow (360px) trigger zone, the same profile
# DESIGN.md's own NPCs-section note already identifies as the case where
# a flat offset stays correct (see field_npc.gd's own OfferLabel, which
# has never needed to change for the same reason). If this object's own
# size or trigger width ever grows, this positioning would need the same
# fix field_heap.gd already got.
@export var offer_font_size: int = 24
# The world-voice line's own size (2026-08-29, prompt-hierarchy pass) -
# RAISED from 20, the shared value this used to hand to BOTH ResultLabel
# and the Investigate/Leave buttons (same bug field_chest.gd's own
# identical pass fixes - see that file's own doc). Label-only now - see
# offer_button_font_size below for the buttons' own, deliberately
# smaller, size.
# No local offer_color export any more (2026-08-30, world-voice color
# fix) - reads HudPalette.WORLD_TEXT directly at the point of use (see
# _style_prompt_text() below), one shared world-voice color instead of
# an independent copy per field prompt.
@export var offer_button_font_size: int = 20
# Investigate/Leave's own size - split out from offer_font_size above so
# the buttons can be smaller than the world-voice line rather than tied
# to its size (2026-08-29, prompt-hierarchy pass). RAISED 16 -> 20
# (2026-08-31, prompt-readability pass) - 16 read as too small to
# comfortably click/read live, the same complaint field_chest.gd's own
# prompt_button_font_size and field_heap.gd's own offer_button_font_size
# got at the same time (all three share this exact value by design - see
# each file's own doc). 20 stays visibly smaller than offer_font_size's
# 24, preserving the prompt-hierarchy pass's own reasoning (see that
# export's own doc), but is a real, legible step up from 16.
@export var offer_fade_in_sec: float = 0.2
@export var offer_fade_out_sec: float = 1.1
@export var outcome_display_sec: float = 1.6

@export var shadow_y_offset: float = 0.0
# Overrides RoomState.entity_shadow_y_offset's own -18 default (2026-08-30,
# shadow-tuning pass) - this curio's diamond marker is a plain hand-built
# Polygon2D (_build_geometry()) with its own base already sitting exactly
# at local y=0 - no trailing cloth/limb, nothing for VisualBounds to
# overestimate. Confirmed live: the shadow already lands exactly at this
# curio's own origin (0px offset) - the -18 global default would lift it
# 18px above its real, already-correct base.

@onready var visual_root: Node2D = $VisualRoot
@onready var offer_prompt: Control = $OfferPrompt
@onready var result_label: Label = $OfferPrompt/PromptColumn/ResultLabel
@onready var choice_row: HBoxContainer = $OfferPrompt/PromptColumn/ChoiceRow
@onready var investigate_button: Button = $OfferPrompt/PromptColumn/ChoiceRow/InvestigateButton
@onready var leave_button: Button = $OfferPrompt/PromptColumn/ChoiceRow/LeaveButton
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _resolved: bool = false
var _offer_tween: Tween

func _ready() -> void:
	_build_geometry()
	# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
	# gd's own doc.
	EntityShadow.attach(self, visual_root, shadow_y_offset)
	_configure_offer_prompt()
	var shape: RectangleShape2D = collision_shape.shape.duplicate()
	shape.size.x = trigger_width_px
	collision_shape.shape = shape
	_style_prompt_text(result_label)
	_style_button(investigate_button)
	_style_button(leave_button)
	offer_prompt.modulate.a = 0.0
	investigate_button.pressed.connect(_on_investigate_pressed)
	leave_button.pressed.connect(_on_leave_pressed)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

# One small flat diamond, centered curio_size_px above the ground line -
# reads as a found object at a glance without claiming to be final art.
func _build_geometry() -> void:
	var marker := Polygon2D.new()
	var half := curio_size_px / 2.0
	marker.polygon = PackedVector2Array([
		Vector2(0, -curio_size_px), Vector2(half, -half),
		Vector2(0, 0), Vector2(-half, -half),
	])
	marker.color = curio_color
	visual_root.add_child(marker)

func _configure_offer_prompt() -> void:
	offer_prompt.position = Vector2(-prompt_width_px / 2.0, -prompt_vertical_gap_px)
	var column: VBoxContainer = offer_prompt.get_node("PromptColumn")
	column.custom_minimum_size.x = prompt_width_px
	column.size.x = prompt_width_px

# Calls OverlayStyle.apply_to_label() directly (2026-08-29, prompt-
# hierarchy pass) - REPLACES a local outline_col computed from this
# file's own offer_outline_width/offer_outline_opacity (0.35, well below
# the shared outline_opacity of 0.85) with the same shared, stronger
# treatment field_chest.gd's own prompt_label already uses - raising
# contrast for the world-voice line (this pass's own brief).
#
# use_light_outline=true (2026-08-30, world-voice color fix) - WORLD_TEXT
# is dark, so it needs OverlayStyle's light outline preset, same as
# field_heap.gd/field_chest.gd's own prompt labels.
func _style_prompt_text(label: Label) -> void:
	label.add_theme_font_override("font", OFFER_FONT)
	label.add_theme_font_size_override("font_size", offer_font_size)
	label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(label, true)

# REGISTER FIX (2026-08-29, prompt-hierarchy pass, consistency companion
# to field_chest.gd/field_heap.gd's own identical fix, which this file
# never received) - Investigate/Leave are mechanical UI, not this
# object's own "voice" the way ResultLabel's outcome text above is (still
# Spectral/HudPalette.WORLD_TEXT, untouched): no font override (project default
# sans, not OFFER_FONT's Spectral any more), HudPalette.SYSTEM_TEXT for
# the fill, same direct-read convention field_chest.gd/field_heap.gd's
# own buttons already follow - offer_hover_color is gone (was only ever
# read here) in favor of the same SYSTEM_TEXT.lightened(0.35) brighten
# those two use. OverlayStyle.light_color() replaces color() for the same
# "dark base text needs a light outline" reason their own doc gives.
func _style_button(button: Button) -> void:
	button.flat = true
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", offer_button_font_size)
	button.add_theme_color_override("font_color", HudPalette.SYSTEM_TEXT)
	var hover_color: Color = HudPalette.SYSTEM_TEXT.lightened(0.35)
	button.add_theme_color_override("font_hover_color", hover_color)
	button.add_theme_color_override("font_pressed_color", hover_color)
	button.add_theme_color_override("font_outline_color", OverlayStyle.light_color())
	button.add_theme_constant_override("outline_size", OverlayStyle.outline_width)

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_show_prompt()

func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		_fade_offer_to(0.0, offer_fade_out_sec)

# Re-establishes the "choosing" state, or the resolved/inert one -
# Investigate hidden once resolved (there is nothing left to investigate
# a second time - this object is a ONE-SHOT, unlike the heap's repeat-
# until-exhausted pull), ResultLabel only showing the resolved flavor
# line in that case. Called on every fresh contact.
func _show_prompt() -> void:
	choice_row.visible = true
	investigate_button.visible = not _resolved
	if _resolved:
		result_label.text = "There's nothing more to find here."
		result_label.visible = true
	else:
		result_label.visible = false
	_fade_offer_to(1.0, offer_fade_in_sec)

func _fade_offer_to(target_alpha: float, duration: float) -> void:
	if _offer_tween:
		_offer_tween.kill()
	_offer_tween = create_tween()
	_offer_tween.tween_property(offer_prompt, "modulate:a", target_alpha, duration)

# Dismisses the prompt exactly like walking out of contact does, WITHOUT
# resolving anything - same "Leave never costs you the choice" shape
# field_heap.gd's own _on_leave_pressed() already establishes. Re-
# entering contact shows the same live choice again, since nothing here
# has been decided yet.
func _on_leave_pressed() -> void:
	_fade_offer_to(0.0, offer_fade_out_sec)

# The Investigate choice - picks ONE entry from outcome_table (plain
# WeightedRandom.pick() over its own entries, not SiftOutcomePool.draw() -
# see this file's own header for why that's deliberate), resolves it,
# shows the result, then settles into the resolved/inert state for good.
# Never reachable a second time (InvestigateButton is hidden once
# resolved - see _show_prompt()).
func _on_investigate_pressed() -> void:
	var weights: Dictionary = {}
	for i in outcome_table.entries.size():
		weights[i] = outcome_table.entries[i].weight
	var outcome: SiftOutcomeData = outcome_table.entries[WeightedRandom.pick(weights)]
	_resolved = true
	choice_row.visible = false
	result_label.visible = true
	result_label.text = outcome.text
	# Awaited BEFORE the emit below - same ordering reason field_heap.gd's
	# own _on_sift_pressed() already documents: UPGRADE_CARD's own
	# CardUpgradeService.offer_upgrade() call doesn't resolve until the
	# player picks (or cancels), and any HP_CHANGE effect has to have
	# already landed in RunState before the HUD refresh downstream reads it.
	await SiftOutcomeResolver.resolve(outcome)
	resolved.emit(outcome)
	await get_tree().create_timer(outcome_display_sec).timeout
	if not is_inside_tree():
		return # The room could in principle be torn down mid-wait - defensive, mirrors field_heap.gd's own identical guard.
	_show_prompt()
