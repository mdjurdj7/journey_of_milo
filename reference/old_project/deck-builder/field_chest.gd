extends Area2D
class_name FieldChest
# Same Area2D "detection zone, not a solid body" idea as field_blob.gd -
# walking into the chest is what opens it. Instanced by field_room.gd's
# _spawn_chest() when RoomState.room_layout happens to include one,
# rather than always being present. class_name added (2026-08-29,
# three-chest treasure room) purely so room_state.gd/field_room.gd can
# reference RewardKind below by name - COMBAT no longer ever spawns a
# chest at all (removed entirely in the 2026-08-29 single-screen pass -
# see room_state.gd's own CHEST_CHANCE doc), so TREASURE is this
# script's only caller today.

# Which of the three treasure-room roles this specific chest plays (see
# room_state.gd's own _generate_treasure_layout(), the only place these
# are assigned) - GOLD preserves this script's entire original
# single-purpose behavior unchanged (flat grant + optional bonus weapon
# roll, see weapon_drop_chance below), CARD and WEAPON are the two new
# ones. One script, one scene, three configurations - same "@export
# decides shape" convention EnemyData/CardData already use everywhere,
# rather than three near-identical chest scripts.
enum RewardKind { GOLD, CARD, WEAPON }
@export var reward_kind: RewardKind = RewardKind.GOLD

@export var chest_id: String = ""
# Which entry of RoomState.chest_opened this SPECIFIC chest instance is
# tracked under (2026-08-29, three-chest treasure room) - mirrors field_
# blob.gd's own blob_id/RoomState.blob_defeated exactly: every chest in a
# room shares this same script, this is what makes each instance's own
# opened-state independent of its siblings. field_room.gd assigns this
# right after spawning, same as blob_id.

@export var prompt_text: String = ""
# The world-voice flavor line shown in the approach prompt (2026-08-29,
# prompt-first interaction pass) - one PER CHEST INSTANCE, threaded in
# from room_state.gd's own three exported strings via the room_layout
# dict, same "set per-instance at spawn time" shape min_gold/max_gold
# already use below - not a single flat default meant to be shared,
# since all three chests need a DIFFERENT line.

@export var closed_prompt_text: String = "It will not open now."
# The world-voice line a FORECLOSED chest shows on contact instead of
# prompt_text above (2026-08-29, chest-states pass) - see close_
# permanently()/_show_prompt() for where this actually gets read. One
# flat default shared by all three chests (unlike prompt_text, which is
# deliberately per-instance) - unlike the three flavor lines, which are
# each chest's own individual voice, this is the SAME fact about the
# SAME mechanic (a sibling was taken) regardless of which chest it's
# said at, so there's no reason for it to vary per instance the way
# prompt_text does.

signal weapon_offered(weapon_data: WeaponData)
# Emitted only for a WEAPON-kind chest, or when a GOLD-kind chest's own
# bonus weapon roll lands (see weapon_drop_chance below) - field_room.gd
# listens (see its _spawn_chest()) and owns opening its own
# WeaponPickupWindow instance for the Equip/Leave decision. Gold never
# gets a signal like this (2026-08-27, in-field reward pass) - it's
# granted directly, right here in _grant_gold(), with nothing left for
# field_room.gd to decide. Same "just report it, let something else
# decide what it means" shape field_exit.gd's own exit_entered already
# uses.

signal card_offered(card_data: CardData)
# CARD-kind's own counterpart to weapon_offered above (2026-08-29) - the
# card itself is rolled here (see _offer_card()), field_room.gd owns
# turning it into the actual in-field reveal (the Keeper's own
# presentation TECHNIQUE, not her own function - see field_room.gd's
# _on_chest_card_offered() for why this is a new function rather than a
# third caller of her already-fragile, already-debugged one).

signal claimed
# Fired once, the instant the player presses TAKE at this chest's own
# approach prompt (see _on_take_pressed() below) - BEFORE its own reward-
# kind-specific logic runs, regardless of kind. REVISED (2026-08-29,
# prompt-first interaction pass): used to fire on mere CONTACT; now
# contact only ever arms the prompt (see _on_body_entered()), and Leave
# consumes nothing, so the actual commitment moved to Take. TREASURE's
# own exclusivity rule (taking any one of the three chests permanently
# forecloses the other two, unlocks the exit) reads off THIS, not off
# weapon_offered/card_offered/the gold grant itself, since all three
# kinds need to trigger the exact same room-level consequence the
# instant the chest is taken, independent of whatever secondary,
# no-longer-a-real-decision presentation (the Keeper-style card, weapon_
# pickup_window's own internal Take/Leave) happens afterward - see
# field_room.gd's _on_any_chest_claimed() and, for the weapon case
# specifically, _on_chest_weapon_offered()'s own doc.

@export var min_gold: int = 20
@export var max_gold: int = 20
# Read only by a GOLD-kind chest (see _grant_gold()) - the actual amount
# is rolled once when opened, between these two. TREASURE's own Chest A
# uses a richer range than the old COMBAT chest used to (see room_
# state.gd's TREASURE_CHEST_GOLD_MIN/MAX, now this script's only real
# caller - COMBAT_CHEST_GOLD_MIN/MAX are unreferenced dead consts left
# over from before COMBAT chests were removed entirely). Defaulting both
# to 20 means a chest nobody bothers configuring still behaves sanely.

@export var weapon_drop_chance: float = 0.0
# GOLD-kind ONLY (see _grant_gold()) - the odds a gold chest ALSO grants
# a weapon, independent of (on top of, never instead of) its gold roll.
# Irrelevant to a WEAPON-kind chest, which always grants one unconditionally
# (see _offer_weapon()) - this field is specifically "gold's own optional
# bonus roll," not "the chance ANY chest grants a weapon." Defaults to 0
# so a chest nobody configures behaves exactly as before.
@export var weapon_common_weight: float = 70.0
@export var weapon_rare_weight: float = 24.0
# Read by both GOLD-kind's bonus roll and WEAPON-kind's guaranteed one -
# one shared sense of "how rare is rare" for weapons regardless of which
# kind of chest is granting one.

@export var card_common_weight: float = 70.0
@export var card_rare_weight: float = 24.0
# CARD-kind's own weighting for CardPool.pick_weighted_card() (see
# _offer_card()) - same COMMON:RARE ratio weapon_common_weight/weapon_
# rare_weight and reward_screen.gd's own regular card-choice roll all
# default to, not a separately-tuned number for no particular reason.
# Same COMMON:RARE ratio reward_screen.gd's own regular card-choice
# roll uses (its own common_weight/rare_weight) - one shared sense of
# "how rare is rare" across cards and weapons, not a separately-tuned
# ratio for no particular reason.

# --- Silhouette (DECIDED - same hand-drawn Polygon2D language as the
# player/enemy silhouettes, not a flat colored square) ---
#
# Three pieces, all built from these exports rather than baked into
# field_chest.tscn - Body (the box) and Latch stay fixed; Lid pivots at
# its own bottom edge (lid_gap_px above Body, so the seam between them
# reads as a visible line even though every piece shares one flat fill
# color) so it can rotate open. See _build_geometry().
@export var chest_width_px: float = 64.0
@export var chest_height_px: float = 56.0
@export var lid_height_px: float = 20.0
@export var lid_gap_px: float = 3.0
@export var latch_width_px: float = 14.0
@export var latch_height_px: float = 16.0

@export var chest_color: Color = Color(0.95, 0.85, 0.2, 1)
# "Opened" is its own color, not just a dimmed version of the closed
# one - a duller, spent-looking gold, so an opened chest reads as opened
# at a glance instead of just darker.
@export var opened_color: Color = Color(0.55, 0.45, 0.25, 1)
@export var open_flash_color: Color = Color(1, 1, 0.6, 1)
# A quick brighten right at the moment of opening, before settling into
# opened_color - see _play_open_flourish().

@export var lid_open_angle_deg: float = -55.0
# How far the Lid rotates open around its hinge (its own bottom edge) -
# the state change the task asked for beyond a flat recolor: an opened
# chest looks structurally different, not just darker.
@export var lid_open_duration_sec: float = 0.35

const OPEN_FLASH_DURATION := 0.15
const OPEN_SCALE_PUNCH := Vector2(1.25, 1.25)
const OPEN_SCALE_DURATION := 0.12

# --- Approach prompt (DECIDED, 2026-08-29 - prompt-first interaction
# pass, replaces "contact grants immediately"; ANCHORING/Z-ORDER/
# LEGIBILITY/REGISTER corrected the same day, cache-room pass; VERTICAL
# CLEARANCE and DRAW ORDER corrected again same day, on top of that -
# see prompt_clearance_gap_px's own doc and PromptCanvas's own doc below) ---
#
# DUPLICATED out of field_heap.gd's own fade/lifecycle prompt machinery
# (_fade_offer_to(), the contact-in/contact-out lifecycle) rather than
# extracted into something shared - explicit instruction for this pass:
# two uses isn't enough to justify guessing at the right shared shape
# yet. Every export/const/function below with an "(heap-shape)" note is
# a deliberate copy, not a coincidence - if the heap's own version is
# ever retuned, this one needs its own separate retune, on purpose.
@export_group("Approach Prompt")
@export var prompt_width_px: float = 420.0
@export var prompt_clearance_gap_px: float = 70.0
# RAISED 40 -> 70 (2026-09-02, prompt-vertical-tuning pass) - Take/Leave
# needed more clearance over the Wanderer's own head; retune again here,
# not by touching the max(belonging, player) height math itself.
#
# REPLACES prompt_head_clearance_px (2026-09-02, prompt-anchor pass) - a
# fixed distance from the chest's own ORIGIN could never be right once
# belonging_offset (per-instance, see FieldChest's own export) lets a
# belonging's real visual sit well away from that origin, and couldn't
# tell a short belonging (the case) from a tall one (the roll) either.
# Now just the CLEARANCE GAP above whichever is taller, the belonging or
# the player, at the anchor point _update_prompt_screen_position() below
# actually computes - see that function's own doc for the full formula.
# real height difference is handled by the max() itself, so this only
# ever needs to cover breathing room on top of that, not a second whole
# figure's worth of margin the way the old fixed clearance did.
@export var prompt_font_size: int = 24
# The world-voice line's own size (2026-08-29, prompt-hierarchy pass) -
# RAISED from 20, the shared value this used to hand to BOTH the label
# and the Take/Leave buttons. That sharing was the actual bug: identical
# size meant a Button (with its own hover feedback and hit padding)
# always read louder than plain Label text at the same size, inverting
# which one the player should read first. Now label-only - see prompt_
# button_font_size below for the buttons' own, deliberately smaller, size.
@export var prompt_button_font_size: int = 20
# Take/Leave's own size - split out from prompt_font_size above
# specifically so the buttons can be smaller than the world-voice line
# rather than tied to its size (2026-08-29, prompt-hierarchy pass).
# RAISED 16 -> 20 (2026-08-31, prompt-readability pass) - 16 read as too
# small to comfortably click/read live, the same complaint field_heap.gd's
# own offer_button_font_size and field_curio.gd's own offer_button_font_
# size got at the same time (all three share this exact value by design -
# see each file's own doc). 20 stays visibly smaller than prompt_font_
# size's 24 (preserving the prompt-hierarchy pass's own reasoning - see
# that export's own doc for why equal sizes would let the button outread
# the label), but is a real, legible step up from 16. Mechanical UI,
# still subordinate to the line it's responding to - see _style_button()'s
# own doc for the color half of that same subordination.
# No local prompt_color export any more (2026-08-30, world-voice color
# fix) - reads HudPalette.WORLD_TEXT directly at the point of use (see
# _style_prompt_text() below), one shared world-voice color instead of
# an independent copy per field prompt.
@export var prompt_fade_in_sec: float = 0.2
@export var prompt_fade_out_sec: float = 0.55
# HALVED from 1.1 (2026-09-02, prompt-distance pass - "50% quicker") - the
# world-voice line was lingering too long after contact ends; fade_in_sec
# is untouched, only the fade-OUT half of the read changed.
# prompt_z_index REMOVED (2026-08-29, draw-order fix) - see PromptCanvas's
# own doc on $PromptCanvas in field_chest.tscn for what replaced it and
# why: z_index=100 measured as correctly set (verified directly - canvas
# RID matched the player's own, no CanvasLayer, no y_sort, no competing
# z_index anywhere in either ancestor chain) and STILL didn't win visually
# against the player's own sprite. Rather than keep trusting a same-canvas
# z_index comparison that already passed this exact check once while the
# bug was live, the prompt now lives on its own CanvasLayer instead - a
# mechanism that doesn't depend on same-canvas z-sort at all, so there's
# nothing left to get subtly wrong the same way again.

const PROMPT_FONT: Font = preload("res://assets/fonts/Spectral-Regular.ttf")
# heap-shape: field_heap.gd's own OFFER_FONT - world-voice serif, same
# reasoning (what the chest "says" is world content, Take/Leave included,
# same register as the prompt line itself).

@export var shadow_y_offset: float = 0.0
# Overrides RoomState.entity_shadow_y_offset's own -18 default (2026-08-30,
# shadow-tuning pass) - this chest is built from an exact hand-authored
# polygon (_build_geometry()), not sprite/texture art, so VisualBounds
# measures its REAL geometric bottom edge precisely, with no trailing-
# cloth/limb overhang to correct for. Confirmed live: the shadow already
# lands exactly at chest_height_px/2 (28px) below this chest's own origin,
# matching Body's own polygon bottom edge exactly - the -18 global default
# would lift it 18px above its real, already-correct base. Still 0.0 with
# belonging_texture set below (2026-09-01, belongings-sprite pass) -
# _build_belonging_sprite() bottom-anchors the sprite itself (real alpha-
# scanned content bottom, not the padded texture rect), so the measured
# bottom is already correct with no per-entity correction needed, the same
# as the polygon case above.

@export var belonging_texture: Texture2D
# When set, ChestRoot shows a single bare Sprite2D with this texture
# instead of the Body/Lid/Latch polygons (2026-09-01, belongings-sprite
# pass - painted plates with color/value baked in, replacing the yellow
# placeholder box for real content). Null (the default) keeps every
# existing chest on the unchanged polygon path - see _build_visual().

@export var belonging_scale: float = 0.167
# ONE shared scale factor for every belonging sprite (2026-09-01, real-
# asset pass) - not threaded per-instance the way belonging_texture is:
# the three PNGs are pre-normalized to each other (same real-world scale
# baked into their own relative pixel sizes), so a single script default
# here, left unset per-chest, already applies identically to all three.
# 0.167 is a starting point, not a measured/tuned value - see this pass's
# own brief.

@export var belonging_scale_multiplier: float = 1.0
# Per-instance correction ON TOP OF belonging_scale above (2026-09-01,
# belongings-tuning pass) - threaded through room_state.gd's layout dict
# exactly as belonging_texture is (see RoomState.treasure_chest_a/b/c_
# scale_multiplier). Exists specifically because the case asset's own
# authored proportion (its size relative to the other two, baked into the
# source art itself) reads too small - NOT because belonging_scale, the
# anchoring, or this chest's placement is wrong. Deliberately breaks
# belonging_scale's "one shared factor" property for exactly one instance
# rather than retuning that shared constant, which would then be wrong
# for the other two.

@export var belonging_offset: Vector2 = Vector2.ZERO
# Manual per-instance nudge ON TOP OF the automatic placement (2026-09-01,
# belongings-tuning pass) - threaded through room_state.gd's layout dict
# exactly as belonging_scale_multiplier is (see RoomState.treasure_chest_
# a/b/c_offset). _build_belonging_sprite() below still does the real work
# (horizontal centering, bottom-anchoring to the alpha-scanned content
# edge) - this is added on top of that result, not a replacement for it,
# so a small hand correction doesn't have to fight or re-derive the
# automatic math. x moves the sprite off-center; y moves its anchored
# bottom off the chest's own origin (positive = down, same direction
# every other y export in this project already uses). The contact shadow
# re-measures the sprite's actual post-offset position on its own (see
# EntityShadow.attach() in _ready() below), so it follows this without
# needing its own copy of the offset.

@onready var chest_root: Node2D = $ChestRoot
@onready var body: Polygon2D = $ChestRoot/Body
@onready var lid: Polygon2D = $ChestRoot/Lid
@onready var latch: Polygon2D = $ChestRoot/Latch
@onready var belonging_sprite: Sprite2D = $ChestRoot/BelongingSprite
@onready var offer_prompt: Control = $PromptCanvas/OfferPrompt
@onready var prompt_label: Label = $PromptCanvas/OfferPrompt/PromptColumn/PromptLabel
@onready var choice_row: HBoxContainer = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow
@onready var take_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/TakeButton
@onready var leave_button: Button = $PromptCanvas/OfferPrompt/PromptColumn/ChoiceRow/LeaveButton

var opened: bool = false
var _foreclosed: bool = false
# True only for a chest FORECLOSED by a sibling being taken (2026-08-29,
# chest-states pass) - see close_permanently()'s own doc. `opened` alone
# can't distinguish "this exact chest was taken" from "a sibling was
# taken instead" (close_permanently() sets both `opened` AND this), and
# _show_prompt() needs to tell them apart: a foreclosed chest still shows
# a prompt on contact (closed_prompt_text, no choice row), a genuinely
# TAKEN one shows nothing at all (its own body_entered is fully
# disconnected instead - see _on_take_pressed() - so _show_prompt() is
# never even reachable for that case).
var _player_in_contact: Player = null
# Set on contact, cleared on exit (see _on_body_entered()/_on_body_
# exited()) - drives BOTH _grant_gold()'s floating-gold-number anchor
# AND _process()'s own per-frame screen-position update (2026-08-29,
# draw-order fix brought _process() back - see PromptCanvas's own doc in
# field_chest.tscn for why, and _process()'s own doc below for what it
# actually recomputes now, which is NOT "follow the player" - that
# anchoring bug is still fixed, unchanged from the prior pass).
var _offer_tween: Tween

func _ready() -> void:
	_build_visual()
	# Contact shadow (2026-08-30, grounding-cue pass) - see entity_shadow.
	# gd's own doc. chest_root is CENTRE-anchored, not base-anchored (its
	# own polygon math spans -28..+28 around this chest's origin) - the
	# whole reason this measures real bounds rather than assuming y=0 is
	# the ground.
	EntityShadow.attach(self, chest_root, shadow_y_offset)
	_configure_offer_prompt()
	_style_prompt_text(prompt_label)
	_style_button(take_button)
	_style_button(leave_button)
	offer_prompt.modulate.a = 0.0
	set_process(false) # Only ever needs to run while a player is in contact - see _process()/_on_body_entered()/_on_body_exited() below.
	# Dictionary, keyed by chest_id, not a single shared bool (2026-08-29,
	# three-chest treasure room) - mirrors RoomState.blob_defeated's own
	# per-blob-id shape exactly, for the exact same reason: multiple
	# chests can now exist in the SAME room, and a single flag could never
	# tell them apart (see RoomState.chest_opened's own doc for the full
	# reasoning, and this room's own DESIGN.md Polish Backlog note on why
	# a FORECLOSED sibling - see close_permanently() below - deliberately
	# does NOT also write here: nothing in this game reloads a TREASURE
	# room mid-visit today, so there is nothing for that state to survive).
	if RoomState.chest_opened.get(chest_id, false):
		opened = true
		_set_opened_colors()
		lid.rotation = deg_to_rad(lid_open_angle_deg)
	else:
		take_button.pressed.connect(_on_take_pressed)
		leave_button.pressed.connect(_on_leave_pressed)
		body_entered.connect(_on_body_entered)
		body_exited.connect(_on_body_exited)

# heap-shape: field_heap.gd's own _configure_offer_prompt() - only the
# column's own WIDTH is fixed up-front here; its POSITION is recomputed
# every frame while shown instead (see _process() below).
func _configure_offer_prompt() -> void:
	var column: VBoxContainer = offer_prompt.get_node("PromptColumn")
	column.custom_minimum_size.x = prompt_width_px
	column.size.x = prompt_width_px

# DRAW-ORDER FIX (2026-08-29) - OfferPrompt now lives on its own
# CanvasLayer ($PromptCanvas in field_chest.tscn, a sibling of ChestRoot
# rather than a plain child of this Area2D) instead of inside the normal
# world-space Node2D tree - see prompt_z_index's own removal note above
# for why a same-canvas z_index, even verified correct, still lost to the
# player's own sprite. A CanvasLayer is its own separate compositing
# pass, layer 1 by default (the same default field_room.tscn's own "UI"
# CanvasLayer already uses for weapon_pickup_window/deck_button/map_
# button) - ANYTHING on layer 1+ draws over the ENTIRE base world canvas
# (layer 0, where Player/every chest's own silhouette/all foreground
# geometry live), unconditionally, with no z_index comparison against
# world content ever entering into it.
#
# The cost: a Control on a CanvasLayer no longer shares a coordinate
# space with this Area2D - global_position on OfferPrompt is now raw
# VIEWPORT PIXELS, not world units, so anchoring it to this chest's own
# (static) world position requires projecting through the CURRENT camera
# transform - and because the camera moves (the player walking scrolls
# it), that projection has to be redone every frame the prompt could be
# visible, not just once in _ready() the way the previous (same-canvas,
# world-space) version could get away with.
#
# NEITHER axis anchors to global_position (this Area2D's own origin) any
# more (2026-09-02, prompt-anchor pass - REPLACES this doc's own previous
# "horizontal centering is UNCHANGED... origin" claim, which stopped being
# true the moment belonging_offset existed): both now read the belonging's
# own REAL rendered bounds instead, via VisualBounds.compute_bottom_
# slice(chest_root, 1.0) - the exact same call EntityShadow.attach() (see
# _ready() above) already makes against this same chest_root, so the
# prompt and the contact shadow are guaranteed to agree on where the
# belonging actually is, including any belonging_offset/belonging_scale_
# multiplier already baked into that measurement.
#
# Horizontal: the slice's own CENTER-x (transformed through chest_root's
# transform, then to_global()) - the belonging's real rendered horizontal
# center, not this Area2D's origin, which belonging_offset.x can now sit
# well away from (see belonging_offset's own doc on FieldChest for
# current per-instance values).
#
# Vertical: the slice's own real BOTTOM edge (belonging_offset.y already
# baked in, same as above) minus whichever is taller, the belonging
# itself (the slice's own measured height) or the player (_player_
# height_px() below) - a short belonging (the case) no longer lets the
# prompt sit low enough to overlap a much-taller player standing next to
# it - minus prompt_clearance_gap_px for breathing room on top of that.
func _update_prompt_screen_position() -> void:
	var local_bounds: Rect2 = VisualBounds.compute_bottom_slice(chest_root, 1.0)
	var chest_local_bounds: Rect2 = chest_root.transform * local_bounds
	var anchor_x: float = to_global(Vector2(chest_local_bounds.get_center().x, 0.0)).x
	var base_y: float = to_global(Vector2(0.0, chest_local_bounds.position.y + chest_local_bounds.size.y)).y
	var clearance_height := maxf(chest_local_bounds.size.y, _player_height_px())
	var world_anchor := Vector2(anchor_x - prompt_width_px / 2.0, base_y - clearance_height - prompt_clearance_gap_px)
	offer_prompt.position = get_viewport().canvas_transform * world_anchor

# The player's own real rendered height, base to top, in px (2026-09-02,
# prompt-anchor pass) - NOT hardcoded: RoomState.player_visual_scale is
# the same single source of truth field_room.gd itself reads for this
# exact figure (see that project's own player_shadow_y_offset doc, and
# this file's own now-removed prompt_head_clearance_px history, both
# independently re-deriving this same transform chain). Treated as a pure
# SIZE with its base AT local y=0 (per this pass's own brief), not the
# more precise real geometry those other two docs use (true topmost point
# -150.35 local, true bottom +17 local, ~167.35 apart) - PlayerVisual's
# own +17 position is a fixed POSITIONING nudge unrelated to how the
# sprite's own scale/atlas math determines its SIZE, so it's deliberately
# left out here: (97.5 + 128 - 30) * 8 * scale is the worst-case walk-
# frame's own topmost opaque row (30 of 256) magnitude alone, ~167.35px at
# today's scale (0.107) - matches "renders ~167px tall" exactly. FieldChest
# has no live reference to the actual Player/Visual nodes to measure
# directly the way field_room.gd's own EntityShadow.attach() call does -
# this recomputes the same number from the same shared export instead,
# rather than reaching across scenes for a node path this script has no
# other reason to know about.
func _player_height_px() -> float:
	var scale: float = RoomState.player_visual_scale
	return (97.5 + 128.0 - 30.0) * 8.0 * scale

# Runs only while a player is in this chest's own trigger zone (see
# _on_body_entered()/_on_body_exited() below, the only two callers of
# set_process()) - re-projects the SAME fixed world anchor point through
# whatever the camera's current transform happens to be, every frame,
# since the chest itself never moves but the camera does. Not "following
# the player" - see _update_prompt_screen_position()'s own doc - the
# anchor is still purely this chest's own position; only the SCREEN
# coordinates that world position maps to change as the camera scrolls.
func _process(_delta: float) -> void:
	_update_prompt_screen_position()

# The flavor line - world-voice (Spectral, full color), per the two-
# register rule. LEGIBILITY (2026-08-29, cache-room pass): REPLACES a
# hand-rolled outline (this file's own weaker prompt_outline_width/
# prompt_outline_opacity copies of the heap's identical fields, both
# since removed) with a direct call to OverlayStyle.apply_to_label() -
# the project's own existing shared legibility treatment (already used
# elsewhere in this same file, see _spawn_gold_number()'s own OverlayStyle.
# apply_to_label() call), already tuned for "readable over an arbitrary
# backdrop" project-wide (outline_opacity 0.85, outline_width 4) rather
# than the noticeably fainter 0.35/3 this file's own first draft used -
# that gap, not a missing treatment, was the actual low-contrast bug
# against a pale sky. No solid background panel added, per this pass's
# own brief.
#
# use_light_outline=true (2026-08-30, world-voice color fix) - WORLD_TEXT
# is dark, so it needs OverlayStyle's light outline preset, same as
# field_heap.gd/field_curio.gd's own prompt labels. This call is
# _style_prompt_text()'s own - _spawn_gold_number()'s separate apply_to_
# label() call below is untouched, still the dark-outline default.
func _style_prompt_text(label: Label) -> void:
	label.add_theme_font_override("font", PROMPT_FONT)
	label.add_theme_font_size_override("font_size", prompt_font_size)
	label.add_theme_color_override("font_color", HudPalette.WORLD_TEXT)
	OverlayStyle.apply_to_label(label, true)

# Take/Leave - REGISTER FIX (2026-08-29, cache-room pass): these are
# mechanical UI, not the chest's own "voice" the way the flavor line
# above is - no font override (project default sans, not PROMPT_FONT's
# Spectral any more), HudPalette.SYSTEM_TEXT for the fill (the same
# muted-system-voice color card.gd's rules text/map_screen.gd's "(here)"
# label/run_hud.gd's room labels already read directly - same "direct-
# read consumer" convention, no local mirroring export). light_outline
# below because SYSTEM_TEXT is a DARK color - the shared dark outline_
# color() would sit invisibly close to it; OverlayStyle.light_color() is
# the already-built answer for exactly this ("dark base text needs a
# light outline instead" - see its own doc, previously only enemy.gd's
# FlavorLabel used it; this is its second consumer, not a new mechanism).
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

# heap-shape: field_heap.gd's own _on_body_entered() - contact only ever
# ARMS the prompt now (2026-08-29, prompt-first interaction pass); it
# does NOT grant anything by itself any more (see _on_take_pressed()
# below for where granting actually happens). No `opened` guard here
# (2026-08-29, chest-states pass - REMOVED, was `not opened`) - `opened`
# is now true for a FORECLOSED chest too (see close_permanently()'s own
# doc), which still wants to respond to contact with its own closed-only
# prompt (see _show_prompt()'s own branch below). Whether THIS signal is
# even connected is the real gate now: a genuinely TAKEN chest disconnects
# body_entered entirely (_on_take_pressed()), so this function is simply
# never called for that case - no in-body check needed to also cover it.
func _on_body_entered(body_node: Node2D) -> void:
	if body_node is Player:
		_player_in_contact = body_node
		# Positioned immediately, not left for _process()'s own next frame
		# (2026-08-29, draw-order fix) - avoids a one-frame flash at
		# whatever stale screen position the camera transform produced the
		# last time this ran (or the Control's own construction-time
		# default, on a chest's very first contact).
		_update_prompt_screen_position()
		set_process(true)
		_show_prompt()

# heap-shape: field_heap.gd's own _on_body_exited().
func _on_body_exited(body_node: Node2D) -> void:
	if body_node == _player_in_contact:
		_player_in_contact = null
		set_process(false) # Freezes the prompt at its last projected screen position, then fades out from there.
		_fade_prompt_to(0.0, prompt_fade_out_sec)

# heap-shape: field_heap.gd's own _show_prompt() (simplified - this
# chest has no exhausted/re-roll state, just one flavor line and two
# buttons that are always both available until taken). Branches on
# _foreclosed (2026-08-29, chest-states pass) - REUSES this exact same
# prompt (anchoring, clearance, fade, world-voice label styling) rather
# than a second prompt path, per that pass's own instruction: only WHICH
# text shows and whether ChoiceRow renders at all change; every other
# mechanism here (offer_prompt, prompt_label, _fade_prompt_to()) is
# unmodified and shared by both states.
func _show_prompt() -> void:
	if _foreclosed:
		prompt_label.text = closed_prompt_text
		choice_row.visible = false
	else:
		prompt_label.text = prompt_text
		choice_row.visible = true
	_fade_prompt_to(1.0, prompt_fade_in_sec)

# heap-shape: field_heap.gd's own _fade_offer_to().
func _fade_prompt_to(target_alpha: float, duration: float) -> void:
	if _offer_tween:
		_offer_tween.kill()
	_offer_tween = create_tween()
	_offer_tween.tween_property(offer_prompt, "modulate:a", target_alpha, duration)

# Leave: dismisses the prompt exactly like walking out of contact does
# (heap-shape: field_heap.gd's own _on_leave_pressed()) - consumes
# nothing, forecloses nothing. Re-arms on the next fresh contact (walk
# off, walk back in) - there is no "already declined" gating, same as
# the heap.
func _on_leave_pressed() -> void:
	_fade_prompt_to(0.0, prompt_fade_out_sec)

# Take: THE single point of commitment for all three reward kinds - see
# claimed's own doc above for why the room-level bookkeeping (opened,
# RoomState.chest_opened, claimed.emit()) happens HERE now instead of on
# contact. For GOLD this is also the entire grant. For CARD, the
# Keeper-pattern card that appears next is no longer a real decision -
# the player already committed by pressing this button; the click on the
# CARD itself is just this same presentation technique's own accept
# gesture, not a second chance to back out (see field_room.gd's own
# _on_chest_card_offered() doc). For WEAPON, opening WeaponPickupWindow
# IS the commitment too - its own internal Take/Leave only decides
# whether to EQUIP the weapon, not whether the room stays spent (see
# field_room.gd's own _on_chest_weapon_offered() doc for the full
# reasoning on this specific edge case).
func _on_take_pressed() -> void:
	if opened:
		return
	opened = true
	RoomState.chest_opened[chest_id] = true
	claimed.emit()
	_fade_prompt_to(0.0, prompt_fade_out_sec)
	set_process(false) # Nothing left to reposition for - draw-order fix's own _process() would otherwise keep re-projecting a permanently-hidden prompt forever.
	if body_entered.is_connected(_on_body_entered):
		body_entered.disconnect(_on_body_entered)
	if body_exited.is_connected(_on_body_exited):
		body_exited.disconnect(_on_body_exited)
	match reward_kind:
		RewardKind.GOLD:
			_grant_gold()
		RewardKind.CARD:
			_offer_card()
		RewardKind.WEAPON:
			_offer_weapon()

# Body is the lower block, Lid the upper one (pivoted at ITS OWN bottom
# edge - lid.position sits at the hinge line, and lid's own polygon
# points are all local to that, which is what makes rotating lid.
# rotation later swing it open around that edge instead of its center).
# lid_gap_px is what makes the seam between Body and Lid read as a line
# at all, despite both sharing one flat fill color - the same "gap
# between same-colored pieces reads as a border" trick the player/enemy
# silhouettes already use between separate limb pieces. Latch straddles
# that seam and stays on Body (not Lid), since a latch/lock band is
# mounted to the box itself, not the lid that swings away from it.
func _build_visual() -> void:
	if belonging_texture != null:
		_build_belonging_sprite()
	else:
		_build_geometry()

# Bare Sprite2D, no modulate/material override - follows the player_visual
# precedent (2026-09-01, belongings-sprite pass) exactly: painted color and
# value are baked into the texture, so this must not participate in
# palette tinting or silhouette_vertical_shade.gdshader the way every
# other silhouette element in this file's own group does.
#
# Bottom-anchored so the texture's own lowest OPAQUE row (not its padded
# canvas edge) lands at local y=0, chest_root's own origin - the same
# convention player_visual.gd's Sprite/offset already establishes,
# necessary here because these plates are trimmed with a few px of
# transparent padding, not flush to the canvas edge. Measured via
# VisualBounds.compute_bottom_slice() (slice_fraction=1.0 - the whole
# image, not a footprint sliver, since there's no raised limb/cape to
# exclude and slicing narrower would only add risk of the pathologically-
# narrow fallback for no benefit) rather than compute()'s plain bounds,
# which would use the texture's own padded rect (see VisualBounds' own
# doc for why that's wrong for anything with transparent margin).
func _build_belonging_sprite() -> void:
	belonging_sprite.texture = belonging_texture
	var effective_scale: float = belonging_scale * belonging_scale_multiplier
	belonging_sprite.scale = Vector2(effective_scale, effective_scale)
	belonging_sprite.position = Vector2.ZERO
	# Measured AFTER scale is set, BEFORE position is - VisualBounds reads
	# the sprite's current transform, so the scan already lands in real
	# on-screen pixels; position (a pure translation) is then free to
	# cancel exactly that without being scaled a second time itself.
	var content_bounds: Rect2 = VisualBounds.compute_bottom_slice(chest_root, 1.0)
	belonging_sprite.position.y = -(content_bounds.position.y + content_bounds.size.y)
	belonging_sprite.position += belonging_offset

func _build_geometry() -> void:
	var half_w := chest_width_px / 2.0
	var half_h := chest_height_px / 2.0
	var lid_bottom_y := -half_h + lid_height_px

	body.polygon = PackedVector2Array([
		Vector2(-half_w, lid_bottom_y + lid_gap_px), Vector2(half_w, lid_bottom_y + lid_gap_px),
		Vector2(half_w, half_h), Vector2(-half_w, half_h),
	])
	body.color = chest_color

	lid.position = Vector2(0, lid_bottom_y)
	lid.polygon = PackedVector2Array([
		Vector2(-half_w, -lid_height_px), Vector2(half_w, -lid_height_px),
		Vector2(half_w, 0), Vector2(-half_w, 0),
	])
	lid.color = chest_color

	var latch_half_w := latch_width_px / 2.0
	var latch_half_h := latch_height_px / 2.0
	latch.position = Vector2(0, lid_bottom_y + lid_gap_px / 2.0)
	latch.polygon = PackedVector2Array([
		Vector2(-latch_half_w, -latch_half_h), Vector2(latch_half_w, -latch_half_h),
		Vector2(latch_half_w, latch_half_h), Vector2(-latch_half_w, latch_half_h),
	])
	latch.color = chest_color

# --- In-field reward (DECIDED, 2026-08-27; interaction model REVISED
# 2026-08-29 - prompt-first pass) ---
#
# The rule: rewards that aren't a decision happen in the world; rewards
# that ARE a decision get a window. Gold is never a decision - a chest's
# gold is a flat randi_range() roll (see min_gold/max_gold above) - so
# it's granted the instant TAKE is pressed (see _on_take_pressed() above),
# with a floating number (_spawn_gold_number()) and the HUD's own tick
# (RunState.gold_changed, already wired into gold_display.gd) as the only
# feedback. No window, no pause, no scene transition. Contact alone no
# longer grants anything - see _on_body_entered()'s own doc above for why
# that moved to an explicit Take press instead. A weapon roll IS a real
# decision (Equip vs. Leave, possibly displacing something already
# equipped) - see weapon_offered above, which field_room.gd turns into a
# WeaponPickupWindow.open_reward() call, the one piece of this that still
# pauses.
#
# RoomState.chest_opened is still set, even though this chest's OWN
# interaction no longer needs a scene reload to survive - it's still
# needed for an UNRELATED reload that still happens: touching a blob in
# this same room still transitions to battle.tscn and back (see field_
# blob.gd), and that return trip reloads field_room.tscn fresh from the
# same RoomState.room_layout, rebuilding THIS chest as a brand new node.
# Without this flag, that fresh chest would render closed and interactive
# again, letting the same chest be opened (and its gold re-granted) twice.
# blob_defeated (see field_blob.gd) is the exact same mechanism for the
# exact same reason, one row over.
#
# GOLD-kind's own reward - called from _on_take_pressed() above, no
# longer takes a body_node param (2026-08-29): the player is no longer
# necessarily still standing in the trigger zone at the moment of a
# button press the way a body_entered callback guaranteed, so this reads
# _player_in_contact directly instead and tolerates it being null (the
# player walked off and the still-fading, still-technically-clickable
# button got pressed anyway - see prompt_fade_out_sec's own doc on why
# that's reachable at all, same as field_heap.gd's identical quirk).
func _grant_gold() -> void:
	var gold_amount := randi_range(min_gold, max_gold)
	RunState.add_gold(gold_amount)
	RunLogger.log_gold_gained(gold_amount, "field chest")
	AudioManager.play_sfx("gold_claimed") # Same "gold changed hands" cue every other gold gain in the game already plays.
	if _player_in_contact != null:
		_spawn_gold_number(gold_amount, _player_in_contact)
	_play_open_flourish()
	# Independent of the gold roll above, never a replacement for it -
	# see weapon_drop_chance's own note.
	if randf() < weapon_drop_chance:
		var weapon := WeaponPool.pick_weighted(weapon_common_weight, weapon_rare_weight)
		# Waits for the floating gold number to finish rising/fading
		# before opening the pickup window (2026-08-28, reward-modal
		# legibility pass) - the window's own ContentColumn is screen-
		# centered, and the gold number rises from directly above the
		# player's head toward that same area, so opening immediately
		# (the old behavior) let the still-animating "+N" overlap the
		# window's own NameLabel. Only this branch waits - a gold-only
		# chest (the common case, see this function's own header)
		# stays exactly as instant as before, since it never reaches
		# this line at all.
		await get_tree().create_timer(GOLD_NUMBER_DURATION_SEC).timeout
		if not is_inside_tree():
			return # The room could in principle have been torn down during the wait (see field_blob.gd's own battle round-trip) - defensive, not expected to trigger given how short this wait is relative to how far the exit sits from any chest.
		weapon_offered.emit(weapon)

# CARD-kind's own reward (2026-08-29, three-chest treasure room) -
# sight-unseen: the card is rolled the instant the chest opens, same
# "no reveal-then-choose-among-several" shape the rare card drop already
# uses, drawn from the SAME pool/weighting the post-battle screen itself
# rolls from (CardPool.load_class_pool()/pick_weighted_card() - see that
# function's own doc). This chest only ROLLS the card and reports it;
# field_room.gd's own _on_chest_card_offered() owns turning it into the
# actual in-field reveal.
func _offer_card() -> void:
	_play_open_flourish()
	var pool := CardPool.load_class_pool()
	var card := CardPool.pick_weighted_card(pool, card_common_weight, card_rare_weight)
	card_offered.emit(card)

# WEAPON-kind's own reward (2026-08-29) - a guaranteed weapon, not a
# chance layered on something else (see weapon_drop_chance's own doc:
# that field is GOLD-kind's own bonus-roll knob, not read here at all).
# Reuses the exact same WeaponPool.pick_weighted() roll and weapon_
# offered signal a GOLD-kind chest's own bonus weapon already uses - the
# SAME field_room.gd handler (_on_chest_weapon_offered()) and the SAME
# WeaponPickupWindow instance present this one too, unchanged.
func _offer_weapon() -> void:
	_play_open_flourish()
	var weapon := WeaponPool.pick_weighted(weapon_common_weight, weapon_rare_weight)
	weapon_offered.emit(weapon)

# Called by field_room.gd on every OTHER chest in the room the instant
# one of them is opened (see TREASURE's own exclusivity rule, claimed's
# own doc above) - a chest that was never touched still needs to visibly
# and functionally stop being one: same dulled colors _set_opened_
# colors() already gives a genuinely-opened chest (placeholder art, not
# a third hand-authored look - no art is being authored this pass), but
# WITHOUT the lid swinging open (it was never actually opened) and
# without the flourish/reward - just permanently inert.
#
# body_entered/body_exited stay CONNECTED now (2026-08-29, chest-states
# pass - REMOVED the old unconditional disconnect of both) - a foreclosed
# chest still arms a prompt on contact, just closed_prompt_text with no
# ChoiceRow instead of the normal one (see _show_prompt()'s own _
# foreclosed branch) - "contact does nothing" is only true for a chest
# THIS player actually took (_on_take_pressed() disconnects body_entered
# entirely for that case, a genuinely different outcome from this one).
# take_button/leave_button DO still get disconnected - there is no choice
# left to make, so nothing should fire even if ChoiceRow's own hidden
# buttons were somehow still reachable.
#
# If the player happens to already be standing in this chest's own
# trigger zone at the exact moment a SIBLING gets taken (the prompt
# already showing THIS chest's normal Take/Leave), refresh it immediately
# rather than leaving stale, non-functional buttons on screen for however
# long remains before they'd naturally walk off - same "don't leave a
# UI state that no longer matches reality" instinct _fade_prompt_to()'s
# own callers already follow elsewhere in this file.
func close_permanently() -> void:
	if opened:
		return
	opened = true
	_foreclosed = true
	_set_opened_colors()
	if take_button.pressed.is_connected(_on_take_pressed):
		take_button.pressed.disconnect(_on_take_pressed)
	if leave_button.pressed.is_connected(_on_leave_pressed):
		leave_button.pressed.disconnect(_on_leave_pressed)
	if _player_in_contact != null:
		_show_prompt()

const GOLD_NUMBER_COLOR := Color(0.85, 0.65, 0.15, 1)
# Matches gold_display.gd's own default coin_color - the number rising
# from the chest and the HUD counter it's about to feed into should read
# as the same "gold" hue, not two unrelated colors for the same fact.
const GOLD_NUMBER_RISE_PX := 60.0
const GOLD_NUMBER_DURATION_SEC := 0.9

# Same floating-number trick as enemy.gd's _spawn_floating_damage() and
# battle.gd's _spawn_player_floating_number() (see either for the fuller
# explanation of how the Tween works) - reused verbatim rather than
# inventing a third copy. Parented onto the PLAYER now (2026-08-27,
# "over the player's head" pass), not this chest - the chest has no
# owned reference to the player anywhere else, but _on_body_entered()'s
# own `body_node` parameter already IS the Player that just triggered
# this (that's the whole reason this function runs at all), so it's
# passed straight through rather than the chest going looking for a
# reference to hold onto. A plain Label parented onto a Node2D (Player,
# a CharacterBody2D) renders in WORLD space via ITS transform, same as
# enemy.gd's version does on Enemy - no CanvasLayer needed. Parenting to
# the player also means the number rises from wherever the player is a
# moment later, not from a fixed world point - matching battle.gd's own
# version, which is likewise anchored to the player, not the thing that
# caused the gain.
func _spawn_gold_number(amount: int, player: Node2D) -> void:
	var number_label := Label.new()
	number_label.text = "+%d" % amount
	number_label.add_theme_font_size_override("font_size", 32)
	number_label.add_theme_color_override("font_color", GOLD_NUMBER_COLOR)
	OverlayStyle.apply_to_label(number_label) # The player always stands on the ground band, not the sky - contrast against ground_base_color isn't guaranteed without this.
	# Measured, not guessed: Player's own origin sits at the character's
	# COLLISION center, but the visual figure (Player/Visual, scale 0.2)
	# extends far above it - Visual's own Sprite sits at scale (8,8) on
	# top of that 0.2, offset.y -97.5, out of a centered 256px-tall frame
	# (see player_visual.tscn/.gd), and Visual's own root sits at local
	# y=17. Combined: (-97.5 - 128) * 8 * 0.2 + 17 = -343.8, the sprite's
	# own top edge in Player-local space - rounded to a clean -350 here.
	# -16 on x is the same "approximate, good enough for a couple of
	# digits" horizontal nudge enemy.gd's own version uses, for the same
	# reason (a fresh Label doesn't know its own width yet).
	number_label.position = Vector2(-16.0, -350.0)
	player.add_child(number_label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(number_label, "position:y", number_label.position.y - GOLD_NUMBER_RISE_PX, GOLD_NUMBER_DURATION_SEC)
	tween.tween_property(number_label, "modulate:a", 0.0, GOLD_NUMBER_DURATION_SEC)
	tween.chain().tween_callback(number_label.queue_free)

func _set_opened_colors() -> void:
	body.color = opened_color
	lid.color = opened_color
	latch.color = opened_color

# Flash bright, scale-punch the whole chest, and swing the lid open, all
# together, then settle into the final opened look (color + the lid left
# rotated open) - both the color state change and the silhouette state
# change happen in the same flourish, not two separate steps.
func _play_open_flourish() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(body, "color", open_flash_color, OPEN_FLASH_DURATION)
	tween.tween_property(lid, "color", open_flash_color, OPEN_FLASH_DURATION)
	tween.tween_property(latch, "color", open_flash_color, OPEN_FLASH_DURATION)
	tween.tween_property(chest_root, "scale", OPEN_SCALE_PUNCH, OPEN_SCALE_DURATION)
	tween.tween_property(lid, "rotation", deg_to_rad(lid_open_angle_deg), lid_open_duration_sec).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().set_parallel(true)
	tween.tween_property(body, "color", opened_color, OPEN_FLASH_DURATION)
	tween.tween_property(lid, "color", opened_color, OPEN_FLASH_DURATION)
	tween.tween_property(latch, "color", opened_color, OPEN_FLASH_DURATION)
	tween.tween_property(chest_root, "scale", Vector2.ONE, OPEN_SCALE_DURATION)
