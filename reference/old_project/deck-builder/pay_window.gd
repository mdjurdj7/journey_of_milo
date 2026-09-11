extends Area2D
class_name PayWindow
# class_name exists purely so test_pay_house_verify.gd (and any future
# script that needs to reach this instance's own members) can hold a
# properly-typed reference - nothing in production code references this
# by static type (field_interior.gd stays fully generic - see its own
# header), the same way field_chest.gd/field_blob.gd get by without one.
#
# The Pay House's own interactable - see DESIGN.md's Sunken Works
# section ("The Pay House") for the full design. Same "walk in, it
# triggers" convention as every other field trigger (field_chest.gd/
# field_blob.gd), but unlike those this opens a real THREE-WAY DECISION
# rather than resolving anything by itself - so walking in opens the
# modal directly instead of applying an effect on contact.
#
# Lives entirely inside pay_house_interior.tscn as a Content child (see
# field_interior.gd's own header) - not a reusable scene of its own,
# since there's exactly one Pay House. A second structure's own
# interactable would follow this exact shape (its own script, its own
# modal built as its own children) without touching field_interior.gd or
# field_structure.gd at all.

const STRUCTURE_ID := "pay_house"

const BLOOD_COST := 15
const GOLD_COST := 50

const THE_CREDITOR := preload("res://resources/weapons/the_creditor.tres")
const LAST_WAGES := preload("res://resources/weapons/last_wages.tres")

const BODY_TEXT := "The window still opens when you knock. Wire mesh, a ledger gone to rust, a slot that takes two kinds of payment. Nothing moves behind the mesh. \nNothing has to."
const BLOOD_OUTCOME_TEXT := "The dish empties. Something in the slot clicks open."
const GOLD_OUTCOME_TEXT := "The coin drops. Something in the slot clicks open."

const OUTCOME_DISPLAY_SEC := 1.2
# How long the one-line outcome text sits on screen before this hands off
# to reward_screen.tscn - long enough to actually read, short enough that
# claiming the weapon doesn't feel delayed. SceneTransition.go_to()'s own
# 0.3s fade-out runs on top of this, same as field_chest.gd's own
# flourish-then-transition timing.

@export var live_color: Color = Color(0.42, 0.44, 0.47, 1)
@export var resolved_color: Color = Color(0.22, 0.23, 0.25, 1)
# "Resolved" is its own dulled color, not a modulate dim - same "opened
# is a distinct color, not just darker" treatment field_chest.gd's own
# opened_color establishes for a chest.

@export_group("Visual size & float")
@export var visual_size: Vector2 = Vector2(220, 180)
# Frame/Mesh's own polygons (see pay_house_interior.tscn) are fixed point
# arrays, hand-drawn at a 90x90 footprint (REFERENCE_VISUAL_SIZE below) -
# rather than rewriting those points for a new size, this scales the
# WHOLE Visual wrapper node (Frame+Mesh, added 2026-08-28 - see that
# node's own doc) non-uniformly (visual_size / REFERENCE_VISUAL_SIZE), so
# width and height are independently tunable while the frame/mesh
# relationship (mesh inset within frame) stays proportional. Does NOT
# touch CollisionShape2D - that's a sibling of Visual, not a child of
# it, entirely unaffected by this scale (see collision_offset/_size
# below, and float_height's own doc for why the two are deliberately
# decoupled).
@export var float_height: float = 120.0
# How far ABOVE the floor line (PayWindow's own position, which sits
# exactly on it - see pay_house_interior.tscn) the VISUAL's own ground
# edge (Frame's bottom, at local y=0 before scaling) floats - applied as
# Visual.position.y = -float_height, leaving Visual's `scale` (visual_
# size above) to handle sizing independently. CollisionShape2D is a
# sibling, not a child of Visual, so this float never moves it - the
# player's own approach trigger stays exactly where it was, at floor
# level, regardless of how far off the ground the artwork sits.
const REFERENCE_VISUAL_SIZE := Vector2(90.0, 90.0)
# Frame's own original polygon bounding box (see pay_house_interior.tscn -
# -45 to 45 horizontally, -90 to 0 vertically) - purely the baseline
# visual_size's scale factor is computed against, not a size anything
# else reads.

@export_group("Collision")
@export var collision_offset: Vector2 = Vector2(0, -40)
@export var collision_size: Vector2 = Vector2(80, 90)
# The Area2D's own approach-trigger box - a floor-level column, NOT
# resized or repositioned by visual_size/float_height above (see their
# own docs for why those two are collision-independent by design). Was a
# fixed CollisionShape2D.position + a baked RectangleShape2D size directly
# in pay_house_interior.tscn; both are real exports now instead, per this
# pass's own brief that everything here should be feel-tunable, not
# hardcoded, even where this specific pass doesn't change the values.

@onready var frame: Polygon2D = $Visual/Frame
@onready var mesh: Polygon2D = $Visual/Mesh
@onready var visual: Node2D = $Visual
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var closed_label: Label = $ClosedLabel
@onready var modal_layer: CanvasLayer = $ModalLayer
@onready var body_label: Label = $ModalLayer/Panel/MainColumn/BodyLabel
@onready var buttons_column: VBoxContainer = $ModalLayer/Panel/MainColumn/ButtonsColumn
@onready var blood_button: Button = $ModalLayer/Panel/MainColumn/ButtonsColumn/PayBloodButton
@onready var gold_button: Button = $ModalLayer/Panel/MainColumn/ButtonsColumn/PayGoldButton
@onready var leave_button: Button = $ModalLayer/Panel/MainColumn/ButtonsColumn/LeaveButton
@onready var outcome_label: Label = $ModalLayer/Panel/MainColumn/OutcomeLabel

func _ready() -> void:
	_apply_geometry()
	# Same "the overlay's own root stays ALWAYS so its own buttons keep
	# working while the tree is paused" convention reward_screen.gd's
	# CardChoiceOverlay/WeaponRewardOverlay already establish - see their
	# own _ready() note.
	modal_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	modal_layer.visible = false
	body_label.text = BODY_TEXT

	if RoomState.structure_resolved.get(STRUCTURE_ID, false):
		_set_resolved_look()
	else:
		body_entered.connect(_on_body_entered)

	blood_button.pressed.connect(_on_pay_blood_pressed)
	gold_button.pressed.connect(_on_pay_gold_pressed)
	leave_button.pressed.connect(_on_leave_pressed)

# Applies visual_size/float_height (Visual only) and collision_offset/
# _size (CollisionShape2D only) - see each export's own doc for why the
# two are kept structurally independent, not just conventionally so.
# Duplicates the shared RectangleShape2D before resizing it, same
# "duplicate before mutating" rule FieldWall.configure() already follows -
# without it, resizing here would resize every OTHER CollisionShape2D
# still pointing at the same baked pay_house_interior.tscn sub-resource.
func _apply_geometry() -> void:
	visual.scale = visual_size / REFERENCE_VISUAL_SIZE
	visual.position.y = -float_height
	var shape: RectangleShape2D = collision_shape.shape.duplicate()
	shape.size = collision_size
	collision_shape.shape = shape
	collision_shape.position = collision_offset

func _set_resolved_look() -> void:
	frame.color = resolved_color
	mesh.color = resolved_color
	closed_label.visible = true

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		_open_modal()

# --- Modal overlay (DECIDED - see DESIGN.md's own note on this pattern):
# a real decision between three known options, not a special reveal - so
# this uses reward_screen.gd's CardChoiceOverlay shape (dimmed backdrop +
# centered Panel, INSTANT show/hide, paused tree), not the rare-drop
# reveal's fade/crossfade treatment. ---

func _open_modal() -> void:
	body_label.visible = true
	buttons_column.visible = true
	outcome_label.visible = false
	outcome_label.text = ""
	blood_button.text = "Pay in Blood (%d HP)" % _blood_cost()
	gold_button.text = "Pay in Gold (%d g)" % GOLD_COST
	# Re-checked every time the modal opens, not just once - the player
	# could leave, earn/spend gold elsewhere in the interior's absence
	# (they can't, today, but the check costs nothing and matches shop_
	# window.gd's own re-check-on-every-open stance for its Buy buttons),
	# and definitely needs to reflect whatever RunState.gold is THIS time
	# the window is opened, not whatever it was on a previous visit.
	gold_button.disabled = RunState.gold < GOLD_COST
	modal_layer.visible = true
	get_tree().paused = true

func _close_modal() -> void:
	modal_layer.visible = false
	get_tree().paused = false

# Never fatal, never below 1 HP remaining - see this feature's own brief.
# At RunState.player_hp <= 1 this floors to 0, an edge case that will
# essentially never come up given normal HP totals but must not be able
# to kill the player or push HP to 0 through this event.
func _blood_cost() -> int:
	return min(BLOOD_COST, RunState.player_hp - 1)

func _on_pay_blood_pressed() -> void:
	var cost := _blood_cost()
	RunState.lose_hp(cost)
	_resolve(THE_CREDITOR, BLOOD_OUTCOME_TEXT)

func _on_pay_gold_pressed() -> void:
	if RunState.gold < GOLD_COST:
		return # Buy button should already be disabled - defensive, same stance shop_window.gd's own card-buy handler takes.
	RunState.spend_gold(GOLD_COST)
	_resolve(LAST_WAGES, GOLD_OUTCOME_TEXT)

# Shared by both payment paths: commit the resolution to RoomState/
# RunState IMMEDIATELY (see _apply_resolution() below - nothing about
# what actually happened waits on the outcome text being read), THEN
# show the outcome line in place (the modal stays up, just swaps its
# content) for a beat before handing off to the loot window. Splitting
# "what happened" from "how it's shown" this way is also what makes the
# state change independently testable without needing to wait through
# (or trigger) the real scene transition below - see test_pay_house_
# verify.gd's own note on this.
func _resolve(weapon: WeaponData, outcome_text: String) -> void:
	_apply_resolution(weapon)
	body_label.visible = false
	buttons_column.visible = false
	outcome_label.text = outcome_text
	outcome_label.visible = true
	await get_tree().create_timer(OUTCOME_DISPLAY_SEC).timeout
	_close_modal()
	# Hands off to the loot window exactly the way a chest/dev-grant
	# button already does (RoomState.pending_weapon_grant + SceneTransition.
	# go_to("res://reward_screen.tscn")) - no separate weapon-grant UI, the
	# existing hover-preview/swap-decision machinery just works.
	SceneTransition.go_to("res://reward_screen.tscn")

# RoomState.in_field_encounter = true is what makes reward_screen.gd's
# _continue_to_next_battle() route Continue back to field_room.tscn
# instead of battle.tscn - the EXACT same flag field_blob.gd already
# uses to mark "this reward claim originated in the field."
#
# RoomState.pending_non_battle_reward = true is a SEPARATE, narrower
# fix: _continue_to_next_battle() also unconditionally calls RunState.
# advance_to_next_battle() whenever it doesn't think it's looking at a
# chest (_is_chest_reward, driven by pending_chest_gold - see its own
# note: "a chest never fought a battle... no battle_number advance").
# The Pay House didn't fight a battle either, but it isn't a chest and
# deliberately never sets pending_chest_gold (weapon-only reward, no
# gold row) - without this flag, paying here would silently inflate
# RunState.battle_number by one, same bug class _is_chest_reward was
# already built to prevent, just for a source that doesn't look like a
# chest. See reward_screen.gd's own _ready()/_continue_to_next_battle().
func _apply_resolution(weapon: WeaponData) -> void:
	RoomState.structure_resolved[STRUCTURE_ID] = true
	RoomState.pending_weapon_grant = weapon
	RoomState.in_field_encounter = true
	RoomState.pending_non_battle_reward = true
	# Claiming the reward skips the interior entirely on the way back to
	# field_room.tscn (SceneTransition.go_to("res://reward_screen.tscn")
	# below, then reward_screen.gd's own Continue routes straight to
	# field_room.tscn - see its _continue_to_next_battle() note on
	# pending_non_battle_reward), so neither exit_door nor back_exit_door
	# ever fires to set player_position. Overwriting it here with the same
	# bypass point the back door uses (see field_structure.gd's own note
	# on structure_bypass_position) means finishing the event continues
	# the player past the structure, toward the room's exit - not back at
	# the front door they walked in through.
	RoomState.player_position = RoomState.structure_bypass_position

# No cost, no reward, no resolution - closes the modal and leaves
# everything exactly as it was. body_entered stays connected (this
# branch never disconnects it, unlike the resolved case in _ready()), so
# walking back in later opens the exact same choice again.
func _on_leave_pressed() -> void:
	_close_modal()
