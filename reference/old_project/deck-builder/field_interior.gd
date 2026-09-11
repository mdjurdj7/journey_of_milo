extends Node2D
class_name FieldInterior
# The reusable shell for an enterable structure's interior - a small
# enclosed room, the interior half of the pattern field_structure.gd's
# own header comment documents in full. A specific interior's own .tscn
# (e.g. pay_house_interior.tscn) uses THIS script as its root and adds
# its own bespoke Content children - mirrors field_room.gd being the
# generic exterior shell with _generate_room_contents()'s spawned
# children as the bespoke part, just simpler: an interior's content is
# hand-authored directly in its own .tscn, not generated from RoomState.
# room_layout, since there's exactly one of each structure and nothing
# to randomize inside it.
#
# Reuses Player/player_visual.tscn/FieldCamera exactly as field_room.tscn
# does (see its own header) - same floor line (RoomState.floor_line_y)
# and full room height (1080) as a standard field room, so neither
# script needs any interior-specific changes.
#
# Deliberately minimal HUD - the player HP bar, gold display, and the
# Deck button/viewer (see field_room.tscn's own HUD for comparison) -
# checking your deck/equipped weapon is still relevant while deciding on
# an interior's own interaction (e.g. the Pay House's blood-or-gold
# choice). ShopWindow/the room labels/Map button still don't make sense
# here - those are about managing/navigating the run outside of any one
# specific interaction. A MapScreen instance IS included, but only
# conditionally (see advance_exit_door below) - it's not part of the HUD,
# it's the travel-commit screen a structure's own optional back exit
# opens, exactly like a field room's real exit does.

const ROOM_HEIGHT := 1080.0
# Matches field_room.gd's own _room_height() (ROOM_VERTICAL_CENTER * 2) -
# an interior keeps the same full vertical span as a standard room (see
# the class doc above), only WIDTH shrinks.
const WALL_THICKNESS := 40.0
# Matches field_room.gd's own WALL_THICKNESS/ROOM_FLOOR_LEFT_X - every
# wall's fixed collision depth from the room's true outer edge.

@export var interior_width: float = 1800.0
# Total wall-to-wall width - smaller than RoomState.standard_room_width
# (2800) on purpose, per this feature's own brief: a structure's interior
# is one small room, not a standard field room's own scale. Widened from
# 1000 (2026-08-27) - NOT yet followed by a reposition of this interior's
# own hand-placed Content/AdvanceExitDoor (see pay_house_interior.tscn's
# own PayWindow/AdvanceExitDoor, both still at their old fixed x, now
# wrong relative to the new width) - that's a deliberate follow-up, not
# an oversight; see this pass's own report for exactly which positions.
@export var door_spawn_margin: float = 100.0
# How far the player spawns in from the door edge (the left wall, where
# ExitDoor also sits - see _ready()) - mirrors field_room.gd/room_state.
# gd's own ENTRANCE_MARGIN.

@export var exit_margin_from_right: float = 200.0
# How far in from the room's RIGHT wall AdvanceExitDoor sits - recomputed
# from interior_width every time _position_bounds() runs (see that
# function below) rather than a frozen absolute x, closing the exact gap
# interior_width's own doc above already flagged ("NOT yet followed by a
# reposition... deliberate follow-up"). ONLY AdvanceExitDoor moves here -
# ExitDoor (the front door back to the exterior field room) deliberately
# stays put, anchored near the LEFT wall at its own fixed x, matching
# where the player always spawns (WALL_THICKNESS + door_spawn_margin)
# regardless of room width. The two doors serve different roles (front
# entry vs. far-side forward exit - see advance_exit_door's own doc) and
# were never meant to share a position; moving ExitDoor to the right
# would strand it on the opposite side from where the player walks in.

@export var wall_color: Color = Color(0.38, 0.37, 0.34, 1)
@export var floor_color: Color = Color(0.44, 0.43, 0.4, 1)
# Same decaying-concrete material language the Sunken Works/industrial
# opening room already established (see field_room.gd's opening_room_
# concrete_wall_color/_floor_color) - every structure interior shares
# this one interior material regardless of which structure it is, the
# same way every standard field room shares one ground treatment.

@onready var player: Player = $Player
@onready var player_visual: PlayerVisual = $Player/Visual
# Scale is applied here at runtime, from RoomState.player_visual_scale
# (see _ready() below) - matches field_room.gd's own identical setup;
# see its own doc for why this replaced a baked scene-file override.
@onready var camera: Camera2D = $Player/Camera2D
@onready var top_wall: FieldWall = $TopWall
@onready var bottom_wall: FieldWall = $BottomWall
@onready var left_wall: FieldWall = $LeftWall
@onready var right_wall: FieldWall = $RightWall
@onready var floor_polygon: Polygon2D = $Floor
@onready var content_root: Node2D = $Content
# Where a specific interior's own bespoke content lives (see the class doc
# above) - reused here only to find whatever Area2D interactables it holds
# (see _setup_click_to_move() below), never to know what any of them
# actually are. Positioned BEFORE Player in this scene's own tree (see
# pay_house_interior.tscn) so its content renders under the player sprite,
# the same layering field_room.tscn's own Content/Player order already
# establishes - this scene's Content used to sit AFTER Player, which
# nothing but click_to_move's own new marker ever needed corrected.
@onready var exit_door: Area2D = $ExitDoor
@onready var advance_exit_door: Area2D = get_node_or_null("AdvanceExitDoor")
@onready var map_screen: MapScreen = get_node_or_null("MapScreen")
# Both optional together - only present if this interior's own .tscn adds
# them (see field_structure.gd's "Optional (e)" note). Lets an interior
# big enough to matter give the player a second way out, on the far side,
# that works exactly like a normal field room's own exit (field_exit.gd's
# real script, not a bespoke one - see _ready() below) rather than merely
# returning to the field room: walking into it advances the run directly,
# right from inside the structure, so the player never has to walk back
# out the front and across the room to reach that room's own exit.
@onready var player_hp_bar: VitalsBar = $UI/HUD/PlayerHPBar
@onready var deck_button: Button = $UI/DeckButton
@onready var deck_viewer: DeckViewer = $DeckViewer

var click_to_move: ClickToMove = null
# Same shared click-to-move/click-to-approach layer field_room.gd's own
# field rooms use (see click_to_move.gd's own header) - this interior had
# none of this at all before (see the "click-to-move doesn't work in the
# Pay House" investigation this fixes), leaving keyboard as the only way
# to move in here even though every other field-style room supported
# mouse parity.

func _ready() -> void:
	_setup_click_to_move()
	_position_bounds()
	_position_floor()
	for wall in [top_wall, bottom_wall, left_wall, right_wall]:
		wall.set_wall_color(wall_color)
	floor_polygon.color = floor_color
	# Initial snap, then a live subscription (2026-09-05, HP-signal pass) -
	# same "_snap() once, then connect()" shape gold_display.gd's own
	# _ready() already establishes, and run_hud.gd/player_battle_visual.gd's
	# own matching subscriptions now use too. REPLACES the old refresh_hp_
	# bar() public hook (removed) - a content script (pay_window.gd) used
	# to have to call back into this shell after changing RunState.player_hp
	# directly; RunState.player_hp_changed now reaches this bar on its own.
	player_hp_bar.refresh_from_run_state()
	RunState.player_hp_changed.connect(_on_player_hp_changed)
	# Always spawns fresh, near the door edge - deliberately does NOT read
	# RoomState.player_position/has_saved_position the way field_room.gd
	# does. Those hold the EXTERIOR field room's own coordinates (set by
	# field_structure.gd right before this scene loaded) - meaningless
	# inside this much smaller interior, and left untouched here so
	# they're still correct when the player exits back to field_room.tscn
	# (see field_structure.gd's own comment on this).
	player.position = Vector2(WALL_THICKNESS + door_spawn_margin, RoomState.floor_line_y)
	# Data-driven now (2026-08-30, spatial framing pass) - see field_room.
	# gd's own identical line for why this replaced pay_house_interior.
	# tscn's own baked Visual scale override.
	player_visual.scale = Vector2(RoomState.player_visual_scale, RoomState.player_visual_scale)
	exit_door.body_entered.connect(_on_exit_body_entered)
	click_to_move.register_interactable(exit_door)
	# Same wiring field_room.gd's own _spawn_exits() uses (door.exit_
	# entered.connect(map_screen.open_map_for_travel)) - this door doesn't
	# need its own handler at all, it already IS a real field_exit.gd
	# instance (see AdvanceExitDoor in pay_house_interior.tscn).
	if advance_exit_door and map_screen:
		advance_exit_door.exit_entered.connect(map_screen.open_map_for_travel)
		click_to_move.register_interactable(advance_exit_door)
	# Registers whatever bespoke interactable(s) this specific interior's
	# own .tscn added under Content (here: just PayWindow) - generically,
	# by type, rather than reaching for PayWindow by name, so a second
	# structure's own interior (see field_structure.gd's "adding a second
	# structure" recipe) gets click-to-approach on its own Content children
	# for free, without field_interior.gd ever needing to know what they
	# are. Doesn't touch how any of them trigger - PayWindow/ExitDoor/
	# AdvanceExitDoor all keep resolving their own interaction entirely
	# through body_entered/exit_entered, exactly as before; a click just
	# walks the player onto them, same as any field_room.gd interactable.
	for child in content_root.get_children():
		if child is Area2D:
			click_to_move.register_interactable(child)
	# Same "set once, never re-read" relationship field_room.gd's own
	# deck_button has with RunState.deck - nothing inside an interior can
	# change deck size (no shop, no card rewards claimed mid-interior), so
	# there's nothing to keep this in sync with later.
	deck_button.text = "Deck (%d)" % RunState.deck.size()
	deck_button.pressed.connect(deck_viewer.open_deck)

# Instantiated before _position_bounds() (which reports the walkable
# bounds this needs - see its own set_bounds() call below) and before the
# interactable-registration loop above, which needs click_to_move to
# already exist. Same instantiate-then-setup shape field_room.gd's own
# _setup_click_to_move() uses.
func _setup_click_to_move() -> void:
	click_to_move = ClickToMove.new()
	add_child(click_to_move)
	click_to_move.setup(player, content_root, RoomState.floor_line_y)

# Same resize-in-place technique field_room.gd's own _position_room_
# bounds() uses (FieldWall.configure()) - only half_length/position
# actually change; every other export (collision_half_thickness/wall_
# thickness_px/void_margin_px) is read back off the node and preserved.
func _position_bounds() -> void:
	var half_width := interior_width / 2.0
	top_wall.configure(half_width, top_wall.collision_half_thickness, top_wall.wall_thickness_px, top_wall.void_margin_px)
	top_wall.position.x = half_width
	bottom_wall.configure(half_width, bottom_wall.collision_half_thickness, bottom_wall.wall_thickness_px, bottom_wall.void_margin_px)
	bottom_wall.position.x = half_width
	right_wall.position.x = interior_width - WALL_THICKNESS / 2.0
	camera.limit_right = interior_width
	if advance_exit_door:
		advance_exit_door.position.x = interior_width - exit_margin_from_right
	# Matches field_room.gd's own ROOM_FLOOR_LEFT_X/_room_floor_right_x()
	# convention exactly - WALL_THICKNESS in from each wall's own outer
	# edge, i.e. each wall's INNER face, not the wider 0/interior_width
	# span _position_floor()'s own decorative floor polygon covers (that
	# polygon reaches under the walls on purpose; the walkable/clickable
	# span does not). Set here, not just once in _ready(), so a future
	# caller that re-runs _position_bounds() after interior_width changes
	# at runtime keeps click_to_move's own bounds in sync for free.
	click_to_move.set_bounds(WALL_THICKNESS, interior_width - WALL_THICKNESS)

func _position_floor() -> void:
	floor_polygon.polygon = PackedVector2Array([
		Vector2(0.0, RoomState.floor_line_y), Vector2(interior_width, RoomState.floor_line_y),
		Vector2(interior_width, ROOM_HEIGHT), Vector2(0.0, ROOM_HEIGHT),
	])

func _on_exit_body_entered(body: Node2D) -> void:
	if body is Player:
		SceneTransition.go_to("res://field_room.tscn")

func _on_player_hp_changed(new_hp: int, new_max_hp: int) -> void:
	player_hp_bar.update_hp(new_hp, new_max_hp)
